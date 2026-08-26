# ActivityWatch Fleet

A Windows-focused fork of [ActivityWatch](https://github.com/ActivityWatch/activitywatch) turned into a **centralized multi-user, multi-device work-tracking system** for a small LAN fleet (~20 users / ~20 devices).

One central server collects events from watchers running on every fleet PC. The web UI is organized around **users and sessions**, not hostnames: who worked when, in which programs, active vs. AFK vs. locked vs. disconnected, compared day-by-day against the hours booked in Redmine.

- Central server + web UI: `http://192.168.0.144:5600/` (host `LS`)
- Development machine / repo: `C:\projecte_visual_code\activitywatch` (branch `central-fork`)
- Detailed work log and current state: [`ACTIVITYWATCH_HANDOFF.md`](ACTIVITYWATCH_HANDOFF.md)
- Deployment details: [`deploy/windows/README.md`](deploy/windows/README.md)

## Architecture

```
Fleet PC (each device)                         Server LS (192.168.0.144)
┌──────────────────────────────────┐           ┌──────────────────────────────────┐
│ Scheduled task (SYSTEM):         │           │ aw-server (PyInstaller, task)    │
│  supervise-watchers.ps1          │  HTTP     │  - REST API + fleet endpoints    │
│  - starts watchers in every      │  :5600    │  - LDAP login, roles             │
│    interactive user session      │ ────────► │  - per-day summary cache +       │
│  - reports watcher version,      │           │    nightly precompute            │
│    self-updates from the server  │           │  - Redmine (MySQL, read-only)    │
│ Per user session:                │           │  - watcher auto-update endpoints │
│  aw-watcher-afk / -window /      │           │  - aw-webui (built, static)      │
│  -session / -audio               │           │ Data: C:\ProgramData\            │
│ Per machine:                     │           │       ActivityWatchFleet         │
│  aw-watcher-system (CPU/RAM)     │           └──────────────────────────────────┘
└──────────────────────────────────┘
```

Every event carries identity metadata (`username`, `device_id`, `device_name`, `session_id`, `session_type`, `hostname`). `aw-watcher-session` is the source of truth for session state; the window watcher additionally captures the open document in Inventor and the folder open in Explorer. Watcher request queues are file-backed, so server outages are retried.

## Key features on top of upstream

- **Fleet views** (Flotte): live devices, users, devices with CPU/RAM waves, summary (Auswertung) over any user/device/date selection. The Geräte list shows every device the fleet has ever heard from — offline ones included, with their last-seen time and last known users — so a switched-off PC stays clickable through to its history.
- **Tagesvergleich**: per user and day, active session time vs. hours booked in Redmine, incl. project, comment, delta; usernames link into the single-user day view.
- **Meine Zusammenfassung**: a personal page (`/fleet/me`) answering "have I booked my hours" — range presets (Heute / Diese Woche / Letzter Monat …), tracked time vs. Redmine bookings with the difference graded green/amber/red, a per-day list comparing the two with that day's bookings and comments, and the range's projects ranked by time. A non-admin page: admins pick any user — themselves included — on the fleet Zusammenfassung instead.
- **Single-user view**: chunked per-day server-side summaries (multi-month ranges are cached and precomputed nightly), progress reporting (day X of Y, ETA), watcher timeline with system-load overlay, dynamic Y-axis.
- **Audited event editing** (admins): edit/extend/create/delete events in all watcher rows; every change carries a server-stamped audit trail (`$edits`, `$manual`); deletes go to a trash bucket and can be restored.
- **Multi-field category rules**: a categorization rule can require several fields at once — e.g. `app` matches `ApplicationFrameHost\.exe` **and** `title` matches the hosted program — so host processes that front many unrelated programs can be split into different categories. A category may carry additional independent rules, so its existing rule stays untouched when a conditioned rule routes more events into it. Editable from the event editor, the fleet activity view, and the category edit dialog; matching runs server-side in `aw-core` with rules compiled once.
- **Auth and roles**: LDAP/AD login with a local `admin` break-glass account; admin-only pages (Zeitachse, Rohdaten, Einstellungen, Administration); per-user page grants and start pages. Grants are Live / Zusammenfassung / **Eigene Zusammenfassung** / Benutzer / Geräte — *Eigene Zusammenfassung* opens **Meine Zusammenfassung** (above), a page of its own rather than the fleet table filtered to one row, so someone can see their own hours and Redmine comparison without seeing colleagues. The restriction is enforced server-side by rewriting the requested usernames, not by trusting the client. Every API route that a browser reads requires a login — there is no anonymous read path.
- **Settings split**: `/settings` (Allgemein) keeps local preferences; `/settings/connectors` (Verbindungen) holds the LDAP and Redmine connections, offered only to the built-in `admin` account. Redmine user auto-mapping reads `email_addresses` (Redmine ≥ 3.0) with `users.mail` as fallback, so accounts created after a Redmine upgrade auto-map by email like the older ones.
- **Device enrollment**: install the watchers and walk away — the device generates its own key, registers itself, and appears under `Administration → Geräte` as *Wartet auf Freigabe* with its IP and a key fingerprint. One click approves it; from then on that key is its credential. A pending device records locally and sends nothing, losing no data (events queue and flush on approval). Revoking a device removes its access immediately, without re-keying the rest of the fleet.
- **Machine authentication**: watchers and the update supervisor have no browser session, so they authenticate with a Bearer token — either their own enrolled key or a shared **fleet token** (`Administration → Fleet-Zugriffstoken`) provisioned by `install-watchers.ps1 -FleetToken <token>`. Enforcement ships **off** and must only be switched on once every device is approved or holds the token — otherwise those devices stop reaching the server.
- **Moving the server**: `Administration → Server umziehen` announces a new address and every device switches to it by itself, so the server can move to another computer or IP without visiting a single PC. The server refuses to announce an address that no ActivityWatch server answers on, and each device re-checks before switching and refuses to move to something it cannot reach — a typo cannot strand the fleet. Announce it while the *old* server is still reachable; the devices learn it from the update check they already run every minute.
- **Watcher updates**: the supervisor on every device polls the server once a minute, reports its package version, and installs newer packages headlessly (SHA256-verified). `Administration → Watcher-Updates` shows per-device versions and lets an admin **update devices manually** — tick checkboxes and press *Ausgewählte aktualisieren*, hit *Alle aktualisieren*, or use the per-row *Jetzt aktualisieren* button. A manual update bypasses the automatic switch and installs even when the version already matches, so it doubles as a repair. The panel also accepts direct package uploads, so watchers roll out fleet-wide without touching the server or any PC. *Aktuell* means the **package** is installed (`package-version.txt`), not that watcher processes run; the install runs detached, so the status shows "Ergebnis wird bestätigt" for up to a minute until the device confirms its new version. The SYSTEM supervisor genuinely restarts watchers into every session after an update (its launch path pins `PSModulePath` locally — a roaming-profile UNC there used to kill the launcher silently).
- **Canonical session vocabulary**: every watcher detects the real Windows session type (`console` / `rdp` / `virtual` / `machine`) through one shared helper, and the server normalizes on read, so one physical session is never labelled two different ways.
- **Crash-safe configuration**: `settings.json` — the only copy of the password hashes, the AD bind password and the Redmine credentials — is written atomically (temp file + fsync + rename) with a `.bak` generation the server recovers from automatically.

## Repository layout

| Path | What it is |
|---|---|
| `aw-server/` | **Submodule (forked)** — the central server; nested submodule `aw-server/aw-webui` (forked web UI) |
| `aw-core/`, `aw-client/` | Submodules (forked) — identity helpers, client queueing |
| `aw-watcher-afk/`, `aw-watcher-window/` | Submodules (forked) — window watcher includes Inventor/Explorer enrichment |
| `aw-watcher-session/`, `aw-watcher-audio/`, `aw-watcher-system/` | Custom watchers, plain directories in this repo |
| `deploy/windows/` | Build + install scripts (IExpress setups, supervisor, installers) |
| `rebuild-server-setup.cmd`, `rebuild-watchers-setup.cmd` | Double-click build chains (self-elevating) |
| `diagnose-watchers.cmd`, `collect-fleet-logs.cmd` | Fleet diagnostics helpers |
| `aw-qt/`, `aw-server-rust/`, `aw-tauri/`, `awatcher/`, `aw-notify/`, `aw-watcher-input/` | Upstream submodules, **unused** by the fleet deployment |
| `ACTIVITYWATCH_HANDOFF.md` | Detailed, dated work log + current status (start here) |
| `roadmap.md`, `fleet-sync-spec.md` | Original planning documents |

## Building and releasing

Prerequisites on the build machine: Python venv at `.venv-build` with PyInstaller, Node/npm for the web UI. All builds are done through the root `.cmd` scripts (they self-elevate and clear locked outputs):

1. **Watchers changed** → `rebuild-watchers-setup.cmd`
   packages all watcher PyInstaller dists into `dist\deployment\ActivityWatch-Fleet-Watchers-Setup.exe`, writes the auto-update `manifest.json` (version = SHA256 of `payload.zip`), and produces `dist\deployment\ActivityWatch-Fleet-Watchers-Update.zip`. When only the update zip is needed (or the setup exe is locked, e.g. open over the network share), `build-setup.ps1 -Target Watchers -SkipWatchersSetupExe` stages payload, manifest and zip without touching the exe.
2. **Distribute the watcher update** — either:
   - upload `ActivityWatch-Fleet-Watchers-Update.zip` in the admin GUI (`Administration → Watcher-Updates`) — no server rebuild needed, devices pick it up within a minute (when auto-update is enabled), or
   - run `rebuild-server-setup.cmd`, which embeds the latest watcher package into the server build, and reinstall the server.
3. **Server changed** → `rebuild-server-setup.cmd`
   builds the web UI, copies it into `aw_server/static`, stages the watcher package, builds the PyInstaller server, and packages `ActivityWatch-Fleet-Server-Setup.exe`. Install it on LS (re-running the setup is an update and preserves data).

After a server/UI deploy, hard-reload (`Ctrl+F5`) once. The server sends `Cache-Control: no-cache` for `index.html` and the JS/CSS bundles are content-hashed, so that is normally enough; if a browser still shows the old UI, use DevTools → Application → Storage → *Clear site data*. Note that despite `@vue/cli-plugin-pwa` emitting a `service-worker.js`, this UI never registers one — there is no service worker to unregister.

## Operations

- Supervisor log per device: `C:\ProgramData\ActivityWatchFleet\logs\supervisor.log`; headless installs: `...\logs\install-watchers.log`; per-user watcher logs: `%LOCALAPPDATA%\ActivityWatchFleet\logs\watchers`; the session launcher writes `%LOCALAPPDATA%\ActivityWatchFleet\logs\start-watchers.log`.
- A device missing from *Live* although its watchers run fine usually has a **skewed clock** (events land in the past and fall out of the freshness window) — check `w32tm /query /status`; the source must be the DC, not `Local CMOS Clock`.
- `diagnose-watchers.cmd` dumps a full watcher-state report on a device; `collect-fleet-logs.cmd` gathers logs from the fleet via admin shares into `diagnostics\`.
- Server data (SQLite + `settings.json`) lives under `C:\ProgramData\ActivityWatchFleet` on LS — **back it up**. `settings.json` is written atomically and keeps a `settings.json.bak` the server recovers from, but that only protects against the last bad write, not against a bad edit or a disk failure. A `settings.json.corrupt-<timestamp>` file means the server rejected an unreadable config and fell back — investigate rather than delete it.
- Device credential: `C:\ProgramData\ActivityWatchFleet\fleet-token.txt` — either the key the device generated at enrollment, or a shared token provisioned with `install-watchers.ps1 -FleetToken <token>` (omitting the switch keeps the existing one, so updates never lose it). `set-fleet-token.ps1`, shipped in the watcher payload, sets it after the fact.
- Announced server address: `C:\ProgramData\ActivityWatchFleet\server-endpoint.txt`. Present only after a server move has been announced; delete it to fall back to the address baked into the watcher package.
- Rolling out watchers: build → upload the `Update.zip` in `Administration → Watcher-Updates` → tick the devices and press *Ausgewählte aktualisieren* (or leave automatic updates on and wait a minute). Devices that have never reported show *Nie gemeldet* — those still need one manual installer run, because they are running a supervisor from before the auto-update feature and never poll the server.
- `commit-current-version.cmd` commits all pending changes across the nested submodules and the root repo in the right order.

## Upstream

Based on [ActivityWatch](https://activitywatch.net/) (MPL-2.0, see `LICENSE.txt`). This fork intentionally trades upstream generality (multi-platform, privacy-first single-user) for centralized Windows fleet tracking. The upstream host-centric views (`Activity`, `Search`, `Report`, `Graph`, `Trends`, `Alerts`, `Timespiral`, Query explorer) have had their routes removed — they are unreachable and no longer bundled — but the `.vue` files remain in the tree, so restoring one is a single entry in `src/route.js`. The Category Builder was removed outright (file and route) — categories are managed in `Einstellungen → Kategorisierung` and from the categorize dialogs.
