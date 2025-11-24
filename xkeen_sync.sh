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
    if [ -z "$COUNTRY_CODE" ]; then
        COUNTRY_CODE=$(echo "$NAME" | tr -d ' |🇱🇹🇰🇿🇩🇪🇺🇸🦅⚡💪🏼' | head -c 5 | tr '[:lower:]' '[:upper:]')
    fi
    generate_outbound_vless "$COUNTRY_CODE" "$UUID" "$HOST" "$PORT" "$SECURITY" "$FLOW" "$SNI" "$FP" "$PBK" "$SID"
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
    shift; SID="$9"
    OUT_FILE="${AVAILABLE_DIR}/04_outbounds_${CC}.json"
    TARGET_FILE="${AVAILABLE_DIR}/04_outbounds_${CC}.target"
    log "Создаём конфигурацию для $CC ($HOST:$PORT)..."
    cat > "$OUT_FILE" << EOF
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$HOST",
            "port": $PORT,
            "users": [
              {
                "id": "$UUID",
                "encryption": "none",
                "flow": "$FLOW"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "$SECURITY",
        "realitySettings": {
          "show": false,
          "fingerprint": "$FP",
          "serverName": "$SNI",
          "publicKey": "$PBK",
          "shortId": "$SID",
          "spiderX": ""
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
    echo "$HOST:$PORT" > "$TARGET_FILE"
    log "✓ Создан $OUT_FILE"
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
    
    # Очистка перед синхронизацией
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
