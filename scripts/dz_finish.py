#!/usr/bin/env python3
# Вспомогательный скрипт для finish-setup.ps1: настройка Ubuntu по SSH.
# Запуск: python dz_finish.py 127.0.0.1 2222 stud ПАРОЛЬ /path/to/project [logfile]
import sys, time, os, paramiko, pathlib, logging

host, port, user, pw, projdir = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
logfile = sys.argv[6] if len(sys.argv) > 6 else os.path.join(os.path.expanduser("~"), "dz-finish.log")

logging.basicConfig(
    level=logging.DEBUG if os.environ.get("DZ_DEBUG") else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(logfile, encoding="utf-8"),
              logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("dz")
log.info("=== dz_finish старт: host=%s port=%s user=%s ===", host, port, user)
log.info("Лог пишется в: %s", logfile)
if os.environ.get("DZ_DEBUG"):
    paramiko.util.log_to_file(logfile + ".paramiko")

cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
methods_tried = ["password"]
connected = False
for attempt in range(5):
    log.info("[ssh] попытка %d: подключаюсь к %s@%s:%d (методы: %s)",
             attempt + 1, user, host, port, ", ".join(methods_tried))
    try:
        cli.connect(host, port=port, username=user, password=pw, timeout=15,
                    banner_timeout=30, auth_timeout=30)
        connected = True
        log.info("[ssh] успешно подключился (попытка %d)", attempt + 1)
        break
    except paramiko.AuthenticationException as e:
        allowed = getattr(e, "allowed_types", None) or []
        log.error("[ssh] AUTH FAILED (попытка %d): %s | сервер разрешает методы: %s",
                  attempt + 1, e, allowed or "неизвестно")
        if attempt >= 2:
            log.error("[ssh] подсказка: 'Authentication failed' = НЕВЕРНЫЙ логин или пароль.")
            log.error("[ssh]   1) Проверь точное имя пользователя в Ubuntu (whoami в окне VirtualBox).")
            log.error("[ssh]   2) Пароль задавался при УСТАНОВКЕ Ubuntu — это не пароль Windows.")
            log.error("[ssh]   3) Если забыл пароль: в консоли ВМ выполни 'sudo passwd ИМЯ' и задай новый.")
            log.error("[ssh]   4) Попробуй вручную из PowerShell: ssh %s@127.0.0.1 -p %d", user, port)
    except Exception as e:
        log.error("[ssh] ошибка (попытка %d): %s: %s", attempt + 1, type(e).__name__, e)
    if attempt < 4:
        time.sleep(10)
if not connected:
    log.critical("[ssh] ВСЕ попытки исчерпаны. Прерываю работу. Полный лог: %s", logfile)
    sys.exit(2)


def run(cmd, timeout=900, label=None):
    log.info("$ %s", label or cmd[:120])
    _, out, err = cli.exec_command(cmd, timeout=timeout)
    o = out.read().decode(errors="replace")
    e = err.read().decode(errors="replace")
    rc = out.channel.recv_exit_status()
    if o.strip():
        log.debug("stdout: %s", o.strip()[:4000])
    if e.strip():
        log.debug("stderr: %s", e.strip()[:4000])
    tail = "\n".join((o + "\n" + e).strip().splitlines()[-12:])
    if tail:
        print(tail)
    if rc != 0:
        log.error("[exit %d] команда завершилась с ошибкой: %s", rc, cmd[:200])
    else:
        log.debug("[exit 0] OK")
    return rc, o, e


# 1. sudo с паролем (первый раз), затем NOPASSWD
def sudo_once(inner):
    # передаём пароль через stdin, безопаснее чем echo в командной строке
    import base64
    b64 = base64.b64encode(inner.encode()).decode()
    full = f"echo {b64} | base64 -d > /tmp/_dzcmd.sh && sudo -S -p '' bash /tmp/_dzcmd.sh"
    log.info("$ [sudo] %s", inner[:100])
    _, out, err = cli.exec_command(full, timeout=900)
    out.channel.sendall((pw + "\n").encode())
    o = out.read().decode(errors="replace")
    e = err.read().decode(errors="replace")
    rc = out.channel.recv_exit_status()
    t = "\n".join((o + "\n" + e).strip().splitlines()[-8:])
    if t:
        print(t)
    if rc != 0:
        log.error("[sudo exit %d] stderr: %s", rc, e.strip()[:1000])
        if "password" in e.lower() or "incorrect" in e.lower() or "try again" in e.lower():
            log.error("[sudo] похоже НЕВЕРНЫЙ ПАРОЛЬ для sudo. Проверь -VmPass.")
    else:
        log.debug("[sudo exit 0] OK")
    return rc, o, e


log.info("==> ШАГ 1/6: Базовые пакеты (apt-get update/install)...")
rc, _, _ = sudo_once("apt-get update -y && apt-get install -y curl ca-certificates sudo")
if rc != 0:
    log.error("[!] ШАГ 1 упал. Наиболее частые причины:")
    log.error("    - неверный пароль sudo (см. сообщения выше про 'НЕВЕРНЫЙ ПАРОЛЬ');")
    log.error("    - в ВМ нет интернета (проверь NAT-адаптер в VirtualBox);")
    log.error("    - пользователь '%s' вообще не существует в Ubuntu.", user)

log.info("==> ШАГ 2/6: Разрешаю NOPASSWD sudo для %s...", user)
sudo_line = f"{user} ALL=(ALL) NOPASSWD:ALL"
import base64 as _b64
_b64line = _b64.b64encode(sudo_line.encode()).decode()
# сначала проверим, что пользователь реально есть и пароль сработал
rc_id, o_id, _ = run("id && whoami", label="who am i (проверка пользователя)")
log.info("    id/whoami вывод: %s", o_id.strip())
rc, _, _ = sudo_once(
    "usermod -aG sudo {u}; echo {b} | base64 -d > /etc/sudoers.d/{u} && chmod 440 /etc/sudoers.d/{u}".format(u=user, b=_b64line)
)
if rc != 0:
    log.critical("[!] ШАГ 2 упал (exit %d): не удалось настроить sudo.", rc)
    log.critical("[!] Проверь: 1) логин (-VmUser) и пароль (-VmPass) от UBUNTU, не от Windows;")
    log.critical("[!]           2) входит ли этот юзер в группу sudo (в консоли ВМ: groups %s).", user)
    log.critical("[!] Полный лог: %s", logfile)
    sys.exit(1)
log.info("    OK: NOPASSWD sudo настроен")


def su(cmd, timeout=900, label=None):
    return run(f"sudo bash -c \"{cmd}\"", timeout=timeout, label=label or cmd[:100])


log.info("==> ШАГ 3/6: Docker...")
rc, _, _ = su("command -v docker")
if rc != 0:
    log.info("    docker не найден — устанавливаю (может занять ~2 мин)...")
    rc2, _, _ = su("curl -fsSL https://get.docker.com | sh", timeout=1500, label="установка docker")
    if rc2 != 0:
        log.error("[!] ШАГ 3: установка Docker упала (exit %d). Смотри stderr выше/в логе.", rc2)
else:
    log.info("    docker уже установлен")
su(f"usermod -aG docker {user}")
su("systemctl enable --now docker")
run("sleep 2; sudo docker info --format '{{.ServerVersion}}'", label="версия docker")

log.info("==> ШАГ 4/6: Копирую проект в ВМ (SFTP)...")
remote_dir = f"/home/{user}/dz"
run(f"rm -rf {remote_dir}; mkdir -p {remote_dir}", label="подготовка папки на ВМ")
sftp = cli.open_sftp()
nfiles = 0

def put_dir(local, remote):
    global nfiles
    try:
        sftp.stat(remote)
    except IOError:
        sftp.mkdir(remote)
    for p in pathlib.Path(local).iterdir():
        r = remote + "/" + p.name
        if p.is_dir():
            if p.name in (".git", "node_modules", "__pycache__", "dist"):
                continue
            put_dir(p, r)
        else:
            sftp.put(str(p), r)
            nfiles += 1
            if nfiles % 20 == 0:
                log.debug("    скопировано файлов: %d", nfiles)

try:
    put_dir(projdir, remote_dir)
except Exception as ex:
    log.critical("[!] ШАГ 4: ошибка копирования (%s: %s). Скопировано файлов до ошибки: %d",
                 type(ex).__name__, ex, nfiles)
    log.critical("[!] Полный лог: %s", logfile)
    sys.exit(4)
sftp.close()
log.info("    скопировано файлов: %d", nfiles)

log.info("==> ШАГ 5/6: Сборка и запуск контейнеров (5-15 мин)...")
rc, _, _ = run(f"cd {remote_dir} && sudo docker compose up -d --build 2>&1 | tail -25",
               timeout=2400, label="docker compose up -d --build")
if rc != 0:
    log.error("[!] ШАГ 5: compose up завершился с ошибкой exit %d.", rc)
    run(f"cd {remote_dir} && sudo docker compose logs --tail=40 2>&1", label="логи контейнеров (для диагностики)")
run(f"cd {remote_dir} && sudo docker compose ps", label="docker compose ps")

time.sleep(5)
log.info("==> ШАГ 6/6: Проверки изнутри ВМ:")
run("curl -s -m 10 http://localhost/api/hello/ || curl -s -m 10 http://127.0.0.1:8000/api/hello/", label="API")
run("curl -s -m 10 -o /dev/null -w 'HTTP %{http_code}\\n' http://localhost/", label="Frontend")

cli.close()
log.info("=== ВСЕ ШАГИ ЗАВЕРШЕНЫ. Полный лог: %s ===", logfile)
print("\nDONE_SSH_SETUP")
