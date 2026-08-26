# ActivityWatch Fork Handoff

Date: 2026-08-25
Repo: `C:\projecte_visual_code\activitywatch`

## 0. Latest Status - 2026-08-25 (evening)

Everything below the old "Rebuild sequence" line has now been BUILT. The repo,
the watcher dists and both setup exes are in sync for the first time in several
rounds. What is left is the part that can only happen on the target machines:
installing the server on LS and running the watcher installer once per device.

### Freshly built artefacts (this round)

- Server setup SHA256: `B4F8A8396291EB96E990C92C3089BD6B20B1FFBE9888E2E22043003EB8060C85`
  (rebuilt 2026-08-26, latest build that day - THIS one is current: Meine
  Zusammenfassung page (non-admin only), settings split with aligned
  connector buttons, Redmine email auto-mapping fix, multi-field category
  rules (aw-core changed!), Category Builder removed, phantom-session
  identity fix, corrected token-panel texts, watcher timeline tree picker, honest
  update-status wording, embeds the DEPLOYED watcher package `673131b3...`
  (identity fix + installer elevation guard + Stop-Process/-Force +
  PSModulePath fixes); payload
  `v0.13.2.dev+e5983e5`. All earlier same-day SHAs are superseded.
  NOTE: `ActivityWatch-Fleet-Watchers-Setup.exe` is still the 2026-08-25
  build - the old exe was held open over the SMB share (System PID 4) and
  could not be replaced. The GUI rollout does not need it:
  `ActivityWatch-Fleet-Watchers-Update.zip` + `watchers-iexpress` staging
  are current (`build-setup.ps1` gained `-SkipWatchersSetupExe` for exactly
  this). Rebuild the exe with `build-setup.ps1 -Target Watchers` once the
  handle is closed (helper: `close-setup-lock.ps1` at the repo root,
  self-elevating, closes the SMB handle). NOTE: iexpress failed once at step 6/6 leaving a
  146KB stub exe + full ~CAB - deleting both and re-running
  `build-setup.ps1 -Target Server` alone fixed it.)
- Watchers setup SHA256: `2BA7E6A28F808C68B64E830126FBE4A12436799F73098E5DE1F1E7BD5A517D0C`
- Watchers update zip: rebuilt 2026-08-26, package version `0c5880e4aeb235796ee009426fc3186563f7c6b20b52fbf65a54b0e2055af6d0` (was 494DB2BC.../57a425e...)
- Watcher package version (= SHA256 of payload.zip, embedded in the server):
  `57a425e44a63ca18bc64a52415718bbc53d07a3ccaf023fef221205d443a1e0c`
- Watchers preconfigured for `http://192.168.0.144:5600/`
- All FIVE watcher PyInstaller dists were rebuilt. aw-core changed this round,
  so every watcher had to be rebuilt, not just aw-watcher-window.

### Steps 1-3 of the old rebuild sequence: DONE

1. All watcher dists rebuilt with PyInstaller. DONE
2. `build-setup.ps1 -Target Watchers` -> setup exe + `manifest.json` +
   `ActivityWatch-Fleet-Watchers-Update.zip`. DONE
3. `rebuild-server-setup.ps1` -> web UI built, copied into `aw_server/static`,
   watcher package embedded (step 4/6), PyInstaller server, setup exe. DONE

### Steps 4-5: STILL TO DO ON THE TARGET MACHINES

4. Install `ActivityWatch-Fleet-Server-Setup.exe` on LS once. Afterwards
   press Ctrl+F5 once in each browser.

   NOTE, corrected 2026-08-25: earlier revisions of this file said to
   "unregister the PWA service worker". That was never true for this fork. The
   build generates `service-worker.js` and links `manifest.json` (from
   `@vue/cli-plugin-pwa`), but NOTHING calls `serviceWorker.register()` - not
   in `src/main.js`, not in `index.html`, not in the built bundle, and not
   anywhere in tracked history. No service worker is ever installed, so there
   is nothing to unregister. The server also sends `Cache-Control: no-cache`
   for `/` and `/index.html`, and the JS/CSS are content-hashed, so a stale UI
   should not survive a hard reload. If one somehow does, use DevTools ->
   Application -> Storage -> "Clear site data"; that covers every cause.
5. Run `ActivityWatch-Fleet-Watchers-Setup.exe` ONCE per device by hand. This is
   unavoidable for the first hop: a device only learns about GUI-triggered
   updates once it runs the NEW supervisor, and the new supervisor can only
   arrive with a package install. From the second generation on, every rollout
   goes through the GUI.

   While doing that pass, decide about the fleet token (section 0.3). If you
   intend to switch token enforcement on, install with:

   ```
   install-watchers.ps1 -FleetToken <token from Administration -> Fleet-Token>
   ```

   Running the installer without `-FleetToken` keeps whatever token the device
   already has, so later updates never lose it.

   You can also skip `-FleetToken` entirely and use device enrollment
   instead (section 0.8): install, then approve each device under
   `Administration -> Geraete`. Nothing has to be carried to the machine.

### Smoke-tested against the PACKAGED binaries, not just the source

The built `aw-server.exe` was started on port 5699 and driven over HTTP:

- unauthenticated GETs of `/fleet/live`, `/fleet/users`, `/fleet/summary`,
  `/fleet/devices`, `/buckets/`, `/export`, `/settings` -> all 401
- machine endpoints (`watcher-update/manifest|payload|status`, bucket
  create/heartbeat/events, `fleet/sync/*`) -> reachable with enforcement off,
  401 without a token and 200 with the token once enforcement is on
- the fleet token does NOT unlock browser or admin endpoints (still 401)
- manual update round trip: request -> `manifest?hostname=` reports it (only to
  that device, case-insensitively) -> device acknowledges -> device reports the
  target version -> request clears automatically
- `settings.json` and `settings.json.bak` both written and both parseable
- one physical session with a legacy `interactive` window bucket and a `console`
  session bucket now resolves deterministically to `console`

Unit tests: **56 passed, 0 failed, 0 errors** - the suite is green for the first
time, from 5 failed / 18 passed / 15 errors at HEAD. `pytest tests/` also works
with the project's own coverage settings now. See section 0.11 for what was
wrong; one of the four failures turned out to be a real product bug.

## 0.1 Manual watcher updates from the GUI (new)

Administration -> Watcher-Updates now has a device table with checkboxes,
"Alle auswählen", "Ausgewählte aktualisieren", "Alle aktualisieren" and a
per-row "Jetzt aktualisieren" button.

How it works, and why it works this way: the server cannot push to a device. An
"update now" click writes a per-device pending request
(`_watcher_update_requests` in settings.json). The supervisor already polls
`GET /api/0/fleet/watcher-update/manifest` once a minute; it now appends
`?hostname=$env:COMPUTERNAME`, so the answer can carry that device's request.
No extra HTTP request, no inbound connection to the device.

Semantics worth knowing:

- A manual request bypasses the `auto_update_enabled` switch entirely.
- It also installs when the reported version already matches, so the button
  doubles as a repair/reinstall.
- It bypasses the 15-minute cooldown exactly ONCE, tracked by `request_id` in
  `%ProgramData%\ActivityWatchFleet\update\state.json`. A permanently failing
  install therefore falls back to the normal 15-minute rhythm instead of
  re-downloading the package every minute.
- The request clears itself when the device reports the target version. It also
  expires after `manual_update_ttl_minutes` (default 360) so a device that is
  switched off does not stay pending forever.
- Requests are keyed by lower-cased hostname, because `_watcher_update_status`
  is keyed by the raw `$env:COMPUTERNAME` while never-reported rows come from
  the fleet device name.
- Devices still running a pre-auto-update supervisor never poll at all. They
  show "Nie gemeldet", the checkbox cannot reach them, and the panel says so.
- "Alle aktualisieren" makes every device download payload.zip within the same
  minute. On ~20 devices over a LAN that is fine; the confirm dialog states the
  device count and warns about the short recording gap while watchers restart.

New endpoints: `POST /api/0/fleet/watcher-update/request` (admin) and `DELETE`
on the same path to cancel pending requests.

## 0.2 settings.json is now crash-safe (fixes section 5.7)

`Settings.save()` used to be `open(path, "w")` + `json.dump(indent=4)`. That
truncates the file to zero bytes before the first new byte exists, and
`indent=4` makes json.dump emit hundreds of small writes, so the window is wide.
`load()` had no recovery at all.

What that meant in practice - this file is the ONLY copy of the password hashes,
the AD bind password, the Redmine DB password, the per-user page grants and the
LDAP config:

- a crash / power loss / disk-full mid-write left a truncated or zero-byte file;
- `json.load` then raised out of `Settings.__init__`, i.e. before Flask was even
  constructed, so aw-server.exe died at startup and the scheduled task (AtStartup
  trigger only) never brought it back;
- and if the damaged file still parsed but had lost `_auth_users`,
  `_ensure_internal_defaults` silently recreated `admin` with the password
  `admin`, minted a new session secret and dropped LDAP/Redmine - a LAN-facing
  admin UI back on default credentials, with nothing logged;
- Flask runs `threaded=True` and `settings.py` had no lock, so two request
  threads could both be inside `open(path,"w")`, and a `del self.data[key]`
  landing inside another thread's `json.dump` raised "dictionary changed size
  during iteration" - corruption with no crash and no disk problem involved.

Now:

- `save()` serializes FIRST (so a concurrent mutation raises before the file is
  touched), writes a temp file in the same directory, `flush()` + `fsync()`,
  copies the current file to `settings.json.bak`, then `os.replace()` - atomic
  on NTFS - with a retry loop for the PermissionError you get while Defender or
  a backup agent holds the file. It never degrades to a truncating write.
- Identical payloads are skipped, so the several getters that normalize-and-save
  no longer rewrite the file for nothing.
