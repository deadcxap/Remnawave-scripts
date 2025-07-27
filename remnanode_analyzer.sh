#!/bin/bash

# # Этот Bash-скрипт предназначен для мониторинга и анализа логов Xray ноды Remnawave в контейнере Docker. 
# 
# # 🔹 Основные возможности:
# # ✅ Просмотр списка последних пользователей – показывает всех пользователей, которые подключались к серверу (из последних 1000 строк лога).
# # ✅ Мониторинг подключений в реальном времени – можно выбрать конкретного пользователя и следить за его активностью (tail -f).
# # ✅ Отслеживание всех подключений – вывод логов в реальном времени для всех пользователей.
# # ✅ Автоматическое обновление данных – можно быстро обновить список последних пользователей

# Цвета для оформления
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Настройки
CONTAINER_NAME="remnanode"
LOG_PATH="/var/log/remnanode/access.log"
LOG_LINES=1000 # Количество анализируемых строк лога

# Функция для быстрого получения логов
get_recent_logs() {
    docker exec "$CONTAINER_NAME" tail -n $LOG_LINES "$LOG_PATH" 2>/dev/null
}

# Функция для получения списка пользователей
get_users() {
    get_recent_logs | grep -o "email: [^ ]*" | awk '{print $2}' | sort -u
}

# Функция для реального времени просмотра логов пользователя
tail_user_logs() {
    local user="$1"
    echo -e "${YELLOW}Следим за логами пользователя $user (Ctrl+C для остановки)...${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    docker exec -it "$CONTAINER_NAME" tail -n 10 -f "$LOG_PATH" | \
    grep --line-buffered "accepted.*email: $user"
}

# Функция для просмотра всех логов в реальном времени
tail_all_logs() {
    echo -e "${YELLOW}Следим за всеми подключениями в реальном времени (Ctrl+C для остановки)...${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    docker exec -it "$CONTAINER_NAME" tail -n 10 -f "$LOG_PATH" | \
    grep --line-buffered "accepted"
}

# Главное меню
while true; do
    clear
    
    # Получаем данные
    all_users=($(get_users))
    
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${CYAN}      Анализатор логов Xray ($CONTAINER_NAME)${NC}"
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${YELLOW}1) Показать список последних пользователей (всего: ${#all_users[@]})${NC}"
    echo -e "${YELLOW}2) Смотреть подключения пользователя в реальном времени${NC}"
    echo -e "${YELLOW}3) Смотреть ВСЕ подключения в реальном времени${NC}"
    echo -e "${YELLOW}4) Обновить данные${NC}"
    echo -e "${RED}0) Выход${NC}"
    echo -e "${GREEN}-----------------------------------------------${NC}"
    
    read -p "$(echo -e ${CYAN}'Ваш выбор: '${NC})" choice
    
    case $choice in
        1)
            clear
            echo -e "${CYAN}Список последних пользователей:${NC}"
            echo -e "${BLUE}--------------------------${NC}"
            for i in "${!all_users[@]}"; do
                echo -e "${YELLOW}$((i+1))) ${all_users[i]}${NC}"
            done
            echo -e "${BLUE}--------------------------${NC}"
            read -p "$(echo -e ${CYAN}'Нажмите Enter для возврата в меню...'${NC})" 
            ;;
        2)
            clear
            if [ ${#all_users[@]} -eq 0 ]; then
                echo -e "${RED}Не найдено пользователей в логах.${NC}"
                read -p "$(echo -e ${CYAN}'Нажмите Enter для возврата в меню...'${NC})"
                continue
            fi
            
            echo -e "${CYAN}Список пользователей:${NC}"
            for i in "${!all_users[@]}"; do
                echo -e "${YELLOW}$((i+1))) ${all_users[i]}${NC}"
            done
            
            read -p "$(echo -e ${CYAN}'Выберите номер пользователя: '${NC})" user_num
            if [[ ! "$user_num" =~ ^[0-9]+$ ]] || [ "$user_num" -lt 1 ] || [ "$user_num" -gt ${#all_users[@]} ]; then
                echo -e "${RED}Неверный выбор.${NC}"
                read -p "$(echo -e ${CYAN}'Нажмите Enter для возврата в меню...'${NC})"
                continue
            fi
            
            user="${all_users[$((user_num-1))]}"
            clear
            tail_user_logs "$user"
            ;;
        3)
            clear
            tail_all_logs
            ;;
        4)
            # Просто обновим экран
            ;;
        0)
            echo -e "${RED}Выход...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
            sleep 1
            ;;
    esac
done
