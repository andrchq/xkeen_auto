#!/bin/sh

# ---------- Настройки ----------
AVAILABLE_DIR="/opt/etc/xray/outbounds_available"   # где лежат все варианты
ACTIVE_DIR="/opt/etc/xray/configs"                  # где лежит активный outbound
ACTIVE_FILE="${ACTIVE_DIR}/04_outbounds.json"
ACTIVE_TARGET="${ACTIVE_DIR}/04_outbounds.target"
STATE_FILE="/tmp/xkeen_current_country"             # текущее состояние
BACKUP_DIR="/opt/etc/xray/backups"                  # резервные копии
BACKUP_KEEP=10                                      # сколько бэкапов хранить
TCP_TIMEOUT=10                                      # таймаут TCP-проверки
RESTART_WAIT=10                                     # время ожидания после xkeen -restart
LOCK_FILE="/var/run/xkeen_rotate.lock"              # файл блокировки
SYNC_SCRIPT="/opt/root/scripts/xkeen_sync.sh"      # скрипт синхронизации подписки
SUBSCRIPTION_FILE="/opt/root/scripts/.subscription_url"  # файл с URL подписки
CUSTOM_RESTART_CMD="/opt/bin/xkeen -restart"       # команда перезапуска
TG_BOT_TOKEN="7305187909:AAHGkLCVpGIlg70AxWT2auyjOrhoAJkof1U"  # токен бота (общий)
TG_CHAT_ID="-1002517339071"                         # ID группы (общий)
TG_TOPIC_ID=""                                      # ID топика (получите у @prsta_helpbot)
TG_ENABLED=1                                        # 1=включено, 0=выключено
TEST_NOTIFY_ENABLED=0                               # 1=автотест каждые N минут, 0=выключено
TEST_NOTIFY_FILE="/tmp/xkeen_last_test_notify"      # файл с временем последнего теста
TEST_NOTIFY_INTERVAL=300                            # интервал в секундах
FAIL_COUNTERS_FILE="/opt/root/scripts/.fail_counters"  # счётчики падений серверов
FAVORITE_COUNTRY_FILE="/opt/root/scripts/.favorite_country"  # избранная страна
FORCED_COUNTRY_FILE="/opt/root/scripts/.forced_country"  # принудительно выбранная страна
FORCED_COUNTRY_TIMEOUT=300                          # таймаут принудительного выбора (5 минут)
# MAX_PING_MS больше не используется - все серверы доступны независимо от ping
# ---------- Конец настроек ----------

FORCE_ROTATE=0
DRY_RUN=0
SHOW_STATUS=0
TEST_NOTIFY=0
VERBOSE=0
TARGET_COUNTRY=""
SYNC_URL=""
DO_CLEANUP=0
SET_FAVORITE=""
SET_FORCED=""
CLEAR_FAVORITE=0
CLEAR_FORCED=0
LIST_COUNTRIES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --force)
            FORCE_ROTATE=1
            ;;
        --test)
            DRY_RUN=1
            ;;
        --status)
            SHOW_STATUS=1
            ;;
        --test-notify)
            TEST_NOTIFY=1
            ;;
        --verbose)
            VERBOSE=1
            ;;
        --country=*)
            TARGET_COUNTRY="${1#--country=}"
            ;;
        --sync-url=*)
            SYNC_URL="${1#--sync-url=}"
            ;;
        --cleanup)
            DO_CLEANUP=1
            ;;
        --set-favorite=*)
            SET_FAVORITE="${1#--set-favorite=}"
            ;;
        --set-forced=*)
            SET_FORCED="${1#--set-forced=}"
            ;;
        --clear-favorite)
            CLEAR_FAVORITE=1
            ;;
        --clear-forced)
            CLEAR_FORCED=1
            ;;
        --list-countries)
            LIST_COUNTRIES=1
            ;;
        *)
            echo "Использование: $0 [опции]"
            echo ""
            echo "Опции:"
            echo "  --force             Принудительная ротация даже если текущая страна работает"
            echo "  --verbose           Подробный вывод (показывает переходы)"
            printf "  --test              Dry-run режим (без реального переключения)\n"
            echo "  --status            Показать состояние всех нод"
            echo "  --test-notify       Отправить тестовое уведомление в Telegram"
            echo "  --country=XX        Переключиться на конкретную страну"
            echo "  --sync-url=URL      Синхронизировать подписку перед ротацией"
            echo "  --cleanup           Очистка файлов (технические серверы, дубликаты, бэкапы)"
            echo "  --set-favorite=XX   Установить избранную страну"
            echo "  --clear-favorite    Сбросить избранную страну"
            echo "  --set-forced=XX     Принудительно выбрать страну (5 мин таймаут)"
            echo "  --clear-forced      Сбросить принудительный выбор"
            echo "  --list-countries    Показать список доступных стран"
            echo ""
            echo "Примеры:"
            echo "  $0 --status"
            echo "  $0 --set-favorite=GERMANY"
            echo "  $0 --set-forced=USA --force"
            echo "  $0 --cleanup"
            exit 2
            ;;
    esac
    shift
