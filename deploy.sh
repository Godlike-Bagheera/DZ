#!/usr/bin/env bash
# deploy.sh — полностью бесплатное развертывание проекта (без VPS).
#
# Вариант 1 (рекомендуется для задания): запуск всего стека локально в Docker Desktop.
#   ./deploy.sh local
#
# Вариант 2: сборка образов и пуш на бесплатный Docker Hub (Godlike-Bagheera).
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
    read -p "Логин Docker Hub [testbagheera666@gmail.com]: " DH_USER
    DH_USER=${DH_USER:-testbagheera666@gmail.com}
    echo "Введи пароль от Docker Hub (символы не отображаются):"
    read -s DH_PASS
    echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
    docker build -t Godlike-Bagheera/backend-image ./backend
    docker build -t Godlike-Bagheera/frontend-image ./frontend
    docker push Godlike-Bagheera/backend-image
    docker push Godlike-Bagheera/frontend-image
    echo "Готово: образы залиты на Docker Hub."
    ;;
  *)
    echo "Использование: $0 [local|push]"; exit 1
    ;;
esac
