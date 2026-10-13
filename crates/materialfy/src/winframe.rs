//! Окно без рамки на Windows: нативный ресайз, Aero Snap, тень и скруглённые углы Windows 11 через DWM
//! (cpp/winframe.cpp). См. контракт §7. На других ОС — пусто: ресайз делает QML ResizeEdges через
//! startSystemResize, углы скругляет QML WindowFrame (окно прозрачное).
//! Там же — кнопки «Назад / Пауза / Дальше» под эскизом окна на панели задач Windows (cpp/taskbar.cpp)
//! и QML-синглтон WindowShell (свернуть окно, не теряя «развёрнуто» / «на весь экран»; окна плеера вне главного
//! окна — островок и виджет в панели задач, cpp/floating.cpp).

use cxx_qt_lib::QString;

/// Ширина зоны ресайза, логические пиксели (как ResizeEdges.grip).
pub const GRIP: i32 = 6;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "mf"]
    unsafe extern "C++" {
        include!("winframe.h");
        /// setWindowStates(windowStates() | Minimized) — см. WindowShell.minimize
        unsafe fn window_minimize(window: *mut QObject);
        include!("taskbar.h");
        unsafe fn taskbar_install(window: *mut QObject) -> bool;
        include!("floating.h");
        unsafe fn floating_tool_window(window: *mut QObject) -> bool;
        unsafe fn floating_set_mask(window: *mut QObject, x: i32, y: i32, w: i32, h: i32);
        fn floating_fullscreen_busy() -> bool;
        unsafe fn floating_taskbar_place(window: *mut QObject, width: i32, height: i32, embed: bool, pos: &QString) -> i32;
        unsafe fn floating_taskbar_drag(window: *mut QObject, width: i32, height: i32, phase: i32) -> QString;
        unsafe fn floating_taskbar_detach(window: *mut QObject);
        unsafe fn floating_key_hook(window: *mut QObject, on: bool) -> bool;
    }

    unsafe extern "RustQt" {
        /// Окно для QML: Window.showMinimized() и visibility = Window.Minimized сбрасывают «развёрнуто» и
        /// «на весь экран» (Qt ставит состояние ровно Minimized), и окно возвращается из панели задач обычным.
        /// WindowShell.minimize(window) добавляет Minimized к текущему состоянию — ОС помнит, каким его вернуть.
        #[qobject]
        type WindowShell = super::WindowShellRust;

        #[qinvokable]
        unsafe fn minimize(self: &WindowShell, window: *mut QObject);

        /// Показать и поднять главное окно (из трея, свёрнутое — тоже), как второй запуск приложения
        #[qinvokable]
        #[cxx_name = "raiseMain"]
        fn raise_main(self: &WindowShell);
        /// Окно-островок: не в панели задач и Alt+Tab, не забирает фокус (Windows; иначе false)
        #[qinvokable]
        #[cxx_name = "makeToolWindow"]
        unsafe fn make_tool_window(self: &WindowShell, window: *mut QObject) -> bool;
        /// Мышь ловит и рисуется только прямоугольник (логические px окна); w <= 0 — всё окно
        #[qinvokable]
        #[cxx_name = "setMask"]
        unsafe fn set_mask(self: &WindowShell, window: *mut QObject, x: i32, y: i32, w: i32, h: i32);
        /// На переднем плане полноэкранное приложение или презентация (Windows)
        #[qinvokable]
        #[cxx_name = "fullscreenBusy"]
        fn fullscreen_busy(self: &WindowShell) -> bool;
        /// Встроить окно в панель задач Windows и поставить на место pos (taskbarWidgetPos): 1 — встроено,
        /// 2 — поверх панели, 0 — некуда, -1 — окно потеряно (перезапуск Explorer), создать заново. См. cpp/floating.h
        #[qinvokable]
        #[cxx_name = "taskbarPlace"]
        unsafe fn taskbar_place(self: &WindowShell, window: *mut QObject, width: i32, height: i32, embed: bool, pos: &QString) -> i32;
        /// Перетаскивание виджета вдоль панели за курсором (phase 0 — начало, 1 — шаг, 2 — конец) → место
        #[qinvokable]
        #[cxx_name = "taskbarDrag"]
        unsafe fn taskbar_drag(self: &WindowShell, window: *mut QObject, width: i32, height: i32, phase: i32) -> QString;
        #[qinvokable]
        #[cxx_name = "taskbarDetach"]
        unsafe fn taskbar_detach(self: &WindowShell, window: *mut QObject);
        /// Стрелки и пробел без фокуса, пока курсор над окном (Windows): QML-функция окна floatingKey(code)
        #[qinvokable]
        #[cxx_name = "keyHook"]
        unsafe fn key_hook(self: &WindowShell, window: *mut QObject, on: bool) -> bool;
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

    fn raise_main(&self) {
        crate::qt::ffi::ffi::post_raise_window();
    }

    unsafe fn make_tool_window(&self, window: *mut cxx_qt::QObject) -> bool {
        // SAFETY: окно из QML (живой QObject), вызов из GUI-потока
        !window.is_null() && unsafe { qobject::floating_tool_window(window) }
    }

    unsafe fn set_mask(&self, window: *mut cxx_qt::QObject, x: i32, y: i32, w: i32, h: i32) {
        if !window.is_null() {
            // SAFETY: то же
            unsafe { qobject::floating_set_mask(window, x, y, w, h) };
        }
    }

    fn fullscreen_busy(&self) -> bool {
        qobject::floating_fullscreen_busy()
    }

    unsafe fn taskbar_place(&self, window: *mut cxx_qt::QObject, width: i32, height: i32, embed: bool, pos: &QString) -> i32 {
        if window.is_null() {
            return 0;
        }
        // SAFETY: то же
        unsafe { qobject::floating_taskbar_place(window, width, height, embed, pos) }
    }

    unsafe fn taskbar_drag(&self, window: *mut cxx_qt::QObject, width: i32, height: i32, phase: i32) -> QString {
        if window.is_null() {
            return QString::default();
        }
        // SAFETY: то же
        unsafe { qobject::floating_taskbar_drag(window, width, height, phase) }
    }

    unsafe fn key_hook(&self, window: *mut cxx_qt::QObject, on: bool) -> bool {
        // SAFETY: то же; снятие хука с нулевым окном — снять любой
        unsafe { qobject::floating_key_hook(window, on) }
    }

    unsafe fn taskbar_detach(&self, window: *mut cxx_qt::QObject) {
        if !window.is_null() {
            // SAFETY: то же
            unsafe { qobject::floating_taskbar_detach(window) };
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
