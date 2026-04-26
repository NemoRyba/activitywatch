# Fleet Offline Sync Spec

This document defines the exact V1 sync mechanism for endpoint machines that can go offline and later reconnect to a central ActivityWatch server.


## 1. Decision

V1 will use:

- a **local `aw-server` on every endpoint machine**
- existing watchers writing to **localhost only**
- a new **`aw-agent-windows`** process that:
  - scans the local `aw-server` data
  - converts mutable local events into an immutable sync outbox
  - uploads outbox batches to the central server
  - resumes safely after network failures or agent crashes

This is intentionally **not** a direct watcher-to-central transport queue.

Reason:

- local `aw-server` already handles heartbeat merging and durable local storage
- watchers do not need to know whether the central network is up
- reconnect sync becomes explicit and idempotent
- we avoid replaying raw heartbeat requests to central


## 2. Non-Goals

V1 does **not** do:

- peer-to-peer sync
- cross-central replication
- central-to-endpoint downsync
- distributed conflict resolution between two writers for the same stream

V1 assumes:

- one endpoint machine owns one local stream
- central is the only aggregation target
- streams are append-mostly, with only the latest local event being mutable due to heartbeat merge


## 3. Exact Architecture

### Endpoint

Processes:

- `aw-server` bound to `127.0.0.1`
- `aw-watcher-window`
- `aw-watcher-afk`
- `aw-watcher-session`
- `aw-agent-windows`

Write path:

```text
watchers -> local aw-server -> local aw-server sqlite db
                                |
                                v
                         aw-agent-windows scan
                                |
                                v
                         local sync outbox sqlite db
                                |
                                v
                    HTTPS upload to central aw-server
```

### Central

Processes:

- central `aw-server`
- fleet sync ingestion module inside `aw-server`

Write path:

```text
sync batch -> fleet sync ingest -> central bucket upsert / event insert-replace
                                 -> central sync metadata db
```


## 4. Identity Model

### Stable IDs

Endpoint machine:

- `agent_id`: stable UUID persisted once per endpoint
- `device_id`: stable device identity used by fleet views

Stream:

- one stream per bucket on the endpoint
- `stream_id = "{agent_id}:{bucket_id}"`

Source event:

- one local `aw-server` event row inside a stream
- `source_event_id = local aw-server event.id`

Source event key:

- `source_event_key = "{stream_id}:{source_event_id}"`

### Why not timestamps as the resume key?

Because timestamps are not strong enough:

- equal timestamps happen
- the latest heartbeat-merged event changes duration over time
- reconnect resume must be exact across crashes

Resume and dedup will therefore use:

- immutable outbox sequence numbers for transport
- `source_event_key` plus `source_event_version` for event replacement


## 5. Endpoint Local Storage

Endpoint already has the local `aw-server` datastore.

Add a second SQLite database owned by `aw-agent-windows`:

- path: `%PROGRAMDATA%\\ActivityWatch\\aw-fleet-sync.v1.db`

### Table: `agents`

```sql
CREATE TABLE agents (
    agent_id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    hostname TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

Purpose:

- stores stable endpoint identity

### Table: `streams`

```sql
CREATE TABLE streams (
    stream_id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    bucket_id TEXT NOT NULL,
    bucket_type TEXT NOT NULL,
    device_id TEXT NOT NULL,
    username TEXT,
    session_id TEXT,
    bucket_metadata_json TEXT NOT NULL,
    next_seq INTEGER NOT NULL,
    last_scan_at TEXT,
    last_local_event_id INTEGER,
    last_local_event_checksum TEXT,
    last_acked_seq INTEGER NOT NULL DEFAULT 0,
    last_sync_attempt_at TEXT,
    last_sync_success_at TEXT,
    FOREIGN KEY (agent_id) REFERENCES agents(agent_id)
);

