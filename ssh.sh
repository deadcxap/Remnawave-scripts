#!/bin/bash

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== АВТОМАТИЧЕСКАЯ НАСТРОЙКА SSH ===${NC}"

# Проверка пользователя
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}❌ Скрипт должен быть запущен от root или через sudo.${NC}"
  exit 1
else
  echo -e "${GREEN}✅ Скрипт запущен с root-доступом.${NC}"
fi

# Запрос SSH-ключа
echo ""
echo -e "${CYAN}➡️ Вставьте ваш SSH-ключ из Windows (например, из C:\\Users\\WORK\\.ssh\\id_rsa.pub):${NC}"
read -rp ">>> " SSH_KEY

# Запрос порта
read -rp "$(echo -e "${CYAN}➡️ Укажите желаемый порт для SSH (например, 2222):${NC} ")" SSH_PORT

# Запрос настройки UFW
echo -e "${CYAN}➡️ Настроить UFW для нового SSH-порта?${NC}"
echo "1) Да"
echo "2) Нет"
read -rp ">>> " SETUP_UFW

# === Шаг 1: ~/.ssh ===
SSH_DIR="$HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -n "$SSH_KEY" ]]; then
  echo "$SSH_KEY" >> "$AUTHORIZED_KEYS"
  chmod 600 "$AUTHORIZED_KEYS"
  echo -e "${GREEN}✅ Ключ добавлен в $AUTHORIZED_KEYS${NC}"
else
  echo -e "${RED}❌ Ключ не был введён. Прерывание.${NC}"
  exit 1
fi

# === Шаг 2: sshd_config ===
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "$SSHD_CONFIG.bak"

update_sshd_config() {
  PARAM="$1"
  VALUE="$2"
  if grep -qE "^#?\s*${PARAM}" "$SSHD_CONFIG"; then
    sed -i "s|^#\?\s*${PARAM}.*|${PARAM} ${VALUE}|g" "$SSHD_CONFIG"
  else
    echo "${PARAM} ${VALUE}" >> "$SSHD_CONFIG"
  fi
}

update_sshd_config "Port" "$SSH_PORT"
update_sshd_config "PubkeyAuthentication" "yes"
update_sshd_config "PasswordAuthentication" "no"
update_sshd_config "PermitEmptyPasswords" "no"
update_sshd_config "Protocol" "2"
update_sshd_config "DebianBanner" "no"

echo -e "${GREEN}✅ Конфигурация SSH обновлена.${NC}"

# === Шаг 3: UFW ===
FIREWALL_STATUS="не настроен"

if [[ "$SETUP_UFW" == "1" ]]; then
  echo -e "${CYAN}🔧 Настройка UFW...${NC}"
  if ! command -v ufw >/dev/null 2>&1; then
    echo "UFW не установлен. Устанавливаем..."
    apt update && apt install -y ufw
  fi

  ufw allow "$SSH_PORT"/tcp
  ufw delete allow 22/tcp 2>/dev/null || true

  ufw disable
  ufw --force enable

  FIREWALL_STATUS="включён (разрешён порт $SSH_PORT)"
  echo -e "${GREEN}✅ UFW настроен.${NC}"
fi

# === Финал: перезапуск SSH ===
systemctl restart sshd

# === Очистка экрана и вывод отчёта ===
clear
echo -e "${CYAN}==============================${NC}"
echo -e "${GREEN}✅ SSH НАСТРОЕН УСПЕШНО!${NC}"
echo ""
echo -e "${CYAN}🔐 Используемый SSH-порт: ${GREEN}${SSH_PORT}${NC}"
echo -e "${CYAN}📂 SSH-ключ сохранён в: ${GREEN}${AUTHORIZED_KEYS}${NC}"
echo -e "${CYAN}🧱 Статус фаервола (UFW): ${GREEN}${FIREWALL_STATUS}${NC}"
echo -e "${CYAN}📄 Бэкап sshd_config: ${GREEN}${SSHD_CONFIG}.bak${NC}"
echo ""
echo -e "${CYAN}⚠️ Перед выходом из этой сессии ОБЯЗАТЕЛЬНО проверьте подключение по новому порту!${NC}"
echo -e "${CYAN}==============================${NC}"
