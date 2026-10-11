//! IconMetrics (icons.py): оптическое центрирование иконок Material Symbols.
//! Шрифт урезан до используемых иконок (tools/subset_fonts.py), поэтому иконка рисуется символом по коду
//! из assets/fonts/icons.json, а не лигатурой — glyph(name). ink(name, size) — замер глифа по пикселям
//! (C++: icon_measure в cpp/mf_shell.cpp), кэш по (имя, round(size)).
use std::collections::HashMap;
use std::pin::Pin;
use std::sync::OnceLock;

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QRectF, QString};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qrectf.h");
        type QRectF = cxx_qt_lib::QRectF;
    }

    unsafe extern "RustQt" {
        #[qobject]
        type IconMetrics = super::IconMetricsRust;

        #[qinvokable]
        fn glyph(self: &IconMetrics, name: &QString) -> QString;

        /// x, y — смещение центра контура глифа от центра его текстового блока (advance × height);
        /// width, height — размер контура, в пикселях. В QML: glyph.x -= x, glyph.y -= y.
        #[qinvokable]
        fn ink(self: Pin<&mut IconMetrics>, name: &QString, size: f64) -> QRectF;
    }
}

#[derive(Default)]
pub struct IconMetricsRust {
    cache: HashMap<(String, i64), QRectF>,
}

fn codepoints() -> &'static HashMap<String, u32> {
    static CODEPOINTS: OnceLock<HashMap<String, u32>> = OnceLock::new();
    CODEPOINTS.get_or_init(|| {
        let path = crate::engine::assets_dir().join("fonts").join("icons.json");
        match std::fs::read_to_string(&path).map(|text| serde_json::from_str(&text)) {
            Ok(Ok(map)) => map,
            Ok(Err(e)) => {
                eprintln!("не удалось разобрать {}: {e}", path.display());
                HashMap::new()
            }
            Err(e) => {
                eprintln!("не удалось прочитать {}: {e}", path.display());
                HashMap::new()
            }
        }
    })
}

fn glyph_text(name: &str) -> String {
    match codepoints().get(name).and_then(|&code| char::from_u32(code)) {
        Some(c) => c.to_string(),
        None => {
            if !name.is_empty() {
                eprintln!("иконки «{name}» нет в урезанном шрифте — запустите tools/subset_fonts.py");
            }
            String::new()
        }
    }
}

impl qobject::IconMetrics {
    fn glyph(&self, name: &QString) -> QString {
        QString::from(glyph_text(&name.to_string()).as_str())
    }

    fn ink(mut self: Pin<&mut Self>, name: &QString, size: f64) -> QRectF {
        let name = name.to_string();
        // round() Python — к чётному
        let size = size.round_ties_even() as i64;
        let key = (name, size);
        if let Some(cached) = self.rust().cache.get(&key) {
            return cached.clone();
        }
        let result = if !key.0.is_empty() && size > 0 {
            let text = glyph_text(&key.0);
            if text.is_empty() {
                QRectF::default()
            } else {
                crate::qt::ffi::ffi::icon_measure(&QString::from(text.as_str()), size.min(i32::MAX as i64) as i32)
            }
        } else {
            QRectF::default()
        };
        self.as_mut().rust_mut().cache.insert(key, result.clone());
        result
    }
}
