#!/bin/sh

set -e

INSTALL_DIR="/opt/root/scripts"
CONFIG_DIR="/opt/etc/xray"
GITHUB_RAW="https://raw.githubusercontent.com/andrchq/xkeen_auto/main"
CONFIGS_INSTALLED=0
SERVER_ACTIVATED=0

# ============ Настройка таймеров этапов ============
# Время ожидания (в секундах) перед переходом к следующему этапу
# Можно изменить значения для каждого этапа отдельно
# Для отключения таймера установите значение 0
# Для увеличения времени ожидания увеличьте значение (в секундах)
TIMER_START=7                    # Начало установки
TIMER_SCRIPTS_LOADED=5           # После загрузки скриптов
TIMER_INIT_SCRIPTS=5             # После установки init-скриптов
TIMER_PERMISSIONS=2              # После установки прав доступа
TIMER_PROSTO_COMMAND=7           # После установки команды prosto
TIMER_XRAY_CONFIGS=6             # После установки конфигов Xray
TIMER_TELEGRAM_TEST=2            # После тестового уведомления Telegram
TIMER_SUBSCRIPTION_LOAD=6        # После загрузки подписки
TIMER_SERVERS_LIST=7             # После показа списка серверов
TIMER_SERVER_ACTIVATE=5          # После активации сервера
TIMER_XRAY_RESTART=4             # После перезапуска Xray
TIMER_CRON_SETUP=2               # После настройки cron
TIMER_MONITORING_SETUP=2         # После настройки мониторинга
TIMER_PORTS_OPEN=2               # После открытия портов
# ====================================================
GRAY="\033[90m"
BLUE="\033[94m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
RESET="\033[0m"
BOLD="\033[1m"
ORANGE="\033[38;5;214m"
CYAN="\033[96m"

LINE="─────────────────────────────────────────────────"

show_header() {
    clear
    printf "${BLUE}${BOLD}🤲🏼 ПРОСТОВПН${RESET}\n"
    printf "${ORANGE}${LINE}${RESET}\n"
    echo ""
}

show_section() {
    TITLE="$1"
    printf "\n%s\n" "${ORANGE}${LINE}${RESET}"
    printf "%s\n" "${BLUE}${BOLD}${TITLE}${RESET}"
    printf "%s\n\n" "${ORANGE}${LINE}${RESET}"
}

show_log() {
    printf "${CYAN}$1${RESET}\n"
}

countdown() {
    SECONDS=${1:-5}
    while [ $SECONDS -gt 0 ]; do
        printf "\r${YELLOW}[%d]${RESET} " "$SECONDS"
        sleep 1
        SECONDS=$((SECONDS - 1))
    done
    printf "\r    \r"
}

log() {
    printf "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${RESET}\n"
}

error() {
    printf "${RED}[ОШИБКА] $*${RESET}\n" >&2
    exit 1
}

# Безопасное создание файла с бэкапом
safe_create_file() {
    FILE_PATH="$1"
    CONTENT="$2"
    
    # Если файл существует, создаём бэкап
    if [ -f "$FILE_PATH" ]; then
        BACKUP_PATH="${FILE_PATH}.bak.$(date +%s)"
        cp "$FILE_PATH" "$BACKUP_PATH" 2>/dev/null && log "Создан backup: $(basename "$BACKUP_PATH")"
    fi
    
    # Создаём/заменяем файл
    echo "$CONTENT" > "$FILE_PATH"
}

# Безопасная загрузка файла с бэкапом
safe_download_file() {
    URL="$1"
    FILE_PATH="$2"
    
    # Если файл существует, создаём бэкап
    if [ -f "$FILE_PATH" ]; then
        BACKUP_PATH="${FILE_PATH}.bak.$(date +%s)"
        cp "$FILE_PATH" "$BACKUP_PATH" 2>/dev/null && log "Создан backup: $(basename "$BACKUP_PATH")"
    fi
    
    # Загружаем файл
    if curl -sSL "$URL" -o "$FILE_PATH"; then
        return 0
    else
        return 1
    fi
}

create_prosto_command() {
    PROSTO_PATH="/opt/bin/prosto"
    
    if [ ! -d "/opt/bin" ]; then
        mkdir -p /opt/bin
    fi
    
    cat > "$PROSTO_PATH" << 'EOFPROSTO'
#!/bin/sh

SCRIPT_DIR="/opt/root/scripts"
GITHUB_RAW="https://raw.githubusercontent.com/andrchq/xkeen_auto/main"
VERSION_FILE="$SCRIPT_DIR/.version"
UPDATE_CHECK_FILE="/tmp/prosto_update_check"
SUBSCRIPTION_FILE="$SCRIPT_DIR/.subscription_url"
OPENED_PORTS_FILE="$SCRIPT_DIR/.opened_ports"
FAVORITE_COUNTRY_FILE="$SCRIPT_DIR/.favorite_country"
FORCED_COUNTRY_FILE="$SCRIPT_DIR/.forced_country"
AVAILABLE_DIR="/opt/etc/xray/outbounds_available"

GRAY="\033[90m"
BLUE="\033[94m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
RESET="\033[0m"
BOLD="\033[1m"
ORANGE="\033[38;5;214m"
CYAN="\033[96m"

LINE="─────────────────────────────────────────────────"

show_header() {
    clear
    printf "${BLUE}${BOLD}🤲🏼 ПРОСТОВПН${RESET}\n"
    printf "${ORANGE}${LINE}${RESET}\n"
    echo ""
}

show_section() {
    printf "\n${ORANGE}${LINE}${RESET}\n"
    printf "${BLUE}${BOLD}$1${RESET}\n"
    printf "${ORANGE}${LINE}${RESET}\n\n"
}

show_log() {
    printf "${CYAN}$1${RESET}\n"
}

show_countdown() {
    _SECS=${1:-3}
    while [ $_SECS -gt 0 ]; do
        printf "\r${YELLOW}[%d]${RESET} " "$_SECS"
        sleep 1
        _SECS=$((_SECS - 1))
    done
    printf "\r    \r"
}

get_subscription_url() {
    if [ -f "$SUBSCRIPTION_FILE" ]; then
        cat "$SUBSCRIPTION_FILE" 2>/dev/null | tr -d '\n\r'
    fi
}

save_subscription_url() {
    echo "$1" > "$SUBSCRIPTION_FILE"
}

get_local_version() {
    if [ -f "$VERSION_FILE" ]; then
        _CONTENT=$(cat "$VERSION_FILE" 2>/dev/null)
        _VER=$(echo "$_CONTENT" | grep "^version:" | cut -d: -f2 | tr -d ' \n\r')
        if [ -n "$_VER" ]; then
            echo "$_VER"
        else
            echo "$_CONTENT" | head -n1 | tr -d '\n\r '
        fi
    else
        echo "0.0.0"
    fi
}

get_file_version() {
    _FILENAME="$1"
    if [ -f "$VERSION_FILE" ]; then
        _VER=$(grep "^${_FILENAME}:" "$VERSION_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' \n\r')
        [ -n "$_VER" ] && echo "$_VER" || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

get_update_type() {
    _VERSION_CONTENT="$1"
    echo "$_VERSION_CONTENT" | grep "^type:" | cut -d: -f2 | tr -d ' '
}

get_main_version() {
    _VERSION_CONTENT="$1"
    echo "$_VERSION_CONTENT" | grep "^version:" | cut -d: -f2 | tr -d ' '
}

version_greater() {
    LOCAL_VER="$1"
    REMOTE_VER="$2"
    LOCAL_MAJOR=$(echo "$LOCAL_VER" | cut -d. -f1)
    LOCAL_MINOR=$(echo "$LOCAL_VER" | cut -d. -f2)
    LOCAL_PATCH=$(echo "$LOCAL_VER" | cut -d. -f3)
    REMOTE_MAJOR=$(echo "$REMOTE_VER" | cut -d. -f1)
    REMOTE_MINOR=$(echo "$REMOTE_VER" | cut -d. -f2)
    REMOTE_PATCH=$(echo "$REMOTE_VER" | cut -d. -f3)
    [ -z "$LOCAL_MAJOR" ] && LOCAL_MAJOR=0
    [ -z "$LOCAL_MINOR" ] && LOCAL_MINOR=0
    [ -z "$LOCAL_PATCH" ] && LOCAL_PATCH=0
    [ -z "$REMOTE_MAJOR" ] && REMOTE_MAJOR=0
    [ -z "$REMOTE_MINOR" ] && REMOTE_MINOR=0
    [ -z "$REMOTE_PATCH" ] && REMOTE_PATCH=0
    [ "$REMOTE_MAJOR" -gt "$LOCAL_MAJOR" ] && return 0
    [ "$REMOTE_MAJOR" -lt "$LOCAL_MAJOR" ] && return 1
    [ "$REMOTE_MINOR" -gt "$LOCAL_MINOR" ] && return 0
    [ "$REMOTE_MINOR" -lt "$LOCAL_MINOR" ] && return 1
    [ "$REMOTE_PATCH" -gt "$LOCAL_PATCH" ] && return 0
    return 1
}

check_for_updates() {
    if [ -f "$UPDATE_CHECK_FILE" ]; then
        LAST_CHECK=$(cat "$UPDATE_CHECK_FILE" 2>/dev/null)
        CURRENT_TIME=$(date +%s)
        if [ -n "$LAST_CHECK" ] && [ "$CURRENT_TIME" -lt "$((LAST_CHECK + 3600))" ]; then
            return 1
        fi
    fi
    date +%s > "$UPDATE_CHECK_FILE"
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        return 1
    fi
    LOCAL_VERSION=$(get_local_version)
    REMOTE_CONTENT=$(curl -sL --max-time 5 "$GITHUB_RAW/VERSION" 2>/dev/null)
    REMOTE_VERSION=$(get_main_version "$REMOTE_CONTENT")
    [ -z "$REMOTE_VERSION" ] && return 1
    version_greater "$LOCAL_VERSION" "$REMOTE_VERSION" && return 0
    return 1
}

offer_update() {
    LOCAL_VERSION=$(get_local_version)
    REMOTE_CONTENT=$(curl -sL --max-time 5 "$GITHUB_RAW/VERSION" 2>/dev/null)
    REMOTE_VERSION=$(get_main_version "$REMOTE_CONTENT")
    UPDATE_TYPE=$(get_update_type "$REMOTE_CONTENT")
    
    case "$UPDATE_TYPE" in
        critical) TYPE_COLOR="$RED"; TYPE_TEXT="КРИТИЧЕСКОЕ" ;;
        recommended) TYPE_COLOR="$YELLOW"; TYPE_TEXT="РЕКОМЕНДУЕМОЕ" ;;
        *) TYPE_COLOR="$GRAY"; TYPE_TEXT="необязательное" ;;
    esac
    
    show_section "🔄 Доступно обновление!"
    printf "Текущая версия:  ${GRAY}${LOCAL_VERSION}${RESET}\n"
    printf "Новая версия:    ${GREEN}${REMOTE_VERSION}${RESET}\n"
    printf "Тип обновления:  ${TYPE_COLOR}${TYPE_TEXT}${RESET}\n"
    printf "\n${ORANGE}${LINE}${RESET}\n\n"
    printf "${BLUE}Обновить систему сейчас? (y/n): ${RESET}"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        run_update
    fi
}

