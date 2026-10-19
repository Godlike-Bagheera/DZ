#!/usr/bin/env bash
# =============================================================================
# vm-setup.sh — полная автоматизация: РЕД ОС (хост) -> VirtualBox Ubuntu (гость)
#
# Что делает сам, без ручного ввода:
#   1. Проверяет SSH-доступ к виртуалке (через проброшенный порт 2222)
#   2. Устанавливает Docker внутри Ubuntu (пароль sudo вводится автоматически)
#   3. Добавляет пользователя в группу docker (чтобы docker работал без sudo)
#   4. Копирует проект в виртуалку по scp
#   5. Собирает и запускает контейнеры (docker compose up -d --build)
#   6. Проверяет, что фронтенд и API отвечают
#
# ЗАПУСК: с хоста (РЕД ОС), из папки проекта DZ:
#   VM_PASS=ваш_пароль_от_виртуалки bash scripts/vm-setup.sh
#
# Параметры через переменные (все имеют значения по умолчанию):
#   VM_HOST   (127.0.0.1)      адрес виртуалки с точки зрения хоста
#   VM_SSH_PORT (2222)         порт SSH (проброс NAT: 2222 -> 22)
#   VM_USER   (stud)           логин внутри Ubuntu
#   VM_PASS   (обязательно!)   пароль этого пользователя (он же для sudo)
#   FRONTEND_PORT_ON_GUEST(80) порт фронтенда ВНУТРИ виртуалки
#                              (если не делал проброс 8080->80, скрипт сам
#                               добавит его через VBoxManage, если он доступен)
# =============================================================================
set -euo pipefail

VM_HOST="${VM_HOST:-127.0.0.1}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
VM_USER="${VM_USER:-stud}"
VM_PASS="${VM_PASS:-}"
FRONTEND_PORT_ON_GUEST="${FRONTEND_PORT_ON_GUEST:-80}"

if [ -z "$VM_PASS" ]; then
  echo "[!] Не задан пароль виртуалки. Запусти так:"
  echo "    VM_PASS=пароль bash scripts/vm-setup.sh"
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p $VM_SSH_PORT"

# --- helper: ssh с авто-вводом пароля (sshpass или expect как запасной) ------
have() { command -v "$1" >/dev/null 2>&1; }

