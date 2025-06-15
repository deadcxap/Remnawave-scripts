#!/bin/bash

# создаем nano /usr/local/bin/remna-update-manager.sh
# потом chmod +x /usr/local/bin/remna-update-manager.sh
# добавляем в кронтаб 
# * * * * * /bin/bash /usr/local/bin/remna-update-manager.sh cron

# === КОНФИГУРАЦИЯ ===
DOCKER_COMPOSE_DIR="/opt/remnawave"
TIMEZONE="Europe/Moscow"
ENV_FILE="/opt/remnawave/.env"

# Цвета
GREEN="\e[32m"
CYAN="\e[36m"
RED="\e[31m"
RESET="\e[0m"

# Временный файл для хранения времени запуска
SCHEDULE_FILE="/tmp/update_schedule_time"

# === Функция для загрузки переменных из .env ===
function load_env_vars() {
    if [[ -f "$ENV_FILE" ]]; then
        # Загружаем переменные из .env файла
        export $(grep -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_NOTIFY_NODES_CHAT_ID)=' "$ENV_FILE" | xargs)
    else
        echo -e "${RED}Файл $ENV_FILE не найден!${RESET}"
        exit 1
    fi
}

# === Функция для отправки уведомлений в Telegram ===
function send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode chat_id="${TELEGRAM_CHAT_ID}" \
        --data-urlencode text="$message" \
        -d parse_mode="Markdown"
}

# === Функция для выполнения обновления ===
function perform_update() {
    # Загружаем запланированное время
    local update_time=$(cat "$SCHEDULE_FILE" 2>/dev/null)
    if [[ -z "$update_time" ]]; then
        return
    fi

    # Получаем текущее время в московском часовом поясе
    local now_time=$(TZ="$TIMEZONE" date +"%H:%M")

    # Логирование для отладки
    echo "DEBUG: now_time=$now_time, update_time=$update_time" >> /tmp/remna_update_debug.log

    # Если текущее время совпадает с запланированным
    if [[ "$now_time" == "$update_time" ]]; then
        echo -e "${GREEN}Начинаем обновление контейнеров...${RESET}"
        send_telegram "*🚀 Обновление контейнеров началось...*"

        cd "$DOCKER_COMPOSE_DIR" || exit 1

        # Выполнение команд
        output=$( (docker compose down && docker compose pull && docker compose up -d) 2>&1 )
        log_output=$(docker compose logs | grep -E 'ERROR|error|Error|WARNING|warning|Warning')

        # Удаляем задание (одноразовое выполнение)
        rm -f "$SCHEDULE_FILE"

        # Отправка в Telegram
        message=$(cat <<EOF
*✅ Обновление завершено.*

*Вывод команд:*
\`\`\`
$output
\`\`\`

*Логи с ошибками/предупреждениями:*
\`\`\`
$log_output
\`\`\`
EOF
)
        send_telegram "$message"
    fi
}

# === Основное меню ===
function show_menu() {
    echo -e "${CYAN}==== Менеджер обновлений контейнеров ====${RESET}"

    if [[ -f "$SCHEDULE_FILE" ]]; then
        echo -e "⏰ Запланировано обновление на: ${GREEN}$(cat "$SCHEDULE_FILE")${RESET} (по $TIMEZONE)"
    else
        echo "📭 Обновление не запланировано."
    fi

    echo
    echo "1. Запланировать одноразовое обновление"
    echo "2. Принудительно выполнить обновление сейчас"
    echo "3. Отменить запланированное обновление"
    echo "4. Выйти"
    echo
    read -p "Выберите действие [1-4]: " choice

    case "$choice" in
        1) schedule_update ;;
        2) echo "$(TZ=$TIMEZONE date +%H:%M)" > "$SCHEDULE_FILE"; perform_update ;;
        3) rm -f "$SCHEDULE_FILE"; echo "Запланированное обновление отменено." ;;
        4) exit 0 ;;
        *) echo "Неверный выбор!" ;;
    esac
}

# === Запуск ===
load_env_vars

if [[ "$1" == "cron" ]]; then
    perform_update >> /tmp/remna_update.log 2>&1
else
    show_menu
fi
