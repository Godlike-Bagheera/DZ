#!/usr/bin/env bash
# =============================================================================
# vm-setup.sh — полная автоматизация: РЕД ОС (хост) -> VirtualBox Ubuntu (гость)
# Работает БЕЗ sudo и БЕЗ sshpass/expect: автологин через Python + paramiko
# (ставится в ~/.local через pip --user, если его нет).
#
# ЗАПУСК с хоста из папки проекта DZ:
#   VM_PASS=пароль_от_виртуалки bash scripts/vm-setup.sh
#
# Параметры (есть значения по умолчанию):
#   VM_HOST (127.0.0.1)  VM_SSH_PORT (2222)  VM_USER (stud)  VM_PASS (обязательно)
# =============================================================================
set -uo pipefail

VM_HOST="${VM_HOST:-127.0.0.1}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
VM_USER="${VM_USER:-stud}"
VM_PASS="${VM_PASS:-}"

if [ -z "$VM_PASS" ]; then
  echo "[!] Не задан пароль виртуалки. Запусти так:"
  echo "    VM_PASS=твой_пароль bash scripts/vm-setup.sh"
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSH_AUTO="$PROJECT_DIR/scripts/ssh_auto.py"
PY="$(command -v python3 || command -v python)"
[ -z "$PY" ] && { echo "[!] Не найден python3 на хосте."; exit 1; }

# --- 0. Убедиться, что paramiko доступен -------------------------------------
if ! "$PY" -c "import paramiko" 2>/dev/null; then
  echo "==> 0. Ставлю python-модуль paramiko в ~/.local (без sudo)..."
  "$PY" -m pip install --user paramiko >/dev/null 2>&1
  if ! "$PY" -c "import paramiko" 2>/dev/null; then
    # вариант для систем с externally-managed-environment
    "$PY" -m pip install --user --break-system-packages paramiko >/dev/null 2>&1
  fi
  if ! "$PY" -c "import paramiko" 2>/dev/null; then
    echo "[!] Не удалось поставить paramiko. Пришли вывод команды:"
    echo "    $PY -m pip install --user paramiko"
    exit 1
  fi
  echo "    ОК"
fi

run_ssh() { "$PY" "$SSH_AUTO" run "$VM_HOST" "$VM_SSH_PORT" "$VM_USER" "$VM_PASS" "$@"; }

echo "==> 1. Проверка SSH-доступа к виртуалке ($VM_USER@$VM_HOST:$VM_SSH_PORT)..."
if ! run_ssh "echo SSH_OK_\$(hostname)"; then
  echo "[!] SSH не проходит. Проверь:"
  echo "    - виртуалка запущена;"
  echo "    - проброс порта NAT: имя=ssh TCP порт хоста=2222 порт гостя=22 (IP-поля пустые);"
  echo "    - VM_USER/VM_PASS указаны верно."
  exit 1
fi

echo "==> 2. Копирую проект в виртуалку (/home/$VM_USER/dz)..."
"$PY" "$SSH_AUTO" putdir "$VM_HOST" "$VM_SSH_PORT" "$VM_USER" "$VM_PASS" "$PROJECT_DIR" "/home/$VM_USER/dz" | tail -1

echo "==> 3. Внутри Ubuntu: установка Docker + запуск проекта (пароль sudo вводится сам)..."
REMOTE_SCRIPT=$(cat << 'EOS'
set -e
echo "--- версия ubuntu:"; head -2 /etc/os-release
if ! command -v docker >/dev/null 2>&1; then
  echo "--- ставлю docker (пароль sudo подставляется автоматически)"
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  echo "__VM_PASS__" | sudo -S sh /tmp/get-docker.sh
else
  echo "--- docker уже установлен: $(docker --version)"
fi
echo "__VM_PASS__" | sudo -S usermod -aG docker $USER
sg docker -c '
cd ~/dz
docker compose up -d --build
docker compose ps
sleep 5
echo "--- проверка API изнутри виртуалки:"
curl -s http://localhost:8000/api/hello/ || true
echo
echo "--- проверка фронтенда:"
curl -s -o /dev/null -w "фронтенд HTTP %{http_code}\n" http://localhost:80/ || \
curl -s -o /dev/null -w "фронтенд HTTP %{http_code}\n" http://localhost:8080/ || true
'
EOS
)
TMP=$(mktemp)
printf '%s\n' "${REMOTE_SCRIPT//__VM_PASS__/$VM_PASS}" > "$TMP"
run_ssh "bash -s" < "$TMP"
rm -f "$TMP"

echo ""
echo "=== ГОТОВО ==="
echo "Открой в браузере на РЕД ОС:"
echo "  фронтенд:  http://127.0.0.1:8080            (проброс NAT 8080 -> 80)"
echo "  API:       http://127.0.0.1:8000/api/hello/ (проброс NAT 8000 -> 8000)"