smart_update() {
    REMOTE_CONTENT="$1"
    show_section "Обновление системы"
    UPDATED_COUNT=0
    
    for _FILE in xkeen_rotate.sh xkeen_sync.sh network_watchdog.sh startup_notify.sh xkeen_restart.sh; do
        LOCAL_FILE_VER=$(get_file_version "$_FILE")
        REMOTE_FILE_VER=$(echo "$REMOTE_CONTENT" | grep "^${_FILE}:" | cut -d: -f2 | tr -d ' ')
        [ -z "$REMOTE_FILE_VER" ] && continue
        if version_greater "$LOCAL_FILE_VER" "$REMOTE_FILE_VER"; then
            printf "${CYAN}Обновляю $_FILE...${RESET} "
            if curl -sSL "$GITHUB_RAW/$_FILE" -o "$SCRIPT_DIR/$_FILE" 2>/dev/null; then
                chmod +x "$SCRIPT_DIR/$_FILE"
                printf "${GREEN}✓${RESET}\n"
                UPDATED_COUNT=$((UPDATED_COUNT + 1))
            else
                printf "${RED}✗${RESET}\n"
            fi
        fi
    done
    
    LOCAL_PROSTO_VER=$(get_file_version "prosto")
    REMOTE_PROSTO_VER=$(echo "$REMOTE_CONTENT" | grep "^prosto:" | cut -d: -f2 | tr -d ' ')
    if [ -n "$REMOTE_PROSTO_VER" ] && version_greater "$LOCAL_PROSTO_VER" "$REMOTE_PROSTO_VER"; then
        printf "${CYAN}Обновляю prosto...${RESET} "
        if curl -sSL "$GITHUB_RAW/prosto" -o "/opt/bin/prosto" 2>/dev/null; then
            chmod +x "/opt/bin/prosto"
            printf "${GREEN}✓${RESET}\n"
            UPDATED_COUNT=$((UPDATED_COUNT + 1))
        else
            printf "${RED}✗${RESET}\n"
        fi
    fi
    
    printf "${CYAN}Обновляю VERSION...${RESET} "
    if curl -sSL "$GITHUB_RAW/VERSION" -o "$VERSION_FILE" 2>/dev/null; then
        printf "${GREEN}✓${RESET}\n"
    else
        printf "${RED}✗${RESET}\n"
    fi
    
    printf "${ORANGE}${LINE}${RESET}\n\n"
    if [ $UPDATED_COUNT -gt 0 ]; then
        printf "${GREEN}✓ Обновлено файлов: $UPDATED_COUNT${RESET}\n"
        printf "${GRAY}Перезапустите prosto для применения изменений${RESET}\n"
    else
        printf "${GREEN}✓ Все файлы актуальны${RESET}\n"
    fi
    rm -f "$UPDATE_CHECK_FILE"
}

run_update() {
    show_section "Полное обновление"
    printf "${CYAN}Запускаю установщик...${RESET}\n"
    printf "${ORANGE}${LINE}${RESET}\n\n"
    rm -f "$UPDATE_CHECK_FILE"
    curl -sSL "$GITHUB_RAW/install.sh" | sh
    exit 0
}

run_xkeen_ap_with_timeout() {
    _PORTS="$1"
    _TIMEOUT=15
    _OUTPUT_FILE="/tmp/xkeen_ports_output_$$"
    (xkeen -ap "$_PORTS" > "$_OUTPUT_FILE" 2>&1; echo $? > "${_OUTPUT_FILE}.exit") &
    _CMD_PID=$!
    _WAITED=0
    while [ $_WAITED -lt $_TIMEOUT ]; do
        if ! kill -0 "$_CMD_PID" 2>/dev/null; then
            wait "$_CMD_PID" 2>/dev/null
            if [ -f "${_OUTPUT_FILE}.exit" ]; then
                _EXIT_CODE=$(cat "${_OUTPUT_FILE}.exit")
                cat "$_OUTPUT_FILE" 2>/dev/null
                rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit"
                return $_EXIT_CODE
            fi
            cat "$_OUTPUT_FILE" 2>/dev/null
            rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit"
            return 0
        fi
        sleep 1
        _WAITED=$((_WAITED + 1))
        printf "\r${GRAY}Ожидание... %d/%d сек${RESET}" "$_WAITED" "$_TIMEOUT"
    done
    printf "\n${YELLOW}⚠ Таймаут! Команда не завершилась за %d секунд${RESET}\n" "$_TIMEOUT"
    kill -9 "$_CMD_PID" 2>/dev/null
    wait "$_CMD_PID" 2>/dev/null
    rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit"
    return 124
}

run_xkeen_restart_with_timeout() {
    _TIMEOUT=10
    _OUTPUT_FILE="/tmp/xkeen_restart_output_$$"
    (xkeen -restart > "$_OUTPUT_FILE" 2>&1; echo $? > "${_OUTPUT_FILE}.exit") &
    _CMD_PID=$!
    _WAITED=0
    while [ $_WAITED -lt $_TIMEOUT ]; do
        if ! kill -0 "$_CMD_PID" 2>/dev/null; then
            wait "$_CMD_PID" 2>/dev/null
            if [ -f "${_OUTPUT_FILE}.exit" ]; then
                cat "$_OUTPUT_FILE" 2>/dev/null
                rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit"
                return 0
            fi
            cat "$_OUTPUT_FILE" 2>/dev/null
            rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit"
            return 0
        fi
        sleep 1
        _WAITED=$((_WAITED + 1))
    done
    kill -9 "$_CMD_PID" 2>/dev/null
    wait "$_CMD_PID" 2>/dev/null
    cat "$_OUTPUT_FILE" 2>/dev/null
    rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit"
    return 0
}

restart_xkeen_for_ports() {
    show_log "Перезапуск xkeen..."
    run_xkeen_restart_with_timeout
    printf "${GREEN}✓ xkeen перезапущен${RESET}\n"
    sleep 2
    return 0
}

