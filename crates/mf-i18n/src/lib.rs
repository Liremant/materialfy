//! Materialfy localisation. Source strings are English; the Russian dictionary (`i18n/ru/*.json` at the repo root)
//! is merged and embedded at compile time by build.rs. The current language is a global atomic, so `t`/`tf`/`n`
//! are callable from any thread.
//!
//! * `t("Settings")` — the translation of an English string (or the string itself in English / when missing).
//! * `tf("Played {0} of {1}", &[&a, &b])` — translate, then substitute positional `{0}`, `{1}`…
//! * `n(count, "{0} track", "{0} tracks")` — plural: English one/many, Russian one/few/many
//!   (dictionary key `"{0} track|{0} tracks"`, value `"{0} трек|{0} трека|{0} треков"`), `{0}` → count.

use std::collections::HashMap;
use std::fmt::Display;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU8, Ordering};

#[cfg(test)]
mod merge;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum Lang {
    #[default]
    En,
    Ru,
}

impl Lang {
    /// Settings / QML code: "en" or "ru".
    pub fn code(self) -> &'static str {
        match self {
            Lang::En => "en",
            Lang::Ru => "ru",
        }
    }
}

static LANG: AtomicU8 = AtomicU8::new(0);

pub fn set_lang(lang: Lang) {
    LANG.store(lang as u8, Ordering::Relaxed);
}

pub fn lang() -> Lang {
    match LANG.load(Ordering::Relaxed) {
        1 => Lang::Ru,
        _ => Lang::En,
    }
}

/// "ru" (any case, also "ru-RU"/"ru_RU") → Ru, anything else → En.
pub fn parse_lang(s: &str) -> Lang {
    let s = s.trim().to_ascii_lowercase();
    if s == "ru" || s.starts_with("ru-") || s.starts_with("ru_") { Lang::Ru } else { Lang::En }
}

/// The Language setting: follow the OS UI language, or one fixed language.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum LangSetting {
    #[default]
    System,
    Fixed(Lang),
}

impl LangSetting {
    /// Settings code: "system", "en" or "ru".
    pub fn code(self) -> &'static str {
        match self {
            LangSetting::System => "system",
            LangSetting::Fixed(lang) => lang.code(),
        }
    }

    /// The language to show: a fixed one as is; System — from the OS UI languages (most preferred first).
    pub fn resolve<S: AsRef<str>>(self, os_languages: &[S]) -> Lang {
        match self {
            LangSetting::System => system_lang(os_languages),
            LangSetting::Fixed(lang) => lang,
        }
    }
}

/// The `language` setting value: "en"/"ru" (any case, with a region) → that language; "system", empty or
/// anything unknown → System.
pub fn parse_setting(s: &str) -> LangSetting {
    let code = s.trim().to_ascii_lowercase();
    let primary = code.split(['-', '_']).next().unwrap_or("");
    match primary {
        "en" => LangSetting::Fixed(Lang::En),
        "ru" => LangSetting::Fixed(Lang::Ru),
        _ => LangSetting::System,
    }
}

/// The app language for the OS UI languages (BCP 47 tags, most preferred first, as QLocale::uiLanguages gives
/// them): Russian when the OS UI language is Russian, English otherwise (also for an empty list).
pub fn system_lang<S: AsRef<str>>(os_languages: &[S]) -> Lang {
    os_languages.first().map_or(Lang::En, |first| parse_lang(first.as_ref()))
}

/// The merged Russian dictionary as a JSON object string (for the QML side).
pub const RU_JSON: &str = include_str!(concat!(env!("OUT_DIR"), "/ru.json"));

fn ru() -> &'static HashMap<String, String> {
    static MAP: OnceLock<HashMap<String, String>> = OnceLock::new();
    MAP.get_or_init(|| serde_json::from_str(RU_JSON).unwrap_or_default())
}

/// The dictionary of `lang` (English key → translation; plural values keep the `one|few|many` form). None for English.
pub fn dictionary(lang: Lang) -> Option<&'static HashMap<String, String>> {
    match lang {
        Lang::En => None,
        Lang::Ru => Some(ru()),
    }
}

fn lookup(en: &str) -> Option<&'static str> {
    dictionary(lang())?.get(en).map(String::as_str)
}

/// Translates an English source string into the current language (unchanged if English or untranslated).
pub fn t(en: &str) -> String {
    lookup(en).unwrap_or(en).to_owned()
}

