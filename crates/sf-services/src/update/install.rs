//! Applying a verified update. Each kind returns what the app does next: quit (a helper or the installer
//! replaces the files and starts the new version) or keep running (macOS: the disk image is opened).
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use super::release::InstallKind;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome {
    /// the app must quit now; the new version starts by itself
    Quit,
    /// the installer was opened; the app keeps running
    HandedOff,
}

/// Inno Setup flags of a silent update; /RELAUNCH starts the app again (materialfy.iss, [Run]).
pub const SETUP_ARGS: [&str; 6] = ["/SILENT", "/SP-", "/NOCANCEL", "/NORESTART", "/CLOSEAPPLICATIONS", "/RELAUNCH"];

pub fn install(kind: InstallKind, file: &Path, work_dir: &Path) -> Result<Outcome, String> {
    match kind {
        InstallKind::WindowsInstaller => run_setup(file),
        InstallKind::WindowsPortable => replace_portable(file, work_dir),
        InstallKind::AppImage => replace_appimage(file),
        InstallKind::MacApp => open_dmg(file),
        InstallKind::Manual | InstallKind::Dev => Err(mf_i18n::t("This copy of Materialfy can't update itself")),
    }
}

fn io_text(error: std::io::Error) -> String {
    error.to_string()
}

#[cfg(windows)]
fn detached(command: &mut Command) -> &mut Command {
    use std::os::windows::process::CommandExt;
    const DETACHED_PROCESS: u32 = 0x0000_0008;
    const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    command.creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW)
}

#[cfg(not(windows))]
fn detached(command: &mut Command) -> &mut Command {
    command
}

fn run_setup(file: &Path) -> Result<Outcome, String> {
    let mut command = Command::new(file);
    command.args(SETUP_ARGS).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    // the setup window (progress of a /SILENT install) must stay visible: no CREATE_NO_WINDOW here
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x0000_0200); // CREATE_NEW_PROCESS_GROUP
    }
    command.spawn().map_err(io_text)?;
    Ok(Outcome::Quit)
}

/// Directory with materialfy(.exe) inside an unpacked archive: the root or its only subdirectory.
pub fn app_root(extracted: &Path, exe_name: &str) -> Option<PathBuf> {
    if extracted.join(exe_name).is_file() {
        return Some(extracted.to_path_buf());
    }
    let dirs: Vec<PathBuf> = std::fs::read_dir(extracted).ok()?.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect();
    match dirs.as_slice() {
        [only] if only.join(exe_name).is_file() => Some(only.clone()),
        _ => None,
    }
}

/// PowerShell helper of a portable update: waits for the app to exit, copies the new files over the old
/// ones (qml\ is mirrored so files dropped in the new version go away), starts the app, cleans up.
pub const PORTABLE_HELPER: &str = r#"param([int]$ProcId, [string]$Source, [string]$Target, [string]$Exe, [string]$Log)
$ErrorActionPreference = 'Continue'
function Write-Log($text) { Add-Content -LiteralPath $Log -Value ("{0:u} {1}" -f (Get-Date), $text) }
Write-Log "update: waiting for process $ProcId"
try { Wait-Process -Id $ProcId -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 500
$ok = $false
for ($i = 0; $i -lt 30 -and -not $ok; $i++) {
    & robocopy.exe $Source $Target /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $code = $LASTEXITCODE
    if ($code -lt 8) { $ok = $true } else { Write-Log "robocopy exit $code, retrying"; Start-Sleep -Seconds 1 }
}
if ($ok -and (Test-Path -LiteralPath (Join-Path $Source 'qml'))) {
    & robocopy.exe (Join-Path $Source 'qml') (Join-Path $Target 'qml') /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
}
Write-Log ("update: copy " + $(if ($ok) { 'done' } else { 'FAILED' }))
Start-Process -FilePath $Exe -WorkingDirectory $Target
if ($ok) { Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue }
"#;

fn replace_portable(file: &Path, work_dir: &Path) -> Result<Outcome, String> {
    let exe = std::env::current_exe().map_err(io_text)?;
    let target = exe.parent().ok_or("no exe directory")?.to_path_buf();
    let exe_name = exe.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "materialfy.exe".into());
    // the app directory must be writable, or the helper would fail after the app is gone
    let probe = target.join(".materialfy-update-probe");
    std::fs::write(&probe, b"").map_err(|e| mf_i18n::tr!("Can't write to {0}: {1}", target.display(), e))?;
    let _ = std::fs::remove_file(&probe);

    let extract = work_dir.join("portable");
    let _ = std::fs::remove_dir_all(&extract);
    std::fs::create_dir_all(&extract).map_err(io_text)?;
    unzip(file, &extract)?;
    let source = app_root(&extract, &exe_name).ok_or_else(|| mf_i18n::t("The archive doesn't contain Materialfy"))?;

    let script = work_dir.join("apply-portable-update.ps1");
    std::fs::write(&script, PORTABLE_HELPER).map_err(io_text)?;
    let log = work_dir.join("update.log");
    let mut command = Command::new(system_tool("WindowsPowerShell\\v1.0\\powershell.exe", "powershell.exe"));
    command
        .args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File"])
        .arg(&script)
        .arg("-ProcId")
        .arg(std::process::id().to_string())
        .arg("-Source")
        .arg(&source)
        .arg("-Target")
        .arg(&target)
        .arg("-Exe")
        .arg(&exe)
        .arg("-Log")
        .arg(&log)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    detached(&mut command).spawn().map_err(io_text)?;
    Ok(Outcome::Quit)
}

