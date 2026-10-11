//! Системные предпочтения интерфейса.

/// Система просит меньше анимаций. Читает мост Settings → Settings.systemReducedMotion → Theme.reducedMotion
/// при Settings.animations == "system". Windows — SPI_GETCLIENTAREAANIMATION == FALSE; Linux — GNOME
/// `enable-animations` == false; macOS — «Уменьшить движение». Не удалось узнать — false.
pub fn reduced_motion() -> bool {
    imp::reduced_motion()
}

/// Тема панели задач (для значка трея): Some(true) — тёмная. Знает только Windows
/// (HKCU\…\Themes\Personalize, SystemUsesLightTheme); на других ОС — None, QML берёт тему Qt.
pub fn taskbar_dark() -> Option<bool> {
    imp::taskbar_dark()
}

#[cfg(target_os = "windows")]
mod imp {
    use windows_sys::Win32::UI::WindowsAndMessaging::{SPI_GETCLIENTAREAANIMATION, SystemParametersInfoW};

    pub fn taskbar_dark() -> Option<bool> {
        let key = winreg::RegKey::predef(winreg::enums::HKEY_CURRENT_USER)
            .open_subkey(r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
            .ok()?;
        // нет значения — Windows 10 до 1903: панель тёмная
        Some(key.get_value::<u32, _>("SystemUsesLightTheme").unwrap_or(0) == 0)
    }

    pub fn reduced_motion() -> bool {
        let mut enabled: i32 = 1;
        // SAFETY: pvParam указывает на BOOL, как требует SPI_GETCLIENTAREAANIMATION
        let ok = unsafe { SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, (&raw mut enabled).cast(), 0) };
        ok != 0 && enabled == 0
    }
}

#[cfg(target_os = "linux")]
mod imp {
    pub fn taskbar_dark() -> Option<bool> {
        None
    }

    pub fn reduced_motion() -> bool {
        super::command_output("gsettings", &["get", "org.gnome.desktop.interface", "enable-animations"])
            .is_some_and(|out| out == "false")
    }
}

#[cfg(target_os = "macos")]
mod imp {
    pub fn taskbar_dark() -> Option<bool> {
        None
    }

    pub fn reduced_motion() -> bool {
        super::command_output("defaults", &["read", "com.apple.universalaccess", "reduceMotion"])
            .is_some_and(|out| out == "1")
    }
}

#[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
mod imp {
    pub fn taskbar_dark() -> Option<bool> {
        None
    }

    pub fn reduced_motion() -> bool {
        false
    }
}

/// Вывод команды без пробелов по краям; None — нет команды или код ошибки.
#[cfg(any(target_os = "linux", target_os = "macos"))]
fn command_output(program: &str, args: &[&str]) -> Option<String> {
    let out = std::process::Command::new(program)
        .args(args)
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

#[cfg(test)]
mod tests {
    #[test]
    fn answers_without_panic() {
        // значение зависит от машины — проверяем только, что вызов работает
        let _ = super::reduced_motion();
        let _ = super::taskbar_dark();
    }
}
