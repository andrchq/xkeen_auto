#!/bin/sh

# xkeen_rotate - Установочный скрипт
# Автоматическая установка системы ротации прокси-серверов для Xray/Xkeen

set -e

INSTALL_DIR="/opt/root/scripts"
CONFIG_DIR="/opt/etc/xray"
GITHUB_RAW="https://raw.githubusercontent.com/andrchq/xkeen_auto/main"

clear
echo "╔══════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                                   ║"
echo "║                                простовпн — xkeen_rotate                           ║"
echo "║                                        Установка                                  ║"
echo "║-----------------------------------------------------------------------------------║"
echo "║                    Автоматическая ротация прокси-серверов для Xray/Xkeen          ║"
echo "║                                                                                   ║"
echo "║                           Разработано командой: 🤲🏻 простовпн                      ║"
echo "║                               Для клиентов: https://t.me/prstabot                 ║"
echo "║                           💬 Служба поддержки: https://t.me/prsta_helpbot         ║"
echo "║                                                                                   ║"
echo "╚═════════════════════════════════════════════════════════════════════════════════════╝"
echo ""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ОШИБКА] $*" >&2
    exit 1
}

log "Начинаю установку..."

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт должен запускаться от root!"
fi

# Проверка наличия необходимых утилит
log "Проверка зависимостей..."
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

# Создание директорий
log "Создаю директории..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR/outbounds_available"
mkdir -p "$CONFIG_DIR/configs"
mkdir -p "$CONFIG_DIR/backups"
log "✓ Директории созданы"

# Скачивание скриптов
log "Загружаю скрипты с GitHub..."

if ! curl -sSL "$GITHUB_RAW/xkeen_rotate.sh" -o "$INSTALL_DIR/xkeen_rotate.sh"; then
    error "Не удалось скачать xkeen_rotate.sh"
fi

if ! curl -sSL "$GITHUB_RAW/xkeen_sync.sh" -o "$INSTALL_DIR/xkeen_sync.sh"; then
    error "Не удалось скачать xkeen_sync.sh"
fi

log "✓ Скрипты загружены"

# Установка прав
log "Устанавливаю права на выполнение..."
chmod +x "$INSTALL_DIR/xkeen_rotate.sh"
chmod +x "$INSTALL_DIR/xkeen_sync.sh"
log "✓ Права установлены"

# Настройка Telegram (интерактивно)
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Настройка Telegram уведомлений                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📱 Для получения ID топика напишите администратору в:"
echo "   @prsta_helpbot"
echo ""
echo "Администратор предоставит вам индивидуальный ID топика"
echo "для получения уведомлений о состоянии сервера."
echo ""
echo "Хотите настроить Telegram сейчас? (y/n)"
read -r SETUP_TG

if [ "$SETUP_TG" = "y" ] || [ "$SETUP_TG" = "Y" ]; then
    echo ""
    echo -n "Введите ID топика (получили у администратора @prsta_helpbot): "
    read -r TG_TOPIC_ID
    
    sed -i "s|TG_TOPIC_ID=\".*\"|TG_TOPIC_ID=\"$TG_TOPIC_ID\"|" "$INSTALL_DIR/xkeen_rotate.sh"
    
    log "✓ Telegram настроен"
    
    # Тестовое уведомление
    echo ""
    echo "Отправить тестовое уведомление? (y/n)"
    read -r TEST_TG
    
    if [ "$TEST_TG" = "y" ] || [ "$TEST_TG" = "Y" ]; then
        cd "$INSTALL_DIR"
        ./xkeen_rotate.sh --test-notify
    fi
else
    log "Пропускаю настройку Telegram (можно настроить позже в $INSTALL_DIR/xkeen_rotate.sh)"
fi

# Настройка подписки
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            Настройка подписки на серверы                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Введите URL подписки (или оставьте пустым для настройки позже):"
read -r SUBSCRIPTION_URL

