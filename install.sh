#!/bin/sh

set -e

INSTALL_DIR="/opt/root/scripts"
CONFIG_DIR="/opt/etc/xray"
GITHUB_RAW="https://raw.githubusercontent.com/andrchq/xkeen_auto/main"
USE_DIALOG=0
DIALOG_CMD=""
CONFIGS_INSTALLED=0
SERVER_ACTIVATED=0

GRAY="\033[90m"
BLUE="\033[94m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
RESET="\033[0m"
BOLD="\033[1m"

check_and_install_whiptail() {
    if command -v whiptail >/dev/null 2>&1; then
        DIALOG_CMD="whiptail"
        USE_DIALOG=1
        return 0
    fi
    
    if command -v dialog >/dev/null 2>&1; then
        DIALOG_CMD="dialog"
        USE_DIALOG=1
        return 0
    fi
    
    echo ""
    printf "${YELLOW}⚡ Устанавливаю whiptail для графического интерфейса...${RESET}\n"
    echo ""
    
    if command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1
        if opkg install whiptail >/dev/null 2>&1; then
            DIALOG_CMD="whiptail"
            USE_DIALOG=1
            printf "${GREEN}✓ whiptail установлен${RESET}\n"
            sleep 1
            # Продолжаем выполнение с уже установленным whiptail
            # (перезапуск не нужен, переменные уже установлены)
        else
            printf "${YELLOW}⚠ Не удалось установить whiptail, продолжаю в текстовом режиме${RESET}\n"
            sleep 2
        fi
    fi
}

show_header() {
    clear
    printf "${GRAY}╔══════════════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${GRAY}║${RESET}${BLUE}${BOLD}                                    простовпн                                          ${RESET}${GRAY}║${RESET}\n"
    printf "${GRAY}╚══════════════════════════════════════════════════════════════════════════════════════╝${RESET}\n"
    echo ""
}

show_section() {
    TITLE="$1"
    printf "${GRAY}╔════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${GRAY}║${RESET} ${BLUE}простовпн | ${BOLD}${TITLE}${RESET}$(printf '%*s' $((57 - ${#TITLE})) '')${GRAY}║${RESET}\n"
    printf "${GRAY}╚════════════════════════════════════════════════════════════╝${RESET}\n"
    echo ""
}

countdown() {
    SECONDS=${1:-5}
    printf "${GRAY}"
    for i in $(seq $SECONDS -1 1); do
        printf "\r   [$i] "
        sleep 1
    done
    printf "\r        \r${RESET}"
}

log() {
    printf "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${RESET}\n"
}

error() {
    printf "${RED}[ОШИБКА] $*${RESET}\n" >&2
    exit 1
}

dialog_msgbox() {
    TITLE="$1"
    MSG="$2"
    if [ "$USE_DIALOG" -eq 1 ]; then
        $DIALOG_CMD --title "простовпн" --msgbox "$MSG" 15 70
    else
        show_header
        show_section "$TITLE"
        echo "$MSG"
        echo ""
        printf "${YELLOW}Нажмите Enter для продолжения...${RESET}"
        read -r dummy
    fi
}

dialog_yesno() {
    TITLE="$1"
    MSG="$2"
    if [ "$USE_DIALOG" -eq 1 ]; then
        $DIALOG_CMD --title "простовпн" --yesno "$MSG" 15 70
        return $?
    else
        show_header
        show_section "$TITLE"
        echo "$MSG"
        echo ""
        printf "${BLUE}Ваш выбор (y/n): ${RESET}"
        read -r answer
        [ "$answer" = "y" ] || [ "$answer" = "Y" ]
        return $?
    fi
}

dialog_inputbox() {
    TITLE="$1"
    MSG="$2"
    DEFAULT="$3"
    if [ "$USE_DIALOG" -eq 1 ]; then
        RESULT=$($DIALOG_CMD --title "простовпн" --inputbox "$MSG" 15 70 "$DEFAULT" 3>&1 1>&2 2>&3)
        echo "$RESULT"
    else
        show_header
        show_section "$TITLE"
        echo "$MSG"
        echo ""
        printf "${BLUE}> ${RESET}"
        read -r result
        echo "$result"
    fi
}

