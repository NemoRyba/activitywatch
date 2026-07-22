# ActivityWatch Fork Handoff

Date: 2026-04-26
Repo: `E:\projects\activitywatch`

## 0. Latest Status - 2026-07-21

The current priority has shifted from exploration to first LAN deployment.

Validated outputs:

- `dist\deployment\ActivityWatch-Fleet-Server-Setup.exe`
- `dist\deployment\ActivityWatch-Fleet-Watchers-Setup.exe`

The watcher setup is preconfigured for:

- `http://192.168.0.144:5600/`

Deployment behavior:

- server setup installs to `C:\Program Files\ActivityWatch Fleet Server`
- server starts as scheduled task `ActivityWatch Fleet Server`
- server binds to `0.0.0.0:5600` so the web UI/API can be reached from the LAN
- server runtime data is redirected to `C:\ProgramData\ActivityWatchFleet`
- watcher setup installs AFK/window/session watchers to `C:\Program Files\ActivityWatch Fleet Watchers`
- watcher setup creates an all-users Startup shortcut so watchers start for every interactive Windows user login
- watchers use central mode against `192.168.0.144:5600`
- watcher request queues are file backed through `aw-client`, so temporary server/network outages are retried after the server returns

Validation done on this working machine:

- web UI build succeeded with `npm run build`
- built web UI assets were copied into `aw-server\aw_server\static`
- PyInstaller builds exist for server, AFK watcher, window watcher, and session watcher
- packaged `aw-server.exe --version` returns `v0.13.2`
- packaged server starts on a test port and returns `/api/0/info`
- deployment setup builder completed successfully for server and watchers
- non-admin smoke install into temp folders passed for both payloads

Important deployment caveats:

- these setup executables are unsigned
- this build machine was not verified to own `192.168.0.144`; the packages are prepared for the intended server machine with that address
- run setup files as Administrator on target machines
- after changing web UI code later, rebuild `aw-server\aw-webui`, copy assets into `aw-server\aw_server\static`, then rebuild/server-package again

Latest fleet UI fixes:

- same-day range selection no longer leaves the fleet user summary permanently loading
- chart x-axis hover no longer triggers repeated redraw loops
- AFK hatch overlay is shown only when the AFK checkbox is enabled
- timeline chart uses a sticky y-axis rail so the hour scale remains visible while horizontally scrolling
- chart legend was removed; category details now live in the category tree below the chart
- chart bottom-label hover shows total bucket detail, category totals, and total AFK for that time bin
- chart segment hover shows only that segment/category detail
- category tree starts collapsed to avoid clutter
- category tree category paths are de-duplicated, so `Uncategorized`, `Comms`, and `IM` are shown once instead of repeated
- start page settings now include `Fleet`
- fleet user detail view now defaults the start date to today instead of the previous 7-day window; the date input remains user-pickable

Latest server summary fix:

- fleet user/device summary cards now merge overlapping state intervals per user/device/session before summing
- this fixes inflated AFK totals caused by duplicated overlapping `afkstatus` rows
- observed July 21 Stepik example before the fix: naive AFK row sum was about 12h 16m
- observed same range after the fix and stack restart: AFK card dropped to about 3h 17m at the time of verification
- regression coverage added in `aw-server\tests\test_server.py`
- fleet server tests passed with `python -m pytest -o addopts= aw-server\tests\test_server.py -k fleet`
- server PyInstaller output and deployment setup EXEs were rebuilt after this fix

Current uncommitted areas:

- root repo has a modified `aw-server` submodule pointer/state
- `aw-server/aw-webui` has modified fleet/settings/category-tree files
- `aw-server/aw_server/fleet.py` and `aw-server/tests/test_server.py` include the AFK interval-merge fix
- `aw-watcher-session` has two new PyInstaller packaging files
- `deploy/windows` is new and contains the installer scripts and builder

## 1. Fork Goal

This fork is no longer meant to stay a mostly local, single-user ActivityWatch install.

The target is a Windows-focused, centralized work-tracking system for a small fleet:

- one central `aw-server` + `aw-webui`
- multiple users
- multiple computers
- grouping and reporting by:
  - user
  - device/computer
  - user on one device
  - user across all devices
- session-aware state handling:
  - active
  - AFK
  - locked
  - disconnected
  - logged_in
  - logged_off
  - no_session

The user intent that drove the fork:

- quickly see what a user worked on
- see which programs were used and for how long
- differentiate active vs AFK vs locked vs disconnected
- eventually treat the whole GUI primarily per user and per session, not just per hostname
- support queries like "how much time did this user spend in Inventor this week across selected PCs or all PCs?"

Constraints/assumptions explicitly stated by the user:

- privacy is not a design blocker for this fork
- Windows username is sufficient identity for now
- reliable session correctness matters
- Explorer path tracking is enough for file/folder context for now
- scale is small, roughly 20 users / 20 devices
- query cost is not a priority right now


## 2. Current Runtime State

Main stack script:

- `stack.ps1`

Useful commands:

```powershell
Set-Location 'E:\projects\activitywatch'
powershell -ExecutionPolicy Bypass -File .\stack.ps1 start
powershell -ExecutionPolicy Bypass -File .\stack.ps1 restart
powershell -ExecutionPolicy Bypass -File .\stack.ps1 status
```

Default web URL:

- `http://127.0.0.1:5600/`

Current login/auth:

- login page is enabled on the server/web UI
- default bootstrap credentials are currently `admin` / `admin`
- password is not stored in plaintext; the server hashes it in `aw_server/settings.py`

Important stack behavior:

- the stack launches `aw-server`, `aw-watcher-afk`, `aw-watcher-window`, and `aw-watcher-session`
- `stack.ps1` can also be run with `-CentralMode`
- built web assets are copied into `aw-server\aw_server\static`


## 3. What Has Already Been Implemented

### 3.1 Watchers and Identity Plumbing

Implemented:

- central identity helpers in `aw-core`
- richer bucket metadata and event metadata in:
  - `aw-watcher-afk`
  - `aw-watcher-window`
- new watcher package:
  - `aw-watcher-session`

Important files:

- [aw-core/aw_core/identity.py](/E:/projects/activitywatch/aw-core/aw_core/identity.py)
- [aw-watcher-afk/aw_watcher_afk/afk.py](/E:/projects/activitywatch/aw-watcher-afk/aw_watcher_afk/afk.py)
- [aw-watcher-afk/aw_watcher_afk/config.py](/E:/projects/activitywatch/aw-watcher-afk/aw_watcher_afk/config.py)
- [aw-watcher-window/aw_watcher_window/main.py](/E:/projects/activitywatch/aw-watcher-window/aw_watcher_window/main.py)
- [aw-watcher-window/aw_watcher_window/config.py](/E:/projects/activitywatch/aw-watcher-window/aw_watcher_window/config.py)
- [aw-watcher-window/aw_watcher_window/lib.py](/E:/projects/activitywatch/aw-watcher-window/aw_watcher_window/lib.py)
- [aw-watcher-session/aw_watcher_session/main.py](/E:/projects/activitywatch/aw-watcher-session/aw_watcher_session/main.py)
- [aw-watcher-session/aw_watcher_session/windows.py](/E:/projects/activitywatch/aw-watcher-session/aw_watcher_session/windows.py)

Current watcher metadata model:

- `username`
- `device_id`
- `device_name`
- `session_id`
- `session_type`
- `hostname`

Current watcher behavior:

- `aw-watcher-session` is the source of truth for session state
- `aw-watcher-afk` reports AFK/not-AFK with session identity attached
- `aw-watcher-window` reports current app/window/process info with session identity attached


### 3.2 Fleet / Multi-User Server Extensions

Implemented in `aw-server`:

- auth/session support for the web UI
- admin UI config endpoints
- fleet summary endpoints
- user/device summary endpoints
- report endpoint
- fleet sync protocol endpoints for offline/resync work
- bucket identity backfill for stale old bucket metadata

Important files:

- [aw-server/aw_server/api.py](/E:/projects/activitywatch/aw-server/aw_server/api.py)
- [aw-server/aw_server/rest.py](/E:/projects/activitywatch/aw-server/aw_server/rest.py)
- [aw-server/aw_server/server.py](/E:/projects/activitywatch/aw-server/aw_server/server.py)
- [aw-server/aw_server/settings.py](/E:/projects/activitywatch/aw-server/aw_server/settings.py)
- [aw-server/aw_server/fleet.py](/E:/projects/activitywatch/aw-server/aw_server/fleet.py)
- [aw-server/aw_server/fleet_sync.py](/E:/projects/activitywatch/aw-server/aw_server/fleet_sync.py)
- [aw-server/aw_server/fleet_sync_store.py](/E:/projects/activitywatch/aw-server/aw_server/fleet_sync_store.py)
- [aw-server/aw_server/bucket_backfill.py](/E:/projects/activitywatch/aw-server/aw_server/bucket_backfill.py)

