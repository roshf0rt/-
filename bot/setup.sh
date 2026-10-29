#!/usr/bin/env bash
# Первичная настройка бота на сервере: спрашивает токен и chat id, пишет .env и запускает контейнер.
# Запуск из папки бота: bash setup.sh
set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
    read -rp ".env уже есть. Перезаписать? [y/N] " answer
    [ "${answer,,}" = "y" ] || { echo "Оставляю прежний .env."; exit 0; }
fi

# Сначала токен: вставьте и нажмите Enter. Виден, чтобы на телефоне было понятно, что вставилось.
echo "1/2. Вставьте токен бота от @BotFather и нажмите Enter:"
read -r bot_token
[ -n "$bot_token" ] || { echo "Токен не введён."; exit 1; }

echo "2/2. Введите ваш chat id (например 523233167) и нажмите Enter."
echo "     Если не знаете — просто нажмите Enter, бот покажет его на /start."
read -r chat_id

umask 077
cat > .env <<EOF
BOT_TOKEN=$bot_token
ALLOWED_CHAT_IDS=$chat_id
GROUP_ID=65979
REMIND_MINUTES=10
DIGEST_HOUR=8
EOF
unset bot_token

echo "Записано в $(pwd)/.env (доступ только у владельца)."
docker compose up -d --build
echo "Готово. Логи: docker compose logs -f"
