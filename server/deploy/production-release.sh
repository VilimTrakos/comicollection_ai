#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 SOURCE_SERVER_DIRECTORY" >&2
  exit 2
fi

SOURCE_DIR=$(CDPATH= cd -- "$1" && pwd)
APP_ROOT=/opt/comicollect
RELEASES_DIR=$APP_ROOT/releases
CURRENT_LINK=$APP_ROOT/current
UNIT_DIR=/etc/systemd/system
API_UNIT=comicollect-production.service
BACKUP_UNIT=comicollect-production-backup.service
TIMER_UNIT=comicollect-production-backup.timer
CHECK_TEMPLATE=comicollect-production-check@.service
LEGACY_CHECK_UNIT=comicollect-production-check.service
HEALTHCHECK_TARGET=$APP_ROOT/tools/production-healthcheck.py
RELEASE_ID=${COMICOLLECT_RELEASE_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}

case "$RELEASE_ID" in
  ""|*[!A-Za-z0-9._-]*)
    echo "Release id contains unsupported characters" >&2
    exit 1
    ;;
esac

UNIT_BACKUP=$(mktemp -d /tmp/comicollect-units.XXXXXX)
CANDIDATE=$RELEASES_DIR/$RELEASE_ID
PREVIOUS_TARGET=
CANDIDATE_CREATED=false
CURRENT_CHANGED=false
UNITS_INSTALLED=false
CHECK_TEMPLATE_INSTALLED=false
SUCCESS=false
OLD_API_ACTIVE=false
OLD_API_ENABLED=false
OLD_TIMER_ACTIVE=false
OLD_TIMER_ENABLED=false
TIMER_PAUSED=false

atomic_current() {
  target=$1
  temporary=$APP_ROOT/.current.$$
  rm -f "$temporary"
  ln -s "$target" "$temporary"
  mv -Tf "$temporary" "$CURRENT_LINK"
}

remember_unit() {
  unit=$1
  if [ -f "$UNIT_DIR/$unit" ]; then
    cp -p "$UNIT_DIR/$unit" "$UNIT_BACKUP/$unit"
  else
    : > "$UNIT_BACKUP/$unit.missing"
  fi
}

restore_unit() {
  unit=$1
  if [ -f "$UNIT_BACKUP/$unit.missing" ]; then
    rm -f "$UNIT_DIR/$unit"
  else
    cp -p "$UNIT_BACKUP/$unit" "$UNIT_DIR/$unit"
  fi
}

restore_healthcheck() {
  if [ -f "$UNIT_BACKUP/production-healthcheck.py.missing" ]; then
    rm -f "$HEALTHCHECK_TARGET"
  else
    cp -p "$UNIT_BACKUP/production-healthcheck.py" "$HEALTHCHECK_TARGET"
  fi
}

restore_enabled_state() {
  if [ "$OLD_API_ENABLED" = true ]; then
    systemctl enable "$API_UNIT" >/dev/null 2>&1 || true
  else
    systemctl disable "$API_UNIT" >/dev/null 2>&1 || true
  fi
  if [ "$OLD_TIMER_ENABLED" = true ]; then
    systemctl enable "$TIMER_UNIT" >/dev/null 2>&1 || true
  else
    systemctl disable "$TIMER_UNIT" >/dev/null 2>&1 || true
  fi
}