dialog_menu() {
    TITLE="$1"
    MSG="$2"
    shift 2
    if [ "$USE_DIALOG" -eq 1 ]; then
        RESULT=$($DIALOG_CMD --title "простовпн" --menu "$MSG" 20 70 10 "$@" 3>&1 1>&2 2>&3)
        echo "$RESULT"
    else
        show_header
        show_section "$TITLE"
        echo "$MSG"
        echo ""
        i=1
        while [ $# -gt 0 ]; do
            printf "${BLUE}  $1)${RESET} $2\n"
            shift 2
        done
        echo ""
        printf "${BLUE}Выберите вариант: ${RESET}"
        read -r result
        echo "$result"
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

show_header() {
    clear
    printf "${GRAY}╔══════════════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${GRAY}║${RESET}${BLUE}${BOLD}                                    простовпн                                          ${RESET}${GRAY}║${RESET}\n"
    printf "${GRAY}╚══════════════════════════════════════════════════════════════════════════════════════╝${RESET}\n"
    echo ""
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
        cat "$VERSION_FILE" 2>/dev/null | tr -d '\n\r '
    else
        echo "0.0.0"
    fi
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
    REMOTE_VERSION=$(curl -sL --max-time 5 "$GITHUB_RAW/VERSION" 2>/dev/null | tr -d '\n\r ')
    [ -z "$REMOTE_VERSION" ] && return 1
    version_greater "$LOCAL_VERSION" "$REMOTE_VERSION" && return 0
    return 1
}

offer_update() {
    LOCAL_VERSION=$(get_local_version)
    REMOTE_VERSION=$(curl -sL --max-time 5 "$GITHUB_RAW/VERSION" 2>/dev/null | tr -d '\n\r ')
    printf "\n${YELLOW}╔════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${YELLOW}║${RESET}  ${BOLD}🔄 Доступно обновление!${RESET}                                   ${YELLOW}║${RESET}\n"
    printf "${YELLOW}╚════════════════════════════════════════════════════════════╝${RESET}\n"
    printf "\n${GRAY}Текущая версия: ${LOCAL_VERSION}${RESET}\n"
    printf "${GREEN}Новая версия:   ${REMOTE_VERSION}${RESET}\n"
    printf "\n${BLUE}Обновить систему сейчас? (y/n): ${RESET}"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        run_update
    fi
}

run_update() {
    printf "\n${GREEN}Запускаю обновление...${RESET}\n\n"
    rm -f "$UPDATE_CHECK_FILE"
    curl -sSL "$GITHUB_RAW/install.sh" | sh
    exit 0
}

open_ports() {
    PORTS_TO_OPEN="80,443,50000:50030"
    printf "${BLUE}Порты для открытия: ${PORTS_TO_OPEN}${RESET}\n\n"
    printf "${YELLOW}Открыть эти порты? (y/n): ${RESET}"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        printf "\n${BLUE}Открываю порты...${RESET}\n"
        printf "${GRAY}Это может занять около 20 секунд...${RESET}\n\n"
        if command -v xkeen >/dev/null 2>&1; then
            PORTS_OUTPUT=$(xkeen -ap "$PORTS_TO_OPEN" 2>&1)
            RESULT=$?
            echo "$PORTS_OUTPUT"
            echo ""
            if [ $RESULT -eq 0 ]; then
                NEW_PORTS=$(echo "$PORTS_OUTPUT" | awk '/Новые порты прокси-клиента/{found=1; next} /Прокси-клиент уже работает/{found=0} found && /^[[:space:]]*[0-9]/{gsub(/^[[:space:]]+/, ""); print}' | tr '\n' ',' | sed 's/,$//')
                if [ -n "$NEW_PORTS" ]; then
                    echo "$NEW_PORTS" > "$OPENED_PORTS_FILE"
                    printf "${GREEN}✓ Порты успешно открыты!${RESET}\n"
                    printf "${GRAY}Новые порты сохранены: $NEW_PORTS${RESET}\n"
                else
                    printf "${GREEN}✓ Все порты уже были открыты ранее${RESET}\n"
                fi
            else
                printf "${RED}Ошибка при открытии портов (код: $RESULT)${RESET}\n"
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
    printf "${BLUE}${BOLD}Избранная страна${RESET}\n\n"
    FAVORITE=$(get_favorite_country)
    if [ -n "$FAVORITE" ]; then
        printf "Текущая избранная: ${YELLOW}★ $FAVORITE${RESET}\n\n"
    else
        printf "${GRAY}Избранная страна не установлена.${RESET}\n\n"
    fi
    printf "${BLUE}1)${RESET} Установить избранную страну\n"
    printf "${BLUE}2)${RESET} Сбросить избранную страну\n"
    printf "${BLUE}0)${RESET} Назад\n"
    echo ""
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
    printf "${BLUE}${BOLD}Выбрать страну принудительно${RESET}\n\n"
    FORCED=$(get_forced_country)
    if [ -n "$FORCED" ]; then
        printf "Текущий выбор: ${BLUE}⚡ $FORCED${RESET}\n"
        printf "${GRAY}(сбросится через 5 минут или при недоступности)${RESET}\n\n"
    else
        printf "${GRAY}Принудительный выбор не установлен.${RESET}\n\n"
    fi
    printf "${BLUE}1)${RESET} Выбрать страну принудительно\n"
    printf "${BLUE}2)${RESET} Сбросить принудительный выбор\n"
    printf "${BLUE}0)${RESET} Назад\n"
    echo ""
    printf "${BLUE}Выберите действие: ${RESET}"
    read -r choice
    case $choice in
        1) show_header; set_forced_interactive ;;
        2) clear_forced ;;
        0|*) return ;;
    esac
}

