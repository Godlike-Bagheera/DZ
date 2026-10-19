#!/usr/bin/env python3
# Вспомогательный скрипт для finish-setup.ps1: настройка Ubuntu по SSH.
# Запуск: python dz_finish.py 127.0.0.1 2222 stud ПАРОЛЬ /path/to/project
import sys, time, paramiko, pathlib

host, port, user, pw, projdir = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]

cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
for attempt in range(5):
    try:
        cli.connect(host, port=port, username=user, password=pw, timeout=15,
                    banner_timeout=30, auth_timeout=30)
        break
    except Exception as e:
        print(f"[ssh] попытка {attempt+1}: {e}")
        if attempt == 4:
            raise
        time.sleep(10)


def run(cmd, timeout=900, label=None):
    print(f"\n$ {label or cmd[:120]}")
    _, out, err = cli.exec_command(cmd, timeout=timeout)
    o = out.read().decode(errors="replace")
    e = err.read().decode(errors="replace")
    rc = out.channel.recv_exit_status()
    tail = "\n".join((o + "\n" + e).strip().splitlines()[-12:])
    if tail:
        print(tail)
    if rc != 0:
        print(f"[exit {rc}]")
    return rc, o, e


# 1. sudo с паролем (первый раз), затем NOPASSWD
def sudo_once(inner):
    # передаём пароль через stdin, безопаснее чем echo в командной строке
    full = f"sudo -S -p '' bash -c '{inner}'" if "'" not in inner else None
    if full is None:
        import base64
        b64 = base64.b64encode(inner.encode()).decode()
        full = f"echo {b64} | base64 -d > /tmp/_dzcmd.sh && sudo -S -p '' bash /tmp/_dzcmd.sh"
    _, out, err = cli.exec_command(full, timeout=900)
    out.channel.sendall((pw + "\n").encode())
    o = out.read().decode(errors="replace")
    e = err.read().decode(errors="replace")
    rc = out.channel.recv_exit_status()
    print(f"$ [sudo] {inner[:100]}")
    t = "\n".join((o + "\n" + e).strip().splitlines()[-8:])
    if t:
        print(t)
    return rc, o, e


print("==> Базовые пакеты...")
sudo_once("apt-get update -y && apt-get install -y curl ca-certificates sudo")

print("==> Разрешаю NOPASSWD sudo для " + user + "...")
rc, _, _ = sudo_once(
    f"usermod -aG sudo {user}; echo '{user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/{user}; chmod 440 /etc/sudoers.d/{user}"
)
if rc != 0:
    print("[!] Не удалось настроить sudo — проверь правильность пароля (-VmPass).")
    sys.exit(1)


def su(cmd, timeout=900, label=None):
    return run(f"sudo bash -c \"{cmd}\"", timeout=timeout, label=label or cmd[:100])


print("==> Docker...")
rc, _, _ = su("command -v docker")
if rc != 0:
    su("curl -fsSL https://get.docker.com | sh", timeout=1500, label="установка docker (может занять ~2 мин)")
else:
    print("    docker уже установлен")
su(f"usermod -aG docker {user}")
su("systemctl enable --now docker")
run("sleep 2; sudo docker info --format '{{.ServerVersion}}'", label="версия docker")

print("==> Копирую проект в ВМ (SFTP)...")
remote_dir = f"/home/{user}/dz"
run(f"rm -rf {remote_dir}; mkdir -p {remote_dir}", label="подготовка папки на ВМ")
sftp = cli.open_sftp()

def put_dir(local, remote):
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

put_dir(projdir, remote_dir)
sftp.close()
print("    скопировано")

print("==> Сборка и запуск контейнеров (5-15 мин)...")
run(f"cd {remote_dir} && sudo docker compose up -d --build 2>&1 | tail -25",
    timeout=2400, label="docker compose up -d --build")
run(f"cd {remote_dir} && sudo docker compose ps", label="docker compose ps")

time.sleep(5)
print("==> Проверки изнутри ВМ:")
run("curl -s -m 10 http://localhost/api/hello/ || curl -s -m 10 http://127.0.0.1:8000/api/hello/", label="API")
run("curl -s -m 10 -o /dev/null -w 'HTTP %{http_code}\\n' http://localhost/", label="Frontend")

cli.close()
print("\nDONE_SSH_SETUP")
