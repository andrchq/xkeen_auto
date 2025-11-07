#!/bin/sh

set -e

INSTALL_DIR="/opt/root/scripts"
CONFIG_DIR="/opt/etc/xray"
GITHUB_RAW="https://raw.githubusercontent.com/andrchq/xkeen_auto/main"
USE_DIALOG=0
DIALOG_CMD=""
XRAY_RESTARTED=0

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
            
            printf "${BLUE}Перезапускаю установщик с графическим интерфейсом...${RESET}\n"
            sleep 2
            exec "$0" "$@"
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
GRAY="\033[90m"
BLUE="\033[94m"
GREEN="\033[92m"
RESET="\033[0m"
BOLD="\033[1m"

show_header() {
    clear
    printf "${GRAY}╔══════════════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${GRAY}║${RESET}${BLUE}${BOLD}                                    простовпн                                          ${RESET}${GRAY}║${RESET}\n"
    printf "${GRAY}╚══════════════════════════════════════════════════════════════════════════════════════╝${RESET}\n"
    echo ""
}

show_menu() {
    show_header
    printf "${BLUE}${BOLD}Управление системой ротации серверов${RESET}\n\n"
    printf "${BLUE}1)${RESET} Показать статус серверов\n"
    printf "${BLUE}2)${RESET} Принудительная ротация\n"
    printf "${BLUE}3)${RESET} Тестовое уведомление\n"
    printf "${BLUE}4)${RESET} Синхронизация подписки\n"
    printf "${BLUE}5)${RESET} Очистка технических серверов\n"
    printf "${BLUE}6)${RESET} Просмотр логов (последние 30 строк)\n"
    printf "${BLUE}7)${RESET} Просмотр логов (в реальном времени)\n"
    printf "${BLUE}8)${RESET} Редактировать настройки\n"
    printf "${BLUE}9)${RESET} О системе\n"
    printf "${BLUE}0)${RESET} Выход\n"
    echo ""
    printf "${BLUE}Выберите действие: ${RESET}"
}

if [ "$1" = "status" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --status
    exit 0
elif [ "$1" = "force" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --force
    exit 0
elif [ "$1" = "test" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --test-notify
    exit 0
elif [ "$1" = "sync" ]; then
    if [ -n "$2" ]; then
        $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$2"
    else
        echo "Использование: prosto sync <URL>"
    fi
    exit 0
elif [ "$1" = "cleanup" ]; then
    $SCRIPT_DIR/xkeen_rotate.sh --cleanup
    exit 0
elif [ "$1" = "logs" ]; then
    logread | grep xkeen_rotate | tail -30
    exit 0
elif [ "$1" = "logsf" ]; then
    logread -f | grep xkeen_rotate
    exit 0
elif [ "$1" = "edit" ]; then
    vi $SCRIPT_DIR/xkeen_rotate.sh
    exit 0
elif [ -n "$1" ]; then
    echo "Неизвестная команда: $1"
    echo ""
    echo "Доступные команды:"
    echo "  prosto              - интерактивное меню"
    echo "  prosto status       - показать статус"
    echo "  prosto force        - принудительная ротация"
    echo "  prosto test         - тестовое уведомление"
    echo "  prosto sync <URL>   - синхронизация подписки"
    echo "  prosto cleanup      - очистка технических серверов"
    echo "  prosto logs         - последние 30 строк логов"
    echo "  prosto logsf        - логи в реальном времени"
    echo "  prosto edit         - редактировать настройки"
    exit 1
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
            $SCRIPT_DIR/xkeen_rotate.sh --force
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        3)
            show_header
            $SCRIPT_DIR/xkeen_rotate.sh --test-notify
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        4)
            show_header
            printf "${BLUE}Введите URL подписки: ${RESET}"
            read -r url
            if [ -n "$url" ]; then
                $SCRIPT_DIR/xkeen_rotate.sh --sync-url="$url"
            fi
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        5)
            show_header
            $SCRIPT_DIR/xkeen_rotate.sh --cleanup
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        6)
            show_header
            logread | grep xkeen_rotate | tail -30
            echo ""
            printf "${BLUE}Нажмите Enter для возврата в меню...${RESET}"
            read -r dummy
            ;;
        7)
            show_header
            printf "${GREEN}Логи в реальном времени (Ctrl+C для выхода)${RESET}\n\n"
            logread -f | grep xkeen_rotate
            ;;
        8)
            vi $SCRIPT_DIR/xkeen_rotate.sh
            ;;
        9)
            show_header
            printf "${BLUE}${BOLD}Система автоматической ротации прокси-серверов${RESET}\n\n"
            printf "Разработано командой ${BLUE}${BOLD}простовпн${RESET}\n\n"
            printf "${GREEN}Покупка:${RESET} https://t.me/prstabot\n"
            printf "${GREEN}Поддержка:${RESET} https://t.me/prsta_helpbot\n"
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

