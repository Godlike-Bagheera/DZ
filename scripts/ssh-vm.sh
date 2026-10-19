#!/usr/bin/env bash
# Простое интерактивное подключение к виртуалке через проброшенный порт.
# Использование: ./scripts/ssh-vm.sh            (логин stud, порт 2222)
#                VM_USER=user ./scripts/ssh-vm.sh
set -u
USER="${VM_USER:-stud}"
PORT="${VM_PORT:-2222}"
echo "Подключение к $USER@127.0.0.1:$PORT"
echo "Пароль — тот, что ты задавал при установке Ubuntu."
echo "Если просит 'Are you sure you want to connect' — напиши yes и Enter."
exec ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER@127.0.0.1"
