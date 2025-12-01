#!/bin/sh

# ---------- Настройки ----------
SUBSCRIPTION_URL=""                                 # URL подписки (передаётся через аргумент)
AVAILABLE_DIR="/opt/etc/xray/outbounds_available"  # куда сохранять outbound файлы
STATE_FILE="/tmp/xkeen_current_country"             # текущее состояние
SUBSCRIPTION_FILE="/opt/root/scripts/.subscription_url"  # файл с сохранённым URL
ACTIVE_FILE="/opt/etc/xray/configs/04_outbounds.json"    # активная конфигурация
ACTIVE_TARGET="/opt/etc/xray/configs/04_outbounds.target" # активный target
# ---------- Конец настроек ----------

log() { 
    echo "[xkeen_sync] $*"
    logger -t xkeen_sync "$*"
}

parse_vless() {
    VLESS_URL="$1"
    UUID=$(echo "$VLESS_URL" | sed -n 's|^vless://\([^@]*\)@.*|\1|p')
    HOST_PORT=$(echo "$VLESS_URL" | sed -n 's|^vless://[^@]*@\([^?]*\)?.*|\1|p')
    HOST=$(echo "$HOST_PORT" | cut -d: -f1)
    PORT=$(echo "$HOST_PORT" | cut -d: -f2)
    NAME_RAW=$(echo "$VLESS_URL" | sed -n 's|.*#\(.*\)$|\1|p')
    if echo "$NAME_RAW" | grep -qE '^%5B'; then
        log "Пропускаю технический сервер: $NAME_RAW (содержит квадратные скобки)"
        return 0
    fi
    if echo "$NAME_RAW" | grep -q '%E2%9C%85'; then
        log "Пропускаю технический сервер: $NAME_RAW (содержит ✅)"
        return 0
    fi
    NAME=$(echo "$NAME_RAW" | sed 's/%20/ /g; s/%7C/|/g; s/%F0%9F%87/%F0%9F%87/g')
    if echo "$NAME" | grep -q '\[✅\]'; then
        log "Пропускаю технический сервер: $NAME"
        return 0
    fi
    if echo "$NAME" | grep -qE '\[[a-z0-9_\.]+\]'; then
        log "Пропускаю служебный сервер: $NAME"
        return 0
    fi
    COUNTRY_CODE=$(echo "$NAME" | grep -o '[A-Z]\{3,\}' | head -1)
    PARAMS=$(echo "$VLESS_URL" | sed -n 's|^[^?]*?\([^#]*\).*|\1|p')
    SECURITY=$(echo "$PARAMS" | grep -o 'security=[^&]*' | cut -d= -f2)
    FLOW=$(echo "$PARAMS" | grep -o 'flow=[^&]*' | cut -d= -f2)
    SNI=$(echo "$PARAMS" | grep -o 'sni=[^&]*' | cut -d= -f2)
    FP=$(echo "$PARAMS" | grep -o 'fp=[^&]*' | cut -d= -f2)
    PBK=$(echo "$PARAMS" | grep -o 'pbk=[^&]*' | cut -d= -f2)
    SID=$(echo "$PARAMS" | grep -o 'sid=[^&]*' | cut -d= -f2)
    SPIDERX=$(echo "$PARAMS" | grep -o 'spx=[^&]*' | cut -d= -f2 | sed 's/%2F/\//g')
    [ -z "$SPIDERX" ] && SPIDERX="/"
    if [ -z "$COUNTRY_CODE" ]; then
        COUNTRY_CODE=$(echo "$NAME" | tr -d ' |🇱🇹🇰🇿🇩🇪🇺🇸🦅⚡💪🏼' | head -c 5 | tr '[:lower:]' '[:upper:]')
    fi
    generate_outbound_vless "$COUNTRY_CODE" "$UUID" "$HOST" "$PORT" "$SECURITY" "$FLOW" "$SNI" "$FP" "$PBK" "$SID" "$SPIDERX"
}

