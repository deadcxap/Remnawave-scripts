#!/bin/bash

# === АВТОМАТИЧЕСКАЯ НАСТРОЙКА SSH ===
# Скрипт для настройки SSH-сервера:
# 1. Добавляет публичный SSH-ключ пользователя в authorized_keys (избегая дубликатов).
# 2. Изменяет стандартный порт SSH.
# 3. Отключает аутентификацию по паролю.
# 4. Опционально настраивает фаервол UFW.
# 5. Обеспечивает идемпотентность (повторные запуски не ломают конфигурацию).

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== АВТОМАТИЧЕСКАЯ НАСТРОЙКА SSH ===${NC}"

# --- Проверка запуска от имени root ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}❌ ОШИБКА: Скрипт должен быть запущен от имени пользователя root или через sudo.${NC}"
  exit 1
else
  echo -e "${GREEN}✅ Проверка прав: Скрипт запущен с root-доступом.${NC}"
fi

# --- Определение домашней директории целевого пользователя ---
TARGET_USER_HOME="$HOME"
TARGET_USER=$(basename "$TARGET_USER_HOME")

if [[ "$TARGET_USER_HOME" == "/root" ]]; then
    echo -e "${CYAN}ℹ️ Ключ будет добавлен для пользователя 'root' ($TARGET_USER_HOME/.ssh).${NC}"
else
    echo -e "${YELLOW}⚠️ ПРЕДУПРЕЖДЕНИЕ: Ключ будет добавлен для пользователя '$TARGET_USER' ($TARGET_USER_HOME/.ssh). Убедитесь, что это нужный пользователь.${NC}"
    if ! id "$TARGET_USER" &>/dev/null; then
        echo -e "${RED}❌ ОШИБКА: Пользователь '$TARGET_USER' не найден в системе. Проверьте значение TARGET_USER_HOME.${NC}"
        exit 1
    fi
fi
echo ""

# --- Разбор параметров командной строки ---
DEFAULT_SSH_PORT=2222
SSH_PORT="$DEFAULT_SSH_PORT"
SSH_KEY=""

show_usage() {
  echo -e "${CYAN}Использование: $0 [-p порт (1-65535)] [-k '\"public_ssh_key\"']${NC}"
  exit 1
}

while getopts ":p:k:" opt; do
  case $opt in
    p)
      SSH_PORT="$OPTARG"
      ;;
    k)
      SSH_KEY="$OPTARG"
      ;;
    \?)
      echo -e "${RED}❌ Неизвестный параметр -$OPTARG${NC}"
      show_usage
      ;;
    :)  
      echo -e "${RED}❌ Опция -$OPTARG требует аргумента.${NC}"
      show_usage
      ;;
  esac
done
shift $((OPTIND -1))

# --- Валидация порта (если указан через параметр) ---
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1 ]] || [[ "$SSH_PORT" -gt 65535 ]]; then
  echo -e "${RED}❌ Неверный номер порта. Должен быть число от 1 до 65535.${NC}"
  exit 1
else
  echo -e "${GREEN}✅ Порт SSH установлен: ${SSH_PORT}.${NC}"
fi

echo ""
# --- Чтение SSH-ключа (если не передан через параметр) ---
if [[ -z "$SSH_KEY" ]]; then
  echo -e "${CYAN}➡️ Вставьте ваш ПУБЛИЧНЫЙ SSH-ключ (содержимое файла .pub, например, id_rsa.pub):${NC}"
  while [[ -z "$SSH_KEY" ]]; do
    read -rp ">>> " SSH_KEY
    if [[ -z "$SSH_KEY" ]]; then
      echo -e "${YELLOW} Поле не может быть пустым. Пожалуйста, вставьте ключ.${NC}"
    elif ! [[ "$SSH_KEY" =~ ^ssh-(rsa|ed25519|ecdsa|dss) ]]; then
       echo -e "${RED}❌ Введенная строка не похожа на публичный SSH-ключ (должна начинаться с ssh-rsa, ssh-ed25519 и т.п.). Попробуйте снова.${NC}"
       SSH_KEY=""
    fi
  done
  echo -e "${GREEN}✅ Ключ принят.${NC}"
else
  echo -e "${GREEN}✅ Ключ принят из параметра.${NC}"
fi

