# aw-watcher-audio

`aw-watcher-audio` is a lightweight Windows watcher that reports whether the
current interactive user's default audio playback and microphone endpoints are
active.

It does not record audio, save waveforms, transcribe speech, or inspect media
content. By default it sends only stable state metadata so ActivityWatch can
merge heartbeats efficiently:

- playback bucket type: `audio.playback`
- microphone bucket type: `audio.microphone`
- event state: `active`, `silent`, `no_device`, or `error`

## Usage

```powershell
aw-watcher-audio --host 127.0.0.1 --port 5600 --central-mode
```

Defaults are tuned for low overhead:

- sample every 10 seconds
- flush unchanged state every 30 seconds
- do not include raw level values in heartbeat data
- check console, multimedia, and communications default devices

Use `--include-levels` while testing if you want rounded peak values in events:

```powershell
aw-watcher-audio --host 127.0.0.1 --port 5600 --central-mode --include-levels
```