generate_outbound_vless() {
    CC="$1"
    UUID="$2"
    HOST="$3"
    PORT="$4"
    SECURITY="$5"
    FLOW="$6"
    SNI="$7"
    FP="$8"
    PBK="$9"
    shift 9
    SID="$1"
    SPIDERX="$2"
    
    # По умолчанию spiderX = /
    [ -z "$SPIDERX" ] && SPIDERX="/"
    
    OUT_FILE="${AVAILABLE_DIR}/04_outbounds_${CC}.json"
    TARGET_FILE="${AVAILABLE_DIR}/04_outbounds_${CC}.target"
    log "Создаём конфигурацию для $CC ($HOST:$PORT)..."
    cat > "$OUT_FILE" << EOF
{
    "outbounds": [
        {
            "tag": "vless-reality",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "$HOST",
                        "port": $PORT,
                        "users": [
                            {
                                "id": "$UUID",
                                "flow": "$FLOW",
                                "encryption": "none",
                                "level": 0
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "$SECURITY",
                "realitySettings": {
                    "publicKey": "$PBK",
                    "fingerprint": "$FP",
                    "serverName": "$SNI",
                    "shortId": "$SID",
                    "spiderX": "$SPIDERX"
                }
            }
        },
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {
                "response": {
                    "type": "http"
                }
            }
        }
    ]
}
EOF
    echo "$HOST:$PORT" > "$TARGET_FILE"
    log "✓ Создан $OUT_FILE"
}

is_technical_server() {
    CC="$1"
    
    # Список технических/запрещённых названий (не страны/города)
    TECHNICAL_NAMES="WIFI|WiFi|wifi|PROXY|proxy|TEST|test|LOCAL|local|VPN|vpn|SERVER|server|NODE|node|DIRECT|direct|BLOCK|block|REJECT|reject|AUTO|auto|BEST|best|FAST|fast|LOAD|load|BALANCE|balance"
    
    # Проверяем на технические названия
    echo "$CC" | grep -qiE "^($TECHNICAL_NAMES)$" && return 0
    
    # Содержит спецсимволы
    echo "$CC" | grep -q '%' && return 0
    
    # Только цифры, нижний регистр или подчёркивания
    echo "$CC" | grep -qE '^[0-9_a-z]+$' && return 0
    
    # Содержит точку
    echo "$CC" | grep -q '\.' && return 0
    
    # Содержит квадратные скобки
    echo "$CC" | grep -qE '[\[\]]' && return 0
    
    # Слишком короткое или слишком длинное
    CC_LEN=$(echo "$CC" | wc -c)
    [ "$CC_LEN" -lt 3 ] || [ "$CC_LEN" -gt 15 ] && return 0
    
    # Список допустимых стран/городов
    VALID_COUNTRIES="USA|US|GERMANY|DE|RUSSIA|RU|FRANCE|FR|NETHERLANDS|NL|UK|GB|JAPAN|JP|SINGAPORE|SG|CANADA|CA|AUSTRALIA|AU|BRAZIL|BR|INDIA|IN|CHINA|CN|KOREA|KR|ITALY|IT|SPAIN|ES|POLAND|PL|SWEDEN|SE|NORWAY|NO|FINLAND|FI|DENMARK|DK|AUSTRIA|AT|SWITZERLAND|CH|BELGIUM|BE|IRELAND|IE|PORTUGAL|PT|GREECE|GR|CZECH|CZ|ROMANIA|RO|HUNGARY|HU|BULGARIA|BG|UKRAINE|UA|TURKEY|TR|ISRAEL|IL|UAE|DUBAI|HONG|HK|TAIWAN|TW|THAILAND|TH|VIETNAM|VN|INDONESIA|ID|MALAYSIA|MY|PHILIPPINES|PH|MEXICO|MX|ARGENTINA|AR|CHILE|CL|COLOMBIA|CO|PERU|PE|SOUTH|AFRICA|ZA|EGYPT|EG|MOROCCO|MA|NIGERIA|NG|KENYA|KE|LITVA|LATVIA|LV|LITHUANIA|LT|ESTONIA|EE|KAZAHSTAN|KAZAKHSTAN|KZ|UZBEKISTAN|UZ|GEORGIA|ARMENIA|AM|AZERBAIJAN|AZ|BELARUS|BY|MOLDOVA|MD|SERBIA|RS|CROATIA|HR|SLOVENIA|SI|SLOVAKIA|SK|CYPRUS|CY|MALTA|MT|LUXEMBOURG|LU|ICELAND|MOSCOW|BERLIN|LONDON|PARIS|AMSTERDAM|TOKYO|SEOUL|BEIJING|SHANGHAI|MUMBAI|SYDNEY|TORONTO|VANCOUVER|MIAMI|DALLAS|CHICAGO|ATLANTA|SEATTLE|DENVER|PHOENIX|BOSTON|WASHINGTON|NEWYORK|LOSANGELES|SANFRANCISCO|FRANKFURT|MUNICH|VIENNA|ZURICH|GENEVA|BRUSSELS|DUBLIN|LISBON|MADRID|BARCELONA|ROME|MILAN|PRAGUE|WARSAW|BUDAPEST|BUCHAREST|SOFIA|HELSINKI|STOCKHOLM|OSLO|COPENHAGEN"
    
    # Если похоже на страну/город - НЕ технический
    echo "$CC" | grep -qiE "^($VALID_COUNTRIES)" && return 1
    
    # По умолчанию - технический
    return 0
}

