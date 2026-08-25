# ActivityWatch Fleet Windows Deployment

This folder builds the current fork into two Windows setup executables:

- `ActivityWatch-Fleet-Server-Setup.exe`
- `ActivityWatch-Fleet-Watchers-Setup.exe`

The watcher setup is preconfigured to send to `http://192.168.0.144:5600/`.

## Build

From the repo root after the PyInstaller component builds, including
`aw-watcher-system`:

```powershell
.\deploy\windows\build-setup.ps1 -ServerHost 192.168.0.144 -ServerPort 5600
```

To rebuild only one setup and leave the other output untouched, pass
`-Target Server` or `-Target Watchers`.

For a full server-only rebuild from current sources, double-click
`rebuild-server-setup.cmd` in the repo root. It rebuilds the web UI,
copies it into the server static assets, stages the latest watcher
package for auto-update (step 4/6, from `dist\deployment\watchers-iexpress`),
rebuilds the PyInstaller server payload, then packages only the server
setup exe.

For a watcher-only repackage, double-click `rebuild-watchers-setup.cmd`
in the repo root. Besides the watcher setup exe it now also writes:

- `dist\deployment\watchers-iexpress\manifest.json` - auto-update manifest
  (version = SHA256 of `payload.zip`)
- `dist\deployment\ActivityWatch-Fleet-Watchers-Update.zip` - single-file
  package for the admin GUI upload (see "Watcher auto-update" below)

The setup files are written to `dist\deployment`.

Current validated output names:

- `dist\deployment\ActivityWatch-Fleet-Server-Setup.exe`
- `dist\deployment\ActivityWatch-Fleet-Watchers-Setup.exe`

Latest validated build, local time 2026-08-25 21:10:

- Server setup SHA256:
  `783AE5809E14C92DBF144EB2783237AE6A66DE102812EA8B2EB07A7C18873909`
- Watchers setup SHA256:
  `2BA7E6A28F808C68B64E830126FBE4A12436799F73098E5DE1F1E7BD5A517D0C`
- Watchers update zip SHA256:
  `494DB2BC3BBF409B3BFEC8C2233AB62C0448952A013560C88A9147894778AA02`
- Watcher package version (= SHA256 of `payload.zip`, embedded in the server):
  `57a425e44a63ca18bc64a52415718bbc53d07a3ccaf023fef221205d443a1e0c`
- Server payload version check: `v0.13.2.dev+e5983e5`

The server and the watcher package MUST be built from the same round: the server
embeds the watcher package it will offer to devices, and if the two disagree the
fleet is told to "update" back and forth between versions. `build-setup.ps1
-Target Watchers` first, then `rebuild-server-setup.ps1`.

What this build adds over 2026-08-24 (see `ACTIVITYWATCH_HANDOFF.md` section 0):
manual watcher updates from the GUI, device enrollment with admin approval,
fleet-token authentication for machine traffic, announcing a server move so the
fleet follows it by itself, canonical session-type labels, crash-safe
`settings.json`, and removal of the legacy upstream view routes.

NOTE on packaging: `iexpress.exe` is a GUI-subsystem binary, so it used to be
launched fire-and-forget and the build polled for the output file. That raced on
a loaded machine - the 65 MB server payload finished its CAB but not the exe,
the poll timed out, and because the previous exe had already been cleared, the
build left NO installer at all. It is now launched with `Start-Process -Wait`
and its exit code is checked.


If the web UI changed, rebuild `aw-server\aw-webui` and copy the built assets into `aw-server\aw_server\static` before rebuilding these setup files.

## Install

Run each setup as Administrator.

Server setup installs `aw-server` to `C:\Program Files\ActivityWatch Fleet Server`, starts it on boot as a scheduled task, binds it to `0.0.0.0:5600`, and opens the Windows firewall for TCP 5600. Use `http://192.168.0.144:5600/` from the LAN.

Re-running the server setup works as an update: it stops the existing installed Fleet Server scheduled task/process, overwrites the program files, and preserves runtime data under `C:\ProgramData\ActivityWatchFleet`.

When an existing server install or existing server data is detected, the server setup asks IN THE CONSOLE whether the data directory should be moved: press `J`/`Y` within 13 seconds to move, `N`/`Enter` to keep, and after 13 seconds without an answer the update simply continues with the current data. Only after an explicit yes does a folder-selection window open (forced to the foreground); choosing a new empty folder moves the existing database/runtime data there, stores the selected path in `HKLM\Software\ActivityWatchFleet\DataRoot` with an install-folder fallback file, and points future server starts at the new location. This can be used to move the database to another drive during an update.

