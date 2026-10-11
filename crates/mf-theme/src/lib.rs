//! Цветовая схема MD3 (src/materialfy/theme.py): materialyoucolor 3.0.4, spec "2025", platform "phone".
//! Эталон — .venv/Lib/site-packages/materialyoucolor; значения должны совпадать с Python до бита
//! (см. тест-векторы в tests/vectors.json). Из material-colors берутся только HCT и палитры схем;
//! разрешение ролей (spec.rs), QuantizeCelebi (quantize.rs), Score (score.rs) и сглаживающий масштаб Qt
//! (scale.rs) портированы с эталона — у material-colors они расходятся с Python.
use std::collections::BTreeMap;
use std::path::Path;

use material_colors::color::Rgb;
use material_colors::dynamic_color::{
    DynamicScheme, Platform, Role, SpecVersion, Variant as MaterialVariant,
};
use material_colors::hct::Hct;

pub mod icons;
mod quantize;
pub use quantize::CrtRand;
mod scale;
mod score;
mod spec;

pub const DEFAULT_SEED: u32 = 0xFF6750A4;

/// 59 ролей — ровно COLOR_NAMES из materialyoucolor (ключи ThemeEngine.colors в QML).
pub const ROLE_NAMES: [&str; 59] = [
    "background",
    "onBackground",
    "surface",
    "surfaceDim",
    "surfaceBright",
    "surfaceContainerLowest",
    "surfaceContainerLow",
    "surfaceContainer",
    "surfaceContainerHigh",
    "surfaceContainerHighest",
    "onSurface",
    "surfaceVariant",
    "onSurfaceVariant",
    "outline",
    "outlineVariant",
    "inverseSurface",
    "inverseOnSurface",
    "shadow",
    "scrim",
    "surfaceTint",
    "primary",
    "primaryDim",
    "onPrimary",
    "primaryContainer",
    "onPrimaryContainer",
    "inversePrimary",
    "primaryFixed",
    "primaryFixedDim",
    "onPrimaryFixed",
    "onPrimaryFixedVariant",
    "secondary",
    "secondaryDim",
    "onSecondary",
    "secondaryContainer",
    "onSecondaryContainer",
    "secondaryFixed",
    "secondaryFixedDim",
    "onSecondaryFixed",
    "onSecondaryFixedVariant",
    "tertiary",
    "tertiaryDim",
    "onTertiary",
    "tertiaryContainer",
    "onTertiaryContainer",
    "tertiaryFixed",
    "tertiaryFixedDim",
    "onTertiaryFixed",
    "onTertiaryFixedVariant",
    "error",
    "errorDim",
    "onError",
    "errorContainer",
    "onErrorContainer",
    "primaryPaletteKeyColor",
    "secondaryPaletteKeyColor",
    "tertiaryPaletteKeyColor",
    "neutralPaletteKeyColor",
    "neutralVariantPaletteKeyColor",
    "errorPaletteKeyColor",
];

/// Роли material-colors в порядке ROLE_NAMES.
const ROLES: [Role; 59] = [
    Role::Background,
    Role::OnBackground,
    Role::Surface,
    Role::SurfaceDim,
    Role::SurfaceBright,
    Role::SurfaceContainerLowest,
    Role::SurfaceContainerLow,
    Role::SurfaceContainer,
    Role::SurfaceContainerHigh,
    Role::SurfaceContainerHighest,
    Role::OnSurface,
    Role::SurfaceVariant,
    Role::OnSurfaceVariant,
    Role::Outline,
    Role::OutlineVariant,
    Role::InverseSurface,
    Role::InverseOnSurface,
    Role::Shadow,
    Role::Scrim,
    Role::SurfaceTint,
    Role::Primary,
    Role::PrimaryDim,
    Role::OnPrimary,
    Role::PrimaryContainer,
    Role::OnPrimaryContainer,
    Role::InversePrimary,
    Role::PrimaryFixed,
    Role::PrimaryFixedDim,
    Role::OnPrimaryFixed,
    Role::OnPrimaryFixedVariant,
    Role::Secondary,
    Role::SecondaryDim,
    Role::OnSecondary,
    Role::SecondaryContainer,
    Role::OnSecondaryContainer,
    Role::SecondaryFixed,
    Role::SecondaryFixedDim,
    Role::OnSecondaryFixed,
    Role::OnSecondaryFixedVariant,
    Role::Tertiary,
    Role::TertiaryDim,
    Role::OnTertiary,
    Role::TertiaryContainer,
    Role::OnTertiaryContainer,
    Role::TertiaryFixed,
    Role::TertiaryFixedDim,
    Role::OnTertiaryFixed,
    Role::OnTertiaryFixedVariant,
    Role::Error,
    Role::ErrorDim,
    Role::OnError,
    Role::ErrorContainer,
    Role::OnErrorContainer,
    Role::PrimaryPaletteKeyColor,
    Role::SecondaryPaletteKeyColor,
    Role::TertiaryPaletteKeyColor,
    Role::NeutralPaletteKeyColor,
    Role::NeutralVariantPaletteKeyColor,
    Role::ErrorPaletteKeyColor,
];