force_check_updates() {
    printf "${BLUE}Проверка обновлений...${RESET}\n\n"
    rm -f "$UPDATE_CHECK_FILE"
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        printf "${RED}Нет подключения к интернету${RESET}\n"
        return 1
    fi
    LOCAL_VERSION=$(get_local_version)
    printf "Текущая версия: ${BLUE}${LOCAL_VERSION}${RESET}\n"
    printf "Проверяю удалённую версию... "
    REMOTE_VERSION=$(curl -sL --max-time 5 "$GITHUB_RAW/VERSION" 2>/dev/null | tr -d '\n\r ')
    if [ -z "$REMOTE_VERSION" ]; then
        printf "${RED}ошибка загрузки${RESET}\n"
        return 1
    fi
    printf "${GREEN}${REMOTE_VERSION}${RESET}\n\n"
    if version_greater "$LOCAL_VERSION" "$REMOTE_VERSION"; then
        printf "${YELLOW}Доступна новая версия: ${REMOTE_VERSION}${RESET}\n\n"
        printf "${BLUE}Обновить сейчас? (y/n): ${RESET}"
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            run_update
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
    printf "${BLUE}${BOLD}Управление системой ротации серверов${RESET} ${GRAY}v${LOCAL_VERSION}${RESET}\n"
    if [ -n "$FAVORITE" ] || [ -n "$FORCED" ]; then
        [ -n "$FAVORITE" ] && printf "${YELLOW}★ Избранная: $FAVORITE${RESET}  "
        [ -n "$FORCED" ] && printf "${BLUE}⚡ Принудительная: $FORCED${RESET}"
        echo ""
    fi
    echo ""
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
    printf "${BLUE}12)${RESET} О системе\n"
    printf "${BLUE}0)${RESET} Выход\n"
    echo ""
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
    printf "${BLUE}${BOLD}Открытие портов${RESET}\n\n"
    open_ports
    exit 0
elif [ "$1" = "closeports" ]; then
    show_header
    printf "${BLUE}${BOLD}Закрытие портов${RESET}\n\n"
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
            $SCRIPT_DIR/xkeen_rotate.sh --status
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        2)
            show_header
            printf "${BLUE}Автоматическая ротация серверов...${RESET}\n\n"
            $SCRIPT_DIR/xkeen_rotate.sh --force --verbose
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        3)
            forced_menu
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        4)
            favorite_menu
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        5)
            show_header
            $SCRIPT_DIR/xkeen_rotate.sh --test-notify
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        6)
            show_header
            SAVED_URL=$(get_subscription_url)
            if [ -n "$SAVED_URL" ]; then
                printf "${BLUE}Синхронизация подписки...${RESET}\n\n"
                $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$SAVED_URL"
            else
                printf "${RED}URL подписки не настроен!${RESET}\n"
                printf "Используйте пункт 7 для настройки ссылки подписки.\n"
            fi
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        7)
            show_header
            CURRENT_URL=$(get_subscription_url)
            if [ -n "$CURRENT_URL" ]; then
                printf "${GRAY}Текущая ссылка: ${CURRENT_URL}${RESET}\n\n"
            fi
            printf "${BLUE}Введите новый URL подписки: ${RESET}"
            read -r url
            if [ -n "$url" ]; then
                save_subscription_url "$url"
                printf "${GREEN}URL подписки сохранён!${RESET}\n"
                echo ""
                printf "${BLUE}Выполнить синхронизацию сейчас? (y/n): ${RESET}"
                read -r dosync
                if [ "$dosync" = "y" ] || [ "$dosync" = "Y" ]; then
                    $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$url"
                fi
            else
                printf "${YELLOW}URL не введён, настройка отменена.${RESET}\n"
            fi
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        8)
            show_header
            printf "${BLUE}Очистка лишних файлов...${RESET}\n\n"
            $SCRIPT_DIR/xkeen_rotate.sh --cleanup
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        9)
            show_header
            force_check_updates
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        10)
            show_header
            printf "${BLUE}${BOLD}Открытие портов${RESET}\n\n"
            open_ports
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        11)
            show_header
            printf "${BLUE}${BOLD}Закрытие портов${RESET}\n\n"
            close_opened_ports
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        12)
            show_header
            LOCAL_VERSION=$(get_local_version)
            printf "${BLUE}${BOLD}Система автоматической ротации прокси-серверов${RESET}\n"
            printf "${GRAY}Версия: ${LOCAL_VERSION}${RESET}\n\n"
            printf "Разработано командой ${BLUE}${BOLD}простовпн${RESET}\n\n"
            printf "${GREEN}Покупка:${RESET} https://t.me/prstabot\n"
            printf "${GREEN}Поддержка:${RESET} https://t.me/prsta_helpbot\n"
            printf "${GREEN}GitHub:${RESET} https://github.com/andrchq/xkeen_auto\n"
            echo ""
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
            printf "${YELLOW}Неверный выбор. Попробуйте снова.${RESET}\n"
            sleep 2
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

