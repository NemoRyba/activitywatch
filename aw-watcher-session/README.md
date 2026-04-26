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

## Usage

```powershell
aw-watcher-session --host 127.0.0.1 --port 5600 --central-mode
```
