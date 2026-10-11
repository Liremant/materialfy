@echo off
setlocal
:: Запуск Materialfy из исходников: cargo run --release с Qt 6.12 (MSVC).
:: Аргументы передаются программе: run_windows.bat --new-instance --light
:: Qt ищется в QTDIR, затем C:\Qt\6.12.0\msvc2022_64, %USERPROFILE%\Qt\6.12.0\msvc2022_64, %USERPROFILE%\Qt\6.12.0.
chcp 65001 >nul

where cargo >nul 2>&1
if errorlevel 1 (
    echo cargo не найден. Поставьте Rust: https://rustup.rs ^(toolchain stable-x86_64-pc-windows-msvc^)
    pause
    exit /b 1
)

set "QT="
if defined QTDIR if exist "%QTDIR%\bin\qmake6.exe" set "QT=%QTDIR%"
if not defined QT if exist "C:\Qt\6.12.0\msvc2022_64\bin\qmake6.exe" set "QT=C:\Qt\6.12.0\msvc2022_64"
if not defined QT if exist "%USERPROFILE%\Qt\6.12.0\msvc2022_64\bin\qmake6.exe" set "QT=%USERPROFILE%\Qt\6.12.0\msvc2022_64"
if not defined QT if exist "%USERPROFILE%\Qt\6.12.0\bin\qmake6.exe" set "QT=%USERPROFILE%\Qt\6.12.0"
if not defined QT (
    echo Qt 6.12 MSVC не найден. Укажите QTDIR или поставьте Qt:
    echo     python .github\scripts\install_qt.py --out C:\Qt\6.12.0\msvc2022_64
    pause
    exit /b 1
)

:: cxx-qt находит Qt по QMAKE; Qt DLL — из PATH
set "QMAKE=%QT%\bin\qmake6.exe"
set "PATH=%QT%\bin;%PATH%"

cd /d "%~dp0"
cargo run --locked --release -p materialfy -- %*