- `load()` falls back to `settings.json.bak` when the primary is unreadable, and
  quarantines the unusable file as `settings.json.corrupt-<timestamp>` instead
  of overwriting it. The backup lags by exactly one save, so recovery loses at
  most the most recent change - never the accounts or the credentials.
- A `synchronized` decorator (re-entrant lock) serializes every mutator and every
  normalizing getter.
- Recreating the built-in admin now logs at ERROR instead of happening silently.

Still worth doing operationally: a daily copy of
`C:\ProgramData\ActivityWatchFleet` (the `.bak` only protects against the last
bad write, not against a bad admin edit), and a Defender exclusion for that
folder.

## 0.3 API authentication (replaces section 5.8)

Two corrections to what section 5.8 used to claim:

1. Fleet GETs were NOT open. `server.py::_enforce_api_auth` has required a login
   for every `/api` route except a small allowlist since April 2026. The old
   note was stale.
2. That allowlist had a real bug: `/api/0/fleet/watcher-update/*` was never added
   to it, so every supervisor poll was answered with 401. The watcher
   auto-update feature could not have worked in the field, and the admin device
   table would have stayed empty. Fixed this round.

The model is now explicit, in `server.py`:

- `PUBLIC_API_PATHS`: `/0/info` and the three `/0/auth/*` routes. `/0/info` stays
  open because every aw-client uses it as the "is the server up?" probe before
  it could authenticate.
- `MACHINE_API_PATHS` + bucket writes: watcher ingest (bucket create/PUT, events,
  heartbeat), the four watcher-update routes, and the two fleet-sync routes.
  These have no browser session, so they authenticate with the FLEET TOKEN
  (`Authorization: Bearer <token>`, or `X-AW-Fleet-Token`).
- Everything else - every fleet read, buckets, events, query, export, settings,
  all admin endpoints - requires a logged-in session (local `admin` or LDAP).
  The token deliberately does NOT unlock any of them.

The token lives in `_fleet_auth_config` and is generated on first access.
Administration -> Fleet-Zugriffstoken shows it, copies it, and rotates it.

ENFORCEMENT SHIPS OFF, ON PURPOSE. Turning `require_watcher_token` on before the
devices hold the token stops the whole fleet from recording. The switch has a
confirm dialog saying exactly that. Sequence: install the new watchers with
`-FleetToken <token>` everywhere, then flip the switch.

Device side:

- `install-watchers.ps1 -FleetToken <token>` writes
  `%ProgramData%\ActivityWatchFleet\fleet-token.txt` (Administrators/SYSTEM full,
  Users read). It sits outside the install dir, so a watcher update cannot lose
  it; omitting the parameter keeps the existing token.
- `aw-client` reads it via `AW_FLEET_TOKEN` -> that file -> `[server]
  fleet_token` in the aw-client config, and sends it as a Bearer token.
- The supervisor sends the same header on manifest/payload/installer/status.
- `aw-client`'s request queue now treats 401/403 as RETRYABLE. Previously an
  unexpected status meant "unknown error, not retrying" and the heartbeat was
  discarded, so a token misconfiguration would have silently destroyed data
  instead of queueing it.

Remaining known gap: the watcher-update payload is SHA256-verified against the
server manifest but not signed, so the server (by IP) is still trusted.

## 0.4 Session type labels are normalized (fixes section 5.3)

The mismatch was real and worse than section 5.3 suggested. `aw-watcher-session`
derived `console`/`rdp` from the WTS client protocol, while `aw-watcher-afk` and
`aw-watcher-window` shipped the literal default `"interactive"` and
`aw-watcher-audio`/`-system` shipped `""`, which `resolve_identity` rewrote to
`"interactive"`. Nothing reconciled them, so one physical session appeared as
"Sitzung 2 (console)" next to "Sitzung 2 (interactive)", and `/fleet/live` picked
whichever bucket the dict iteration reached first.

Canonical vocabulary, in `aw-core/aw_core/identity.py`:

- session_type: `console` | `rdp` | `virtual` | `machine` | `unknown`.
  `"interactive"` is gone as a stored value - it was never a session type, it was
  the absence of detection - and maps to `unknown`. `virtual` is new, for WTS
  protocol 1 (ICA/Citrix), which used to be mislabelled `interactive`.
- session state: `active` | `locked` | `disconnected` | `logged_in` |
  `no_session`. `logged_off` is produced by nothing in this repo and now aliases
  to `no_session` on read.

Applied at both ends, so no data migration is needed:

- WRITE: `resolve_identity()` is the single choke point every watcher goes
  through. It now calls `detect_windows_session_type()` (one WTS query on the
  process's own session) so afk/window/audio report the same real value the
  session watcher does. A stale on-disk `aw-watcher-afk.toml` saying
  `session_type = "interactive"` normalizes to `unknown` and therefore falls
  through to detection - upgraded devices are not pinned to the placeholder.
- READ: `fleet.get_bucket_identity()` and `_merge_identity()` normalize, and an
  event-level `interactive` can no longer overwrite a bucket-level `console`.
  `bucket_backfill` rewrites stored `session_type` values in place at startup.
- `/fleet/live` now prefers the sessionstate bucket for `session_type` instead of
  relying on dict order.

Cost: ~0.6 ms once per watcher process at startup, and ~1 microsecond per poll in
the session watcher. Nothing was added to any sampling loop.

## 0.5 Legacy upstream views are unreachable (fixes section 4 / 5.1)

The nav entries went on 2026-08-24; the routes are gone now, so typed URLs hit
NotFound too and the code is no longer bundled. Removed from `route.js`:
`/activity/:host/...` (parent plus both children), `/trends`, `/trends/:host`,
`/report`, `/query`, `/alerts`, `/timespiral`, `/search`, `/graph`.

Deliberately KEPT:

- `/stopwatch` - explicit fork decision in section 5.4: the code stays and the
  admin can re-enable it (`show_stopwatch_menu`); the route guard already
  redirects when that is off.
- `/dev` - developer diagnostics, now `adminOnly`.
- `/buckets`, `/buckets/:id`, `/timeline`, `/settings`, `/admin` - all now carry
  `meta.adminOnly` explicitly rather than relying only on the non-admin
  whitelist.

The `.vue` files are still in the tree, so restoring one is a single route entry.
Two follow-ups were needed for this to be safe:

- `landingPage.ts::resolveLandingPage` clamps a personal start page to
  `ADMIN_LANDING_PAGES`; an admin whose stored `landingpage` was
  `/activity/<host>` would otherwise have landed on the 404 page.
- `Header.vue` still built an `activityViews` array of `/activity/<host>` URLs in
  `mounted()` for a menu that no longer exists. Removed; the bucket-store prime
  it also did is kept.

Not done, deliberately: the now-orphaned component files
(`SelectableVisualization.vue`, `Timespiral.vue`, `ForceGraph.vue`,
`PeriodUsage.vue`, `stores/activity.ts`, ...) and their `main.js` registrations
are still present. They are lazy imports, so nothing fetches them; deleting them
is cosmetic and would make restoring a view harder.

## 0.6 aw-agent-windows: what it is, and why it stays parked

WHAT IT IS FOR. A laptop that is off the LAN (customer site, VPN down, server
rebooting) should still record locally and push everything it missed on
reconnect - exactly once, no gaps, no double-counted time. The design is
"local-first": every device runs its OWN aw-server on 127.0.0.1, the watchers
talk only to that, and `aw-agent-windows` is the only process that talks to
central. It scans the local database, turns local events into an immutable
numbered "outbox" log, and uploads that log in batches.

WHAT ACTUALLY EXISTS. The receiving half is complete and covered by tests in
`aw-server/tests/test_server.py`: `POST /api/0/fleet/sync/handshake` and
`/batch`, a per-stream `last_acked_seq` cursor, all-or-nothing transactional
batches, and idempotent upsert keyed by `(stream_id, source_event_id)` plus
version and checksum, so a resend after an ambiguous network failure is provably
harmless. There is even self-healing repair of duplicates from markers embedded
in the events. On the device side the durable outbox schema, the stable agent
identity, the handshake/batch client and the batch sizing all exist.

WHAT IS MISSING. The one piece that reads the local database and writes into the
outbox. `local_scan.py` does not exist; nothing anywhere calls
`enqueue_bucket_upsert`, `enqueue_event_upsert` or `record_source_event_state` -
those functions have zero call sites. So `main.py` finds no streams, returns
immediately, and the agent logs "uploaded_ops=0" every 10 seconds forever. It is
a no-op today.

IS IT REDUNDANT? Partly, and honestly so. `aw-client` already has a durable
file-backed queue (`persistqueue`, SQLite on disk) and every watcher in this fork
uses `queued=True`, so "server down for an hour" is already covered. What the
agent would add that the queue structurally cannot:

- an idempotency key - the queue has none, so an ambiguous failure means either a
  lost or a double-sent event, with no way to tell. On data that feeds time
  reporting, silently double-counted hours are a business problem, not just a
  technical one.
- no silent data loss - the queue discards anything the server 400s and anything
  that raises unexpectedly, permanently, with only a log line. (This round
  narrowed that: 401/403 are now retried rather than discarded.)
- auditability - "how far behind is this machine?" has no answer today.

COST TO FINISH. The scanner itself is small, roughly 150-250 lines plus wiring;
call it 1-2 days. That is not the real cost. Making it deliver its promise also
needs exponential backoff, outbox pruning, 409/400 handling in the agent,
sync-status endpoints, packaging into the installers (it is in no build file
today), and - the big one - installing a local aw-server on every device and
repointing every watcher at 127.0.0.1. That is a fleet-wide rollout,
realistically 2-4 weeks including staged deployment.

RECOMMENDATION. On a reliable LAN the aw-client queue is adequate; leave the
agent parked. Finish it if the fleet gains genuinely disconnected machines, or if
this data ever drives billing or payroll. Either way: running the agent as
designed WITHOUT first moving the watchers to a local aw-server would
double-write events - `fleet-sync-spec.md` warns about exactly that.

## 0.8 Device enrollment (devices register, admin approves)

Replaces carrying a secret to every machine. Install the watcher setup and walk
away; the device asks to join and you approve it in the GUI.

Flow:

1. On first start the supervisor generates a 256-bit key, stores it in
   `%ProgramData%\ActivityWatchFleet\fleet-token.txt` (the same file the shared
   token uses, so `aw-client` needed no change at all) and POSTs it to
   `/api/0/fleet/enroll` with hostname and package version.
2. The device appears under `Administration -> Geräte` as *Wartet auf Freigabe*,
   with its IP, first-seen time and a short key fingerprint.
3. One click approves it. From then on that key is its credential, sent as the
   same `Authorization: Bearer` header the shared token uses.

Properties worth knowing:

- **Enrolling grants nothing.** A pending device is refused by the same auth
  gate as an unknown caller. Verified: with enforcement on, a pending key gets
  401 and the same key gets 200 immediately after approval.
- **Nothing is lost while pending.** aw-client queues events to disk, and 401/403
  are retryable since section 0.3, so a device records from minute one and
  flushes on approval.
- **Only the SHA256 of the key is stored**, and it doubles as the record id, so
  authenticating a request is one dict lookup. SHA256 rather than a password KDF
  is correct here because the key is 256 bits of randomness, not a human-chosen
  secret - and a KDF per heartbeat would be far too slow.
- **Re-enrolling is idempotent** and never downgrades an approved device, so the
  supervisor can re-post on every start.
- **The open endpoint is capped** at `MAX_PENDING_DEVICES` (200) so nobody on the
  LAN can grow settings.json without bound.
- Revoking sets the device back to rejected; access disappears immediately.
- A re-imaged device loses its key and reappears as pending - correct, but
  expect it and compare the fingerprint before approving.

The shared fleet token still works and remains the break-glass path. Enrollment
is additive: same header, same file, same server-side check.

New endpoints: `POST /0/fleet/enroll` and `GET /0/fleet/enroll/status` (both
public, by necessity), `GET|POST|DELETE /0/fleet/devices/enrollment` (admin).

## 0.9 Moving the server to another machine / IP

Before this, the server address was baked into the watcher package at build time
(`build-setup.ps1 -ServerHost`), so moving the server meant rebuilding the
watchers AND visiting every device - and there was a trap: devices poll the OLD
server for updates, so retiring it first left no way to tell them anything.

Now `Administration -> Server umziehen` announces the new address, and devices
pick it up from the manifest they already poll every minute.

Correct order (the GUI states it too):

1. Start the new server and give it the fleet data. Restoring
   `C:\ProgramData\ActivityWatchFleet` also carries the token and the approved
   device keys across, so devices keep working without re-approval.
2. On the OLD server - still reachable by the devices - announce the new
   address.
3. Wait until `Administration -> Watcher-Updates` shows the devices reporting to
   the new server.
4. Retire the old server.

Two independent safety checks, because a wrong address here strands the fleet:

- The **server** refuses to announce an address unless an ActivityWatch server
  actually answers `/api/0/info` there. (Override with "announce anyway" only if
  you know the new server is not up yet.)
- Each **device** verifies the announced address itself before switching, and
  refuses to move to something it cannot reach - so a typo, or a server the
  device cannot route to, leaves it exactly where it was. Verified against two
  live servers: a dead address is logged and ignored, a live one is adopted.

Device side: the override lives in
`%ProgramData%\ActivityWatchFleet\server-endpoint.txt`, outside the install
directory, so a watcher update cannot lose it. `supervise-watchers.ps1`,
`start-watchers.ps1` and `start-system-watcher.ps1` all read it and fall back to
the baked-in address when it is missing or malformed. After a switch the
supervisor stops the watchers so they restart against the new address - they
read `--host`/`--port` only at startup.

Clearing the announcement does NOT move devices back; devices that already
switched keep the new address. Only clear it once the whole fleet has moved.

## 0.11 The test suite is green (and one failure was a real bug)

The suite had 5 failures and 15 errors at HEAD. All of them are fixed. What each
one actually was:

**1. A real product bug: a device showed no users for any past range.**
`summarize_device` derived its user list from `summarize_live_state`, which only
keeps sessions updated within the last two minutes. So opening
`/fleet/devices/<id>` for yesterday, last week, or any historical range listed
*no users at all* - the page silently looked empty rather than wrong. It now
takes the users with watcher activity in the SELECTED RANGE, unioned with
whoever is logged in right now (`_users_seen_on_device`). It runs inside the
request-scoped event cache and reads bucket identity rather than scanning every
event, so it costs effectively nothing. Regression test:
`test_fleet_device_lists_users_for_a_past_range` - verified to fail against the
old code and to also assert that a quiet range does not invent users.

**2. `tests/test_client.py` had nothing to connect to.** Those tests use a real
HTTP client against the "server-testing" profile (127.0.0.1:5666), and upstream
expects you to have started `aw-server --testing` by hand - so on a clean
checkout they always failed with ConnectionError, taking 12 errors with them.
`tests/conftest.py` now starts a real server on that port in a daemon thread for
the session, and reuses an already-running one if it finds it.

**3. The test server has to use the same storage as the real server.** Started
with `AWFlask`'s default (memory), `test_get_events_interval` failed: peewee
clips an event's duration to the queried range (`storages/peewee.py`), the
in-memory store does not. `aw_server/config.py` sets `storage = "peewee"` for
both profiles, so the fixture now passes peewee explicitly and the HTTP tests
exercise what actually ships.

**4. A locked testing database could abort server startup.** With two testing
servers alive, `FleetSyncStore`/`FleetSummaryStore`'s `os.remove()` of their
testing DB hit `PermissionError` on Windows and propagated out of
`ServerAPI.__init__`, killing construction. Both now log and carry on. That is a
product robustness fix, not only a test fix: an antivirus scan or a stale handle
could do the same thing on a real machine.

**5. Two dev dependencies were missing from `.venv-build`.** `pytest-benchmark`
(3 errors) and `pytest-cov` - both declared in `pyproject.toml`, neither
installed. Installed.

Two stale assertions were also updated (they predate this round): the admin
UI-config tests still expected the pre-landing-page shape.

Running the suite:

```
.venv-build\Scripts\python.exe -m pytest tests/ -q
```

from `aw-server`. It is self-contained now - no server needs to be started
first, and it is stable across repeated runs.

## 0.13 "Eigene Zusammenfassung" - the summary page, own row only

A fifth per-user page grant next to Live / Zusammenfassung / Benutzer / Geraete
in `Administration -> Benutzer und Seiten-Zugriff`. It opens the SAME
Zusammenfassung page, restricted to the user's own data - so someone can see
their own active time and Redmine comparison without seeing any colleague.

Grant key: `fleet-summary-own`. It is an alternative to `fleet-summary`, not an
addition; ticking one unticks the other in the admin table, because the server
lets the wider grant win and showing both ticked would be a lie.

How the restriction is enforced - this is the part that matters:

- `rest._authorize_fleet_summary_scope()` returns the username the request must
  be limited to (or None for admins / the full grant), and the endpoints then
  OVERWRITE the requested usernames with it. It does not reject a request that
  names someone else, it rewrites it - so there is no way to phrase a request
  that leaks another user, and no client bug can widen the scope.
- Applied to `GET /0/fleet/summary`, `POST /0/fleet/redmine-comparison`,
  `POST /0/fleet/redmine-daily-comparison` and
  `POST /0/fleet/summary/precompute`.
- Tested, including a deliberately regressed build to confirm the test catches
  a leak: `test_own_summary_grant_cannot_see_other_users`,
  `test_full_summary_grant_is_not_restricted`,
  `test_summary_needs_one_of_the_two_grants`.

Two holes were closed in passing, both found while wiring this up:

- `POST /0/fleet/summary/precompute` had NO authorization beyond "logged in".
  Any non-admin could have forced a fleet-wide recompute for arbitrary
  usernames. It is now scoped exactly like reading.
- `GET|POST /0/fleet/summary/precompute/config` - the server-wide nightly
  precompute settings - were equally open, and are now admin-only. They are
  only used by the admin-only Einstellungen page.

Front end: `FleetSummary.vue` gains `ownSummaryOnly`. When set it skips
`/0/fleet/users` entirely (that endpoint needs the `fleet-users` grant, which
these users do not have), pins the selection to the logged-in user, hides the
user picker, and shows "Auf dieser Seite werden nur deine eigenen Daten
angezeigt." The route guard (`isNonAdminPathAllowed`) and the FleetNav pill
accept either summary grant, and `fleet-summary-own` is selectable as a start
page once granted.

RESOLVED 2026-08-26: it is a page of its own now - see section 0.16. The
grant, and the server-side scoping described above, are unchanged.

## 0.16 "Meine Zusammenfassung" is its own page (finishes 0.13)

The own-summary grant used to open `/fleet/summary` with every other user
filtered out: a one-row table, a hidden user picker and a sentence explaining
that the rest was missing. It was correct and it was safe, but it read like a
page someone had been locked out of rather than a page written for them.

There is now `/fleet/me` (`FleetMySummary.vue`), built for one person:

- range presets - Heute / Gestern / Diese Woche / Letzte Woche / Dieser Monat /
  Letzter Monat - instead of two date fields and a Load button as the only way
  in. It opens on the current week.
- four figures at the top: aktive Sitzungszeit (with the AFK-subtracted value
  underneath), in Redmine gebucht, the difference, and the number of days with
  activity plus the average per such day.
- "Meine Tage": one block per day, newest first, each with a two-bar comparison
  (tracked vs booked, scaled against the busiest day in the range) and that
  day's bookings with project and comment. The date links into the own
  single-user view for that day.
- "Meine Projekte": the range's Redmine projects ranked by time, with a share
  bar.
- the difference is graded rather than just signed: within 15 min green, within
  an hour amber, beyond that red - the question this page answers is "have I
  booked my hours", so it should answer it at a glance.

No new endpoints and no new authorization. It reads `/0/fleet/summary`,
`/0/fleet/redmine-comparison` and `/0/fleet/redmine-daily-comparison`, all three
already scope-rewritten server-side by `_authorize_fleet_summary_scope`
(section 0.13). The page pins the username to the logged-in user as well, but
that is cosmetic - the server would rewrite it anyway.

Routing, and the one thing to be careful about:

- `FLEET_PAGE_PATHS['fleet-summary-own']` now points at `/fleet/me`, and the
  non-admin whitelist lets `fleet-summary` open BOTH pages while
  `fleet-summary-own` opens only the personal one. If that mapping ever slips
  back to `/fleet/summary`, an own-only user lands on the fleet-wide table -
  scoped by the server, so not a leak, but wrong. That is what
  `test/unit/landingPage.test.node.ts` guards.
- `/fleet/summary` redirects to `/fleet/me` for own-only users, so old bookmarks
  and stored landing pages still work.
- REVERSED 2026-08-26 (same day): admins do NOT get the page. They pick any
  user - themselves included - on the fleet Zusammenfassung, so the personal
  page is non-admin only: no nav pill, no start-page option, `/fleet/me`
  redirects admins to `/fleet/summary`, and a stale `fleet-summary-own`
  start-page override degrades to the fleet table.
- `FleetSummary.vue` lost its `ownSummaryOnly` branch entirely - the fleet table
  is the fleet table again.

One server change was needed, and it is worth knowing about on its own:
`get_fleet_redmine_daily_comparison` used to return ZERO days when Redmine was
disabled or unreachable. The per-day list is the substance of the personal page,
and how long someone worked each day does not depend on Redmine, so the days are
now returned either way - with `redmine_seconds`/`delta_seconds` as `null` and
`matched: false`, exactly like a user who has no Redmine account. `enabled` and
`message`/`error` still say why the booked column is empty. A failed lookup
resets the matched set first, so a Redmine outage can never render as "matched,
booked nothing". The Tagesvergleich on the fleet page benefits from the same
change. Covered by
`test_daily_comparison_returns_days_without_redmine`.

Tests: 57 passed in `aw-server` (was 56), 41 in `aw-webui` (was 32), covering
the grant-to-path mapping, the own-row selection, the per-day mapping, the
tolerance grading and the range presets. Verified against a real server on
port 5699 with seeded events: the daily endpoint returns seven working days
with tracked time while Redmine is off.

## 0.14 Geraete lists offline devices too

The Geraete page only ever listed devices with a session updated in the last
two minutes, because `summarize_devices` was built from `summarize_live_state`.
A PC that was switched off vanished from the list completely - and since the
list is the only way into `/fleet/devices/<id>`, its entire history became
unreachable from the UI.

`summarize_devices` now enumerates every device the fleet has ever heard from.
It reuses `_load_live_snapshots`, which already walks every watcher bucket and
reads one latest_event each, and shares the request-scoped event cache with the
live pass - so this is not a second trip to the datastore.

Rows for devices that are not currently live get:

- `status: "offline"` (the badge renders grey; "offline" added to the German
  labels next to online/veraltet)
- `last_seen` from the newest event across that device's buckets
- `users` = the users last seen on it, so the row still says whose PC it is
- `session_count: 0`

This is the same root cause as the device-detail bug in section 0.11 - live
state being used where a range was meant. Both are fixed; both have regression
tests (`test_devices_list_includes_offline_devices` also asserts the detail
page it links to returns real historical data).

Note the Systemlast sparkline stays empty for an offline device under the
default "Letzte 2 Stunden" range, which is correct - widen the range on the
device page to see its history.

## 0.15 Key deployment facts (unchanged)

- Server installs to `C:\Program Files\ActivityWatch Fleet Server`, runs as
  scheduled task `ActivityWatch Fleet Server`, binds `0.0.0.0:5600`, data under
  `C:\ProgramData\ActivityWatchFleet` (movable via installer prompt /
  `HKLM\Software\ActivityWatchFleet\DataRoot`).
- Watchers install to `C:\Program Files\ActivityWatch Fleet Watchers`; SYSTEM
  task `ActivityWatch Fleet Watchers Supervisor` starts per-user watchers in
  every interactive session once a minute (plus all-users Startup shortcut
  fallback); machine-level task `ActivityWatch Fleet System Watcher` samples
  CPU/RAM.
- Both installers self-elevate, prompt once, abort correctly on X-close, verify
  watcher startup, and are headless-safe for the auto-update path.
- Client queues are file-backed (`aw-client`), so server outages are retried.
- Setup exes are unsigned; run as Administrator on targets. First start after
  install can be slowed by Defender scanning fresh PyInstaller exes.
- PyInstaller on this build machine needs the build-home env overrides (locked
  roaming profile under `\\dc\profiles$`) - `rebuild-server-setup.ps1` sets them
  automatically. Remove the generated `.build-home` and `aw-server/activitywatch`
  folders afterwards if they appear.

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
Set-Location 'C:\projecte_visual_code\activitywatch'
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

- [aw-core/aw_core/identity.py](/C:/projecte_visual_code/activitywatch/aw-core/aw_core/identity.py)
- [aw-watcher-afk/aw_watcher_afk/afk.py](/C:/projecte_visual_code/activitywatch/aw-watcher-afk/aw_watcher_afk/afk.py)
- [aw-watcher-afk/aw_watcher_afk/config.py](/C:/projecte_visual_code/activitywatch/aw-watcher-afk/aw_watcher_afk/config.py)
- [aw-watcher-window/aw_watcher_window/main.py](/C:/projecte_visual_code/activitywatch/aw-watcher-window/aw_watcher_window/main.py)
- [aw-watcher-window/aw_watcher_window/config.py](/C:/projecte_visual_code/activitywatch/aw-watcher-window/aw_watcher_window/config.py)
- [aw-watcher-window/aw_watcher_window/lib.py](/C:/projecte_visual_code/activitywatch/aw-watcher-window/aw_watcher_window/lib.py)
- [aw-watcher-session/aw_watcher_session/main.py](/C:/projecte_visual_code/activitywatch/aw-watcher-session/aw_watcher_session/main.py)
- [aw-watcher-session/aw_watcher_session/windows.py](/C:/projecte_visual_code/activitywatch/aw-watcher-session/aw_watcher_session/windows.py)
- [aw-watcher-audio/aw_watcher_audio/main.py](/C:/projecte_visual_code/activitywatch/aw-watcher-audio/aw_watcher_audio/main.py)
- [aw-watcher-audio/aw_watcher_audio/windows.py](/C:/projecte_visual_code/activitywatch/aw-watcher-audio/aw_watcher_audio/windows.py)
- [aw-watcher-system/aw_watcher_system/main.py](/C:/projecte_visual_code/activitywatch/aw-watcher-system/aw_watcher_system/main.py)
- [aw-watcher-system/aw_watcher_system/windows.py](/C:/projecte_visual_code/activitywatch/aw-watcher-system/aw_watcher_system/windows.py)

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

- [aw-server/aw_server/api.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/api.py)
- [aw-server/aw_server/rest.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/rest.py)
- [aw-server/aw_server/server.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/server.py)
- [aw-server/aw_server/settings.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/settings.py)
- [aw-server/aw_server/fleet.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/fleet.py)
- [aw-server/aw_server/fleet_sync.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/fleet_sync.py)
- [aw-server/aw_server/fleet_sync_store.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/fleet_sync_store.py)
- [aw-server/aw_server/bucket_backfill.py](/C:/projecte_visual_code/activitywatch/aw-server/aw_server/bucket_backfill.py)

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

- [aw-agent-windows/aw_agent_windows/main.py](/C:/projecte_visual_code/activitywatch/aw-agent-windows/aw_agent_windows/main.py)
- [aw-agent-windows/aw_agent_windows/config.py](/C:/projecte_visual_code/activitywatch/aw-agent-windows/aw_agent_windows/config.py)
- [aw-agent-windows/aw_agent_windows/identity.py](/C:/projecte_visual_code/activitywatch/aw-agent-windows/aw_agent_windows/identity.py)
- [aw-agent-windows/aw_agent_windows/outbox.py](/C:/projecte_visual_code/activitywatch/aw-agent-windows/aw_agent_windows/outbox.py)
- [aw-agent-windows/aw_agent_windows/sync_client.py](/C:/projecte_visual_code/activitywatch/aw-agent-windows/aw_agent_windows/sync_client.py)
- [aw-agent-windows/README.md](/C:/projecte_visual_code/activitywatch/aw-agent-windows/README.md)

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

- [aw-server/aw-webui/src/i18n.ts](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/i18n.ts)
- [aw-server/aw-webui/src/views/Login.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/Login.vue)
- [aw-server/aw-webui/src/stores/auth.ts](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/stores/auth.ts)
- [aw-server/aw-webui/src/stores/adminUi.ts](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/stores/adminUi.ts)
- [aw-server/aw-webui/src/stores/fleet.ts](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/stores/fleet.ts)
- [aw-server/aw-webui/src/util/bucketIdentity.ts](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/util/bucketIdentity.ts)
- [aw-server/aw-webui/src/views/Timeline.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/Timeline.vue)
- [aw-server/aw-webui/src/visualizations/VisTimeline.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/visualizations/VisTimeline.vue)
- [aw-server/aw-webui/src/views/Bucket.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/Bucket.vue)
- [aw-server/aw-webui/src/views/Buckets.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/Buckets.vue)
- [aw-server/aw-webui/src/views/fleet/FleetOverview.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/fleet/FleetOverview.vue)
- [aw-server/aw-webui/src/views/fleet/FleetUsers.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/fleet/FleetUsers.vue)
- [aw-server/aw-webui/src/views/fleet/FleetUser.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/fleet/FleetUser.vue)
- [aw-server/aw-webui/src/views/fleet/FleetDevices.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/fleet/FleetDevices.vue)
- [aw-server/aw-webui/src/views/fleet/FleetDevice.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/views/fleet/FleetDevice.vue)
- [aw-server/aw-webui/src/components/Header.vue](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/components/Header.vue)
- [aw-server/aw-webui/src/route.js](/C:/projecte_visual_code/activitywatch/aw-server/aw-webui/src/route.js)

Current timeline behavior:

- filter by user
- filter by device
- filter by duration
- select individual watcher/session buckets
- when one user is selected and device is "all devices", timelines stack by device
- hover details now render in a details area below the timeline instead of blocking the chart
- legacy stopwatch bucket is filtered out of the timeline view


## 4. Current Functional Direction

RESOLVED 2026-08-25 - see section 0.5.

The fork used to mix two worlds: the new session-aware / user-aware fleet
functionality, and the old upstream host-centric ActivityWatch views (`Activity`,
`Report`, `Search`, `Graph`, `Trends`, `Alerts`, `Timespiral`, the Query
explorer). The old views were unlinked from the navigation on 2026-08-24 and
their routes were removed on 2026-08-25, so they are no longer reachable at all
and their code is no longer bundled.

What remains is one genuine host-centric leftover, not a whole world: the shared
query components under `src/queries.ts` and `components/QueryOptions.vue` still
carry per-host assumptions. `QueryOptions.vue` is now only used by
`settings/CategoryBuilder.vue`, so the blast radius is small.


## 5. Known Issues / Incomplete Areas

### 5.1 GUI is session-first now; query helpers are the leftover

RESOLVED for the views - see section 0.5. Fleet views, timeline and bucket
identity handling are session-aware and user-aware, and every host-centric view
is gone.

Still carrying per-host assumptions:

- `src/queries.ts` and `components/QueryOptions.vue` (used only by the category
  builder)
- some older bucket grouping helpers in the stores


### 5.2 `aw-agent-windows` is incomplete

Unchanged, and now explained in full in section 0.6 - what it is for, what
exists, what is missing (the local bucket scan into the outbox; those enqueue
functions have zero call sites), whether it is redundant given the aw-client
queue, and what finishing it would actually cost. Short version: the receiving
half is complete and tested, the sending half is a no-op, and the expensive part
is not the code but rolling out a local aw-server to every device.


### 5.3 Session type mismatch

RESOLVED 2026-08-25 - see section 0.4. There is now one canonical vocabulary
(`console` / `rdp` / `virtual` / `machine` / `unknown`), every watcher detects
the real Windows session type through the same helper, and the server normalizes
on read so existing history renders consistently without a migration.
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


### 5.6 Deployed binaries lag the repo

The repo regularly runs ahead of the deployed exes (see section 0). Before debugging a "missing feature", check the deployed setup hashes first — that has repeatedly masqueraded as a code bug. (The other suspect this section used to name, a PWA service worker, does not exist: see the note in section 0. Browser caching is still worth a Ctrl+F5, but there is no service worker to unregister.)

### 5.7 settings.json robustness

RESOLVED 2026-08-25 - see section 0.2. `save()` is now temp file + fsync +
`os.replace` with a `.bak` generation, `load()` recovers from that backup and
quarantines an unusable file instead of overwriting it, and every mutator runs
under a re-entrant lock.

Still open, operationally rather than in code: nothing automates a daily backup
of `C:\ProgramData\ActivityWatchFleet`. The `.bak` protects against the last bad
write, not against a bad admin edit or a disk failure.

### 5.8 API authentication

REWORKED 2026-08-25 - see section 0.3. The claim this section used to make ("most
`/api/0/fleet/*` GET endpoints require no login") was stale: the global
`_enforce_api_auth` gate has required a session since April 2026. What was
genuinely open was machine traffic, and the watcher-update routes were
accidentally NOT in the allowlist, so the supervisor was being 401'd.

Now: browser endpoints need a login (local or LDAP); machine endpoints
(watcher ingest, watcher update, fleet sync) authenticate with the fleet token;
the token unlocks nothing else. Token enforcement ships OFF and must be switched
on only after every device has been given the token.

Remaining known gap: the watcher-update payload is SHA256-verified against the
server manifest but not signed, so the server (by IP) is still trusted.

## 6. Important Decisions Already Made

- Privacy is not treated as a blocker for this fork.
- Windows username is sufficient identity for now.
- Session correctness matters more than elegant abstraction.
- Explorer path tracking is enough for now; broad app-specific open-file extraction is deferred.
- Small-fleet simplicity is preferred over heavy optimization.
- Backward compatibility with upstream/local ActivityWatch is useful, but this fork should bias toward central multi-user correctness.


## 7. Recommended Next Steps For A New Chat

If a new chat needs a concrete next slice, the highest-value order is:

1. DEPLOY. Install the freshly built server setup on LS, then run the watcher
   setup once per device (section 0). Verify on ONE device first: that it shows
   up under Administration -> Watcher-Updates with a reported version, that
   ticking its checkbox and pressing "Jetzt aktualisieren" installs within a
   minute, and only then enable auto-update fleet-wide.
2. Decide on token enforcement. Provision `-FleetToken` during the per-device
   pass, then flip "Token verlangen" in Administration. Until that switch is on,
   anyone on the LAN can still POST watcher-style events (reads are already
   locked down).
3. Add a nightly backup task for `C:\ProgramData\ActivityWatchFleet`. The code
   side of the settings corruption risk is fixed (section 0.2); the operational
   side is not.
4. DONE this round - the test suite is green (section 0.11), including a
   real bug it turned out to be hiding. Keep it that way: it is now
   self-contained, so a red run means something actually broke.

5. Decide about `aw-agent-windows` (section 0.6): finish the local bucket scan
   and the local-aw-server rollout, or write it off explicitly in the README so
   it stops reading as working infrastructure. Do not leave it half-finished.
6. Retire the per-host assumptions left in `src/queries.ts` and
   `components/QueryOptions.vue` (now only used by the category builder).
7. Add tests around:
   - bucket identity backfill
   - timeline per-session watcher filtering
   - user/device aggregated report correctness
   - sync conflict/recovery behaviour
8. Add more explicit fleet UI drilldowns where needed:
   - selected users + selected devices + date range
   - per-session filters
   - app summary across selected PCs


## 8. Suggested Prompt For The Next Chat

Use something like:

```text
Read ACTIVITYWATCH_HANDOFF.md and continue this ActivityWatch fork.

This fork is a centralized Windows multi-user work-tracking system.
Start with section 0: the current build is packaged but NOT yet installed on LS
or on the devices. Deploy first, verify the manual watcher update on one device,
then pick up the next item from section 7.

Before changing code, inspect the current implementations in:
- aw-server/aw_server/server.py      (the API auth gate: public / machine / session)
- aw-server/aw_server/settings.py    (atomic save, fleet token, update requests)
- aw-server/aw_server/fleet.py       (identity + session type normalization on read)
- aw-core/aw_core/identity.py        (canonical session vocabulary, detection)
- deploy/windows/watchers/supervise-watchers.ps1  (manual update pickup)
- aw-server/aw-webui/src/views/settings/WatcherUpdateSettings.vue
- aw-agent-windows/aw_agent_windows/*  (parked - read section 0.6 first)
```

## 9. Roadmap Reference

The original detailed implementation roadmap is in:

- [roadmap.md](/C:/projecte_visual_code/activitywatch/roadmap.md)

That roadmap still reflects the intended direction well, but this handoff is the more accurate picture of current implementation state.


## 10. Latest Local Work Notes

### 2026-08-26 — Watcher timeline picker as a tree + honest update status

- The Watcher-Zeitachse bucket picker in the fleet single-user view grouped
  its flat checkbox list (one per watcher x device x session - unusable once
  a user has worked on many machines) into a TREE: one card per watcher TYPE
  with a tri-state parent checkbox (select/deselect all devices, shows n/m)
  and the devices ("DEVICE - Sitzung n (type)") as children. The inner
  scrollbar is gone - the panel grows with content
  (`.fleet-daily-watcher-controls`, `dailyWatcherGroups`,
  `toggleDailyWatcherGroup` in FleetActivitySummary.vue).
- The update panel's "Manuelles Update zuletzt fehlgeschlagen, naechster
  Versuch in Kuerze" was shown for ~1 min after every SUCCESSFUL manual
  update (the state only means "attempted, cooling down" - the detached
  installer's result is unknown until the device confirms its new version,
  which also auto-clears the request). Reworded to "Manuelles Update
  ausgefuehrt - Ergebnis wird bestaetigt". The real fix (result file +
  status reporting + abort button) is the tracked TODO task.
- TBFPC8 was invisible in Live although all watchers ran fine: its clock was
  5 min behind (w32time source "Local CMOS Clock", never synced). Now
  configured against dc.tbfgmbh.local. LESSON: a device missing from Live
  with healthy watchers = check the clock first.

### 2026-08-26 — GUI watcher update debugged end-to-end (two latent bugs)

The first-ever GUI-triggered watcher update (all previous rollouts were
manual installs) hit TWO latent bugs, found by live-debugging on TBFPC2 with
the logs of TBFPC7 read over the admin share:

- BUG 1 - headless install hung forever: `Stop-ExistingWatcherProcesses` in
  install-watchers.ps1 called Stop-Process WITHOUT -Force. Stopping another
  user's process (SYSTEM stopping the session users' watchers) makes
  Stop-Process PROMPT - invisibly, with no console - so the update froze
  right after "Selected watcher components" ($ConfirmPreference='None' does
  NOT suppress this particular prompt; only -Force does). Manual installs
  never hit it (same-user processes). Fix: -Force -Confirm:$false, plus the
  supervisor tasks are now unregistered BEFORE stopping watchers so a
  supervisor pass cannot relaunch them mid-extraction. A hung installer
  shows as GUI "Update laeuft"/"zuletzt fehlgeschlagen" with retries every
  ~15 min per request; the stuck powershell must be killed by hand.
