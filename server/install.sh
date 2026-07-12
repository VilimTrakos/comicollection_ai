#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root: sudo ./install.sh" >&2
  exit 1
fi

APP_DIR=/opt/comicollect
DATA_DIR=/var/lib/comicollect
BACKUP_DIR=/var/backups/comicollect
ENV_FILE=/etc/comicollect.env
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

command -v python3 >/dev/null 2>&1 || { echo "Python 3 is required" >&2; exit 1; }
id comicollect >/dev/null 2>&1 || useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin comicollect
install -d -o root -g root -m 0755 "$APP_DIR"
install -d -o comicollect -g comicollect -m 0750 "$DATA_DIR" "$BACKUP_DIR"
install -o root -g root -m 0755 "$SCRIPT_DIR/comicollect_server.py" "$APP_DIR/comicollect_server.py"

if [ ! -f "$ENV_FILE" ]; then
  TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(36))')
  umask 077
  printf 'COMICOLLECT_TOKEN=%s\nCOMICOLLECT_DB=%s/comicollect.sqlite3\nCOMICOLLECT_BACKUP_DIR=%s\nCOMICOLLECT_HOST=0.0.0.0\nCOMICOLLECT_PORT=8787\n' "$TOKEN" "$DATA_DIR" "$BACKUP_DIR" > "$ENV_FILE"
fi

install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/comicollect.service" /etc/systemd/system/comicollect.service
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/comicollect-backup.service" /etc/systemd/system/comicollect-backup.service
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/comicollect-backup.timer" /etc/systemd/system/comicollect-backup.timer
systemctl daemon-reload
systemctl enable --now comicollect.service comicollect-backup.timer

IP=$(hostname -I | awk '{print $1}')
TOKEN=$(sed -n 's/^COMICOLLECT_TOKEN=//p' "$ENV_FILE")
echo
echo "Comicollect is ready. Enter these values in the phone app:"
echo "Server: http://${IP:-YOUR_PI_IP}:8787"
echo "API token: $TOKEN"
echo "Health check: http://${IP:-YOUR_PI_IP}:8787/health"
