#!/bin/sh

set -e

INSTALL_DIR="/opt/root/scripts"
CONFIG_DIR="/opt/etc/xray"
GITHUB_RAW="https://raw.githubusercontent.com/andrchq/xkeen_auto/main"
USE_DIALOG=0
DIALOG_CMD=""

check_dialog() {
    if command -v whiptail >/dev/null 2>&1; then
        DIALOG_CMD="whiptail"
        USE_DIALOG=1
    elif command -v dialog >/dev/null 2>&1; then
        DIALOG_CMD="dialog"
        USE_DIALOG=1
    fi
}

show_header() {
    clear
    echo "╔══════════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                  🤲🏻 простовпн                                        ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ОШИБКА] $*" >&2
    exit 1
}

dialog_msgbox() {
    TITLE="$1"
    MSG="$2"
    if [ "$USE_DIALOG" -eq 1 ]; then
        $DIALOG_CMD --title "🤲🏻 простовпн" --msgbox "$MSG" 15 70
    else
        show_header
        echo "$TITLE"
        echo ""
        echo "$MSG"
        echo ""
        printf "Нажмите Enter для продолжения..."
        read -r dummy
    fi
}

dialog_yesno() {
    TITLE="$1"
    MSG="$2"
    if [ "$USE_DIALOG" -eq 1 ]; then
        $DIALOG_CMD --title "🤲🏻 простовпн" --yesno "$MSG" 15 70
        return $?
    else
        show_header
        echo "$TITLE"
        echo ""
        echo "$MSG"
        echo ""
        printf "Ваш выбор (y/n): "
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
        RESULT=$($DIALOG_CMD --title "🤲🏻 простовпн" --inputbox "$MSG" 15 70 "$DEFAULT" 3>&1 1>&2 2>&3)
        echo "$RESULT"
    else
        show_header
        echo "$TITLE"
        echo ""
        echo "$MSG"
        echo ""
        printf "> "
        read -r result
        echo "$result"
    fi
}

