# ГАЙД: запуск проекта на Windows через VirtualBox (полный автомат)

Всё делает один скрипт. Ты только скачиваешь 3 программы и запускаешь 2 команды.
Логины и пароли ниже уже придуманы за тебя — просто используй их как есть.

## Данные, которые используются (запомни или скопируй)
| Что | Значение |
|---|---|
| Логин в виртуалке (Ubuntu) | `stud` |
| Пароль от виртуалки | `DzPass2026!` |
| Имя виртуальной машины | `UbuntuServ` |
| Сайт (фронтенд) | http://127.0.0.1:8080 |
| API (backend) | http://127.0.0.1:8000/api/hello/ |
| SSH в виртуалку | `ssh stud@127.0.0.1 -p 2222` (пароль `DzPass2026!`) |

---

## ШАГ 1. Установить три программы

1. **VirtualBox** → https://www.virtualbox.org/wiki/Downloads → «Windows host» → установить, везде «Next», в конце разрешить перезагрузку сети (перезагрузка не обязательна сразу).
2. **Git** → https://git-scm.com/download/win → установить, везде «Next».
3. **Python** → https://python.org/downloads → при установке ОБЯЗАТЕЛЬНО поставить галочку **«Add python.exe to PATH»**.

## ШАГ 2. Скачать ISO Ubuntu Server

→ https://ubuntu.com/download/server → кнопка Download → файл вида `ubuntu-24.04-live-server-amd64.iso` (~3 ГБ).
Дождись окончания загрузки. Запомни путь (обычно `C:\Users\ТВОЁ_ИМЯ\Downloads`).

> Это единственный раз, когда что-то скачивается вручную. Саму Ubuntu ставить НЕ надо — скрипт установит её внутри виртуалки автоматически, включая OpenSSH.

## ШАГ 3. Скачать проект

Нажми `Пуск` → напиши `PowerShell` → открой **Windows PowerShell** (обычный, не админ). Вставь и выполни:

```powershell
cd $env:USERPROFILE\Desktop
git clone https://github.com/Godlike-Bagheera/DZ.git
cd DZ
```

## ШАГ 4. Запустить автомат

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\auto-setup.ps1 -IsoPath "$env:USERPROFILE\Downloads\ubuntu-24.04-live-server-amd64.iso" -VmPass "DzPass2026!"
```

Если у тебя ISO называется чуть иначе — посмотрите точное имя файла в папке Downloads и подставь его в `-IsoPath`.

**Что произойдёт дальше (само, ~15–25 минут):**
1. Скрипт создаст виртуальную машину `UbuntuServ` (2 ГБ RAM, 25 ГБ диск).
2. Подключит к ней ISO + диск с файлом автоустановки (cloud-init) и запустит окно VirtualBox.
3. Ubuntu установится БЕЗ вопросов (виртуалка сама всё сделает; можно пойти выпить чаю). После установки она сама выключится — это нормально.
4. Скрипт пробросит порты NAT: `2222→22` (SSH), `8080→80` (сайт), `8000→8000` (API).
5. Снова запустит ВМ, дождётся SSH, зайдёт внутрь как `stud / DzPass2026!`.
6. Установит Docker внутри Ubuntu, зальёт туда проект, выполнит `docker compose up -d --build`.
7. Проверит фронтенд и API и напишет «ГОТОВО».

## ШАГ 5. Проверка и скриншоты для отчёта

Открой браузер:
- **http://127.0.0.1:8080** — должен открыться сайт (кнопка, по нажатию приходит сообщение от Django);
- **http://127.0.0.1:8000/api/hello/** — должен быть JSON вида `{"message": "..."}`.

Скриншоты, которые надо сдать:
1. Окно PowerShell, где видно успешное завершение `auto-setup.ps1`;
2. Открытый сайт http://127.0.0.1:8080;
3. Открытый JSON http://127.0.0.1:8000/api/hello/;
4. Из окна виртуалки (или по SSH): вывод `docker ps` — видны два контейнера backend и frontend;
5. Ссылка на репозиторий https://github.com/Godlike-Bagheera/DZ.

Как подключиться по SSH для п.4 (из PowerShell):
```powershell
ssh stud@127.0.0.1 -p 2222
# пароль: DzPass2026!
docker ps
```

---

## Если что-то пошло не так

| Симптом | Решение |
|---|---|
| `IsoPath не найден` | Проверь точное имя файла в Downloads, скопируй путь целиком |
| `VirtualBox не найден` | Установи VirtualBox из Шага 1 и перезапусти PowerShell |
| `Не удалось выполнить скрипт... выполнение отключено` | Ещё раз выполни `Set-ExecutionPolicy -Scope Process Bypass -Force` в ЭТОМ окне PowerShell |
| Долго висит «жду SSH» (>5 мин) | Открой окно VirtualBox: если там чёрный экран/ошибка установки — выключи ВМ и повтори Шаг 4 |
| Порт занят / старая ВМ мешает | `& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" unregistervm "UbuntuServ" --delete` и повтори Шаг 4 |
| Сайт не открывается | Внутри ВМ (по SSH): `cd ~/dz && sudo docker compose restart`, потом подожди 30 сек |
| Python не найден скриптом | Перезапусти PowerShell после установки Python (галочка Add to PATH обязательна) |

## Полезные команды после всего

```powershell
# остановить проект
ssh stud@127.0.0.1 -p 2222            # пароль DzPass2026!
cd ~/dz && sudo docker compose stop

# запустить обратно
cd ~/dz && sudo docker compose up -d

# посмотреть логи backend
sudo docker compose logs backend

# выключить виртуалку
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm "UbuntuServ" poweroff
```
