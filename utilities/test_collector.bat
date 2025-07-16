@echo off
echo Testing Music Collector Setup
echo ============================

echo.
echo 1. Checking Python installation...
python --version
if %errorlevel% neq 0 (
    echo ERROR: Python not found or not in PATH
    echo Please install Python/Anaconda
    pause
    exit /b 1
)

echo.
echo 2. Checking if music_collector.py exists...
if exist "music_collector.py" (
    echo Found music_collector.py
) else (
    echo ERROR: music_collector.py not found in current directory
    echo Please run this from the same directory as music_collector.py
    pause
    exit /b 1
)

echo.
echo 3. Checking ffprobe installation...
set "FFMPEG_PATH=C:\Users\cayuse\ffmpeg-2025-07-10-git-82aeee3c19-essentials_build\bin"
if exist "%FFMPEG_PATH%\ffprobe.exe" (
    echo Found ffprobe.exe at: %FFMPEG_PATH%
) else (
    echo ERROR: ffprobe.exe not found at: %FFMPEG_PATH%
    echo Please check your ffmpeg installation
    pause
    exit /b 1
)

echo.
echo 4. Testing ffprobe...
"%FFMPEG_PATH%\ffprobe.exe" -version
if %errorlevel% neq 0 (
    echo ERROR: ffprobe.exe is not working
    pause
    exit /b 1
)

echo.
echo 5. Testing Python script with help...
python music_collector.py --help
if %errorlevel% neq 0 (
    echo ERROR: Python script is not working
    pause
    exit /b 1
)

echo.
echo ============================
echo All tests passed! 
echo.
echo Now try running:
echo collect_music.bat "C:\YourMusicFolder" "E:\YourThumbDrive\Test" country 100mb
echo.
pause 