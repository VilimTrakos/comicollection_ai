# Production accounts and backend authentication

Comicollect production mode provides real accounts and isolates every account
in its own existing Sync v2 `Store`. The sync protocol itself is not forked or
simplified: each tenant database has its own persistent `server_id`, contiguous
revision stream, mutation receipts, request cache and tombstones.

The authenticated account is derived exclusively from the bearer access token.
`account_id`, e-mail and other tenant selectors are deliberately absent from
sync request bodies. The client-controlled Sync v2 `device_id` is diagnostic
and is never an authorization boundary.

## Runtime modes

Production accounts are the default:

```sh
COMICOLLECT_PASSWORD_PEPPER_FILE=/run/secrets/comicollect-password-pepper \
COMICOLLECT_DATA_ROOT=/var/lib/comicollect \
COMICOLLECT_PUBLIC_REGISTRATION=true \
python3 server/comicollect_server.py
```

Startup fails when the password pepper is missing, shorter than 32 bytes, or
when configured scrypt parameters are below the accepted production floor.
The server binds to `127.0.0.1` by default. Put it behind a maintained TLS
reverse proxy, enforce an external request rate limit there and forward only
from trusted infrastructure. The bundled framework-free HTTP adapter is not a
TLS terminator.

The old single-user LAN deployment remains available only when selected
explicitly:

```sh
COMICOLLECT_MODE=legacy \
COMICOLLECT_TOKEN='at-least-32-characters-of-random-data' \
python3 server/comicollect_server.py
```

Existing installations must add `COMICOLLECT_MODE=legacy` before upgrading if
they are not ready to create production accounts. No global API token is read
in production mode.

## Required production configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `COMICOLLECT_PASSWORD_PEPPER_FILE` | none | Preferred root-owned secret file, at least 32 bytes |
| `COMICOLLECT_PASSWORD_PEPPER` | none | Inline alternative; configure exactly one pepper source |
| `COMICOLLECT_DATA_ROOT` | none | Required absolute parent for account metadata and tenant stores |
| `COMICOLLECT_AUTH_DB` | `<data>/accounts.sqlite3` | Account/session database |
| `COMICOLLECT_TENANT_ROOT` | `<data>/accounts` | Per-account Sync v2 databases |
| `COMICOLLECT_PUBLIC_REGISTRATION` | `false` | Enables public registration explicitly |
| `COMICOLLECT_HOST` | `127.0.0.1` | Backend bind address |
| `COMICOLLECT_PORT` | `8787` | Backend port |
| `COMICOLLECT_ACCESS_TTL_SECONDS` | `900` | Access-token lifetime |
| `COMICOLLECT_REFRESH_TTL_SECONDS` | `2592000` | Rotating refresh-token lifetime |
| `COMICOLLECT_SESSION_TTL_SECONDS` | `7776000` | Absolute session lifetime |
| `COMICOLLECT_TENANT_STORAGE_LIMIT_BYTES` | `536870912` | Maximum SQLite/WAL bytes per account before writes stop |
| `COMICOLLECT_DISK_RESERVE_BYTES` | `1073741824` | Minimum host free space retained before all sync writes stop |

The default scrypt work factor is `N=32768, r=8, p=3, dkLen=32`. It can be
raised with `COMICOLLECT_SCRYPT_N`, `_R`, `_P`, `_DKLEN` and `_MAXMEM`, but
production configuration rejects values below the supported OWASP-equivalent
cost combinations.

Passwords are never trimmed or normalized. E-mail addresses are NFKC
normalized, trimmed and case-folded. Each password receives a random salt and
is processed by stdlib `hashlib.scrypt` after an HMAC-SHA-256 pepper step.

## HTTP contract

All POST endpoints require `Content-Type: application/json`, reject unknown or
missing keys and reject non-standard JSON constants. Authentication bodies are
limited to 32 KiB, compatibility v1 sync to 1 MiB, and Sync v2 to 8 MiB.

### Register

`POST /api/v1/auth/register`

```json
{
  "email": "collector@example.com",
  "password": "a long private passphrase",
  "display_name": "Collector",
  "installation_id": "stable-installation-id"
}
```

