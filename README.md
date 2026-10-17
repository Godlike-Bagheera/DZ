# Fullstack: Django + React + Docker (задание «Задание до субботы.docx»)

Всё делается **бесплатно** на твоём компьютере: Docker Desktop + GitHub + Docker Hub. VPS не нужен.

## Структура
- `backend/` — Django (проект `mysite`), эндпоинт `GET /api/hello/` → `{"message": "Привет с Django!"}`, CORS включён, запуск через gunicorn (порт 8000).
- `frontend/` — React (Vite) + axios. Ходит на относительный `/api/hello/` — **вставлять IP никуда не нужно**. Многоступенчатый Dockerfile: сборка на node:18-alpine, раздача через nginx:alpine (порт 80, nginx проксирует `/api/` на бэкенд).
- `docker-compose.yml` — собирает и запускает оба контейнера одной командой.
- `deploy.sh` — скрипт-помощник (`./deploy.sh local` или `./deploy.sh push`).
- `ИНСТРУКЦИЯ_бесплатно.md` — подробная пошаговая инструкция.

## Быстрый старт (если скачал проект с GitHub)
Открой в папке проекта терминал (в Windows: PowerShell или Git Bash) и выполни одну команду:
```bash
./start.sh        # Windows PowerShell: .\start.sh
```
Скрипт сам проверит Docker, соберёт образы, запустит контейнеры и покажет результаты проверки.
Остановка: `./start.sh stop`.

Можно и вручную 3 командами:
```bash
cd DZ
docker compose up -d --build
```
Открой http://localhost — страница «React фронтенд» с надписью «Привет с Django!».
API напрямую: http://localhost:8000/api/hello/. Остановить: `docker compose down`.

## Залить образы на Docker Hub (бесплатно)
```bash
docker login -u di0724599   # пароль/access token с hub.docker.com
docker compose build
docker compose push
```
Образы: `di0724599/backend-image` и `di0724599/frontend-image`.

## Публичная ссылка без сервера (если требует преподаватель)
```bash
npx localtunnel --port 80   # даст бесплатный адрес вида https://имя.loca.lt
```

## Локальный запуск без Docker
Бэкенд: `cd backend && pip install -r requirements.txt && python manage.py runserver 0.0.0.0:8000`
Фронтенд: `cd frontend && npm install && npm run dev` (http://localhost:5173)
