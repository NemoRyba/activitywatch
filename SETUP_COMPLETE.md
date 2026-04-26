# ActivityWatch Full Stack - Ready to Run

This repository has been fully prepared and built with all ActivityWatch components:

## ✅ Installed Components

- **aw-core** (v0.5.17) - Core library
- **aw-client** (v0.5.15) - Client library for communicating with the server  
- **aw-server** (v0.13.2) - Backend server for storing and querying activity data
- **aw-qt** (v0.1.0) - Desktop UI (system tray application)
- **aw-watcher-afk** (v0.2.0) - AFK (away from keyboard) detector
- **PyQt6** (v6.5.3) - Qt framework for the desktop UI

## 🚀 Quick Start

### Option 1: Using the Batch File (Easiest)
Simply double-click: **`run-stack.bat`**

This will:
1. Start the aw-server on http://127.0.0.1:5600
2. Start the aw-qt Windows system tray application
3. Launch both in separate console windows for monitoring

### Option 2: Using PowerShell Script
```powershell
.\run-stack.ps1
```

### Option 3: Manual Start (Individual Components)

**Terminal 1 - Start the Server:**
```powershell
.\.venv\Scripts\python.exe -m aw_server.main --host 127.0.0.1 --port 5600
```

**Terminal 2 - Start the Desktop UI (after server is ready):**
```powershell
.\.venv\Scripts\python.exe -m aw_qt.main
```

**Terminal 3 - Start the AFK Watcher (optional):**
```powershell
.\.venv\Scripts\python.exe -m aw_watcher_afk
```

## 🌐 Access Points

Once running, you can access:

- **Web Interface:** http://127.0.0.1:5600
- **API Documentation:** http://127.0.0.1:5600/api/ (interactive Swagger UI)
- **REST API:** http://127.0.0.1:5600/api/0/ (core API endpoints)

### Example API Calls:

```powershell
# Get server info
curl http://127.0.0.1:5600/api/0/info

# List buckets
curl http://127.0.0.1:5600/api/0/buckets/

# Query events (example)
$body = @{
    "query" = "RETURN 'test'"
} | ConvertTo-Json
curl -Method POST -Uri http://127.0.0.1:5600/api/0/query/ `
    -ContentType "application/json" -Body $body
```

## 📊 Collecting Data

The system starts tracking activity when:

1. **aw-server** is running (stores all data)
2. **aw-watcher-afk** is running (tracks when you're away from keyboard)
3. **aw-watcher-window** is running (tracks active window/application)
4. **aw-qt** is running (system tray manager and UI)

All activity data is stored locally in: `%LOCALAPPDATA%\activitywatch\activitywatch\`

## 📁 Project Structure

```
E:\projects\activitywatch\
├── .venv\                    # Python virtual environment
├── aw-core\                  # Core library
├── aw-client\                # Client library
├── aw-server\                # Server component
├── aw-qt\                    # Desktop UI
├── aw-watcher-afk\           # AFK detector
├── aw-watcher-window\        # Window tracker
├── run-stack.bat             # Batch launcher
├── run-stack.ps1             # PowerShell launcher
└── [other components...]
```

## ⚙️ Virtual Environment

The Python virtual environment is located at `.\.venv\`

To activate it manually:
```powershell
.\.venv\Scripts\Activate.ps1
```

## 🛠️ Development

If you need to rebuild or reinstall components:

```powershell
# Reinstall a specific component
.\.venv\Scripts\python.exe -m pip install -e .\aw-core

# Reinstall all local components
.\.venv\Scripts\python.exe -m pip install -e . -e .\aw-core -e .\aw-client -e .\aw-server -e .\aw-qt
```

## 📝 Logs

When running via batch file or PowerShell script, logs will be displayed in the console windows of each component. You can also check:

- Server logs: Console output from server window
- Qt UI logs: Console output from Qt application window

## ⚠️ Important Notes

- The development server should NOT be used in production
- Data is stored locally on your machine in: `%LOCALAPPDATA%\activitywatch\`
- To stop any component, close its console window or press Ctrl+C

## 🔗 Resources

- Official Website: https://activitywatch.net/
- Documentation: https://docs.activitywatch.net/
- GitHub: https://github.com/ActivityWatch/activitywatch

---

**Ready to start?** Run `run-stack.bat` and enjoy tracking your activity! 🎉
