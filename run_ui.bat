@echo off
setlocal
set "ROOT=%~dp0"
cd /d "%ROOT%"
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" scripts\ui.py
) else (
    python scripts\ui.py
)
