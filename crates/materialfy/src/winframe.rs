//! Окно без рамки на Windows: нативный ресайз, Aero Snap, тень и скруглённые углы Windows 11 через DWM
//! (cpp/winframe.cpp). См. контракт §7. На других ОС — пусто: ресайз делает QML ResizeEdges через
//! startSystemResize, углы скругляет QML WindowFrame (окно прозрачное).
//! Там же — кнопки «Назад / Пауза / Дальше» под эскизом окна на панели задач Windows (cpp/taskbar.cpp)
//! и QML-синглтон WindowShell (свернуть окно, не теряя «развёрнуто» / «на весь экран»).

/// Ширина зоны ресайза, логические пиксели (как ResizeEdges.grip).
pub const GRIP: i32 = 6;

#[cxx_qt::bridge]
pub mod qobject {
    #[namespace = "mf"]
    unsafe extern "C++" {
        include!("winframe.h");
        /// setWindowStates(windowStates() | Minimized) — см. WindowShell.minimize
        unsafe fn window_minimize(window: *mut QObject);
        include!("taskbar.h");
        unsafe fn taskbar_install(window: *mut QObject) -> bool;
    }

    unsafe extern "RustQt" {
        /// Окно для QML: Window.showMinimized() и visibility = Window.Minimized сбрасывают «развёрнуто» и
        /// «на весь экран» (Qt ставит состояние ровно Minimized), и окно возвращается из панели задач обычным.
        /// WindowShell.minimize(window) добавляет Minimized к текущему состоянию — ОС помнит, каким его вернуть.
        #[qobject]
        type WindowShell = super::WindowShellRust;

        #[qinvokable]
        unsafe fn minimize(self: &WindowShell, window: *mut QObject);
    }
}

#[derive(Default)]
pub struct WindowShellRust;

impl qobject::WindowShell {
    unsafe fn minimize(&self, window: *mut cxx_qt::QObject) {
        if !window.is_null() {
            // SAFETY: окно из QML (живой QObject), вызов из GUI-потока
            unsafe { qobject::window_minimize(window) };
        }
    }
}

/// Поставить фильтр на главное окно (после load, окно уже создано). `window` — QQuickWindow* корня.
pub fn install(window: *mut cxx_qt::QObject) {
    if !cfg!(target_os = "windows") || window.is_null() {
        return;
    }
    // SAFETY: window — живой корневой объект движка, вызов из GUI-потока
    if !unsafe { crate::qt::ffi::ffi::winframe_install(window, GRIP) } {
        tracing::warn!("window frame: root is not a QWindow or has no HWND — resizing via QML");
    }
    // SAFETY: то же окно; Player и прочие синглтоны уже созданы (register_qml_types до load)
    if !unsafe { qobject::taskbar_install(window) } {
        tracing::warn!("taskbar: no thumbnail toolbar (no HWND, QML engine or Player)");
    }
}