log "✓ Скрипты загружены"
sleep 1

show_header
show_section "Установка прав доступа"

chmod +x "$INSTALL_DIR/xkeen_rotate.sh"
chmod +x "$INSTALL_DIR/xkeen_sync.sh"

log "✓ Права установлены"
sleep 1

show_header
show_section "Установка команды prosto"

create_prosto_command

log "✓ Команда 'prosto' установлена в /opt/bin"
printf "${BLUE}   Используйте команду: ${BOLD}prosto${RESET}\n"
printf "${GRAY}   (если команда не найдена, перезапустите сессию или выполните: export PATH=\"/opt/bin:\$PATH\")${RESET}\n"
sleep 2

if dialog_yesno "Рекомендуемые настройки Xray" "Установить оптимизированные конфигурации inbound и routing?

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
    
    printf "${GREEN}✓ Конфигурации установлены${RESET}\n"
    echo ""
    printf "${BLUE}Перезапускаю Xray для применения изменений...${RESET}\n"
    echo ""
    
    RESTART_LOG="/tmp/xray_restart_$$.log"
    xkeen -restart > "$RESTART_LOG" 2>&1 &
    sleep 7
    
    if [ -f "$RESTART_LOG" ]; then
        RESTART_OUTPUT=$(cat "$RESTART_LOG")
        if echo "$RESTART_OUTPUT" | grep -q "Прокси-клиент запущен"; then
            printf "${GREEN}✓ Xray успешно перезапущен с новыми конфигурациями${RESET}\n"
            log "Xray перезапущен успешно"
            XRAY_RESTARTED=1
        else
            log "Не удалось подтвердить перезапуск Xray"
        fi
        rm -f "$RESTART_LOG"
    else
        log "Не удалось получить вывод команды xkeen -restart"
    fi
    sleep 1
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
        
        show_header
        show_section "Telegram настроен"
        log "✓ Telegram настроен"
        sleep 1
        
        if dialog_yesno "Тестовое уведомление" "Отправить тестовое уведомление в Telegram для проверки настроек?"; then
            show_header
            show_section "Отправка тестового уведомления"
            log "Отправляю тестовое уведомление..."
            cd "$INSTALL_DIR"
            ./xkeen_rotate.sh --test-notify
            sleep 2
        fi
    fi
else
    show_header
    show_section "Telegram настройка пропущена"
    log "Пропущено (можно настроить позже: prosto edit)"
    sleep 1
fi

SUBSCRIPTION_URL=$(dialog_inputbox "Настройка подписки" "Введите URL подписки на серверы (или оставьте пустым для настройки позже):" "")

if [ -n "$SUBSCRIPTION_URL" ]; then
    show_header
    show_section "Загрузка серверов из подписки"
    log "Загружаю серверы из подписки..."
    
    cd "$INSTALL_DIR"
    if ./xkeen_sync.sh "$SUBSCRIPTION_URL"; then
        log "✓ Серверы загружены"
        sleep 1
        
        show_header
        show_section "Доступные серверы"
        ./xkeen_rotate.sh --status
        
        sleep 2
        
        if dialog_yesno "Активация сервера" "Активировать первый доступный сервер сейчас?"; then
            show_header
            show_section "Активация сервера"
            log "Активирую сервер..."
            ./xkeen_rotate.sh
            log "✓ Сервер активирован"
            sleep 1
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
    
    if [ -n "$SUBSCRIPTION_URL" ]; then
        echo "0 3 * * * $INSTALL_DIR/xkeen_rotate.sh --sync-url=\"$SUBSCRIPTION_URL\" >/dev/null 2>&1" >> "$TEMP_CRON"
    fi
    
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
    sleep 1
else
    show_header
    show_section "Cron настройка пропущена"
    log "Пропущено (можно настроить позже: crontab -e)"
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

if [ "$XRAY_RESTARTED" -eq 0 ]; then
    echo ""
    printf "${RED}${BOLD}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${RED}${BOLD}║                                                                           ║${RESET}\n"
    printf "${RED}${BOLD}║                    ⚠️  ВАЖНО: ТРЕБУЕТСЯ ПЕРЕЗАПУСК XRAY  ⚠️                ║${RESET}\n"
    printf "${RED}${BOLD}║                                                                           ║${RESET}\n"
    printf "${RED}${BOLD}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}\n"
    echo ""
    printf "${YELLOW}${BOLD}Конфигурации были установлены, но не удалось подтвердить перезапуск.${RESET}\n"
    printf "${YELLOW}${BOLD}Для применения изменений выполните команду:${RESET}\n"
    echo ""
    printf "${GREEN}${BOLD}    xkeen -restart${RESET}\n"
    echo ""
    printf "${GRAY}После успешного перезапуска вы должны увидеть:${RESET}\n"
    printf "${GRAY}  \"Прокси-клиент запущен\"${RESET}\n"
    echo ""
fi
