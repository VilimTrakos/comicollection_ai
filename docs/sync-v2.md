# Comicollect sync protocol v2

Sync v2 is the canonical, offline-first synchronization protocol for user data.
It deliberately separates transport ordering from device clocks and from the
packaged comic catalog.

## Invariants

- The server assigns every accepted atomic mutation one strictly increasing
  revision. A sync cursor is a server revision, never a timestamp.
- A local domain write and its durable outbox mutation commit in the same
  SQLite transaction.
- Mutation IDs are globally unique and idempotent. Reusing an ID with different
  content is a protocol conflict.
- One mutation may update several entities and is applied atomically. One log
  revision therefore never exposes half of a user action.
- A response page, its acknowledgements, downloaded changes and its cursor are
  applied in one local transaction. A crash can cause a safe replay, never a
  cursor gap.
- Device timestamps are retained only for diagnostics and the legacy UI. They
  never decide ordering or conflict winners in v2.
- Bundled catalog metadata and APK-local cover paths are not user sync data.

## Entities

| Wire entity | Stable identity | Purpose |
| --- | --- | --- |
| `custom_issue` | custom issue ID | User-created comic metadata |
| `collection_entry` | issue ID | Owned/wanted/read/rating/notes state |
| `copy` | copy UUID or migrated stable ID | One physical copy and its condition/value/loan |
| `barcode_mapping` | normalized barcode | User-learned barcode override and tombstone |

Copy `ordinal` controls presentation only. The copy ID is the distributed
identity, so two offline devices may create copies with the same ordinal
without overwriting each other.

Collection and copy payloads include a minimal, non-authoritative issue hint.
It lets an older APK display user state for a bundled issue absent from its
catalog. A later packaged catalog refresh remains authoritative.

After the initial full bootstrap, a local action uploads only entities whose
semantic data actually changed. Diagnostic `updated_at` and `issue_hint`
differences do not make an otherwise unchanged entity dirty. For example,
marking an issue as read does not resend its copies, so a newer condition edit
from another device cannot be overwritten accidentally.

The payload shapes are:

| Entity | `data` fields |
| --- | --- |
| `custom_issue` | `series`, `edition`, `number`, `title`; optional `publisher`, `year`, `page_count`, `writer`, `artist` |
| `collection_entry` | `issue_id`, `owned`, `is_wanted`, `is_read`, `is_duplicate`, `rating`, `notes`, `deleted`, `updated_at`, optional `issue_hint` |
| `copy` | `issue_id`, `ordinal`, `active`, `condition_grade`, `purchase_price`, `estimated_value`, `loaned_to`, `deleted`, `updated_at`, optional `issue_hint` |
| `barcode_mapping` | `issue_id`, `deleted`, `updated_at`, optional `issue_hint` |

An `issue_hint` contains `id`, `origin` (`bundled` or `custom`), `series`,
`edition`, `number`, `title`, `publisher` and `year`. Copy `issue_id` is
immutable for a given copy ID. Active, non-deleted copies are authoritative for
the derived collection fields `owned` and `is_duplicate`.

## Exchange

Authenticated clients call `POST /api/v2/sync`:

```json
{
  "protocol": 2,
  "request_id": "uuid",
  "device_id": "stable-installation-uuid",
  "server_id": "optional-pinned-server-id",
  "cursor": 127,
  "limit": 100,
  "mutations": [
    {
      "mutation_id": "uuid",
      "created_at": 1784100000000,
      "changes": [
        {
          "entity_type": "custom_issue",
          "entity_id": "issue-uuid",
          "operation": "upsert",
          "data": {
            "series": "Dylan Dog",
            "edition": "Privatno izdanje",
            "number": 1,
            "title": "Naslov",
            "publisher": "",
            "year": null,
            "page_count": null,
            "writer": "",
            "artist": ""
          }
        }
      ]
    }
  ]
}
```

The response contains the persistent server identity, acknowledgements and
whole atomic change groups in revision order:

```json
{
  "protocol": 2,
  "server_id": "persistent-server-uuid",
  "request_id": "uuid",
  "server_time": 1784100000123,
  "next_cursor": 128,
  "has_more": false,
  "acknowledgements": [
    {"mutation_id": "uuid", "revision": 128, "status": "applied"}
  ],
  "change_groups": [
    {
      "revision": 128,
      "mutation_id": "uuid",
      "changes": [
        {
          "entity_type": "custom_issue",
          "entity_id": "issue-uuid",
          "operation": "upsert",
          "data": {
            "series": "Dylan Dog",
            "edition": "Privatno izdanje",
            "number": 1,
            "title": "Naslov",
            "publisher": "",
            "year": null,
            "page_count": null,
            "writer": "",
            "artist": "",
            "deleted": false
          }
        }
      ]
    }
  ]
}
```

`next_cursor` is the last delivered revision. When `has_more` is true, the
client immediately requests another page. Acknowledged outbox records remain
durable until the local cursor reaches their revision, which makes a lost HTTP
response and an app crash after server commit safe.

An acknowledgement is also bound to the `mutation_id` of the change group at
its revision. It may point beyond the current page only while `has_more` is
true. The client persists that expectation and rejects a later mismatched group
or a final page ending below an acknowledged revision, so an acknowledgement
can never silently discard another mutation.

Change groups are contiguous: the first response revision is `cursor + 1`,
every following revision increments by one, and the last equals
`next_cursor`. A cursor never advances without the corresponding groups, and
`has_more: true` never accompanies an empty page. Clients reject a response
that violates any of these rules instead of risking a silent data gap.

### Protocol limits

Limits are enforced independently by the Flutter client and the server before
any state is committed:

| Boundary | Limit |
| --- | ---: |
| Encoded request body | 8 MiB |
| Mutations per request | 100 |
| Uploaded changes per mutation | 500 |
| Uploaded changes per request | 500 |
| Requested/downloaded groups per page | 100 |
| One canonical atomic change group | 5 MiB |
| Encoded response page | 6 MiB |

The server may append a derived `collection_entry` snapshot when a copy
changes, so the canonical downloaded group can contain more items than the
uploaded mutation. It still remains atomic and must fit the 5 MiB group and
6 MiB response limits. Client connect and response timeouts are five and ten
seconds. A large history is consumed in bounded passes and automatically
continues instead of blocking the UI indefinitely.

Mutation receipts and revision history are durable. Exact request responses
are a retry optimization rather than the source of truth: the LAN server keeps
at most 1,000 responses, seven days and 32 MiB. A retry after cache eviction is
still safe because the permanent mutation receipt returns `duplicate` for an
already committed mutation.

### Stable errors

Errors are JSON objects with `error` and, for v2, a stable `code`. The client
maps these codes to actionable Croatian UI messages while keeping the outbox
intact.

| HTTP | Codes | Meaning |
| ---: | --- | --- |
| 400 | `invalid_request` | Malformed JSON or a field outside the contract |
| 401/403 | — | Missing or invalid bearer token |
| 409 | `server_mismatch`, `cursor_invalid` | Wrong server identity or a server restored behind the client cursor |
| 409 | `request_id_reused`, `mutation_id_reused` | An idempotency ID was reused with different content |
| 409 | `v1_read_only` | A legacy client attempted to write after v2 activation |
| 413 | `request_too_large`, `mutation_too_large`, `change_group_too_large` | A configured byte limit was exceeded |
| 415 | `unsupported_media_type` | v2 was called without JSON content type |

## Conflict and deletion policy

Atomic mutations are serialized by server revision. Changes to different
entities merge independently; for concurrent changes to the same entity, the
later accepted server mutation becomes canonical. Device clock skew has no
effect.

Deletes are synchronized tombstones rather than physical removal. Copy,
collection and barcode tombstones are retained so an offline device cannot
silently resurrect deleted state. Explicit later upserts can intentionally
restore an entity and receive a new revision.

Collection deletion follows observed-remove/add-wins semantics across its
physical copies. A deletion succeeds when the same mutation has removed every
copy observed by the server. If another device created an active copy which
the deleting device had not seen, that independent copy survives: the server
acknowledges the mutation and returns a canonical `collection_entry` upsert on
the same revision. Its server-side read/rating/notes values are preserved and
its owned/duplicate flags are recomputed from all active copies. This avoids
both surprise loss of a concurrent physical-copy record and a permanently
retrying outbox item. Once the client has observed and explicitly removed the
remaining copy, a later collection deletion becomes the canonical tombstone.
When one collection has more copies than fit in a mutation, the client sends
all copy tombstones first and the aggregate `collection_entry` tombstone last.
This preserves the same observed-remove rule across protocol-sized chunks.

## Compatibility rollout

The server keeps `/api/v1/sync` and imports its existing flat `comics` rows into
the v2 event log once. A new client tries v2 first and falls back to v1 only
when the server genuinely does not implement v2 and no v2 server identity has
ever been pinned locally.

The first v2 baseline and every continuation page are pull-only. With a
confirmed v1 cursor, only state newer than that cursor and v2-only data are
protected while the baseline is applied, so newer server state wins over clean
legacy rows. A cursor-zero installation or an explicit server rebind stages a
complete local snapshot before the pull so a fresh server cannot erase the
only copy of the collection. Upload begins only after the final baseline page.

Fallback itself is crash-safe. Before a v1 request, SQLite stores a durable
pending marker, the legacy cursor and the outbox high-water included in that
request. Completion merges the response, rebases only that confirmed prefix
and stores the new legacy cursor in one SQLite transaction. Writes made while
HTTP is in flight receive a later sequence and remain pending. After restart,
the client finishes v1 recovery before probing v2, and a lagging preferences
cursor cannot roll back SQLite. If another device activated v2 in the meantime,
the server accepts exact/already-older v1 retries only as no-ops; a rejected
newer retry is atomically promoted to v2 without deleting its outbox.

After v2 activation, v1 payloads which could change state are rejected with
HTTP 409. Exact or older crash retries are accepted strictly as no-ops. This is
an intentional safety boundary: a flattened v1 record cannot represent three
physical copies or their independent prices and loans. Old clients can still
pull the compatibility projection while they are being upgraded.

The persistent `server_id` prevents an address typo or a fresh server database
from silently mixing unrelated histories. Moving deliberately to another
server requires the confirmed **Poveži drugi ili novi server** action in app
settings. It preserves all collection rows and the stable device ID, clears
both v1/v2 server cursors, then creates a fresh v2 snapshot for the selected
server.

The v5-to-v6 migration normalizes historical values to strict wire bounds in
the schema transaction. Original JSON and a reason remain in
`sync_quarantine`; invalid identifiers are not uploaded, and sync reports how
many migrated records require review instead of claiming silent full success.

The current self-hosted server has one account selected by its bearer token.
A future public multi-tenant service must derive an account scope from its
authenticated identity and include that scope in every state/log key; clients
must never choose another account in the payload.

The bundled deployment profile is for a trusted private LAN and must not be
published directly on the internet. A public/store production service also
requires TLS for all collection traffic and Android Keystore/iOS Keychain
storage for credentials; the current injectable token-store boundary exists so
that upgrade does not change sync logic.
