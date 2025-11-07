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
CUSTOM_RESTART_CMD="/opt/bin/xkeen -restart"       # команда перезапуска
TG_BOT_TOKEN="7305187909:AAHGkLCVpGIlg70AxWT2auyjOrhoAJkof1U"  # токен бота (общий)
TG_CHAT_ID="-1002517339071"                         # ID группы (общий)
TG_TOPIC_ID=""                                      # ID топика (получите у @prsta_helpbot)
TG_ENABLED=1                                        # 1=включено, 0=выключено
TEST_NOTIFY_ENABLED=0                               # 1=автотест каждые N минут, 0=выключено
TEST_NOTIFY_FILE="/tmp/xkeen_last_test_notify"      # файл с временем последнего теста
TEST_NOTIFY_INTERVAL=300                            # интервал в секундах
# ---------- Конец настроек ----------

FORCE_ROTATE=0
DRY_RUN=0
SHOW_STATUS=0
TEST_NOTIFY=0
TARGET_COUNTRY=""
SYNC_URL=""

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
        --country=*)
            TARGET_COUNTRY="${1#--country=}"
            ;;
        --sync-url=*)
            SYNC_URL="${1#--sync-url=}"
            ;;
        --cleanup)
            echo "Очистка технических серверов..."
            CLEANED=0
            for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
                [ -f "$f" ] || continue
                CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
                if is_technical_server "$CC"; then
                    echo "Удаляю: $CC"
                    rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.json"
                    rm -f "${AVAILABLE_DIR}/04_outbounds_${CC}.target"
                    CLEANED=$((CLEANED + 1))
                fi
            done
            echo "Удалено технических серверов: $CLEANED"
            exit 0
            ;;
        *)
            echo "Использование: $0 [опции]"
            echo ""
            echo "Опции:"
            echo "  --force           Принудительная ротация даже если текущая страна работает"
            echo "  --test            Dry-run режим (без реального переключения)"
            echo "  --status          Показать состояние всех нод"
            echo "  --test-notify     Отправить тестовое уведомление в Telegram"
            echo "  --country=XX      Переключиться на конкретную страну"
            echo "  --sync-url=URL    Синхронизировать подписку перед ротацией"
            echo "  --cleanup         Удалить технические серверы из доступных"
            echo ""
            echo "Примеры:"
            echo "  $0 --status"
            echo "  $0 --sync-url=https://example.com/subscription"
            echo "  $0 --country=US --force"
            echo "  $0 --cleanup"
            exit 2
            ;;
    esac
    shift
done

log() { logger -t xkeen_rotate "$*"; }

