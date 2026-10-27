"""Собирает setup-all.sh (вставить в SSH) и deploy-mac.command (запустить на Mac) из файлов сервера."""
from pathlib import Path

HERE = Path(__file__).parent
FILES = ["app.py", "requirements.txt", "Dockerfile", "Caddyfile", "docker-compose.yml", "install.sh"]

setup = ["""#!/usr/bin/env bash
# Всё для сервера общего ДЗ в одном файле: вставьте целиком в SSH-терминал (под root).
# Ставит сервис в /opt/urfu-homework и не мешает другим сервисам на сервере.
set -euo pipefail
SRC=$(mktemp -d)
cd "$SRC"
"""]
for name in FILES:
    body = (HERE / name).read_text()
    assert "URFU_EOF" not in body and "URFU_DEPLOY" not in body
    setup.append(f"cat > {name} <<'URFU_EOF'\n{body}URFU_EOF\n")
setup.append("chmod +x install.sh\n./install.sh\n")
setup = "".join(setup)
(HERE / "setup-all.sh").write_text(setup)

(HERE / "deploy-mac.command").write_text("""#!/usr/bin/env bash
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
""" + setup + """URFU_DEPLOY

echo
read -r -p "Нажмите Enter, чтобы закрыть."
""")