/// %SystemRoot%\System32\<relative>, or the bare name through PATH.
fn system_tool(relative: &str, fallback: &str) -> PathBuf {
    std::env::var_os("SystemRoot")
        .map(|root| PathBuf::from(root).join("System32").join(relative))
        .filter(|p| p.is_file())
        .unwrap_or_else(|| PathBuf::from(fallback))
}

/// Unpacks a zip with the tools Windows ships: tar.exe (bsdtar, Windows 10 1803+), else Expand-Archive.
fn unzip(file: &Path, into: &Path) -> Result<(), String> {
    let quiet = |command: &mut Command| {
        command.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::piped());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
        }
    };
    let mut tar = Command::new(system_tool("tar.exe", "tar"));
    tar.arg("-xf").arg(file).arg("-C").arg(into);
    quiet(&mut tar);
    if tar.output().is_ok_and(|out| out.status.success()) {
        return Ok(());
    }
    let mut ps = Command::new(system_tool("WindowsPowerShell\\v1.0\\powershell.exe", "powershell.exe"));
    ps.args(["-NoProfile", "-NonInteractive", "-Command", "Expand-Archive -LiteralPath $args[0] -DestinationPath $args[1] -Force"])
        .arg(file)
        .arg(into);
    quiet(&mut ps);
    let out = ps.output().map_err(io_text)?;
    if out.status.success() {
        Ok(())
    } else {
        let detail = String::from_utf8_lossy(&out.stderr).trim().to_owned();
        Err(mf_i18n::tr!("Couldn't unpack the update: {0}", detail))
    }
}

/// New AppImage next to the old one, made executable, renamed over it (atomic on one file system);
/// a shell waits for this process to exit and starts it.
fn replace_appimage(file: &Path) -> Result<Outcome, String> {
    let current = std::env::var_os("APPIMAGE").map(PathBuf::from).ok_or("APPIMAGE is not set")?;
    let dir = current.parent().ok_or("no AppImage directory")?;
    let name = current.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let staged = dir.join(format!(".{name}.update"));
    std::fs::copy(file, &staged).map_err(|e| mf_i18n::tr!("Can't write to {0}: {1}", dir.display(), e))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&staged, std::fs::Permissions::from_mode(0o755)).map_err(io_text)?;
    }
    if let Err(error) = std::fs::rename(&staged, &current) {
        let _ = std::fs::remove_file(&staged);
        return Err(io_text(error));
    }
    let script = format!(
        "while kill -0 {pid} 2>/dev/null; do sleep 0.2; done; exec \"$0\"",
        pid = std::process::id()
    );
    Command::new("/bin/sh")
        .arg("-c")
        .arg(script)
        .arg(&current)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(io_text)?;
    Ok(Outcome::Quit)
}

fn open_dmg(file: &Path) -> Result<Outcome, String> {
    let status = Command::new("open").arg(file).status().map_err(io_text)?;
    if status.success() { Ok(Outcome::HandedOff) } else { Err(format!("open: {status}")) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_app_root() {
        let base = std::env::temp_dir().join(format!("mf-update-root-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let flat = base.join("flat");
        std::fs::create_dir_all(flat.join("qml")).unwrap();
        std::fs::write(flat.join("materialfy.exe"), b"").unwrap();
        assert_eq!(app_root(&flat, "materialfy.exe"), Some(flat.clone()));

        let nested = base.join("nested");
        std::fs::create_dir_all(nested.join("Materialfy")).unwrap();
        std::fs::write(nested.join("Materialfy").join("materialfy.exe"), b"").unwrap();
        assert_eq!(app_root(&nested, "materialfy.exe"), Some(nested.join("Materialfy")));

        let empty = base.join("empty");
        std::fs::create_dir_all(empty.join("a")).unwrap();
        std::fs::create_dir_all(empty.join("b")).unwrap();
        assert_eq!(app_root(&empty, "materialfy.exe"), None);
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn setup_runs_silently_and_relaunches() {
        assert!(SETUP_ARGS.contains(&"/SILENT"));
        assert!(SETUP_ARGS.contains(&"/RELAUNCH"));
        assert!(!SETUP_ARGS.contains(&"/VERYSILENT"));
        assert!(PORTABLE_HELPER.contains("Wait-Process -Id $ProcId"));
    }
}
