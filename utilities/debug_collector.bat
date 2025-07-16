@echo off
echo Debug Music Collector
echo ====================

echo.
echo Running debug test...
python debug_collector.py --debug

echo.
echo Testing with sample arguments...
python debug_collector.py --source "C:\Music" --dest "E:\Test" --genre country --size 100mb

echo.
echo If you're still having issues, please:
echo 1. Run: test_collector.bat
echo 2. Tell me what error messages you see
echo 3. Try running the Python script directly:
echo    python music_collector.py --source "C:\Music" --dest "E:\Test" --genre country --size 100mb
echo.
pause 