open_ports() {
    PORTS_TO_OPEN="80,443,50000:50030"
    printf "${BLUE}Порты для открытия: ${PORTS_TO_OPEN}${RESET}\n\n"
    printf "${YELLOW}Открыть эти порты? (y/n): ${RESET}"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        printf "\n${BLUE}Открываю порты...${RESET}\n"
        printf "${GRAY}Таймаут: 15 секунд${RESET}\n\n"
        if command -v xkeen >/dev/null 2>&1; then
            MAX_ATTEMPTS=3
            ATTEMPT=1
            PORTS_SUCCESS=0
            while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ $PORTS_SUCCESS -eq 0 ]; do
                printf "${BLUE}Попытка $ATTEMPT из $MAX_ATTEMPTS...${RESET}\n"
                PORTS_OUTPUT=$(run_xkeen_ap_with_timeout "$PORTS_TO_OPEN")
                RESULT=$?
                echo ""
                if [ $RESULT -eq 124 ]; then
                    printf "${YELLOW}Команда зависла, перезапускаю xkeen...${RESET}\n\n"
                    restart_xkeen_for_ports
                    echo ""
                    ATTEMPT=$((ATTEMPT + 1))
                    continue
                elif [ $RESULT -eq 0 ]; then
                    echo "$PORTS_OUTPUT"
                    echo ""
                    NEW_PORTS=$(echo "$PORTS_OUTPUT" | awk '/Новые порты прокси-клиента/{found=1; next} /Прокси-клиент уже работает/{found=0} found && /^[[:space:]]*[0-9]/{gsub(/^[[:space:]]+/, ""); print}' | tr '\n' ',' | sed 's/,$//')
                    if [ -n "$NEW_PORTS" ]; then
                        echo "$NEW_PORTS" > "$OPENED_PORTS_FILE"
                        printf "${GREEN}✓ Порты успешно открыты!${RESET}\n"
                        printf "${GRAY}Новые порты сохранены: $NEW_PORTS${RESET}\n"
                    else
                        printf "${GREEN}✓ Все порты уже были открыты ранее${RESET}\n"
                    fi
                    PORTS_SUCCESS=1
                else
                    printf "${RED}Ошибка при открытии портов (код: $RESULT)${RESET}\n"
                    echo "$PORTS_OUTPUT"
                    ATTEMPT=$((ATTEMPT + 1))
                    if [ $ATTEMPT -le $MAX_ATTEMPTS ]; then
                        printf "${YELLOW}Перезапускаю xkeen перед повторной попыткой...${RESET}\n"
                        restart_xkeen_for_ports
                        echo ""
                    fi
                fi
            done
            if [ $PORTS_SUCCESS -eq 0 ]; then
                printf "${RED}⚠ Не удалось открыть порты после $MAX_ATTEMPTS попыток${RESET}\n"
            fi
        else
            printf "${RED}Ошибка: xkeen не найден${RESET}\n"
        fi
    else
        printf "${GRAY}Отменено.${RESET}\n"
    fi
}

close_opened_ports() {
    if [ ! -f "$OPENED_PORTS_FILE" ]; then
        printf "${YELLOW}Файл с открытыми портами не найден.${RESET}\n"
        printf "${GRAY}Возможно, порты не были открыты при установке.${RESET}\n"
        return 1
    fi
    PORTS_TO_CLOSE=$(cat "$OPENED_PORTS_FILE" 2>/dev/null | tr -d '\n\r ')
    if [ -z "$PORTS_TO_CLOSE" ]; then
        printf "${YELLOW}Список портов пуст.${RESET}\n"
        printf "${GRAY}При установке не были открыты новые порты.${RESET}\n"
        return 1
    fi
    printf "${BLUE}Порты, открытые при установке: ${PORTS_TO_CLOSE}${RESET}\n\n"
    printf "${YELLOW}Закрыть эти порты? (y/n): ${RESET}"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        printf "\n${BLUE}Закрываю порты...${RESET}\n"
        printf "${GRAY}Это может занять около 20 секунд...${RESET}\n\n"
        if command -v xkeen >/dev/null 2>&1; then
            xkeen -dp "$PORTS_TO_CLOSE"
            RESULT=$?
            echo ""
            if [ $RESULT -eq 0 ]; then
                rm -f "$OPENED_PORTS_FILE"
                printf "${GREEN}✓ Порты успешно закрыты!${RESET}\n"
            else
                printf "${RED}Ошибка при закрытии портов (код: $RESULT)${RESET}\n"
            fi
        else
            printf "${RED}Ошибка: xkeen не найден${RESET}\n"
        fi
    else
        printf "${GRAY}Отменено.${RESET}\n"
    fi
}

get_favorite_country() {
    if [ -f "$FAVORITE_COUNTRY_FILE" ]; then
        cat "$FAVORITE_COUNTRY_FILE" 2>/dev/null | tr -d '\n\r '
    fi
}

get_forced_country() {
    if [ -f "$FORCED_COUNTRY_FILE" ]; then
        LINE=$(cat "$FORCED_COUNTRY_FILE" 2>/dev/null)
        CC="${LINE%%:*}"
        TIMESTAMP="${LINE##*:}"
        if [ -n "$CC" ] && [ -n "$TIMESTAMP" ]; then
            CURRENT_TIME=$(date +%s)
            TIME_DIFF=$((CURRENT_TIME - TIMESTAMP))
            if [ "$TIME_DIFF" -lt 300 ]; then
                echo "$CC"
            fi
        fi
    fi
}

is_technical_server() {
    CC="$1"
    TECHNICAL_NAMES="WIFI|WiFi|wifi|PROXY|proxy|TEST|test|LOCAL|local|VPN|vpn|SERVER|server|NODE|node|DIRECT|direct|BLOCK|block|REJECT|reject|AUTO|auto|BEST|best|FAST|fast|LOAD|load|BALANCE|balance"
    echo "$CC" | grep -qiE "^($TECHNICAL_NAMES)$" && return 0
    echo "$CC" | grep -q '%' && return 0
    echo "$CC" | grep -qE '^[0-9_a-z]+$' && return 0
    echo "$CC" | grep -q '\.' && return 0
    echo "$CC" | grep -qE '[\[\]]' && return 0
    CC_LEN=$(echo "$CC" | wc -c)
    [ "$CC_LEN" -lt 3 ] || [ "$CC_LEN" -gt 15 ] && return 0
    VALID_COUNTRIES="USA|US|GERMANY|DE|RUSSIA|RU|FRANCE|FR|NETHERLANDS|NL|UK|GB|JAPAN|JP|SINGAPORE|SG|CANADA|CA|AUSTRALIA|AU|BRAZIL|BR|INDIA|IN|CHINA|CN|KOREA|KR|ITALY|IT|SPAIN|ES|POLAND|PL|SWEDEN|SE|NORWAY|NO|FINLAND|FI|DENMARK|DK|AUSTRIA|AT|SWITZERLAND|CH|BELGIUM|BE|IRELAND|IE|PORTUGAL|PT|GREECE|GR|CZECH|CZ|ROMANIA|RO|HUNGARY|HU|BULGARIA|BG|UKRAINE|UA|TURKEY|TR|ISRAEL|IL|UAE|DUBAI|HONG|HK|TAIWAN|TW|THAILAND|TH|VIETNAM|VN|INDONESIA|ID|MALAYSIA|MY|PHILIPPINES|PH|MEXICO|MX|ARGENTINA|AR|CHILE|CL|COLOMBIA|CO|PERU|PE|SOUTH|AFRICA|ZA|EGYPT|EG|MOROCCO|MA|NIGERIA|NG|KENYA|KE|LITVA|LATVIA|LV|LITHUANIA|LT|ESTONIA|EE|KAZAHSTAN|KAZAKHSTAN|KZ|UZBEKISTAN|UZ|GEORGIA|ARMENIA|AM|AZERBAIJAN|AZ|BELARUS|BY|MOLDOVA|MD|SERBIA|RS|CROATIA|HR|SLOVENIA|SI|SLOVAKIA|SK|CYPRUS|CY|MALTA|MT|LUXEMBOURG|LU|ICELAND|MOSCOW|BERLIN|LONDON|PARIS|AMSTERDAM|TOKYO|SEOUL|BEIJING|SHANGHAI|MUMBAI|SYDNEY|TORONTO|VANCOUVER|MIAMI|DALLAS|CHICAGO|ATLANTA|SEATTLE|DENVER|PHOENIX|BOSTON|WASHINGTON|NEWYORK|LOSANGELES|SANFRANCISCO|FRANKFURT|MUNICH|VIENNA|ZURICH|GENEVA|BRUSSELS|DUBLIN|LISBON|MADRID|BARCELONA|ROME|MILAN|PRAGUE|WARSAW|BUDAPEST|BUCHAREST|SOFIA|HELSINKI|STOCKHOLM|OSLO|COPENHAGEN"
    echo "$CC" | grep -qiE "^($VALID_COUNTRIES)" && return 1
    return 0
}

get_available_countries() {
    for f in "${AVAILABLE_DIR}"/04_outbounds_*.json; do
        [ -f "$f" ] || continue
        CC=$(basename "$f" | sed -n 's/^04_outbounds_\([^.]*\)\.json$/\1/p')
        [ -z "$CC" ] && continue
        is_technical_server "$CC" && continue
        echo "$CC"
    done
}