done

log() { logger -t xkeen_rotate "$*"; }

verbose_print() {
    [ "$VERBOSE" -eq 1 ] && echo "$*"
}

# Измерить ping до хоста (возвращает время в ms или 9999 если недоступен)
measure_ping() {
    HOST="$1"
    # Извлекаем только хост без порта
    HOST_ONLY="${HOST%%:*}"
    PING_RESULT=$(ping -c 1 -W 2 "$HOST_ONLY" 2>/dev/null | grep -oE 'time=[0-9.]+' | cut -d= -f2 | head -1)
    if [ -n "$PING_RESULT" ]; then
        # Округляем до целого
        echo "$PING_RESULT" | cut -d. -f1
    else
        echo "9999"
    fi
}

# ============ Счётчик падений серверов ============

# Получить счётчик падений для страны
get_fail_count() {
    CC="$1"
    [ ! -f "$FAIL_COUNTERS_FILE" ] && echo "0" && return
    COUNT=$(grep "^${CC}:" "$FAIL_COUNTERS_FILE" 2>/dev/null | cut -d: -f2)
    [ -z "$COUNT" ] && echo "0" || echo "$COUNT"
}

# Увеличить счётчик падений
increment_fail_count() {
    CC="$1"
    [ -z "$CC" ] && return
    CURRENT=$(get_fail_count "$CC")
    NEW_COUNT=$((CURRENT + 1))
    # Обновляем файл
    if [ -f "$FAIL_COUNTERS_FILE" ]; then
        grep -v "^${CC}:" "$FAIL_COUNTERS_FILE" > "${FAIL_COUNTERS_FILE}.tmp" 2>/dev/null || true
        mv "${FAIL_COUNTERS_FILE}.tmp" "$FAIL_COUNTERS_FILE"
    fi
    echo "${CC}:${NEW_COUNT}" >> "$FAIL_COUNTERS_FILE"
    log "Счётчик падений $CC: $NEW_COUNT"
}

# Сбросить счётчик падений (при успешной работе)
reset_fail_count() {
    CC="$1"
    [ -z "$CC" ] && return
    [ ! -f "$FAIL_COUNTERS_FILE" ] && return
    grep -v "^${CC}:" "$FAIL_COUNTERS_FILE" > "${FAIL_COUNTERS_FILE}.tmp" 2>/dev/null || true
    mv "${FAIL_COUNTERS_FILE}.tmp" "$FAIL_COUNTERS_FILE"
}

# ============ Избранная страна ============

# Получить избранную страну
get_favorite_country() {
    [ -f "$FAVORITE_COUNTRY_FILE" ] && cat "$FAVORITE_COUNTRY_FILE" 2>/dev/null | tr -d '\n\r '
}

# Установить избранную страну
set_favorite_country() {
    CC="$1"
    if [ -z "$CC" ]; then
        rm -f "$FAVORITE_COUNTRY_FILE"
        log "Избранная страна сброшена"
    else
        echo "$CC" > "$FAVORITE_COUNTRY_FILE"
        log "Избранная страна установлена: $CC"
    fi
}

# ============ Принудительный выбор страны ============

# Получить принудительно выбранную страну (если не просрочена)
get_forced_country() {
    [ ! -f "$FORCED_COUNTRY_FILE" ] && return
    # Формат файла: СТРАНА:TIMESTAMP
    LINE=$(cat "$FORCED_COUNTRY_FILE" 2>/dev/null)
    CC="${LINE%%:*}"
    TIMESTAMP="${LINE##*:}"
    [ -z "$CC" ] || [ -z "$TIMESTAMP" ] && return
    # Проверяем таймаут
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - TIMESTAMP))
    if [ "$TIME_DIFF" -lt "$FORCED_COUNTRY_TIMEOUT" ]; then
        echo "$CC"
    fi
}

# Установить принудительную страну
set_forced_country() {
    CC="$1"
    if [ -z "$CC" ]; then
        rm -f "$FORCED_COUNTRY_FILE"
        log "Принудительный выбор страны сброшен"
    else
        TIMESTAMP=$(date +%s)
        echo "${CC}:${TIMESTAMP}" > "$FORCED_COUNTRY_FILE"
        log "Принудительно выбрана страна: $CC"
    fi
}

# Сбросить принудительный выбор
clear_forced_country() {
    rm -f "$FORCED_COUNTRY_FILE"
    log "Принудительный выбор сброшен"
}

