#!/usr/bin/env bash
# Ставит сервер общего ДЗ с Mac: подключается по SSH и запускает установку.
# Запуск: в Терминале выполните  bash ~/Downloads/deploy-mac.command
set -euo pipefail

read -r -p "IP сервера [2.26.99.200]: " HOST
HOST=${HOST:-2.26.99.200}
read -r -p "Пользователь [root]: " USER_NAME
USER_NAME=${USER_NAME:-root}

echo
echo "Подключаюсь к $USER_NAME@$HOST. Сейчас спросят пароль от сервера (символы не видны — это нормально)."
echo
ssh -o StrictHostKeyChecking=accept-new "$USER_NAME@$HOST" 'bash -s' <<'URFU_DEPLOY'
#!/usr/bin/env bash
# Всё для сервера общего ДЗ в одном файле: вставьте целиком в SSH-терминал (под root).
# Ставит сервис в /opt/urfu-homework. Онлайн-кинотеатр и другие сервисы не трогает:
# если порты 80/443 заняты, скрипт остановится и ничего не изменит.
set -euo pipefail
SRC=$(mktemp -d)
cd "$SRC"
cat > app.py <<'URFU_EOF'
"""Общее ДЗ для приложения «Расписание УрФУ».

Пользователь — это ник и группа, без пароля: приложение получает токен при
регистрации и хранит его у себя. ДЗ привязано к паре по предмету и времени
начала, поэтому потоковая пара у нескольких групп получает одно и то же ДЗ.
"""
import hashlib
import os
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from pydantic import BaseModel, Field, field_validator

POSTS_PER_HOUR = int(os.environ.get("POSTS_PER_HOUR", "30"))
GROUP_ID = r"^\d{1,12}$"

