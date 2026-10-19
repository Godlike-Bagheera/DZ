#!/usr/bin/env bash
# ============================================================================
# ЗАПУСК ПРОЕКТА БЕЗ ДОКЕРА (для РЕД ОС / машин без sudo).
# Ставит Python и Node в домашнюю папку (~/.local), ставит Django,
# собирает фронтенд и поднимает оба сервиса. Ничего системного не трогает.
#
#   bash scripts/run-local.sh
#
# После запуска:
#   фронтенд: http://localhost:8080
#   API:      http://localhost:8000/api/hello/
# Остановка: Ctrl+C
# ============================================================================
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
mkdir -p ~/.local/bin

say() { echo -e "\n==> $1"; }

# ---------- 1. Python ----------
say "1. Проверяю Python..."
if command -v python3 >/dev/null 2>&1; then
    PY=python3
else
    echo "Python3 не найден. Попроси админа или используй conda."; exit 1
fi
$PY --version

# venv без pip? качаем get-pip
if ! $PY -m ensurepip --version >/dev/null 2>&1 && ! $PY -m pip --version >/dev/null 2>&1; then
    say "Ставлю pip через get-pip.py (в домашнюю папку, без sudo)..."
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py || \
    wget -qO /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
    $PY /tmp/get-pip.py --user
fi

# ---------- 2. Backend ----------
say "2. Создаю виртуальное окружение и ставлю Django..."
if [ ! -d ~/.venv-dz ]; then
    $PY -m venv ~/.venv-dz || { echo "venv недоступен — ставлю пакеты через --user"; VENV=0; }
fi
if [ -d ~/.venv-dz ]; then
    source ~/.venv-dz/bin/activate
    pip install -q --upgrade pip
    pip install -q -r backend/requirements.txt
else
    $PY -m pip install --user -q -r backend/requirements.txt
fi
echo "    Готово: $($PY -c 'import django; print("Django", django.get_version())')"

# ---------- 3. Node.js ----------
say "3. Проверяю Node.js..."
if command -v node >/dev/null 2>&1; then
    NODE_OK=1
else
    echo "    Node нет — качаю официальную сборку в ~/.local ..."
    VER=v20.18.1
    if command -v curl >/dev/null 2>&1; then DL="curl -fsSL"; else DL="wget -qO-"; fi
    $DL "https://nodejs.org/dist/$VER/node-$VER-linux-x64.tar.xz" -o /tmp/node.tar.xz || \
    $DL "https://nodejs.org/dist/$VER/node-$VER-linux-x64.tar.xz" > /tmp/node.tar.xz
    mkdir -p ~/.local/node
    tar xf /tmp/node.tar.xz -C ~/.local/node --strip-components=1
    export PATH=~/.local/node/bin:$PATH
    grep -q '.local/node/bin' ~/.bashrc || echo 'export PATH=$HOME/.local/node/bin:$PATH' >> ~/.bashrc
    NODE_OK=1
fi
node --version && npm --version

# ---------- 4. Frontend ----------
say "4. Собираю фронтенд (React + Vite)..."
cd frontend
npm install --no-audit --no-fund
npm run build
cd "$ROOT"
echo "    Сборка готова: frontend/dist"

# ---------- 5. Запуск ----------
say "5. Запускаю backend (порт 8000) и frontend (порт 8080)..."
(cd backend && $PY manage.py runserver 0.0.0.0:8000 >/tmp/dz-backend.log 2>&1 &)
(cd frontend/dist && nohup $PY -m http.server 8080 >/tmp/dz-frontend.log 2>&1 &)
sleep 4

echo
echo "=== Проверка ==="
echo "--- API http://localhost:8000/api/hello/ :"
curl -s http://localhost:8000/api/hello/ || cat /tmp/dz-backend.log | tail -5
echo
echo "--- Фронтенд http://localhost:8080 :"
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8080/

cat <<'EOF'

============================================================
 ВСЁ ЗАВЕДЕНО (без Docker и без sudo):
   Фронтенд:  http://localhost:8080   (или открой frontend/dist/index.html)
   API:       http://localhost:8000/api/hello/
 Логи:        /tmp/dz-backend.log, /tmp/dz-frontend.log
 Остановить:  pkill -f "manage.py runserver"; pkill -f "http.server 8080"
 Скриншоты для отчёта: терминал с этим выводом + обе страницы в браузере.
============================================================
EOF