CREATE UNIQUE INDEX idx_streams_bucket_id ON streams(bucket_id);
```

Purpose:

- defines each outbound sync stream
- tracks its monotonic outbox sequence number
- tracks sync progress

### Table: `source_event_state`

```sql
CREATE TABLE source_event_state (
    stream_id TEXT NOT NULL,
    source_event_id INTEGER NOT NULL,
    source_event_version INTEGER NOT NULL,
    event_checksum TEXT NOT NULL,
    last_emitted_seq INTEGER NOT NULL,
    is_final INTEGER NOT NULL DEFAULT 0,
    first_seen_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    PRIMARY KEY (stream_id, source_event_id),
    FOREIGN KEY (stream_id) REFERENCES streams(stream_id)
);
```

Purpose:

- remembers which local source events have already been exported
- detects when the latest event changed and therefore needs a new `event_upsert`

### Table: `outbox_ops`

```sql
CREATE TABLE outbox_ops (
    stream_id TEXT NOT NULL,
    seq INTEGER NOT NULL,
    op_type TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    payload_checksum TEXT NOT NULL,
    created_at TEXT NOT NULL,
    acked_at TEXT,
    PRIMARY KEY (stream_id, seq),
    FOREIGN KEY (stream_id) REFERENCES streams(stream_id)
);

