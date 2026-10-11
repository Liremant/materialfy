#Requires -Version 7.0
<#
.SYNOPSIS
    Сборка Materialfy (Rust + Qt 6.12) для Windows: exe, портативная папка и инсталлер Inno Setup.

.DESCRIPTION
    1. Находит Qt 6.12 MSVC (qmake6.exe, windeployqt.exe) и выставляет QMAKE/PATH для cxx-qt.
    2. cargo build --release -p materialfy (или -CargoProfile debug).
    3. Собирает target\dist\materialfy\: materialfy.exe, qml\ (src\materialfy\qml), assets\ (шрифты,
       значки), Qt через windeployqt --qmldir, рантайм MSVC.
    4. Инсталлер через Inno Setup → target\dist\Materialfy-<версия>-Setup.exe.

    Звук играет librespot внутри exe (устройство открывает cpal/WASAPI) — внешних DLL плеера нет.

.PARAMETER QtDir
    Префикс Qt (каталог с bin\qmake6.exe). По умолчанию: $env:QTDIR, каталог $env:QMAKE,
    C:\Qt\6.12.0\msvc2022_64, ~\Qt\6.12.0\msvc2022_64, ~\Qt\6.12.0.

.PARAMETER Version
    Версия в инсталлере. По умолчанию — [workspace.package] version из Cargo.toml.

.PARAMETER OutDir
    Куда класть результат. По умолчанию target\dist.

.PARAMETER CargoProfile
    Профиль cargo: release (по умолчанию) или debug.

.PARAMETER SkipBuild
    Не запускать cargo (взять готовый target\<профиль>\materialfy.exe).

.PARAMETER SkipInstaller
    Без шага Inno Setup.

.PARAMETER Portable
    Дополнительно упаковать папку в Materialfy-<версия>-windows-x64-portable.zip.
#>
param(
    [string]$QtDir,
    [string]$Version,
    [string]$OutDir,
    [ValidateSet("release", "debug")]
    [string]$CargoProfile = "release",
    [switch]$SkipBuild,
    [switch]$SkipInstaller,
    [switch]$Portable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
# русский вывод в любой консоли (cp866/cp1251)
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

$AppName = "Materialfy"
$ExeName = "materialfy.exe"
$FilePrefix = "Materialfy"

$ProjectRoot = $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot "target\dist" }
$OutDir = [IO.Path]::GetFullPath($OutDir)
$Stage = Join-Path $OutDir "materialfy"

function Write-Step { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "    WARN: $msg" -ForegroundColor Yellow }
function Abort      { param([string]$msg) Write-Host "`nОШИБКА: $msg" -ForegroundColor Red; exit 1 }

# ─── Версия ───────────────────────────────────────────────────────────────────
if (-not $Version) {
    $cargoToml = Get-Content (Join-Path $ProjectRoot "Cargo.toml") -Raw
    if ($cargoToml -match '(?ms)^\[workspace\.package\].*?^version\s*=\s*"([^"]+)"') {
        $Version = $Matches[1]
    } else {
        $Version = "0.0.0"
    }
}
$Version = $Version.TrimStart("v")
Write-Host "$AppName $Version → $OutDir" -ForegroundColor White

# ─── 1. Qt ────────────────────────────────────────────────────────────────────
Write-Step "Поиск Qt 6.12 (MSVC)"
$candidates = @()
if ($QtDir) { $candidates += $QtDir }
if ($env:QTDIR) { $candidates += $env:QTDIR }
if ($env:QMAKE) { $candidates += (Split-Path (Split-Path $env:QMAKE)) }
$candidates += @(
    "C:\Qt\6.12.0\msvc2022_64",
    (Join-Path $HOME "Qt\6.12.0\msvc2022_64"),
    (Join-Path $HOME "Qt\6.12.0")
)
$QtDir = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c "bin\qmake6.exe"))) { $QtDir = (Resolve-Path $c).Path; break }
}
if (-not $QtDir) {
    Abort ("Qt 6.12 MSVC не найден. Укажите -QtDir или поставьте его:`n" +
        "    python .github\scripts\install_qt.py --out C:\Qt\6.12.0\msvc2022_64")
}
$Qmake = Join-Path $QtDir "bin\qmake6.exe"
$WinDeployQt = Join-Path $QtDir "bin\windeployqt.exe"
if (-not (Test-Path $WinDeployQt)) { $WinDeployQt = Join-Path $QtDir "bin\windeployqt6.exe" }
if (-not (Test-Path $WinDeployQt)) { Abort "windeployqt не найден в $QtDir\bin" }
$env:QMAKE = $Qmake
$env:QTDIR = $QtDir
$env:PATH = "$QtDir\bin;$env:PATH"
Write-Ok "$QtDir ($(& $Qmake -query QT_VERSION))"

# ─── 2. cargo build ───────────────────────────────────────────────────────────
$Exe = Join-Path $ProjectRoot "target\$CargoProfile\$ExeName"
if (-not $SkipBuild) {
    Write-Step "cargo build ($CargoProfile) -p materialfy"
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        Abort "cargo не найден. Поставьте Rust: https://rustup.rs (toolchain stable-x86_64-pc-windows-msvc)"
    }
    Push-Location $ProjectRoot
    try {
        # --locked: Cargo.lock держит vergen 9.0.6 (9.1 ломает build-скрипт librespot-core)
        if ($CargoProfile -eq "release") {
            cargo build --locked --release -p materialfy
        } else {
            cargo build --locked -p materialfy
        }
        if ($LASTEXITCODE -ne 0) { Abort "cargo build завершился с ошибкой" }
    } finally {
        Pop-Location
    }
}
if (-not (Test-Path $Exe)) { Abort "Нет $Exe" }
Write-Ok $Exe