run_ssh() {
  if have sshpass; then
    sshpass -p "$VM_PASS" ssh $SSH_OPTS "$VM_USER@$VM_HOST" "$@"
  elif have expect; then
    expect -c "
      set timeout 300
      spawn ssh $SSH_OPTS $VM_USER@$VM_HOST {$*}
      expect -re {(?i)password:} { send \"$VM_PASS\r\" }
      expect eof
      catch wait result
      exit [lindex \$result 3]
    "
  else
    echo "[!] Нужен sshpass или expect. Установи любой (без sudo тоже можно):"
    echo "    sudo apt install sshpass        # если есть sudo"
    echo "    # ИЛИ скачай статический sshpass:"
    echo "    curl -L -o ~/.local/bin/sshpass https://github.com/kxdeng/sshpass-static-build/releases/download/v1.09/sshpass-v1.09-linux-static-x86_64.tar.gz"
    echo "    (распакуй бинарник в ~/.local/bin и chmod +x)"
    exit 1
  fi
}

copy_scp() {
  local src="$1" dst="$2"
  if have sshpass; then
    sshpass -p "$VM_PASS" scp $SSH_OPTS -r "$src" "$VM_USER@$VM_HOST:$dst"
  elif have expect; then
    # scp через expect не всегда удобен — используем tar поверх ssh
    tar -C "$(dirname "$src")" -cf - "$(basename "$src")" | \
    expect -c "
      set timeout 600
      spawn ssh $SSH_OPTS $VM_USER@$VM_HOST {mkdir -p ~ && cat > /tmp/proj.tar && tar -xf /tmp/proj.tar -C ~ && rm /tmp/proj.tar}
      expect -re {(?i)password:} { send \"$VM_PASS\r\" }
      expect eof
    "
  fi
}

echo "==> 1. Проверка SSH-доступа к виртуалке ($VM_USER@$VM_HOST:$VM_SSH_PORT)..."
run_ssh "echo OK && lsb_release -ds 2>/dev/null || cat /etc/os-release | head -1"
echo "    SSH работает ✅"

echo "==> 2. Установка Docker внутри Ubuntu (sudo-пароль вводится автоматически)..."
run_ssh "echo '$VM_PASS' | sudo -S true"   # прогреваем sudo-кэш / проверяем пароль
run_ssh "command -v docker >/dev/null 2>&1 && echo 'Docker уже установлен' || {
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh &&
  echo '$VM_PASS' | sudo -S sh /tmp/get-docker.sh
}"

echo "==> 3. Добавляю $VM_USER в группу docker (docker без sudo)..."
run_ssh "echo '$VM_PASS' | sudo -S usermod -aG docker $VM_USER"

echo "==> 4. Копирую проект в виртуалку..."
tar -C "$PROJECT_DIR" --exclude='.git' -czf /tmp/dz-project.tar.gz .
if have sshpass; then
  sshpass -p "$VM_PASS" scp $SSH_OPTS /tmp/dz-project.tar.gz "$VM_USER@$VM_HOST:/tmp/"
else
  cat /tmp/dz-project.tar.gz | run_ssh "cat > /tmp/dz-project.tar.gz"
fi
rm -f /tmp/dz-project.tar.gz
run_ssh "rm -rf ~/dz && mkdir -p ~/dz && tar -xzf /tmp/dz-project.tar.gz -C ~/dz && rm /tmp/dz-project.tar.gz"
echo "    Проект скопирован в ~/dz ✅"

echo "==> 5. Сборка и запуск контейнеров (первый раз 5-10 минут)..."
run_ssh "cd ~/dz && sg docker -c 'docker compose up -d --build'"

echo "==> 6. Проброс портов на хосте (если VBoxManage доступен здесь)..."
if have VBoxManage; then
  VM_NAME="${VM_NAME:-$(VBoxManage list vms | sed -n 's/\"\(.*\)\" .*/\1/p' | head -1)}"
  for rule in "frontend:8080:80" "backend:8000:8000"; do
    name="${rule%%:*}"; rest="${rule#*:}"; hp="${rest%%:*}"; gp="${rest##*:}"
    if ! ss -tln 2>/dev/null | grep -q ":$hp "; then
      VBoxManage modifyvm "$VM_NAME" --natpf1 "$name,tcp,,$hp,,$gp" 2>/dev/null || true
      echo "    Добавлено правило $hp -> гость:$gp"
    fi
  done
else
  echo "    VBoxManage не найден на этом хосте — предполагаем, что порты уже проброшены вручную."
fi

echo "==> 7. Проверка результата..."
sleep 3
echo "--- Статус контейнеров:"
run_ssh "sg docker -c 'cd ~/dz && docker compose ps'"
echo "--- Ответ API изнутри виртуалки:"
run_ssh "curl -s http://localhost:8000/api/hello/ || true"
echo ""
echo "--- Ответ фронтенда изнутри виртуалки:"
run_ssh "curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:$FRONTEND_PORT_ON_GUEST/ || true"

echo ""
echo "=============================================================="
echo " ГОТОВО ✅  Открой в браузере на РЕД ОС:"
echo "   Фронтенд:  http://127.0.0.1:8080"
echo "   API:       http://127.0.0.1:8000/api/hello/"
echo ""
echo " Зайти внутрь виртуалки руками (если понадобится):"
echo "   ssh -p $VM_SSH_PORT $VM_USER@127.0.0.1   (пароль: тот же)"
echo " Логи контейнеров:"
echo "   ssh -p $VM_SSH_PORT $VM_USER@127.0.0.1 \"cd ~/dz && docker compose logs\""
echo " Остановить всё:"
echo "   ssh -p $VM_SSH_PORT $VM_USER@127.0.0.1 \"cd ~/dz && docker compose down\""
echo "=============================================================="
