# ActivityWatch Centralized Multi-User V1 Roadmap

## Goal

Turn this repository from a primarily local, single-user activity tracker into a **centralized Windows-focused work-tracking system** for a small fleet:

- one central server and web UI
- multiple endpoint computers on the network
- multiple Windows users across those computers
- grouping and reporting by:
  - user
  - computer
  - user on one computer
  - user across all computers
- reliable session-state handling for:
  - login
  - active
  - AFK
  - locked
  - disconnected
  - logoff

This roadmap is for **Phase 1 / V1**, optimized for correctness and implementation speed over long-term generality.


## V1 Scope

### Included

- central server mode
- Windows endpoints only
- direct network ingestion from endpoint agents to central server
- Windows account name as identity
- current app and window title
- process executable name and executable path
- AFK vs not-AFK
- session-state watcher for login/lock/unlock/disconnect/logoff
- Explorer path capture when Explorer is active
- UI filters and dashboards by user and device
- report queries such as:
  - "how much time did user X spend in Inventor this week?"
  - "what is user X doing right now?"
  - "what was user X's session state over the last day/week?"

### Deferred

- heavy query optimization
- enterprise auth/roles
- non-Windows support
- exact open-file extraction for every third-party application
- high-scale fleet management


## Architectural Direction

### Centralized Model

Do **not** build V1 around syncing local ActivityWatch databases.

Instead:

- run one **central ActivityWatch server**
- run one **Windows agent/service** on each endpoint
- let the agent run or coordinate watchers for each interactive session
- send events directly to the central server over HTTP

This keeps the data model simple and makes live views possible.

### Why this fits the current repo

The repo already has useful foundations:

- bucket metadata already contains `client`, `hostname`, and arbitrary `data`
  - [aw-server/aw_server/api.py](./aw-server/aw_server/api.py)
  - [aw-core/aw_core/schemas/bucket.json](./aw-core/aw_core/schemas/bucket.json)
- the web UI already groups data by host/device and has an early multidevice mode
  - [aw-server/aw-webui/src/stores/buckets.ts](./aw-server/aw-webui/src/stores/buckets.ts)
  - [aw-server/aw-webui/src/stores/activity.ts](./aw-server/aw-webui/src/stores/activity.ts)
  - [aw-server/aw-webui/src/queries.ts](./aw-server/aw-webui/src/queries.ts)
- the current watchers already report bucketed event streams
  - [aw-watcher-window/aw_watcher_window/main.py](./aw-watcher-window/aw_watcher_window/main.py)
  - [aw-watcher-afk/aw_watcher_afk/afk.py](./aw-watcher-afk/aw_watcher_afk/afk.py)

The missing pieces are:

- first-class user identity
- reliable Windows session-state tracking
- agent orchestration for networked endpoints
- admin/fleet UI surfaces


## Phase 1 Deliverables

### New Components

1. `aw-agent-windows`
   - Windows machine-level agent
   - central server URL + token/config
   - reports machine heartbeat
   - launches or supervises per-session watchers
   - tags endpoint identity

2. `aw-watcher-session`
   - new watcher for Windows session state
   - emits session lifecycle and session-state events

3. `aw-server` fleet extensions
   - API endpoints for:
     - live fleet summary
     - user summary
     - device summary
     - activity reports by user/device/app

4. `aw-webui` fleet/admin screens
   - live overview
   - users list
   - user detail
   - device detail
   - report/search screen for user/app/date

### Existing Components to Extend

1. `aw-watcher-window`
   - add user/device/session/process metadata
   - add Explorer path extraction when Explorer is active

2. `aw-watcher-afk`
   - add user/device/session metadata
   - align AFK semantics with session-state watcher

3. `aw-server` bucket and query handling
   - accept and expose richer bucket metadata
   - add grouping helpers for user/device/session

4. `aw-webui` stores and route model
   - treat `user` and `device` as first-class filters
   - continue using host/device grouping logic where possible


