# Fullstack: Django + React + Docker (заданию «Задание до субботы.docx»)

## Структура
- `backend/` — Django (проект `mysite`), эндпоинт `GET /api/hello/` → `{"message": "Привет с Django!"}`, CORS включён (`corsheaders`), сервер в контейнере запускается через gunicorn (порт 8000).
- `frontend/` — React (Vite, вместо CRA — современный аналог из задания), через axios ходит на `http://IP_СЕРВЕРА:8000/api/hello/`. Многоступенчатый Dockerfile: сборка на node:18-alpine, раздача через nginx:alpine (порт 80).
- `docker-compose.yml` — готов к запуску на VPS (образы с Docker Hub).

## Локальный запуск без Docker
Бэкенд:
```bash
cd backend
pip install -r requirements.txt
python manage.py runserver 0.0.0.0:8000   # http://localhost:8000/api/hello/
```
Фронтенд:
```bash
cd frontend
npm install
npm run dev        # http://localhost:5173
```

## Сборка и пуш образов (ШАГ 2)
```bash
docker login
docker build -t Godlike-Bagheera/backend-image ./backend
docker build -t Godlike-Bagheera/frontend-image ./frontend
docker push Godlike-Bagheera/backend-image
docker push Godlike-Bagheera/frontend-image
```

## Запуск на VPS (ШАГИ 6–7)
```bash
ssh root@ТВОЙ_IP
mkdir -p /root/myapp && cd /root/myapp
nano docker-compose.yml   # вставить содержимое docker-compose.yml из корня репозитория
docker compose up -d
docker compose ps
```

## ШАГ 9 — подстановка реального IP
1. В файле `frontend/src/App.jsx` замени `IP_СЕРВЕРА` на реальный IP VPS.
2. Пересобери и перезалей образ:
```bash
docker build -t Godlike-Bagheera/frontend-image ./frontend
docker push Godlike-Bagheera/frontend-image
```
3. На сервере:
```bash
cd /root/myapp && docker compose pull && docker compose up -d
```

## ШАГ 8 — фаервол
В панели reg.cloud открой входящие правила: TCP 80 (фронт) и TCP 8000 (бэк).

## Проверка (ШАГ 10)
Открой `http://ТВОЙ_IP` — должна появиться надпись «Привет с Django!».
