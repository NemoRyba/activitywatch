# ActivityWatch Fork Handoff

Date: 2026-08-24
Repo: `C:\projecte_visual_code\activitywatch`

## 0. Latest Status - 2026-08-24

The current priority is finishing the LAN fleet deployment and iterating on the server-side fleet/admin UI.

Validated outputs:

- `dist\deployment\ActivityWatch-Fleet-Server-Setup.exe`
- `dist\deployment\ActivityWatch-Fleet-Watchers-Setup.exe`

Latest validated setup hashes:

- Server setup SHA256:
  `E15E28E752804D759AEC56681A3622FC64A36E61364CE9A8A0B96362E9DF9608`
- Watchers setup SHA256:
  `6AF72FA248FFC68D6530A47A29C0D0FC16496B88D39B1B6A36FD638B052F2AF7`

Latest code/package commit pointers on `central-fork`:

- root `activitywatch` package commit: `0c657eb Package aggregate fleet chart fix`
- nested `aw-server`: `3a4762b Add aggregate fleet activity endpoint`
- nested `aw-server/aw-webui`: `e183471 Render aggregate fleet charts for long ranges`

This handoff may have a newer root docs-only commit after `0c657eb`; the setup hash above is the reliable identity for the packaged server installer.

The watcher setup is preconfigured for:

- `http://192.168.0.144:5600/`

Deployment behavior:

- server setup installs to `C:\Program Files\ActivityWatch Fleet Server`
- server starts as scheduled task `ActivityWatch Fleet Server`
- server binds to `0.0.0.0:5600` so the web UI/API can be reached from the LAN
- server runtime data is redirected to `C:\ProgramData\ActivityWatchFleet`
- server setup can now move an existing server database/runtime data directory during update; it prompts for an empty target folder, moves the data there, and stores the selected path in `HKLM\Software\ActivityWatchFleet\DataRoot` plus an install-folder `data-root.txt` fallback
- watcher setup installs AFK/window/session/audio watchers to `C:\Program Files\ActivityWatch Fleet Watchers`
- watcher setup registers scheduled task `ActivityWatch Fleet Watchers Supervisor` as `SYSTEM`; it launches the per-user watchers inside every active interactive user session and repeats once per minute to catch fast-user-switching/new logons
- watcher setup also creates an all-users Startup shortcut as a fallback
- watcher setup stages the per-user audio watcher and the system CPU/RAM watcher; CPU/RAM runs through a machine-level scheduled task named `ActivityWatch Fleet System Watcher`
- watchers use central mode against `192.168.0.144:5600`
- watcher request queues are file backed through `aw-client`, so temporary server/network outages are retried after the server returns

Validation done on this working machine:

- web UI build succeeded with `npm run build`
- built web UI assets were copied into `aw-server\aw_server\static`
- PyInstaller builds exist for server, AFK watcher, window watcher, session watcher, audio watcher, and CPU/RAM system watcher
- packaged `aw-server.exe --version` returns `v0.13.2.dev+e5983e5`
- packaged server starts on a test port and returns `/api/0/info`
- deployment setup builder completed successfully for the server setup after the latest web UI change
- watcher setup was not rebuilt for the latest server-only UI update
- non-admin smoke install into temp folders passed for both payloads

Important deployment caveats:

- these setup executables are unsigned
- this build machine was not verified to own `192.168.0.144`; the packages are prepared for the intended server machine with that address
- run setup files as Administrator on target machines
- after changing web UI code later, rebuild `aw-server\aw-webui`, copy assets into `aw-server\aw_server\static`, then rebuild/server-package again
- on this Windows build machine, PyInstaller may try to resolve a locked roaming profile path under `\\dc\profiles$`; set build-local `USERPROFILE`, `HOME`, `APPDATA`, `LOCALAPPDATA`, `TEMP`, `TMP`, `PYTHONNOUSERSITE=1`, and `PYINSTALLER_CONFIG_DIR` before running PyInstaller if that happens

Latest fleet UI fixes:

- fleet single-user range apply/refresh now shows a spinner and elapsed seconds while the user detail request is running
- fleet single-user activity summary now shows a lightweight loading panel with elapsed time, loaded bucket count, current bucket name, progress bar, cancel button, and restart button
- fleet single-user activity summary now loads matching watcher buckets sequentially instead of firing all long-range bucket event requests in parallel; this avoids the page appearing frozen for long ranges such as `mstep` from `2026-08-01` to `2026-08-24`
- canceling the fleet single-user activity summary calls the ActivityWatch web client's `abort()` hook so in-flight API calls are aborted and the request controller is reset
- after production testing showed the 24-day `mstep` range still took about 2 minutes and hover/click froze the browser after load, ranges over 7 days now render the same timeline/category diagram panels from server-side aggregate data via `/api/0/fleet/users/<username>/activity-summary` instead of sending raw window-event dumps to the browser
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
- fleet user detail view now has a direct user selector in the header so users can switch without returning to the fleet user list
- fleet summary filters now expose a checked-by-default `Subtract AFK time` checkbox; internally this reuses the existing inverse `fleetSummaryShowAfkTime` setting for compatibility
- fleet user summary shows a raw daily watcher timeline below the bar chart when the selected range is one day; watchers can be toggled on/off and swimlanes can be switched like the Timeline page
- fleet devices view now loads `/api/0/fleet/devices/metrics` and shows per-device CPU/RAM wave sparklines for the selected recent time window
- category edit now uses a full hue/saturation color picker with native color input and hex entry instead of the limited compact palette; dark-mode styling was added for the picker popover
- fleet user/device detail views now have a checked-by-default `Only count AFK while session is active` option; this is separate from the chart-only `Subtract AFK time` filter
- event edit modals now include a compact category rule creator: pick an event data field (`app`, `title`, `process_name`, `process_path`, etc.), generate/edit a regex, then append it to an existing category or create a new category path

Latest server summary fix:

- fleet user/device summary cards now merge overlapping state intervals per user/device/session before summing
- this fixes inflated AFK totals caused by duplicated overlapping `afkstatus` rows
- fleet user/device summaries can now exclude AFK intervals outside `sessionstate = active`; locked, disconnected, logged-in-only, logged-off, and no-session periods no longer inflate AFK totals when this option is enabled
- observed July 21 Stepik example before the fix: naive AFK row sum was about 12h 16m
- observed same range after the fix and stack restart: AFK card dropped to about 3h 17m at the time of verification
- regression coverage added in `aw-server\tests\test_server.py`
- fleet server tests passed with `python -m pytest -o addopts= aw-server\tests\test_server.py -k fleet`
- server PyInstaller output and deployment setup EXEs were rebuilt after this fix
- field-scoped category rule matching is covered by `npx jest --selectProjects node --runTestsByPath test/unit/classes.test.node.ts --coverage=false`

Current local notes:

