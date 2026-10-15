#!/usr/bin/env bash
set -e

echo "🔧 1/4. Проверяю Docker..."
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker не запущен. Открой приложение Docker Desktop и подожди, пока ластичка перестанет крутиться (статус Engine running). Потом запусти скрипт снова."
  exit 1
fi
echo "✅ Docker работает: $(docker --version)"

echo ""
echo "🏗️ 2/4. Собираю образы backend и frontend..."
docker compose build

echo ""
echo "🚀 3/4. Запускаю контейнеры..."
docker compose up -d

echo ""
echo "⏳ Жду 5 секунд, пока приложения поднимутся..."
sleep 5

echo ""
echo "🩺 4/4. Проверки:"
echo "--- docker compose ps ---"
docker compose ps
echo ""
echo "--- Ответ API через nginx (http://localhost/api/hello/) ---"
curl -s http://localhost/api/hello/ || true
echo ""
echo "--- Ответ API напрямую (http://localhost:8000/api/hello/) ---"
curl -s http://localhost:8000/api/hello/ || true
echo ""
echo "--- HTML главной страницы (http://localhost) ---"
curl -s http://localhost | head -5

echo ""
echo "=============================================="
echo "✅ ВСЁ ЗАПУЩЕНО! Открой в браузере: http://localhost"
echo "   Там должна быть страница с надписью «Привет с Django!»"
echo ""
echo "Остановить:        ./start.sh stop"
echo "Посмотреть логи:   docker compose logs -f"
echo "=============================================="

if [ "$1" = "stop" ]; then
  docker compose down
  echo "⏹️  Контейнеры остановлены."
fi
