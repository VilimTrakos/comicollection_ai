#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_ROOT=/opt/comicollect
RELEASES_DIR=$APP_ROOT/releases
TOOLS_DIR=$APP_ROOT/tools
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
  if [ ! -f "$1" ]; then
    echo "Required production file is missing: $1" >&2
    exit 1
  fi
}

for file in \
  comicollect_server.py comicollect_wsgi.py comicollect_mailer.py \
  comicollect_backup.py \
  comicollect_backend/backup.py comicollect_backend/backup_verification.py \
  comicollect_backend/config.py \
  gunicorn.conf.py requirements-production.txt \
  systemd/comicollect-production.service \
  systemd/comicollect-production-check@.service \
  systemd/comicollect-production-backup.service \
  systemd/comicollect-production-backup.timer \
  systemd/comicollect-production-mailer.service \
  systemd/comicollect-production-mailer.timer \
  deploy/comicollect.production.env.example \
  deploy/nginx/comicollect.conf \
  deploy/production-healthcheck.py \
  deploy/production-release.sh; do
  require_file "$SCRIPT_DIR/$file"
done
require_file "$SCRIPT_DIR/../docs/production-deployment.md"

if [ "$DRY_RUN" = true ]; then
  echo "Production install dry-run passed."
  echo "No files, secrets, packages, or services were changed."
  echo "No release was staged or activated."
  echo "Target: $APP_ROOT/current; data: $DATA_DIR; backup: $BACKUP_DIR"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root: sudo ./install-production.sh" >&2
  exit 1
fi

for command in python3 openssl install systemctl useradd flock; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required" >&2
    exit 1
  }
done

exec 9>/run/lock/comicollect-production-install.lock
if ! flock -n 9; then
  echo "Another Comicollect production install is already running" >&2
  exit 1
fi

id comicollect >/dev/null 2>&1 || \
  useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin comicollect

install -d -o root -g root -m 0755 "$APP_ROOT" "$RELEASES_DIR" "$TOOLS_DIR"
install -d -o comicollect -g comicollect -m 0750 "$DATA_DIR" "$BACKUP_DIR"
install -d -o root -g comicollect -m 0750 "$CONFIG_DIR"

if [ -e "$PEPPER_FILE" ] || [ -L "$PEPPER_FILE" ]; then
  if [ -L "$PEPPER_FILE" ] || [ ! -f "$PEPPER_FILE" ]; then
    echo "Password pepper must be a regular, non-symlink file" >&2
    exit 1
  fi
else
  if [ -e "$ENV_FILE" ] || [ -L "$ENV_FILE" ] || \
     [ -e "$DATA_DIR/accounts.sqlite3" ]; then
    echo "Refusing to replace a missing pepper on an existing installation" >&2
    exit 1
  fi
  PEPPER_TEMP=$CONFIG_DIR/.password-pepper.$$
  trap 'rm -f "${PEPPER_TEMP:-}"' 0 1 2 15
  PEPPER_UMASK=$(umask)
  umask 077
  openssl rand -out "$PEPPER_TEMP" 48
  umask "$PEPPER_UMASK"
  chown root:comicollect "$PEPPER_TEMP"
  chmod 0440 "$PEPPER_TEMP"
  mv "$PEPPER_TEMP" "$PEPPER_FILE"
  trap - 0 1 2 15
fi
chown root:comicollect "$PEPPER_FILE"
chmod 0440 "$PEPPER_FILE"

if [ -e "$ENV_FILE" ] || [ -L "$ENV_FILE" ]; then
  if [ -L "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
    echo "Production environment must be a regular, non-symlink file" >&2
    exit 1
  fi
else
  install -o root -g comicollect -m 0640 \
    "$SCRIPT_DIR/deploy/comicollect.production.env.example" "$ENV_FILE"
fi
chown root:comicollect "$ENV_FILE"
chmod 0640 "$ENV_FILE"

sh "$SCRIPT_DIR/deploy/production-release.sh" "$SCRIPT_DIR"

echo "Comicollect production closed-beta release is ready on loopback."
echo "No secret was printed and public registration remains disabled."
echo "Configure DNS and TLS using $APP_ROOT/current/docs/production-deployment.md"
