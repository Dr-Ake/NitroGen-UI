@echo off
setlocal EnableDelayedExpansion

set "ROOT=%~dp0"
cd /d "%ROOT%"

set "STEP=Checking for Python 3.10+"
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
        goto :fail
    )
)

set "STEP=Creating virtual environment"
echo [NitroGen] Creating virtual environment...
if not exist ".venv\Scripts\python.exe" (
    %PY% -m venv .venv
    if errorlevel 1 goto :fail
)

call ".venv\Scripts\activate.bat"

set "STEP=Upgrading pip"
echo [NitroGen] Upgrading pip...
python -m pip install --upgrade pip
if errorlevel 1 goto :fail

set "STEP=Installing PyTorch"
echo [NitroGen] Detecting NVIDIA GPU for CUDA support...
set "HAS_NVIDIA="
set "TORCH_INDEX="
set "TORCH_PRE="
set "GPU_NAME="
set "NEED_NIGHTLY="
where nvidia-smi >nul 2>&1 && set "HAS_NVIDIA=1"
if not defined HAS_NVIDIA (
    wmic path win32_VideoController get name | find /I "NVIDIA" >nul 2>&1 && set "HAS_NVIDIA=1"
)

if defined HAS_NVIDIA (
    for /f "usebackq delims=" %%A in (`nvidia-smi --query-gpu=name --format=csv,noheader 2^>nul`) do if not defined GPU_NAME set "GPU_NAME=%%A"
    if not defined GPU_NAME (
        for /f "skip=1 tokens=* delims=" %%A in ('wmic path win32_VideoController get name ^| find /I "NVIDIA" 2^>nul') do if not defined GPU_NAME set "GPU_NAME=%%A"
    )
    if /I "%FORCE_TORCH_NIGHTLY%"=="1" set "NEED_NIGHTLY=1"
    if defined GPU_NAME (
        set "GPU_NAME=!GPU_NAME: =!"
        echo !GPU_NAME! | find /I "RTX50" >nul && set "NEED_NIGHTLY=1"
        echo !GPU_NAME! | find /I "RTX 50" >nul && set "NEED_NIGHTLY=1"
    )
    if defined NEED_NIGHTLY (
        set "TORCH_INDEX=https://download.pytorch.org/whl/nightly/cu124"
        set "TORCH_PRE=--pre"
        echo [NitroGen] Using PyTorch nightly for RTX 50xx support...
    ) else (
        set "TORCH_INDEX=https://download.pytorch.org/whl/cu121"
        echo [NitroGen] Using stable CUDA build for detected NVIDIA GPU.
    )
    if defined GPU_NAME (
        echo [NitroGen] GPU: !GPU_NAME!
    )
    echo [NitroGen] PyTorch index: !TORCH_INDEX!
    echo [NitroGen] NVIDIA GPU detected. Installing CUDA-enabled PyTorch...
    python -m pip uninstall -y torch torchvision torchaudio >nul 2>&1
    python -m pip install !TORCH_PRE! torch torchvision --index-url !TORCH_INDEX!
) else (
    echo [NitroGen] No NVIDIA GPU detected. Installing CPU-only PyTorch...
    python -m pip uninstall -y torch torchvision torchaudio >nul 2>&1
    python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 goto :fail

set "STEP=Installing NitroGen dependencies"
echo [NitroGen] Installing NitroGen dependencies...
python -m pip install -e .
if errorlevel 1 goto :fail

set "STEP=Installing Hugging Face Hub client"
echo [NitroGen] Installing Hugging Face Hub client (compatible version)...
python -m pip install "huggingface_hub>=0.34.0,<1.0"
if errorlevel 1 goto :fail

set "STEP=Downloading model checkpoint"
echo [NitroGen] Downloading model checkpoint (ng.pt). This can be large...
set "HF_HOME=%CD%\.cache\huggingface"
python -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='nvidia/NitroGen', filename='ng.pt', local_dir='.', local_dir_use_symlinks=False)"
if errorlevel 1 goto :fail

echo [NitroGen] Done. To launch the UI run: run_ui.bat
pause
exit /b 0

:fail
echo [NitroGen] Install failed during: %STEP%
pause
exit /b 1
