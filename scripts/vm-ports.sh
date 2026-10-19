#!/usr/bin/env bash
# Настройка проброса портов VirtualBox для ВМ "UbuntuServ" (выполнять на РЕД ОС)
VBM=/usr/lib/virtualbox/VBoxManage
[ -x "$VBM" ] || VBM=$(command -v VBoxManage)
[ -n "$VBM" ] || { echo "[!] VBoxManage не найден. Установи VirtualBox."; exit 1; }

VM=${1:-UbuntuServ}
"$VBM" list vms | grep -q "\"$VM\"" || { echo "[!] ВМ \"$VM\" не найдена. Список:"; "$VBM" list vms; exit 1; }

echo "==> Удаляю старые правила NAT..."
"$VBM" modifyvm "$VM" --natpf1 delete ssh      2>/dev/null
"$VBM" modifyvm "$VM" --natpf1 delete frontend 2>/dev/null
"$VBM" modifyvm "$VM" --natpf1 delete backend  2>/dev/null

echo "==> Создаю новые правила NAT (ВМ должна быть ВЫКЛЮЧЕНА или в состоянии saved)..."
"$VBM" modifyvm "$VM" --natpf1 "ssh,tcp,,2222,,22"
"$VBM" modifyvm "$VM" --natpf1 "frontend,tcp,,8080,,80"
"$VBM" modifyvm "$VM" --natpf1 "backend,tcp,,8000,,8000"

echo "==> Текущие правила:"
"$VBM" showvminfo "$VM" --machinereadable | grep natpf
echo ""
echo "OK. Запусти ВМ и проверь: nc -zv 127.0.0.1 2222"