rollback() {
  status=$?
  trap - 0 1 2 15
  set +e
  if [ "$SUCCESS" = true ]; then
    rm -rf "$UNIT_BACKUP"
    exit 0
  fi
  [ "$status" -ne 0 ] || status=1
  echo "Release $RELEASE_ID failed; restoring the previous runtime." >&2

  if [ "$UNITS_INSTALLED" = true ]; then
    systemctl stop "$API_UNIT" >/dev/null 2>&1 || true
  fi
  if [ "$CURRENT_CHANGED" = true ]; then
    if [ -n "$PREVIOUS_TARGET" ]; then
      atomic_current "$PREVIOUS_TARGET"
    else
      rm -f "$CURRENT_LINK"
    fi
  fi
  if [ "$UNITS_INSTALLED" = true ]; then
    restore_unit "$API_UNIT"
    restore_unit "$BACKUP_UNIT"
    restore_unit "$TIMER_UNIT"
    restore_unit "$LEGACY_CHECK_UNIT"
    restore_healthcheck
  fi
  if [ "$CHECK_TEMPLATE_INSTALLED" = true ]; then
    restore_unit "$CHECK_TEMPLATE"
  fi
  if [ "$UNITS_INSTALLED" = true ] || [ "$CHECK_TEMPLATE_INSTALLED" = true ]; then
    systemctl daemon-reload || true
    systemctl reset-failed "comicollect-production-check@$RELEASE_ID.service" \
      >/dev/null 2>&1 || true
  fi
  if [ "$UNITS_INSTALLED" = true ]; then
    restore_enabled_state
    systemctl reset-failed "$API_UNIT" >/dev/null 2>&1 || true
    if [ "$OLD_API_ACTIVE" = true ] && [ -n "$PREVIOUS_TARGET" ]; then
      systemctl restart "$API_UNIT" || true
    fi
    if [ "$OLD_TIMER_ACTIVE" = true ]; then
      systemctl start "$TIMER_UNIT" >/dev/null 2>&1 || true
    else
      systemctl stop "$TIMER_UNIT" >/dev/null 2>&1 || true
    fi
  elif [ "$TIMER_PAUSED" = true ] && [ "$OLD_TIMER_ACTIVE" = true ]; then
    systemctl start "$TIMER_UNIT" >/dev/null 2>&1 || true
  fi
  if [ "$CANDIDATE_CREATED" = true ]; then
    rm -rf "$CANDIDATE"
  fi
  rm -rf "$UNIT_BACKUP"
  exit "$status"
}
trap rollback 0 1 2 15

if [ -L "$CURRENT_LINK" ]; then
  PREVIOUS_TARGET=$(readlink -f "$CURRENT_LINK")
elif [ -e "$CURRENT_LINK" ]; then
  echo "$CURRENT_LINK must be a symbolic link" >&2
  exit 1
elif [ -d "$APP_ROOT/server" ] && [ -x "$APP_ROOT/venv/bin/python" ]; then
  # One-time compatibility bridge from the original in-place layout. The old
  # files are not modified and remain a valid rollback target.
  atomic_current "$APP_ROOT"
  PREVIOUS_TARGET=$APP_ROOT
fi

if [ -e "$CANDIDATE" ]; then
  echo "Release already exists: $CANDIDATE" >&2
  exit 1
fi

CANDIDATE_CREATED=true
install -d -o root -g root -m 0755 \
  "$CANDIDATE/server/comicollect_backend" \
  "$CANDIDATE/server/deploy/nginx" \
  "$CANDIDATE/server/systemd" \
  "$CANDIDATE/docs"
install -o root -g root -m 0755 \
  "$SOURCE_DIR/comicollect_server.py" \
  "$SOURCE_DIR/comicollect_backup.py" \
  "$CANDIDATE/server/"
install -o root -g root -m 0644 \
  "$SOURCE_DIR/comicollect_wsgi.py" \
  "$SOURCE_DIR/gunicorn.conf.py" \
  "$SOURCE_DIR/requirements-production.txt" \
  "$CANDIDATE/server/"