echo ""
# --- Настройка UFW ---
SETUP_UFW=""
echo -e "${CYAN}➡️ Настроить фаервол UFW для нового SSH-порта (${SSH_PORT})?${NC}"
echo "   1) Да (рекомендуется, если UFW используется или планируется)"
echo "   2) Нет"
while [[ "$SETUP_UFW" != "1" && "$SETUP_UFW" != "2" ]]; do
    read -rp ">>> Ваш выбор [1/2]: " SETUP_UFW
    if [[ "$SETUP_UFW" != "1" && "$SETUP_UFW" != "2" ]]; then
        echo -e "${RED}❌ Неверный выбор. Введите 1 или 2.${NC}"
    fi
done
if [[ "$SETUP_UFW" == "1" ]]; then
    echo -e "${GREEN}✅ UFW будет настроен.${NC}"
else
    echo -e "${YELLOW}ℹ️ UFW настраиваться не будет. Убедитесь, что порт ${SSH_PORT} разрешен в вашем фаерволе вручную, если он активен.${NC}"
fi

echo ""
# === Шаг 1: Настройка каталога .ssh и файла authorized_keys ===
echo -e "${CYAN}--- Шаг 1: Настройка SSH-ключа для пользователя '$TARGET_USER' ---${NC}"
SSH_DIR="$TARGET_USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

echo -e "🔧 Создание каталога $SSH_DIR (если не существует)..."
mkdir -p "$SSH_DIR"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ ОШИБКА: Не удалось создать каталог $SSH_DIR.${NC}"
    exit 1
fi

echo -e "🔧 Установка прав доступа для $SSH_DIR (700)..."
chmod 700 "$SSH_DIR"

echo -e "🔧 Создание файла $AUTHORIZED_KEYS (если не существует)..."
touch "$AUTHORIZED_KEYS"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ ОШИБКА: Не удалось создать файл $AUTHORIZED_KEYS.${NC}"
    exit 1
fi

echo -e "🔧 Установка прав доступа для $AUTHORIZED_KEYS (600)..."
chmod 600 "$AUTHORIZED_KEYS"

echo -e "🔧 Проверка наличия ключа в $AUTHORIZED_KEYS..."
if grep -q -F -x "$SSH_KEY" "$AUTHORIZED_KEYS"; then
  echo -e "${YELLOW}ℹ️ Этот SSH-ключ уже существует в файле $AUTHORIZED_KEYS. Добавление пропущено.${NC}"
else
  echo -e "🔧 Добавление ключа в $AUTHORIZED_KEYS..."
  if [[ -s "$AUTHORIZED_KEYS" ]] && [[ "$(tail -c 1 "$AUTHORIZED_KEYS")" != "" ]]; then
      echo "" >> "$AUTHORIZED_KEYS"
  fi
  echo "$SSH_KEY" >> "$AUTHORIZED_KEYS"
  echo -e "${GREEN}✅ Ключ успешно добавлен в $AUTHORIZED_KEYS.${NC}"
fi

echo -e "🔧 Установка владельца каталога $SSH_DIR и его содержимого на '$TARGET_USER'..."
chown -R "${TARGET_USER}:${TARGET_USER}" "$SSH_DIR" 2>/dev/null || echo -e "${YELLOW}⚠️ Не удалось изменить владельца $SSH_DIR. Убедитесь, что права установлены вручную, если пользователь не root.${NC}"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTHORIZED_KEYS"
echo ""

# === Шаг 2: Настройка файла конфигурации SSH (/etc/ssh/sshd_config) ===
echo -e "${CYAN}--- Шаг 2: Настройка конфигурации SSH-сервера ---${NC}"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP="${SSHD_CONFIG}.bak_$(date +%Y%m%d_%H%M%S)"

echo -e "🔧 Создание резервной копии $SSHD_CONFIG в ${SSHD_CONFIG_BACKUP}..."
cp "$SSHD_CONFIG" "$SSHD_CONFIG_BACKUP"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ ОШИБКА: Не удалось создать резервную копию конфигурационного файла SSH.${NC}"
    echo -e "${YELLOW}⚠️ Предупреждение: Продолжаем без резервной копии.${NC}"
else
    echo -e "${GREEN}✅ Резервная копия создана: ${SSHD_CONFIG_BACKUP}${NC}"
fi

