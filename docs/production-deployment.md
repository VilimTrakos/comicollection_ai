# Production deployment: single-node closed beta

This profile puts the authenticated Comicollect API behind TLS, runs it as an
unprivileged hardened service, and fails startup when its secret or security
parameters are missing. It is appropriate for a controlled, monitored beta on
one Linux host.

It is **not a high-availability architecture**. Account metadata and each
account's sync realm are SQLite databases, while one layer of auth throttling
is in process memory. Gunicorn therefore runs exactly one `gthread` worker.
Increasing the worker count or adding a second application host is unsupported;
PostgreSQL plus a shared rate limiter are prerequisites for that change.

## Topology and trust boundary

```text
Flutter app
    │ HTTPS only
    ▼
nginx :443  ── TLS, endpoint-specific body limits, per-IP throttling
    │ loopback, X-Real-IP replaced by nginx
    ▼
Gunicorn 127.0.0.1:8787 ── one process, 2–4 bounded threads
    │
    ├── accounts.sqlite3
    └── accounts/account-<sha256(account-id)>.sqlite3
```

Port `8787` must never be opened publicly. The WSGI adapter accepts
`X-Real-IP` for rate-limit identity only when the direct peer is an explicitly
trusted IP address. The supplied configuration trusts loopback and nginx
replaces, rather than appends, the incoming forwarding headers.

## Files

- `server/comicollect_wsgi.py` builds the API lazily from validated environment
  configuration. Invalid configuration stops the Gunicorn worker.
- `server/comicollect_backend/wsgi.py` performs bounded WSGI request reads and
  trusted-proxy handling.
- `server/gunicorn.conf.py` fixes the deployment to one bounded `gthread`
  worker.
- `server/comicollect_backup.py` creates production generations and fully
  verifies a generation without opening the live application database.
- `server/comicollect_backend/backup.py` owns locking, capacity checks, copy,
  publication, and retention; `backup_verification.py` owns the strict on-disk
  format and offline verifier.
- `server/systemd/comicollect-production.service` is the hardened service
  template.
- `server/systemd/comicollect-production-check@.service` takes a pre-migration
  snapshot and validates a candidate release with the protected environment.
- `server/systemd/comicollect-production-backup.{service,timer}` schedules
  verified daily generations.
- `server/deploy/production-release.sh` stages, switches, verifies, rolls back,
  and prunes immutable releases.
- `server/deploy/nginx/comicollect.conf` is the TLS reverse-proxy template.
- `server/deploy/comicollect.production.env.example` documents non-secret
  configuration.
- `server/install-production.sh` installs the closed-beta profile without
  printing secrets or enabling the placeholder nginx configuration.

## Host preparation

Use a currently supported Linux distribution, Python 3.12 or newer, nginx, and
a real DNS name. Runtime files use this layout:

```text
/opt/comicollect/
├── current -> /opt/comicollect/releases/<release-id>
├── releases/<release-id>/{server,venv,docs}
└── tools/production-healthcheck.py
```

Each release and virtual environment is created fresh and remains root-owned.
The `comicollect` service account can read a release but cannot modify it.

`server/install.sh` is explicitly the legacy shared-token installer for a
trusted private LAN. It must not be used for a public service. The production
installer has a side-effect-free preflight which is safe to run without root
or secrets:

```bash
cd server
sh ./install-production.sh --dry-run
sudo ./install-production.sh
```

It generates the pepper directly in the protected configuration directory,
preserves an existing pepper and environment, stages a new root-owned release
and per-release virtual environment, and leaves nginx disabled until a real
hostname and certificate are configured. It never prints the pepper and
refuses to generate a replacement when an existing environment or auth
database indicates that the original secret was lost. A host-level deployment
lock rejects concurrent installer runs.

Before candidate code can migrate storage, the candidate check unit creates a
locked, verified pre-migration snapshot when an auth database exists. The old
worker remains active during that snapshot and candidate check. Only a
successful check can atomically replace the `current` symlink. The service's
`ExecStartPost` then verifies both loopback probes. A failed switch, start, or
startup probe restores the old symlink and unit files and restarts the old
release. The timer is paused during activation, and activation refuses to
continue while a backup oneshot is still running. Up to four successfully
activated versioned releases, including the
previous release, are retained; incomplete staging directories never displace
a rollback release. A one-time pre-versioned tree remains available after the
first migration until an operator removes it after a later verified rollout.

