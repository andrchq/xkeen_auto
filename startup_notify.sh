#!/opt/bin/sh

# === ПАРАМЕТРЫ ===

TG_TOKEN="7305187909:AAHGkLCVpGIlg70AxWT2auyjOrhoAJkof1U"
TG_CHAT_ID="-1002517339071"
TG_TOPIC_ID=""

LOG_DIR="/opt/root/xkeen_logs/startup_notify"
LOG_BASE="startup_notify"
DATE_SUFFIX=$(date '+%Y.%m.%d_%H-%M-%S')
LOG_FILE="$LOG_DIR/${LOG_BASE}_${DATE_SUFFIX}.log"
PENDING_FILE="$LOG_DIR/pending_messages.log"

MAX_LOG_FILES=60

mkdir -p "$LOG_DIR"

# === ФУНКЦИИ ===

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  logger -t startup_notify "$1"
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
    $extra_args >/dev/null 2>&1 || echo "$text" >> "$PENDING_FILE"
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
    $extra_args >/dev/null 2>&1
}

send_pending_if_any() {
  [ -s "$PENDING_FILE" ] || return

  local pending_file="/tmp/system_start_pending_$(date +%s).log"
  cp "$PENDING_FILE" "$pending_file"
  : > "$PENDING_FILE"

  send_telegram_file "$pending_file" "🟨 <b>ОТЛОЖЕННЫЕ УВЕДОМЛЕНИЯ:</b> (system_start)"
  rm -f "$pending_file"
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

# === ОТЛОЖЕННЫЙ СТАРТ ===

(
  sleep 120

  cleanup_old_logs

  CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  log_message "✅ Роутер успешно загрузился: $CURRENT_TIME"

  TEXT="🟩 <b>СТАРТ СИСТЕМЫ:</b>

<b>Роутер успешно загружен!</b>

⏰ $CURRENT_TIME"

  if check_internet; then
    send_pending_if_any
    send_telegram_message "$TEXT"
  else
    log_message "📡 Нет соединения с интернетом — сохраняем сообщение в очередь."
    echo "$TEXT" >> "$PENDING_FILE"
  fi
) &