# Обновить время принудительного выбора (при успешной работе)
refresh_forced_country() {
    [ ! -f "$FORCED_COUNTRY_FILE" ] && return
    CC=$(get_forced_country)
    [ -n "$CC" ] && set_forced_country "$CC"
}

# ============ Получение кандидатов ============

# Получить список серверов отсортированных по (ping + fail_count*10)
# Все серверы доступны независимо от ping (ограничения по ping убраны)
get_sorted_candidates() {
    TEMP_PING_FILE="/tmp/xkeen_ping_$$"
    : > "$TEMP_PING_FILE"
    
    FAVORITE=$(get_favorite_country)
    
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        [ -z "$CC" ] && continue
        
        if is_technical_server "$CC"; then
            continue
        fi
        
        CAND_TARGET="${AVAILABLE_DIR}/04_outbounds_${CC}.target"
        [ ! -f "$CAND_TARGET" ] && continue
        
        TGT="$(head -n1 "$CAND_TARGET" | tr -d '\r\n')"
        [ -z "$TGT" ] && continue
        
        PING_MS=$(measure_ping "$TGT")
        
        # Для избранной страны - нет ограничений
        if [ "$CC" = "$FAVORITE" ]; then
            # Избранная всегда в начале (сортировочный ключ 0)
            echo "0 $CC $TGT $f $PING_MS" >> "$TEMP_PING_FILE"
            continue
        fi
        
        # Все серверы доступны независимо от ping
        
        # Получаем счётчик падений
        FAIL_COUNT=$(get_fail_count "$CC")
        
        # Вычисляем сортировочный ключ: ping + fail_count * 10
        SORT_KEY=$((PING_MS + FAIL_COUNT * 10))
        
        echo "$SORT_KEY $CC $TGT $f $PING_MS" >> "$TEMP_PING_FILE"
    done
    
    # Сортируем по сортировочному ключу (первый столбец)
    sort -n "$TEMP_PING_FILE"
    rm -f "$TEMP_PING_FILE"
}

is_technical_server() {
    CC="$1"
    
    # Список технических/запрещённых названий (не страны/города)
    TECHNICAL_NAMES="WIFI|WiFi|wifi|PROXY|proxy|TEST|test|LOCAL|local|VPN|vpn|SERVER|server|NODE|node|DIRECT|direct|BLOCK|block|REJECT|reject|AUTO|auto|BEST|best|FAST|fast|LOAD|load|BALANCE|balance"
    
    # Проверяем на технические названия
    if echo "$CC" | grep -qiE "^($TECHNICAL_NAMES)$"; then
        return 0
    fi
    
    # Содержит спецсимволы
    if echo "$CC" | grep -q '%'; then
        return 0
    fi
    
    # Только цифры, нижний регистр или подчёркивания (не название страны)
    if echo "$CC" | grep -qE '^[0-9_a-z]+$'; then
        return 0
    fi
    
    # Содержит точку (вероятно домен)
    if echo "$CC" | grep -q '\.'; then
        return 0
    fi
    
    # Содержит квадратные скобки
    if echo "$CC" | grep -qE '[\[\]]'; then
        return 0
    fi
    
    # Слишком короткое или слишком длинное название
    CC_LEN=$(echo "$CC" | wc -c)
    if [ "$CC_LEN" -lt 3 ] || [ "$CC_LEN" -gt 15 ]; then
        return 0
    fi
    
    # Список допустимых стран/городов (проверка на совпадение)
    VALID_COUNTRIES="USA|US|GERMANY|DE|RUSSIA|RU|FRANCE|FR|NETHERLANDS|NL|UK|GB|JAPAN|JP|SINGAPORE|SG|CANADA|CA|AUSTRALIA|AU|BRAZIL|BR|INDIA|IN|CHINA|CN|KOREA|KR|ITALY|IT|SPAIN|ES|POLAND|PL|SWEDEN|SE|NORWAY|NO|FINLAND|FI|DENMARK|DK|AUSTRIA|AT|SWITZERLAND|CH|BELGIUM|BE|IRELAND|IE|PORTUGAL|PT|GREECE|GR|CZECH|CZ|ROMANIA|RO|HUNGARY|HU|BULGARIA|BG|UKRAINE|UA|TURKEY|TR|ISRAEL|IL|UAE|DUBAI|HONG|HK|TAIWAN|TW|THAILAND|TH|VIETNAM|VN|INDONESIA|ID|MALAYSIA|MY|PHILIPPINES|PH|MEXICO|MX|ARGENTINA|AR|CHILE|CL|COLOMBIA|CO|PERU|PE|SOUTH|AFRICA|ZA|EGYPT|EG|MOROCCO|MA|NIGERIA|NG|KENYA|KE|LITVA|LATVIA|LV|LITHUANIA|LT|ESTONIA|EE|KAZAHSTAN|KAZAKHSTAN|KZ|UZBEKISTAN|UZ|GEORGIA|ARMENIA|AM|AZERBAIJAN|AZ|BELARUS|BY|MOLDOVA|MD|SERBIA|RS|CROATIA|HR|SLOVENIA|SI|SLOVAKIA|SK|CYPRUS|CY|MALTA|MT|LUXEMBOURG|LU|ICELAND|MOSCOW|BERLIN|LONDON|PARIS|AMSTERDAM|TOKYO|SEOUL|BEIJING|SHANGHAI|MUMBAI|SYDNEY|TORONTO|VANCOUVER|MIAMI|DALLAS|CHICAGO|ATLANTA|SEATTLE|DENVER|PHOENIX|BOSTON|WASHINGTON|NEWYORK|LOSANGELES|SANFRANCISCO|FRANKFURT|MUNICH|VIENNA|ZURICH|GENEVA|BRUSSELS|DUBLIN|LISBON|MADRID|BARCELONA|ROME|MILAN|PRAGUE|WARSAW|BUDAPEST|BUCHAREST|SOFIA|HELSINKI|STOCKHOLM|OSLO|COPENHAGEN"
    
    # Если название похоже на страну/город - это НЕ технический сервер
    if echo "$CC" | grep -qiE "^($VALID_COUNTRIES)"; then
    return 1
    fi
    
    # По умолчанию считаем техническим если не в списке стран
    return 0
}