Schema migrations executed by `--check` must be additive and backward
compatible with the immediately previous release. This is mandatory because
the old worker remains live until activation and because a code rollback does
not reverse committed schema changes. A destructive or data-rewriting
migration requires an explicit maintenance-window migration and restore plan;
do not place one in normal startup code.

The only external runtime package is pinned to `gunicorn==26.0.0`. Dependency
updates should be reviewed and exercised in staging before changing that pin.

Generate the password pepper on the host. It must be random, must never enter
Git or logs, and must remain available for the lifetime of all password hashes
and sessions:

```bash
sudo openssl rand -out /etc/comicollect/password-pepper 48
sudo chown root:comicollect /etc/comicollect/password-pepper
sudo chmod 0440 /etc/comicollect/password-pepper
```

The installer initially copies `server/deploy/comicollect.production.env.example`
to `/etc/comicollect/production.env` with owner `root:comicollect` and mode
`0640`. The environment points to the pepper file; it does not contain the pepper.
The pepper is `root:comicollect` mode `0440`; startup rejects
owner/group-writable, executable, or world-accessible pepper files.
`COMICOLLECT_PUBLIC_REGISTRATION=false` is the safe default. Do not enable
unrestricted signup until email verification, password recovery, abuse
handling, and the privacy workflow are deployed.

The supplied units intentionally authorize only the documented `/var/lib` and
`/var/backups` paths. Changing a data or backup path also requires a reviewed
systemd override for both `ReadWritePaths` and `RequiresMountsFor`; changing the
port requires the matching nginx upstream change. An environment-only path
change is expected to fail inside the sandbox.

## Service installation

The installer installs the candidate check template, stages and checks the
release, atomically activates it, then installs/enables the current-release API
and backup units. Inspect the result with:

```bash
sudo systemctl status comicollect-production.service
sudo systemctl status comicollect-production-backup.timer
readlink -f /opt/comicollect/current
```

`ExecStartPre` validates the complete configuration, verifies the pepper
fingerprint, initializes storage, pings the auth repository, and checks tenant
writability plus the configured disk reserve before Gunicorn accepts traffic.
`ExecStartPost` refuses a successful start unless both HTTP probes pass.
The unit grants write access only to `/var/lib/comicollect` and its runtime
directory, removes Linux capabilities, and restricts network access to
loopback. `MemoryHigh=512M` begins memory pressure before the hard `768M`
ceiling; investigate sustained pressure rather than raising the limit blindly.

Validate the internal probes before adding nginx:

```bash
curl --fail --silent --show-error http://127.0.0.1:8787/health/live
curl --fail --silent --show-error http://127.0.0.1:8787/health/ready
```

Liveness only confirms that request routing works. Readiness also checks the
auth database and writable tenant storage. Neither endpoint exposes account
counts, server identifiers, or credentials.

## TLS reverse proxy

Replace every `api.comicollect.example` value in the nginx template. Provision
a valid certificate for the real hostname before enabling the TLS server, then
install the template inside nginx's `http` context:

```bash
sudo cp /opt/comicollect/current/server/deploy/nginx/comicollect.conf \
  /etc/nginx/conf.d/comicollect.conf
sudo nginx -t
sudo systemctl reload nginx
```

The template:

- redirects plaintext HTTP to HTTPS;
- permits TLS 1.2 and 1.3 and sends HSTS;
- buffers requests before the application;
- limits auth requests to 32 KiB, v1 sync to 1 MiB and v2 sync to 8 MiB;
- applies independent registration, auth, sync, connection limits;
- overwrites proxy identity headers and generates an `X-Request-ID`;
- exposes liveness but permits readiness only from the local host.

Open only ports `80` and `443` in the host and cloud firewalls. Confirm HTTPS
and certificate renewal before retaining HSTS; an expired or missing
certificate cannot be bypassed by clients after HSTS is cached.