- BUG 2 - supervisor could never start watchers (latent since forever):
  start-watchers.ps1, when launched by the SYSTEM supervisor into a session
  (CreateProcessAsUser + CreateEnvironmentBlock), dies in ~0.5s with exit 1
  and no output. Cause: the USER part of PSModulePath points into the
  redirected Documents folder on \dc\profiles$, unreachable for that
  process (its token cannot re-authenticate to the share); PowerShell module
  auto-loading then fails and BUILT-IN cmdlets (Write-Warning,
  Import-PowerShellDataFile) resolve as "not recognized"; with
  $ErrorActionPreference='Stop' the script exits silently. Interactive runs
  and scheduled tasks can reach the share, so the logon-shortcut start
  always worked and masked this. Fix: first statement of start-watchers.ps1
  pins $env:PSModulePath to "$PSHOME\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
  via plain assignment (cmdlet-free - a Join-Path there would itself fail).
  start-watchers also gained a transcript
  (%LOCALAPPDATA%\ActivityWatchFleet\logs\start-watchers.log) and an error
  trap with a %TEMP% fallback, so this path is diagnosable from now on.
- Debug technique worth remembering: the launcher's exit code was captured
  by polling Win32_Process and touching .Handle before exit; a user-level
  scheduled task reproduces the CreateEnvironmentBlock environment; the
  installed scripts were instrumented in place after an elevated
  `icacls ... /grant TBFGMBH\mstep:(OI)(CI)M` (REVOKE with /remove:g after
  debugging; helper grant-debug-access.ps1 at repo root).