Implemented endpoints worth knowing:

- `GET /api/0/fleet/live`
- `GET /api/0/fleet/users`
- `GET /api/0/fleet/users/<username>`
- `GET /api/0/fleet/devices`
- `GET /api/0/fleet/devices/<device_id>`
- `POST /api/0/fleet/report`
- `POST /api/0/fleet/sync/handshake`
- `POST /api/0/fleet/sync/batch`

Important fix already done:

- old AFK/window buckets had empty metadata, which caused `unknown` everywhere in the UI
- this was fixed by:
  - bucket metadata backfill from latest event data
  - UI fallback to event-level identity when bucket metadata is stale
  - fixing `api.update_bucket()` to pass `type_id=` to the datastore


### 3.3 Endpoint Sync Scaffold

There is now a partial endpoint sync component:

- `aw-agent-windows`

Important files:

- [aw-agent-windows/aw_agent_windows/main.py](/E:/projects/activitywatch/aw-agent-windows/aw_agent_windows/main.py)
- [aw-agent-windows/aw_agent_windows/config.py](/E:/projects/activitywatch/aw-agent-windows/aw_agent_windows/config.py)
- [aw-agent-windows/aw_agent_windows/identity.py](/E:/projects/activitywatch/aw-agent-windows/aw_agent_windows/identity.py)
- [aw-agent-windows/aw_agent_windows/outbox.py](/E:/projects/activitywatch/aw-agent-windows/aw_agent_windows/outbox.py)
- [aw-agent-windows/aw_agent_windows/sync_client.py](/E:/projects/activitywatch/aw-agent-windows/aw_agent_windows/sync_client.py)
- [aw-agent-windows/README.md](/E:/projects/activitywatch/aw-agent-windows/README.md)

Current status:

- durable sync outbox exists
- handshake + batch upload client exists
- stable endpoint identity exists
- the missing piece is the local bucket scan / local event export into the outbox

So:

- transport layer is partially implemented
- complete offline resync from endpoint-local data is not finished end-to-end yet


### 3.4 Web UI Changes

Implemented in `aw-webui`:

- German/English static translation layer
- language selector in top-right
- German set as default
- login page
- auth store
- admin UI config store
- fleet views
- session-aware bucket identity helper
- improved timeline details panel under the timeline
- per-session watcher selection in timeline
- multiple stacked timelines when viewing one user across all devices
- user/device-aware bucket detail/list screens
- column order saving
- admin toggles for Stopwatch and Tools menu visibility
- Stopwatch remains in code but is intentionally fork-disabled by default

Important files:

- [aw-server/aw-webui/src/i18n.ts](/E:/projects/activitywatch/aw-server/aw-webui/src/i18n.ts)
- [aw-server/aw-webui/src/views/Login.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/Login.vue)
- [aw-server/aw-webui/src/stores/auth.ts](/E:/projects/activitywatch/aw-server/aw-webui/src/stores/auth.ts)
- [aw-server/aw-webui/src/stores/adminUi.ts](/E:/projects/activitywatch/aw-server/aw-webui/src/stores/adminUi.ts)
- [aw-server/aw-webui/src/stores/fleet.ts](/E:/projects/activitywatch/aw-server/aw-webui/src/stores/fleet.ts)
- [aw-server/aw-webui/src/util/bucketIdentity.ts](/E:/projects/activitywatch/aw-server/aw-webui/src/util/bucketIdentity.ts)
- [aw-server/aw-webui/src/views/Timeline.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/Timeline.vue)
- [aw-server/aw-webui/src/visualizations/VisTimeline.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/visualizations/VisTimeline.vue)
- [aw-server/aw-webui/src/views/Bucket.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/Bucket.vue)
- [aw-server/aw-webui/src/views/Buckets.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/Buckets.vue)
- [aw-server/aw-webui/src/views/fleet/FleetOverview.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/fleet/FleetOverview.vue)
- [aw-server/aw-webui/src/views/fleet/FleetUsers.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/fleet/FleetUsers.vue)
- [aw-server/aw-webui/src/views/fleet/FleetUser.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/fleet/FleetUser.vue)
- [aw-server/aw-webui/src/views/fleet/FleetDevices.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/fleet/FleetDevices.vue)
- [aw-server/aw-webui/src/views/fleet/FleetDevice.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/views/fleet/FleetDevice.vue)
- [aw-server/aw-webui/src/components/Header.vue](/E:/projects/activitywatch/aw-server/aw-webui/src/components/Header.vue)
- [aw-server/aw-webui/src/route.js](/E:/projects/activitywatch/aw-server/aw-webui/src/route.js)