app = FastAPI(title="UrFU homework", version="1")

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    token_hash TEXT UNIQUE NOT NULL,
    nickname TEXT NOT NULL,
    group_id TEXT NOT NULL,
    group_name TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS homework (
    id INTEGER PRIMARY KEY,
    author_id INTEGER NOT NULL REFERENCES users(id),
    subject TEXT NOT NULL,
    lesson_start TEXT NOT NULL,
    text TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS audience (
    homework_id INTEGER NOT NULL REFERENCES homework(id),
    group_id TEXT NOT NULL,
    group_name TEXT NOT NULL,
    PRIMARY KEY (homework_id, group_id)
);
CREATE INDEX IF NOT EXISTS audience_group ON audience(group_id);
CREATE INDEX IF NOT EXISTS homework_author_time ON homework(author_id, created_at);
"""


def db():
    conn = sqlite3.connect(os.environ.get("DB_PATH", "/data/homework.db"))
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def clean(text: str) -> str:
    """Trim and drop control characters except newlines."""
    return "".join(ch for ch in text.strip() if ch == "\n" or ch.isprintable())


class Group(BaseModel):
    id: str = Field(pattern=GROUP_ID)
    name: str = Field(min_length=1, max_length=64)


class ProfileIn(BaseModel):
    nickname: str = Field(min_length=2, max_length=32)
    group: Group

    @field_validator("nickname")
    @classmethod
    def nickname_clean(cls, value: str) -> str:
        value = clean(value).replace("\n", " ")
        if len(value) < 2:
            raise ValueError("ник слишком короткий")
        return value


class HomeworkIn(BaseModel):
    subject: str = Field(min_length=1, max_length=200)
    lesson_start: datetime
    text: str = Field(min_length=1, max_length=2000)
    audience: list[Group] = Field(min_length=1, max_length=10)

    @field_validator("text", "subject")
    @classmethod
    def text_clean(cls, value: str) -> str:
        value = clean(value)
        if not value:
            raise ValueError("пустой текст")
        return value


def current_user(authorization: str = Header(default=""), conn=Depends(db)) -> sqlite3.Row:
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(401, "нужен токен")
    user = conn.execute(
        "SELECT * FROM users WHERE token_hash = ?", (hashlib.sha256(token.encode()).hexdigest(),)
    ).fetchone()
    if user is None:
        raise HTTPException(401, "неизвестный токен")
    return user


def user_json(user: sqlite3.Row) -> dict:
    return {"id": user["id"], "nickname": user["nickname"],
            "group": {"id": user["group_id"], "name": user["group_name"]}}


def homework_json(conn, row: sqlite3.Row, viewer_id: int | None) -> dict:
    audience = conn.execute(
        "SELECT group_id, group_name FROM audience WHERE homework_id = ? ORDER BY group_name", (row["id"],)
    ).fetchall()
    return {
        "id": row["id"],
        "author": {"id": row["author_id"], "nickname": row["nickname"], "group_name": row["group_name"]},
        "subject": row["subject"],
        "lesson_start": row["lesson_start"],
        "text": row["text"],
        "audience": [{"id": a["group_id"], "name": a["group_name"]} for a in audience],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "mine": row["author_id"] == viewer_id,
    }


def load_homework(conn, homework_id: int) -> sqlite3.Row:
    row = conn.execute(
        """SELECT h.*, u.nickname, u.group_name FROM homework h JOIN users u ON u.id = h.author_id
           WHERE h.id = ? AND h.deleted = 0""",
        (homework_id,),
    ).fetchone()
    if row is None:
        raise HTTPException(404, "ДЗ не найдено")
    return row


@app.get("/v1/health")
def health():
    return {"ok": True}


@app.post("/v1/users")
def register(profile: ProfileIn, conn=Depends(db)):
    token = secrets.token_urlsafe(32)
    cursor = conn.execute(
        "INSERT INTO users (token_hash, nickname, group_id, group_name, created_at) VALUES (?, ?, ?, ?, ?)",
        (hashlib.sha256(token.encode()).hexdigest(), profile.nickname, profile.group.id,
         profile.group.name, iso(now())),
    )
    user = conn.execute("SELECT * FROM users WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return {"token": token, "user": user_json(user)}


@app.put("/v1/users/me")
def update_profile(profile: ProfileIn, user=Depends(current_user), conn=Depends(db)):
    conn.execute(
        "UPDATE users SET nickname = ?, group_id = ?, group_name = ? WHERE id = ?",
        (profile.nickname, profile.group.id, profile.group.name, user["id"]),
    )
    return user_json(conn.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone())


@app.get("/v1/homework")
def list_homework(groups: str = Query(min_length=1, max_length=400),
                  user=Depends(current_user), conn=Depends(db)):
    """ДЗ, адресованное любой из групп, для пар от недели назад до двух месяцев вперёд."""
    ids = [g for g in groups.split(",") if g]
    if not ids or len(ids) > 20 or any(not g.isdigit() or len(g) > 12 for g in ids):
        raise HTTPException(422, "groups: до 20 числовых id через запятую")
    start = iso(now() - timedelta(days=7))
    end = iso(now() + timedelta(days=60))
    marks = ",".join("?" * len(ids))
    rows = conn.execute(
        f"""SELECT DISTINCT h.*, u.nickname, u.group_name FROM homework h
            JOIN users u ON u.id = h.author_id
            JOIN audience a ON a.homework_id = h.id
            WHERE h.deleted = 0 AND a.group_id IN ({marks}) AND h.lesson_start BETWEEN ? AND ?
            ORDER BY h.lesson_start, h.created_at""",
        (*ids, start, end),
    ).fetchall()
    return [homework_json(conn, row, user["id"]) for row in rows]


@app.post("/v1/homework")
def create_homework(item: HomeworkIn, user=Depends(current_user), conn=Depends(db)):
    hour_ago = iso(now() - timedelta(hours=1))
    recent = conn.execute(
        "SELECT COUNT(*) FROM homework WHERE author_id = ? AND created_at > ?", (user["id"], hour_ago)
    ).fetchone()[0]
    if recent >= POSTS_PER_HOUR:
        raise HTTPException(429, "слишком много записей, попробуйте позже")
    stamp = iso(now())
    cursor = conn.execute(
        """INSERT INTO homework (author_id, subject, lesson_start, text, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (user["id"], item.subject, iso(item.lesson_start), item.text, stamp, stamp),
    )
    save_audience(conn, cursor.lastrowid, item.audience)
    return homework_json(conn, load_homework(conn, cursor.lastrowid), user["id"])


@app.put("/v1/homework/{homework_id}")
def update_homework(homework_id: int, item: HomeworkIn, user=Depends(current_user), conn=Depends(db)):
    row = load_homework(conn, homework_id)
    if row["author_id"] != user["id"]:
        raise HTTPException(403, "менять можно только своё ДЗ")
    conn.execute(
        "UPDATE homework SET subject = ?, lesson_start = ?, text = ?, updated_at = ? WHERE id = ?",
        (item.subject, iso(item.lesson_start), item.text, iso(now()), homework_id),
    )
    conn.execute("DELETE FROM audience WHERE homework_id = ?", (homework_id,))
    save_audience(conn, homework_id, item.audience)
    return homework_json(conn, load_homework(conn, homework_id), user["id"])


@app.delete("/v1/homework/{homework_id}")
def delete_homework(homework_id: int, user=Depends(current_user), conn=Depends(db)):
    row = load_homework(conn, homework_id)
    if row["author_id"] != user["id"]:
        raise HTTPException(403, "удалять можно только своё ДЗ")
    conn.execute("UPDATE homework SET deleted = 1, updated_at = ? WHERE id = ?", (iso(now()), homework_id))
    return {"ok": True}


def save_audience(conn, homework_id: int, groups: list[Group]) -> None:
    unique = {group.id: group for group in groups}
    conn.executemany(
        "INSERT INTO audience (homework_id, group_id, group_name) VALUES (?, ?, ?)",
        [(homework_id, group.id, group.name) for group in unique.values()],
    )
URFU_EOF
cat > requirements.txt <<'URFU_EOF'
fastapi==0.115.6
uvicorn==0.34.0
URFU_EOF
cat > Dockerfile <<'URFU_EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENV DB_PATH=/data/homework.db
VOLUME /data
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
URFU_EOF
cat > Caddyfile <<'URFU_EOF'
{$DOMAIN} {
	encode gzip
	reverse_proxy api:8000
}
URFU_EOF
cat > docker-compose.yml <<'URFU_EOF'
# Общее ДЗ: API и Caddy с бесплатным HTTPS-сертификатом для $DOMAIN.
services:
  api:
    build: .
    restart: unless-stopped
    volumes:
      - ./data:/data
  caddy:
    image: caddy:2.8.4
    restart: unless-stopped
    depends_on: [api]
    ports:
      - "80:80"
      - "443:443"
    environment:
      DOMAIN: ${DOMAIN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
volumes:
  caddy_data:
  caddy_config:
URFU_EOF
cat > install.sh <<'URFU_EOF'
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
URFU_EOF
chmod +x install.sh
./install.sh
URFU_DEPLOY

echo
read -r -p "Готово. Нажмите Enter, чтобы закрыть."