## Operations

Follow service logs with:

```bash
journalctl -u comicollect-production.service -f
```

Gunicorn writes access and error logs to the journal. Both supplied access-log
formats record the normalized path but deliberately omit the query string.
nginx logs metadata but must never be configured to log request bodies or
authorization headers. Apply a documented short retention period to IP-address
logs. Correlate incidents with `X-Request-ID`; do not add tokens, passwords,
refresh payloads, or email addresses to routine log messages.

The production installer implements this deployment transaction:

1. run the complete server and Flutter test suites;
2. stage a fresh versioned release and per-release virtual environment;
3. take a verified backup before the candidate can run additive migrations;
4. run the candidate's real repository, storage, and reserve check;
5. atomically switch `current`, restart, and require both startup probes;
6. roll back code and units on failure and keep the previous release;
7. after success, verify login, refresh, and sync with a test account.

Use `systemctl reload comicollect-production` only for a tested code-only
change. A restart is clearer for configuration or schema changes.

## Backup and recovery

The production backup unit first opens the auth repository, validates the
configured pepper fingerprint, and constructs the same auth dependency graph
as the API. It refuses to create a missing auth database. The systemd unit is
the supported creation entry point because it supplies the protected
environment and mount dependencies. The timer runs it daily with a randomized
delay:

```bash
systemctl list-timers comicollect-production-backup.timer
sudo systemctl start comicollect-production-backup.service
journalctl -u comicollect-production-backup.service
```

Each run writes into a uniquely named `.partial` directory. Every copied
database must pass SQLite `PRAGMA quick_check`; `manifest.json` records its
relative path, byte size, and SHA-256. `completion.json` commits the exact
manifest digest. Only after all checks and fsyncs does the job atomically rename
the directory into a completed generation.

An exclusive process lock prevents the timer and a manual invocation from
running together. Before copying, the job estimates the source footprint and
requires that the destination retain `COMICOLLECT_BACKUP_RESERVE_BYTES` after
the new generation. The unit has `RequiresMountsFor` for both data and backup
paths, so a configured backup mount must be present. Prefer a separately
monitored backup volume; the reserve is a final safety boundary, not capacity
planning.

A failed run removes its partial generation. Before retention counts a
generation, it fully verifies the completion marker, manifest digest and
schema, exact database list and byte sizes, every SHA-256, and every SQLite
`PRAGMA quick_check`. Invalid or incomplete directories are ignored rather
than allowed to evict a known-good generation. A partial or invalid directory
must be investigated and removed only after confirming no backup process runs.

SQLite's online backup makes **each database file individually consistent**.
The files are copied sequentially, so the generation is not a global
point-in-time transaction across the auth database and every tenant database.
For a strict coordinated cut, enter maintenance, stop
the backup timer and `comicollect-production.service`, run the backup oneshot,
then start the API and timer again. Normal daily online backups favor
availability and retain this clearly documented cross-file boundary.

A local 14-generation rotation is only the first tier. Copy completed
generations to encrypted off-host object storage, verify the manifest after
transfer, alert on missed backups, and perform a documented restore drill at
least monthly.

Full verification needs no production secret and checks the completion marker,
manifest schema, exact database set, byte sizes, SHA-256 values, and SQLite
integrity:

```bash
sudo -u comicollect -- /bin/sh -c '
  cd /opt/comicollect/current/server
  exec ../venv/bin/python -m comicollect_backup verify "$1"
' comicollect-verify /var/backups/comicollect/<generation>
```

The pepper is not part of database snapshots. Keep an encrypted recovery copy
under separate access control. Losing it makes existing password hashes and
sessions unusable; replacing it casually is not a supported rotation process.

For a restore:

1. stop `comicollect-production-backup.timer`, then stop and confirm the backup
   oneshot is inactive;
2. stop `comicollect-production.service`;
3. run `comicollect_backup verify` on the selected local/off-host generation;
4. build a new sibling data directory on the same filesystem, containing both
   `accounts.sqlite3` and the complete `accounts/` directory, with no stale
   `-wal` or `-shm` files;
