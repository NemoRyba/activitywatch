# ActivityWatch Fleet Windows Deployment

This folder builds the current fork into two Windows setup executables:

- `ActivityWatch-Fleet-Server-Setup.exe`
- `ActivityWatch-Fleet-Watchers-Setup.exe`

The watcher setup is preconfigured to send to `http://192.168.0.144:5600/`.

## Build

From the repo root after the PyInstaller component builds:

```powershell
.\deploy\windows\build-setup.ps1 -ServerHost 192.168.0.144 -ServerPort 5600
```

The setup files are written to `dist\deployment`.

Current validated output names:

- `dist\deployment\ActivityWatch-Fleet-Server-Setup.exe`
- `dist\deployment\ActivityWatch-Fleet-Watchers-Setup.exe`

If the web UI changed, rebuild `aw-server\aw-webui` and copy the built assets into `aw-server\aw_server\static` before rebuilding these setup files.

## Install

Run each setup as Administrator.

Server setup installs `aw-server` to `C:\Program Files\ActivityWatch Fleet Server`, starts it on boot as a scheduled task, binds it to `0.0.0.0:5600`, and opens the Windows firewall for TCP 5600. Use `http://192.168.0.144:5600/` from the LAN.

Re-running the server setup works as an update: it stops the existing installed Fleet Server scheduled task/process, overwrites the program files, and preserves runtime data under `C:\ProgramData\ActivityWatchFleet`.

Watcher setup installs AFK, window, and session watchers to `C:\Program Files\ActivityWatch Fleet Watchers`. It creates an all-users Startup shortcut so the watchers start inside every logged-in user's desktop session. Watcher retry queues remain in each user's local ActivityWatch data directory, so temporary server/network outages are retried.

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