## Data Model

### Canonical Identity Fields

V1 uses Windows username as the user identifier.

Required machine/session fields:

- `username`
- `device_id`
- `device_name`
- `session_id`
- `session_type`
- `agent_id`

Recommended supporting fields:

- `domain`
- `hostname`
- `os`
- `process_name`
- `process_path`
- `window_title`
- `explorer_path`
- `state`

### Bucket Strategy

Use separate buckets per watcher per device per user per session.

Recommended bucket ID shape:

```text
aw-watcher-window__{device_id}__{username}__{session_id}
aw-watcher-afk__{device_id}__{username}__{session_id}
aw-watcher-session__{device_id}__{username}__{session_id}
aw-agent-heartbeat__{device_id}
```

Reason:

- avoids collisions across machines
- keeps session transitions explicit
- supports queries by user/device/session without schema changes to bucket ID parsing logic

### Bucket `data` payload

All Phase 1 watcher buckets should include:

```json
{
  "username": "jdoe",
  "device_id": "pc-01",
  "device_name": "PC-01",
  "session_id": "2",
  "session_type": "interactive",
  "agent_id": "pc-01-agent",
  "source": "central-v1"
}
```

### Event Shapes

#### Window watcher event

```json
{
  "timestamp": "2026-04-17T08:10:00Z",
  "duration": 0,
  "data": {
    "app": "Inventor.exe",
    "title": "part-123.ipt - Autodesk Inventor",
    "process_name": "Inventor.exe",
    "process_path": "C:\\Program Files\\Autodesk\\Inventor\\Inventor.exe",
    "username": "jdoe",
    "device_id": "pc-01",
    "device_name": "PC-01",
    "session_id": "2",
    "state": "active",
    "explorer_path": null
  }
}
```

#### AFK watcher event

```json
{
  "timestamp": "2026-04-17T08:10:00Z",
  "duration": 0,
  "data": {
    "status": "not-afk",
    "username": "jdoe",
    "device_id": "pc-01",
    "device_name": "PC-01",
    "session_id": "2"
  }
}
```

#### Session watcher event

```json
{
  "timestamp": "2026-04-17T08:10:00Z",
  "duration": 0,
  "data": {
    "state": "locked",
    "username": "jdoe",
    "device_id": "pc-01",
    "device_name": "PC-01",
    "session_id": "2",
    "reason": "workstation-lock"
  }
}
```

#### Agent heartbeat event

```json
{
  "timestamp": "2026-04-17T08:10:00Z",
  "duration": 0,
  "data": {
    "status": "online",
    "device_id": "pc-01",
    "device_name": "PC-01",
    "hostname": "PC-01",
    "users_logged_in": ["jdoe"],
    "active_sessions": [2]
  }
}
```


## Session-State Semantics

This is the most important correctness rule for V1.

### States

Use this normalized state model:

- `active`
- `afk`
- `locked`
- `disconnected`
- `logged_in`
- `logged_off`
- `no_session`

### Counting Rules

- `active` counts as work-capable session time
- `afk` does **not** count as active work time
- `locked` does **not** count as active work time
- `disconnected` does **not** count as active work time
- `logged_in` but not active is presence, not active work time
- `logged_off` and `no_session` mean no user session is available

### Source of truth

Do **not** infer `locked` or `disconnected` from AFK.

Use:

- `aw-watcher-session` as source of truth for session state
- `aw-watcher-afk` only for `active` vs `afk` inside an interactive unlocked session


## File-by-File Implementation Roadmap

## 1. Server: metadata and fleet APIs

### Existing files to modify

#### [aw-server/aw_server/rest.py](./aw-server/aw_server/rest.py)

Purpose:

- extend the public API contract
- add fleet endpoints

Changes:

- expand `create_bucket` and `update_bucket` request models to include `data`
- stop assuming only `client`, `type`, `hostname` are relevant
- add new resources:
  - `GET /api/0/fleet/live`
  - `GET /api/0/fleet/users`
  - `GET /api/0/fleet/users/<username>`
  - `GET /api/0/fleet/devices`
  - `GET /api/0/fleet/devices/<device_id>`
  - `POST /api/0/fleet/report`

#### [aw-server/aw_server/api.py](./aw-server/aw_server/api.py)

Purpose:

- implement fleet/grouping/report logic

Changes:

- extend `create_bucket(...)` calls to consistently persist `data`
- add helpers:
  - `get_bucket_identity(bucket)`
  - `group_buckets_by_user()`
  - `group_buckets_by_device()`
  - `get_live_fleet_summary()`
  - `get_user_summary(username, start, end)`
  - `get_device_summary(device_id, start, end)`
  - `run_report(report_spec)`
- add report helpers for:
  - app time by user
  - active time by user
  - session-state totals by user/device

#### [aw-core/aw_core/schemas/bucket.json](./aw-core/aw_core/schemas/bucket.json)

Purpose:

- make the new bucket metadata contract explicit

Changes:

- keep `data` as object but document required V1 keys:
  - `username`
  - `device_id`
  - `device_name`
  - `session_id`
  - `session_type`
  - `agent_id`

### New file(s) to add

#### `aw-server/aw_server/fleet.py`

Purpose:

- keep fleet logic out of `api.py`

Responsibilities:

- bucket classification helpers
- live-state reduction
- user/device grouping
- report transformations

Suggested functions:

```python
def classify_bucket(bucket: dict) -> dict: ...
def latest_event(api, bucket_id: str) -> dict | None: ...
def summarize_live_state(api) -> dict: ...
def summarize_user(api, username: str, start, end) -> dict: ...
def summarize_device(api, device_id: str, start, end) -> dict: ...
def report_time_by_app(api, username: str | None, device_id: str | None, start, end) -> dict: ...
```


## 2. New watcher: Windows session state

### New module

#### `aw-watcher-session/`

Create a new standalone package parallel to the existing watchers.

Suggested files:

- `aw-watcher-session/pyproject.toml`
- `aw-watcher-session/README.md`
- `aw-watcher-session/aw_watcher_session/__init__.py`
- `aw-watcher-session/aw_watcher_session/__main__.py`
- `aw-watcher-session/aw_watcher_session/main.py`
- `aw-watcher-session/aw_watcher_session/config.py`
- `aw-watcher-session/aw_watcher_session/windows.py`
- `aw-watcher-session/aw_watcher_session/identity.py`

Responsibilities:

- discover current username and session id
- determine state transitions:
  - login
  - active
  - locked
  - disconnected
  - logoff
- emit heartbeats or transition events to a `sessionstate` bucket

Suggested bucket type:

- `sessionstate`

Suggested event schema:

```json
{
  "state": "locked",
  "username": "jdoe",
  "device_id": "pc-01",
  "device_name": "PC-01",
  "session_id": "2",
  "reason": "workstation-lock"
}
```

### Exact integration rules

- when the session transitions to `locked`, the session watcher emits a state event immediately
- when the session transitions to `disconnected`, emit immediately
- when the session transitions back to interactive/unlocked, emit `active` or `logged_in` depending on input state


## 3. New machine-level endpoint agent

### New module

#### `aw-agent-windows/`

Suggested files:

- `aw-agent-windows/pyproject.toml`
- `aw-agent-windows/README.md`
- `aw-agent-windows/aw_agent_windows/__init__.py`
- `aw-agent-windows/aw_agent_windows/__main__.py`
- `aw-agent-windows/aw_agent_windows/main.py`
- `aw-agent-windows/aw_agent_windows/config.py`
- `aw-agent-windows/aw_agent_windows/identity.py`
- `aw-agent-windows/aw_agent_windows/sessions.py`
- `aw-agent-windows/aw_agent_windows/process_manager.py`
- `aw-agent-windows/aw_agent_windows/heartbeat.py`

