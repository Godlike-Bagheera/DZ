#!/usr/bin/env bash
# =============================================================================
# auto-setup.sh — ОДИН скрипт на всё: РЕД ОС -> VirtualBox Ubuntu Server
#   1) выключает ВМ, настраивает NAT-проброс портов (2222->22, 8080->80, 8000->8000)
#   2) запускает ВМ в headless и ждёт подъёма SSH (до 4 минут)
#   3) ставит paramiko без sudo (pip --user), логинится по паролю сам
#   4) копает проект в виртуалку, ставит там Docker, запускает docker compose
#   5) проверяет фронтенд и API
#
# ЗАПУСК из папки проекта DZ на РЕД ОС:
#   VM_PASS=пароль_ubuntu bash scripts/auto-setup.sh
# Опционально: VM_NAME=UbuntuServ VM_USER=stud VM_IP=127.0.0.1 VM_SSH_PORT=2222
# =============================================================================
set -uo pipefail

VM_NAME="${VM_NAME:-UbuntuServ}"
VM_USER="${VM_USER:-stud}"
VM_PASS="${VM_PASS:-}"
VM_HOST="${VM_HOST:-127.0.0.1}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"

if [ -z "$VM_PASS" ]; then
  echo "[!] Не задан пароль виртуалки. Запусти так:"
  echo "    VM_PASS=твой_пароль bash scripts/auto-setup.sh"
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY="$(command -v python3 || command -v python)"
[ -z "$PY" ] && { echo "[!] На хосте нет python3."; exit 1; }

VBM=/usr/lib/virtualbox/VBoxManage
[ -x "$VBM" ] || VBM="$(command -v VBoxManage || true)"
[ -n "$VBM" ] || { echo "[!] VBoxManage не найден —VirtualBox не установлен?"; exit 1; }

echo "==> 1. Проброс портов NAT ($VM_NAME): ssh 2222->22, frontend 8080->80, backend 8000->8000"
STATE="$("$VBM" showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep '^VMState=' | cut -d'"' -f2)"
case "$STATE" in
  running|paused|saved|"")
    echo "    Состояние ВМ: ${STATE:-неизвестно}. Выключаю (poweroff)..."
    "$VBM" controlvm "$VM_NAME" poweroff >/dev/null 2>&1 || true
    sleep 3 ;;
esac
bash "$PROJECT_DIR/scripts/vm-ports.sh" "$VM_NAME" || { echo "[!] Не удалось настроить порты."; exit 1; }

echo "==> 2. Запускаю ВМ и жду реальный SSH-баннер на $VM_HOST:$VM_SSH_PORT (до 5 мин)..."
echo "    (окно VirtualBox с консолью ВМ — для наглядности; закрыть можно после)"
"$VBM" startvm "$VM_NAME" >/dev/null 2>&1 || "$VBM" startvm "$VM_NAME" --type headless >/dev/null
OK=0
for i in $(seq 1 60); do
  # порт мало открыть — дождёмся настоящего баннера sshd
  if "$PY" "$PROJECT_DIR/scripts/ssh_auto.py" run "$VM_HOST" "$VM_SSH_PORT" "$VM_USER" "$VM_PASS" "echo SSH_READY" 2>/dev/null | grep -q SSH_READY; then
    OK=1; break
  fi
  sleep 5
done
if [ "$OK" != 1 ]; then
  echo ""
  echo "[!] SSH за 5 минут не поднялся (порт может открываться, но sshd внутри Ubuntu отсутствует)."
  echo "    РЕШЕНИЕ: в окне VirtualBox (уже открыто) войди в систему"
  echo "    (логин $VM_USER, пароль — тот, что задавал при установке Ubuntu) и выполни ДВЕ команды:"
  echo "      sudo apt update && sudo apt install -y openssh-server"
  echo "      sudo systemctl enable --now ssh"
  echo "    Если sudo спросит пароль — введи его (он же VM_PASS)."
  echo "    После этого повтори: VM_PASS=... bash scripts/auto-setup.sh"
  exit 1
fi
echo "    SSH работает, вход выполнен."

echo "==> 3. Ставлю paramiko в ~/.local (без sudo)..."
if ! "$PY" -c "import paramiko" 2>/dev/null; then
  "$PY" -m pip install --user paramiko >/dev/null 2>&1 || \
  "$PY" -m pip install --user --break-system-packages paramiko >/dev/null 2>&1
fi
"$PY" -c "import paramiko" 2>/dev/null || { echo "[!] paramiko не поставился. Пришли вывод: $PY -m pip install --user paramiko"; exit 1; }
echo "    ОК"

echo "==> 4. Подключение по SSH к виртуалке..."
if ! "$PY" "$PROJECT_DIR/scripts/ssh_auto.py" run "$VM_HOST" "$VM_SSH_PORT" "$VM_USER" "$VM_PASS" "echo SSH_OK_\$(hostname)"; then
  echo "[!] Логин по SSH не прошёл. Проверь VM_USER/VM_PASS (виртуалка создана с пользователем $VM_USER?)."
  exit 1
fi

echo "==> 5. Копирую проект в /home/$VM_USER/dz ..."
"$PY" "$PROJECT_DIR/scripts/ssh_auto.py" putdir "$VM_HOST" "$VM_SSH_PORT" "$VM_USER" "$VM_PASS" "$PROJECT_DIR" "/home/$VM_USER/dz" | tail -1

echo "==> 6. Внутри Ubuntu: установка Docker + запуск проекта (sudo-пароль подставляется сам)..."
REMOTE_SCRIPT=$(cat << 'EOS'
set -e
echo "--- версия ubuntu:"; head -2 /etc/os-release
if ! command -v docker >/dev/null 2>&1; then
  echo "--- ставлю docker (пароль sudo подставлен автоматически)"
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
curl -s -o /dev/null -w "фронтенд HTTP %{http_code}\n" http://localhost:80/ || true
'
EOS
)
TMP=$(mktemp)
printf '%s\n' "${REMOTE_SCRIPT//__VM_PASS__/$VM_PASS}" > "$TMP"
"$PY" "$PROJECT_DIR/scripts/ssh_auto.py" run "$VM_HOST" "$VM_SSH_PORT" "$VM_USER" "$VM_PASS" "bash -s" < "$TMP"
RC=$?
rm -f "$TMP"
[ $RC != 0 ] && { echo "[!] Этап установки/запуска завершился с ошибкой (код $RC). Пришли вывод выше."; exit $RC; }

echo ""
echo "=== ГОТОВО ==="
echo "Открой в браузере на РЕД ОС:"
echo "  фронтенд:  http://127.0.0.1:8080            (NAT 8080 -> 80)"
echo "  API:       http://127.0.0.1:8000/api/hello/ (NAT 8000 -> 8000)"
