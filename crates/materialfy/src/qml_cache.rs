//! Кэш скомпилированного QML (его пишет сам Qt, QML_DISK_CACHE_PATH): своя папка на версию приложения и сброс
//! после неудачного запуска. Испорченный файл кэша (процесс убит посреди записи) Qt берёт как есть — содержимое
//! он не проверяет, — и движок QML падает на каждом старте (Qt6Qml.dll, 0xc0000005 в 0.3.1 у пользователя).
//! Метка «запуск не завершён» снимается через 15 с работы; нашли её при старте — прошлый запуск упал, кэш
//! стираем, QML скомпилируется заново.
use std::path::{Path, PathBuf};
use std::time::Duration;

const SETTLE: Duration = Duration::from_secs(15);

pub struct StartGuard {
    marker: PathBuf,
}

/// Вызывать до создания QApplication (ставит QML_DISK_CACHE_PATH). `guard` — следить за неудачными запусками
/// (не в режиме снимков: там процесс выходит раньше, чем метка снимется). None — путь кэша задал пользователь.
pub fn prepare(guard: bool) -> Option<StartGuard> {
    if std::env::var_os("QML_DISK_CACHE_PATH").is_some() {
        return None;
    }
    let root = mf_platform::dirs::cache_dir().join("qmlcache");
    let version = env!("CARGO_PKG_VERSION");
    let dir = root.join(version);
    remove_other_versions(&root, version);
    let marker = root.join(format!("starting-{version}"));
    if guard && marker.exists() {
        tracing::warn!("the previous start did not finish: the compiled QML cache is cleared");
        let _ = std::fs::remove_dir_all(&dir);
    }
    if let Err(error) = std::fs::create_dir_all(&dir) {
        tracing::warn!("QML cache {}: {error}", dir.display());
        return None;
    }
    // через Qt: на Windows он читает переменные из копии C-рантайма, std::env::set_var её не меняет
    crate::qt::ffi::ffi::set_qt_env(
        &cxx_qt_lib::QString::from("QML_DISK_CACHE_PATH"),
        &cxx_qt_lib::QString::from(dir.to_string_lossy().as_ref()),
    );
    guard.then_some(StartGuard { marker })
}

impl StartGuard {
    /// Поставить метку (когда ясно, что этот процесс и правда запускает окно) и снять её через SETTLE работы.
    pub fn arm(self, rt: &tokio::runtime::Handle) {
        let _ = std::fs::write(&self.marker, b"");
        rt.spawn(async move {
            tokio::time::sleep(SETTLE).await;
            let _ = std::fs::remove_file(&self.marker);
        });
    }
}

/// Кэш прошлых версий и старый плоский кэш (файлы прямо в qmlcache, до 0.3.2) — удалить.
fn remove_other_versions(root: &Path, version: &str) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if path.is_dir() {
            if name != version {
                let _ = std::fs::remove_dir_all(&path);
            }
        } else if name.ends_with(".qmlc") || name.ends_with(".jsc") || (name.starts_with("starting-") && name != format!("starting-{version}")) {
            let _ = std::fs::remove_file(&path);
        }
    }
}