select_country_menu() {
    TITLE="$1"
    printf "${BLUE}${BOLD}${TITLE}${RESET}\n\n"
    FAVORITE=$(get_favorite_country)
    FORCED=$(get_forced_country)
    
    # Проверяем наличие стран
    COUNTRY_LIST=$(get_available_countries | sort)
    if [ -z "$COUNTRY_LIST" ]; then
        printf "${YELLOW}Список стран пуст!${RESET}\n\n"
        printf "${GRAY}Страны не найдены в папке конфигураций.${RESET}\n"
        SAVED_URL=$(get_subscription_url)
        if [ -n "$SAVED_URL" ]; then
            printf "${BLUE}Выполнить синхронизацию подписки? (y/n): ${RESET}"
            read -r dosync
            if [ "$dosync" = "y" ] || [ "$dosync" = "Y" ]; then
                $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$SAVED_URL"
                # Повторно получаем список после синхронизации
                COUNTRY_LIST=$(get_available_countries | sort)
            fi
        else
            printf "${RED}URL подписки не настроен!${RESET}\n"
            printf "Используйте пункт 7 меню для настройки ссылки подписки.\n"
        fi
        if [ -z "$COUNTRY_LIST" ]; then
            SELECTED_COUNTRY=""
            return 1
        fi
    fi
    
    printf "${GRAY}Доступные страны:${RESET}\n\n"
    i=1
    COUNTRIES_FILE="/tmp/prosto_countries_$$"
    : > "$COUNTRIES_FILE"
    for CC in $COUNTRY_LIST; do
        MARKS=""
        [ "$CC" = "$FAVORITE" ] && MARKS=" [★ избранная]"
        [ "$CC" = "$FORCED" ] && MARKS=" [⚡ принудительная]"
        printf "  ${BLUE}%2d)${RESET} %s${YELLOW}%s${RESET}\n" "$i" "$CC" "$MARKS"
        echo "$CC" >> "$COUNTRIES_FILE"
        i=$((i + 1))
    done
    echo ""
    printf "${BLUE}Введите номер страны (0 для отмены): ${RESET}"
    read -r choice
    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        rm -f "$COUNTRIES_FILE"
        SELECTED_COUNTRY=""
        return 1
    fi
    SELECTED_COUNTRY=$(sed -n "${choice}p" "$COUNTRIES_FILE")
    rm -f "$COUNTRIES_FILE"
    if [ -n "$SELECTED_COUNTRY" ]; then
        return 0
    fi
    SELECTED_COUNTRY=""
    return 1
}

set_favorite_interactive() {
    select_country_menu "Выбор избранной страны"
    if [ $? -eq 0 ] && [ -n "$SELECTED_COUNTRY" ]; then
        echo "$SELECTED_COUNTRY" > "$FAVORITE_COUNTRY_FILE"
        printf "\n${GREEN}✓ Избранная страна установлена: $SELECTED_COUNTRY${RESET}\n"
        printf "${GRAY}Эта страна будет в приоритете при ротации, без ограничений по ping.${RESET}\n"
    else
        printf "\n${GRAY}Отменено.${RESET}\n"
    fi
}

clear_favorite() {
    if [ -f "$FAVORITE_COUNTRY_FILE" ]; then
        rm -f "$FAVORITE_COUNTRY_FILE"
        printf "${GREEN}✓ Избранная страна сброшена.${RESET}\n"
    else
        printf "${GRAY}Избранная страна не была установлена.${RESET}\n"
    fi
}

set_forced_interactive() {
    select_country_menu "Выбрать страну принудительно"
    if [ $? -eq 0 ] && [ -n "$SELECTED_COUNTRY" ]; then
        TIMESTAMP=$(date +%s)
        echo "${SELECTED_COUNTRY}:${TIMESTAMP}" > "$FORCED_COUNTRY_FILE"
        printf "\n${GREEN}✓ Принудительно выбрана страна: $SELECTED_COUNTRY${RESET}\n"
        printf "${GRAY}Эта страна будет использоваться 5 минут или до недоступности.${RESET}\n"
        echo ""
        printf "${BLUE}Активировать сейчас? (y/n): ${RESET}"
        read -r activate
        if [ "$activate" = "y" ] || [ "$activate" = "Y" ]; then
            $SCRIPT_DIR/xkeen_rotate.sh --country="$SELECTED_COUNTRY" --force --verbose
        fi
    else
        printf "\n${GRAY}Отменено.${RESET}\n"
    fi
}

clear_forced() {
    if [ -f "$FORCED_COUNTRY_FILE" ]; then
        rm -f "$FORCED_COUNTRY_FILE"
        printf "${GREEN}✓ Принудительный выбор сброшен.${RESET}\n"
    else
        printf "${GRAY}Принудительный выбор не был установлен.${RESET}\n"
    fi
}

favorite_menu() {
    show_header
    show_section "Избранная страна"
    FAVORITE=$(get_favorite_country)
    if [ -n "$FAVORITE" ]; then
        printf "Текущая избранная: ${YELLOW}★ $FAVORITE${RESET}\n\n"
    else
        printf "${GRAY}Избранная страна не установлена.${RESET}\n\n"
    fi
    printf "${BLUE}1)${RESET} Установить избранную страну\n"
    printf "${BLUE}2)${RESET} Сбросить избранную страну\n"
    printf "${BLUE}0)${RESET} Назад\n"
    printf "${ORANGE}${LINE}${RESET}\n"
    printf "${BLUE}Выберите действие: ${RESET}"
    read -r choice
    case $choice in
        1) show_header; set_favorite_interactive ;;
        2) clear_favorite ;;
        0|*) return ;;
    esac
}

forced_menu() {
    show_header
    show_section "Выбрать страну принудительно"
    FORCED=$(get_forced_country)
    if [ -n "$FORCED" ]; then
        printf "Текущий выбор: ${CYAN}⚡ $FORCED${RESET}\n"
        printf "${GRAY}(сбросится через 5 минут или при недоступности)${RESET}\n\n"
    else
        printf "${GRAY}Принудительный выбор не установлен.${RESET}\n\n"
    fi
    printf "${BLUE}1)${RESET} Выбрать страну принудительно\n"
    printf "${BLUE}2)${RESET} Сбросить принудительный выбор\n"
    printf "${BLUE}0)${RESET} Назад\n"
    printf "${ORANGE}${LINE}${RESET}\n"
    printf "${BLUE}Выберите действие: ${RESET}"
    read -r choice
    case $choice in
        1) show_header; set_forced_interactive ;;
        2) clear_forced ;;
        0|*) return ;;
    esac
}

force_check_updates() {
    show_section "Проверка обновлений"
    rm -f "$UPDATE_CHECK_FILE"
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        printf "${RED}Нет подключения к интернету${RESET}\n"
        return 1
    fi
    LOCAL_VERSION=$(get_local_version)
    printf "Текущая версия: ${GRAY}${LOCAL_VERSION}${RESET}\n"
    printf "Проверяю удалённую версию... "
    REMOTE_CONTENT=$(curl -sL --max-time 5 "$GITHUB_RAW/VERSION" 2>/dev/null)
    REMOTE_VERSION=$(get_main_version "$REMOTE_CONTENT")
    UPDATE_TYPE=$(get_update_type "$REMOTE_CONTENT")
    if [ -z "$REMOTE_VERSION" ]; then
        printf "${RED}ошибка загрузки${RESET}\n"
        return 1
    fi
    printf "${GREEN}${REMOTE_VERSION}${RESET}\n"
    printf "${ORANGE}${LINE}${RESET}\n\n"
    if version_greater "$LOCAL_VERSION" "$REMOTE_VERSION"; then
        case "$UPDATE_TYPE" in
            critical) TYPE_COLOR="$RED"; TYPE_TEXT="КРИТИЧЕСКОЕ" ;;
            recommended) TYPE_COLOR="$YELLOW"; TYPE_TEXT="РЕКОМЕНДУЕМОЕ" ;;
            *) TYPE_COLOR="$GRAY"; TYPE_TEXT="необязательное" ;;
        esac
        printf "${GREEN}Доступна новая версия: ${REMOTE_VERSION}${RESET}\n"
        printf "Тип обновления: ${TYPE_COLOR}${TYPE_TEXT}${RESET}\n\n"
        printf "${GRAY}Файлы для обновления:${RESET}\n"
        for _FILE in prosto xkeen_rotate.sh xkeen_sync.sh network_watchdog.sh startup_notify.sh xkeen_restart.sh; do
            LOCAL_FILE_VER=$(get_file_version "$_FILE")
            REMOTE_FILE_VER=$(echo "$REMOTE_CONTENT" | grep "^${_FILE}:" | cut -d: -f2 | tr -d ' ')
            [ -z "$REMOTE_FILE_VER" ] && continue
            if version_greater "$LOCAL_FILE_VER" "$REMOTE_FILE_VER"; then
                printf "  ${CYAN}$_FILE${RESET}: $LOCAL_FILE_VER → ${GREEN}$REMOTE_FILE_VER${RESET}\n"
            fi
        done
        printf "\n${BLUE}Обновить сейчас? (y/n): ${RESET}"
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            smart_update "$REMOTE_CONTENT"
        fi
    else
        printf "${GREEN}✓ У вас установлена актуальная версия!${RESET}\n"
    fi
}