cleanup_before_sync() {
    log "Очистка технических серверов перед синхронизацией..."
    CLEANED=0
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        if is_technical_server "$CC"; then
            rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.json"
            rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.target"
            CLEANED=$((CLEANED + 1))
        fi
    done
    [ "$CLEANED" -gt 0 ] && log "Удалено технических серверов: $CLEANED"
}

sync_subscription() {
    SUBSCRIPTION_URL="$1"
    if [ -z "$SUBSCRIPTION_URL" ]; then
        echo "Ошибка: не указан URL подписки"
        echo "Использование: $0 <URL_подписки>"
        exit 1
    fi
    log "Загрузка подписки: $SUBSCRIPTION_URL"
    mkdir -p "$AVAILABLE_DIR"
    
    # Удаление всех старых файлов синхронизации перед загрузкой новых
    log "Удаление старых файлов синхронизации..."
    OLD_FILES_COUNT=0
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.json"
        rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.target"
        OLD_FILES_COUNT=$((OLD_FILES_COUNT + 1))
    done
    [ "$OLD_FILES_COUNT" -gt 0 ] && log "Удалено старых файлов: $OLD_FILES_COUNT"
    
    # Очистка технических серверов (на случай если что-то осталось)
    cleanup_before_sync
    SUBSCRIPTION_DATA=$(curl -sL "$SUBSCRIPTION_URL" | base64 -d 2>/dev/null)
    if [ -z "$SUBSCRIPTION_DATA" ]; then
        log "Ошибка: не удалось загрузить или декодировать подписку"
        exit 2
    fi
    log "Подписка загружена, обрабатываю серверы..."
    COUNT=0
    echo "$SUBSCRIPTION_DATA" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
            vless://*)
                parse_vless "$line"
                COUNT=$((COUNT + 1))
                ;;
            vmess://*)
                log "Пропускаю vmess (пока не поддерживается): $line"
                ;;
            trojan://*)
                log "Пропускаю trojan (пока не поддерживается): $line"
                ;;
            *)
                log "Неизвестный протокол, пропускаю: $line"
                ;;
        esac
    done
    FINAL_COUNT=$(ls "${AVAILABLE_DIR}"/04_outbounds_*.json 2>/dev/null | wc -l)
    log "Синхронизация завершена. Создано конфигураций: $FINAL_COUNT"
    if [ "$FINAL_COUNT" -gt 0 ]; then
        log "Доступные страны:"
        for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
            [ -f "$f" ] || continue
            CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
            TARGET=$(cat "${AVAILABLE_DIR}/04_outbounds_${CC}.target" 2>/dev/null)
            log "  - $CC ($TARGET)"
        done
    else
        log "Внимание: не создано ни одной конфигурации! Проверьте подписку."
    fi
}

# Определяем URL подписки
if [ -n "$1" ]; then
    # URL передан как аргумент
    SYNC_URL="$1"
elif [ -f "$SUBSCRIPTION_FILE" ]; then
    # Читаем из сохранённого файла
    SYNC_URL=$(cat "$SUBSCRIPTION_FILE" 2>/dev/null | tr -d '\n\r')
    if [ -n "$SYNC_URL" ]; then
        log "Используется сохранённый URL подписки"
    fi
fi

if [ -z "$SYNC_URL" ]; then
    echo "Скрипт синхронизации подписок xkeen"
    echo ""
    echo "Использование:"
    echo "  $0 <URL_подписки>    - синхронизация с указанным URL"
    echo "  $0                   - синхронизация с сохранённым URL"
    echo ""
    echo "URL подписки можно сохранить через команду: prosto seturl <URL>"
    echo ""
    echo "Скрипт загрузит подписку, декодирует и создаст outbound файлы"
    echo "в директории: $AVAILABLE_DIR"
    exit 0
fi

sync_subscription "$SYNC_URL"