CREATE INDEX idx_outbox_unacked ON outbox_ops(stream_id, acked_at, seq);
```

Allowed `op_type` values:

- `bucket_upsert`
- `event_upsert`

Purpose:

- immutable transport log
- anything not acked remains eligible for resend


## 6. Central Storage

Add a second SQLite database on the central server:

- path: `aw-server/fleet-sync.v1.db`

This stores sync metadata only. Actual user-facing activity data still ends up in the normal central `aw-server` datastore.

### Table: `sync_streams`

```sql
CREATE TABLE sync_streams (
    stream_id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    hostname TEXT NOT NULL,
    bucket_id TEXT NOT NULL,
    bucket_type TEXT NOT NULL,
    central_bucket_id TEXT NOT NULL,
    bucket_metadata_json TEXT NOT NULL,
    last_acked_seq INTEGER NOT NULL DEFAULT 0,
    last_received_at TEXT,
    updated_at TEXT NOT NULL
);
```

Purpose:

- stream registry
- authoritative cursor per stream
- mapping from remote bucket to central bucket

### Table: `sync_event_map`

```sql
CREATE TABLE sync_event_map (
    stream_id TEXT NOT NULL,
    source_event_id INTEGER NOT NULL,
    source_event_version INTEGER NOT NULL,
    central_bucket_id TEXT NOT NULL,
    central_event_id INTEGER NOT NULL,
    event_checksum TEXT NOT NULL,
    last_seq INTEGER NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (stream_id, source_event_id)
);
```

Purpose:

- maps remote source events to central datastore event IDs
- allows idempotent upsert and replacement of the latest event when it changes locally


## 7. Central Bucket Naming

Central bucket IDs remain the fleet bucket IDs already introduced:

```text
aw-watcher-window__{device_id}__{username}__{session_id}
aw-watcher-afk__{device_id}__{username}__{session_id}
aw-watcher-session__{device_id}__{username}__{session_id}
```

Central stream metadata stores:

- original remote `bucket_id`
- `central_bucket_id`

This keeps the central data directly usable by existing fleet reducers.


## 8. Outbox Operation Shapes

### `bucket_upsert`

```json
{
  "bucket_id": "aw-watcher-window__Mareks-Lenovo__Stepik__1",
  "bucket_type": "currentwindow",
  "bucket_metadata": {
    "username": "Stepik",
    "device_id": "Mareks-Lenovo",
    "device_name": "Mareks-Lenovo",
    "session_id": "1",
    "session_type": "console",
    "hostname": "Mareks-Lenovo",
    "source": "aw-central-v1"
  }
}
```

### `event_upsert`

```json
{
  "source_event_id": 9211,
  "source_event_version": 2,
  "timestamp": "2026-04-17T08:10:00Z",
  "duration": 45.0,
  "data": {
    "app": "Code.exe",
    "title": "main.py - Visual Studio Code",
    "username": "Stepik",
    "device_id": "Mareks-Lenovo",
    "session_id": "1"
  }
}
```

Notes:

- `source_event_version` increments whenever the local source event changes checksum
- for ordinary finalized events the version is usually `1`
- for the active mutable tail event, version may advance multiple times before the stream moves on


## 9. Endpoint Scan Algorithm

`aw-agent-windows` runs a scan loop every few seconds.

### Input

For each local bucket:

- local bucket metadata from local `aw-server`
- local events from local `aw-server`, including `event.id`

### Step-by-step

1. Discover or create a `streams` row for each local bucket of interest.
2. If bucket metadata changed, emit a `bucket_upsert`.
3. Read events for the bucket ordered by `event.id ASC`.
4. For each event:
   - compute checksum over:
     - `timestamp`
     - `duration`
     - canonical JSON of `data`
   - look up `(stream_id, source_event_id)` in `source_event_state`
5. If source event does not exist in `source_event_state`:
   - create `source_event_version = 1`
   - emit `event_upsert`
   - store checksum and emitted seq
6. If source event exists and checksum changed:
   - increment `source_event_version`
   - emit `event_upsert`
   - update checksum and emitted seq
7. Mark all source events except the latest one in the bucket as `is_final = 1`.
8. Update `streams.last_local_event_id`, `streams.last_local_event_checksum`, `streams.last_scan_at`.

### Important consequence

This turns the local mutable event model into an immutable sync transport:

- the outbox never edits old rows
- a changed local event becomes a new `event_upsert` with a higher `source_event_version`


## 10. Endpoint Sync Algorithm

### Trigger

Sync loop runs continuously with backoff:

- immediate when online and there is unacked outbox data
- slower when offline or idle

### Handshake

Agent calls:

- `POST /api/0/fleet/sync/handshake`

Purpose:

- register agent identity
- register streams and bucket metadata
- obtain central `last_acked_seq` per stream

### Upload

For each stream:

1. Read `last_acked_seq` from central handshake response.
2. Read unacked `outbox_ops` with `seq > last_acked_seq`, ordered by `seq`.
3. Split into batches:
   - max `500` ops, or
   - max `1 MiB` JSON payload
4. `POST /api/0/fleet/sync/batch`
5. If acknowledged:
   - mark all rows `<= acked_through_seq` as `acked_at = now`
   - update `streams.last_acked_seq`
6. Repeat until caught up.


## 11. Sync API

### `POST /api/0/fleet/sync/handshake`

Request:

```json
{
  "protocol_version": 1,
  "agent": {
    "agent_id": "f3cf0f0a-6f44-4b47-8f50-a6f2b6cc9327",
    "device_id": "Mareks-Lenovo",
    "device_name": "Mareks-Lenovo",
    "hostname": "Mareks-Lenovo"
  },
  "streams": [
    {
      "stream_id": "f3cf0f0a-6f44-4b47-8f50-a6f2b6cc9327:aw-watcher-window__Mareks-Lenovo__Stepik__1",
      "bucket_id": "aw-watcher-window__Mareks-Lenovo__Stepik__1",
      "bucket_type": "currentwindow",
      "bucket_metadata": {
        "username": "Stepik",
        "device_id": "Mareks-Lenovo",
        "device_name": "Mareks-Lenovo",
        "session_id": "1",
        "session_type": "console"
      },
      "next_seq": 3812
    }
  ]
}
```

Response:

```json
{
  "protocol_version": 1,
  "server_time": "2026-04-17T08:15:00Z",
  "streams": [
    {
      "stream_id": "f3cf0f0a-6f44-4b47-8f50-a6f2b6cc9327:aw-watcher-window__Mareks-Lenovo__Stepik__1",
      "central_bucket_id": "aw-watcher-window__Mareks-Lenovo__Stepik__1",
      "last_acked_seq": 3721
    }
  ]
}
```

### `POST /api/0/fleet/sync/batch`

Request:

```json
{
  "protocol_version": 1,
  "agent_id": "f3cf0f0a-6f44-4b47-8f50-a6f2b6cc9327",
  "stream_id": "f3cf0f0a-6f44-4b47-8f50-a6f2b6cc9327:aw-watcher-window__Mareks-Lenovo__Stepik__1",
  "from_seq": 3722,
  "to_seq": 3724,
  "ops": [
    {
      "seq": 3722,
      "op_type": "bucket_upsert",
      "payload": {
        "bucket_id": "aw-watcher-window__Mareks-Lenovo__Stepik__1",
        "bucket_type": "currentwindow",
        "bucket_metadata": {
          "username": "Stepik",
          "device_id": "Mareks-Lenovo",
          "device_name": "Mareks-Lenovo",
          "session_id": "1",
          "session_type": "console"
        }
      }
    },
    {
      "seq": 3723,
      "op_type": "event_upsert",
      "payload": {
        "source_event_id": 9210,
        "source_event_version": 1,
        "timestamp": "2026-04-17T08:10:00Z",
        "duration": 32.0,
        "data": {
          "app": "Code.exe",
          "title": "main.py - Visual Studio Code",
          "username": "Stepik",
          "device_id": "Mareks-Lenovo",
          "session_id": "1"
        }
      }
    },
    {
      "seq": 3724,
      "op_type": "event_upsert",
      "payload": {
        "source_event_id": 9211,
        "source_event_version": 3,
        "timestamp": "2026-04-17T08:10:32Z",
        "duration": 15.0,
        "data": {
          "app": "Code.exe",
          "title": "main.py - Visual Studio Code",
          "username": "Stepik",
          "device_id": "Mareks-Lenovo",
          "session_id": "1"
        }
      }
    }
  ]
}
```

Response:

```json
{
  "stream_id": "f3cf0f0a-6f44-4b47-8f50-a6f2b6cc9327:aw-watcher-window__Mareks-Lenovo__Stepik__1",
  "acked_through_seq": 3724,
  "applied_ops": 3,
  "replaced_events": 1,
  "deduplicated_ops": 0,
  "central_bucket_id": "aw-watcher-window__Mareks-Lenovo__Stepik__1"
}
```


## 12. Central Apply Rules

Each batch is processed inside **one transaction**.

### Batch validation

Reject with `400` if:

- protocol version unsupported
- `from_seq > to_seq`
- sequence numbers not strictly increasing
- required fields missing

Reject with `409` if:

- `from_seq != last_acked_seq + 1`

Response for `409`:

```json
{
  "stream_id": "...",
  "need_resync_from_seq": 3722,
  "last_acked_seq": 3721
}
```

### Apply `bucket_upsert`

1. Ensure stream row exists in `sync_streams`.
2. Ensure central bucket exists using the bucket metadata.
3. If bucket metadata changed, update central bucket metadata.

### Apply `event_upsert`

1. Compute `source_event_key = (stream_id, source_event_id)`.
2. Look up `sync_event_map`.
3. If no mapping exists:
   - insert event into `central_bucket_id`
   - store returned `central_event_id`
   - store `source_event_version`
4. If mapping exists:
   - if incoming `source_event_version` is lower than stored version:
     - ignore as stale duplicate
   - if equal and checksum equal:
     - ignore as duplicate
   - if greater:
     - replace the existing central event by `central_event_id`
     - update version and checksum

### Ack rule

Only after the full transaction commits:

- update `sync_streams.last_acked_seq = to_seq`
- return `acked_through_seq = to_seq`

This gives the agent a clear exactly-once-visible outcome at the batch level:

- if the batch was committed, it is acked
- if not acked, the agent must resend the exact same batch range


## 13. Retry and Failure Rules

### Network timeout / connection refused

Agent behavior:

- keep local outbox rows unchanged
- retry same handshake or same unacked batch later
- use exponential backoff:
  - `2s`
  - `5s`
  - `10s`
  - `30s`
  - `60s`
  - cap at `300s`

### HTTP 5xx

Agent behavior:

- treat as unknown commit result
- do **not** mark anything acked
- resend same batch later

Server requirement:

- duplicate resend must be harmless

### Agent crash after server commit but before local ack mark

Behavior:

- agent restarts
- handshake returns higher `last_acked_seq`
- agent locally marks already-acked rows when it sees that cursor

### Central crash during apply

Behavior:

- transaction rolls back
- `last_acked_seq` does not advance
- agent resends same batch


## 14. Pruning Rules

### Endpoint `outbox_ops`

Safe to prune when:

- `acked_at IS NOT NULL`
- and older than `7 days`

Keep last `1000` acked ops per stream even after pruning threshold for diagnostics.

### Endpoint `source_event_state`

Safe to prune when:

- `is_final = 1`
- corresponding latest emitted seq is acked
- row is not one of the two newest source events in the stream
- older than `7 days`

Keep the newest two source events per stream to tolerate heartbeat-tail replacements.

### Central `sync_event_map`

Do **not** prune in V1.

Reason:

- it is the authoritative upsert mapping
- retention volume is acceptable at the target scale


## 15. Sync Status for Fleet UI

Add central status endpoints based on `sync_streams`:

- `last_received_at`
- `last_acked_seq`
- `stream count`

Derived per-agent/device status:

- `online`
- `offline`
- `catching_up`
- `error`

Derived fields:

- `last_sync_success_at`
- `pending_streams`
- `estimated_sync_lag_seconds`

Recommended thresholds:

- `online`: handshake or batch received within `60s`
- `offline`: no sync traffic within `300s`
- `catching_up`: online and at least one stream has backlog


## 16. New Modules and Files

### Endpoint

Add:

- `aw-agent-windows/aw_agent_windows/main.py`
- `aw-agent-windows/aw_agent_windows/config.py`
- `aw-agent-windows/aw_agent_windows/identity.py`
- `aw-agent-windows/aw_agent_windows/local_scan.py`
- `aw-agent-windows/aw_agent_windows/outbox.py`
- `aw-agent-windows/aw_agent_windows/sync_client.py`
- `aw-agent-windows/aw_agent_windows/health.py`

Responsibilities:

- process supervision
- local bucket discovery
- source event checksum/version tracking
- outbox persistence
- batch upload and retry

### Central

Add:

- `aw-server/aw_server/fleet_sync.py`
- `aw-server/aw_server/fleet_sync_store.py`
- `aw-server/aw_server/fleet_sync_models.py`

Modify:

- `aw-server/aw_server/api.py`
- `aw-server/aw_server/rest.py`


## 17. Endpoint Startup Contract

`aw-agent-windows` owns process startup for:

- local `aw-server`
- `aw-watcher-window`
- `aw-watcher-afk`
- `aw-watcher-session`

Watcher target:

- always `127.0.0.1:<local-port>`

Central target:

- used only by `aw-agent-windows`

This is required to guarantee offline-first behavior.


## 18. Migration Plan

### Phase 1

- central-mode fleet as currently implemented
- direct-to-central acceptable for development only

### Phase 2

- introduce `aw-agent-windows`
- move endpoint watchers to local-only target
- add sync API and metadata DB

### Phase 3

- central UI shows sync health
- old legacy direct buckets can remain readable but new installs use local-first sync only


## 19. Implementation Notes

### Important rule: no direct central writes from watchers in production fleet mode

If watchers can write directly to central while the agent also syncs local data:

- duplicates become very likely
- event mutability rules become ambiguous
- offline semantics become inconsistent

Fleet mode should therefore mean:

- watchers write to local only
- agent syncs to central only

### Important rule: central batch endpoint must be transactional

The server must never ack half a batch.

Either:

- everything in the batch is committed and `acked_through_seq` advances

or:

- nothing is committed and the agent resends the same batch


## 20. Summary

The reconnect-safe mechanism is:

1. capture locally into `aw-server`
2. scan local buckets into an immutable outbox with monotonic per-stream sequence numbers
3. upload batches to central
4. central upserts by `(stream_id, source_event_id)` and acks by `seq`
5. resend is always safe
6. only acked outbox rows are pruned

This gives:

- offline durability
- reconnect correctness
- idempotent replay
- safe handling of heartbeat-merged mutable tail events
- direct compatibility with the existing fleet bucket model