# Полная очистка файлов
do_full_cleanup() {
    echo "=== Очистка файлов ==="
    echo ""
    CLEANED=0
    
    # 1. Удаление технических серверов
    echo "1. Удаление технических серверов..."
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        if is_technical_server "$CC"; then
            echo "   Удаляю: $CC"
            rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.json"
            rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.target"
            CLEANED=$((CLEANED + 1))
        fi
    done
    echo "   Удалено технических серверов: $CLEANED"
    
    # 2. Удаление .json без соответствующих .target
    echo ""
    echo "2. Удаление файлов без пары..."
    ORPHANS=0
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        TARGET_FILE="${AVAILABLE_DIR}/04_outbounds_${CC}.target"
        if [ ! -f "$TARGET_FILE" ]; then
            echo "   Удаляю (нет .target): $CC"
            rm -f "$f"
            ORPHANS=$((ORPHANS + 1))
        fi
    done
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.target; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.target$/\1/p')
        JSON_FILE="${AVAILABLE_DIR}/04_outbounds_${CC}.json"
        if [ ! -f "$JSON_FILE" ]; then
            echo "   Удаляю (нет .json): $CC.target"
            rm -f "$f"
            ORPHANS=$((ORPHANS + 1))
        fi
    done
    echo "   Удалено файлов-сирот: $ORPHANS"
    
    # 3. Очистка старых бэкапов
    echo ""
    echo "3. Очистка старых бэкапов..."
    if [ -d "$BACKUP_DIR" ]; then
        BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.bak" -type f 2>/dev/null | wc -l)
        find "$BACKUP_DIR" -name "*.bak" -type f -mtime +7 -delete 2>/dev/null
        BACKUP_AFTER=$(find "$BACKUP_DIR" -name "*.bak" -type f 2>/dev/null | wc -l)
        echo "   Было бэкапов: $BACKUP_COUNT, осталось: $BACKUP_AFTER"
    else
        echo "   Папка бэкапов не существует"
    fi
    
    # 4. Очистка логов
    echo ""
    echo "4. Очистка старых логов..."
    LOG_DIRS="/opt/root/xkeen_logs"
    if [ -d "$LOG_DIRS" ]; then
        OLD_LOGS=$(find "$LOG_DIRS" -name "*.log" -type f -mtime +7 2>/dev/null | wc -l)
        find "$LOG_DIRS" -name "*.log" -type f -mtime +7 -delete 2>/dev/null
        find "$LOG_DIRS" -name "*.log.gz" -type f -mtime +14 -delete 2>/dev/null
        echo "   Удалено старых логов: $OLD_LOGS"
    else
        echo "   Папка логов не существует"
    fi
    
    echo ""
    echo "=== Очистка завершена ==="
}