check_and_install_whiptail

show_header
printf "${BLUE}${BOLD}xkeen_rotate - Установка${RESET}\n"
printf "${BLUE}Автоматическая ротация прокси-серверов для Xray/Xkeen${RESET}\n"
echo ""
printf "Разработано командой ${BLUE}${BOLD}простовпн${RESET}\n"
printf "Для клиентов ${BLUE}https://t.me/prstabot${RESET}\n"
echo ""
printf "${GREEN}💬 Служба поддержки:${RESET} https://t.me/prsta_helpbot\n"
echo ""

log "Начинаю установку..."
sleep 2

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

if ! curl -sSL "$GITHUB_RAW/xkeen_rotate.sh" -o "$INSTALL_DIR/xkeen_rotate.sh"; then
    error "Не удалось скачать xkeen_rotate.sh"
fi

if ! curl -sSL "$GITHUB_RAW/xkeen_sync.sh" -o "$INSTALL_DIR/xkeen_sync.sh"; then
    error "Не удалось скачать xkeen_sync.sh"
fi

if ! curl -sSL "$GITHUB_RAW/network_watchdog.sh" -o "$INSTALL_DIR/network_watchdog.sh"; then
    error "Не удалось скачать network_watchdog.sh"
fi

if ! curl -sSL "$GITHUB_RAW/startup_notify.sh" -o "$INSTALL_DIR/startup_notify.sh"; then
    error "Не удалось скачать startup_notify.sh"
fi

if ! curl -sSL "$GITHUB_RAW/xkeen_restart.sh" -o "$INSTALL_DIR/xkeen_restart.sh"; then
    error "Не удалось скачать xkeen_restart.sh"
fi