For scripted installs, pass `-DataDir "D:\ActivityWatchFleetData"` to `install-server.ps1` to set or move the data location without the dialog. Use `-SkipDataLocationPrompt` to keep the current location.

Watcher setup bundles AFK, window/activity, session, audio, and CPU/RAM system watchers into one installer. During setup it shows a component picker with all watchers selected by default. The selected components are installed to `C:\Program Files\ActivityWatch Fleet Watchers` and saved in `watchers.config.psd1` so scheduled starts keep honoring the choice. For scripted installs, pass `-Watchers afk,window,session,audio,system` or use `-SkipWatcherSelection` to install all watchers without the dialog.

For selected per-user watchers, setup creates a machine-level scheduled supervisor task named `ActivityWatch Fleet Watchers Supervisor` which runs as `SYSTEM`, checks active interactive sessions, and starts the selected AFK/window/session/audio watchers inside each logged-in user's own session. It also keeps an all-users Startup shortcut as a fallback. If the CPU/RAM system watcher is selected, CPU/RAM load is sampled once per computer by a separate machine-level scheduled task named `ActivityWatch Fleet System Watcher`. Watcher retry queues remain in each user's local ActivityWatch data directory, so temporary server/network outages are retried.

Re-running the watcher setup works as an update: it stops existing installed watcher processes, overwrites the program files, recreates the supervisor scheduled task and all-users Startup shortcut, and preserves each user's local retry queues/logs. The setup does not need to be run separately for each Windows user.

Pass `-FleetToken <token>` to provision this machine's fleet token in the same run (see "Fleet token" below). Omitting it keeps whatever token the device already has, so updates never lose it.

## Watcher updates (automatic and manual)

Once the auto-update-capable supervisor is installed on a device (any watcher
setup run from 2026-08-25 on), the device can update itself and can be updated
on demand from the admin GUI.

How the device side works:

- The SYSTEM supervisor task polls
  `/api/0/fleet/watcher-update/manifest?hostname=<COMPUTERNAME>` about once a
  minute and reports its installed package version (`package-version.txt` in
  the install dir).
- The hostname in that query is what lets the server answer with a MANUAL
  update request filed for exactly that device. It costs no extra request, and
  the server never opens a connection to the device.
