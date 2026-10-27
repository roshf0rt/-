#!/usr/bin/env bash
# Ставит сервис общего ДЗ в /opt/urfu-homework. Запускать от root.
# Если порты 80/443 держит Caddy, установленный на сервере (например, для кинотеатра),
# в его конфиг добавляется отдельный адрес для ДЗ — с резервной копией и проверкой.
set -euo pipefail

TARGET=/opt/urfu-homework
IP=${1:-$(curl -4 -fsS https://api.ipify.org)}
DOMAIN=${DOMAIN:-${IP//./-}.sslip.io}

if ! command -v docker >/dev/null; then
  echo "Устанавливаю Docker…"
  curl -fsSL https://get.docker.com | sh
fi

busy=$(ss -ltnpH '( sport = :80 or sport = :443 )' | grep -v docker-proxy || true)
if [ -z "$busy" ]; then
  MODE=own-proxy
elif echo "$busy" | grep -q '"caddy"' && systemctl is-active --quiet caddy; then
  MODE=host-caddy
else
  echo "Порты 80/443 заняты, и это не Caddy из systemd — ничего не меняю:"
  echo "$busy"
  exit 1
fi
echo "Режим: $MODE, адрес: https://$DOMAIN"

mkdir -p "$TARGET/data"
cp app.py requirements.txt Dockerfile Caddyfile docker-compose.yml "$TARGET/"
echo "DOMAIN=$DOMAIN" > "$TARGET/.env"
cd "$TARGET"

if [ "$MODE" = own-proxy ]; then
  docker compose --profile own-proxy up -d --build
else
  docker compose up -d --build api
  CADDYFILE=$(systemctl cat caddy | grep -oP -- '--config \K\S+' | head -1 || true)
  CADDYFILE=${CADDYFILE:-/etc/caddy/Caddyfile}
  if grep -q "$DOMAIN" "$CADDYFILE"; then
    echo "Адрес $DOMAIN уже есть в $CADDYFILE"
  else
    BACKUP="$CADDYFILE.bak-urfu-$(date +%Y%m%d%H%M%S)"
    cp "$CADDYFILE" "$BACKUP"
    printf '\n# Общее ДЗ (urfu-homework)\n%s {\n\tencode gzip\n\treverse_proxy 127.0.0.1:8100\n}\n' "$DOMAIN" >> "$CADDYFILE"
    if ! caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1; then
      cp "$BACKUP" "$CADDYFILE"
      echo "Конфиг Caddy не прошёл проверку, вернул как было ($BACKUP). Кинотеатр не затронут."
      exit 1
    fi
    systemctl reload caddy
    echo "Добавил $DOMAIN в $CADDYFILE (копия: $BACKUP)"
  fi
fi

echo "Жду сертификат для https://$DOMAIN …"
for _ in $(seq 1 30); do
  if curl -fsS "https://$DOMAIN/v1/health" >/dev/null 2>&1; then
    echo "Готово: https://$DOMAIN"
    exit 0
  fi
  sleep 5
done
echo "Сервис запущен, но HTTPS пока не отвечает. Проверьте: curl -s http://127.0.0.1:8100/v1/health и journalctl -u caddy -n 50"
exit 1
