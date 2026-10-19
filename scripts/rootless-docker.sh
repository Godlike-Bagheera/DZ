#!/usr/bin/env bash
# ============================================================================
# Установка DOCKER БЕЗ ПРАВА sudo (rootless) — для РЕД ОС / ALT Linux и т.п.
# Ставится в домашнюю папку: ~/.local/bin/docker, ~/.local/bin/dockerd
# Ничего системного не трогает, требует только curl/wget и tar (есть всегда).
#
# ЗАПУСКАТЬ НА ОСНОВНОЙ СИСТЕМЕ (той, где ты сидишь под stud@...):
#   bash rootless-docker.sh
# ============================================================================
set -e

echo "==> 1. Проверяю интернет..."
if command -v curl >/dev/null 2>&1; then DL="curl -fsSL"; else DL="wget -qO-"; fi
$DL https://download.docker.com > /dev/null && echo "    ОК" || { echo "НЕТ ИНТЕРНЕТА наружу — см. раздел 'Если интернета нет' в конце"; }

echo "==> 2. Качаю статические бинарники Docker (официальный сайт)..."
mkdir -p ~/.local/bin ~/.docker-data
cd /tmp
DVER=27.3.1
$DL "https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-$DVER.tgz" -o rce.tgz || \
$DL "https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-$DVER.tgz" > rce.tgz
$DL "https://download.docker.com/linux/static/stable/x86_64/docker-$DVER.tgz" -o dkr.tgz || \
$DL "https://download.docker.com/linux/static/stable/x86_64/docker-$DVER.tgz" > dkr.tgz

echo "==> 3. Распаковываю в ~/.local/bin ..."
tar xzf dkr.tgz && tar xzf rce.tgz
cp docker/docker* ~/.local/bin/ 2>/dev/null || true
cp docker-rootless-extras/* ~/.local/bin/ 2>/dev/null || true   # тут же rootlesskit и newuidmap/newgidmap-обёртки
chmod +x ~/.local/bin/* 

# докер-команды compose: плагин-бинарник
$DL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o ~/.docker/cli-plugins/docker-compose 2>/dev/null || {
  mkdir -p ~/.docker/cli-plugins
  $DL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" > ~/.docker/cli-plugins/docker-compose
}
chmod +x ~/.docker/cli-plugins/docker-compose

echo "==> 4. Добавляю ~/.local/bin в PATH (в .bashrc)..."
grep -q '.local/bin' ~/.bashrc || echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
export PATH=$HOME/.local/bin:$PATH
docker --version && docker compose version

echo "==> 5. Настраиваю rootless-демона..."
# subuid/subgid обычно есть в РЕД ОС; если нет — без sudo не обойтись, см. вывод ниже
cat /etc/subuid 2>/dev/null | grep -q "^$(whoami):" && echo "    subuid есть, ОК" || \
  echo "    ВНИМАНИЕ: тебя нет в /etc/subuid. Попроси админа строку '$(whoami):100000:65536'"

systemctl --user status >/dev/null 2>&1 || { echo "    systemd --user недоступен (нет сессии?) — запусти из обычного терминала входа, не из su"; exit 1; }

# iptables может отсутствовать/не грузиться без sudo — тогда демон стартует с --iptables=false
export PATH=~/.local/bin:$PATH
if command -v rootlesskit >/dev/null 2>&1 || [ -x ~/.local/bin/rootlesskit ]; then
  echo "    rootlesskit найден, ОК"
else
  echo "    ВНИМАНИЕ: rootlesskit не найден даже после распаковки — см. доп. инструкции ниже"; 
fi

~/.local/bin/dockerd-rootless-setuptool.sh install || {
  echo "    Пробую установить с обходом проверок (без iptables, допустимо для учебных задач)...";
  mkdir -p ~/.config/systemd/user
  cat > ~/.config/systemd/user/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine (Rootless)
Documentation=https://docs.docker.com/go/rootless/

[Service]
Environment=PATH=\$HOME/.local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
ExecStart=\$HOME/.local/bin/dockerd-rootless.sh --iptables=false --ip6tables=false --bridge=none
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  systemctl daemon-reload --user 2>/dev/null || true
}

echo "==> 6. Запускаю демона..."
systemctl --user enable --now docker 2>/dev/null || {
  nohup ~/.local/bin/dockerd-rootless.sh --iptables=false --ip6tables=false --bridge=none > ~/dockerd.log 2>&1 &
}
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
grep -q 'DOCKER_HOST' ~/.bashrc || echo "export DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/docker.sock" >> ~/.bashrc

sleep 5
echo "==> 7. Проверка:"
docker info | head -5 && docker run --rm hello-world && echo "=== ДОКЕР БЕЗ SUDO РАБОТАЕТ ===" || echo "Не взлетело — пришли вывод команды: cat ~/dockerd.log | tail -30"