show_menu() {
    show_header
    LOCAL_VERSION=$(get_local_version)
    FAVORITE=$(get_favorite_country)
    FORCED=$(get_forced_country)
    printf "${GRAY}v${LOCAL_VERSION}${RESET}\n"
    if [ -n "$FAVORITE" ] || [ -n "$FORCED" ]; then
        [ -n "$FAVORITE" ] && printf "${YELLOW}★ Избранная: $FAVORITE${RESET}  "
        [ -n "$FORCED" ] && printf "${CYAN}⚡ Принудительная: $FORCED${RESET}"
        echo ""
    fi
    printf "${ORANGE}${LINE}${RESET}\n\n"
    printf "${BLUE}1)${RESET} Показать статус серверов\n"
    printf "${BLUE}2)${RESET} Автоматическая ротация\n"
    printf "${BLUE}3)${RESET} Выбрать страну принудительно\n"
    printf "${BLUE}4)${RESET} Избранная страна\n"
    printf "${BLUE}5)${RESET} Тестовое уведомление\n"
    printf "${BLUE}6)${RESET} Синхронизация подписки\n"
    printf "${BLUE}7)${RESET} Смена ссылки подписки\n"
    printf "${BLUE}8)${RESET} Очистка файлов\n"
    printf "${BLUE}9)${RESET} Проверить обновления\n"
    printf "${BLUE}10)${RESET} Открыть порты\n"
    printf "${BLUE}11)${RESET} Закрыть порты\n"
    printf "${BLUE}12)${RESET} Перезапуск xkeen\n"
    printf "${BLUE}13)${RESET} О системе\n"
    printf "${BLUE}0)${RESET} Выход\n"
    printf "${ORANGE}${LINE}${RESET}\n"
    printf "${BLUE}Выберите действие: ${RESET}"
}

if [ "$1" = "status" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --status
    exit 0
elif [ "$1" = "force" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --force --verbose
    exit 0
elif [ "$1" = "test" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --test-notify
    exit 0
elif [ "$1" = "sync" ]; then
    SAVED_URL=$(get_subscription_url)
    if [ -n "$SAVED_URL" ]; then
        $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$SAVED_URL"
    else
        printf "${RED}Ошибка: URL подписки не настроен.${RESET}\n"
        echo "Используйте: prosto seturl <URL>"
    fi
    exit 0
elif [ "$1" = "seturl" ]; then
    if [ -n "$2" ]; then
        save_subscription_url "$2"
        printf "${GREEN}URL подписки сохранён.${RESET}\n"
    else
        echo "Использование: prosto seturl <URL>"
    fi
    exit 0
elif [ "$1" = "cleanup" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --cleanup
    exit 0
elif [ "$1" = "country" ]; then
    if [ -n "$2" ]; then
        $SCRIPT_DIR/xkeen_rotate.sh --set-forced="$2"
        $SCRIPT_DIR/xkeen_rotate.sh --country="$2" --force --verbose
    else
        $SCRIPT_DIR/xkeen_rotate.sh --list-countries
    fi
    exit 0
elif [ "$1" = "favorite" ]; then
    if [ -n "$2" ]; then
        $SCRIPT_DIR/xkeen_rotate.sh --set-favorite="$2"
    else
        FAVORITE=$(get_favorite_country)
        if [ -n "$FAVORITE" ]; then
            printf "Избранная страна: ${YELLOW}★ $FAVORITE${RESET}\n"
        else
            echo "Избранная страна не установлена."
            echo "Используйте: prosto favorite <СТРАНА>"
        fi
    fi
    exit 0
elif [ "$1" = "clearfavorite" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --clear-favorite
    exit 0
elif [ "$1" = "clearforced" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --clear-forced
    exit 0
elif [ "$1" = "openports" ]; then
    show_header
    show_section "Открытие портов"
    open_ports
    exit 0
elif [ "$1" = "closeports" ]; then
    show_header
    show_section "Закрытие портов"
    close_opened_ports
    exit 0
elif [ "$1" = "update" ]; then
    show_header
    force_check_updates
    exit 0
elif [ "$1" = "version" ]; then
    LOCAL_VERSION=$(get_local_version)
    echo "простовпн v${LOCAL_VERSION}"
    exit 0
elif [ -n "$1" ]; then
    echo "Неизвестная команда: $1"
    echo ""
    echo "Доступные команды:"
    echo "  prosto                 - интерактивное меню"
    echo "  prosto status          - показать статус"
    echo "  prosto force           - автоматическая ротация"
    echo "  prosto country <XX>    - выбрать страну принудительно"
    echo "  prosto favorite <XX>   - установить избранную страну"
    echo "  prosto clearfavorite   - сбросить избранную страну"
    echo "  prosto clearforced     - сбросить принудительный выбор"
    echo "  prosto test            - тестовое уведомление"
    echo "  prosto sync            - синхронизация (использует сохранённый URL)"
    echo "  prosto seturl <URL>    - установить URL подписки"
    echo "  prosto cleanup         - очистка файлов"
    echo "  prosto openports       - открыть порты"
    echo "  prosto closeports      - закрыть порты"
    echo "  prosto update          - проверить обновления"
    echo "  prosto version         - показать версию"
    exit 1
fi

if check_for_updates; then
    show_header
    offer_update
fi

while true; do
    show_menu
    read -r choice
    
    case $choice in
        1)
            show_header
            show_section "Статус серверов"
            show_log "$($SCRIPT_DIR/xkeen_rotate.sh --status)"
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        2)
            show_header
            show_section "Автоматическая ротация"
            $SCRIPT_DIR/xkeen_rotate.sh --force --verbose
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        3)
            forced_menu
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        4)
            favorite_menu
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        5)
            show_header
            show_section "Тестовое уведомление"
            $SCRIPT_DIR/xkeen_rotate.sh --test-notify
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        6)
            show_header
            show_section "Синхронизация подписки"
            SAVED_URL=$(get_subscription_url)
            if [ -n "$SAVED_URL" ]; then
                show_log "Синхронизация..."
                $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$SAVED_URL"
            else
                printf "${RED}URL подписки не настроен!${RESET}\n"
                printf "Используйте пункт 7 для настройки ссылки подписки.\n"
            fi
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        7)
            show_header
            show_section "Смена ссылки подписки"
            CURRENT_URL=$(get_subscription_url)
            if [ -n "$CURRENT_URL" ]; then
                printf "${GRAY}Текущая ссылка: ${CURRENT_URL}${RESET}\n\n"
            fi
            printf "${BLUE}Введите новый URL подписки: ${RESET}"
            read -r url
            if [ -n "$url" ]; then
                save_subscription_url "$url"
                printf "${GREEN}URL подписки сохранён!${RESET}\n"
                printf "${ORANGE}${LINE}${RESET}\n"
                printf "${BLUE}Выполнить синхронизацию сейчас? (y/n): ${RESET}"
                read -r dosync
                if [ "$dosync" = "y" ] || [ "$dosync" = "Y" ]; then
                $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$url"
            fi
            else
                printf "${YELLOW}URL не введён, настройка отменена.${RESET}\n"
            fi
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        8)
            show_header
            show_section "Очистка файлов"
            $SCRIPT_DIR/xkeen_rotate.sh --cleanup
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        9)
            show_header
            force_check_updates
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        10)
            show_header
            show_section "Открытие портов"
            open_ports
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        11)
            show_header
            show_section "Закрытие портов"
            close_opened_ports
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        12)
            show_header
            show_section "Перезапуск xkeen"
            printf "${YELLOW}Выполнить перезапуск xkeen? (y/n): ${RESET}"
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                show_log "Перезапуск xkeen..."
                run_xkeen_restart_with_timeout
                printf "${GREEN}✓ xkeen перезапущен${RESET}\n"
            else
                printf "${GRAY}Отменено.${RESET}\n"
            fi
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        13)
            show_header
            show_section "О системе"
            LOCAL_VERSION=$(get_local_version)
            printf "Версия: ${GRAY}${LOCAL_VERSION}${RESET}\n\n"
            printf "Разработано командой ${BLUE}${BOLD}простовпн${RESET}\n\n"
            printf "${GREEN}Покупка:${RESET} https://t.me/prstabot\n"
            printf "${GREEN}Поддержка:${RESET} https://t.me/prsta_helpbot\n"
            printf "${GREEN}GitHub:${RESET} https://github.com/andrchq/xkeen_auto\n"
            printf "${ORANGE}${LINE}${RESET}\n"
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        0)
            show_header
            printf "${GREEN}До свидания!${RESET}\n\n"
            exit 0
            ;;
        *)
            show_header
            printf "${YELLOW}Неверный выбор.${RESET}\n"
            show_countdown 2
            ;;
    esac
