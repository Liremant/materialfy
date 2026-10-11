@echo off
setlocal
:: Runs Materialfy from source: cargo run --release with Qt 6.12 (MSVC).
:: Arguments are passed to the app: run_windows.bat --new-instance --light
:: Qt is looked up in QTDIR, then C:\Qt\6.12.0\msvc2022_64, %USERPROFILE%\Qt\6.12.0\msvc2022_64, %USERPROFILE%\Qt\6.12.0.
chcp 65001 >nul

where cargo >nul 2>&1
if errorlevel 1 (
    echo cargo not found. Install Rust: https://rustup.rs ^(toolchain stable-x86_64-pc-windows-msvc^)
    pause
    exit /b 1
)

set "QT="
if defined QTDIR if exist "%QTDIR%\bin\qmake6.exe" set "QT=%QTDIR%"
if not defined QT if exist "C:\Qt\6.12.0\msvc2022_64\bin\qmake6.exe" set "QT=C:\Qt\6.12.0\msvc2022_64"
if not defined QT if exist "%USERPROFILE%\Qt\6.12.0\msvc2022_64\bin\qmake6.exe" set "QT=%USERPROFILE%\Qt\6.12.0\msvc2022_64"
if not defined QT if exist "%USERPROFILE%\Qt\6.12.0\bin\qmake6.exe" set "QT=%USERPROFILE%\Qt\6.12.0"
if not defined QT (
    echo Qt 6.12 MSVC not found. Set QTDIR or install Qt:
    echo     python .github\scripts\install_qt.py --out C:\Qt\6.12.0\msvc2022_64
    pause
    exit /b 1
)

:: cxx-qt finds Qt through QMAKE; Qt DLLs come from PATH
set "QMAKE=%QT%\bin\qmake6.exe"
set "PATH=%QT%\bin;%PATH%"

cd /d "%~dp0"
cargo run --locked --release -p materialfy -- %*