- When an update is due, the supervisor downloads the package, verifies its
  SHA256, and runs `install-watchers.ps1` headlessly (no prompts, no UAC, keeps
  the device's watcher selection).
  Logs: `C:\ProgramData\ActivityWatchFleet\logs\install-watchers.log`.
- A 15-minute per-version cooldown prevents retry loops.

### Automatic updates

Enabled by the switch under `Administration -> Watcher-Updates` (default OFF).
While it is on, every device installs a newer package within about a minute of
it appearing on the server.

### Manual updates from the GUI

The device table in `Administration -> Watcher-Updates` has a checkbox per row
plus:

- **Alle auswählen** / **Auswahl aufheben**
- **Ausgewählte aktualisieren** - update just the ticked devices
- **Alle aktualisieren** - update every listed device
- **Jetzt aktualisieren** per row - update one device

A manual request:

- bypasses the automatic switch entirely, so it works with auto-update OFF;
- installs even when the reported version already matches, so the button also
  works as a repair / reinstall;
- bypasses the 15-minute cooldown exactly once (tracked by `request_id` in
  `%ProgramData%\ActivityWatchFleet\update\state.json`), so a persistently
  failing install falls back to the normal 15-minute rhythm instead of
  re-downloading every minute;
- clears itself once the device reports the target version, and expires after
  `manual_update_ttl_minutes` (default 6 h) if the device stays off.

The row shows *Update angefordert* until the device picks it up, then *Update
läuft*, then the normal *Aktuell*. **Ausstehende Updates abbrechen** withdraws
requests that have not been picked up yet.

Note the restart: installing stops and replaces the watchers, so expect a short
gap in that device's recording. The confirm dialog states the device count.

### Publishing a new watcher package

1. GUI upload (no server rebuild): run `rebuild-watchers-setup.cmd`, then
   upload `dist\deployment\ActivityWatch-Fleet-Watchers-Update.zip` under
   `Administration -> Watcher-Updates`. An uploaded package overrides the
   embedded one until it is removed in the GUI and survives server reinstalls.
2. Embedded in the server build: run `rebuild-watchers-setup.cmd`, then
   `rebuild-server-setup.cmd`, then reinstall the server setup.

Devices showing **Nie gemeldet** still run a pre-auto-update supervisor. They
never poll the server, so neither automatic nor manual updates can reach them:
run the watcher setup there once by hand. Afterwards they follow GUI rollouts.

## Device enrollment (no secret has to be carried to the machine)

Preferred way to give a device a credential: let it ask for one.

1. Run the watcher setup on the device. Do not pass `-FleetToken`.
2. On first start the supervisor generates a 256-bit key, stores it in
   `%ProgramData%\ActivityWatchFleet\fleet-token.txt`, and registers it with the
   server.
3. The device appears under `Administration -> Geräte` as *Wartet auf Freigabe*,
   with its IP address, first-seen time and a short key fingerprint.
4. Approve it. From then on that key is the device's credential.

Notes:

- Enrolling grants nothing. A pending device is refused exactly like an unknown
  caller, so an open enrollment endpoint is not a way in.
- No data is lost while a device waits: the watchers queue events on disk and
  flush them the moment the device is approved.
- Only the SHA256 of the key is stored on the server. The key itself never
  leaves the device after enrollment, and is never shown in the GUI.
- Re-posting the same key is idempotent and never sends an approved device back
  to pending, so the supervisor can register on every start.
- If two rows show the same hostname, compare the fingerprint before approving -
  a re-imaged machine generates a new key and enrolls again.
- Revoking a device takes its access away immediately, without affecting any
  other device. That is the main advantage over the shared token.

The shared fleet token still works and is the break-glass path; both travel in
the same `Authorization: Bearer` header and live in the same file.

## Moving the server to another computer or IP

The watcher package has a server address baked in at build time, but it can be
overridden fleet-wide from the GUI, so a move needs no visit to any PC.

**Order matters.** Devices learn the new address from the update check they run
against the CURRENT server, so that server has to still be reachable when you
announce the move.

1. Set up the new server and give it the fleet data. Restoring
   `C:\ProgramData\ActivityWatchFleet` also brings the fleet token and the
   approved device keys, so devices keep working without being re-approved.
2. On the OLD server, open `Administration -> Server umziehen`, enter the new
   address (e.g. `http://192.168.0.200:5600`) and announce it.
3. Watch `Administration -> Watcher-Updates` on the NEW server: devices appear
   there as they switch over, within about a minute each.
4. Once every device has moved, retire the old server.

Two independent checks stop a typo from stranding the fleet:

- The server refuses to announce an address unless an ActivityWatch server
  actually answers `/api/0/info` there. The "announce anyway" checkbox overrides
  this - only use it if the new server genuinely is not up yet.
- Each device verifies the announced address itself before switching, and stays
  where it is if it cannot reach it. A device on a different subnet that cannot
  route to the new address simply does not move, and logs why in
  `C:\ProgramData\ActivityWatchFleet\logs\supervisor.log`.

On the device the override is stored in
`%ProgramData%\ActivityWatchFleet\server-endpoint.txt`, outside the install
directory so a watcher update cannot lose it. Deleting that file returns the
device to the address baked into its watcher package. After switching, the
supervisor restarts the watchers, because they read the server address only at
startup - expect a few seconds' gap in that device's recording.

Clearing the announcement does NOT move devices back; those that already
switched keep the new address. Only clear it once the whole fleet has moved.

## Fleet token (machine authentication)

Everything a browser reads from the API requires a login. Watchers and the
supervisor have no browser session, so they authenticate with a shared **fleet
token** instead.

- The server generates it on first start. Read, copy or rotate it under
  `Administration -> Fleet-Zugriffstoken` (built-in `admin` only).
- Provision a device with:

  ```powershell
  .\install-watchers.ps1 -FleetToken <token>
  ```

  It is written to `C:\ProgramData\ActivityWatchFleet\fleet-token.txt`
  (Administrators/SYSTEM full control, Users read). That path is outside the
  install directory on purpose, so a watcher update cannot lose it — and
  omitting `-FleetToken` on an update keeps the token already present.
- Watchers pick it up through `aw-client`, which looks at `AW_FLEET_TOKEN`,
  then that file, then `[server] fleet_token` in the aw-client config.

**Enforcement ships OFF.** Turning on *Token verlangen* before every device
holds the token makes those devices stop recording — their events queue on disk
rather than being lost, but nothing reaches the server until the token is
fixed. Correct order: install the new watchers with `-FleetToken` everywhere,
confirm the device table looks healthy, then flip the switch.

Rotating the token invalidates the old one immediately, so plan a rotation the
same way as the initial rollout.

## Verify

On the server machine after installing:

```powershell
Invoke-RestMethod http://127.0.0.1:5600/api/0/info
Invoke-RestMethod http://192.168.0.144:5600/api/0/info
```

On watcher machines after user login, logs are written below:

```text
%LOCALAPPDATA%\ActivityWatchFleet\logs\watchers
```

Server logs and runtime data are written below:

```text
C:\ProgramData\ActivityWatchFleet
```