- Package history that day: 0c5880e4 (identity fix, BROKEN headless update),
  ca93cf03 (+ Stop-Process fix - update path works), d5cbb17d
  (+ start-watchers instrumentation), 673131b3 (+ PSModulePath fix - FINAL,
  rolled out fleet-wide via GUI upload). `build-setup.ps1` gained
  `-SkipWatchersSetupExe` (stage payload/manifest/Update.zip without the
  setup exe) after the old exe was SMB-locked by another PC.
- Server-side status view: "Aktuell/Gemeldete Version" reflects
  package-version.txt as reported by the supervisor - it proves the PACKAGE
  is installed, not that watcher PROCESSES are running. The pending TODO
  (abort button + real error reporting) is tracked as a spawned task.

### 2026-08-26 — Phantom session fix (elevation identity) + token rollout facts

- BUG (seen on TBFPC7): a UAC prompt answered with a DIFFERENT account's
  credentials (admin installs watchers while a user is logged in) runs the
  installer - and the watchers it starts - with the ADMIN's token and
  environment inside the logged-in user's session. resolve_identity read
  %USERNAME%, so those watchers reported the admin as a second "active
  session" on the device (aklac AND mstep active on PC7).
- Fix 1 (root, aw-core/identity.py): `get_windows_session_username()` asks
  WTS for the session OWNER; resolve_identity precedence is now explicit
  config > WTS session owner > %USERNAME% > getpass. Session 0/services fall
  through to the environment as before. Ships with the WATCHER package -
  five dists rebuilt.