/// Substitutes `{0}`, `{1}`… in `pattern` (unknown or out-of-range placeholders stay as is).
pub fn format(pattern: &str, args: &[&dyn Display]) -> String {
    if args.is_empty() || !pattern.contains('{') {
        return pattern.to_owned();
    }
    let mut out = String::with_capacity(pattern.len() + 16);
    let mut rest = pattern;
    while let Some(open) = rest.find('{') {
        out.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        let idx = after.find('}').and_then(|close| after[..close].parse::<usize>().ok().map(|i| (i, close)));
        match idx {
            Some((i, close)) if i < args.len() => {
                use std::fmt::Write;
                let _ = write!(out, "{}", args[i]);
                rest = &after[close + 1..];
            }
            _ => {
                out.push('{');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Translates, then substitutes `{0}`, `{1}`…
pub fn tf(en: &str, args: &[&dyn Display]) -> String {
    format(lookup(en).unwrap_or(en), args)
}

/// Russian plural category: 0 = one (1, 21, 101…), 1 = few (2–4, 22–24…), 2 = many (0, 5–20, 11–14, 25…).
pub fn ru_plural_index(count: i64) -> usize {
    let n = count.unsigned_abs();
    let (m10, m100) = (n % 10, n % 100);
    if m10 == 1 && m100 != 11 {
        0
    } else if (2..=4).contains(&m10) && !(12..=14).contains(&m100) {
        1
    } else {
        2
    }
}

/// Plural form for `count`; `{0}` in the chosen form is replaced by `count`.
pub fn n(count: i64, one: &str, many: &str) -> String {
    let form: String = match dictionary(lang()).and_then(|d| d.get(&format!("{one}|{many}"))) {
        Some(ru) => {
            let forms: Vec<&str> = ru.split('|').collect();
            forms.get(ru_plural_index(count)).or(forms.last()).copied().unwrap_or(many).to_owned()
        }
        None if count == 1 => one.to_owned(),
        None => many.to_owned(),
    };
    format(&form, &[&count])
}

/// `tr!("Played {0} of {1}", a, b)` — `t` without arguments, `tf` with them.
#[macro_export]
macro_rules! tr {
    ($en:expr) => {
        $crate::t($en)
    };
    ($en:expr, $($arg:expr),+ $(,)?) => {
        $crate::tf($en, &[$(&$arg as &dyn ::std::fmt::Display),+])
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // the language is global: tests that switch it run one at a time
    static GUARD: Mutex<()> = Mutex::new(());

    fn with_lang<R>(l: Lang, f: impl FnOnce() -> R) -> R {
        let _g = GUARD.lock().unwrap_or_else(|e| e.into_inner());
        set_lang(l);
        let r = f();
        set_lang(Lang::En);
        r
    }

    #[test]
    fn plural_rules() {
        let cases = [
            (0, 2),
            (1, 0),
            (2, 1),
            (4, 1),
            (5, 2),
            (11, 2),
            (12, 2),
            (14, 2),
            (21, 0),
            (22, 1),
            (25, 2),
            (101, 0),
            (111, 2),
            (112, 2),
            (-1, 0),
        ];
        for (count, idx) in cases {
            assert_eq!(ru_plural_index(count), idx, "count {count}");
        }
    }

    #[test]
    fn parse() {
        assert_eq!(parse_lang("ru"), Lang::Ru);
        assert_eq!(parse_lang("RU-ru"), Lang::Ru);
        assert_eq!(parse_lang("en"), Lang::En);
        assert_eq!(parse_lang(""), Lang::En);
        assert_eq!(parse_lang("de"), Lang::En);
        assert_eq!(Lang::Ru.code(), "ru");
    }

    #[test]
    fn parse_setting_values() {
        assert_eq!(parse_setting("system"), LangSetting::System);
        assert_eq!(parse_setting(" System "), LangSetting::System);
        assert_eq!(parse_setting(""), LangSetting::System);
        assert_eq!(parse_setting("de"), LangSetting::System);
        assert_eq!(parse_setting("english"), LangSetting::System);
        assert_eq!(parse_setting("en"), LangSetting::Fixed(Lang::En));
        assert_eq!(parse_setting("EN-us"), LangSetting::Fixed(Lang::En));
        assert_eq!(parse_setting("ru"), LangSetting::Fixed(Lang::Ru));
        assert_eq!(parse_setting("ru_RU"), LangSetting::Fixed(Lang::Ru));
        assert_eq!(LangSetting::default(), LangSetting::System);
        for setting in [LangSetting::System, LangSetting::Fixed(Lang::En), LangSetting::Fixed(Lang::Ru)] {
            assert_eq!(parse_setting(setting.code()), setting);
        }
    }

    #[test]
    fn system_language() {
        let none: [&str; 0] = [];
        assert_eq!(system_lang(&none), Lang::En);
        assert_eq!(system_lang(&["ru-RU", "en-US"]), Lang::Ru);
        assert_eq!(system_lang(&["ru"]), Lang::Ru);
        assert_eq!(system_lang(&["en-US", "ru-RU"]), Lang::En);
        assert_eq!(system_lang(&["de-DE", "ru-RU"]), Lang::En);
        assert_eq!(system_lang(&["uk-UA"]), Lang::En);
        assert_eq!(system_lang(&["be-BY"]), Lang::En);
        assert_eq!(system_lang(&["kk-KZ"]), Lang::En);
        assert_eq!(system_lang(&["rue"]), Lang::En);
        assert_eq!(system_lang(&[String::from("ru-UA")]), Lang::Ru);
    }

    #[test]
    fn resolve_setting() {
        let russian_os = ["ru-RU", "en-US"];
        let english_os = ["en-GB"];
        assert_eq!(parse_setting("system").resolve(&russian_os), Lang::Ru);
        assert_eq!(parse_setting("system").resolve(&english_os), Lang::En);
        assert_eq!(parse_setting("en").resolve(&russian_os), Lang::En);
        assert_eq!(parse_setting("ru").resolve(&english_os), Lang::Ru);
    }

    #[test]
    fn formatting() {
        assert_eq!(format("{0} of {1}", &[&1, &"two"]), "1 of two");
        assert_eq!(format("{1}{0}{1}", &[&"a", &"b"]), "bab");
        assert_eq!(format("{x} {5} {", &[&1]), "{x} {5} {");
        assert_eq!(format("no args", &[]), "no args");
    }

    #[test]
    fn english_passthrough() {
        with_lang(Lang::En, || {
            assert_eq!(t("Language"), "Language");
            assert_eq!(tf("Untranslated {0}", &[&7]), "Untranslated 7");
            assert_eq!(n(1, "{0} track", "{0} tracks"), "1 track");
            assert_eq!(n(5, "{0} track", "{0} tracks"), "5 tracks");
            assert_eq!(tr!("{0}+{1}", 1, 2), "1+2");
            assert_eq!(tr!("Language"), "Language");
        });
    }

    #[test]
    fn russian_lookup() {
        with_lang(Lang::Ru, || {
            assert_eq!(t("Language"), "Язык");
            assert_eq!(t("No such string here"), "No such string here");
            let forms = [
                (1, "1 трек"),
                (2, "2 трека"),
                (5, "5 треков"),
                (11, "11 треков"),
                (21, "21 трек"),
                (22, "22 трека"),
                (25, "25 треков"),
                (111, "111 треков"),
            ];
            for (c, want) in forms {
                assert_eq!(n(c, "{0} track", "{0} tracks"), want);
            }
            // an untranslated plural falls back to the English forms
            assert_eq!(n(2, "{0} zork", "{0} zorks"), "2 zorks");
        });
    }

    #[test]
    fn embedded_dictionary_is_valid() {
        let map: HashMap<String, String> = serde_json::from_str(RU_JSON).expect("ru.json");
        for (k, v) in &map {
            if k.contains('|') {
                assert_eq!(v.split('|').count(), 3, "{k}");
            }
        }
    }

    fn files(list: &[(&str, &str)]) -> Vec<(String, String)> {
        list.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect()
    }

    #[test]
    fn duplicate_keys() {
        // identical duplicates across files are fine
        let ok = merge::merge(&files(&[
            ("a.json", r#"{"Play": "Играть"}"#),
            ("b.json", r#"{"Play": "Играть", "Pause": "Пауза"}"#),
        ]));
        assert_eq!(ok.unwrap().len(), 2);
        // conflicting values across files
        let err = merge::merge(&files(&[("a.json", r#"{"Play": "Играть"}"#), ("b.json", r#"{"Play": "Воспроизвести"}"#)]))
            .unwrap_err();
        assert!(err.contains("duplicate key \"Play\"") && err.contains("a.json") && err.contains("b.json"), "{err}");
        // conflicting values inside one file
        let err = merge::merge(&files(&[("a.json", r#"{"Play": "Играть", "Play": "Пуск"}"#)])).unwrap_err();
        assert!(err.contains("duplicate key"), "{err}");
        // malformed plural
        let err = merge::merge(&files(&[("a.json", r#"{"{0} track|{0} tracks": "{0} трек|{0} треков"}"#)])).unwrap_err();
        assert!(err.contains("plural"), "{err}");
        // bad JSON
        assert!(merge::merge(&files(&[("a.json", "{")])).is_err());
    }
}
