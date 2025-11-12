#!/opt/bin/sh

set -e

# === ПАРАМЕТРЫ ===

TG_TOKEN="7305187909:AAHGkLCVpGIlg70AxWT2auyjOrhoAJkof1U"
TG_CHAT_ID="-1002517339071"
TG_TOPIC_ID=""

LOG_DIR="/opt/root/xkeen_logs/xkeen_restart"
LOG_BASE="xkeen_restart"
DATE_SUFFIX=$(date '+%Y.%m.%d_%H-%M-%S')
LOG_FILE="$LOG_DIR/${LOG_BASE}_${DATE_SUFFIX}.log"
PENDING_FILE="$LOG_DIR/pending_messages.log"

CMD_RESTART="/opt/sbin/xkeen -restart"
CMD_STATUS="/opt/sbin/xkeen -status"

MAX_LOG_FILES=60
ARCHIVE_LIMIT_MB=10

mkdir -p "$LOG_DIR"

# === ФУНКЦИИ ===

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  logger -t xkeen_restart "$1"
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
    $extra_args >/dev/null 2>&1 || echo "$caption" >> "$PENDING_FILE"
}

send_pending_if_any() {
  [ -s "$PENDING_FILE" ] || return

  local pending_file="/tmp/xkeen_restart_pending_$(date +%s).log"
  cp "$PENDING_FILE" "$pending_file"
  : > "$PENDING_FILE"

  send_telegram_file "$pending_file" "🟨 <b>ОТЛОЖЕННЫЕ УВЕДОМЛЕНИЯ:</b> (xkeen_restart)"
  rm -f "$pending_file"
}

archive_log_if_too_large() {
  local size
  size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$size" -ge $((ARCHIVE_LIMIT_MB * 1024 * 1024)) ]; then
    local old_log="${LOG_FILE}.old"
    mv "$LOG_FILE" "$old_log"
    gzip "$old_log"
    touch "$LOG_FILE"
    log_message "📦 Предыдущий лог заархивирован из-за превышения ${ARCHIVE_LIMIT_MB}MB"
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
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

# === ОСНОВНАЯ ЛОГИКА ===

cleanup_old_logs
send_pending_if_any

log_message "🔄 Запуск команды перезапуска: $CMD_RESTART"
echo -e "\n-------------------- 🔽 ВЫВОД xkeen -restart 🔽 --------------------\n" >> "$LOG_FILE"

TMP_PIPE="/tmp/xkeen_pipe_$$"
rm -f "$TMP_PIPE"
mkfifo "$TMP_PIPE"

cat "$TMP_PIPE" >> "$LOG_FILE" &
TEE_PID=$!

sh -c "$CMD_RESTART" > "$TMP_PIPE" 2>&1 &
CMD_PID=$!

sleep 10

kill "$TEE_PID" 2>/dev/null || true
wait "$TEE_PID" 2>/dev/null || true
rm -f "$TMP_PIPE"

echo -e "\n-------------------- 🔼 КОНЕЦ xkeen -restart 🔼 --------------------\n" >> "$LOG_FILE"

ps | grep " $CMD_PID " | grep -v grep >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  log_message "⚠️ Процесс перезапуска всё ещё активен после 10 секунд."
else
  log_message "✅ Перезапуск завершился в течение 10 секунд."
fi

# === Проверка состояния xkeen ===

echo -e "\n-------------------- 🔽 ВЫВОД xkeen -status 🔽 --------------------\n" >> "$LOG_FILE"

STATUS_OUTPUT_RAW=$($CMD_STATUS 2>&1)
STATUS_OUTPUT=$(echo "$STATUS_OUTPUT_RAW" | tr -d '\033' | sed 's/\[[0-9;]*m//g' | tr -d '\r\000' | tr -s ' ')

echo "$STATUS_OUTPUT" >> "$LOG_FILE"
echo -e "\n-------------------- 🔼 КОНЕЦ xkeen -status 🔼 --------------------\n" >> "$LOG_FILE"

# === Уведомление в Telegram ===

if echo "$STATUS_OUTPUT" | grep -q "Прокси-клиент запущен"; then
  TEXT="🟩 <b>СТАТУС:</b>\n\n<pre>$STATUS_OUTPUT</pre>"
else
  TEXT="🟥 <b>ПРЕДУПРЕЖДЕНИЕ:</b>\n\n<b>Ошибка после перезапуска xkeen:</b>\n\n<pre>$STATUS_OUTPUT</pre>"
fi

send_telegram_file "$LOG_FILE" "$TEXT"
log_message "📤 Лог и статус отправлены в Telegram"

archive_log_if_too_large