if [ -n "$SUBSCRIPTION_URL" ]; then
    log "Загружаю серверы из подписки..."
    cd "$INSTALL_DIR"
    if ./xkeen_sync.sh "$SUBSCRIPTION_URL"; then
        log "✓ Серверы загружены"
        
        # Показываем статус
        echo ""
        echo "Доступные серверы:"
        ./xkeen_rotate.sh --status
        
        # Активируем первый сервер
        echo ""
        echo "Активировать первый доступный сервер? (y/n)"
        read -r ACTIVATE_SERVER
        
        if [ "$ACTIVATE_SERVER" = "y" ] || [ "$ACTIVATE_SERVER" = "Y" ]; then
            log "Активирую сервер..."
            ./xkeen_rotate.sh
            log "✓ Сервер активирован"
        fi
    else
        log "⚠ Не удалось загрузить подписку (настройте позже)"
    fi
fi

# Настройка cron
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Настройка автоматической ротации (cron)           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Настроить автоматическую проверку доступности? (y/n)"
read -r SETUP_CRON

if [ "$SETUP_CRON" = "y" ] || [ "$SETUP_CRON" = "Y" ]; then
    echo ""
    echo "Интервал проверки:"
    echo "  1) Каждые 2 минуты (рекомендуется)"
    echo "  2) Каждые 5 минут"
    echo "  3) Каждые 10 минут"
    echo -n "Выберите вариант (1-3): "
    read -r CRON_INTERVAL
    
    case "$CRON_INTERVAL" in
        1) CRON_SCHEDULE="*/2 * * * *" ;;
        2) CRON_SCHEDULE="*/5 * * * *" ;;
        3) CRON_SCHEDULE="*/10 * * * *" ;;
        *) CRON_SCHEDULE="*/5 * * * *" ;;
    esac
    
    # Добавляем задания в crontab
    TEMP_CRON=$(mktemp)
    crontab -l > "$TEMP_CRON" 2>/dev/null || true
    
    # Удаляем старые задания если есть
    grep -v "xkeen_rotate.sh" "$TEMP_CRON" > "$TEMP_CRON.new" || true
    mv "$TEMP_CRON.new" "$TEMP_CRON"
    
    # Добавляем новые задания
    echo "" >> "$TEMP_CRON"
    echo "# xkeen_rotate - автоматическая ротация прокси" >> "$TEMP_CRON"
    echo "$CRON_SCHEDULE $INSTALL_DIR/xkeen_rotate.sh >/dev/null 2>&1" >> "$TEMP_CRON"
    
    if [ -n "$SUBSCRIPTION_URL" ]; then
        echo "0 3 * * * $INSTALL_DIR/xkeen_rotate.sh --sync-url=\"$SUBSCRIPTION_URL\" >/dev/null 2>&1" >> "$TEMP_CRON"
    fi
    
    crontab "$TEMP_CRON"
    rm -f "$TEMP_CRON"
    
    # Перезапускаем cron
    /etc/init.d/cron restart >/dev/null 2>&1 || true
    
    log "✓ Автоматическая ротация настроена"
else
    log "Пропускаю настройку cron (можно настроить позже командой: crontab -e)"
fi

# Настройка автозапуска
echo ""
echo "Настроить автоматический выбор сервера после перезагрузки роутера? (y/n)"
read -r SETUP_AUTOSTART

if [ "$SETUP_AUTOSTART" = "y" ] || [ "$SETUP_AUTOSTART" = "Y" ]; then
    if [ -f /etc/rc.local ]; then
        if ! grep -q "xkeen_rotate.sh" /etc/rc.local; then
            # Добавляем перед exit 0
            sed -i '/exit 0/i sleep 60 \&\& '"$INSTALL_DIR"'/xkeen_rotate.sh \&' /etc/rc.local
            log "✓ Автозапуск настроен"
        else
            log "✓ Автозапуск уже настроен"
        fi
    else
        log "⚠ Файл /etc/rc.local не найден (настройте автозапуск вручную)"
    fi
fi

# Итоговая информация
echo ""
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

# Предложение удалить установочный скрипт
if [ -f "$0" ] && [ "$0" != "/dev/stdin" ]; then
    echo "Удалить установочный скрипт? (y/n)"
    read -r DELETE_INSTALLER
    
    if [ "$DELETE_INSTALLER" = "y" ] || [ "$DELETE_INSTALLER" = "Y" ]; then
        INSTALLER_PATH="$0"
        rm -f "$INSTALLER_PATH"
        log "✓ Установочный скрипт удалён"
    fi
fi

echo ""
log "Готово! Система автоматической ротации активна."
echo ""

