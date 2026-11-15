@echo off
REM Serves the Development folder on http://localhost:8080/ (needs Python 3)
cd /d "%~dp0"
start "" http://localhost:8080/
python -m http.server 8080