- Fix 2 (install-watchers.ps1): the interactive direct-start now compares
  the installer identity with the session owner (explorer.exe owner) and
  skips the direct start on mismatch - the SYSTEM supervisor (kicked by the
  existing wait loop) starts watchers with the real session user's token.
- Device-side cleanup after the bug: `Get-Process aw-watcher-* | Stop-Process
  -Force` (elevated); the supervisor relaunches correct ones within a
  minute. Phantom buckets `...__<host>__<admin>__1` can be deleted in Raw
  Data.
- TOKEN ROLLOUT FACT (from a code audit, see api.py:843-851): an APPROVED
  enrolled device's key is a FULL alternative to the shared fleet token -
  `is_machine_credential_valid` accepts either. Devices write their
  self-generated key to the same fleet-token.txt and send it as Bearer on
  every heartbeat/update poll. So with every expected device "Freigegeben"
  under Administration > Geraete, "Token verlangen" can be switched on
  WITHOUT running install-watchers.ps1 -FleetToken anywhere. The old panel
  warning claimed otherwise - texts updated (FleetAuthSettings.vue, i18n).
- Tests: aw-core 184 passed (5 new in tests/test_identity_username.py),
  aw-webui 61. Rollout: watcher dists + package rebuilt, then server rebuilt
  (embeds package + new texts). Fleet updates itself via the GUI package;
  the identity fix reaches devices with that watcher update.

### 2026-08-26 — Multi-field category rules + Category Builder removed

- Category rules can now check SEVERAL fields at once: a rule may carry
  `conditions` - additional per-field regex checks that must ALL hold on top
  of the primary pattern. Motivating case: ApplicationFrameHost.exe fronts
  many unrelated UWP programs, so `app` alone cannot categorize it; an
  app + title rule can. Matching lives in `aw-core/aw_transform/classify.py`
  (`RuleCondition`, AND-ed in `Rule.match`, compiled once - no measurable
  cost; malformed conditions fail closed). Tie-breaking: deepest category
  still wins; at equal depth the rule with MORE conditions now wins
  (previously list order); condition-less behaviour is bit-identical.
- A category may also carry `extra_rules` (OR-ed, independent): a
  conditioned rule routes more events into an existing category WITHOUT
  touching its main rule. The webui flattens them into repeated (name, rule)
  query entries (`classes_for_query`, `SelectCategoriesOrPattern`), which
  the query engine already accepted.
- UI: both categorize panels (EventEditor "Edit event" and the fleet
  activity view) gained "Zusaetzliche Feldpruefungen" rows (field + pattern,
  prefilled from the event where a value exists). Saving with conditions
  against an existing category stores an extra rule - never OR-appends into
  the old regex, which would drop the AND semantics. `CategoryEditModal`
  edits conditions and extra rules; the tree shows +N condition(s)/rule(s).
- REMOVED: the Category Builder page (`/settings/category-builder`,
  `CategoryBuilder.vue`) and every link to it (CategorizationSettings
  paragraph, UncategorizedNotification sentence).
- Storage: plain JSON keys inside the existing `classes` setting - old
  configs load unchanged; `cleanCategory` strips unsatisfiable conditions
  and empty extra rules on save.
- Tests: aw-core `tests/test_classify_conditions.py` (11, incl. a
  tie-behaviour regression guard), webui `test/unit/categoryConditions.test.js`
  (9). Suites: aw-core 179 passed, aw-webui 61, aw-server 65. Requires webui
  rebuild + server repackage (aw-core changed: PyInstaller rebuild REQUIRED).

### 2026-08-26 — Connector panels: one button convention