- deployment setup EXEs were rebuilt after the 2026-07-22 fleet UI/raw event updates
- watcher setup was changed after a deployment bug where rerunning setup under one/admin user only started the installer user's watchers; the fixed setup uses the SYSTEM supervisor task to start watchers in each active logged-in user's own Windows session
- root `backups\` contains local runtime cleanup exports and is intentionally not part of the deployment build
- `aw-watcher-audio` now reports per-user playback/microphone activity and `aw-watcher-system` now reports CPU/RAM usage; watcher setup must be rebuilt and redeployed to watcher machines before audio/RAM data appears in fleet views

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
- new lightweight host metrics watcher package:
  - `aw-watcher-system`
- new lightweight per-user audio activity watcher package:
  - `aw-watcher-audio`

Important files:

- [aw-core/aw_core/identity.py](/E:/projects/activitywatch/aw-core/aw_core/identity.py)
- [aw-watcher-afk/aw_watcher_afk/afk.py](/E:/projects/activitywatch/aw-watcher-afk/aw_watcher_afk/afk.py)
- [aw-watcher-afk/aw_watcher_afk/config.py](/E:/projects/activitywatch/aw-watcher-afk/aw_watcher_afk/config.py)
- [aw-watcher-window/aw_watcher_window/main.py](/E:/projects/activitywatch/aw-watcher-window/aw_watcher_window/main.py)
- [aw-watcher-window/aw_watcher_window/config.py](/E:/projects/activitywatch/aw-watcher-window/aw_watcher_window/config.py)
- [aw-watcher-window/aw_watcher_window/lib.py](/E:/projects/activitywatch/aw-watcher-window/aw_watcher_window/lib.py)
- [aw-watcher-session/aw_watcher_session/main.py](/E:/projects/activitywatch/aw-watcher-session/aw_watcher_session/main.py)
- [aw-watcher-session/aw_watcher_session/windows.py](/E:/projects/activitywatch/aw-watcher-session/aw_watcher_session/windows.py)
- [aw-watcher-audio/aw_watcher_audio/main.py](/E:/projects/activitywatch/aw-watcher-audio/aw_watcher_audio/main.py)
- [aw-watcher-audio/aw_watcher_audio/windows.py](/E:/projects/activitywatch/aw-watcher-audio/aw_watcher_audio/windows.py)
- [aw-watcher-system/aw_watcher_system/main.py](/E:/projects/activitywatch/aw-watcher-system/aw_watcher_system/main.py)
- [aw-watcher-system/aw_watcher_system/windows.py](/E:/projects/activitywatch/aw-watcher-system/aw_watcher_system/windows.py)

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
- `aw-watcher-audio` reports aggregate audio playback and microphone endpoint state with session identity attached
- `aw-watcher-system` reports machine-level CPU/RAM load with `systemmetrics` events

Audio watcher notes for the builder machine:

- `aw-watcher-audio` is Windows-only and uses Windows Core Audio / WASAPI through `ctypes`
- it has no extra runtime dependency for the audio API and does not record, transcribe, or store audio content
- default sampling interval is 10 seconds, while unchanged state heartbeats flush every 30 seconds to keep traffic low
- default event data intentionally avoids raw level values; it reports state metadata such as `active`, `silent`, `no_device`, threshold, sampled roles, and device count
- it creates two per-user buckets: `audio.playback` and `audio.microphone`
- deployment starts it next to AFK/window/session inside each active interactive user session, not as the machine-level SYSTEM task
- `deploy\windows\build-setup.ps1` now requires `aw-watcher-audio\dist\aw-watcher-audio` and copies it into the watcher payload
- build the executable with `pyinstaller aw-watcher-audio.spec --clean --noconfirm` from `aw-watcher-audio` after dependencies are installed
- after building, rerun `.\deploy\windows\build-setup.ps1 -ServerHost 192.168.0.144 -ServerPort 5600` so `ActivityWatch-Fleet-Watchers-Setup.exe` actually contains the audio watcher

CPU/RAM watcher notes for the builder machine:

- `aw-watcher-system` is Windows-only and uses the native `GetSystemTimes` and `GlobalMemoryStatusEx` APIs through `ctypes`
- it intentionally avoids WMI/CIM, `Get-Counter`, and `psutil` to keep overhead minimal and avoid broken performance counter installations
- default sampling interval is 60 seconds
- event data includes `metric = system_load`, `cpu_percent`, `cpu_idle_percent`, `cpu_count`, `memory_percent`, `memory_used_bytes`, `memory_available_bytes`, `memory_total_bytes`, and `sample_seconds`
- deployment should run it once per computer, not once per logged-in user
- `deploy\windows\watchers\start-system-watcher.ps1` starts it as machine identity with `--username system --session-id machine --session-type machine`
- watcher setup creates the scheduled task `ActivityWatch Fleet System Watcher` as `SYSTEM` at startup; AFK/window/session watchers still use the all-users Startup shortcut per interactive user
- system watcher logs/pid are under `C:\ProgramData\ActivityWatchFleet`, while per-user watcher logs remain under `%LOCALAPPDATA%\ActivityWatchFleet`
- `deploy\windows\build-setup.ps1` now requires `aw-watcher-system\dist\aw-watcher-system` and copies it into the watcher payload
- build the executable with `pyinstaller aw-watcher-system.spec --clean --noconfirm` from `aw-watcher-system` after dependencies are installed
- after building, rerun `.\deploy\windows\build-setup.ps1 -ServerHost 192.168.0.144 -ServerPort 5600` so `ActivityWatch-Fleet-Watchers-Setup.exe` actually contains the CPU/RAM watcher

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
- `GET /api/0/fleet/devices/metrics`
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


## 10. Latest Local Work Notes

### 2026-08-24 aggregate long-range fleet charts

- The previous quick fix that paused detailed charts for ranges over 7 days has been removed. The user rejected that behavior, correctly: the diagram must still render.
- New backend endpoint: `GET /api/0/fleet/users/<username>/activity-summary`. It returns compact, chart-ready aggregate events plus per-bin active-session totals for the selected user/range/devices.
- Long single-user ranges now use server-side aggregate rows in `FleetActivitySummary.vue` instead of loading raw `currentwindow`/AFK/session buckets into the browser. Shorter ranges still use the raw watcher path so the detailed watcher timeline remains available.
- The aggregate response is intentionally event-shaped, so the existing frontend category rules, ignored-category filter, timeline barchart, category tree, top apps/titles/categories, and sunburst panels still render through the existing UI path.
- Aggregate payload size is capped adaptively per bin. Larger ranges keep fewer app/title/device rows per bin and roll the small tail into `Other`, so hover/click detail windows stay responsive.
- Verified: backend `py_compile`, fake-data smoke test of `summarize_user_activity`, `npm run build` in `aw-server\aw-webui`, PyInstaller server payload rebuild, server payload version check `v0.13.2.dev+e5983e5`, and rebuilt `dist\deployment\ActivityWatch-Fleet-Server-Setup.exe`.
- Latest server setup SHA256: `E15E28E752804D759AEC56681A3622FC64A36E61364CE9A8A0B96362E9DF9608`.
- Watcher setup was intentionally not rebuilt; its SHA256 stayed `6AF72FA248FFC68D6530A47A29C0D0FC16496B88D39B1B6A36FD638B052F2AF7`.
- Root package commit for that installer: `0c657eb Package aggregate fleet chart fix`. Any newer root commit can be treated as documentation-only unless its diff says otherwise.
- Left uncommitted on this machine: `deploy/windows/watchers/install-watchers.ps1` and `rebuild-watchers-setup.cmd`. They are not part of the rebuilt server installer.

### 2026-08-24 fleet loading feedback and server installer refresh

- Fleet single-user view (`aw-server/aw-webui/src/views/fleet/FleetUser.vue`) now shows loading state on header refresh and `Zeitraum anwenden`, including elapsed seconds and an abort button while the user detail request is in flight.
- Fleet single-user activity summary (`aw-server/aw-webui/src/views/fleet/FleetActivitySummary.vue`) now replaces the bare `Lädt...` text with a lightweight loading panel showing elapsed time, bucket progress, current bucket, progress bar, `Abbrechen`, and restart/refresh.
- Long-range summary loading now fetches candidate watcher buckets sequentially with progress instead of using one large `Promise.all`; this was done because ranges like `mstep` `2026-08-01` to `2026-08-24` could look stuck/unresponsive while raw events were loading.
- Follow-up after testing: the same 24-day range still loaded only after about 2 minutes, and hover/click interactions then froze the browser because the chart/category detail code had a huge raw window-event set. This was superseded the same day by the server-side aggregate endpoint described above.
- Interactive raw-event timeline/category charts are intentionally reserved for ranges of 7 days or less. Multi-week charts should use the server-side aggregate endpoint rather than sending raw window events to the browser.
- Cancel/restart uses the existing ActivityWatch web client `getClient().abort()` method. Cancelled requests are treated as expected cancellation, not as generic load failures.
- German i18n labels were added in `aw-server/aw-webui/src/i18n.ts` for the new loading/cancel/progress text.
- Verified `aw-server/aw-webui` with `npm run build`. The build completed successfully; warnings were the existing asset-size/browserslist/dependency warnings and a PowerShell profile access warning from npm.
- Rebuilt the web UI, copied `aw-server/aw-webui/dist/*` into `aw-server/aw_server/static`, rebuilt the PyInstaller server payload, and rebuilt only `dist/deployment/ActivityWatch-Fleet-Server-Setup.exe`.
- Packaged server payload check: `aw-server/dist/aw-server/aw-server.exe --version` returned `v0.13.2.dev+e5983e5`.
- Latest server setup SHA256 before the aggregate endpoint replacement: `5999E4ABFB64A75166FA1CDD2FA6C7CB714702726C1C9EE450EFF0CAF252A328`.
- Watcher setup was intentionally not rebuilt; its SHA256 stayed `6AF72FA248FFC68D6530A47A29C0D0FC16496B88D39B1B6A36FD638B052F2AF7`.
- Root package commit for that superseded installer: `a46d415 Package long-range fleet loading fix`.
- PyInstaller on this machine may fail with access denied resolving `C:\Users\mstep` or `\\dc\profiles$\mstep`. The successful run used local build env overrides:

```powershell
$repo = (Resolve-Path '..').Path
$buildHome = Join-Path $repo '.build-home'
New-Item -ItemType Directory -Force -Path $buildHome,(Join-Path $buildHome 'AppData\Roaming'),(Join-Path $buildHome 'AppData\Local'),(Join-Path $buildHome 'Temp'),(Join-Path $buildHome 'PyInstaller') | Out-Null
$env:USERPROFILE=$buildHome
$env:HOME=$buildHome
$env:APPDATA=Join-Path $buildHome 'AppData\Roaming'
$env:LOCALAPPDATA=Join-Path $buildHome 'AppData\Local'
$env:TEMP=Join-Path $buildHome 'Temp'
$env:TMP=$env:TEMP
$env:PYTHONNOUSERSITE='1'
$env:PYINSTALLER_CONFIG_DIR=Join-Path $buildHome 'PyInstaller'
& ..\.venv-build\Scripts\python.exe -m PyInstaller aw-server.spec --clean --noconfirm
```

- After that run, remove generated local-only folders `.build-home` and `aw-server/activitywatch` if they appear. They are build/runtime scratch data and should not be committed.

### 2026-08-24 fleet summary selection and server setup helper

- Fleet summary user selection was fixed in `aw-server/aw-webui`: loading a filtered summary no longer replaces the global fleet-user picker list, changing the range/users clears displayed results, and Redmine comparison data only appears after the explicit Redmine load button.
- Follow-up hardening: `FleetSummary.vue` now keeps a local `allUserOptions` pool loaded from `/fleet/users` and only merges users into it. Summary responses can no longer shrink the visible checkbox list, even if a store action mutates `fleetStore.users`.
- Added root double-click helper `rebuild-server-setup.cmd`, backed by `deploy/windows/rebuild-server-setup.ps1`.
- The helper performs the full server-only packaging path: rebuild web UI, copy `aw-server/aw-webui/dist/*` into `aw-server/aw_server/static`, rebuild `aw-server/dist/aw-server` with PyInstaller, then run `deploy/windows/build-setup.ps1 -Target Server`.
- The helper sets a local PyInstaller home to avoid profile permission errors and passes a process-local Git `safe.directory` setting so `vue.config.js` can read the web UI commit hash under Codex/sandbox ownership.
- Rebuilt and verified `dist/deployment/ActivityWatch-Fleet-Server-Setup.exe`. Server setup SHA256: `3B60E081A16A660CFB1831FF0A0C79C0485D6E8172BE6B9DE8CE2F5428FBC914`.
- Server payload check: `aw-server/dist/aw-server/aw-server.exe --version` returned `v0.13.2.dev+e5983e5`.
- Watcher setup was intentionally not rebuilt for this server-only refresh.
- Root package commit: `0dc2ffe Package complete fleet summary picker fix`.

### 2026-07-23 timeline audio/session readability

- Fleet user daily watcher timeline now labels audio watcher bars by audio state, same idea as session bars. Expected audio states include `active`, `silent`, `no_device`, and `error`.
- Audio watcher tooltips now show state, stream, active roles, device count, device name, and session when that data is present.
- Timeline detail popover now exposes a state color picker for state-driven bars:
  - session state bars use keys like `sessionstate:locked`
  - audio bars use keys like `audio.microphone:active`
- The chosen colors are persisted through the existing web UI settings store/server settings API in `timelineStateColorsData`, so the server remembers them as user preferences.
- Fleet summary block chart now auto-scrolls once after data load/refresh to the densest activity area. Manual user scrolling cancels any pending auto-scroll so the chart does not keep snapping back.
- Fleet user watcher timeline panel is shown for selected ranges up to about 3 days, not only single-day ranges. Larger ranges keep the panel hidden to avoid loading very large raw watcher timelines.
- Fleet user previous-day button imports its `arrow-left` icon explicitly; missing vue-awesome icon imports can surface as `Cannot read properties of undefined (reading 'paths')`.
- Fresh Windows setup EXEs were rebuilt after copying the web build into `aw-server/aw_server/static` and rebuilding `aw-server/dist/aw-server`.

### 2026-07-23 LDAP authentication draft

- Added optional LDAP/Active Directory authentication behind the existing `/api/0/auth/login` endpoint.
- Built-in local `admin` remains the fallback/break-glass account and does not fall back to LDAP if the password is wrong.
- Successful LDAP users are stored in `_auth_users` with `source: ldap`, canonicalized by `sAMAccountName`/UPN where available, and default to `is_admin: false`.
- Only the built-in `admin` user can access the auth-management endpoints/UI:
  - `/api/0/admin/auth/ldap`
  - `/api/0/admin/auth/ldap/test`
  - `/api/0/admin/auth/users`
- The settings UI now has an `Authentication and LDAP` section visible only to the built-in `admin` account.
- LDAP bind passwords are stored server-side but never returned to the browser; the UI can preserve or clear the saved password.
- Runtime dependency `ldap3` was added to `aw-server/pyproject.toml` and installed into the local build venv for packaging. `poetry.lock` was not regenerated because Poetry is not installed in this environment.

### 2026-07-23 fleet system-load waves

- Added a reusable opt-in CPU/RAM wave graph component backed by `/api/0/fleet/devices/metrics`; it only loads metrics after the user enables "Show system load".
- Single-device fleet view now has a hidden-by-default system-load graph tied to the selected date range.
- Fleet user watcher timeline now has the same optional system-load graph for the currently selected devices and range, so activity events can be compared with CPU/RAM spikes.
- Raw `systemmetrics` buckets are hidden from the watcher timeline rows; system data is shown through the wave graph instead.

### 2026-07-23 fleet summary navigation and setup refresh

- Fleet user range controls now show previous-day and next-day shortcuts above the date inputs; next-day is disabled once the selected end date is today.
- Fleet user summary now displays the overlap-collapsed active session time directly above the `Timeline (barchart)` panel. This uses `user.totals.active_seconds`, which is calculated by merging active session intervals across selected devices so overlapping active sessions count once.
- Verified the overlap behavior with:
  - `test_fleet_user_summary_merges_overlapping_state_events`
  - `test_fleet_user_summary_unions_active_sessions_across_devices`
- Fresh Windows setup EXEs were rebuilt after copying the web build into `aw-server/aw_server/static` and rebuilding `aw-server/dist/aw-server`.
- Historical setup hashes from that refresh, superseded by the 2026-08-24 status at the top of this file:
  - Server: `EA01182622F7335DD2E1AF41B1462DEBA9C100B8B515E9C95AA92813CBF1D86E`
  - Watchers: `784E854FCDA42BBB617938371E3C63208F4460757A8BB5041B8AA4DB51C218C6`
