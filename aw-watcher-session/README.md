# aw-watcher-session

`aw-watcher-session` is a Windows-only watcher that reports the current session
state to ActivityWatch.

It is intended for centralized multi-user deployments and emits `sessionstate`
events such as:

- `active`
- `locked`
- `disconnected`
- `logged_in`
- `no_session`

The watcher reports the state of the Windows session it is running inside.
For multi-user machines, a separate watcher process should run in each user
session. A machine-level supervisor can launch those per-session watchers.

## Usage

```powershell
aw-watcher-session --host 127.0.0.1 --port 5600 --central-mode
```
