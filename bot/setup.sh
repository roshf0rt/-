#!/usr/bin/env bash
# Первичная настройка бота на сервере: спрашивает токен и chat id, пишет .env и запускает контейнер.
# Запуск из папки бота: bash setup.sh
set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
    read -rp ".env уже есть. Перезаписать? [y/N] " answer
    [ "${answer,,}" = "y" ] || { echo "Оставляю прежний .env."; exit 0; }
fi

# -s: ввод токена не отображается на экране.
read -rsp "Токен бота от @BotFather: " bot_token
echo
[ -n "$bot_token" ] || { echo "Токен не введён."; exit 1; }

read -rp "Ваш chat id (пусто, если не знаете — бот покажет его на /start): " chat_id

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
