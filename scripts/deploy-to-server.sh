#!/usr/bin/env bash
# Универсальный деплой на ЛЮБОЙ сервер (виртуалка или реальный VPS).
# Использование: SERVER_IP=192.168.56.10 SERVER_USER=student ./scripts/deploy-to-server.sh
# Опционально: SSH_PORT=2222 (если NAT с пробросом)
set -e
: "${SERVER_IP:?Укажи: SERVER_IP=... }"
: "${SERVER_USER:?Укажи: SERVER_USER=... }"
SSH_PORT="${SSH_PORT:-22}"
cd "$(dirname "$0")/.."

echo "==> 1. Проверяю SSH..."
ssh -p "$SSH_PORT" -o ConnectTimeout=10 "$SERVER_USER@$SERVER_IP" "echo OK: ssh работает"

echo "==> 2. Ставлю Docker (если ещё нет)..."
ssh -p "$SSH_PORT" "$SERVER_USER@$SERVER_IP" "command -v docker >/dev/null || { curl -fsSL https://get.docker.com | sudo sh; sudo usermod -aG docker \$USER; }"

echo "==> 3. Перекидываю проект через scp..."
ssh -p "$SSH_PORT" "$SERVER_USER@$SERVER_IP" "mkdir -p ~/myapp"
scp -P "$SSH_PORT" -r backend frontend docker-compose.yml "$SERVER_USER@$SERVER_IP:~/myapp/"

echo "==> 4. Собираю и запускаю..."
ssh -p "$SSH_PORT" "$SERVER_USER@$SERVER_IP" "cd ~/myapp && docker compose up -d --build && docker compose ps"

echo ""
echo "✅ ГОТОВО!"
echo "   Фронтенд: http://$SERVER_IP (или http://localhost:$WEB_PORT если NAT)"
echo "   API:      http://$SERVER_IP:8000/api/hello/"
