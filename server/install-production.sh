#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_ROOT=/opt/comicollect
SERVER_DIR=$APP_ROOT/server
VENV_DIR=$APP_ROOT/venv
DATA_DIR=/var/lib/comicollect
BACKUP_DIR=/var/backups/comicollect
CONFIG_DIR=/etc/comicollect
ENV_FILE=$CONFIG_DIR/production.env
PEPPER_FILE=$CONFIG_DIR/password-pepper

usage() {
  echo "Usage: $0 [--dry-run]" >&2
  exit 2
}

DRY_RUN=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *) usage ;;
esac

require_file() {
  file=$1
  if [ ! -f "$file" ]; then
    echo "Required production file is missing: $file" >&2
    exit 1
  fi
}

require_file "$SCRIPT_DIR/comicollect_server.py"
require_file "$SCRIPT_DIR/comicollect_wsgi.py"
require_file "$SCRIPT_DIR/gunicorn.conf.py"
require_file "$SCRIPT_DIR/requirements-production.txt"
require_file "$SCRIPT_DIR/systemd/comicollect-production.service"
require_file "$SCRIPT_DIR/systemd/comicollect-production-check.service"
require_file "$SCRIPT_DIR/systemd/comicollect-production-backup.service"
require_file "$SCRIPT_DIR/systemd/comicollect-production-backup.timer"
require_file "$SCRIPT_DIR/deploy/comicollect.production.env.example"
require_file "$SCRIPT_DIR/deploy/nginx/comicollect.conf"
require_file "$SCRIPT_DIR/../docs/production-deployment.md"

if [ "$DRY_RUN" = true ]; then
  echo "Production install dry-run passed."
  echo "No files, secrets, packages, or services were changed."
  echo "Target: $APP_ROOT; data: $DATA_DIR; backup: $BACKUP_DIR"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root: sudo ./install-production.sh" >&2
  exit 1
fi

for command in python3 openssl install systemctl useradd; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required" >&2
    exit 1
  }
done

id comicollect >/dev/null 2>&1 || \
  useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin comicollect

install -d -o root -g root -m 0755 "$APP_ROOT" "$SERVER_DIR"
install -d -o root -g root -m 0755 \
  "$SERVER_DIR/comicollect_backend" "$SERVER_DIR/deploy/nginx" "$APP_ROOT/docs"
install -d -o comicollect -g comicollect -m 0750 "$DATA_DIR" "$BACKUP_DIR"
install -d -o root -g comicollect -m 0750 "$CONFIG_DIR"

install -o root -g root -m 0755 \
  "$SCRIPT_DIR/comicollect_server.py" "$SERVER_DIR/comicollect_server.py"
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/comicollect_wsgi.py" "$SERVER_DIR/comicollect_wsgi.py"
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/gunicorn.conf.py" "$SERVER_DIR/gunicorn.conf.py"
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/requirements-production.txt" \
  "$SERVER_DIR/requirements-production.txt"
install -o root -g root -m 0644 \
  "$SCRIPT_DIR"/comicollect_backend/*.py "$SERVER_DIR/comicollect_backend/"
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/../docs/production-deployment.md" \
  "$APP_ROOT/docs/production-deployment.md"
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/deploy/nginx/comicollect.conf" \
  "$SERVER_DIR/deploy/nginx/comicollect.conf"

if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --disable-pip-version-check \
  --requirement "$SERVER_DIR/requirements-production.txt"

if [ ! -f "$PEPPER_FILE" ]; then
  PEPPER_TEMP=$CONFIG_DIR/.password-pepper.$$
  trap 'rm -f "${PEPPER_TEMP:-}"' 0 1 2 15
  umask 077
  openssl rand -out "$PEPPER_TEMP" 48
  chown root:comicollect "$PEPPER_TEMP"
  chmod 0440 "$PEPPER_TEMP"
  mv "$PEPPER_TEMP" "$PEPPER_FILE"
  trap - 0 1 2 15
fi
chown root:comicollect "$PEPPER_FILE"
chmod 0440 "$PEPPER_FILE"

if [ ! -f "$ENV_FILE" ]; then
  install -o root -g comicollect -m 0640 \
    "$SCRIPT_DIR/deploy/comicollect.production.env.example" "$ENV_FILE"
fi
chown root:comicollect "$ENV_FILE"
chmod 0640 "$ENV_FILE"

install -o root -g root -m 0644 \
  "$SCRIPT_DIR/systemd/comicollect-production.service" \
  /etc/systemd/system/comicollect-production.service
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/systemd/comicollect-production-check.service" \
  /etc/systemd/system/comicollect-production-check.service
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/systemd/comicollect-production-backup.service" \
  /etc/systemd/system/comicollect-production-backup.service
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/systemd/comicollect-production-backup.timer" \
  /etc/systemd/system/comicollect-production-backup.timer

systemctl daemon-reload
systemctl start comicollect-production-check.service
systemctl enable \
  comicollect-production.service comicollect-production-backup.timer
systemctl restart comicollect-production.service
systemctl start comicollect-production-backup.timer

echo "Comicollect production closed-beta service is running on loopback."
echo "No secret was printed and public registration remains disabled."
echo "Configure DNS, TLS, and nginx using:"
echo "  $APP_ROOT/docs/production-deployment.md"
