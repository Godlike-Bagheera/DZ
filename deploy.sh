#!/usr/bin/env bash
# deploy.sh — полностью бесплатное развертывание проекта (без VPS).
#
# Вариант 1 (рекомендуется для задания): запуск всего стека локально в Docker Desktop.
#   ./deploy.sh local
#
# Вариант 2: сборка образов и пуш на бесплатный Docker Hub (k1ttt3n).
#   ./deploy.sh push
#
# Требуется установленный Docker Desktop: https://www.docker.com/products/docker-desktop/
set -e

MODE="${1:-local}"

case "$MODE" in
  local)
    echo "==> Локальный запуск через docker compose (бесплатно)"
    docker compose up -d --build
    echo ""
    echo "Открой в браузере: http://localhost"
    echo "API напрямую:      http://localhost:8000/api/hello/"
    ;;
  push)
    echo "==> Сборка и пуш образов на Docker Hub (бесплатный аккаунт)"
    if ! docker info >/dev/null 2>&1; then
      echo "Docker не запущен. Открой Docker Desktop и повтори."; exit 1
    fi
    read -p "Логин Docker Hub [твоя_почта@gmail.com]: " DH_USER
    DH_USER=${DH_USER:-твоя_почта@gmail.com}
    echo "Введи пароль от Docker Hub (символы не отображаются):"
    read -s DH_PASS
    echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
    docker build -t k1ttt3n/backend-image ./backend
    docker build -t k1ttt3n/frontend-image ./frontend
    docker push k1ttt3n/backend-image
    docker push k1ttt3n/frontend-image
    echo "Готово: образы залиты на Docker Hub."
    ;;
  *)
    echo "Использование: $0 [local|push]"; exit 1
    ;;
esac