send_telegram() {
    [ "$TG_ENABLED" -ne 1 ] && return 0
    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return 0
    STATUS_TITLE="$1"
    MSG_CONTENT="$2"
    [ -z "$STATUS_TITLE" ] && return 0
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    FULL_MSG="🟩 <b>${STATUS_TITLE}</b>

<b>${MSG_CONTENT}</b>

⏰ ${TIMESTAMP}"
    API_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
    MSG_ESCAPED=$(echo "$FULL_MSG" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
    if [ -n "$TG_TOPIC_ID" ] && [ "$TG_TOPIC_ID" != "0" ]; then
        PAYLOAD="{\"chat_id\":\"${TG_CHAT_ID}\",\"message_thread_id\":${TG_TOPIC_ID},\"text\":\"${MSG_ESCAPED}\",\"parse_mode\":\"HTML\"}"
    else
        PAYLOAD="{\"chat_id\":\"${TG_CHAT_ID}\",\"text\":\"${MSG_ESCAPED}\",\"parse_mode\":\"HTML\"}"
    fi
    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" >/dev/null 2>&1
    return 0
}

auto_test_notify() {
    [ "$TEST_NOTIFY_ENABLED" -ne 1 ] && return 0
    [ "$TG_ENABLED" -ne 1 ] && return 0
    CURRENT_TIME=$(date +%s)
    if [ -f "$TEST_NOTIFY_FILE" ]; then
        LAST_TEST_TIME=$(cat "$TEST_NOTIFY_FILE" 2>/dev/null)
        if [ -n "$LAST_TEST_TIME" ] && [ "$LAST_TEST_TIME" -gt 0 ]; then
            TIME_DIFF=$((CURRENT_TIME - LAST_TEST_TIME))
            if [ "$TIME_DIFF" -lt "$TEST_NOTIFY_INTERVAL" ]; then
                return 0
            fi
        fi
    fi
    CURRENT_CC=""
    [ -f "$STATE_FILE" ] && CURRENT_CC="$(cat "$STATE_FILE" 2>/dev/null)"
    CURRENT_NODE="не настроен"
    if [ -f "$ACTIVE_TARGET" ]; then
        CUR_TGT="$(head -n1 "$ACTIVE_TARGET" | tr -d '\r\n')"
        [ -n "$CUR_TGT" ] && CURRENT_NODE="$CUR_TGT"
    fi
    send_telegram "ТЕСТ УВЕДОМЛЕНИЙ" "Проверка системы уведомлений.
Текущая страна: ${CURRENT_CC:-не установлена}
Узел: $CURRENT_NODE

<b>Уведомления работают корректно.</b>"
    echo "$CURRENT_TIME" > "$TEST_NOTIFY_FILE"
    log "Автоматическое тестовое уведомление отправлено"
    return 0
}

health_tcp() {
    HOSTPORT="$1"
    HOST="${HOSTPORT%%:*}"
    PORT="${HOSTPORT##*:}"
    [ -z "$HOST" ] || [ -z "$PORT" ] && return 1
    nc "$HOST" "$PORT" </dev/null >/dev/null 2>&1 &
    NC_PID=$!
    i=0
    while kill -0 "$NC_PID" 2>/dev/null; do
        i=$((i+1))
        [ "$i" -ge "$TCP_TIMEOUT" ] && { kill "$NC_PID" 2>/dev/null; wait "$NC_PID" 2>/dev/null; return 1; }
        sleep 1
    done
    wait "$NC_PID"
    return $?
}

# Множественная проверка доступности (2 из 3 должны пройти)
health_check_multi() {
    HOSTPORT="$1"
    SUCCESS_COUNT=0
    
    for check_num in 1 2 3; do
        if health_tcp "$HOSTPORT"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
        # Ждём 2 секунды между проверками (кроме последней)
        [ "$check_num" -lt 3 ] && sleep 2
    done
    
    # Если 2+ из 3 успешны — сервер доступен
    [ "$SUCCESS_COUNT" -ge 2 ]
}

restart_xkeen() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "[TEST] Перезапуск xkeen пропущен (dry-run)\n"
        return 0
    fi
    eval "$CUSTOM_RESTART_CMD" >/dev/null 2>&1
    sleep "$RESTART_WAIT"
}

cleanup_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        return
    fi
    find "$BACKUP_DIR" -name "04_outbounds.json.*.bak" -type f 2>/dev/null | \
        sort -r | tail -n +$((BACKUP_KEEP + 1)) | xargs rm -f 2>/dev/null
    find "$BACKUP_DIR" -name "04_outbounds.target.*.bak" -type f 2>/dev/null | \
        sort -r | tail -n +$((BACKUP_KEEP + 1)) | xargs rm -f 2>/dev/null
}

