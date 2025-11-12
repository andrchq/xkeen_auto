#!/opt/bin/sh

set -e

# === ПАРАМЕТРЫ ===

TG_TOKEN="7305187909:AAHGkLCVpGIlg70AxWT2auyjOrhoAJkof1U"
TG_CHAT_ID="-1002517339071"
TG_TOPIC_ID=""

SCRIPT_NAME="network_watchdog"
HUMAN_NAME="Система мониторинга сети"

LOG_DIR="/opt/root/xkeen_logs/$SCRIPT_NAME"
LOG_BASE="${SCRIPT_NAME}"
DATE_SUFFIX=$(date '+%Y.%m.%d_%H-%M-%S')
LOG_FILE="$LOG_DIR/${LOG_BASE}_${DATE_SUFFIX}.log"
UNSENT_FILE="$LOG_DIR/pending_messages.log"

ARCHIVE_LIMIT_MB=10
MAX_LOG_FILES=60

PING_HOSTS="1.1.1.1 8.8.8.8 8.8.4.4"
PING_COUNT=1
PING_TIMEOUT=2

XKEEN_RESTART="/opt/sbin/xkeen -restart"
XKEEN_STATUS="/opt/sbin/xkeen -status"
XKEEN_START="/opt/sbin/xkeen -start"

COUNTER_FILE="$LOG_DIR/restart_counter.txt"
REBOOT_FILE="$LOG_DIR/reboot_limit.txt"
REBOOT_LIMIT=3

mkdir -p "$LOG_DIR"

# === ФУНКЦИИ ===

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  logger -t "$SCRIPT_NAME" "$1"
}

send_telegram_message() {
  local text="$1"
  local extra_args=""
  if [ -n "$TG_TOPIC_ID" ] && [ "$TG_TOPIC_ID" != "0" ]; then
    extra_args="-d message_thread_id=$TG_TOPIC_ID"
  fi
  curl -s --max-time 10 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "text=$text" \
    -d "parse_mode=HTML" \
    $extra_args >/dev/null 2>&1 || echo "$text" >> "$UNSENT_FILE"
}

send_telegram_file() {
  local file_path="$1"
  local caption="$2"
  local extra_args=""
  if [ -n "$TG_TOPIC_ID" ] && [ "$TG_TOPIC_ID" != "0" ]; then
    extra_args="-F message_thread_id=$TG_TOPIC_ID"
  fi
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendDocument" \
    -F "chat_id=$TG_CHAT_ID" \
    -F "document=@$file_path" \
    -F "caption=$caption" \
    -F "parse_mode=HTML" \
    $extra_args >/dev/null 2>&1 || echo "$caption" >> "$UNSENT_FILE"
}

flush_unsent_messages() {
  if [ -s "$UNSENT_FILE" ]; then
    local bundle_file="$LOG_DIR/unsent_$(date '+%Y%m%d_%H%M%S').log"
    mv "$UNSENT_FILE" "$bundle_file"
    send_telegram_file "$bundle_file" "📤 <b>$HUMAN_NAME:</b>\n\n<pre>Отложенные уведомления (интернет восстановлен)</pre>"
  fi
}

cleanup_old_logs() {
  local files count
  files=$(ls -1t "$LOG_DIR"/${LOG_BASE}_*.log 2>/dev/null | head -n 100)
  if [ -z "$files" ]; then
    return 0
  fi
  count=$(echo "$files" | grep -c .)
  if [ "$count" -gt "$MAX_LOG_FILES" ]; then
    echo "$files" | tail -n +$(($MAX_LOG_FILES + 1)) | while read -r f; do 
      [ -f "$f" ] && rm -f "$f"
    done
  fi
}

