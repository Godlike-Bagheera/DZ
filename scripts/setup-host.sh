#!/usr/bin/env bash
# Запустить на ХОСТЕ (Windows: через Git Bash; Mac/Linux: обычный терминал).
# Делает: проверяет VirtualBox/Vagrant, ставит Vagrant при необходимости,
# создаёт ВМ, пробрасывает порты, разворачивает проект.
set -e
cd "$(dirname "$0")/.."

echo "==> 1. Проверка VirtualBox..."
if ! command -v VBoxManage >/dev/null 2>&1; then
  echo "!! VirtualBox не найден. Установи: https://www.virtualbox.org/wiki/Downloads"
  exit 1
fi
VBoxManage --version

echo "==> 2. Проверка Vagrant..."
if ! command -v vagrant >/dev/null 2>&1; then
  echo "!! Vagrant не найден."
  echo "   Windows: winget install Hashicorp.Vagrant"
  echo "   macOS:   brew install vagrant"
  echo "   Linux:   sudo apt install vagrant (или скачай с developer.hashicorp.com)"
  exit 1
fi
vagrant --version

echo "==> 3. Создание ВМ + установка Docker + копирование проекта (займёт 5-15 минут)..."
cd vm && vagrant up && cd ..

echo "==> 4. Развёртывание проекта внутри ВМ..."
cd vm && vagrant ssh -c "cd /home/vagrant/myapp && docker compose up -d --build" ; cd ..

echo ""
echo "✅ ГОТОВО! Проверь в браузере:"
echo "   Фронтенд: http://localhost:8080"
echo "   API:      http://localhost:8000/api/hello/"
echo "Управление ВМ: cd vm && vagrant halt (выключить), vagrant destroy (удалить)"
