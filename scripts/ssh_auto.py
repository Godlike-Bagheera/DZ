#!/usr/bin/env python3
# ssh_auto.py — автологин по паролю без sshpass/expect (только стандартная библиотека)
# Использование:
#   python3 ssh_auto.py run    <host> <port> <user> <pass> <cmd...>   # SSH-команда, вывод как есть
#   python3 ssh_auto.py putdir <host> <port> <user> <pass> <local> <remote>  # загрузка папки (sftp)
import os, sys, socket

try:
    import paramiko
except ImportError:
    print("[!] Python-модуль paramiko не найден. Запусти скрипт через scripts/vm-setup.sh"
          " — он сам установит его в ~/.local.", file=sys.stderr)
    sys.exit(42)

def get_client(host, port, user, pw):
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        c.connect(hostname=host, port=int(port), username=user, password=pw,
                  timeout=15, banner_timeout=30, auth_timeout=30,
                  allow_agent=False, look_for_keys=False)
    except Exception as e:
        print(f"[SSH] Не удалось подключиться к {user}@{host}:{port}: {e}", file=sys.stderr)
        sys.exit(1)
    return c

def main():
    mode, host, port, user, pw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
    c = get_client(host, port, user, pw)
    rc = 0
    try:
        if mode == "run":
            cmd = " ".join(sys.argv[6:])
            chan = c.exec_command(cmd, get_pty=True)
            for line in iter(lambda: chan.stdout.readline().decode(errors="replace"), ""):
                sys.stdout.write(line); sys.stdout.flush()
            rc = chan.recv_exit_status()
        elif mode == "putdir":
            local, remote = sys.argv[6], sys.argv[7]
            sftp = c.open_sftp()
            def ensure(d):
                dirs, cur = [], d.rstrip("/") or "/"
                while True:
                    try:
                        sftp.stat(cur); break
                    except IOError:
                        dirs.append(cur)
                        parent = os.path.dirname(cur)
                        if parent == cur: break
                        cur = parent
                for d in reversed(dirs):
                    try: sftp.mkdir(d)
                    except IOError: pass
            n = 0
            for root, files, _ in os.walk(local):
                for f in files:
                    lp = os.path.join(root, f)
                    rp = remote + "/" + os.path.relpath(lp, local).replace(os.sep, "/")
                    ensure(os.path.dirname(rp))
                    sftp.put(lp, rp); n += 1
            print(f"[ok] загружено файлов: {n}")
            sftp.close()
    finally:
        c.close()
    sys.exit(rc)

main()