check_internet() {
  for host in $PING_HOSTS; do
    if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$host" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

restart_xkeen() {
  log_message "🔄 Перезапуск xkeen"
  sh -c "$XKEEN_RESTART" >> "$LOG_FILE" 2>&1
}

start_xkeen() {
  log_message "🟡 Попытка запуска xkeen"
  sh -c "$XKEEN_START" >> "$LOG_FILE" 2>&1
}

check_reboot_limit() {
  local count=0
  if [ -f "$REBOOT_FILE" ]; then
    count=$(cat "$REBOOT_FILE" 2>/dev/null | tr -d '\n\r' | grep -o '[0-9]*')
    [ -z "$count" ] && count=0
  fi
  count=$((count + 1))
  echo "$count" > "$REBOOT_FILE"

  if [ "$count" -gt "$REBOOT_LIMIT" ]; then
    log_message "🚫 Лимит перезагрузок $REBOOT_LIMIT достигнут. Больше не перезагружаем."
    send_telegram_message "🟧 <b>ОГРАНИЧЕНИЕ:</b>\n\n<b>Превышен лимит $REBOOT_LIMIT перезагрузок.</b>\nСкрипт прекращает перезагрузки."
    exit 0
  fi
}

reboot_router() {
  log_message "🔴 Перезагрузка роутера после 3 неудачных попыток"
  send_telegram_message "🟥 <b>ПРЕДУПРЕЖДЕНИЕ:</b>\n\n<b>Интернет недоступен.</b>\n\nВыполняется перезагрузка роутера!"
  reboot
}

check_xkeen_status() {
  local status
  status=$($XKEEN_STATUS 2>&1)
  status=$(echo "$status" | tr -d '\033' | sed 's/\[[0-9;]*m//g' | tr -d '\r\000' | tr -s ' ')
  log_message "Статус xkeen: $status"

  if echo "$status" | grep -q "Прокси-клиент запущен"; then
    log_message "✅ Статус xkeen: прокси запущен."
  else
    log_message "🟥 xkeen не запущен, попытка запуска"
    send_telegram_message "🟥 <b>$HUMAN_NAME:</b>\n\n<b>xkeen не запущен!</b>\n\n<pre>$status</pre>"
    start_xkeen
  fi
}

archive_log_if_too_large() {
  local size
  size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$size" -ge $((ARCHIVE_LIMIT_MB * 1024 * 1024)) ]; then
    # Создаем новый лог файл и архивируем старый
    local old_log="${LOG_FILE}.old"
    mv "$LOG_FILE" "$old_log"
    gzip "$old_log"
    # Пересоздаем LOG_FILE для будущих записей
    touch "$LOG_FILE"
    log_message "📦 Предыдущий лог заархивирован (более ${ARCHIVE_LIMIT_MB}MB)"
  fi
}

# === ОСНОВНАЯ ЛОГИКА ===

cleanup_old_logs
log_message "🚀 Проверка интернета"

if check_internet; then
  log_message "✅ Интернет доступен"
  rm -f "$COUNTER_FILE" "$REBOOT_FILE" 2>/dev/null
  flush_unsent_messages
else
  log_message "❌ Интернет недоступен"

  ATTEMPTS=1
  if [ -f "$COUNTER_FILE" ]; then
    PREV_ATTEMPTS=$(cat "$COUNTER_FILE" 2>/dev/null | tr -d '\n\r' | grep -o '[0-9]*')
    [ -n "$PREV_ATTEMPTS" ] && ATTEMPTS=$((PREV_ATTEMPTS + 1))
  fi
  echo "$ATTEMPTS" > "$COUNTER_FILE"

  if [ "$ATTEMPTS" -ge 3 ]; then
    send_telegram_file "$LOG_FILE" "🟥 <b>$HUMAN_NAME:</b>\n\n<b>Интернет отсутствует после 3 попыток.</b>\nВыполняется перезагрузка."
    check_reboot_limit
    reboot_router
  else
    send_telegram_file "$LOG_FILE" "🟧 <b>$HUMAN_NAME:</b>\n\n<b>Интернет недоступен. Перезапуск xkeen.</b>"
    restart_xkeen
  fi
fi

check_xkeen_status
archive_log_if_too_large
