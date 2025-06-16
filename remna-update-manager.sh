#!/bin/bash

# === КОНФИГУРАЦИЯ ===
DOCKER_COMPOSE_DIR="/opt/remnawave"
TIMEZONE="Europe/Moscow"
ENV_FILE="/opt/remnawave/.env"
AT_JOB_FILE="/tmp/remna_update_at_job"

# Цвета
GREEN="\e[32m"
CYAN="\e[36m"
RED="\e[31m"
RESET="\e[0m"

# === Функция для проверки и установки at ===
function check_install_at() {
    if ! command -v at &> /dev/null; then
        echo -e "${RED}Команда 'at' не установлена.${RESET}"
        read -p "Установить сейчас? [y/N] " answer
        if [[ "$answer" =~ [yY] ]]; then
            if [[ -f /etc/debian_version ]]; then
                apt-get update && apt-get install -y at
            elif [[ -f /etc/redhat-release ]]; then
                yum install -y at
            else
                echo -e "${RED}Не удалось определить дистрибутив для установки at. Установите вручную.${RESET}"
                exit 1
            fi
            systemctl enable --now atd
            echo -e "${GREEN}at успешно установлен и запущен.${RESET}"
        else
            echo -e "${RED}Для работы скрипта требуется at. Выход.${RESET}"
            exit 1
        fi
    fi
}

# === Функция для загрузки переменных из .env ===
function load_env_vars() {
    if [[ -f "$ENV_FILE" ]]; then
        export $(grep -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_NOTIFY_NODES_CHAT_ID)=' "$ENV_FILE" | sed 's/^/export /' | xargs -d '\n')
        TELEGRAM_BOT_TOKEN=$(echo "$TELEGRAM_BOT_TOKEN" | sed 's/^"\(.*\)"$/\1/')
        TELEGRAM_CHAT_ID=$(echo "$TELEGRAM_NOTIFY_NODES_CHAT_ID" | sed 's/^"\(.*\)"$/\1/')
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
        -d parse_mode="Markdown" > /dev/null 2>&1
}

# === Функция для конвертации времени ===
function convert_to_server_time() {
    local user_time="$1"
    local user_tz="$2"
    
    if [[ "$(date +%Z)" == "MSK" ]] || [[ "$(date +%Z)" == "+0300" ]]; then
        echo "$user_time"
    else
        local current_date=$(TZ="$user_tz" date +"%Y-%m-%d")
        local user_datetime="${current_date} ${user_time}"
        date --date="TZ=\"$user_tz\" $user_datetime" +"%H:%M"
    fi
}

# === Функция для планирования обновления ===
function schedule_update() {
    echo -e "${CYAN}Введите время одноразового обновления в формате HH:MM (по $TIMEZONE):${RESET}"
    read -p "Время: " time_input
    
    if [[ $time_input =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        server_time=$(convert_to_server_time "$time_input" "$TIMEZONE")
        
        if [[ -f "$AT_JOB_FILE" ]]; then
            atrm $(cat "$AT_JOB_FILE") 2>/dev/null
            rm -f "$AT_JOB_FILE"
        fi
        
        local at_cmd_file=$(mktemp)
        cat <<EOF > "$at_cmd_file"
#!/bin/bash
"$0" execute_update
EOF
        
        local job_info=$(at "$server_time" -f "$at_cmd_file" 2>&1)
        local job_id=$(echo "$job_info" | grep -oP 'job\s+\K\d+')
        
        if [[ -n "$job_id" ]]; then
            echo "$job_id" > "$AT_JOB_FILE"
            echo -e "${GREEN}Обновление запланировано на $time_input по $TIMEZONE${RESET}"
            if [[ "$server_time" != "$time_input" ]]; then
                echo -e " (серверное время: $server_time)"
            fi
            echo -e "ID задания at: $job_id"
            send_telegram "*📅 Запланировано обновление контейнеров в $time_input по $TIMEZONE*"
        else
            echo -e "${RED}Не удалось запланировать задание:${RESET}"
            echo "$job_info"
        fi
        rm -f "$at_cmd_file"
    else
        echo -e "${RED}Неверный формат времени. Попробуйте ещё раз.${RESET}"
    fi
}

# === Функция для проверки запланированного задания ===
function check_scheduled_job() {
    if [[ -f "$AT_JOB_FILE" ]]; then
        local job_id=$(cat "$AT_JOB_FILE")
        local job_info=$(at -l | grep "^${job_id}\b")
        
        if [[ -n "$job_info" ]]; then
            local exec_time=$(echo "$job_info" | awk '{print $3, $4, $5, $6}')
            local user_time=$(TZ="Europe/Moscow" date --date="TZ=\"$(date +%Z)\" $exec_time" +"%H:%M")
            
            echo -e "⏰ Запланировано обновление на: ${GREEN}$user_time${RESET} (по $TIMEZONE)"
            echo -e "ID задания at: $job_id"
            return 0
        else
            rm -f "$AT_JOB_FILE"
        fi
    fi
    echo "📭 Обновление не запланировано."
    return 1
}

# === Функция для выполнения обновления ===
function perform_update() {
    echo -e "${GREEN}Начинаем обновление контейнеров...${RESET}"
    send_telegram "*🚀 Обновление контейнеров началось...*"

    cd "$DOCKER_COMPOSE_DIR" || exit 1

    output=$( (ls) 2>&1 ) # это тест. замените потом на строку ниже
    # output=$( (docker compose down && docker compose pull && docker compose up -d) 2>&1 )
    log_output=$(docker compose logs | grep -E 'ERROR|error|Error|WARNING|warning|Warning')

    rm -f "$AT_JOB_FILE"

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
}

# === Основное меню ===
function show_menu() {
    echo -e "${CYAN}==== Менеджер обновлений контейнеров ====${RESET}"
    echo

    check_scheduled_job

    echo
    echo "1. Запланировать одноразовое обновление"
    echo "2. Принудительно выполнить обновление сейчас"
    echo "3. Отменить запланированное обновление"
    echo "4. Выйти"
    echo
    read -p "Выберите действие [1-4]: " choice

    case "$choice" in
        1) schedule_update ;;
        2) perform_update ;;
        3) 
            if [[ -f "$AT_JOB_FILE" ]]; then
                job_id=$(cat "$AT_JOB_FILE")
                atrm "$job_id"
                rm -f "$AT_JOB_FILE"
                echo -e "${GREEN}Запланированное обновление отменено.${RESET}"
                send_telegram "*❌ Запланированное обновление контейнеров отменено.*"
            else
                echo -e "${RED}Нет запланированных обновлений.${RESET}"
            fi
            ;;
        4) exit 0 ;;
        *) echo -e "${RED}Неверный выбор!${RESET}" ;;
    esac
}

# === Запуск ===
check_install_at
load_env_vars

if [[ "$1" == "execute_update" ]]; then
    perform_update >> /tmp/remna_update.log 2>&1
    rm -f "$AT_JOB_FILE"
else
    show_menu
fi
