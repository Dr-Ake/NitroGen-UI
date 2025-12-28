@echo off
setlocal EnableDelayedExpansion

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
set "TORCH_INDEX="
set "TORCH_PRE="
set "CC="
set "CC_MAJOR="
set "GPU_NAME="
where nvidia-smi >nul 2>&1 && set "HAS_NVIDIA=1"
if not defined HAS_NVIDIA (
    wmic path win32_VideoController get name | find /I "NVIDIA" >nul 2>&1 && set "HAS_NVIDIA=1"
)

if defined HAS_NVIDIA (
    for /f "usebackq delims=" %%A in (`nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2^>nul`) do if not defined CC set "CC=%%A"
    if not defined CC (
        for /f "usebackq delims=" %%A in (`nvidia-smi --query-gpu=compute_capability --format=csv,noheader 2^>nul`) do if not defined CC set "CC=%%A"
    )
    if defined CC (
        set "CC=!CC: =!"
        for /f "tokens=1 delims=." %%A in ("!CC!") do set "CC_MAJOR=%%A"
    )
    if not defined CC_MAJOR (
        for /f "usebackq delims=" %%A in (`nvidia-smi --query-gpu=name --format=csv,noheader 2^>nul`) do if not defined GPU_NAME set "GPU_NAME=%%A"
        if defined GPU_NAME (
            set "GPU_NAME=!GPU_NAME: =!"
            echo !GPU_NAME! | find /I "RTX50" >nul && set "CC_MAJOR=12"
        )
    )
    if defined CC_MAJOR if !CC_MAJOR! GEQ 12 (
        if defined CC (
            echo [NitroGen] Detected compute capability !CC!. Using PyTorch nightly for RTX 50xx support...
        ) else (
            echo [NitroGen] Detected RTX 50xx GPU. Using PyTorch nightly for support...
        )
        set "TORCH_INDEX=https://download.pytorch.org/whl/nightly/cu124"
        set "TORCH_PRE=--pre"
    ) else (
        set "TORCH_INDEX=https://download.pytorch.org/whl/cu121"
    )
    echo [NitroGen] NVIDIA GPU detected. Installing CUDA-enabled PyTorch...
    python -m pip install !TORCH_PRE! torch torchvision --index-url !TORCH_INDEX!
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
