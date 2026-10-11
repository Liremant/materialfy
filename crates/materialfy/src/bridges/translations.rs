// Translations: language of the UI for QML (Md3/I18n.qml). Source strings are English; `ru` is the embedded Russian
// dictionary from mf-i18n (i18n/ru/*.json). The SettingKey::Language setting is the source of truth: a change from any
// place (Settings.language in QML) arrives through the store subscription, switches mf_i18n, Qt's own translator
// (file dialogs, context menus), then `language` here — QML bindings over I18n re-evaluate on languageChanged.
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QVariant};

use crate::qt::QVariantMap;
use mf_i18n::Lang;
use mf_platform::SettingKey;

use super::{Delivery, forward_events};
use crate::context::ctx;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        /// "en" | "ru" — the language applied right now (follows Settings.language)
        #[qproperty(QString, language, READ, NOTIFY = language_changed)]
        /// English source → Russian; plural keys "one|many" → "one|few|many"
        #[qproperty(QMap_QString_QVariant, ru, READ, CONSTANT)]
        type Translations = super::TranslationsRust;

        #[qsignal]
        #[cxx_name = "languageChanged"]
        fn language_changed(self: Pin<&mut Translations>);

        /// Translation of one string in the current language (for code that is not a binding).
        #[qinvokable]
        fn tr(self: &Translations, en: &QString) -> QString;
    }

    impl cxx_qt::Threading for Translations {}
    impl cxx_qt::Initialize for Translations {}
}

pub struct TranslationsRust {
    language: QString,
    ru: QVariantMap,
}

impl Default for TranslationsRust {
    fn default() -> Self {
        let mut ru = QVariantMap::default();
        for (en, value) in mf_i18n::dictionary(Lang::Ru).into_iter().flatten() {
            ru.insert(QString::from(en.as_str()), QVariant::from(&QString::from(value.as_str())));
        }
        Self { language: QString::from(mf_i18n::lang().code()), ru }
    }
}

/// Switches the process language: mf_i18n (Rust strings) and Qt's translator. GUI thread only.
pub fn apply_language(lang: Lang) {
    mf_i18n::set_lang(lang);
    crate::qt::ffi::ffi::app_set_qt_language(&QString::from(lang.code()));
}

/// Language stored in the settings (default English).
pub fn stored_language(store: &mf_platform::SettingsStore) -> Lang {
    mf_i18n::parse_lang(&store.get_str(SettingKey::Language))
}

impl qobject::Translations {
    fn tr(&self, en: &QString) -> QString {
        QString::from(mf_i18n::t(&en.to_string()).as_str())
    }

    fn on_store(mut self: Pin<&mut Self>, delivery: Delivery<SettingKey>) {
        if matches!(delivery, Delivery::Event(key) if key != SettingKey::Language) {
            return;
        }
        let lang = stored_language(&ctx().services.settings);
        let code = QString::from(lang.code());
        if self.language == code {
            return;
        }
        apply_language(lang);
        self.as_mut().rust_mut().language = code;
        self.as_mut().language_changed();
        // Rust-made texts (snapshots of services) refresh with their next update.
    }
}

impl cxx_qt::Initialize for qobject::Translations {
    fn initialize(self: Pin<&mut Self>) {
        forward_events(self.qt_thread(), ctx().services.settings.subscribe(), Self::on_store);
    }
}