Responsibilities:

- read config:
  - server URL
  - API token or shared secret
  - device ID override
  - polling intervals
- discover current endpoint identity
- enumerate active/logged-in Windows sessions
- start per-session helper watchers
- send machine heartbeat events
- restart failed watchers

V1 can initially run as a foreground process before being converted to a Windows service.

### Phase 1 config shape

```toml
[server]
host = "central-host"
port = 5600
token = "dev-token"

[agent]
device_id = "pc-01"
device_name = "PC-01"
machine_poll_time = 5
session_poll_time = 2
```


## 4. Extend current window watcher

### Existing files to modify

#### [aw-watcher-window/aw_watcher_window/main.py](./aw-watcher-window/aw_watcher_window/main.py)

Changes:

- build richer bucket IDs
- attach identity metadata to bucket creation
- attach identity/process metadata to every event
- capture `process_path` on Windows
- call Explorer-path helper when active process is Explorer

#### [aw-watcher-window/aw_watcher_window/config.py](./aw-watcher-window/aw_watcher_window/config.py)

Changes:

- add optional args:
  - `--username`
  - `--device-id`
  - `--device-name`
  - `--session-id`
  - `--central-mode`

#### `aw-watcher-window/aw_watcher_window/lib.py`

Changes:

- extend current returned window payload on Windows to include:
  - `process_name`
  - `process_path`
- if active app is Explorer, enrich with:
  - `explorer_path`

### New helper files to add

#### `aw-watcher-window/aw_watcher_window/identity.py`

Responsibilities:

- resolve:
  - username
  - device_id
  - device_name
  - session_id

#### `aw-watcher-window/aw_watcher_window/explorer.py`

Responsibilities:

- Windows-only Explorer path extraction
- return current folder path when Explorer is focused


## 5. Extend current AFK watcher

### Existing files to modify

#### [aw-watcher-afk/aw_watcher_afk/afk.py](./aw-watcher-afk/aw_watcher_afk/afk.py)

Changes:

- enrich bucket creation with `data`
- include:
  - `username`
  - `device_id`
  - `device_name`
  - `session_id`
in emitted events

#### [aw-watcher-afk/aw_watcher_afk/config.py](./aw-watcher-afk/aw_watcher_afk/config.py)

Changes:

- add optional args:
  - `--username`
  - `--device-id`
  - `--device-name`
  - `--session-id`
  - `--central-mode`

### New helper file to add

#### `aw-watcher-afk/aw_watcher_afk/identity.py`

Purpose:

- same shape as window watcher identity helper


## 6. Web UI route and screen plan

### Existing route file to modify

#### [aw-server/aw-webui/src/route.js](./aw-server/aw-webui/src/route.js)

Add new routes:

- `/fleet`
- `/fleet/users`
- `/fleet/users/:username`
- `/fleet/devices`
- `/fleet/devices/:device_id`
- `/fleet/report`

### Existing stores to modify

#### [aw-server/aw-webui/src/stores/server.ts](./aw-server/aw-webui/src/stores/server.ts)

Changes:

- extend server info shape if needed for central mode
- add `mode: "local" | "central"` if useful

#### [aw-server/aw-webui/src/stores/buckets.ts](./aw-server/aw-webui/src/stores/buckets.ts)

Changes:

- add getters:
  - `users`
  - `devices`
  - `sessions`
  - `bucketsByUser`
  - `bucketsBySession`
- stop treating `hostname` as the only primary dimension
- preserve current host logic for backward compatibility

#### [aw-server/aw-webui/src/stores/activity.ts](./aw-server/aw-webui/src/stores/activity.ts)

Changes:

- introduce query options for:
  - `username`
  - `device_id`
  - `session_id`
- keep existing `host` support during transition
- add methods:
  - `query_user_activity(...)`
  - `query_device_activity(...)`
  - `query_user_app_time(...)`

