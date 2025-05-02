#!/bin/bash

set -e

echo "Удаляем старые версии Docker и Docker Compose..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-compose || true

echo "Обновляем apt и устанавливаем зависимости..."
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

echo "Добавляем официальный GPG ключ Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "Добавляем репозиторий Docker в APT..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Устанавливаем последнюю версию Docker и Docker Compose..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Проверка версий:"
docker --version
docker compose version

echo "Готово! Используйте 'docker compose' вместо 'docker-compose'"
