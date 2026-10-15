# Fullstack: Django + React + Docker (задание «Задание до субботы.docx»)

Всё делается **бесплатно** на твоём компьютере: Docker Desktop + GitHub + Docker Hub. VPS не нужен.

## Структура
- `backend/` — Django (проект `mysite`), эндпоинт `GET /api/hello/` → `{"message": "Привет с Django!"}`, CORS включён, запуск через gunicorn (порт 8000).
- `frontend/` — React (Vite) + axios. Ходит на относительный `/api/hello/` — **вставлять IP никуда не нужно**. Многоступенчатый Dockerfile: сборка на node:18-alpine, раздача через nginx:alpine (порт 80, nginx проксирует `/api/` на бэкенд).
- `docker-compose.yml` — собирает и запускает оба контейнера одной командой.
- `deploy.sh` — скрипт-помощник (`./deploy.sh local` или `./deploy.sh push`).
- `ИНСТРУКЦИЯ_бесплатно.md` — подробная пошаговая инструкция.

## Быстрый старт (3 команды)
```bash
git clone https://github.com/Godlike-Bagheera/DZ.git
cd DZ
docker compose up -d --build
```
Открой http://localhost — страница «React фронтенд» с надписью «Привет с Django!».
API напрямую: http://localhost:8000/api/hello/. Остановить: `docker compose down`.

## Залить образы на Docker Hub (бесплатно)
```bash
docker login -u godlike-bagheera   # пароль/access token с hub.docker.com
docker compose build
docker compose push
```
Образы: `godlike-bagheera/backend-image` и `godlike-bagheera/frontend-image`.

## Публичная ссылка без сервера (если требует преподаватель)
```bash
npx localtunnel --port 80   # даст бесплатный адрес вида https://имя.loca.lt
```

## Локальный запуск без Docker
Бэкенд: `cd backend && pip install -r requirements.txt && python manage.py runserver 0.0.0.0:8000`
Фронтенд: `cd frontend && npm install && npm run dev` (http://localhost:5173)