is_technical_server() {
    CC="$1"
    if echo "$CC" | grep -q '%'; then
        return 0
    fi
    if echo "$CC" | grep -qE '^[0-9_a-z]+$'; then
        return 0
    fi
    if echo "$CC" | grep -q '\.'; then
        return 0
    fi
    if echo "$CC" | grep -qE '[\[\]]'; then
        return 0
    fi
    CC_LEN=$(echo "$CC" | wc -c)
    if [ "$CC_LEN" -lt 3 ] || [ "$CC_LEN" -gt 10 ]; then
        return 0
    fi
    return 1
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
Страна: $CURRENT_NODE

<b>Уведомления работают корректно.</b>
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

restart_xkeen() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[TEST] Перезапуск xkeen пропущен (dry-run)"
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
    echo "=== Статус нод xkeen ==="
    echo ""
    CURRENT_CC=""
    [ -f "$STATE_FILE" ] && CURRENT_CC="$(cat "$STATE_FILE" 2>/dev/null)"
    if [ -f "$ACTIVE_TARGET" ]; then
        CUR_TGT="$(head -n1 "$ACTIVE_TARGET" | tr -d '\r\n')"
        echo -n "Активная: $CURRENT_CC ($CUR_TGT) - "
        if health_tcp "$CUR_TGT"; then
            echo "✓ ДОСТУПНА"
        else
            echo "✗ НЕДОСТУПНА"
        fi
    else
        echo "Активная: не настроена"
    fi
    echo ""
    echo "Доступные ноды:"
    CANDIDATES=$(ls "${AVAILABLE_DIR}"/04_outbounds_*.json 2>/dev/null)
    if [ -z "$CANDIDATES" ]; then
        echo "  Нет доступных конфигураций"
        return
    fi
    for cand in $CANDIDATES; do
        [ -f "$cand" ] || continue
        CC=$(basename "$cand" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        [ -z "$CC" ] && continue
        if is_technical_server "$CC"; then
            continue
        fi
        CAND_TARGET="${AVAILABLE_DIR}/04_outbounds_${CC}.target"
        if [ ! -f "$CAND_TARGET" ]; then
            echo "  $CC: нет .target файла"
            continue
        fi
        TGT="$(head -n1 "$CAND_TARGET" | tr -d '\r\n')"
        if [ -z "$TGT" ]; then
            echo "  $CC: .target пуст"
            continue
        fi
        echo -n "  $CC ($TGT) - "
        if health_tcp "$TGT"; then
            echo "✓ доступна"
        else
            echo "✗ недоступна"
        fi
    done
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
Страна: $CURRENT_NODE

<b>Уведомления работают корректно.</b>
    if [ "$TG_ENABLED" -eq 1 ]; then
        echo "✓ Тестовое уведомление отправлено в топик $TG_TOPIC_ID группы $TG_CHAT_ID"
    else
        echo "✗ Telegram уведомления отключены (TG_ENABLED=0)"
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

if [ "$TEST_NOTIFY" -ne 1 ] && [ "$SHOW_STATUS" -ne 1 ]; then
    auto_test_notify
fi

acquire_lock

CURRENT_CC=""
[ -f "$STATE_FILE" ] && CURRENT_CC="$(cat "$STATE_FILE" 2>/dev/null)"

if [ -f "$ACTIVE_TARGET" ]; then
    CUR_TGT="$(head -n1 "$ACTIVE_TARGET" | tr -d '\r\n')"
    if [ -n "$CUR_TGT" ]; then
        if health_tcp "$CUR_TGT"; then
            if [ "$FORCE_ROTATE" -eq 0 ] && [ -z "$TARGET_COUNTRY" ]; then
                log "[$CURRENT_CC] Страна $CURRENT_CC доступна — ничего не делаем."
                exit 0
            else
                log "[$CURRENT_CC] Страна $CURRENT_CC доступна, но запрошена принудительная ротация."
            fi
        else
            log "[$CURRENT_CC] Страна $CURRENT_CC недоступна — пробуем следующую страну."
            send_telegram "СТРАНА НЕДОСТУПНА" "Страна $CURRENT_CC недоступна.
Начинаю автоматический поиск альтернативного сервера."
        fi
    else
        log "ACTIVE_TARGET пустой — требуется переключение."
    fi
else
    log "ACTIVE_TARGET не найден — требуется переключение."
fi

CANDIDATES=$(ls "${AVAILABLE_DIR}"/04_outbounds_*.json 2>/dev/null)
[ -z "$CANDIDATES" ] && { log "Нет доступных файлов в $AVAILABLE_DIR"; exit 3; }

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[TEST] Резервное копирование пропущено (dry-run)"
else
    [ -f "$ACTIVE_FILE" ] && cp -a "$ACTIVE_FILE" "$BACKUP_DIR/04_outbounds.json.$(date +%s).bak" 2>/dev/null
    [ -f "$ACTIVE_TARGET" ] && cp -a "$ACTIVE_TARGET" "$BACKUP_DIR/04_outbounds.target.$(date +%s).bak" 2>/dev/null
    cleanup_backups
fi

cc_from_filename() {
    basename "$1" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p'
}

for cand in $CANDIDATES; do
    [ -f "$cand" ] || continue
    CC=$(cc_from_filename "$cand")
    [ -z "$CC" ] && continue

    if is_technical_server "$CC"; then
        log "Пропускаем технический сервер: $CC"
        continue
    fi

    if [ -n "$TARGET_COUNTRY" ]; then
        [ "$CC" != "$TARGET_COUNTRY" ] && continue
    fi

    if [ "$CC" = "$CURRENT_CC" ] && [ "$FORCE_ROTATE" -eq 0 ] && [ -z "$TARGET_COUNTRY" ]; then
        continue
    fi

    CAND_TARGET="${AVAILABLE_DIR}/04_outbounds_${CC}.target"
    [ ! -f "$CAND_TARGET" ] && { log "Пропускаем $CC — нет .target"; continue; }

    NEW_TGT="$(head -n1 "$CAND_TARGET" | tr -d '\r\n')"
    [ -z "$NEW_TGT" ] && { log "Пропускаем $CC — .target пуст"; continue; }

    log "Проверяем $CC ($NEW_TGT)..."
    if ! health_tcp "$NEW_TGT"; then
        log "[$CC] Страна $CC недоступен — пропускаем."
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[TEST] Переключение на $CC ($NEW_TGT)"
        echo "[TEST] Файлы: ${AVAILABLE_DIR}/04_outbounds_${CC}.json -> $ACTIVE_FILE"
        exit 0
    else
        mv -f "$ACTIVE_FILE" "${AVAILABLE_DIR}/04_outbounds_${CURRENT_CC}.json" 2>/dev/null
        mv -f "$ACTIVE_TARGET" "${AVAILABLE_DIR}/04_outbounds_${CURRENT_CC}.target" 2>/dev/null
        mv -f "$cand" "$ACTIVE_FILE" 2>/dev/null
        mv -f "$CAND_TARGET" "$ACTIVE_TARGET" 2>/dev/null
    fi

    log "Активируем $CC и перезапускаем xkeen..."
    restart_xkeen

    if health_tcp "$NEW_TGT"; then
        echo "$CC" > "$STATE_FILE"
        log "Успешно активирована страна $CC ($NEW_TGT)."
        if [ -n "$CURRENT_CC" ] && [ "$CURRENT_CC" != "$CC" ]; then
            send_telegram "СМЕНА СЕРВЕРА" "Выполнено переключение с $CURRENT_CC ($CUR_TGT) на $CC ($NEW_TGT).
Новый сервер активирован и успешно прошёл проверку доступности."
        fi
        exit 0
    else
        log "[$CC] После рестарта страна $CC всё ещё недоступна — пробуем следующего кандидата."
    fi
done

if [ -n "$TARGET_COUNTRY" ]; then
    log "Страна $TARGET_COUNTRY не найдена или недоступна."
else
    log "Нет доступных стран с рабочими нодами. Оставляем текущую конфигурацию."
    send_telegram "КРИТИЧНО - ВСЕ СЕРВЕРЫ НЕДОСТУПНЫ" "Не найдено ни одного работающего сервера из доступных вариантов!
Текущая конфигурация $CURRENT_CC сохранена. Требуется срочная проверка серверов вручную."
fi
exit 1