# Скачиваем файл версии
if curl -sSL "$GITHUB_RAW/VERSION" -o "$INSTALL_DIR/.version" 2>/dev/null; then
    log "✓ Версия: $(cat $INSTALL_DIR/.version)"
else
    echo "1.0.0" > "$INSTALL_DIR/.version"
fi

log "✓ Основные скрипты загружены"
countdown 2

show_header
show_section "Загрузка init-скриптов"

INIT_DIR="/opt/etc/init.d"
mkdir -p "$INIT_DIR"

if ! curl -sSL "$GITHUB_RAW/S99startup_notify" -o "$INIT_DIR/S99startup_notify"; then
    log "⚠ Не удалось скачать S99startup_notify (продолжаем)"
else
    chmod +x "$INIT_DIR/S99startup_notify"
    log "✓ S99startup_notify установлен"
fi

if ! curl -sSL "$GITHUB_RAW/S99xkeenstart" -o "$INIT_DIR/S99xkeenstart"; then
    log "⚠ Не удалось скачать S99xkeenstart (продолжаем)"
else
    chmod +x "$INIT_DIR/S99xkeenstart"
    log "✓ S99xkeenstart установлен"
fi

# Удаляем старые init-скрипты если существуют
[ -f "$INIT_DIR/S01notify" ] && rm -f "$INIT_DIR/S01notify"
[ -f "$INIT_DIR/S99xkeenrestart" ] && rm -f "$INIT_DIR/S99xkeenrestart"

log "✓ Init-скрипты установлены"
countdown 3

show_header
show_section "Установка прав доступа"

chmod +x "$INSTALL_DIR/xkeen_rotate.sh"
chmod +x "$INSTALL_DIR/xkeen_sync.sh"
chmod +x "$INSTALL_DIR/network_watchdog.sh"
chmod +x "$INSTALL_DIR/startup_notify.sh"
chmod +x "$INSTALL_DIR/xkeen_restart.sh"

log "✓ Права установлены"
countdown 3

show_header
show_section "Установка команды prosto"

create_prosto_command

log "✓ Команда 'prosto' установлена в /opt/bin"
printf "${BLUE}   Используйте команду: ${BOLD}prosto${RESET}\n"
printf "${GRAY}   (если команда не найдена, перезапустите сессию или выполните: export PATH=\"/opt/bin:\$PATH\")${RESET}\n"
countdown 3

if command -v xkeen >/dev/null 2>&1 && dialog_yesno "Рекомендуемые настройки Xray" "Установить оптимизированные конфигурации inbound и routing?

Преимущества:
✓ Блокировка рекламы и аналитики
✓ Умная маршрутизация (RU напрямую, заблокированное через прокси)
✓ Оптимизация для Telegram, Discord, Google, ChatGPT
✓ Блокировка QUIC для стабильности
✓ BitTorrent напрямую (ЗАПРЕЩЕНО использовать через прокси)

Существующие файлы будут заменены."; then
    
    show_header
    show_section "Установка конфигураций Xray"
    
    BACKUP_SUFFIX=$(date +%s)
    
    if [ -f "$CONFIG_DIR/configs/03_inbounds.json" ]; then
        cp "$CONFIG_DIR/configs/03_inbounds.json" "$CONFIG_DIR/configs/03_inbounds.json.bak.$BACKUP_SUFFIX" 2>/dev/null
        log "Создан backup: 03_inbounds.json.bak.$BACKUP_SUFFIX"
    fi
    
    if [ -f "$CONFIG_DIR/configs/05_routing.json" ]; then
        cp "$CONFIG_DIR/configs/05_routing.json" "$CONFIG_DIR/configs/05_routing.json.bak.$BACKUP_SUFFIX" 2>/dev/null
        log "Создан backup: 05_routing.json.bak.$BACKUP_SUFFIX"
    fi
    
    if curl -sSL "$GITHUB_RAW/03_inbounds.json" -o "$CONFIG_DIR/configs/03_inbounds.json"; then
        log "✓ 03_inbounds.json установлен"
    else
        log "⚠ Не удалось загрузить 03_inbounds.json"
    fi
    
    if curl -sSL "$GITHUB_RAW/05_routing.json" -o "$CONFIG_DIR/configs/05_routing.json"; then
        log "✓ 05_routing.json установлен"
    else
        log "⚠ Не удалось загрузить 05_routing.json"
    fi
    
    printf "${GREEN}✓ Конфигурации inbound и routing установлены${RESET}\n"
    printf "${GRAY}   Перезапуск Xray будет выполнен после настройки подписки${RESET}\n"
    CONFIGS_INSTALLED=1
    countdown 5