update_sshd_config() {
  local PARAM="$1"
  local VALUE="$2"
  local CONFIG_FILE="$3"
  local CURRENT_VALUE
  local LINE_EXISTS=false
  local IS_COMMENTED=false

  if grep -qE "^\s*#?\s*${PARAM}\s+" "$CONFIG_FILE"; then
      LINE_EXISTS=true
      if grep -qE "^\s*#\s*${PARAM}\s+" "$CONFIG_FILE"; then
          IS_COMMENTED=true
      fi
      CURRENT_VALUE=$(grep -E "^\s*${PARAM}\s+" "$CONFIG_FILE" | awk '{print $2}' | head -n 1)
  fi

  if [[ "$LINE_EXISTS" == true && "$IS_COMMENTED" == false && "$CURRENT_VALUE" == "$VALUE" ]]; then
      echo -e "${CYAN}ℹ️ Параметр '${PARAM}' уже установлен в '${VALUE}'. Изменения не требуются.${NC}"
  else
      echo -e "🔧 Установка параметра '${PARAM}' в '${VALUE}'..."
      if [[ "$LINE_EXISTS" == true ]]; then
          sed -i -E "s/^\s*#?\s*${PARAM}\s+.*/${PARAM} ${VALUE}/g" "$CONFIG_FILE"
          echo -e "${GREEN}✅ Параметр '${PARAM}' установлен (замена/раскомментирование).${NC}"
      else
          echo "${PARAM} ${VALUE}" >> "$CONFIG_FILE"
          echo -e "${GREEN}✅ Параметр '${PARAM}' установлен (добавление).${NC}"
      fi
  fi
}

echo -e "🔧 Обновление параметров в $SSHD_CONFIG..."
update_sshd_config "Port" "$SSH_PORT" "$SSHD_CONFIG"
update_sshd_config "PubkeyAuthentication" "yes" "$SSHD_CONFIG"
update_sshd_config "PasswordAuthentication" "no" "$SSHD_CONFIG"
update_sshd_config "ChallengeResponseAuthentication" "no" "$SSHD_CONFIG"
update_sshd_config "UsePAM" "no" "$SSHD_CONFIG"
update_sshd_config "PermitEmptyPasswords" "no" "$SSHD_CONFIG"
update_sshd_config "PermitRootLogin" "prohibit-password" "$SSHD_CONFIG"
echo ""

# === Шаг 3: Настройка фаервола UFW ===
echo -e "${CYAN}--- Шаг 3: Настройка фаервола UFW ---${NC}"
FIREWALL_STATUS="не настроен (пропущено пользователем)"

if [[ "$SETUP_UFW" == "1" ]]; then
  echo -e "🔧 Проверка наличия UFW..."
  if ! command -v ufw >/dev/null 2>&1; then
    echo -e "${YELLOW} Команда 'ufw' не найдена. Попытка установки пакета 'ufw'...${NC}"
    apt update > /dev/null && apt install -y ufw
    if ! command -v ufw >/dev/null 2>&1; then
       echo -e "${RED}❌ ОШИБКА: Не удалось установить UFW. Пропустите этот шаг или установите вручную ('apt install ufw').${NC}"
       FIREWALL_STATUS="не настроен (ошибка установки UFW)"
       SETUP_UFW="2"
    else
       echo -e "${GREEN}✅ UFW успешно установлен.${NC}"
    fi
  else
      echo -e "${GREEN}✅ UFW найден в системе.${NC}"
  fi

  if [[ "$SETUP_UFW" == "1" ]]; then
    echo -e "🔧 Разрешение входящих соединений на порт ${SSH_PORT}/tcp..."
    ufw allow "${SSH_PORT}/tcp" comment "Allow SSH on custom port set by script"
    if [[ "$SSH_PORT" -ne 22 ]]; then
      echo -e "🔧 Удаление правила для стандартного порта 22/tcp (если существует)..."
      ufw delete allow 22/tcp > /dev/null 2>&1
      ufw delete allow ssh > /dev/null 2>&1
      echo -e "${CYAN}ℹ️ Правило для порта 22/tcp удалено (если было).${NC}"
    else
      echo -e "${CYAN}ℹ️ Новый порт SSH совпадает со стандартным (22). Правило для порта 22 не удаляется.${NC}"
    fi

    UFW_CURRENT_STATUS=$(ufw status | head -n 1)
    if [[ "$UFW_CURRENT_STATUS" == "Status: active" ]]; then
        echo -e "🔧 UFW уже активен. Перезагрузка правил..."
        ufw reload
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✅ Правила UFW перезагружены.${NC}"
            FIREWALL_STATUS="активен, правила обновлены (порт ${SSH_PORT}/tcp разрешен)"
        else
            echo -e "${RED}❌ ОШИБКА: Не удалось перезагрузить правила UFW.${NC}"
            FIREWALL_STATUS="ошибка перезагрузки правил"
        fi
    elif [[ "$UFW_CURRENT_STATUS" == "Status: inactive" ]]; then
        echo -e "🔧 UFW неактивен. Включение UFW..."
        yes | ufw enable
        if ufw status | grep -qw active; then
            echo -e "${GREEN}✅ UFW успешно включен и настроен.${NC}"
            FIREWALL_STATUS="активен (порт ${SSH_PORT}/tcp разрешен)"
        else
            echo -e "${RED}❌ ОШИБКА: Не удалось активировать UFW.${NC}"
            FIREWALL_STATUS="ошибка активации"
        fi
    else
         echo -e "${RED}❌ ОШИБКА: Не удалось определить статус UFW. Проверьте вручную ('ufw status').${NC}"
         FIREWALL_STATUS="неизвестный статус"
    fi
  fi
