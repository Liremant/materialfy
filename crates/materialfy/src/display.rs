//! Самый быстрый монитор — основным экраном до создания окон (display.py). Только Linux, C++
//! (cpp/mf_shell.cpp): QWindowSystemInterface::handlePrimaryScreenChanged(fastest->handle()) через dlsym —
//! если символа нет, пропуск с сообщением. MATERIALFY_KEEP_PRIMARY_SCREEN=1 — не трогать.
//! Windows/macOS — ничего не делать.

/// Строка для лога (--debug-fps печатает её в stderr).
pub fn prefer_fastest_screen() -> String {
    if cfg!(target_os = "linux") && std::env::var_os("MATERIALFY_KEEP_PRIMARY_SCREEN").is_some_and(|v| !v.is_empty()) {
        return "primary screen: kept the system one (MATERIALFY_KEEP_PRIMARY_SCREEN)".to_owned();
    }
    crate::qt::ffi::ffi::prefer_fastest_screen().to_string()
}