/// Варианты схемы; имена — значения Settings.schemeVariant и ThemeEngine.variants (в этом порядке).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum Variant {
    #[default]
    Content,
    TonalSpot,
    Vibrant,
    Expressive,
    Fidelity,
    Neutral,
    Monochrome,
}

impl Variant {
    pub const ALL: [Variant; 7] = [
        Variant::Content,
        Variant::TonalSpot,
        Variant::Vibrant,
        Variant::Expressive,
        Variant::Fidelity,
        Variant::Neutral,
        Variant::Monochrome,
    ];

    /// "content" | "tonalSpot" | "vibrant" | "expressive" | "fidelity" | "neutral" | "monochrome"
    pub fn name(self) -> &'static str {
        match self {
            Variant::Content => "content",
            Variant::TonalSpot => "tonalSpot",
            Variant::Vibrant => "vibrant",
            Variant::Expressive => "expressive",
            Variant::Fidelity => "fidelity",
            Variant::Neutral => "neutral",
            Variant::Monochrome => "monochrome",
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|v| v.name() == name)
    }

    /// Имена в порядке ThemeEngine.variants.
    pub fn names() -> [&'static str; 7] {
        Self::ALL.map(Variant::name)
    }

    fn material(self) -> MaterialVariant {
        match self {
            Variant::Content => MaterialVariant::Content,
            Variant::TonalSpot => MaterialVariant::TonalSpot,
            Variant::Vibrant => MaterialVariant::Vibrant,
            Variant::Expressive => MaterialVariant::Expressive,
            Variant::Fidelity => MaterialVariant::Fidelity,
            Variant::Neutral => MaterialVariant::Neutral,
            Variant::Monochrome => MaterialVariant::Monochrome,
        }
    }
}

impl std::fmt::Display for Variant {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.name())
    }
}

impl std::str::FromStr for Variant {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, ()> {
        Self::from_name(s).ok_or(())
    }
}

/// ARGB всех 59 ролей.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Scheme {
    pub seed: u32,
    pub dark: bool,
    pub variant: Variant,
    pub colors: BTreeMap<&'static str, u32>,
}

#[derive(Debug, thiserror::Error)]
pub enum ThemeError {
    #[error("could not open image: {0}")]
    Image(String),
}

/// Схема из seed (build_scheme в theme.py). ~1 мс; можно звать из GUI-потока для стартовой схемы.
pub fn build_scheme(seed: u32, dark: bool, variant: Variant, contrast: f64) -> Scheme {
    // Content/Fidelity/Monochrome сами откатываются на spec 2021 — как _maybe_fallback_spec_version в Python
    let scheme = DynamicScheme::from_spec(
        Hct::new(Rgb::from_u32(seed)),
        variant.material(),
        dark,
        Some(contrast),
        Platform::Phone,
        SpecVersion::Spec2025,
    );
    // палитры — из material-colors, разрешение ролей — порт Python (spec.rs)
    let resolver = spec::Resolver::new(&scheme);
    let colors = ROLE_NAMES
        .iter()
        .zip(ROLES)
        .map(|(&name, role)| (name, resolver.argb(role)))
        .collect();
    Scheme {
        seed,
        dark,
        variant,
        colors,
    }
}

/// Сторона картинки, до которой она уменьшается перед квантованием.
pub const SAMPLE_SIZE: u32 = 112;
/// Число кластеров QuantizeCelebi.
pub const MAX_COLORS: usize = 128;

/// Доминантный цвет картинки (seed_from_image): масштаб до 112×112 (сглаживание, без сохранения пропорций),
/// RGB, QuantizeCelebi(pixels, 128) → Score.score → первый; пусто → DEFAULT_SEED.
///
/// Отличия от Python: PNG дают те же пиксели, что Qt, с точностью до единицы в редких краевых пикселях;
/// JPEG декодирует не libjpeg-turbo, а zune-jpeg (≈1 % отсчётов на 1–2 уровня), поэтому у части обложек seed
/// выходит соседним оттенком. Квантование и ранжирование на одних и тех же пикселях совпадают точно.
/// Блокирующая (декодирование + ~10 мс квантования) — звать из spawn_blocking.
pub fn seed_from_image(path: &Path) -> Result<u32, ThemeError> {
    seed_from_image_with(path, CrtRand::native())
}