### New stores to add

#### `aw-server/aw-webui/src/stores/fleet.ts`

Responsibilities:

- load live fleet summary
- load users list
- load devices list
- load user detail payload
- load device detail payload
- load reports

Suggested methods:

```ts
loadLive(): Promise<void>
loadUsers(): Promise<void>
loadUser(username: string, params): Promise<void>
loadDevices(): Promise<void>
loadDevice(deviceId: string, params): Promise<void>
runReport(spec): Promise<void>
```

### New views to add

#### `aw-server/aw-webui/src/views/fleet/FleetOverview.vue`

Screen purpose:

- live "who is active right now" table

Columns:

- user
- device
- session state
- AFK state
- current app
- current title
- last update

#### `aw-server/aw-webui/src/views/fleet/Users.vue`

Screen purpose:

- list all known users
- quick totals for today/week

#### `aw-server/aw-webui/src/views/fleet/UserDetail.vue`

Screen purpose:

- one user across all machines

Sections:

- live state
- devices used
- weekly totals
- app breakdown
- session-state timeline
- window/activity drilldown

#### `aw-server/aw-webui/src/views/fleet/Devices.vue`

Screen purpose:

- list all endpoint machines

#### `aw-server/aw-webui/src/views/fleet/DeviceDetail.vue`

Screen purpose:

- what happened on one machine

Sections:

- currently logged-in users
- live session state
- current app
- recent activity

#### `aw-server/aw-webui/src/views/fleet/Report.vue`

Screen purpose:

- ad hoc report UI for:
  - user
  - device
  - app/process
  - date range

Example canned report:

- "Inventor time this week per user"


## 7. API Shapes for Phase 1

## A. Fleet Live

### `GET /api/0/fleet/live`

Response:

```json
{
  "generated_at": "2026-04-17T08:15:00Z",
  "users": [
    {
      "username": "jdoe",
      "device_id": "pc-01",
      "device_name": "PC-01",
      "session_id": "2",
      "session_state": "active",
      "afk_status": "not-afk",
      "current_app": "Inventor.exe",
      "current_title": "part-123.ipt - Autodesk Inventor",
      "process_path": "C:\\Program Files\\Autodesk\\Inventor\\Inventor.exe",
      "last_updated": "2026-04-17T08:14:58Z"
    }
  ],
  "devices": [
    {
      "device_id": "pc-01",
      "device_name": "PC-01",
      "status": "online",
      "users_logged_in": ["jdoe"],
      "last_updated": "2026-04-17T08:14:58Z"
    }
  ]
}
```

## B. Users list

### `GET /api/0/fleet/users`

Response:

```json
{
  "users": [
    {
      "username": "jdoe",
      "devices": ["pc-01", "pc-02"],
      "last_seen": "2026-04-17T08:14:58Z"
    }
  ]
}
```

## C. User detail

### `GET /api/0/fleet/users/<username>?start=<iso>&end=<iso>`

Response:

```json
{
  "username": "jdoe",
  "range": {
    "start": "2026-04-14T00:00:00Z",
    "end": "2026-04-21T00:00:00Z"
  },
  "devices": ["pc-01", "pc-02"],
  "totals": {
    "active_seconds": 12345,
    "afk_seconds": 2345,
    "locked_seconds": 500,
    "disconnected_seconds": 0
  },
  "apps": [
    {
      "app": "Inventor.exe",
      "seconds": 7200
    }
  ],
  "sessions": [
    {
      "device_id": "pc-01",
      "session_id": "2",
      "state": "active",
      "last_updated": "2026-04-17T08:14:58Z"
    }
  ]
}
```

## D. Device detail

### `GET /api/0/fleet/devices/<device_id>?start=<iso>&end=<iso>`

Response:

```json
{
  "device_id": "pc-01",
  "device_name": "PC-01",
  "users": ["jdoe"],
  "status": "online",
  "sessions": [
    {
      "username": "jdoe",
      "session_id": "2",
      "state": "active"
    }
  ],
  "last_updated": "2026-04-17T08:14:58Z"
}
```

## E. Report endpoint

### `POST /api/0/fleet/report`

Request:

```json
{
  "report": "time_by_app",
  "filters": {
    "username": "jdoe",
    "device_id": null,
    "app_contains": "Inventor",
    "start": "2026-04-14T00:00:00Z",
    "end": "2026-04-21T00:00:00Z"
  }
}
```

Response:

```json
{
  "report": "time_by_app",
  "filters": {
    "username": "jdoe",
    "app_contains": "Inventor"
  },
  "rows": [
    {
      "username": "jdoe",
      "device_id": "pc-01",
      "app": "Inventor.exe",
      "seconds": 7200
    }
  ]
}
```


## 8. Query Strategy for Phase 1

Avoid inventing a second reporting engine immediately.

For V1:

- continue using raw buckets/events
- use Python-side reduction in the new fleet API layer
- only later decide whether to push more into AW query scripts or server-side materialized summaries

### Phase 1 summary logic

- latest-state endpoints:
  - read last event from window/afk/session buckets
- weekly report endpoints:
  - fetch raw events in range
  - merge by state/app in Python

This is acceptable for the target size of roughly 20 users and 20 machines.


## 9. Migration / Compatibility Rules

### Existing personal/local installs

Do not break the current local single-user flow.

Compatibility rules:

- existing routes stay working
- existing host-based activity view stays working
- existing bucket shapes remain valid
- new V1 central fields are additive

### UI transition strategy

- existing `/activity/:host/...` remains
- new `/fleet/...` screens are added alongside it
- central mode users primarily use `/fleet/...`


## 10. Recommended Implementation Order

## Milestone 1: Shared identity plumbing

Files:

- `aw-server/aw_server/api.py`
- `aw-server/aw_server/rest.py`
- `aw-core/aw_core/schemas/bucket.json`
- `aw-watcher-window/...`
- `aw-watcher-afk/...`

Result:

- watchers can emit enriched metadata
- server can store and expose it

## Milestone 2: Session watcher

Files:

- new `aw-watcher-session/...`

Result:

- lock/disconnect/logoff correctness is available in stored data

## Milestone 3: Fleet APIs

Files:

- `aw-server/aw_server/fleet.py`
- `aw-server/aw_server/api.py`
- `aw-server/aw_server/rest.py`

Result:

- central summaries and reports are available for the UI

## Milestone 4: Fleet UI screens

Files:

- `aw-server/aw-webui/src/route.js`
- `aw-server/aw-webui/src/stores/fleet.ts`
- `aw-server/aw-webui/src/stores/buckets.ts`
- new `aw-server/aw-webui/src/views/fleet/*.vue`

Result:

- live operations dashboard and user/device views

## Milestone 5: Agent/service

Files:

- new `aw-agent-windows/...`

Result:

- centralized deployment model is usable across endpoints


## 11. Initial Acceptance Criteria for Phase 1

V1 Phase 1 is considered complete when all of the following are true:

- a central server receives data from at least 2 Windows machines
- data is distinguishable by:
  - username
  - device
  - session
- lock/unlock/disconnect/logoff transitions are stored explicitly
- the web UI shows:
  - current users and their live state
  - current device status
  - user detail page with app totals
  - report for app time this week
- querying "Inventor time this week for jdoe" works
- Explorer path is captured when Explorer is active


## 12. First Implementation Slice After This Roadmap

The best first coding slice is:

1. extend `aw-watcher-window` and `aw-watcher-afk` to emit V1 identity metadata
2. add server support for storing/exposing that metadata cleanly
3. scaffold `aw-watcher-session`
4. add `GET /api/0/fleet/live`
5. add `FleetOverview.vue`

That gives the shortest path to an end-to-end demo of the new direction.
