# Run the audio analysis until every mirrored song is done. Safe to stop and restart (resumes).
# Usage: powershell -File scripts\run_analysis.ps1
Set-Location C:\Users\cayuse\ai_stuff\music_archive
$env:PYTHONUNBUFFERED = "1"; $env:PYTHONIOENCODING = "utf-8"
while ($true) {
  .\venv\Scripts\python scripts\analyze_audio.py --workers 18 2>&1 | Where-Object { $_ -match '^(songs|model|DONE|\d+/)' } | Tee-Object -FilePath work\analysis.log -Append
  $last = Get-Content work\analysis.log -Tail 1
  if ($last -match 'to do 0' -or $last -match 'DONE .* 0 not mirrored') { break }
  Start-Sleep -Seconds 180
}
"ANALYSIS COMPLETE" | Tee-Object -FilePath work\analysis.log -Append
