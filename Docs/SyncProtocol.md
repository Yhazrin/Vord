# Vord sync protocol 1

Local-first SQLite clients exchange records through an authenticated HTTPS server. The service endpoint is `https://yhazrin.xyz/vord-sync`; clients POST to endpoint + `/v1/sync`. No AI credentials travel with this data.

## Request

```
{"protocolVersion":1,"deviceID":"UPPERCASE-UUID","cursor":0,"changes":[
  {"kind":"entry","id":"UPPERCASE-UUID","clock":1,"deviceID":"UPPERCASE-UUID","deleted":false,"payload":{ /* VocabularyEntry */ },"changedFields":["english","chinese"]},
  {"kind":"direction","id":"ENTRY-UUID/englishToChinese","clock":2,"deviceID":"UPPERCASE-UUID","deleted":false,"payload":{"entryID":"ENTRY-UUID","state":{ /* ReviewDirectionState */ }}},
  {"kind":"log","id":"LOG-UUID","clock":3,"deviceID":"UPPERCASE-UUID","deleted":false,"payload":{ /* ReviewLog */ }}
]}
```

`Authorization: Bearer <sync token>` identifies a private workspace. Uppercase UUIDs, camelCase model fields, ISO8601 UTC dates with milliseconds, enum strings matching existing models, signed 64-bit positive Lamport clocks. Missing optional model fields are accepted as null; records returned by the server include model-compatible payloads. `direction.id` has uppercase entry UUID, slash, direction enum. ProtocolVersion and library export schemaVersion are separate from local SQLite migration version.

## Response

```
{"protocolVersion":1,"cursor":42,"hasMore":false,"changes":[ /* record envelopes as above, plus seq */ ],"acknowledged":[{"kind":"entry","id":"ORIGINAL-SENT-ID","clock":1,"deviceID":"SENT-DEVICE-ID"}],"aliases":{"OLD-ENTRY-UUID":"CANONICAL-ENTRY-UUID"}}
```

Acknowledgements use original request IDs so pending generations can be cleared precisely. Envelopes include `kind,id,clock,deviceID,deleted,payload`; deleted payload may be null. Responses include up to 500 journal changes ordered by seq. Cursor is the last returned seq (or current journal max if none); hasMore means another request at that cursor is needed. Requests cap at 200 changes, 4 MiB. Every valid request commits atomically, including acknowledgements and incoming changes. Errors never advance client cursor. Invalid/orphan records return 400 and roll back the entire batch. Authentication errors return 401. Future cursor returns 409. `GET /health` returns no user data.

## Merge and delete

Clients persist a monotonically increasing Lamport counter, device UUID, outbox, server cursor and last remote payload baselines in their library SQLite DB. Local writes and dirty generations are captured in one DB transaction. Clocks advance above all clocks observed remotely. Server compares (clock, deviceID), independent of device wall clocks.

An entry is merged per field. `changedFields` lists only fields different from the client's last remote baseline (all model fields except id for first upload). Server applies only those fields whose incoming stamp wins that field's stored stamp; unmodified fields are preserved. `createdAt` keeps earliest value, `updatedAt` keeps latest value; metadata cannot silently erase another device's meaning/tag change. Same-field concurrent edits use deterministic stamp order; server journal/history preserves accepted revisions. Entries cannot be empty. `direction` is a whole-record winner for that direction only, so practicing opposite directions never overwrites each other. Logs are immutable and deduplicated by UUID; a differing payload for an existing log is rejected. Server retains tombstones permanently: any entry deletion wins over edits/retries, and its states/logs are no longer projected. Explicit re-add uses a new entry UUID.

Same English headword (trimmed, case-insensitive) added independently on two devices converges on the existing server entry UUID. Server records a permanent alias for the other UUID; payload references and direction IDs are canonicalized. Aliases returned in every response let clients consolidate rows and transfer local review states/logs/outbox to the canonical ID before applying remote records. A deleted entry does not block a fresh UUID for a later explicit re-add. Alias and record processing are in one transaction.

## Client application

Capture pending envelopes and generation clocks before the HTTP call. On response, clear only generations whose kind/id/clock/deviceID exactly match acknowledged sent records (remap aliases consistently). Apply aliases and remote changes transactionally. A newer or unsent local mutation must remain queued: preserve its locally changed fields over remote entry values, preserve whole pending direction values, then update the baseline to the remote payload. Deleted entries always delete local rows and clear dependent pending changes, regardless of unsent edits. Remote writes must not generate local outbox events. Only after this transaction succeeds persist the returned cursor. Drain pending batches and hasMore pages with a bounded loop; trigger another pass when dirty changes arrive during a run.

The UI offers endpoint, secret sync code, connect/disconnect, sync now, status and last successful time. macOS code belongs in Keychain; Android encrypts it with Android Keystore. Sync on connect, on app foreground, periodically while running, and shortly after local writes; offline errors leave the outbox intact without interrupting study. Disconnect preserves local library. Credentials are never written to source control or logs. Tokens are provisioned privately, one token/workspace, with no unauthenticated public registration.

Committed local writes schedule an immediate exchange. Foreground clients poll every 3 seconds; Mac additionally checks the local outbox revision every second for commits from another process, and polls every 60 seconds when in the background. Android's background fallback uses network-constrained WorkManager with a 15-minute minimum interval, subject to OS scheduling. Android retry backoff waits independently of the request queue, so a new write or foreground trigger is not blocked by a previous failure. Remote-only Mac UI notifications are marked with origin `sync` to avoid scheduling another exchange merely to redraw the library.