done
EOFPROSTO

    chmod +x "$PROSTO_PATH"
    
    if ! echo "$PATH" | grep -q "/opt/bin"; then
        if [ -f /etc/profile ]; then
            if ! grep -q "export PATH=.*\/opt\/bin" /etc/profile; then
                echo 'export PATH="/opt/bin:$PATH"' >> /etc/profile
            fi
        fi
        
        if [ -f ~/.profile ]; then
            if ! grep -q "export PATH=.*\/opt\/bin" ~/.profile; then
                echo 'export PATH="/opt/bin:$PATH"' >> ~/.profile
            fi
        fi
    fi
    
    export PATH="/opt/bin:$PATH"
}

show_header
show_section "Приветствуем вас!"

printf "Спасибо за покупку и доверие к сервису ${BLUE}${BOLD}простовпн${RESET}\n\n"

printf "Вы выбрали самый клиентоориентированный сервис:\n"
printf "— Быстрый запуск без сложности и лишних действий\n"
printf "— Максимально простая установка и настройка\n"
printf "— Поддержка, которая всегда рядом\n\n"

printf "Мы — единственный сервис, предлагающий действительно\n"
printf "простую автоматическую установку VPN на роутерах 🔥\n"
printf "Никакой магии — только технологии, сделанные для людей.\n\n"

printf "Команда ${BLUE}${BOLD}простовпн${RESET} поздравляет вас с подключением!\n"
printf "Добро пожаловать в мир защищённого и свободного интернета.\n\n"

printf "${GREEN}💬 Поддержка:${RESET} https://t.me/prsta_helpbot\n"
printf "${BLUE}🤖 Наш бот:${RESET} https://t.me/prstabot\n"
printf "${ORANGE}${LINE}${RESET}\n\n"


log "Начинаю установку..."
countdown "$TIMER_START"

if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт должен запускаться от root!"
fi

show_header
show_section "Проверка зависимостей"

MISSING_DEPS=""

check_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        MISSING_DEPS="$MISSING_DEPS $1"
    fi
}

check_dependency curl
check_dependency base64
check_dependency nc
check_dependency crontab

if [ -n "$MISSING_DEPS" ]; then
    log "Отсутствующие зависимости:$MISSING_DEPS"
    log "Устанавливаю недостающие пакеты..."
    if command -v opkg >/dev/null 2>&1; then
        opkg update
        for dep in $MISSING_DEPS; do
            case "$dep" in
                curl) opkg install curl ;;
                base64) opkg install coreutils-base64 ;;
                nc) opkg install netcat ;;
                crontab) opkg install cron ;;
            esac
        done
    else
        error "Менеджер пакетов opkg не найден! Установите зависимости вручную."
    fi
fi

log "✓ Все зависимости установлены"
sleep 1

show_header
show_section "Создание директорий"

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR/outbounds_available"
mkdir -p "$CONFIG_DIR/configs"
mkdir -p "$CONFIG_DIR/backups"

log "✓ Директории созданы"
sleep 1

show_header
show_section "Загрузка скриптов с GitHub"

if ! safe_download_file "$GITHUB_RAW/xkeen_rotate.sh" "$INSTALL_DIR/xkeen_rotate.sh"; then
    error "Не удалось скачать xkeen_rotate.sh"
fi

if ! safe_download_file "$GITHUB_RAW/xkeen_sync.sh" "$INSTALL_DIR/xkeen_sync.sh"; then
    error "Не удалось скачать xkeen_sync.sh"
fi

if ! safe_download_file "$GITHUB_RAW/network_watchdog.sh" "$INSTALL_DIR/network_watchdog.sh"; then
    error "Не удалось скачать network_watchdog.sh"
fi

if ! safe_download_file "$GITHUB_RAW/startup_notify.sh" "$INSTALL_DIR/startup_notify.sh"; then
    error "Не удалось скачать startup_notify.sh"
fi

if ! safe_download_file "$GITHUB_RAW/xkeen_restart.sh" "$INSTALL_DIR/xkeen_restart.sh"; then
    error "Не удалось скачать xkeen_restart.sh"
fi

# Скачиваем файл версии
if safe_download_file "$GITHUB_RAW/VERSION" "$INSTALL_DIR/.version"; then
    log "✓ Версия: $(cat $INSTALL_DIR/.version)"
else
    if [ -f "$INSTALL_DIR/.version" ]; then
        BACKUP_PATH="${INSTALL_DIR}/.version.bak.$(date +%s)"
        cp "$INSTALL_DIR/.version" "$BACKUP_PATH" 2>/dev/null
    fi
    echo "1.0.0" > "$INSTALL_DIR/.version"
fi

log "✓ Основные скрипты загружены"
countdown "$TIMER_SCRIPTS_LOADED"

show_header
show_section "Загрузка init-скриптов"

INIT_DIR="/opt/etc/init.d"
mkdir -p "$INIT_DIR"

if safe_download_file "$GITHUB_RAW/S99startup_notify" "$INIT_DIR/S99startup_notify"; then
    chmod +x "$INIT_DIR/S99startup_notify"
    log "✓ S99startup_notify установлен"
else
    log "⚠ Не удалось скачать S99startup_notify (продолжаем)"
fi

if safe_download_file "$GITHUB_RAW/S99xkeenstart" "$INIT_DIR/S99xkeenstart"; then
    chmod +x "$INIT_DIR/S99xkeenstart"
    log "✓ S99xkeenstart установлен"
else
    log "⚠ Не удалось скачать S99xkeenstart (продолжаем)"
fi

# Удаляем старые init-скрипты если существуют
[ -f "$INIT_DIR/S01notify" ] && rm -f "$INIT_DIR/S01notify"
[ -f "$INIT_DIR/S99xkeenrestart" ] && rm -f "$INIT_DIR/S99xkeenrestart"

log "✓ Init-скрипты установлены"
countdown "$TIMER_INIT_SCRIPTS"

show_header
show_section "Установка прав доступа"

chmod +x "$INSTALL_DIR/xkeen_rotate.sh"
chmod +x "$INSTALL_DIR/xkeen_sync.sh"
chmod +x "$INSTALL_DIR/network_watchdog.sh"
chmod +x "$INSTALL_DIR/startup_notify.sh"
chmod +x "$INSTALL_DIR/xkeen_restart.sh"

log "✓ Права установлены"
countdown "$TIMER_PERMISSIONS"

show_header
show_section "Установка команды prosto"

create_prosto_command

log "✓ Команда 'prosto' установлена в /opt/bin"
printf "${BLUE}   Используйте команду: ${BOLD}prosto${RESET}\n"
printf "${GRAY}   (если команда не найдена, перезапустите сессию или выполните: export PATH=\"/opt/bin:\$PATH\")${RESET}\n"
countdown "$TIMER_PROSTO_COMMAND"

# 1. Установка конфигураций Xray без вопроса
if command -v xkeen >/dev/null 2>&1; then
    show_header
    show_section "Установка конфигураций Xray"
    
    printf "${GRAY}Будут установлены:${RESET}\n"
    printf "  ${CYAN}• Блокировка рекламы и аналитики${RESET}\n"
    printf "  ${CYAN}• Умная маршрутизация (RU напрямую, заблокированное через прокси)${RESET}\n"
    printf "  ${CYAN}• Оптимизация для Telegram, Discord, Google, ChatGPT${RESET}\n"
    printf "  ${CYAN}• Блокировка QUIC для стабильности${RESET}\n"
    printf "  ${CYAN}• BitTorrent напрямую (ЗАПРЕЩЕНО использовать через прокси)${RESET}\n"
    printf "${ORANGE}${LINE}${RESET}\n\n"
    
    BACKUP_SUFFIX=$(date +%s)
    
    if safe_download_file "$GITHUB_RAW/03_inbounds.json" "$CONFIG_DIR/configs/03_inbounds.json"; then
        log "✓ 03_inbounds.json установлен"
    else
        log "⚠ Не удалось загрузить 03_inbounds.json"
    fi
    
    if safe_download_file "$GITHUB_RAW/05_routing.json" "$CONFIG_DIR/configs/05_routing.json"; then
        log "✓ 05_routing.json установлен"
    else
        log "⚠ Не удалось загрузить 05_routing.json"
    fi
    
    printf "${GREEN}✓ Конфигурации inbound и routing установлены${RESET}\n"
    printf "${GRAY}   Перезапуск Xray будет выполнен после настройки подписки${RESET}\n"
    CONFIGS_INSTALLED=1
    countdown "$TIMER_XRAY_CONFIGS"
