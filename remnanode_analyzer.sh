#!/bin/bash
# Как установить и использовать:
# 
# Сохраните скрипт в файл, например, remnanode_analyzer.sh.
# nano remnanode_analyzer.sh
# Убедитесь, что утилита dialog установлена:
# sudo apt install dialog  # Для Ubuntu/Debian
# 
# Сделайте скрипт исполняемым:
# chmod +x remnanode_analyzer.sh
# Переместите скрипт в /usr/local/bin для удобного запуска:
# sudo mv remnanode_analyzer.sh /usr/local/bin/remnanode_analyzer
# Запустите скрипт:
# remnanode_analyzer
# 

# Путь к лог-файлу в контейнере
LOG_FILE="/var/log/supervisor/xray.out.log"
CONTAINER_NAME="remnanode"

# Московский часовой пояс (UTC+3)
MOSCOW_TIMEZONE="+03:00"

# Функция для конвертации времени в московский часовой пояс
convert_to_moscow_time() {
    local datetime="$1"
    date -d "${datetime} UTC" +"%Y/%m/%d %H:%M:%S" --date="${MOSCOW_TIMEZONE}" 2>/dev/null || echo "INVALID_DATE"
}

# Функция для получения всех пользователей из логов
get_all_users() {
    docker exec "$CONTAINER_NAME" tail -n +1 "$LOG_FILE" | grep -oP "email: \K\S+" | sort | uniq
}

# Функция для отображения активности пользователей
get_active_users() {
    local current_time=$(date +%s)
    local active_users=0

    docker exec "$CONTAINER_NAME" tail -n +1 "$LOG_FILE" | while read -r line; do
        local log_time=$(echo "$line" | awk '{print $1, $2}')
        local log_timestamp=$(date -d "$log_time" +%s 2>/dev/null)
        if [ -n "$log_timestamp" ]; then
            local diff=$((current_time - log_timestamp))
            if [ "$diff" -le 60 ]; then
                active_users=$((active_users + 1))
            fi
        fi
    done

    echo "$active_users"
}

# Функция для отображения истории подключений пользователя
show_user_history() {
    local user="$1"
    docker exec "$CONTAINER_NAME" tail -n +1 "$LOG_FILE" | grep -F "email: $user" | while read -r line; do
        local log_time=$(echo "$line" | awk '{print $1, $2}')
        local converted_time=$(convert_to_moscow_time "$log_time")
        if [ "$converted_time" != "INVALID_DATE" ]; then
            echo "$line" | sed "s/$log_time/$converted_time/"
        fi
    done
}

# Функция для отображения текущей активности пользователя
show_user_realtime() {
    local user="$1"
    docker exec "$CONTAINER_NAME" tail -f "$LOG_FILE" | grep --line-buffered -F "email: $user" | while read -r line; do
        local log_time=$(echo "$line" | awk '{print $1, $2}')
        local converted_time=$(convert_to_moscow_time "$log_time")
        if [ "$converted_time" != "INVALID_DATE" ]; then
            echo "$line" | sed "s/$log_time/$converted_time/"
        fi
    done
}

# Функция для отображения текущей активности в логах
show_logs_realtime() {
    docker exec "$CONTAINER_NAME" tail -f "$LOG_FILE" | while read -r line; do
        local log_time=$(echo "$line" | awk '{print $1, $2}')
        local converted_time=$(convert_to_moscow_time "$log_time")
        if [ "$converted_time" != "INVALID_DATE" ]; then
            echo "$line" | sed "s/$log_time/$converted_time/"
        fi
    done
}

# Функция для сохранения логов
save_logs() {
    local user="$1"
    local output_file="$2"

    if [ -z "$user" ]; then
        docker exec "$CONTAINER_NAME" tail -n +1 "$LOG_FILE" | while read -r line; do
            local log_time=$(echo "$line" | awk '{print $1, $2}')
            local converted_time=$(convert_to_moscow_time "$log_time")
            if [ "$converted_time" != "INVALID_DATE" ]; then
                echo "$line" | sed "s/$log_time/$converted_time/"
            fi
        done > "$output_file"
    else
        docker exec "$CONTAINER_NAME" tail -n +1 "$LOG_FILE" | grep -F "email: $user" | while read -r line; do
            local log_time=$(echo "$line" | awk '{print $1, $2}')
            local converted_time=$(convert_to_moscow_time "$log_time")
            if [ "$converted_time" != "INVALID_DATE" ]; then
                echo "$line" | sed "s/$log_time/$converted_time/"
            fi
        done > "$output_file"
    fi

    echo "Логи сохранены в файл $output_file"
}

# Функция для выбора пользователя через dialog
select_user() {
    local users=($(get_all_users))
    local options=()
    for i in "${!users[@]}"; do
        options+=("$i" "${users[$i]}")
    done

    local choice=$(dialog --clear --title "Выбор пользователя" --menu "Выберите пользователя:" 15 50 10 "${options[@]}" 2>&1 >/dev/tty)
    clear
    echo "${users[$choice]}"
}

# Главное меню
while true; do
    echo "Выберите действие:"
    echo "1) Показать список всех пользователей"
    echo "2) Показать количество активных пользователей (последнее подключение не старше минуты)"
    echo "3) Показать историю подключений пользователя"
    echo "4) Показать текущую активность пользователя"
    echo "5) Показать текущую активность в логах"
    echo "6) Сохранить логи"
    echo "7) Обновить скрипт"
    echo "8) Выйти"
    read -rp "Введите номер действия: " choice

    case $choice in
        1)
            echo "Список всех пользователей:"
            get_all_users
            ;;
        2)
            echo "Количество активных пользователей:"
            get_active_users
            ;;
        3)
            user=$(select_user)
            if [ -n "$user" ]; then
                echo "История подключений пользователя $user:"
                show_user_history "$user"
            else
                echo "Пользователь не выбран."
            fi
            ;;
        4)
            user=$(select_user)
            if [ -n "$user" ]; then
                echo "Текущая активность пользователя $user:"
                show_user_realtime "$user"
            else
                echo "Пользователь не выбран."
            fi
            ;;
        5)
            echo "Текущая активность в логах:"
            show_logs_realtime
            ;;
        6)
            user=$(select_user)
            read -rp "Введите имя файла для сохранения логов: " output_file
            save_logs "$user" "$output_file"
            ;;
        7)
            echo "Обновление скрипта..."
            exec "$0"
            ;;
        8)
            echo "Выход..."
            exit 0
            ;;
        *)
            echo "Неверный выбор, попробуйте снова."
            ;;
    esac
done
