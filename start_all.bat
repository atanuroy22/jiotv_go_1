@echo off
setlocal enabledelayedexpansion

set "DIR=%~dp0"
set "JIOTV_URL=http://localhost:5001"
set "PUBLIC_URL=https://atanu.qzz.io"
set "TIMEOUT=60"

echo ============================================
echo   JioTV Go - Auto Start + Fresh M3U Generator
echo ============================================
echo.

:: Auto-detect jiotv_go.exe (same folder as this bat)
set "BIN=%DIR%jiotv_go.exe"
if not exist "%BIN%" for /f "delims=" %%F in ('dir /b /s "%DIR%jiotv_go.exe" 2^>nul') do set "BIN=%%F"
if not exist "%BIN%" (
    echo [ERROR] jiotv_go.exe not found in this folder!
    pause
    exit /b 1
)
echo [INFO] Found: %BIN%

:: Auto-detect cloudflared
set "CF="
if exist "%DIR%cloudflared.exe" set "CF=%DIR%cloudflared.exe"
if not defined CF if exist "%DIR%cloudflared-windows-amd64.exe" set "CF=%DIR%cloudflared-windows-amd64.exe"
if not defined CF for /f "delims=" %%F in ('dir /b /s "%DIR%cloudflared*.exe" 2^>nul') do set "CF=%%F"
if defined CF echo [INFO] Found: %CF%

:: Set path prefix so JioTV Go uses local .jiotv_go folder
set "JIOTV_PATH_PREFIX=%DIR%"

:: Check if already running
echo.
echo [1/4] Checking JioTV Go...
curl.exe -s -o nul -w "%%{http_code}" "%JIOTV_URL%" 2>nul | findstr "200" >nul
if %errorlevel%==0 (
    echo [INFO] Already running.
    goto GEN
)

:: Start JioTV Go
echo [2/4] Starting JioTV Go...
start "JioTVGo" /min cmd /k "cd /d "%DIR%" && "%BIN%" serve"

echo [INFO] Waiting...
set /a N=0
:W
timeout /t 2 /nobreak >nul
set /a N+=1
curl.exe -s -o nul -w "%%{http_code}" "%JIOTV_URL%" 2>nul | findstr "200" >nul
if %errorlevel%==0 goto GEN
if %N% GEQ %TIMEOUT% (
    echo [ERROR] Timeout. Check JioTVGo window.
    pause
    exit /b 1
)
echo [INFO] Waiting... (%N%/%TIMEOUT%)
goto W

:GEN
echo.
echo [3/4] Generating M3U playlist...
echo.
powershell -ExecutionPolicy Bypass -File "%DIR%generate_render_playlist.ps1"

echo.
echo [4/4] Starting Cloudflare Tunnel...
if defined CF (
    start "Cloudflared" /min cmd /k "cd /d "%DIR%" && "%CF%" tunnel run --token eyJhIjoiZGY0ODYzO"
) else (
    echo [WARN] cloudflared not found, skipped.
)

echo.
echo ============================================
echo   DONE!
echo   Playlist: %DIR%jiotv_playlist_fresh.m3u
echo   URL: %PUBLIC_URL%/channels?type=m3u
echo ============================================
pause
