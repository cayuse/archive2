# Analyse whatever the archive has waiting and write it back. Safe to run any time, or from Task Scheduler.
# Usage: powershell -File scripts\sync_archive.ps1
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:PYTHONUNBUFFERED = "1"; $env:PYTHONIOENCODING = "utf-8"
.\venv\Scripts\python scripts\archive_sync.py @args 2>&1 | Where-Object { $_ -notmatch 'Warning|warn\(' } | Tee-Object -FilePath work\sync\sync.log -Append