/// seed_from_image с явным выбором rand() (см. CrtRand).
pub fn seed_from_image_with(path: &Path, crt: CrtRand) -> Result<u32, ThemeError> {
    let image = image::ImageReader::open(path)
        .and_then(|r| r.with_guessed_format())
        .map_err(|e| ThemeError::Image(format!("{}: {e}", path.display())))?
        .decode()
        .map_err(|e| ThemeError::Image(format!("{}: {e}", path.display())))?;
    Ok(seed_from_rgba_with(&image.to_rgba8(), crt))
}

/// То же по уже декодированной картинке (например, из памяти).
pub fn seed_from_rgba(image: &image::RgbaImage) -> u32 {
    seed_from_rgba_with(image, CrtRand::native())
}

pub fn seed_from_rgba_with(image: &image::RgbaImage, crt: CrtRand) -> u32 {
    seed_from_pixels_with(
        &scale::smooth_scale_rgb(image, SAMPLE_SIZE, SAMPLE_SIZE),
        crt,
    )
}

/// То же по готовым пикселям RGB.
pub fn seed_from_pixels(pixels: &[[u8; 3]]) -> u32 {
    seed_from_pixels_with(pixels, CrtRand::native())
}

pub fn seed_from_pixels_with(pixels: &[[u8; 3]], crt: CrtRand) -> u32 {
    if pixels.is_empty() {
        return DEFAULT_SEED;
    }
    let argb: Vec<u32> = pixels
        .iter()
        .map(|&[r, g, b]| 0xFF00_0000 | u32::from(r) << 16 | u32::from(g) << 8 | u32::from(b))
        .collect();
    let population = quantize::quantize_celebi(&argb, MAX_COLORS, crt);
    score::score(&population)
        .first()
        .copied()
        .unwrap_or(DEFAULT_SEED)
}

/// "#RRGGBB" / "#AARRGGBB" → ARGB (альфа FF), как QColor(str); неверная строка → None.
/// Как и QColor, понимает ещё "#RGB", "#RRRGGGBBB" и "#RRRRGGGGBBBB" (берутся старшие 8 бит канала).
pub fn parse_color(text: &str) -> Option<u32> {
    let hex = text.trim().strip_prefix('#')?;
    if hex.is_empty() || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let value = |s: &str| u32::from_str_radix(s, 16).ok();
    match hex.len() {
        3 => {
            let v = value(hex)?;
            let (r, g, b) = ((v >> 8) & 0xF, (v >> 4) & 0xF, v & 0xF);
            Some(0xFF00_0000 | (r * 0x11) << 16 | (g * 0x11) << 8 | (b * 0x11))
        }
        6 => Some(0xFF00_0000 | value(hex)?),
        8 => value(hex),
        9 | 12 => {
            let n = hex.len() / 3;
            let channel = |i: usize| value(&hex[i * n..(i + 1) * n]).map(|c| c >> ((n - 2) * 4));
            Some(0xFF00_0000 | channel(0)? << 16 | channel(1)? << 8 | channel(2)?)
        }
        _ => None,
    }
}

/// ARGB → "#AARRGGBB" (верхний регистр, как в тест-векторах).
pub fn format_color(argb: u32) -> String {
    format!("#{argb:08X}")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn camel(snake: &str) -> String {
        let mut out = String::new();
        let mut upper = false;
        for c in snake.chars() {
            if c == '_' {
                upper = true;
            } else if upper {
                out.extend(c.to_uppercase());
                upper = false;
            } else {
                out.push(c);
            }
        }
        out
    }

    #[test]
    fn roles_match_names() {
        for (name, role) in ROLE_NAMES.iter().zip(ROLES) {
            assert_eq!(*name, camel(role.name()));
        }
    }

    #[test]
    fn variant_names() {
        assert_eq!(
            Variant::names(),
            [
                "content",
                "tonalSpot",
                "vibrant",
                "expressive",
                "fidelity",
                "neutral",
                "monochrome"
            ]
        );
        for v in Variant::ALL {
            assert_eq!(Variant::from_name(v.name()), Some(v));
        }
        assert_eq!(Variant::from_name("rainbow"), None);
    }

    #[test]
    fn parse_colors() {
        assert_eq!(parse_color("#6750A4"), Some(0xFF6750A4));
        assert_eq!(parse_color("#806750a4"), Some(0x806750A4));
        assert_eq!(parse_color("#fc0"), Some(0xFFFFCC00));
        assert_eq!(parse_color("#ffffcccc0000"), Some(0xFFFFCC00));
        assert_eq!(parse_color(""), None);
        assert_eq!(parse_color("6750A4"), None);
        assert_eq!(parse_color("#6750A"), None);
        assert_eq!(parse_color("#zzzzzz"), None);
        assert_eq!(format_color(0xFF6750A4), "#FF6750A4");
    }

    #[test]
    fn empty_pixels_default_seed() {
        assert_eq!(seed_from_pixels(&[]), DEFAULT_SEED);
    }
}
