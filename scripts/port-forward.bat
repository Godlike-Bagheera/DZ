@echo off
REM Проброс портов для ВМ в VirtualBox (запускать на хосте, Windows).
REM Требует, чтобы ВМ называлась "ubuntu-server" (или поправь имя ниже).
REM Режим сети должен быть NAT.
VBoxManage modifyvm "ubuntu-server" --natpf1 "ssh,tcp,,2222,,22"
VBoxManage modifyvm "ubuntu-server" --natpf1 "web,tcp,,8080,,80"
VBoxManage modifyvm "ubuntu-server" --natpf1 "api,tcp,,8000,,8000"
echo Готово. Теперь: SSH -> ssh -p 2222 student@127.0.0.1, сайт -> http://localhost:8080
pause