else
    show_header
    show_section "Конфигурации пропущены"
    log "Пропущено (текущие конфигурации сохранены)"
    sleep 1
fi

if dialog_yesno "Настройка Telegram уведомлений" "Для получения ID топика напишите администратору в @prsta_helpbot

Администратор предоставит вам индивидуальный ID топика для получения уведомлений о состоянии сервера.

Хотите настроить Telegram сейчас?"; then
    
    TG_TOPIC_ID=$(dialog_inputbox "ID топика" "Введите ID топика (получили у администратора @prsta_helpbot):" "")
    
    if [ -n "$TG_TOPIC_ID" ]; then
        sed -i "s|TG_TOPIC_ID=\".*\"|TG_TOPIC_ID=\"$TG_TOPIC_ID\"|" "$INSTALL_DIR/xkeen_rotate.sh"
        sed -i "s|TG_TOPIC_ID=\".*\"|TG_TOPIC_ID=\"$TG_TOPIC_ID\"|" "$INSTALL_DIR/network_watchdog.sh"
        sed -i "s|TG_TOPIC_ID=\".*\"|TG_TOPIC_ID=\"$TG_TOPIC_ID\"|" "$INSTALL_DIR/startup_notify.sh"
        sed -i "s|TG_TOPIC_ID=\".*\"|TG_TOPIC_ID=\"$TG_TOPIC_ID\"|" "$INSTALL_DIR/xkeen_restart.sh"
        
        show_header
        show_section "Telegram настроен"
        log "✓ Telegram настроен для всех скриптов"
        countdown 3
        
        if dialog_yesno "Тестовое уведомление" "Отправить тестовое уведомление в Telegram для проверки настроек?"; then
            show_header
            show_section "Отправка тестового уведомления"
            log "Отправляю тестовое уведомление..."
            cd "$INSTALL_DIR"
            ./xkeen_rotate.sh --test-notify
            countdown 5
        fi
    fi
else
    show_header
    show_section "Telegram настройка пропущена"
    log "Пропущено (можно настроить позже: prosto edit)"
    sleep 1
fi

SUBSCRIPTION_FILE="$INSTALL_DIR/.subscription_url"
SUBSCRIPTION_URL=$(dialog_inputbox "Настройка подписки" "Введите URL подписки на серверы (или оставьте пустым для настройки позже):" "")

if [ -n "$SUBSCRIPTION_URL" ]; then
    # Сохраняем URL подписки для будущего использования
    echo "$SUBSCRIPTION_URL" > "$SUBSCRIPTION_FILE"
    log "URL подписки сохранён в $SUBSCRIPTION_FILE"
    
    show_header
    show_section "Загрузка серверов из подписки"
    log "Загружаю серверы из подписки..."
    
    cd "$INSTALL_DIR"
    if ./xkeen_sync.sh "$SUBSCRIPTION_URL"; then
        log "✓ Серверы загружены"
        countdown 5
        
        show_header
        show_section "Доступные серверы"
        ./xkeen_rotate.sh --status
        
        countdown 5
        
        if dialog_yesno "Активация сервера" "Активировать сервер с лучшим ping сейчас?"; then
            show_header
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
            countdown 5
            
            if [ "$CONFIGS_INSTALLED" -eq 1 ] && [ -f "$CONFIG_DIR/configs/04_outbounds.json" ]; then
                show_header
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
                countdown 5
            fi
        fi
    else
        show_header
        show_section "Ошибка загрузки подписки"
        printf "${YELLOW}⚠ Не удалось загрузить подписку (настройте позже командой: prosto)${RESET}\n"
        sleep 2
    fi
fi

