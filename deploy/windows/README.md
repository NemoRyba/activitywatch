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

The setup files are written to `dist\deployment`.

Current validated output names:

- `dist\deployment\ActivityWatch-Fleet-Server-Setup.exe`
- `dist\deployment\ActivityWatch-Fleet-Watchers-Setup.exe`

Latest validated build, local time 2026-08-07 22:12:

- Server setup SHA256:
  `9C48FC1547C64A19E47A53D98BDE826C4181D0FF6A0CA65C384F52001C5067DB`
- Watchers setup SHA256:
  `090E9E1E419E4199F2C99243B98064FB0C7810E1A6E3599F85EF9DC03C512D5A`
- Included UI state: fleet user next/previous day shortcuts, raw active session total with optional after-AFK total above the bar chart, ignored-category filter for excluding selected category paths and children from activity summaries/charts, click-to-categorize Uncategorized app rows in the category tree, always-visible compact total labels above each bar-chart bar plus full `Bar total` values in hover/click details, chart-coherent active-session tooltip values, pinned scrollable draggable/resizable bar-chart details window on chart/time-axis click, 3-second hover delay for transient chart tooltips, server-backed remembered Fleet user filter state per logged-in web user, max active-session AFK display/default for the short-AFK threshold, optional threshold for treating short AFK periods as active/non-AFK in summaries and watcher timelines, AFK data gaps counted as active only when clamped to overlapping session-watcher active intervals, timeline edit dialogs that preserve scroll position, packaged web UI logo assets, optional CPU/RAM system-load waves in device/user timeline views, LDAP admin settings. Fleet live summaries hide stale non-terminal sessions and only show AFK/window details from fresh watcher updates. The server installer uses a smoother data-location prompt with default keep-current-data behavior and a 30-second auto-continue timeout. The server payload was rebuilt with the lock-compatible `peewee 3.17.6` dependency.
- The short-AFK threshold groups consecutive `afk -> afk -> ... -> not-afk` rows into one AFK period before deciding whether the period is short enough to ignore.
- The fleet user filter includes an opt-in `Count AFK watcher gaps as active only inside active sessions` checkbox for counting active-session gaps with no AFK watcher coverage as non-AFK/active.

If the web UI changed, rebuild `aw-server\aw-webui` and copy the built assets into `aw-server\aw_server\static` before rebuilding these setup files.

## Install

Run each setup as Administrator.

Server setup installs `aw-server` to `C:\Program Files\ActivityWatch Fleet Server`, starts it on boot as a scheduled task, binds it to `0.0.0.0:5600`, and opens the Windows firewall for TCP 5600. Use `http://192.168.0.144:5600/` from the LAN.

Re-running the server setup works as an update: it stops the existing installed Fleet Server scheduled task/process, overwrites the program files, and preserves runtime data under `C:\ProgramData\ActivityWatchFleet`.

When an existing server install or existing server data is detected, the server setup prompts whether the data directory should be moved. Choosing a new empty folder moves the existing database/runtime data there, stores the selected path in `HKLM\Software\ActivityWatchFleet\DataRoot` with an install-folder fallback file, and points future server starts at the new location. This can be used to move the database to another drive during an update.

For scripted installs, pass `-DataDir "D:\ActivityWatchFleetData"` to `install-server.ps1` to set or move the data location without the dialog. Use `-SkipDataLocationPrompt` to keep the current location.

Watcher setup installs AFK, window, session, and system-metrics watchers to `C:\Program Files\ActivityWatch Fleet Watchers`. It creates a machine-level scheduled supervisor task named `ActivityWatch Fleet Watchers Supervisor` which runs as `SYSTEM`, checks active interactive sessions, and starts AFK/window/session watchers inside each logged-in user's own session. It also keeps an all-users Startup shortcut as a fallback. CPU/RAM load is sampled once per computer by a separate machine-level scheduled task named `ActivityWatch Fleet System Watcher`. Watcher retry queues remain in each user's local ActivityWatch data directory, so temporary server/network outages are retried.

Re-running the watcher setup works as an update: it stops existing installed watcher processes, overwrites the program files, recreates the supervisor scheduled task and all-users Startup shortcut, and preserves each user's local retry queues/logs. The setup does not need to be run separately for each Windows user.

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
