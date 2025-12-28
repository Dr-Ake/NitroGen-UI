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

echo [NitroGen] Detecting NVIDIA GPU for CUDA support...
set "HAS_NVIDIA="
where nvidia-smi >nul 2>&1 && set "HAS_NVIDIA=1"
if not defined HAS_NVIDIA (
    wmic path win32_VideoController get name | find /I "NVIDIA" >nul 2>&1 && set "HAS_NVIDIA=1"
)

if defined HAS_NVIDIA (
    echo [NitroGen] NVIDIA GPU detected. Installing CUDA-enabled PyTorch...
    python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
) else (
    echo [NitroGen] No NVIDIA GPU detected. Installing CPU-only PyTorch...
    python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 exit /b 1

echo [NitroGen] Installing NitroGen dependencies...
python -m pip install -e .
if errorlevel 1 exit /b 1

echo [NitroGen] Installing Hugging Face Hub client (compatible version)...
python -m pip install "huggingface_hub>=0.34.0,<1.0"
if errorlevel 1 exit /b 1

echo [NitroGen] Downloading model checkpoint (ng.pt). This can be large...
set "HF_HOME=%CD%\.cache\huggingface"
python -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='nvidia/NitroGen', filename='ng.pt', local_dir='.', local_dir_use_symlinks=False)"
if errorlevel 1 exit /b 1

echo [NitroGen] Done. To launch the UI run: run_ui.bat
pause