# ─── 3. Папка дистрибутива ────────────────────────────────────────────────────
Write-Step "Сборка $Stage"
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force $Stage | Out-Null
Copy-Item $Exe $Stage

# QML и ресурсы — рядом с exe: оболочка ищет <exe>\qml, assets — соседний каталог
$srcQml = Join-Path $ProjectRoot "src\materialfy\qml"
$srcAssets = Join-Path $ProjectRoot "src\materialfy\assets"
Copy-Item $srcQml (Join-Path $Stage "qml") -Recurse
Get-ChildItem (Join-Path $Stage "qml") -Recurse -Directory -Filter "__pycache__" |
    Remove-Item -Recurse -Force
$assets = Join-Path $Stage "assets"
New-Item -ItemType Directory -Force $assets | Out-Null
Copy-Item (Join-Path $srcAssets "fonts") (Join-Path $assets "fonts") -Recurse   # fonts-src (исходники шрифтов) не нужен
Get-ChildItem $srcAssets -File | Where-Object { $_.Extension -in ".svg", ".png" } |
    Copy-Item -Destination $assets

$deployArgs = @("--qmldir", $srcQml, "--no-opengl-sw", "--no-compiler-runtime", "--translations", "ru")   # интерфейс только русский
if ($CargoProfile -eq "release") { $deployArgs = @("--release") + $deployArgs }
& $WinDeployQt @deployArgs (Join-Path $Stage $ExeName)
if ($LASTEXITCODE -ne 0) { Abort "windeployqt завершился с ошибкой $LASTEXITCODE" }
Write-Ok "Qt разложен windeployqt"

# Рантайм MSVC (vcruntime140*.dll, msvcp140*.dll) кладём рядом с exe — без vc_redist у пользователя
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$crtDir = $null
if (Test-Path $vswhere) {
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath | Select-Object -First 1
    if ($vs) {
        $crtDir = Get-ChildItem (Join-Path $vs "VC\Redist\MSVC") -Directory -ErrorAction SilentlyContinue |
            Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } -Descending |
            ForEach-Object { Get-ChildItem (Join-Path $_.FullName "x64") -Directory -Filter "Microsoft.VC*.CRT" -ErrorAction SilentlyContinue } |
            Select-Object -First 1
    }
}
if ($crtDir) {
    Copy-Item (Join-Path $crtDir.FullName "*.dll") $Stage
    Write-Ok "рантайм MSVC: $($crtDir.FullName)"
} else {
    Write-Warn "рантайм MSVC не найден — на чистой системе понадобится Visual C++ Redistributable"
}

$sizeMB = [math]::Round(((Get-ChildItem $Stage -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB, 0)
Write-Ok "папка готова: $Stage ($sizeMB МБ)"

if ($Portable) {
    $zip = Join-Path $OutDir "$FilePrefix-$Version-windows-x64-portable.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $zip -CompressionLevel Optimal
    Write-Ok "портативный архив: $zip"
}

if ($SkipInstaller) {
    Write-Host "`nГотово: $Stage\$ExeName (Inno Setup пропущен)" -ForegroundColor Green
    exit 0
}

# ─── 4. Inno Setup ────────────────────────────────────────────────────────────
Write-Step "Поиск Inno Setup"
$iscc = $null
$isccCmd = Get-Command ISCC -ErrorAction SilentlyContinue
foreach ($candidate in @(
    $(if ($isccCmd) { $isccCmd.Source }),
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)) {
    if ($candidate -and (Test-Path $candidate)) { $iscc = $candidate; break }
}
if (-not $iscc) {
    Write-Warn "Inno Setup 6 не найден (winget install JRSoftware.InnoSetup) — инсталлер пропущен"
    Write-Host "`nГотово: $Stage\$ExeName" -ForegroundColor Green
    exit 0
}
Write-Ok $iscc

Write-Step "Сборка инсталлера"
# VersionInfoVersion — только числа: 0.2.0-rc1 → 0.2.0
$numVersion = ($Version -split '[-+]')[0]
& $iscc "/Qp" "/DAppVersion=$Version" "/DAppNumVersion=$numVersion" "/DDistDir=$Stage" "/O$OutDir" (Join-Path $ProjectRoot "materialfy.iss")
if ($LASTEXITCODE -ne 0) { Abort "Inno Setup завершился с ошибкой $LASTEXITCODE" }

$setupExe = Join-Path $OutDir "$FilePrefix-$Version-Setup.exe"
if (-not (Test-Path $setupExe)) { Abort "Нет $setupExe после ISCC" }
$sizeMB = [math]::Round((Get-Item $setupExe).Length / 1MB, 0)
Write-Host "`nГотово:" -ForegroundColor Green
Write-Host "  Инсталлер:  $setupExe ($sizeMB МБ)" -ForegroundColor White
Write-Host "  Portable:   $Stage\$ExeName" -ForegroundColor White