if dialog_yesno "Настройка автоматической ротации" "Настроить автоматическую проверку доступности серверов через cron?"; then
    
    CRON_CHOICE=$(dialog_menu "Интервал проверки" "Выберите интервал проверки доступности серверов:" \
        "1" "Каждые 2 минуты (рекомендуется)" \
        "2" "Каждые 5 минут" \
        "3" "Каждые 10 минут")
    
    case "$CRON_CHOICE" in
        1) CRON_SCHEDULE="*/2 * * * *" ;;
        2) CRON_SCHEDULE="*/5 * * * *" ;;
        3) CRON_SCHEDULE="*/10 * * * *" ;;
        *) CRON_SCHEDULE="*/5 * * * *" ;;
    esac
    
    SETUP_AUTOSTART=0
    if dialog_yesno "Автозапуск" "Настроить автоматический выбор сервера после перезагрузки роутера?

Скрипт будет запускаться через 2 минуты после загрузки."; then
        SETUP_AUTOSTART=1
    fi
    
    TEMP_CRON=$(mktemp)
    crontab -l > "$TEMP_CRON" 2>/dev/null || true
    grep -v "xkeen_rotate.sh" "$TEMP_CRON" > "$TEMP_CRON.new" 2>/dev/null || true
    mv "$TEMP_CRON.new" "$TEMP_CRON"
    
    echo "" >> "$TEMP_CRON"
    echo "$CRON_SCHEDULE $INSTALL_DIR/xkeen_rotate.sh >/dev/null 2>&1" >> "$TEMP_CRON"
    
    # Ежедневная синхронизация подписки в 3:00 (читает URL из файла)
    echo "0 3 * * * [ -f $INSTALL_DIR/.subscription_url ] && $INSTALL_DIR/xkeen_rotate.sh --sync-url=\"\$(cat $INSTALL_DIR/.subscription_url)\" >/dev/null 2>&1" >> "$TEMP_CRON"
    
    if [ "$SETUP_AUTOSTART" -eq 1 ]; then
        echo "@reboot sleep 120 && $INSTALL_DIR/xkeen_rotate.sh >/dev/null 2>&1" >> "$TEMP_CRON"
    fi
    
    crontab "$TEMP_CRON"
    rm -f "$TEMP_CRON"
    /etc/init.d/cron restart >/dev/null 2>&1 || true
    
    show_header
    show_section "Настройка завершена"
    log "✓ Автоматическая ротация настроена"
    if [ "$SETUP_AUTOSTART" -eq 1 ]; then
        log "✓ Автозапуск настроен через cron (@reboot)"
    fi
    countdown 5
    
    if dialog_yesno "Система мониторинга и автозапуска" "Настроить полную систему автоматизации?

Система включает:
✓ Автозапуск Xray при загрузке роутера (S99xkeenstart)
✓ Автоматический выбор рабочего сервера
✓ Уведомления о загрузке системы (S99startup_notify)
✓ Мониторинг интернета каждые 5 минут
✓ Автовосстановление при проблемах
✓ Перезагрузка роутера при критических сбоях

Рекомендуется включить для полностью автономной работы."; then
        
        show_header
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
        countdown 3
    else
        show_header
        show_section "Автоматизация пропущена"
        log "Пропущено (можно настроить позже вручную)"
        log "Init-скрипты установлены но не активированы"
        
        # Отключаем автозапуск в S99xkeenstart
        if [ -f "$INIT_DIR/S99xkeenstart" ]; then
            sed -i 's/AUTOSTART="on"/AUTOSTART="off"/' "$INIT_DIR/S99xkeenstart"
            log "✓ Автозапуск Xray отключен"
        fi
        
        sleep 2
    fi
else
    show_header
    show_section "Cron настройка пропущена"
    log "Пропущено (можно настроить позже: crontab -e)"
    sleep 1
fi

# ============ Открытие портов ============
show_header
show_section "Настройка портов прокси"

PORTS_TO_OPEN="80,443,50000:50030"
OPENED_PORTS_FILE="$INSTALL_DIR/.opened_ports"