Registration returns HTTP 201. It is unavailable unless public registration
was enabled explicitly.

### Login

`POST /api/v1/auth/login`

```json
{
  "email": "collector@example.com",
  "password": "a long private passphrase",
  "installation_id": "stable-installation-id"
}
```

Unknown accounts, wrong passwords and unavailable accounts all return the same
`invalid_credentials` response. The unknown-account path performs a real dummy
scrypt verification to reduce timing disclosure.

Register and login return:

```json
{
  "account": {
    "id": "account-uuid",
    "email": "collector@example.com",
    "display_name": "Collector",
    "email_verified": false
  },
  "access_token": "cca_...",
  "access_expires_at": 1784000000000,
  "refresh_token": "ccr_...",
  "refresh_expires_at": 1786500000000
}
```

Expiry values are Unix epoch **milliseconds**, matching Sync v2 timestamps.

### Refresh and logout

`POST /api/v1/auth/refresh` accepts exactly:

```json
{
  "refresh_token":"ccr_...",
  "installation_id":"stable-installation-id",
  "request_id":"stable-refresh-attempt-uuid"
}
```

Refresh tokens rotate once. The client persists one `request_id` for an
in-flight refresh. Retrying a consumed token with that same ID reconstructs and
returns the identical replacement pair, including after a backend restart.
Reuse with a different request ID is treated as credential replay and revokes
the complete session, including access and the replacement refresh token. The
app must serialize refresh attempts and persist the new credential pair before
clearing its pending request ID.

`POST /api/v1/auth/logout` requires the access bearer and an empty JSON object
(or an empty body). Logout is idempotent and revokes its session. `GET
/api/v1/account/me` returns the account bound to the access token.

Access and refresh tokens contain a random 256-bit nonce and a keyed 256-bit
authenticator. Only their binary SHA-256 digests and non-secret derivation
nonces are stored in SQLite. The password pepper is domain-separated into the
token derivation key, allowing an idempotent response to be reconstructed
without storing a raw token. Raw tokens, passwords and request bodies must
never be logged. The auth database pins a fingerprint of this derived key and
startup fails if the configured secret changes unexpectedly.

### Sync

`POST /api/v2/sync` keeps the exact documented Sync v2 request and response
contract. `POST /api/v1/sync` remains account-scoped for compatibility. Both
require a production access token; a token can access only its tenant store.

## Errors, health and headers

Expected failures have stable JSON fields:

```json
{"code":"invalid_credentials","error":"Email or password is incorrect","request_id":"uuid"}
```

Relevant auth codes include `registration_disabled`, `email_in_use`,
`password_policy_failed`, `invalid_credentials`, `invalid_token`,
`access_expired`, `invalid_refresh_token`, `refresh_expired`, `refresh_reused`,
`account_unavailable` and `rate_limited`.

Every response includes `Cache-Control: no-store`, `X-Content-Type-Options:
nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer` and an
`X-Request-ID`. A syntactically safe incoming request ID is echoed; otherwise a
new UUID is generated. HTTP 429 responses also include an integer
`Retry-After` duration in seconds.

Public health endpoints disclose no account counts or server identity:

- `GET /health/live` checks only process liveness.
- `GET /health/ready` verifies the auth database and tenant directory.

## Backup and operations

`python3 server/comicollect_server.py --backup` uses SQLite's online backup API
for the auth database and every tenant database, then retains fourteen backup
sets. Backups contain password hashes and active token digests and must be
encrypted off-host with restricted access. Restore drills must restore the
whole set, not one tenant file without its auth database.

The in-process bounded limiter is a second safety layer. A public service must
also rate-limit login, registration, refresh and body size at the TLS proxy.
The supplied WSGI/Gunicorn profile deliberately uses one worker; multiple
workers or hosts require PostgreSQL plus a shared limiter because an in-process
lock cannot coordinate separate processes. See
[`production-deployment.md`](production-deployment.md) for the supported
single-node topology and its explicit general-availability prerequisites.

Run the complete legacy Sync v2 and production-account regression suite with:

```sh
cd server
python3 -m unittest discover -v
```
