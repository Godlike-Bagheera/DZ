#!/usr/bin/env python3
"""Проверка TCP-доступности порта (для диагностики проброса VirtualBox)."""
import socket, sys
host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 2222
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
try:
    s.connect((host, port))
    banner = b""
    try:
        s.settimeout(3)
        banner = s.recv(64)
    except Exception:
        pass
    print(f"TCP {host}:{port} ОТКРЫТ", end="")
    if banner:
        print(f", баннер: {banner.decode(errors='replace').strip()}")
    else:
        print(" (баннер не получен)")
except socket.timeout:
    print(f"TCP {host}:{port} — таймаут (пакеты уходят, но ответа нет; NAT-проброс не доходит до гостя или гость молчит)")
    sys.exit(2)
except ConnectionRefusedError:
    print(f"TCP {host}:{port} — REFUSED (порт на хосте слушается, но внутри виртуалки SSH не запущен / OpenSSH server не установлен)")
    sys.exit(3)
except Exception as e:
    print(f"TCP {host}:{port} — ошибка: {e}")
    sys.exit(4)
