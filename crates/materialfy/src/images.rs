//! Дисковый кэш картинок для QML (images.py): QQmlNetworkAccessManagerFactory в C++ (cpp/mf_shell.cpp),
//! каждый NAM — свой QNetworkDiskCache на общий каталог dirs::cache_subdir("images"), 512 МиБ;
//! только HTTP/1.1 (Http2AllowedAttribute = false: по HTTP/2 сервер обложек отвечает REFUSED_STREAM).
//! Прокси — действующий у сервисов (AuthService::proxy / watch_proxy), тот же, что у запросов к Web API.
use cxx_qt_lib::{QQmlApplicationEngine, QString};
use sf_services::{ProxyConfig, Services};
use std::pin::Pin;

pub const CACHE_BYTES: i64 = 512 * 1024 * 1024;

/// Установить фабрику на движок (до load) и следить за прокси.
pub fn install_caching_nam(engine: Pin<&mut QQmlApplicationEngine>, rt: &tokio::runtime::Handle, services: &Services) {
    let dir = mf_platform::dirs::cache_subdir("images");
    let dir = QString::from(dir.to_string_lossy().as_ref());
    crate::qt::ffi::ffi::engine_install_caching_nam(engine, &dir, CACHE_BYTES);

    let mut proxy = services.auth.watch_proxy();
    apply_proxy(&proxy.borrow_and_update());
    // set_image_proxy потокобезопасен — из задачи tokio, без GUI-потока
    rt.spawn(async move {
        while proxy.changed().await.is_ok() {
            let config = proxy.borrow_and_update().clone();
            apply_proxy(&config);
        }
    });
}

/// Режимы cpp/mf_shell.h: 0 — без прокси, 1 — системный, 2 — HTTP, 3 — SOCKS5, 4 — заблокировать.
fn apply_proxy(config: &ProxyConfig) {
    let none = QString::default();
    let (mode, manual) = match config {
        ProxyConfig::Off => (0, None),
        ProxyConfig::System => (1, None),
        ProxyConfig::Http(manual) => (2, Some(manual)),
        ProxyConfig::Socks(manual) => (3, Some(manual)),
        // сервисы при неверных настройках блокируют запросы — картинки тоже не идут напрямую
        ProxyConfig::Invalid(_) => (4, None),
    };
    match manual {
        Some(manual) => crate::qt::ffi::ffi::set_image_proxy(
            mode,
            &QString::from(manual.host()),
            i32::from(manual.port()),
            &QString::from(manual.username()),
            &QString::from(manual.password()),
        ),
        None => crate::qt::ffi::ffi::set_image_proxy(mode, &none, 0, &none, &none),
    }
}
