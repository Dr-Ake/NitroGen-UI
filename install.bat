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
set "TORCH_CUDA_STABLE=cu130"
set "TORCH_CUDA_FALLBACKS=cu124 cu121"
set "TORCH_CUDA_NIGHTLY=cu130"
set "TORCHVISION_NO_DEPS="
set "ALLOW_TORCHVISION_FAIL="
set "GPU_NAME="
set "NEED_NIGHTLY="
if defined FORCE_TORCH_CUDA (
    set "TORCH_CUDA_STABLE=%FORCE_TORCH_CUDA%"
    set "TORCH_CUDA_NIGHTLY=%FORCE_TORCH_CUDA%"
    set "TORCH_CUDA_FALLBACKS="
)
where nvidia-smi >nul 2>&1 && set "HAS_NVIDIA=1"
if not defined HAS_NVIDIA (
    wmic path win32_VideoController get name | find /I "NVIDIA" >nul 2>&1 && set "HAS_NVIDIA=1"
)

if defined HAS_NVIDIA (
    if /I "%FORCE_TORCH_NIGHTLY%"=="1" set "NEED_NIGHTLY=1"
    for /f "usebackq tokens=1,* delims=:" %%A in (`nvidia-smi -L 2^>nul`) do if not defined GPU_NAME set "GPU_NAME=%%B"
    if not defined GPU_NAME (
        for /f "skip=1 tokens=* delims=" %%A in ('wmic path win32_VideoController get name ^| find /I "NVIDIA" 2^>nul') do if not defined GPU_NAME set "GPU_NAME=%%A"
    )
    if /I "%FORCE_TORCH_STABLE%"=="1" (
        set "NEED_NIGHTLY="
        echo [NitroGen] Forcing stable PyTorch build: FORCE_TORCH_STABLE=1.
    )
    if defined NEED_NIGHTLY (
        set "TORCH_INDEX=https://download.pytorch.org/whl/nightly/!TORCH_CUDA_NIGHTLY!"
        set "TORCH_PRE=--pre"
        set "TORCHVISION_NO_DEPS=--no-deps"
        set "ALLOW_TORCHVISION_FAIL=1"
        echo [NitroGen] Using PyTorch nightly build: FORCE_TORCH_NIGHTLY=1.
    ) else (
        echo [NitroGen] Using stable PyTorch build for detected NVIDIA GPU.
    )
    if defined GPU_NAME (
        echo [NitroGen] GPU: !GPU_NAME!
    ) else (
        echo [NitroGen] GPU: NVIDIA (name unavailable)
    )
    echo [NitroGen] NVIDIA GPU detected. Installing CUDA-enabled PyTorch...
    python -m pip uninstall -y torch torchvision torchaudio >nul 2>&1
    if defined NEED_NIGHTLY (
        echo [NitroGen] PyTorch index: !TORCH_INDEX!
        python -m pip install !TORCH_PRE! torch --index-url !TORCH_INDEX!
        if errorlevel 1 goto :fail
    ) else (
        set "TORCH_INSTALLED="
        set "TORCH_CUDA_USED="
        for %%C in (!TORCH_CUDA_STABLE! !TORCH_CUDA_FALLBACKS!) do (
            if not defined TORCH_INSTALLED (
                set "TORCH_INDEX=https://download.pytorch.org/whl/%%C"
                echo [NitroGen] Trying PyTorch index: !TORCH_INDEX!
                python -m pip install !TORCH_PRE! torch --index-url !TORCH_INDEX!
                if not errorlevel 1 (
                    set "TORCH_INSTALLED=1"
                    set "TORCH_CUDA_USED=%%C"
                )
            )
        )
        if not defined TORCH_INSTALLED goto :fail
        echo [NitroGen] PyTorch index: !TORCH_INDEX!
    )
    if /I "%SKIP_TORCHVISION%"=="1" (
        echo [NitroGen] Skipping torchvision install (SKIP_TORCHVISION=1).
    ) else (
        python -m pip install !TORCH_PRE! torchvision !TORCHVISION_NO_DEPS! --index-url !TORCH_INDEX!
        if errorlevel 1 (
            if defined ALLOW_TORCHVISION_FAIL (
                echo [NitroGen] Warning: torchvision install failed. Continuing with torch only.
                cmd /c exit /b 0
            ) else (
                goto :fail
            )
        )
    )
) else (
    echo [NitroGen] No NVIDIA GPU detected. Installing CPU-only PyTorch...
    python -m pip uninstall -y torch torchvision torchaudio >nul 2>&1
    python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
    if errorlevel 1 goto :fail
)

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
