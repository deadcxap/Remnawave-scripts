#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="/backup"
REMNAWAVE_DIR="/opt/remnawave"
DOCKER_COMPOSE_FILE="$REMNAWAVE_DIR/docker-compose.yml"
DOCKER_VOLUMES=("remnawave-db-data" "remnawave-redis-data")
LOG_FILE="/var/log/vps_backup_restore.log"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root${NC}"
  exit 1
fi

# Create backup directory if not exists
mkdir -p "$BACKUP_DIR"

backup() {
  local backup_name="docker-backup-$(date +%F-%H-%M-%S)"
  local temp_dir="/tmp/$backup_name"
  mkdir -p "$temp_dir"
  
  echo -e "${YELLOW}Starting Docker backup process...${NC}"
  
  # 1. Stop Docker containers if they exist
  if [ -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${YELLOW}Stopping Docker containers...${NC}"
    cd "$REMNAWAVE_DIR" && docker compose down
  fi
  
  # 2. Backup Docker volumes
  echo -e "${YELLOW}Backing up Docker volumes...${NC}"
  mkdir -p "$temp_dir/docker/volumes"
  
  for volume in "${DOCKER_VOLUMES[@]}"; do
    if docker volume inspect "$volume" &>/dev/null; then
      echo "Backing up volume $volume..."
      docker run --rm -v "$volume:/volume" -v "$temp_dir/docker/volumes:/backup" alpine \
        sh -c "cd /volume && tar -czf /backup/$volume.tar.gz ."
    fi
  done
  
  # 3. Create final archive
  echo -e "${YELLOW}Creating backup archive...${NC}"
  tar -cvpzf "$BACKUP_DIR/$backup_name.tar.gz" -C /tmp "$backup_name"
  
  # 4. Start Docker containers back if they were running
  if [ -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${YELLOW}Starting Docker containers...${NC}"
    cd "$REMNAWAVE_DIR" && docker compose up -d
  fi
  
  # Cleanup
  rm -rf "$temp_dir"
  
  echo -e "${GREEN}Backup completed successfully!${NC}"
  echo -e "Backup file: ${GREEN}$BACKUP_DIR/$backup_name.tar.gz${NC}"
  echo -e "Size: $(du -sh "$BACKUP_DIR/$backup_name.tar.gz" | cut -f1)"
}

restore() {
  echo -e "${YELLOW}Available backups:${NC}"
  local backups=($(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
  
  if [ ${#backups[@]} -eq 0 ]; then
    echo -e "${RED}No backups found in $BACKUP_DIR${NC}"
    return 1
  fi
  
  for i in "${!backups[@]}"; do
    echo "[$i] ${backups[$i]}"
  done
  
  read -p "Enter backup number to restore: " backup_num
  
  if [[ ! "$backup_num" =~ ^[0-9]+$ ]] || [ "$backup_num" -ge ${#backups[@]} ]; then
    echo -e "${RED}Invalid backup number${NC}"
    return 1
  fi
  
  local selected_backup="${backups[$backup_num]}"
  local temp_dir="/tmp/restore-$(date +%s)"
  
  echo -e "${YELLOW}Starting restore from $selected_backup...${NC}"
  
  # Check disk space
  local required_space=$(du -s "$selected_backup" | cut -f1)
  local available_space=$(df --output=avail / | tail -n1 | tr -d ' ')
  
  if [ "$required_space" -gt "$available_space" ]; then
    echo -e "${RED}Not enough disk space! Required: $required_space, Available: $available_space${NC}"
    return 1
  fi
  
  # Extract backup
  mkdir -p "$temp_dir"
  tar -xvpzf "$selected_backup" -C "$temp_dir" --strip-components=1
  
  # 1. Stop Docker if running
  if docker compose version &>/dev/null && [ -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${YELLOW}Stopping Docker containers...${NC}"
    cd "$REMNAWAVE_DIR" && docker compose down
  fi
  
  # 2. Restore Docker volumes
  echo -e "${YELLOW}Restoring Docker volumes...${NC}"
  
  for volume in "${DOCKER_VOLUMES[@]}"; do
    if [ -f "$temp_dir/docker/volumes/$volume.tar.gz" ]; then
      echo "Restoring volume $volume..."
      docker volume create "$volume" 2>/dev/null || true
      docker run --rm -v "$volume:/volume" -v "$temp_dir/docker/volumes:/backup" alpine \
        sh -c "find /volume -delete && tar -xzf /backup/$volume.tar.gz -C /volume"
    fi
  done
  
  # 3. Start Docker containers
  if [ -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${YELLOW}Starting Docker containers...${NC}"
    cd "$REMNAWAVE_DIR" && docker compose up -d --build
  fi
  
  # Cleanup
  rm -rf "$temp_dir"
  
  echo -e "${GREEN}Restore completed successfully!${NC}"
  echo -e "${YELLOW}Recommended actions:${NC}"
  echo -e "1. Check Docker containers: ${GREEN}docker ps -a${NC}"
  echo -e "Full log available at: ${GREEN}$LOG_FILE${NC}"
}

menu() {
  while true; do
    echo -e "\n${YELLOW}==== Docker Backup/Restore Menu ====${NC}"
    echo "1) Create Docker backup"
    echo "2) Restore from Docker backup"
    echo "3) Exit"
    read -p "Choose an option: " choice
    
    case $choice in
      1) backup ;;
      2) restore ;;
      3) exit 0 ;;
      *) echo -e "${RED}Invalid option${NC}" ;;
    esac
  done
}

# Start menu
menu