5. fsync the staged copy, atomically rename the current data directory to a
   preserved path, then atomically rename the staged directory into
   `/var/lib/comicollect`;
6. start the current release's `comicollect-production-check@.service` instance
   so the check receives the protected production environment;
7. start `comicollect-production.service`; its startup probe must succeed;
8. verify `/health/ready`, login, refresh, and sync with a test account;
9. start `comicollect-production-backup.timer` again and confirm its next run.

One concrete command sequence is:

```bash
set -eu
generation=${GENERATION:?export GENERATION as the selected absolute path}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
restore_stage=/var/lib/comicollect.restore-$stamp
preserved=/var/lib/comicollect.pre-restore-$stamp

sudo systemctl stop comicollect-production-backup.timer
sudo systemctl stop comicollect-production-backup.service
if systemctl is-active --quiet comicollect-production-backup.service; then
  echo "backup service is still active" >&2
  exit 1
fi
sudo systemctl stop comicollect-production.service
sudo -u comicollect -- /bin/sh -c '
  cd /opt/comicollect/current/server
  exec ../venv/bin/python -m comicollect_backup verify "$1"
' comicollect-verify "$generation"

test ! -e "$restore_stage"
test ! -e "$preserved"
sudo install -d -o comicollect -g comicollect -m 0750 "$restore_stage"
sudo install -d -o comicollect -g comicollect -m 0700 \
  "$restore_stage/accounts"
sudo install -o comicollect -g comicollect -m 0600 \
  "$generation/accounts.sqlite3" "$restore_stage/accounts.sqlite3"
sudo cp -a "$generation/accounts/." "$restore_stage/accounts/"
sudo chown -R comicollect:comicollect "$restore_stage"
sudo find "$restore_stage" -type f -exec chmod 0600 {} +
sudo chmod 0750 "$restore_stage"
sudo chmod 0700 "$restore_stage/accounts"
sudo sync

# Both source and destination are siblings on /var/lib, so each publication
# rename is atomic. Keep $preserved until the restore drill is accepted.
sudo mv -T /var/lib/comicollect "$preserved"
if ! sudo mv -T "$restore_stage" /var/lib/comicollect; then
  sudo mv -T "$preserved" /var/lib/comicollect
  exit 1
fi
sudo sync

release_id=$(basename "$(readlink -f /opt/comicollect/current)")
sudo systemctl start "comicollect-production-check@${release_id}.service"
sudo systemctl start comicollect-production.service
curl --fail --silent --show-error http://127.0.0.1:8787/health/ready
# Complete login, refresh, and sync smoke tests before re-enabling backups.
sudo systemctl start comicollect-production-backup.timer
```

Never restore only the auth database or only tenant databases. They form one
logical generation even though their individual snapshots were taken
sequentially. If the release check or smoke tests fail, keep services stopped,
move the failed restored directory aside, atomically move `$preserved` back to
`/var/lib/comicollect`, and repeat the release check before starting the API.

## Verification

Run the focused WSGI checks and then the full backend suite:

```bash
cd server
python3 -m unittest -v tests.test_wsgi
python3 -m unittest -v tests.test_tenant_store \
  tests.test_production_backup_cli tests.test_deployment_assets
python3 -m unittest discover -v
python3 -m unittest -v test_server.py
```

The WSGI tests cover bounded declared and chunked bodies, truncated input,
security headers, exact response length, proxy spoof resistance, and lazy
fail-closed construction.

## Required work before general availability or HA

The single-node profile is intentionally honest. General public availability
still requires:

- verified email ownership, password recovery, account export/deletion, and
  documented privacy retention;
- automated secret rotation which preserves or deliberately revokes sessions;
- encrypted off-host backups with monitored restore objectives;
- metrics, availability/error alerts, audit-event retention, load tests, and
  an independent security review;
- PostgreSQL migrations and a shared rate limiter before multiple workers or
  hosts, rolling deploys, or an uptime SLA;
- a managed TLS/DNS lifecycle and incident-response ownership.

Do not market this SQLite profile as horizontally scalable or highly
available. It is a secure deployment boundary for a monitored single-node
closed beta and a migration step toward the multi-node architecture above.