if command -v xkeen >/dev/null 2>&1; then
    log "Открываю порты для прокси-клиента..."
    printf "${BLUE}Команда: xkeen -ap $PORTS_TO_OPEN${RESET}\n"
    printf "${GRAY}Это может занять около 20 секунд...${RESET}\n"
    echo ""
    
    # Выполняем команду и сохраняем вывод
    PORTS_OUTPUT=$(xkeen -ap "$PORTS_TO_OPEN" 2>&1)
    PORTS_EXIT_CODE=$?
    
    echo "$PORTS_OUTPUT"
    echo ""
    
    if [ $PORTS_EXIT_CODE -eq 0 ]; then
        # Парсим вывод для получения списка новых портов
        # Ищем блок после "Новые порты прокси-клиента" и извлекаем номера портов
        NEW_PORTS=$(echo "$PORTS_OUTPUT" | awk '/Новые порты прокси-клиента/{found=1; next} /Прокси-клиент уже работает/{found=0} found && /^[[:space:]]*[0-9]/{gsub(/^[[:space:]]+/, ""); print}' | tr '\n' ',' | sed 's/,$//')
        
        if [ -n "$NEW_PORTS" ]; then
            echo "$NEW_PORTS" > "$OPENED_PORTS_FILE"
            log "✓ Порты открыты успешно"
            log "✓ Новые порты сохранены: $NEW_PORTS"
        else
            # Если новых портов нет (все уже были открыты), сохраняем пустой файл
            echo "" > "$OPENED_PORTS_FILE"
            log "✓ Все порты уже были открыты ранее"
        fi
    else
        log "⚠ Не удалось открыть порты (код: $PORTS_EXIT_CODE)"
    fi
    
    countdown 3
else
    log "⚠ xkeen не найден, пропускаю настройку портов"
    sleep 1
fi

if [ "$USE_DIALOG" -eq 1 ]; then
    $DIALOG_CMD --title "простовпн" --msgbox "╔════════════════════════════════════════════════════════════╗
║              Установка успешно завершена!                  ║
╚════════════════════════════════════════════════════════════╝

Основные команды:
• prosto                   # Интерактивное меню
• prosto status            # Показать статус серверов
• prosto force             # Принудительная ротация
• prosto test              # Тест Telegram уведомлений
• prosto logs              # Просмотр логов

Система автоматической ротации активна!

════════════════════════════════════════════════════════════
Покупка: https://t.me/prstabot
Поддержка: https://t.me/prsta_helpbot
════════════════════════════════════════════════════════════" 25 70
else
    show_header
    show_section "Установка завершена!"
    log "✓ Установка успешно завершена!"
    echo ""
    printf "${BLUE}${BOLD}Основные команды:${RESET}\n"
    printf "${BLUE}  prosto${RESET}                   # Интерактивное меню\n"
    printf "${BLUE}  prosto status${RESET}            # Показать статус серверов\n"
    printf "${BLUE}  prosto force${RESET}             # Принудительная ротация\n"
    printf "${BLUE}  prosto test${RESET}              # Тест Telegram уведомлений\n"
    printf "${BLUE}  prosto logs${RESET}              # Просмотр логов\n"
    printf "${BLUE}  prosto cleanup${RESET}           # Очистка технических серверов\n"
    echo ""
    printf "${GREEN}Система автоматической ротации активна!${RESET}\n"
    echo ""
    printf "${GRAY}════════════════════════════════════════════════════════════${RESET}\n"
    printf "${BLUE}Покупка:${RESET} https://t.me/prstabot\n"
    printf "${BLUE}Поддержка:${RESET} https://t.me/prsta_helpbot\n"
    printf "${GRAY}════════════════════════════════════════════════════════════${RESET}\n"
    echo ""
fi

if dialog_yesno "Удаление установщика" "Удалить установочный скрипт?"; then
    if [ -f "$0" ] && [ "$0" != "/dev/stdin" ]; then
        INSTALLER_PATH="$0"
        rm -f "$INSTALLER_PATH"
        show_header
        show_section "Установщик удалён"
        log "✓ Установочный скрипт удалён"
    fi
fi

show_header
printf "${GREEN}${BOLD}Готово! Система автоматической ротации активна.${RESET}\n"
echo ""
printf "${BLUE}${BOLD}Используйте команду: prosto${RESET}\n"
printf "${GRAY}(Если команда не найдена, выполните: export PATH=\"/opt/bin:\$PATH\")${RESET}\n"
echo ""
