@echo off
setlocal

set "ROOT=%~dp0"
cd /d "%ROOT%"

echo [NitroGen] Checking for Python 3.10+...
where python >nul 2>&1
if %errorlevel%==0 (
    set "PY=python"
) else (
    where py >nul 2>&1
    if %errorlevel%==0 (
        set "PY=py -3"
    ) else (
        echo Python 3.10+ is required. Install it from https://www.python.org/downloads/ and re-run.
        exit /b 1
    )
)

echo [NitroGen] Creating virtual environment...
if not exist ".venv\Scripts\python.exe" (
    %PY% -m venv .venv
    if errorlevel 1 exit /b 1
)

call ".venv\Scripts\activate.bat"

echo [NitroGen] Upgrading pip...
python -m pip install --upgrade pip
if errorlevel 1 exit /b 1

echo [NitroGen] Installing NitroGen dependencies...
python -m pip install -e .
if errorlevel 1 exit /b 1

echo [NitroGen] Installing Hugging Face Hub client...
python -m pip install --upgrade huggingface_hub
if errorlevel 1 exit /b 1

echo [NitroGen] Downloading model checkpoint (ng.pt). This can be large...
set "HF_HOME=%CD%\.cache\huggingface"
python -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='nvidia/NitroGen', filename='ng.pt', local_dir='.', local_dir_use_symlinks=False)"
if errorlevel 1 exit /b 1

echo [NitroGen] Done. To launch the UI run: run_ui.bat
pause
