# Гайд: Ubuntu Server в VirtualBox + Docker + проброс портов

Этот гайд — про запуск проекта на **виртуальной машине** (бесплатная замена VPS из задания).
Всё то же самое, что с реальным сервером, но у тебя на компьютере.

## Что происходит (общая схема)
1. Создаём виртуалку с Ubuntu Server в VirtualBox.
2. Настраиваем сеть и **пробрасываем порты** (чтобы с основного компьютера видеть сайт с виртуалки).
3. По SSH заходим на виртуалку и ставим Docker.
4. Через `scp` перекидываем файлы проекта (`docker-compose.yml` и т.д.) на сервер.
5. Запускаем `docker compose up -d` — сайт работает «на сервере».

## Быстрый путь: один скрипт
```bash
vagrant up        # создаёт ВМ, сам ставит Docker, сам разворачивает проект
```
(нужен установленный Vagrant: https://developer.hashicorp.com/vagrant/downloads)

## Ручной путь: по шагам
### Шаг 1. Скачать Ubuntu Server
https://ubuntu.com/download/server → Ubuntu Server 22.04 LTS (≈1.5 ГБ).

### Шаг 2. Создать ВМ в VirtualBox
- New → имя `ubuntu-server`, тип Linux, версия Ubuntu (64-bit)
- RAM: 2048 МБ, диск: 20 ГБ
- Settings → Storage → выбрать скачанный ISO
- Settings → Network → Adapter 1 → **Bridged Adapter** (или Host-only, см. ниже)
- Start → установить Ubuntu (user: `student`, пароль придумай, поставь галочку Install OpenSSH server)

### Шаг 3. Узнать IP виртуалки
На виртуалке (в консоли VirtualBox):
```bash
ip a | grep inet
```
IP вида `192.168.x.x` (Bridged) или `192.168.56.x` (Host-only).

### Шаг 4. Проброс портов (если Host-only/NAT)
На хосте в терминале (VirtualBox запущен, ВМ можно выключить):
```bash
VBoxManage modifyvm "ubuntu-server" --natpf1 "ssh,tcp,,2222,,22"
VBoxManage modifyvm "ubuntu-server" --natpf1 "web,tcp,,8080,,80"
VBoxManage modifyvm "ubuntu-server" --natpf1 "api,tcp,,8000,,8000"
```
Теперь: SSH = порт 2222, сайт = 8080, API = 8000 на твоём компьютере.

### Шаг 5. Проверить SSH
```bash
ssh student@IP_ВИРТУАЛКИ          # Bridged
ssh -p 2222 student@127.0.0.1     # NAT с пробросом
```

### Шаг 6. Установить Docker на виртуалке
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker --version
```

### Шаг 7. Перекинуть проект через scp
С хоста, из папки проекта:
```bash
scp -r backend frontend docker-compose.yml student@IP:/home/student/myapp/
# или при NAT: scp -P 2222 -r ... student@127.0.0.1:/home/student/myapp/
```

### Шаг 8. Запустить всё
```bash
ssh student@IP
cd myapp
docker compose up -d --build
docker compose ps
```

### Шаг 9. Проверка с хоста
- Фронтенд: http://localhost:8080 (или http://IP_ВИРТУАЛКИ)
- API: http://localhost:8000/api/hellO/ → JSON

📸 Скриншоты для отчёта: установка Ubuntu, `docker compose ps`, открытый сайт.

## Частые проблемы
| Проблема | Решение |
|---|---|
| SSH не-connect | Проверь, что OpenSSH server установлен; `sudo systemctl status ssh` |
| Порт занят | Поменяй внешнюю сторону проброса: `,,8081,,80` |
| docker: permission denied | `sudo usermod -aG docker $USER` и перезайти |
| Брандмауэр | `sudo ufw allow 80,8000/tcp` |