Current timeline behavior:

- filter by user
- filter by device
- filter by duration
- select individual watcher/session buckets
- when one user is selected and device is "all devices", timelines stack by device
- hover details now render in a details area below the timeline instead of blocking the chart
- legacy stopwatch bucket is filtered out of the timeline view


## 4. Current Functional Direction

The fork currently mixes two worlds:

1. new session-aware / user-aware fleet functionality
2. old upstream host-centric ActivityWatch functionality

The new work is already most visible in:

- fleet pages
- timeline
- bucket detail/list screens

The old host-centric model still dominates in several legacy views:

- `Activity`
- `Report`
- `Search`
- `Graph`
- some older query components

This is the biggest architectural gap left in the UI.


## 5. Known Issues / Incomplete Areas

### 5.1 Full GUI is not yet fully session-first

Most important remaining gap:

- the whole GUI is not yet consistently treated per session and per user

What is already adapted:

- fleet views
- timeline
- bucket identity handling

What is still mostly legacy:

- host-based activity views
- report/search/graph paths
- some older bucket grouping assumptions in stores and query code


### 5.2 `aw-agent-windows` is incomplete

Current state:

- sync outbox and wire protocol exist
- local datastore scan into outbox is still missing

This means:

- direct central-mode watcher upload works
- durable offline sync from endpoint-local data is not finished end-to-end


### 5.3 Session type mismatch can still happen

Observed nuance:

- `aw-watcher-session` can report exact Windows session type such as `console`
- AFK/window identity currently may still say `interactive`

This is not fatal, but if the UI needs a single authoritative session label, it should prefer the session watcher.


### 5.4 Stopwatch is legacy for this fork

Current intent:

- do not remove upstream stopwatch code
- keep it clearly marked as unused in this fork
- hide it from normal navigation by default

Current implementation:

- admin UI config can toggle visibility of Stopwatch and Tools menus
- timeline view explicitly hides the legacy stopwatch bucket


### 5.5 Auth model is minimal

Current auth is intentionally simple:

- server login page exists
- default admin user is auto-created
- password is hashed

What is not implemented:

- multi-user server auth management UI
- password change flow
- role hierarchy beyond admin flag


## 6. Important Decisions Already Made

- Privacy is not treated as a blocker for this fork.
- Windows username is sufficient identity for now.
- Session correctness matters more than elegant abstraction.
- Explorer path tracking is enough for now; broad app-specific open-file extraction is deferred.
- Small-fleet simplicity is preferred over heavy optimization.
- Backward compatibility with upstream/local ActivityWatch is useful, but this fork should bias toward central multi-user correctness.


## 7. Recommended Next Steps For A New Chat

If a new chat needs a concrete next slice, the highest-value order is:

1. Finish making the remaining legacy web UI views session-aware and user-aware.
2. Complete `aw-agent-windows` local bucket scan -> outbox -> fleet sync flow.
3. Normalize session identity and session type across AFK/window/session watchers.
4. Add tests around:
   - bucket identity backfill
   - timeline per-session watcher filtering
   - user/device aggregated report correctness
   - sync conflict/recovery behavior
5. Add more explicit fleet UI drilldowns where needed:
   - selected users + selected devices + date range
   - per-session filters
   - app summary across selected PCs


## 8. Suggested Prompt For The Next Chat

Use something like:

```text
Read ACTIVITYWATCH_HANDOFF.md and continue this ActivityWatch fork.

This fork is intended to become a centralized Windows multi-user work-tracking system.
Priority: make the remaining GUI consistently session-aware and user-aware, then continue the endpoint sync path in aw-agent-windows.

Before changing code, inspect the current implementations in:
- aw-server/aw_server/fleet.py
- aw-server/aw_server/fleet_sync.py
- aw-server/aw_server/bucket_backfill.py
- aw-server/aw-webui/src/views/Timeline.vue
- aw-server/aw-webui/src/util/bucketIdentity.ts
- aw-agent-windows/aw_agent_windows/*
- aw-watcher-session/*
```


## 9. Roadmap Reference

The original detailed implementation roadmap is in:

- [roadmap.md](/E:/projects/activitywatch/roadmap.md)

That roadmap still reflects the intended direction well, but this handoff is the more accurate picture of current implementation state.