fi

echo ""
# === Шаг 4: Перезапуск службы SSH ===
echo -e "${CYAN}--- Шаг 4: Перезапуск службы SSH ---${NC}"
echo -e "🔧 Перезапуск службы ssh для применения изменений..."
systemctl daemon-reload
systemctl restart ssh.socket

if systemctl is-active --quiet ssh.socket; then
    echo -e "${GREEN}✅ Служба SSH (ssh.socket) успешно перезапущена и активна.${NC}"
else
    echo -e "${RED}❌ КРИТИЧЕСКАЯ ОШИБКА: Не удалось перезапустить службу SSH!${NC}"
    echo -e "${RED}   Возможно, в конфигурации ${SSHD_CONFIG} есть синтаксическая ошибка.${NC}"
    echo -e "${YELLOW}   Проверьте конфигурацию вручную: ${CYAN}sshd -t${NC}"
    echo -e "${YELLOW}   Проверьте логи службы: ${CYAN}journalctl -u ssh.socket -e${NC}"
    echo -e "${YELLOW}   Вы можете восстановить предыдущую конфигурацию из бэкапа: ${GREEN}${SSHD_CONFIG_BACKUP}${NC}"
    echo -e "${YELLOW}   Команда восстановления: ${CYAN}cp ${SSHD_CONFIG_BACKUP} ${SSHD_CONFIG} && systemctl restart ssh.socket${NC}"
fi

echo ""
# === Финал: Вывод отчета ===
echo -e "${CYAN}=======================================================${NC}"
echo -e "${GREEN}✅ НАСТРОЙКА SSH ЗАВЕРШЕНА УСПЕШНО!${NC}"
echo -e "${CYAN}=======================================================${NC}"
echo ""
echo -e "${CYAN}📊 Сводка конфигурации:${NC}"
echo -e "  ${CYAN}👤 Пользователь для SSH-ключа: ${GREEN}${TARGET_USER} (${TARGET_USER_HOME})${NC}"
echo -e "  ${CYAN}📂 Файл с ключами: ${GREEN}${AUTHORIZED_KEYS}${NC}"
echo -e "  ${CYAN}🔐 Порт SSH: ${GREEN}${SSH_PORT}${NC}"
echo -e "  ${CYAN}🔑 Аутентификация по паролю: ${RED}ОТКЛЮЧЕНА${NC}"
echo -e "  ${CYAN}🧱 Статус фаервола (UFW): ${GREEN}${FIREWALL_STATUS}${NC}"
echo -e "  ${CYAN}📄 Резервная копия конфиг. SSH: ${GREEN}${SSHD_CONFIG_BACKUP}${NC}"
echo ""
echo -e "${CYAN}=======================================================${NC}"
echo -e "${RED}⚠️ ВАЖНО! ПРОВЕРЬТЕ ПОДКЛЮЧЕНИЕ ПЕРЕД ВЫХОДОМ!${NC}"
echo -e "${CYAN}=======================================================${NC}"
echo -e "${YELLOW}Прежде чем закрывать текущую консоль, откройте НОВУЮ и выполните:${NC}"
echo -e "${CYAN}   ssh ${TARGET_USER}@<IP_адрес_или_имя_сервера> -p ${SSH_PORT}${NC}"
echo ""
echo -e "${YELLOW}Убедитесь, что вы можете войти, используя ваш SSH-ключ, и что вход по паролю НЕ запрашивается.${NC}"
echo -e "${YELLOW}Если подключение не удалось, проверьте логи и конфигурацию или восстановите бэкап.${NC}"
echo -e "${CYAN}=======================================================${NC}"

en

