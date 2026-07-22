# aw-watcher-system

`aw-watcher-system` is a lightweight Windows watcher that reports host-level
system metrics to ActivityWatch.

It samples Windows' native system CPU time counters and physical memory status
once per poll interval and sends one queued heartbeat to the server. It avoids
WMI, CIM, `Get-Counter`, and `psutil`.

## Usage

```powershell
aw-watcher-system --host 127.0.0.1 --port 5600 --central-mode
```

By default it samples every 60 seconds. Use `--poll-time` to change the interval:

```powershell
aw-watcher-system --host 127.0.0.1 --port 5600 --central-mode --poll-time 60
```
