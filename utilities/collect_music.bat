@echo off
REM Music Collector Batch File - COPIES music files (does NOT move/delete originals)
REM Usage: collect_music.bat [source_dir] [dest_dir] [genre] [size]

setlocal enabledelayedexpansion

REM Robust argument parsing
set "ARG1=%~1"
set "ARG2=%~2"
set "ARG3=%~3"
set "ARG4=%~4"

REM Remove any surrounding quotes
set ARG1=%ARG1:"=%
set ARG2=%ARG2:"=%
set ARG3=%ARG3:"=%
set ARG4=%ARG4:"=%

REM Debug: Show what we received
echo DEBUG: Arguments received:
echo   SOURCE_DIR: [%ARG1%]
echo   DEST_DIR: [%ARG2%]
echo   GENRE: [%ARG3%]
echo   SIZE: [%ARG4%]
echo.

REM If any argument is missing, show usage
if "%ARG1%"=="" goto usage
if "%ARG2%"=="" goto usage
if "%ARG3%"=="" goto usage
if "%ARG4%"=="" goto usage

goto continue

:usage
echo Music Collector - Windows Batch File
echo.
echo NOTE: This script COPIES files (does NOT move or delete originals)
echo.
echo Usage: collect_music.bat [source_dir] [dest_dir] [genre] [size]
echo.
echo Format: collect_music.bat "SOURCE_FOLDER" "DESTINATION_FOLDER" GENRE SIZE
echo.
echo Examples:
echo   collect_music.bat "C:\Music" "D:\Country_Collection" country 1gb
echo   collect_music.bat "C:\Music" "E:\Random_Collection" random 500mb
echo   collect_music.bat "C:\Music" "F:\Rock_Collection" rock 2gb
echo.
echo For thumbdrive usage:
echo   collect_music.bat "C:\Music" "E:\Country_Test" country 500mb
echo   collect_music.bat "C:\Music" "F:\Rock_Test" rock 1gb
echo.
echo Parameters:
echo   SOURCE_FOLDER: Where your music is stored (e.g., "C:\Music")
echo   DESTINATION_FOLDER: Where to copy files (e.g., "E:\MyCollection")
echo   GENRE: Music genre or "random" (e.g., country, rock, jazz)
echo   SIZE: Amount to copy (e.g., 1gb, 500mb, 2.5gb)
echo.
pause
exit /b 1

:continue
REM Check if source directory exists
if not exist "%ARG1%" (
    echo Error: Source directory does not exist: %ARG1%
    pause
    exit /b 1
)

REM Check if destination directory is provided
if "%ARG2%"=="" (
    echo Error: Destination directory is required
    echo Usage: collect_music.bat [source_dir] [dest_dir] [genre] [size]
    pause
    exit /b 1
)

REM Create destination directory if it doesn't exist
if not exist "%ARG2%" (
    echo Creating destination directory: %ARG2%
    mkdir "%ARG2%"
)

REM Determine if it's random selection
set "RANDOM_FLAG="
if /i "%ARG3%"=="random" (
    set "RANDOM_FLAG=--random"
    set "ARG3="
)

REM Check if music_collector.py exists
if not exist "music_collector.py" (
    echo ERROR: music_collector.py not found in current directory
    echo Current directory: %CD%
    echo Please run this from the same directory as music_collector.py
    pause
    exit /b 1
)

REM Build the command
set "CMD=python music_collector.py --source "%ARG1%" --dest "%ARG2%" --size %ARG4%"

if not "%ARG3%"=="" (
    set "CMD=%CMD% --genre %ARG3%"
)

if not "%RANDOM_FLAG%"=="" (
    set "CMD=%CMD% %RANDOM_FLAG%"
)

REM Add force rescan option if requested (you can add this as a 5th argument)
if not "%~5"=="" (
    if /i "%~5"=="--force-rescan" (
        set "CMD=%CMD% --force-rescan"
    )
    if /i "%~5"=="--cache-only" (
        set "CMD=%CMD% --cache-only"
    )
)

echo Running: %CMD%
echo.
echo NOTE: Files will be COPIED (not moved) to: %ARG2%
echo.

REM Run the script
%CMD%

echo.
echo Collection complete! Files copied to: %ARG2%
echo Original files remain unchanged in: %ARG1%
pause 