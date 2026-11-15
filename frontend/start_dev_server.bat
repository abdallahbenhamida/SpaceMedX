@echo off
REM Crew Health Monitor (standalone frontend, demo data): serves this folder on http://localhost:8080/ (needs Python 3)
REM If the port is already taken (e.g. another copy of the UI is still running),
REM the browser would silently talk to that other server - so stop here instead.
cd /d "%~dp0"
netstat -an | findstr /C:":8080 " | findstr /C:"LISTENING" >nul
if not errorlevel 1 (
  echo.
  echo  Port 8080 is already in use - another dev server is still running.
  echo  Close its window ^(or end python.exe in Task Manager^), then run this again.
  echo.
  pause
  exit /b 1
)
echo  Crew Health Monitor (standalone frontend, demo data) -^> http://localhost:8080/   ^(Ctrl+C to stop^)
echo  Tip: if the page looks outdated, reload it with Ctrl+F5.
start "" http://localhost:8080/
python -m http.server 8080
