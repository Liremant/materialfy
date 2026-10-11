//! Окно без рамки на Windows: нативный ресайз и Aero Snap (cpp/winframe.cpp). См. контракт §7.
//! На других ОС — пусто (ресайз делает QML ResizeEdges через startSystemResize).

/// Ширина зоны ресайза, логические пиксели (как ResizeEdges.grip).
pub const GRIP: i32 = 6;

/// Поставить фильтр на главное окно (после load, окно уже создано). `window` — QQuickWindow* корня.
pub fn install(window: *mut cxx_qt::QObject) {
    if !cfg!(target_os = "windows") || window.is_null() {
        return;
    }
    // SAFETY: window — живой корневой объект движка, вызов из GUI-потока
    if !unsafe { crate::qt::ffi::ffi::winframe_install(window, GRIP) } {
        tracing::warn!("рамка окна: корень не QWindow или нет HWND — ресайз через QML");
    }
}
