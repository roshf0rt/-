#!/usr/bin/env bash
# Ставит сервис общего ДЗ в /opt/urfu-homework. Запускать от root в папке server/.
# Другие сервисы на сервере не трогает: если порты 80/443 заняты, останавливается.
set -euo pipefail

TARGET=/opt/urfu-homework
IP=${1:-$(curl -4 -fsS https://api.ipify.org)}
DOMAIN=${DOMAIN:-${IP//./-}.sslip.io}

if ! command -v docker >/dev/null; then
  echo "Устанавливаю Docker…"
  curl -fsSL https://get.docker.com | sh
fi

busy=$(ss -ltnpH '( sport = :80 or sport = :443 )' | grep -v docker-proxy || true)
if [ -n "$busy" ] && ! docker compose -f "$TARGET/docker-compose.yml" ps -q caddy 2>/dev/null | grep -q .; then
  echo "Порты 80/443 заняты другим сервисом, ничего не меняю:"
  echo "$busy"
  exit 1
fi

mkdir -p "$TARGET/data"
cp app.py requirements.txt Dockerfile Caddyfile docker-compose.yml "$TARGET/"
echo "DOMAIN=$DOMAIN" > "$TARGET/.env"
cd "$TARGET"
docker compose up -d --build

echo "Жду сертификат для https://$DOMAIN …"
for _ in $(seq 1 30); do
  if curl -fsS "https://$DOMAIN/v1/health" >/dev/null 2>&1; then
    echo "Готово: https://$DOMAIN"
    exit 0
  fi
  sleep 5
done
echo "Сервис запущен, но HTTPS пока не отвечает. Логи: docker compose -f $TARGET/docker-compose.yml logs caddy"
exit 1