fi

# 2. Обязательная настройка Telegram
show_header
show_section "Настройка Telegram уведомлений"
printf "%s\n" "${GRAY}Для получения ID топика напишите администратору в @prsta_helpbot${RESET}"
printf "%s\n" "${GRAY}Администратор предоставит вам индивидуальный ID топика для получения уведомлений${RESET}"
printf "%s\n\n" "${ORANGE}${LINE}${RESET}"

TG_TOPIC_ID=""
while [ -z "$TG_TOPIC_ID" ]; do
    printf "%s" "${BLUE}Введите ID топика Telegram: ${RESET}"
    read -r TG_TOPIC_ID
    if [ -z "$TG_TOPIC_ID" ]; then
        printf "%s\n" "${RED}ID топика не может быть пустым!${RESET}"
    fi
done

# Безопасная замена TG_TOPIC_ID в файлах
set_telegram_id() {
    _FILE="$1"
    _TMP="${_FILE}.tmp.$$"
    if [ -f "$_FILE" ]; then
        sed "s/TG_TOPIC_ID=\"[^\"]*\"/TG_TOPIC_ID=\"$TG_TOPIC_ID\"/" "$_FILE" > "$_TMP" && mv "$_TMP" "$_FILE"
        log "✓ Настроен: $(basename "$_FILE")"
    else
        log "⚠ Файл не найден: $_FILE"
    fi
}

set_telegram_id "$INSTALL_DIR/xkeen_rotate.sh"
set_telegram_id "$INSTALL_DIR/network_watchdog.sh"
set_telegram_id "$INSTALL_DIR/startup_notify.sh"
set_telegram_id "$INSTALL_DIR/xkeen_restart.sh"

log "✓ Telegram ID настроен во всех скриптах"
printf "%s\n\n" "${ORANGE}${LINE}${RESET}"

# 4. Автоматическая отправка тестового уведомления
show_section "Отправка тестового уведомления"
log "Отправляю тестовое уведомление..."
cd "$INSTALL_DIR"
if ./xkeen_rotate.sh --test-notify; then
    printf "${GREEN}✓ Тестовое уведомление отправлено успешно${RESET}\n"
else
    printf "${RED}✗ Ошибка отправки тестового уведомления${RESET}\n"
    printf "${YELLOW}Проверьте правильность ID топика${RESET}\n"
fi
printf "${ORANGE}${LINE}${RESET}\n"
countdown "$TIMER_TELEGRAM_TEST"

# 5. Обязательный ввод URL подписки
SUBSCRIPTION_FILE="$INSTALL_DIR/.subscription_url"
show_header
show_section "Настройка подписки"

SUBSCRIPTION_URL=""
while [ -z "$SUBSCRIPTION_URL" ]; do
    printf "%s" "${BLUE}Введите URL подписки на серверы: ${RESET}"
    read -r SUBSCRIPTION_URL
    if [ -z "$SUBSCRIPTION_URL" ]; then
        printf "%s\n" "${RED}URL подписки не может быть пустым!${RESET}"
    fi
done

# Сохраняем URL подписки для будущего использования
echo "$SUBSCRIPTION_URL" > "$SUBSCRIPTION_FILE"
log "URL подписки сохранён в $SUBSCRIPTION_FILE"

show_section "Загрузка серверов из подписки"
log "Загружаю серверы из подписки..."

cd "$INSTALL_DIR"
if ./xkeen_sync.sh "$SUBSCRIPTION_URL"; then
    log "✓ Серверы загружены"
    countdown "$TIMER_SUBSCRIPTION_LOAD"
    
    show_section "Доступные серверы"
    ./xkeen_rotate.sh --status
    
    countdown "$TIMER_SERVERS_LIST"
    
    # 6. Обязательная активация сервера с лучшим ping
    show_section "Активация сервера"
    log "Выбираю сервер с наименьшим ping..."
    printf "${BLUE}Измерение ping до всех серверов...${RESET}\n"
    echo ""
    ACTIVATE_RESULT=0
    ./xkeen_rotate.sh --force --verbose || ACTIVATE_RESULT=$?
    
    if [ $ACTIVATE_RESULT -eq 0 ]; then
        log "✓ Сервер активирован"
        SERVER_ACTIVATED=1
        
        # Отправляем уведомление о первой активации
        ACTIVATED_CC=""
        ACTIVATED_TGT=""
        [ -f "/tmp/xkeen_current_country" ] && ACTIVATED_CC=$(cat "/tmp/xkeen_current_country" 2>/dev/null)
        [ -f "$CONFIG_DIR/configs/04_outbounds.target" ] && ACTIVATED_TGT=$(head -n1 "$CONFIG_DIR/configs/04_outbounds.target" 2>/dev/null | tr -d '\r\n')
        
        if [ -n "$TG_TOPIC_ID" ] && [ -n "$ACTIVATED_CC" ]; then
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
            NOTIFY_MSG="🟩 <b>ПЕРВИЧНАЯ НАСТРОЙКА ЗАВЕРШЕНА</b>

<b>Система успешно настроена!</b>
Активирован сервер: $ACTIVATED_CC ($ACTIVATED_TGT)

⏰ $TIMESTAMP"
            curl -s -X POST "https://api.telegram.org/bot7305187909:AAHGkLCVpGIlg70AxWT2auyjOrhoAJkof1U/sendMessage" \
                -d "chat_id=-1002517339071" \
                -d "message_thread_id=$TG_TOPIC_ID" \
                -d "text=$NOTIFY_MSG" \
                -d "parse_mode=HTML" >/dev/null 2>&1
            log "Уведомление о первой активации отправлено"
        fi
    else
        log "⚠ Не удалось активировать сервер"
    fi
    countdown "$TIMER_SERVER_ACTIVATE"
    
    if [ "$CONFIGS_INSTALLED" -eq 1 ] && [ -f "$CONFIG_DIR/configs/04_outbounds.json" ]; then
        show_section "Перезапуск Xray"
        printf "${BLUE}Все конфигурации установлены. Перезапускаю Xray...${RESET}\n"
        echo ""
        
        printf "${GRAY}Ожидание завершения перезапуска (10 секунд)...${RESET}\n"
        
        RESTART_LOG="/tmp/xray_restart_$$.log"
        xkeen -restart > "$RESTART_LOG" 2>&1
        
        if [ -f "$RESTART_LOG" ]; then
            echo ""
            cat "$RESTART_LOG"
            echo ""
            
            if cat "$RESTART_LOG" | grep -q "запущен"; then
                printf "${GREEN}${BOLD}✓ Xray успешно перезапущен! Все конфигурации применены.${RESET}\n"
                log "Xray перезапущен успешно с новыми конфигурациями"
            else
                printf "${YELLOW}⚠ Не удалось подтвердить успешный запуск${RESET}\n"
            fi
            rm -f "$RESTART_LOG"
        else
            printf "${YELLOW}⚠ Не удалось получить вывод команды${RESET}\n"
        fi
        countdown "$TIMER_XRAY_RESTART"
    fi
else
    show_section "Ошибка загрузки подписки"
    printf "${RED}⚠ Не удалось загрузить подписку${RESET}\n"
    printf "${YELLOW}Проверьте правильность URL и повторите установку${RESET}\n"
    exit 1
fi

# 7-10. Автоматическая настройка cron и мониторинга
show_section "Настройка автоматической ротации"
log "Настраиваю автоматическую проверку доступности серверов..."

CRON_SCHEDULE="*/2 * * * *"  # Каждые 2 минуты

TEMP_CRON=$(mktemp)
crontab -l > "$TEMP_CRON" 2>/dev/null || true
grep -v "xkeen_rotate.sh" "$TEMP_CRON" > "$TEMP_CRON.new" 2>/dev/null || true
mv "$TEMP_CRON.new" "$TEMP_CRON"

echo "" >> "$TEMP_CRON"
echo "# Автоматическая ротация серверов" >> "$TEMP_CRON"
echo "$CRON_SCHEDULE $INSTALL_DIR/xkeen_rotate.sh >/dev/null 2>&1" >> "$TEMP_CRON"

# Ежедневная синхронизация подписки в 3:00
echo "0 3 * * * [ -f $INSTALL_DIR/.subscription_url ] && $INSTALL_DIR/xkeen_rotate.sh --sync-url=\"\$(cat $INSTALL_DIR/.subscription_url)\" >/dev/null 2>&1" >> "$TEMP_CRON"

# 9. Автозапуск - ДА
echo "@reboot sleep 120 && $INSTALL_DIR/xkeen_rotate.sh >/dev/null 2>&1" >> "$TEMP_CRON"