install -o root -g root -m 0644 \
  "$SOURCE_DIR"/comicollect_backend/*.py \
  "$CANDIDATE/server/comicollect_backend/"
install -o root -g root -m 0644 \
  "$SOURCE_DIR/deploy/comicollect.production.env.example" \
  "$CANDIDATE/server/deploy/"
install -o root -g root -m 0755 \
  "$SOURCE_DIR/deploy/production-healthcheck.py" \
  "$SOURCE_DIR/deploy/production-release.sh" \
  "$CANDIDATE/server/deploy/"
install -o root -g root -m 0644 \
  "$SOURCE_DIR/deploy/nginx/comicollect.conf" \
  "$CANDIDATE/server/deploy/nginx/"
install -o root -g root -m 0644 \
  "$SOURCE_DIR"/systemd/comicollect-production* \
  "$CANDIDATE/server/systemd/"
install -o root -g root -m 0644 \
  "$SOURCE_DIR/../docs/production-deployment.md" \
  "$CANDIDATE/docs/production-deployment.md"

python3 -m venv "$CANDIDATE/venv"
"$CANDIDATE/venv/bin/pip" install --disable-pip-version-check \
  --requirement "$CANDIDATE/server/requirements-production.txt"

remember_unit "$CHECK_TEMPLATE"
CHECK_TEMPLATE_INSTALLED=true
install -o root -g root -m 0644 \
  "$SOURCE_DIR/systemd/$CHECK_TEMPLATE" "$UNIT_DIR/$CHECK_TEMPLATE"
systemctl daemon-reload
systemctl reset-failed "comicollect-production-check@$RELEASE_ID.service" \
  >/dev/null 2>&1 || true
systemctl start "comicollect-production-check@$RELEASE_ID.service"

systemctl is-active --quiet "$API_UNIT" && OLD_API_ACTIVE=true || true
systemctl is-enabled --quiet "$API_UNIT" && OLD_API_ENABLED=true || true
systemctl is-active --quiet "$TIMER_UNIT" && OLD_TIMER_ACTIVE=true || true
systemctl is-enabled --quiet "$TIMER_UNIT" && OLD_TIMER_ENABLED=true || true
if [ "$OLD_TIMER_ACTIVE" = true ]; then
  TIMER_PAUSED=true
  systemctl stop "$TIMER_UNIT"
fi
if systemctl is-active --quiet "$BACKUP_UNIT"; then
  echo "A production backup is still active; retry the deployment later" >&2
  exit 1
fi

remember_unit "$API_UNIT"
remember_unit "$BACKUP_UNIT"
remember_unit "$TIMER_UNIT"
remember_unit "$LEGACY_CHECK_UNIT"
if [ -f "$HEALTHCHECK_TARGET" ]; then
  cp -p "$HEALTHCHECK_TARGET" "$UNIT_BACKUP/production-healthcheck.py"
else
  : > "$UNIT_BACKUP/production-healthcheck.py.missing"
fi
UNITS_INSTALLED=true
rm -f "$UNIT_DIR/$LEGACY_CHECK_UNIT"
install -o root -g root -m 0755 \
  "$SOURCE_DIR/deploy/production-healthcheck.py" "$HEALTHCHECK_TARGET"
install -o root -g root -m 0644 "$SOURCE_DIR/systemd/$API_UNIT" "$UNIT_DIR/$API_UNIT"
install -o root -g root -m 0644 "$SOURCE_DIR/systemd/$BACKUP_UNIT" "$UNIT_DIR/$BACKUP_UNIT"
install -o root -g root -m 0644 "$SOURCE_DIR/systemd/$TIMER_UNIT" "$UNIT_DIR/$TIMER_UNIT"
systemctl daemon-reload

atomic_current "$CANDIDATE"
CURRENT_CHANGED=true
systemctl reset-failed "$API_UNIT" >/dev/null 2>&1 || true
systemctl restart "$API_UNIT"
systemctl enable "$API_UNIT" "$TIMER_UNIT"
systemctl start "$TIMER_UNIT"
install -o root -g root -m 0444 /dev/null "$CANDIDATE/.activated"

CURRENT_TARGET=$(readlink -f "$CURRENT_LINK")
kept=1
case "$PREVIOUS_TARGET" in
  "$RELEASES_DIR"/*) kept=2 ;;
esac
for release in $(ls -1dt "$RELEASES_DIR"/* 2>/dev/null); do
  [ -d "$release" ] || continue
  [ -f "$release/.activated" ] || continue
  [ "$release" = "$CURRENT_TARGET" ] && continue
  if [ -n "$PREVIOUS_TARGET" ] && [ "$release" = "$PREVIOUS_TARGET" ]; then
    continue
  elif [ "$kept" -lt 4 ]; then
    kept=$((kept + 1))
  else
    rm -rf "$release"
  fi
done

SUCCESS=true
echo "Activated immutable release $RELEASE_ID."
exit 0
