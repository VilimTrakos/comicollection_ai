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
- `server/systemd/comicollect-production.service` is the hardened service
  template.
- `server/systemd/comicollect-production-check.service` validates a newly
  installed release with the real protected environment before restart.
- `server/systemd/comicollect-production-backup.{service,timer}` schedules
  verified daily generations.
- `server/deploy/nginx/comicollect.conf` is the TLS reverse-proxy template.
- `server/deploy/comicollect.production.env.example` documents non-secret
  configuration.
- `server/install-production.sh` installs the closed-beta profile without
  printing secrets or enabling the placeholder nginx configuration.

## Host preparation

Use a currently supported Linux distribution, Python 3.12 or newer, nginx, and
a real DNS name. The examples assume the repository is installed at
`/opt/comicollect`.

`server/install.sh` is explicitly the legacy shared-token installer for a
trusted private LAN. It must not be used for a public service. The production
installer has a side-effect-free preflight which is safe to run without root
or secrets:

```bash
cd server
sh ./install-production.sh --dry-run
sudo ./install-production.sh
```

It generates the pepper directly into the protected configuration directory,
preserves an existing pepper and environment, installs the pinned runtime,
starts only the loopback API and backup timer, and leaves nginx disabled until
a real hostname and certificate are configured. On upgrade it runs the
isolated configuration/storage check first and restarts the API explicitly
only after that check succeeds. It never prints the pepper.

The equivalent manual setup follows for operators who manage releases with
their own automation.

Create the service account and Python environment:

```bash
sudo useradd --system --home-dir /var/lib/comicollect \
  --shell /usr/sbin/nologin comicollect
sudo install -d -o root -g root -m 0755 /opt/comicollect
sudo install -d -o root -g comicollect -m 0750 /etc/comicollect
sudo python3 -m venv /opt/comicollect/venv
sudo /opt/comicollect/venv/bin/pip install \
  -r /opt/comicollect/server/requirements-production.txt
```

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

Copy the environment example and keep it root-controlled:

```bash
sudo cp /opt/comicollect/server/deploy/comicollect.production.env.example \
  /etc/comicollect/production.env
sudo chown root:comicollect /etc/comicollect/production.env
sudo chmod 0640 /etc/comicollect/production.env
```

The environment points to the pepper file; it does not contain the pepper.
`COMICOLLECT_PUBLIC_REGISTRATION=false` is the safe default. Do not enable
unrestricted signup until email verification, password recovery, abuse
handling, and the privacy workflow are deployed.

## Service installation

Install and start the unit:

```bash
sudo cp /opt/comicollect/server/systemd/comicollect-production.service \
  /etc/systemd/system/
sudo cp /opt/comicollect/server/systemd/comicollect-production-check.service \
  /etc/systemd/system/
sudo cp /opt/comicollect/server/systemd/comicollect-production-backup.service \
  /etc/systemd/system/
sudo cp /opt/comicollect/server/systemd/comicollect-production-backup.timer \
  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start comicollect-production-check.service
sudo systemctl enable \
  comicollect-production.service comicollect-production-backup.timer
sudo systemctl restart comicollect-production.service
sudo systemctl start comicollect-production-backup.timer
sudo systemctl status comicollect-production.service
```

`ExecStartPre` validates the complete configuration, verifies the pepper
fingerprint, and initializes storage before Gunicorn starts accepting traffic.
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
sudo cp /opt/comicollect/server/deploy/nginx/comicollect.conf \
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

Before every deployment:

1. run the complete server and Flutter test suites;
2. create and verify a database backup;
3. install the new code into a versioned release directory;
4. run `python -m comicollect_wsgi --check` using the production environment;
5. restart the service and verify both probes plus one test account sync;
6. retain the previous release until the smoke test passes.

Use `systemctl reload comicollect-production` only for a tested code-only
change. A restart is clearer for configuration or schema changes.

## Backup and recovery

The production backup command first opens the auth repository, validates the
configured pepper fingerprint, and constructs the same auth dependency graph
as the API. It refuses to create a missing auth database. It then creates one
verified generation containing the auth database and every account database:

```bash
/opt/comicollect/venv/bin/python \
  /opt/comicollect/server/comicollect_server.py \
  --mode production --backup --backup-dir /var/backups/comicollect
```

Run it from a dedicated systemd oneshot unit with the same `EnvironmentFile`
as the API. The supplied timer does this daily with a randomized delay:

```bash
systemctl list-timers comicollect-production-backup.timer
sudo systemctl start comicollect-production-backup.service
journalctl -u comicollect-production-backup.service
```

Each run writes into a uniquely named `.partial` directory. Every copied
database must pass SQLite `PRAGMA quick_check`; `manifest.json` records its
relative path, byte size, and SHA-256. Only after all checks and an fsync does
the job atomically rename the directory into a completed generation. A failed
run removes its partial directory, and retention considers only completed
directories with a manifest. A partial directory left by a power loss is never
treated as a backup; remove it only after confirming no backup process runs.

SQLite's online backup makes **each database file individually consistent**.
The files are copied sequentially, so the generation is not a global
point-in-time transaction across the auth database and every tenant database.
For a strict coordinated cut, enter maintenance, stop
`comicollect-production.service`, run the backup oneshot, and start the API
again. Normal daily online backups favor availability and retain this clearly
documented cross-file boundary.

A local 14-generation rotation is only the first tier. Copy completed
generations to encrypted off-host object storage, verify the manifest after
transfer, alert on missed backups, and perform a documented restore drill at
least monthly.

The pepper is not part of database snapshots. Keep an encrypted recovery copy
under separate access control. Losing it makes existing password hashes and
sessions unusable; replacing it casually is not a supported rotation process.

For a restore:

1. stop `comicollect-production.service`;
2. preserve the current `/var/lib/comicollect` directory for investigation;
3. verify `PRAGMA quick_check` on `accounts.sqlite3` and every tenant database
   in the chosen snapshot;
4. restore both `accounts.sqlite3` and the complete `accounts/` directory as
   one snapshot, with owner `comicollect` and mode `0750`/`0600`;
5. run the configuration check and readiness probe;
6. start the service and verify login, refresh, and sync with a test account.

Never restore only the auth database or only tenant databases. They form one
logical generation even though their individual snapshots were taken
sequentially.

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