crontab "$TEMP_CRON"
rm -f "$TEMP_CRON"
/etc/init.d/cron restart >/dev/null 2>&1 || true

log "✓ Автоматическая ротация настроена (интервал: 2 минуты)"
log "✓ Автозапуск настроен через cron (@reboot)"
countdown "$TIMER_CRON_SETUP"

# 10. Система мониторинга - ДА
show_section "Настройка системы автоматизации"

# Включаем init-скрипты автозапуска
if [ -f "$INIT_DIR/S99xkeenstart" ]; then
    log "✓ Автозапуск Xray включен (S99xkeenstart)"
fi

if [ -f "$INIT_DIR/S99startup_notify" ]; then
    log "✓ Уведомления о старте включены (S99startup_notify)"
fi

# Настраиваем cron для мониторинга
TEMP_CRON=$(mktemp)
crontab -l > "$TEMP_CRON" 2>/dev/null || true
grep -v "network_watchdog.sh" "$TEMP_CRON" > "$TEMP_CRON.new" 2>/dev/null || true
mv "$TEMP_CRON.new" "$TEMP_CRON"

echo "" >> "$TEMP_CRON"
echo "# Мониторинг интернета и автовосстановление" >> "$TEMP_CRON"
echo "*/5 * * * * $INSTALL_DIR/network_watchdog.sh >/dev/null 2>&1" >> "$TEMP_CRON"

crontab "$TEMP_CRON"
rm -f "$TEMP_CRON"
/etc/init.d/cron restart >/dev/null 2>&1 || true

log "✓ Мониторинг сети настроен (проверка каждые 5 минут)"
log "✓ Полная система автоматизации активирована"
countdown "$TIMER_MONITORING_SETUP"

# ============ Открытие портов ============
show_header
show_section "Настройка портов прокси"

PORTS_TO_OPEN="80,443,50000:50030"
OPENED_PORTS_FILE="$INSTALL_DIR/.opened_ports"

# Функция открытия портов с таймаутом
open_ports_with_timeout() {
    _TIMEOUT=15
    _OUTPUT_FILE="/tmp/xkeen_ports_output_$$"
    _PID_FILE="/tmp/xkeen_ports_pid_$$"
    
    # Запускаем команду в фоне
    (xkeen -ap "$PORTS_TO_OPEN" > "$_OUTPUT_FILE" 2>&1; echo $? > "${_OUTPUT_FILE}.exit") &
    _CMD_PID=$!
    echo "$_CMD_PID" > "$_PID_FILE"
    
    # Ждём завершения с таймаутом
    _WAITED=0
    while [ $_WAITED -lt $_TIMEOUT ]; do
        if ! kill -0 "$_CMD_PID" 2>/dev/null; then
            # Процесс завершился
            wait "$_CMD_PID" 2>/dev/null
            if [ -f "${_OUTPUT_FILE}.exit" ]; then
                _EXIT_CODE=$(cat "${_OUTPUT_FILE}.exit")
                cat "$_OUTPUT_FILE" 2>/dev/null
                rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit" "$_PID_FILE"
                return $_EXIT_CODE
            fi
            cat "$_OUTPUT_FILE" 2>/dev/null
            rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit" "$_PID_FILE"
            return 0
        fi
        sleep 1
        _WAITED=$((_WAITED + 1))
        printf "\r${GRAY}Ожидание... %d/%d сек${RESET}" "$_WAITED" "$_TIMEOUT"
    done
    
    # Таймаут - убиваем процесс
    printf "\n${YELLOW}⚠ Таймаут! Команда не завершилась за %d секунд${RESET}\n" "$_TIMEOUT"
    kill -9 "$_CMD_PID" 2>/dev/null
    wait "$_CMD_PID" 2>/dev/null
    rm -f "$_OUTPUT_FILE" "${_OUTPUT_FILE}.exit" "$_PID_FILE"
    return 124  # Код таймаута
}

# Функция перезапуска xkeen
restart_xkeen() {
    log "Перезапуск xkeen..."
    _RESTART_OUTPUT=$(xkeen -restart 2>&1)
    echo "$_RESTART_OUTPUT"
    
    # Проверяем успешность запуска
    if echo "$_RESTART_OUTPUT" | grep -q "Прокси-клиент запущен"; then
        log "✓ xkeen успешно перезапущен"
        return 0
    else
        log "⚠ Ожидание запуска xkeen..."
        sleep 3
        return 0
    fi
}

if command -v xkeen >/dev/null 2>&1; then
    log "Открываю порты для прокси-клиента..."
    printf "${BLUE}Команда: xkeen -ap $PORTS_TO_OPEN${RESET}\n"
    printf "${GRAY}Таймаут: 15 секунд${RESET}\n"
    echo ""
    
    MAX_ATTEMPTS=3
    ATTEMPT=1
    PORTS_SUCCESS=0
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ $PORTS_SUCCESS -eq 0 ]; do
        log "Попытка $ATTEMPT из $MAX_ATTEMPTS..."
        
        PORTS_OUTPUT=$(open_ports_with_timeout)
        PORTS_EXIT_CODE=$?
        
        echo ""
        
        if [ $PORTS_EXIT_CODE -eq 124 ]; then
            # Таймаут - перезапускаем xkeen
            log "Команда зависла, перезапускаю xkeen..."
            echo ""
            restart_xkeen
            echo ""
            ATTEMPT=$((ATTEMPT + 1))
            continue
        elif [ $PORTS_EXIT_CODE -eq 0 ]; then
            # Успех
            echo "$PORTS_OUTPUT"
            echo ""
            
            # Парсим вывод для получения списка новых портов
            NEW_PORTS=$(echo "$PORTS_OUTPUT" | awk '/Новые порты прокси-клиента/{found=1; next} /Прокси-клиент уже работает/{found=0} found && /^[[:space:]]*[0-9]/{gsub(/^[[:space:]]+/, ""); print}' | tr '\n' ',' | sed 's/,$//')
            
            if [ -n "$NEW_PORTS" ]; then
                echo "$NEW_PORTS" > "$OPENED_PORTS_FILE"
                log "✓ Порты открыты успешно"
                log "✓ Новые порты сохранены: $NEW_PORTS"
            else
                echo "" > "$OPENED_PORTS_FILE"
                log "✓ Все порты уже были открыты ранее"
            fi
            PORTS_SUCCESS=1
        else
            # Другая ошибка
            log "⚠ Ошибка при открытии портов (код: $PORTS_EXIT_CODE)"
            echo "$PORTS_OUTPUT"
            ATTEMPT=$((ATTEMPT + 1))
            
            if [ $ATTEMPT -le $MAX_ATTEMPTS ]; then
                log "Перезапускаю xkeen перед повторной попыткой..."
                restart_xkeen
                echo ""
            fi
        fi
    done
    
    if [ $PORTS_SUCCESS -eq 0 ]; then
        log "⚠ Не удалось открыть порты после $MAX_ATTEMPTS попыток"
    fi
    
    countdown "$TIMER_PORTS_OPEN"
else
    log "⚠ xkeen не найден, пропускаю настройку портов"
    sleep 1
fi

show_header
show_section "Установка завершена!"
log "✓ Установка успешно завершена!"

printf "\n${CYAN}Основные команды:${RESET}\n"
printf "  ${BLUE}prosto${RESET}                   - Интерактивное меню\n"
printf "  ${BLUE}prosto status${RESET}            - Показать статус серверов\n"
printf "  ${BLUE}prosto force${RESET}             - Принудительная ротация\n"
printf "  ${BLUE}prosto test${RESET}              - Тест Telegram уведомлений\n"
printf "  ${BLUE}prosto update${RESET}            - Проверить обновления\n"

printf "\n${ORANGE}${LINE}${RESET}\n\n"
printf "${GREEN}Система автоматической ротации активна!${RESET}\n"
printf "\n${ORANGE}${LINE}${RESET}\n"
printf "${BLUE}Покупка:${RESET} https://t.me/prstabot\n"
printf "${BLUE}Поддержка:${RESET} https://t.me/prsta_helpbot\n"
printf "${ORANGE}${LINE}${RESET}\n\n"

# 11. Автоматическое удаление установщика
if [ -f "$0" ] && [ "$0" != "/dev/stdin" ]; then
    INSTALLER_PATH="$0"
    rm -f "$INSTALLER_PATH"
    log "✓ Установочный скрипт удалён"
fi

show_header
printf "${GREEN}${BOLD}✓ Готово!${RESET}\n"
printf "${ORANGE}${LINE}${RESET}\n\n"
printf "Используйте команду: ${BLUE}${BOLD}prosto${RESET}\n"
printf "${GRAY}(Если команда не найдена: export PATH=\"/opt/bin:\$PATH\")${RESET}\n\n"
