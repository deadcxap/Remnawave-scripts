#!/bin/bash

# создаем nano /usr/local/bin/remna-update-manager.sh
# потом chmod +x /usr/local/bin/remna-update-manager.sh
# добавляем в кронтаб 
# * * * * * /usr/local/bin/remna-update-manager.sh cron

# === КОНФИГУРАЦИЯ ===
DOCKER_COMPOSE_DIR="/opt/remnawave"
TIMEZONE="Europe/Moscow"

# Telegram
TELEGRAM_BOT_TOKEN="xxxxxxxx:yyyyyyyyyyyyyyyyyyyyyyyyyy"
TELEGRAM_CHAT_ID="-100xxxxxxxxxxxxxxx"

# Цвета
GREEN="\e[32m"
CYAN="\e[36m"
RED="\e[31m"
RESET="\e[0m"

# Временный файл для хранения времени запуска
SCHEDULE_FILE="/tmp/update_schedule_time"

function send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode chat_id="${TELEGRAM_CHAT_ID}" \
        --data-urlencode text="$message" \
        -d parse_mode="Markdown"
}

function schedule_update() {
    echo -e "${CYAN}Введите время одноразового обновления в формате HH:MM (по $TIMEZONE):${RESET}"
    read -p "Время: " time_input
    if [[ $time_input =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        echo "$time_input" > "$SCHEDULE_FILE"
        echo -e "${GREEN}Обновление запланировано на $time_input по $TIMEZONE${RESET}"
        send_telegram "*📅 Запланировано обновление контейнеров в $time_input по $TIMEZONE*"
    else
        echo -e "${RED}Неверный формат времени. Попробуйте ещё раз.${RESET}"
    fi
}

function perform_update() {
    local update_time=$(cat "$SCHEDULE_FILE" 2>/dev/null)
    if [[ -z "$update_time" ]]; then
        return
    fi

    # Получаем текущее время
    local now_time=$(TZ="$TIMEZONE" date +"%H:%M")

    # Если сейчас то самое время
    if [[ "$now_time" >= "$update_time" ]]; then
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

if [[ "$1" == "cron" ]]; then
    perform_update
else
    show_menu
fi