dialog_menu() {
    TITLE="$1"
    MSG="$2"
    shift 2
    if [ "$USE_DIALOG" -eq 1 ]; then
        RESULT=$($DIALOG_CMD --title "🤲🏻 простовпн" --menu "$MSG" 20 70 10 "$@" 3>&1 1>&2 2>&3)
        echo "$RESULT"
    else
        show_header
        echo "$TITLE"
        echo ""
        echo "$MSG"
        echo ""
        i=1
        while [ $# -gt 0 ]; do
            echo "  $1) $2"
            shift 2
        done
        echo ""
        printf "Выберите вариант: "
        read -r result
        echo "$result"
    fi
}

check_dialog

show_header
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         xkeen_rotate - Установка                          ║"
echo "║  Автоматическая ротация прокси-серверов для Xray/Xkeen    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Разработано командой 🤲🏻 простовпн"
echo "Для клиентов https://t.me/prstabot"
echo ""
echo "💬 Служба поддержки: https://t.me/prsta_helpbot"
echo ""

if [ "$USE_DIALOG" -eq 0 ]; then
    echo "💡 Для графического интерфейса установите whiptail:"
    echo "   opkg update && opkg install whiptail"
    echo ""
fi

log "Начинаю установку..."
sleep 2

if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт должен запускаться от root!"
fi

show_header
log "Проверка зависимостей..."
echo ""

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
log "Создаю директории..."
echo ""

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR/outbounds_available"
mkdir -p "$CONFIG_DIR/configs"
mkdir -p "$CONFIG_DIR/backups"

log "✓ Директории созданы"
sleep 1

show_header
log "Загружаю скрипты с GitHub..."
echo ""

if ! curl -sSL "$GITHUB_RAW/xkeen_rotate.sh" -o "$INSTALL_DIR/xkeen_rotate.sh"; then
    error "Не удалось скачать xkeen_rotate.sh"
fi

if ! curl -sSL "$GITHUB_RAW/xkeen_sync.sh" -o "$INSTALL_DIR/xkeen_sync.sh"; then
    error "Не удалось скачать xkeen_sync.sh"
fi

log "✓ Скрипты загружены"
sleep 1

show_header
log "Устанавливаю права на выполнение..."
echo ""

chmod +x "$INSTALL_DIR/xkeen_rotate.sh"
chmod +x "$INSTALL_DIR/xkeen_sync.sh"

log "✓ Права установлены"
sleep 1

if dialog_yesno "Настройка Telegram уведомлений" "Для получения ID топика напишите администратору в @prsta_helpbot

Администратор предоставит вам индивидуальный ID топика для получения уведомлений о состоянии сервера.

Хотите настроить Telegram сейчас?"; then
    
    TG_TOPIC_ID=$(dialog_inputbox "ID топика" "Введите ID топика (получили у администратора @prsta_helpbot):" "")
    
    if [ -n "$TG_TOPIC_ID" ]; then
        sed -i "s|TG_TOPIC_ID=\".*\"|TG_TOPIC_ID=\"$TG_TOPIC_ID\"|" "$INSTALL_DIR/xkeen_rotate.sh"
        
        show_header
        log "✓ Telegram настроен"
        sleep 1
        
        if dialog_yesno "Тестовое уведомление" "Отправить тестовое уведомление в Telegram для проверки настроек?"; then
            show_header
            log "Отправляю тестовое уведомление..."
            echo ""
            cd "$INSTALL_DIR"
            ./xkeen_rotate.sh --test-notify
            sleep 2
        fi
    fi
else
    show_header
    log "Пропускаю настройку Telegram (можно настроить позже в $INSTALL_DIR/xkeen_rotate.sh)"
    sleep 1
fi

SUBSCRIPTION_URL=$(dialog_inputbox "Настройка подписки" "Введите URL подписки на серверы (или оставьте пустым для настройки позже):" "")

if [ -n "$SUBSCRIPTION_URL" ]; then
    show_header
    log "Загружаю серверы из подписки..."
    echo ""
    
    cd "$INSTALL_DIR"
    if ./xkeen_sync.sh "$SUBSCRIPTION_URL"; then
        log "✓ Серверы загружены"
        sleep 1
        
        show_header
        echo "Доступные серверы:"
        echo ""
        ./xkeen_rotate.sh --status
        
        sleep 2
        
        if dialog_yesno "Активация сервера" "Активировать первый доступный сервер сейчас?"; then
            show_header
            log "Активирую сервер..."
            echo ""
            ./xkeen_rotate.sh
            log "✓ Сервер активирован"
            sleep 1
        fi
    else
        show_header
        log "⚠ Не удалось загрузить подписку (настройте позже)"
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
    
    TEMP_CRON=$(mktemp)
    crontab -l > "$TEMP_CRON" 2>/dev/null || true
    grep -v "xkeen_rotate.sh" "$TEMP_CRON" > "$TEMP_CRON.new" || true
    mv "$TEMP_CRON.new" "$TEMP_CRON"
    
    echo "" >> "$TEMP_CRON"
    echo "# xkeen_rotate - автоматическая ротация прокси" >> "$TEMP_CRON"
    echo "$CRON_SCHEDULE $INSTALL_DIR/xkeen_rotate.sh >/dev/null 2>&1" >> "$TEMP_CRON"
    
    if [ -n "$SUBSCRIPTION_URL" ]; then
        echo "0 3 * * * $INSTALL_DIR/xkeen_rotate.sh --sync-url=\"$SUBSCRIPTION_URL\" >/dev/null 2>&1" >> "$TEMP_CRON"
    fi
    
    crontab "$TEMP_CRON"
    rm -f "$TEMP_CRON"
    /etc/init.d/cron restart >/dev/null 2>&1 || true
    
    show_header
    log "✓ Автоматическая ротация настроена"
    sleep 1
else
    show_header
    log "Пропускаю настройку cron (можно настроить позже командой: crontab -e)"
    sleep 1
fi

if dialog_yesno "Автозапуск" "Настроить автоматический выбор сервера после перезагрузки роутера?"; then
    if [ -f /etc/rc.local ]; then
        if ! grep -q "xkeen_rotate.sh" /etc/rc.local; then
            sed -i '/exit 0/i sleep 60 \&\& '"$INSTALL_DIR"'/xkeen_rotate.sh \&' /etc/rc.local
            show_header
            log "✓ Автозапуск настроен"
        else
            show_header
            log "✓ Автозапуск уже настроен"
        fi
    else
        show_header
        log "⚠ Файл /etc/rc.local не найден (настройте автозапуск вручную)"
    fi
    sleep 1
fi

if [ "$USE_DIALOG" -eq 1 ]; then
    $DIALOG_CMD --title "🤲🏻 простовпн" --msgbox "Установка успешно завершена!

Основные команды:
• $INSTALL_DIR/xkeen_rotate.sh --status
• $INSTALL_DIR/xkeen_rotate.sh --force
• $INSTALL_DIR/xkeen_rotate.sh --test-notify

Просмотр логов:
• logread | grep xkeen_rotate | tail -20

Настройки: $INSTALL_DIR/xkeen_rotate.sh (строки 3-22)

Система автоматической ротации активна!" 20 70
else
    show_header
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                 Установка завершена!                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log "✓ Установка успешно завершена!"
    echo ""
    echo "Основные команды:"
    echo "  $INSTALL_DIR/xkeen_rotate.sh --status        # Показать статус серверов"
    echo "  $INSTALL_DIR/xkeen_rotate.sh --force         # Принудительная ротация"
    echo "  $INSTALL_DIR/xkeen_rotate.sh --test-notify   # Тест Telegram"
    echo "  $INSTALL_DIR/xkeen_rotate.sh --cleanup       # Очистка технических серверов"
    echo ""
    echo "Просмотр логов:"
    echo "  logread | grep xkeen_rotate | tail -20"
    echo "  logread -f | grep xkeen_rotate"
    echo ""
    echo "Настройки находятся в: $INSTALL_DIR/xkeen_rotate.sh (строки 3-22)"
    echo ""
fi

if dialog_yesno "Удаление установщика" "Удалить установочный скрипт?"; then
    if [ -f "$0" ] && [ "$0" != "/dev/stdin" ]; then
        INSTALLER_PATH="$0"
        rm -f "$INSTALLER_PATH"
        show_header
        log "✓ Установочный скрипт удалён"
    fi
fi

show_header
log "Готово! Система автоматической ротации активна."
echo ""