show_status() {
    # Показываем избранную и принудительную страну (только если установлены)
    FAVORITE=$(get_favorite_country)
    FORCED=$(get_forced_country)
    
    CURRENT_CC=""
    [ -f "$STATE_FILE" ] && CURRENT_CC="$(cat "$STATE_FILE" 2>/dev/null)"
    
    # Показываем активную страну
    if [ -n "$CURRENT_CC" ] && [ -f "$ACTIVE_TARGET" ]; then
        CUR_TGT="$(head -n1 "$ACTIVE_TARGET" | tr -d '\r\n')"
        if health_tcp "$CUR_TGT"; then
            echo "Активная: $CURRENT_CC - ✓ ДОСТУПНА"
        else
            echo "Активная: $CURRENT_CC - ✗ НЕДОСТУПНА"
        fi
    else
        echo "Активная: не настроена"
    fi
    echo ""
    
    # Показываем избранную и принудительную страну (только если установлены)
    [ -n "$FAVORITE" ] && echo "★ Избранная страна: $FAVORITE"
    [ -n "$FORCED" ] && echo "⚡ Принудительно выбрана: $FORCED"
    [ -n "$FAVORITE" ] || [ -n "$FORCED" ] && echo ""
    
    # Собираем список доступных стран
    TEMP_STATUS="/tmp/xkeen_status_$$"
    : > "$TEMP_STATUS"
    
    CANDIDATES=$(ls "${AVAILABLE_DIR}"/04_outbounds_*.json 2>/dev/null)
    if [ -z "$CANDIDATES" ]; then
        echo "Найдено стран: 0"
        rm -f "$TEMP_STATUS"
        exit 0
    fi
    
    AVAILABLE_COUNT=0
    for cand in $CANDIDATES; do
        [ -f "$cand" ] || continue
        CC=$(basename "$cand" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        [ -z "$CC" ] && continue
        if is_technical_server "$CC"; then
            continue
        fi
        CAND_TARGET="${AVAILABLE_DIR}/04_outbounds_${CC}.target"
        if [ ! -f "$CAND_TARGET" ]; then
            continue
        fi
        TGT="$(head -n1 "$CAND_TARGET" | tr -d '\r\n')"
        if [ -z "$TGT" ]; then
            continue
        fi
        PING_MS=$(measure_ping "$TGT")
        if health_tcp "$TGT"; then
            echo "$PING_MS $CC" >> "$TEMP_STATUS"
            AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
        fi
    done
    
    # Выводим список доступных стран (простой формат)
    echo "Доступные страны:"
    if [ "$AVAILABLE_COUNT" -eq 0 ]; then
        echo "  Нет доступных стран"
    else
        sort -n "$TEMP_STATUS" | while read -r ping cc; do
            MARKS=""
            [ "$cc" = "$FAVORITE" ] && MARKS="${MARKS} ★"
            [ "$cc" = "$FORCED" ] && MARKS="${MARKS} ⚡"
            echo "  - $cc${MARKS}"
        done
    fi
    
    rm -f "$TEMP_STATUS"
    exit 0
}

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        PID=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            log "Скрипт уже запущен (PID: $PID)"
            exit 4
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

trap release_lock EXIT INT TERM

mkdir -p "$AVAILABLE_DIR" "$BACKUP_DIR"

if [ "$TEST_NOTIFY" -eq 1 ]; then
    echo "Отправка тестового уведомления в Telegram..."
    CURRENT_CC=""
    [ -f "$STATE_FILE" ] && CURRENT_CC="$(cat "$STATE_FILE" 2>/dev/null)"
    CURRENT_NODE="не настроен"
    if [ -f "$ACTIVE_TARGET" ]; then
        CUR_TGT="$(head -n1 "$ACTIVE_TARGET" | tr -d '\r\n')"
        [ -n "$CUR_TGT" ] && CURRENT_NODE="$CUR_TGT"
    fi
    send_telegram "ТЕСТ УВЕДОМЛЕНИЙ" "Проверка системы уведомлений xkeen_rotate.
Текущая страна: ${CURRENT_CC:-не установлена}
Узел: $CURRENT_NODE

<b>Уведомления работают корректно.</b>"
    if [ "$TG_ENABLED" -eq 1 ]; then
        echo "✓ Тестовое уведомление отправлено!"
    else
        printf "✗ Telegram уведомления отключены (TG_ENABLED=0)\n"
    fi
    exit 0
fi

if [ -n "$SYNC_URL" ]; then
    if [ ! -f "$SYNC_SCRIPT" ]; then
        log "Ошибка: скрипт синхронизации не найден: $SYNC_SCRIPT"
        echo "Создайте скрипт xkeen_sync.sh или укажите правильный путь в настройках"
        exit 5
    fi
    log "Запуск синхронизации подписки..."
    echo "Синхронизация подписки: $SYNC_URL"
    sh "$SYNC_SCRIPT" "$SYNC_URL"
    SYNC_RESULT=$?
    if [ $SYNC_RESULT -eq 0 ]; then
        log "Синхронизация завершена успешно"
    else
        log "Ошибка синхронизации (код: $SYNC_RESULT)"
    fi
    echo ""
    echo "Синхронизация завершена. Запускаю ротацию..."
    echo ""
fi

[ "$SHOW_STATUS" -eq 1 ] && show_status

# Обработка списка стран
if [ "$LIST_COUNTRIES" -eq 1 ]; then
    echo "=== Доступные страны ==="
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        [ -z "$CC" ] && continue
        is_technical_server "$CC" && continue
        echo "  $CC"
    done
    exit 0
fi

# Обработка установки избранной страны
if [ -n "$SET_FAVORITE" ]; then
    set_favorite_country "$SET_FAVORITE"
    echo "✓ Избранная страна установлена: $SET_FAVORITE"
    exit 0
fi

if [ "$CLEAR_FAVORITE" -eq 1 ]; then
    set_favorite_country ""
    echo "✓ Избранная страна сброшена"
    exit 0
fi

# Обработка принудительного выбора
if [ -n "$SET_FORCED" ]; then
    set_forced_country "$SET_FORCED"
    echo "✓ Принудительно выбрана страна: $SET_FORCED (таймаут: 5 мин)"
    # Также переключаемся на эту страну
    TARGET_COUNTRY="$SET_FORCED"
    FORCE_ROTATE=1
fi

if [ "$CLEAR_FORCED" -eq 1 ]; then
    clear_forced_country
    echo "✓ Принудительный выбор сброшен"
    exit 0
fi

# Обработка очистки
if [ "$DO_CLEANUP" -eq 1 ]; then
    do_full_cleanup
    exit 0
fi

if [ "$TEST_NOTIFY" -ne 1 ] && [ "$SHOW_STATUS" -ne 1 ]; then
    auto_test_notify
fi

acquire_lock

CURRENT_CC=""
[ -f "$STATE_FILE" ] && CURRENT_CC="$(cat "$STATE_FILE" 2>/dev/null)"

# Проверяем избранную и принудительную страну
FAVORITE=$(get_favorite_country)
FORCED=$(get_forced_country)

if [ -f "$ACTIVE_TARGET" ]; then
    CUR_TGT="$(head -n1 "$ACTIVE_TARGET" | tr -d '\r\n')"
    if [ -n "$CUR_TGT" ]; then
        # Используем множественную проверку (2 из 3 должны пройти)
        if health_check_multi "$CUR_TGT"; then
            # Сервер работает — сбрасываем счётчик падений
            reset_fail_count "$CURRENT_CC"
            # Обновляем время принудительного выбора
            [ -n "$FORCED" ] && [ "$CURRENT_CC" = "$FORCED" ] && refresh_forced_country
            
            if [ "$FORCE_ROTATE" -eq 0 ] && [ -z "$TARGET_COUNTRY" ]; then
                log "[$CURRENT_CC] Узел $CUR_TGT доступен — ничего не делаем."
                exit 0
            else
                log "[$CURRENT_CC] Узел $CUR_TGT доступен, но запрошена принудительная ротация."
            fi
        else
            # Увеличиваем счётчик падений
            increment_fail_count "$CURRENT_CC"
            
            # Если это принудительно выбранная страна и она недоступна — сбрасываем
            if [ -n "$FORCED" ] && [ "$CURRENT_CC" = "$FORCED" ]; then
                log "Принудительно выбранная страна $FORCED недоступна — сбрасываем выбор"
                clear_forced_country
                FORCED=""
            fi
            
            log "[$CURRENT_CC] Узел $CUR_TGT недоступен (2+ из 3 проверок не прошли) — пробуем следующую страну."
            send_telegram "УЗЕЛ НЕДОСТУПЕН" "Текущий узел $CURRENT_CC ($CUR_TGT) не отвечает.
Начинаю автоматический поиск альтернативного сервера."
        fi
    else
        log "ACTIVE_TARGET пустой — требуется переключение."
    fi
else
    log "ACTIVE_TARGET не найден — требуется переключение."
fi

# Удаляем флаг успеха перед началом ротации
SUCCESS_FLAG="/tmp/xkeen_rotate_success"
rm -f "$SUCCESS_FLAG"

# Получаем кандидатов отсортированных по ping
verbose_print "Измерение ping до всех серверов..."
SORTED_CANDIDATES=$(get_sorted_candidates)

if [ -z "$SORTED_CANDIDATES" ]; then
    log "Нет доступных файлов в $AVAILABLE_DIR"
    echo "Нет доступных серверов для ротации."
    exit 3
fi

if [ "$VERBOSE" -eq 1 ]; then
    echo ""
    echo "Серверы отсортированы по надёжности (ping + падения*10):"
    echo "$SORTED_CANDIDATES" | while read -r sort_key cc tgt file real_ping; do
        FAIL_COUNT=$(get_fail_count "$cc")
        if [ "$real_ping" = "9999" ] || [ -z "$real_ping" ]; then
            echo "  $cc - недоступен [падений: $FAIL_COUNT]"
        else
            echo "  $cc - ${real_ping}ms [падений: $FAIL_COUNT]"
        fi
    done
    echo ""
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf "[TEST] Резервное копирование пропущено (dry-run)\n"
else
    [ -f "$ACTIVE_FILE" ] && cp -a "$ACTIVE_FILE" "$BACKUP_DIR/04_outbounds.json.$(date +%s).bak" 2>/dev/null
    [ -f "$ACTIVE_TARGET" ] && cp -a "$ACTIVE_TARGET" "$BACKUP_DIR/04_outbounds.target.$(date +%s).bak" 2>/dev/null
    cleanup_backups
fi

# Проходим по отсортированным кандидатам (формат: SORT_KEY CC TGT FILE REAL_PING)
echo "$SORTED_CANDIDATES" | while read -r SORT_KEY CC NEW_TGT cand REAL_PING; do
    [ -z "$CC" ] && continue

    if [ -n "$TARGET_COUNTRY" ]; then
        [ "$CC" != "$TARGET_COUNTRY" ] && continue
    fi

    if [ "$CC" = "$CURRENT_CC" ] && [ "$FORCE_ROTATE" -eq 0 ] && [ -z "$TARGET_COUNTRY" ]; then
        continue
    fi

    CAND_TARGET="${AVAILABLE_DIR}/04_outbounds_${CC}.target"

    # Используем реальный ping для отображения
    PING_MS="${REAL_PING:-$SORT_KEY}"

    verbose_print "Проверяем $CC (ping: ${PING_MS}ms)..."
    log "Проверяем $CC ($NEW_TGT)..."
    
    # Используем множественную проверку (2 из 3 должны пройти)
    if ! health_check_multi "$NEW_TGT"; then
        # Увеличиваем счётчик падений для этого кандидата
        increment_fail_count "$CC"
        verbose_print "  ✗ $CC недоступен (2+ из 3 проверок не прошли)"
        log "[$CC] Узел $NEW_TGT недоступен — пропускаем."
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf "[TEST] Переключение на $CC\n"
        exit 0
    fi
    
    # Выводим информацию о переходе (без IP/доменов)
    if [ -n "$CURRENT_CC" ] && [ "$CURRENT_CC" != "$CC" ]; then
        echo ""
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║                    СМЕНА СЕРВЕРА                           ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo "      С:  $CURRENT_CC"                                          
        echo "      На: $CC [ping: ${PING_MS}ms]"                             
        echo ""
        echo ""
    else
        echo ""
        echo "Активация сервера: $CC [ping: ${PING_MS}ms]"
        echo ""
    fi

        mv -f "$ACTIVE_FILE" "${AVAILABLE_DIR}/04_outbounds_${CURRENT_CC}.json" 2>/dev/null
        mv -f "$ACTIVE_TARGET" "${AVAILABLE_DIR}/04_outbounds_${CURRENT_CC}.target" 2>/dev/null
        mv -f "$cand" "$ACTIVE_FILE" 2>/dev/null
        mv -f "$CAND_TARGET" "$ACTIVE_TARGET" 2>/dev/null

    log "Активируем $CC и перезапускаем xkeen..."
    restart_xkeen

    # Используем множественную проверку после перезапуска (2 из 3 должны пройти)
    if health_check_multi "$NEW_TGT"; then
        echo "$CC" > "$STATE_FILE"
        # Сбрасываем счётчик падений при успешной активации
        reset_fail_count "$CC"
        log "Успешно активирована узел $NEW_TGT."
        echo "✓ Сервер $CC успешно активирован!"
        if [ -n "$CURRENT_CC" ] && [ "$CURRENT_CC" != "$CC" ]; then
            send_telegram "СМЕНА СЕРВЕРА" "Выполнено переключение с $CURRENT_CC ($CUR_TGT) на $CC ($NEW_TGT).
Новый сервер активирован и успешно прошёл проверку доступности."
        fi
        # Создаём флаг успеха для выхода из основного скрипта
        touch "$SUCCESS_FLAG"
        exit 0
    else
        # Увеличиваем счётчик падений при неудаче после перезапуска
        increment_fail_count "$CC"
        log "[$CC] После рестарта страна $CC всё ещё недоступна — пробуем следующего кандидата."
        verbose_print "  ⚠ $CC не работает после перезапуска, пробуем следующий..."
    fi
done

# Проверяем флаг успеха - если он есть, сервер был успешно переключен в подоболочке
if [ -f "$SUCCESS_FLAG" ]; then
    rm -f "$SUCCESS_FLAG"
    exit 0
fi

if [ -n "$TARGET_COUNTRY" ]; then
    log "Страна $TARGET_COUNTRY не найдена или недоступна."
else
    log "Нет доступных стран с рабочими нодами. Оставляем текущую конфигурацию."
    send_telegram "КРИТИЧНО - ВСЕ СЕРВЕРЫ НЕДОСТУПНЫ" "Не найдено ни одного работающего сервера из доступных вариантов!
Текущая конфигурация $CURRENT_CC сохранена. Требуется срочная проверка серверов вручную."
fi
rm -f "$SUCCESS_FLAG"
exit 1