- `/settings/connectors` panels no longer disagree about button placement:
  the enable switch sits top left under the heading (Redmine's Aktiviert
  toggle moved down from the header's right corner), fields follow, and the
  action row sits bottom LEFT with Save first and Test next to it - on both
  `RedmineSettings.vue` and `AdminAuthSettings.vue`. (First attempt
  right-aligned the rows; corrected the same day to left.)
- Requires webui rebuild + server repackage (included in the current
  installer, SHA 04A379B9...).

### 2026-08-26 — Meine Zusammenfassung removed for admins

- The personal page is non-admin only now: admins already pick any user
  (themselves included) on the fleet Zusammenfassung. Removed the admin nav
  pill (`FleetNav.vue`), the admin start-page option
  (`UserAccessSettings.vue`), and `/fleet/me` from `ADMIN_LANDING_PAGES`.
- Degradation for stale state: `route.js` redirects an admin hitting
  `/fleet/me` to `/fleet/summary`; `ADMIN_LANDING_KEY_PATHS` maps a stored
  admin `fleet-summary-own` override to `/fleet/summary`; a stored personal
  `/fleet/me` start page clamps to the default. Non-admin behaviour (grant,
  scoping, redirect for own-only users) unchanged.
- Tests: `landingPage.test.node.ts` grew to 10. Requires webui rebuild +
  server repackage.

### 2026-08-26 — Settings split + Redmine email auto-mapping fix

- Settings menu is split in two: `/settings` (Allgemein) keeps the local
  preferences, new `/settings/connectors` (Verbindungen) holds LDAP
  (`AdminAuthSettings`) and Redmine (`RedmineSettings`). Shared pill sub-nav
  `components/SettingsNav.vue` on both pages; the header Settings entry is now
  a dropdown with both. The Connectors tab/menu item and panels are only
  offered to the built-in `admin` account (their endpoints already were);
  other admins get a notice. Both routes stay `adminOnly`.
- BUG FIX — Redmine auto-mapping ("kein Redmine-Benutzer" despite matching
  addresses, e.g. ecau/aklac): `active_users()` read `users.mail`, but
  Redmine >= 3.0 stores addresses in `email_addresses` and an upgraded DB
  keeps the old column empty for accounts created after the upgrade. The
  query now reads `email_addresses` (default address first) with
  `COALESCE(..., u.mail)` as fallback, and degrades gracefully: no
  `email_addresses` table -> `users.mail` only; no `users.mail` column ->
  `email_addresses` only. See `_active_users_sql`/`_query_active_users` in
  `aw_server/redmine.py`.
- Jest config: `vue-awesome/icons/*` is now stubbed globally via
  `moduleNameMapper` -> `test/stubs/vueAwesomeIcon.js`; per-test
  `jest.mock('vue-awesome/icons/...')` lines are no longer needed.
- New tests: `tests/test_redmine.py` (8, scripted `_query`, no DB needed) and
  `test/unit/SettingsNav.test.js` (7). Suites: aw-server 65, aw-webui 49.
  `npm run build` verified. Requires webui rebuild + server repackage.

### 2026-08-26 — "Meine Zusammenfassung" as a real page

- New view `views/fleet/FleetMySummary.vue` on `/fleet/me`: range presets, four
  headline figures, a per-day tracked-vs-booked list with bars and bookings, and
  a ranked project list. Full description in section 0.16.
- `landingPage.ts`: `OWN_SUMMARY_PAGE`, `hasOwnSummaryOnly()`, the
  `fleet-summary-own` grant now maps to `/fleet/me`, and the non-admin
  whitelist splits the two summary grants.
- `route.js`: the new route plus a redirect from `/fleet/summary` to `/fleet/me`
  for own-only users (old bookmarks / stored landing pages).
- `FleetNav.vue`: a "Meine Zusammenfassung" pill for admins and for
  `fleet-summary-own` holders. `UserAccessSettings.vue`: selectable as an admin
  start page.
- `FleetSummary.vue`: `ownSummaryOnly` removed - no more one-row table.
- `api.py`: `get_fleet_redmine_daily_comparison` returns its days even when
  Redmine is disabled or fails; unbooked days come back as `null`, never as 0.
- New tests: `test/unit/FleetMySummary.test.js` (9),
  `test/unit/landingPage.test.node.ts` (7),
  `test_daily_comparison_returns_days_without_redmine`.
- Requires webui rebuild + server repackage (PyInstaller dist rebuild first).


### 2026-08-25 — Per-user page permissions, non-admin lockdown, wide settings

- Non-admin lockdown is now a WHITELIST (route guard `isNonAdminPathAllowed`): a non-admin can open ONLY their own single-user view (`/fleet/users/<own name>` + subpaths) plus fleet pages explicitly granted to them — every other route, fleet or legacy (`/settings`, `/buckets`, `/search`, ...), typed URL included, redirects to their start page.
- Per-user page grants: `settings.py` auth-user records got `allowed_pages` (subset of `fleet-live`, `fleet-summary`, `fleet-users`, `fleet-devices`) and `landing_page` (`own` or a granted page key; auto-clamped when a grant is revoked). Preserved across LDAP logins (`_record_ldap_login` spreads the existing record). Session payload (`/0/auth/session`) now carries both; `POST /0/admin/auth/users/<u>` accepts `allowed_pages`/`landing_page` alongside `is_admin` (built-in admin only).
- Server-side backing: `_authorize_fleet_page(page, target_username)` in rest.py — a logged-in non-admin gets 403 on fleet endpoints for pages not granted (live/storage→fleet-live, users list + FOREIGN user detail/progress/activity/recalculate→fleet-users, summary + Redmine comparisons→fleet-summary, devices list/detail→fleet-devices). Own-user endpoints always pass. Device METRICS stay session-open because the own view renders the Systemlast wave. Sessions-less LAN calls (watchers, tooling) keep the documented open behavior.
- Admin UI: the user table moved BELOW the LDAP/Test panels (full width) in `AdminAuthSettings.vue` and gained per-row "Seiten-Zugriff" checkboxes (Live/Zusammenfassung/Benutzer/Geräte) and a "Startseite" select (Eigene Auswertung (Standard) + granted pages only, per the request that permitted pages become pickable). Admin rows show "Alle Seiten"/-.
- Start page resolution (`resolveLandingPage` now takes the auth store): non-admins → per-user override if granted, else own view; the global "Startseite (Benutzer)" option remains only "Meine Auswertung". FleetNav shows non-admins "Meine Auswertung" plus pills for granted pages; the FleetUser user-switcher appears for admins or `fleet-users` grantees.
- `/settings` and `/admin` routes got `meta.fullContainer` — wide-screen layout like the fleet views.
- Follow-up in the same round: the user table now lives on the ADMINISTRATION page (`UserAccessSettings.vue`, shown to the built-in admin only, above Redmine-Benutzerzuordnung); `AdminAuthSettings.vue` in Einstellungen keeps just the LDAP connection + test panels.
- Follow-up 2: the global "Startseite" section was REMOVED from Einstellungen (`LandingPageSettings.vue` is orphaned, no longer imported). Start pages are now purely per-user in the Benutzer und Seiten-Zugriff table — admin rows too: options Live (Standard, clears override), Meine Auswertung, Zusammenfassung, Benutzer, Geräte, Zeitachse, Rohdaten (`landing_page` keys incl. `timeline`/`buckets`, admins skip the grant clamp; demotion re-clamps). The old global `landingPageAdmin` value remains only as a silent fallback. Also fixed: LOCAL logins (built-in `admin`) now stamp `last_login` — previously only LDAP logins did, so admin always showed '-'.
- Touched: settings.py, api.py, rest.py, auth.ts, landingPage.ts, route.js, Header.vue, FleetNav.vue, FleetUser.vue, AdminAuthSettings.vue, i18n.ts. Requires webui rebuild + server repackage.


### 2026-08-25 — Watcher package upload via GUI (distribute without server rebuild)

- The Watcher-Updates panel (Administration) now has an upload form: drop in `dist/deployment/ActivityWatch-Fleet-Watchers-Update.zip` (new build-setup.ps1 output bundling payload.zip + install-watchers.ps1 + manifest.json; a bare `payload.zip` is also accepted) and the server distributes it immediately — no server rebuild/reinstall when only the watchers changed.
- Two package locations, uploaded ALWAYS wins until removed: embedded (`aw_server/watcher_package`, read-only, baked by rebuild-server-setup) and uploaded (`<aw-server data dir>/watcher_package_uploaded`, survives server reinstalls). The GUI shows the active source (Hochgeladen/Eingebettet), a remove-override button (falls back to embedded, with confirm), and a warning when the embedded package is newer than the uploaded one (e.g. after a later server rebuild) so a stale override cannot silently downgrade the fleet.
- Server recomputes version/sha256 from the uploaded payload.zip and writes its own manifest — uploaded manifests are never trusted. Upload validation: zip classification (wrapper vs bare payload via entry names), payload must contain `aw-watcher-*` folders, installer fallback from the previously active package when the upload has none. Atomic-ish swap via tmp dir + rename, one retry for Windows file-lock races; tmp dirs always cleaned.
- New endpoints: `POST /api/0/fleet/watcher-update/upload` (admin, multipart field `file`) and `DELETE` same path (admin, removes override). Supervisors are untouched — they keep polling the manifest, which now resolves uploaded-over-embedded transparently (extra `source`/`uploaded`/`embedded` keys are GUI detail).
- Quick rollout when only watchers changed: `rebuild-watchers-setup.cmd` → upload `ActivityWatch-Fleet-Watchers-Update.zip` in the GUI → done. Full chain (watchers rebuild → server rebuild → server install) is only needed when the server itself changed.
- Touched: api.py, rest.py, WatcherUpdateSettings.vue, fleet.ts, i18n.ts, build-setup.ps1.


### 2026-08-25 — Watcher auto-update from the admin web GUI

- Fleet devices now update their watchers themselves: the SYSTEM supervisor task checks the server about once a minute, and when the server carries a different watcher package and auto-update is enabled, it downloads, SHA256-verifies, and installs it headlessly. No more walking installers to every PC.
- Package identity: version = SHA256 of the watcher `payload.zip` (lowercase). `build-setup.ps1 -Target Watchers` writes `dist/deployment/watchers-iexpress/manifest.json` `{version, sha256, created}`; `install-watchers.ps1` stamps the installed version into `<InstallDir>\package-version.txt` after extraction.
- Server embeds the package: `rebuild-server-setup.ps1` gained step 4/6, which copies `payload.zip` + `install-watchers.ps1` + `manifest.json` from `dist/deployment/watchers-iexpress/` into `aw-server/aw_server/watcher_package/` before PyInstaller; `aw-server.spec` bundles that folder (optional — the server still builds without it and reports "no package"). The folder is gitignored.
- BUILD ORDER for a full rollout: `rebuild-watchers-setup.cmd` FIRST (produces the new watcher package), then `rebuild-server-setup.cmd` (embeds it), then install the new server setup on LS once. From then on the fleet pulls the update itself.
- New endpoints (rest.py): unauthenticated like watcher traffic — `GET /api/0/fleet/watcher-update/manifest` (includes `auto_update_enabled`), `GET .../payload`, `GET .../installer`, `POST .../status` (per-device version report). Admin-only: `GET .../devices` (merged per-device report incl. fleet devices that never reported), `GET/POST .../config` (`auto_update_enabled`, default OFF).
- settings.py: `_watcher_update_config` + `_watcher_update_status` reserved keys; per-device status writes to disk only when version/message/updating changes (reports come once a minute per device).
- supervise-watchers.ps1: new `-ServerBase` param (IP/port baked by `build-setup.ps1` like the start scripts) and `Invoke-WatcherUpdateCheck`, which runs AFTER session launching so update trouble can never block watcher starts. 15-minute per-version cooldown via `%ProgramData%\ActivityWatchFleet\update\state.json` prevents retry loops; downloads land in `update\<version>\`; the installer is spawned DETACHED (`-Headless -KeepExistingSelection -InstallDir ...`) because it replaces the supervisor's own files.
- install-watchers.ps1 is now headless-safe (this also fixed the file's mixed CRLF/LF endings — normalized to CRLF): new `-Headless` + `-KeepExistingSelection` switches, auto-detects non-interactive sessions, never prompts/dialogs/UAC when headless, keeps the machine's existing watcher selection (`watchers.config.psd1`, fallback all), and transcribes to `%ProgramData%\ActivityWatchFleet\logs\install-watchers.log`. Interactive installs are unchanged.
- Admin GUI: `/admin` page (user-dropdown → "Administration", admins only) now hosts Redmine-Benutzerzuordnung plus the new Watcher-Updates panel: embedded package version/date/size, the auto-update switch, and a per-device table (gemeldete Version, Aktuell/Veraltet/Aktualisiert gerade/Nie gemeldet, letzte Meldung, Statusmeldung) that auto-refreshes every 30 s.
- IMPORTANT repair: `views/admin/AdminView.vue` was missing on disk while `route.js` still imported it — `npm run build` would have failed. The file is restored (with the new panel).
- Rollout note: devices running the pre-auto-update supervisor never report and show "Nie gemeldet" — run the watcher installer there once by hand; every later update then comes from the GUI. Auto-update ships DISABLED; flip the switch in /admin after the new server is live.
- Touched: install-watchers.ps1, supervise-watchers.ps1, build-setup.ps1, rebuild-server-setup.ps1, aw-server.spec, settings.py, api.py, rest.py, AdminView.vue (restored), WatcherUpdateSettings.vue (new), fleet.ts, Header.vue, i18n.ts, .gitignore.


### 2026-08-24 web UI chrome cleanup (footer links, Activity menu, Tools menu)

- Footer: removed all six external links (Report a bug / Ask for help / Vote on features / Twitter / GitHub / Donate) and their icon imports from `Footer.vue`. The footer now shows only the `Host:` / `Version:` line.
- Header: removed the `Activity` top-left menu entry in both forms (the single-view `b-nav-item` and the multi-host dropdown with its Loading / "No activity reports available" / per-host items). The nav now starts at Timeline, then Fleet.
- Header: removed the `Tools` ("Werkzeuge") dropdown entirely (Search, Trends, Report, Alerts, Timespiral, Query, Graph) plus its eight now-unused icon imports.
- Header: also removed the "Show tools menu" switch from the Admin-settings modal, because it would otherwise toggle a menu that no longer exists. The `show_tools_menu` value is still read into the draft and written back on save, so nothing is clobbered server-side and the menu can be restored by reverting the template alone.
- The routes behind the removed entries (`/activity/<host>`, `/search`, `/query`, `/trends`, `/report`, `/alerts`, `/timespiral`, `/graph`) are still registered and reachable by direct URL. Only the menu chrome was removed.
- `Header.vue` still computes `activityViews` in `mounted`; it is dead data for the removed menu, kept because the same hook performs `bucketStore.ensureLoaded()`.
- Touched: `Footer.vue`, `Header.vue`. Requires webui rebuild + server repackage (PyInstaller dist rebuild first).


### 2026-08-24 watcher rollout hardening (self-elevation, supervisor logging, diagnostics)

- `install-server.ps1` and `install-watchers.ps1` now self-elevate instead of failing with "Run this setup as Administrator": `Invoke-SelfElevation` re-launches the script through an encoded command under `-Verb RunAs`, forwards every bound parameter, keeps the elevated window open until Enter, and propagates the elevated exit code.
- `install-watchers.ps1` gained `-StartupTimeoutSeconds` (default 60) plus `Get-WatcherExePath` / `Get-RunningWatcherProcesses` / `Start-SelectedWatchers`: after registering the supervisor task it waits for the watchers to appear and, for any that the supervisor did not bring up in time, starts them directly in the installing user's session.
- `supervise-watchers.ps1` now logs to `C:\ProgramData\ActivityWatchFleet\logs\supervisor.log`: it records the identity it runs as, every enumerated session with state/station/user, and why a session was skipped. The native session enumerator no longer drops sessions whose user name cannot be read (a failed `WTSQuerySessionInformation` was previously indistinguishable from "no sessions exist"); that filtering now happens in PowerShell, where it is logged.
- New `diagnose-watchers.cmd` / `diagnose-watchers.ps1` at the repo root: self-elevating dump of running watcher processes (PID/session/owner/path), both scheduled tasks with last run time and result, the Startup shortcut, install and runtime folders, and log tails. It writes `watcher-diagnostics.txt` next to the script; that report is generated output and is gitignored.
- New `rebuild-watchers-setup.cmd` at the repo root, mirroring `rebuild-server-setup.cmd`: self-elevates, clears locks/ACLs on the previous exe, and repackages the watcher setup only.


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

### 2026-08-24 — Zeitachse: audited event editing + manual event creation

- Timeline events are now editable for ADMINS on every watcher row — including sessionstate/audio events, which previously never opened the editor because their click was reserved for the color picker (both work now). Editing stays gated to admins in the UI; the SERVER additionally allows non-admin users to edit events in buckets belonging to their own username (forward-compatible self-service editing — flip the UI gate later in VisTimeline.canEditEvents).
- Double-click on empty space in a watcher's row creates a manual event there (30 min default at the clicked time), immediately persisted and opened in the EventEditor; data template per bucket type (currentwindow: app/title, afkstatus: status, sessionstate: state, audio: audible).
- Audit trail (server-stamped in rest.py, so it cannot be forged/lost): every manual create/edit appends {by, at, action} to event.data.$edits; manual creations also get $manual=true. Watcher writes carry no browser session and are untouched. EventEditor hides $-keys from the editable table and shows the history ("Verlauf") instead.
- Cache coherence: manual create/edit/delete invalidates overlapping cached day summaries (fleet_summary_store.delete_user_summaries_in_range) for the bucket's username — verified day-targeted (only the touched day drops). Heartbeats are unaffected (today's chunk is never persisted).
- Timeline gets a filter "Bearbeitete / manuelle Events": Alle / Ausblenden / Nur diese.
- Touched: rest.py (stamping/auth/invalidation on event POST/DELETE), api.py (invalidate_fleet_user_summaries), fleet_summary_store.py, VisTimeline.vue, EventEditor.vue, Timeline.vue, i18n.ts. Requires webui rebuild + server repackage (PyInstaller dist rebuild first).


### 2026-08-24 — Zusammenfassung: Tagesvergleich (daily active time vs Redmine bookings)

- New card below the Auswertung table ("Tagesvergleich laden"): for every fleet day in the selected range, per user: Aktive Sitzungszeit vs Redmine gebucht (delta), plus every booking of that day with project label, hours, and the time-entry comment. Empty user-days are skipped; days sort newest first.
- `redmine.py`: `daily_time_entries()` — row-level read-only SELECT (te.spent_on, project name via join, te.hours, te.comments).
- `api.py`: `get_fleet_redmine_daily_comparison(start, end, usernames)` — reuses the mapping/matching logic; the active side reads per-day totals from the day-chunk summary cache (get_fleet_user_summary_value per fleet day → warm days are store lookups). Day key = chunk-start local date, so a booking on 2026-08-13 aligns with the fleet day starting 13th 04:00.
- `rest.py`: POST `/0/fleet/redmine-daily-comparison`. webui: fleet store action (10-min timeout), new card UI in FleetSummary.vue, German i18n strings.
- Requires webui rebuild + server repackage (PyInstaller dist rebuild first!).


### 2026-08-24 — Fleet user summaries now chunked per fleet day (multi-month ranges)

- `GET /0/fleet/users/<u>` and the Zusammenfassung page now split EVERY range at local start_of_day (04:00) boundaries: complete days are served from `user_summary_cache` (totals + apps + devices per day) and persisted after first computation; only missing days and the current, still-running day are computed. A quarter = ~90 SQLite lookups + merge when warm.
- `fleet.py`: `iter_fleet_day_ranges` (DST-safe wall-clock boundaries via naive `astimezone()`), `calculate_user_summary_day` (totals+apps for one chunk on one shared event cache), `merge_user_summary_chunks` (verified: chunked == whole-range on the real interval logic, incl. boundary-crossing events).
- `api.py`: `get_fleet_user_summary_value` rewritten around chunks; cached day rows are trusted only if `calculated_at >= range_end` (stale partial-day rows self-heal); the current day is never persisted (Live stays fresh). `_previous_summary_period` now uses wall-clock boundaries so nightly precompute keys match chunk keys. Nightly precompute (unchanged callers) now fills day rows WITH apps, so it warms the App-Zeit table too.
- "Neu berechnen" (force) recomputes and re-persists every day in the selected range.
- No webui changes needed. Requires server repackage (PyInstaller dist rebuild!) + reinstall on LS.


### 2026-08-24 — Fleet user view: 60s timeout fix (performance + caching)

- Problem: `GET /0/fleet/users/<username>` recomputed everything per request and fetched the same bucket events from SQLite 5-8 times (totals were even computed twice); multi-week ranges exceeded the webui's 60s request timeout.
- `aw_server/fleet.py`: new request-scoped `FleetEventCache` / `wrap_fleet_event_cache()` memoizes `get_buckets()`/`get_events()` within one request; entry points (`summarize_user`, `calculate_user_summary_totals`, `report_time_by_app`, `summarize_user_activity`, `summarize_device`, `summarize_device_metrics`) wrap themselves. `summarize_user` accepts `precomputed_summary` (skips duplicate totals pass); new `build_user_detail_from_summary()` serves a fully cached range with zero event scans.
- `aw_server/fleet_summary_store.py`: `user_summary_cache` gains `apps_json` + `available_devices_json` (auto-migrated via ALTER TABLE; COALESCE on conflict so totals-only precompute never wipes cached apps).
- `aw_server/api.py`: `get_fleet_user()` shares one event cache across summary+detail, serves fully cached ranges instantly, and persists apps/devices after fresh computes; `recalculate_fleet_user_summary()` now forces a FULL recompute (totals + apps) so the "Neu berechnen" button refreshes the cache coherently.
- webui: per-request 10-min timeouts for `loadUser`, `recalculateUserSummary`, and the activity-summary call (global 60s default untouched).
- Result: first load of a new range is several times faster; revisiting a range is near-instant; "Neu berechnen" is the explicit cache-bust. Requires webui rebuild + server repackage.


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
