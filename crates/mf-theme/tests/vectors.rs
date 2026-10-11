//! Сверка с выходом Python (theme.build_scheme / seed_from_image).
use std::path::Path;

use serde_json::Value;
use mf_theme::{
    CrtRand, DEFAULT_SEED, ROLE_NAMES, Variant, build_scheme, format_color, parse_color,
    seed_from_image, seed_from_image_with, seed_from_pixels_with,
};

fn manifest(rel: &str) -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

#[test]
fn schemes_match_python() {
    let text = std::fs::read_to_string(manifest("tests/vectors.json")).unwrap();
    let vectors: Vec<Value> = serde_json::from_str(&text).unwrap();
    assert_eq!(vectors.len(), 56);
    let mut mismatches = Vec::new();
    for v in &vectors {
        let seed = parse_color(v["seed"].as_str().unwrap()).unwrap();
        let dark = v["dark"].as_bool().unwrap();
        let variant = Variant::from_name(v["variant"].as_str().unwrap()).unwrap();
        let contrast = v["contrast"].as_f64().unwrap();
        let scheme = build_scheme(seed, dark, variant, contrast);
        let expected = v["colors"].as_object().unwrap();
        assert_eq!(expected.len(), ROLE_NAMES.len());
        assert_eq!(scheme.colors.len(), ROLE_NAMES.len());
        for (role, want) in expected {
            let got = scheme.colors.get(role.as_str()).map(|&c| format_color(c));
            if got.as_deref() != want.as_str() {
                mismatches.push(format!(
                    "{} dark={dark} {variant}: {role} = {got:?}, ждали {want}",
                    v["seed"]
                ));
            }
        }
    }
    assert!(
        mismatches.is_empty(),
        "{} расхождений:\n{}",
        mismatches.len(),
        mismatches.join("\n")
    );
}

#[test]
fn stable_roles_default_seed() {
    // фирменный фиолетовый, tonalSpot; значения — из Python theme.build_scheme
    let dark = build_scheme(DEFAULT_SEED, true, Variant::TonalSpot, 0.0);
    let light = build_scheme(DEFAULT_SEED, false, Variant::TonalSpot, 0.0);
    let hex = |s: &mf_theme::Scheme, role: &str| format_color(s.colors[role]);
    for (role, want) in [
        ("primary", "#FFCDC0EC"),
        ("onPrimary", "#FF443A5F"),
        ("primaryContainer", "#FF574D72"),
        ("surface", "#FF0F0D12"),
        ("onSurface", "#FFEAE3EF"),
        ("primaryFixed", "#FFDED0FE"),
        ("primaryDim", "#FFBFB2DE"),
        ("error", "#FFF97386"),
    ] {
        assert_eq!(hex(&dark, role), want, "dark {role}");
    }
    for (role, want) in [
        ("primary", "#FF655789"),
        ("onPrimary", "#FFFDF7FF"),
        ("primaryContainer", "#FFD4C3FD"),
        ("surface", "#FFFDF7FE"),
        ("onSurface", "#FF34313A"),
        ("primaryFixedDim", "#FFC6B6EE"),
        ("inversePrimary", "#FFD4C3FD"),
    ] {
        assert_eq!(hex(&light, role), want, "light {role}");
    }
    for s in [&dark, &light] {
        assert_eq!(s.colors["shadow"], 0xFF000000);
        assert_eq!(s.colors["scrim"], 0xFF000000);
        assert_eq!(s.colors["surfaceTint"], s.colors["primary"]);
        assert_eq!(s.colors.len(), ROLE_NAMES.len());
    }
    assert_eq!(dark.seed, DEFAULT_SEED);
    assert!(dark.dark && !light.dark);
}

/// Пиксели 112×112, которые отдаёт Qt (QImage.scaled Smooth → RGB888) для seed.png.
/// На одних и тех же пикселях квантование и ранжирование обязаны совпасть с Python точно.
/// Эталоны сняты Python на Windows, поэтому rand() — MSVC (на других ОС Python сам даёт иное).
#[test]
fn seed_from_qt_pixels_matches_python() {
    let raw = std::fs::read(manifest("tests/seed_112.rgb")).unwrap();
    assert_eq!(raw.len(), 112 * 112 * 3);
    let pixels: Vec<[u8; 3]> = raw.as_chunks::<3>().0.to_vec();
    assert_eq!(seed_from_pixels_with(&pixels, CrtRand::Msvc), 0xFFFFDB00);
}

/// Полный путь от файла: декодирование `image` и порт qSmoothScaleImage (у seed.png 17 из 12544
/// пикселей отличаются от Qt на 1), seed совпадает с Python — #FFFFDB00.
#[test]
fn seed_from_image_matches_python() {
    let png = manifest("tests/seed.png");
    assert_eq!(
        seed_from_image_with(&png, CrtRand::Msvc).unwrap(),
        0xFFFFDB00
    );
    // у этой картинки результат не зависит от rand()
    assert_eq!(
        seed_from_image_with(&png, CrtRand::Glibc).unwrap(),
        0xFFFFDB00
    );
    assert_eq!(seed_from_image(&png).unwrap() >> 24, 0xFF);
}

#[test]
fn seed_from_missing_image_is_error() {
    assert!(seed_from_image(Path::new("нет/такой/картинки.png")).is_err());
}

/// Широкая сверка с Python: по строке на схему — seed dark variant contrast и 59 ARGB в порядке ROLE_NAMES.
/// По умолчанию — tests/schemes_extra.txt (217 схем: оттенки по кругу, чёрный/белый, контраст −1…1, выборка
/// из 12852 схем, сверенных при порте); полный дамп можно подать через MF_THEME_DUMP=<файл>.
#[test]
fn schemes_match_python_dump() {
    let path = std::env::var("MF_THEME_DUMP")
        .unwrap_or_else(|_| manifest("tests/schemes_extra.txt").display().to_string());
    let text = std::fs::read_to_string(path).unwrap();
    let mut bad = Vec::new();
    let mut total = 0;
    for line in text.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        let seed = u32::from_str_radix(parts[0], 16).unwrap();
        let dark = parts[1] == "1";
        let variant = Variant::from_name(parts[2]).unwrap();
        let contrast: f64 = parts[3].parse().unwrap();
        let scheme = build_scheme(seed, dark, variant, contrast);
        total += 1;
        for (name, want) in ROLE_NAMES.iter().zip(&parts[4..]) {
            let got = format!("{:08X}", scheme.colors[name]);
            if got != *want {
                bad.push(format!(
                    "{seed:08X} dark={dark} {variant} c={contrast}: {name} = {got}, ждали {want}"
                ));
            }
        }
    }
    assert!(
        bad.is_empty(),
        "{total} схем, {} расхождений:\n{}",
        bad.len(),
        bad[..bad.len().min(80)].join("\n")
    );
}

/// Сверка seed_from_image с Python (Windows) на наборе картинок: MF_THEME_SEEDS=<файл «путь ARGB» по строке>.
/// При порте: 40 картинок, PNG — все совпали, JPEG — 10 из 20 отличаются из-за декодера (см. seed_from_image).
#[test]
#[ignore]
fn seeds_match_python_dump() {
    let Ok(path) = std::env::var("MF_THEME_SEEDS") else {
        return;
    };
    let text = std::fs::read_to_string(path).unwrap();
    let mut bad = Vec::new();
    let mut total = 0;
    for line in text.lines() {
        let (file, want) = line.rsplit_once(' ').unwrap();
        let got = format!(
            "{:08X}",
            seed_from_image_with(Path::new(file), CrtRand::Msvc).unwrap()
        );
        total += 1;
        let lower = file.to_ascii_lowercase();
        if got != want {
            // JPEG — другой декодер, расхождение ожидаемо; только печатаем
            if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
                println!("JPEG {file}: {got}, у Python {want}");
            } else {
                bad.push(format!("{file}: {got}, ждали {want}"));
            }
        }
    }
    assert!(
        bad.is_empty(),
        "{total} картинок, {} расхождений:\n{}",
        bad.len(),
        bad.join("\n")
    );
}

/// То же, но по пикселям, уже уменьшенным Qt (рядом с картинкой лежит <путь>.rgb): проверяет только
/// квантование и ранжирование (при порте — 40 из 40).
#[test]
#[ignore]
fn seeds_from_qt_pixels_match_python_dump() {
    let Ok(path) = std::env::var("MF_THEME_SEEDS") else {
        return;
    };
    let text = std::fs::read_to_string(path).unwrap();
    let mut bad = Vec::new();
    for line in text.lines() {
        let (file, want) = line.rsplit_once(' ').unwrap();
        let raw = std::fs::read(format!("{file}.rgb")).unwrap();
        let pixels: Vec<[u8; 3]> = raw.as_chunks::<3>().0.to_vec();
        let got = format!("{:08X}", seed_from_pixels_with(&pixels, CrtRand::Msvc));
        if got != want {
            bad.push(format!("{file}: {got}, ждали {want}"));
        }
    }
    assert!(
        bad.is_empty(),
        "{} расхождений:\n{}",
        bad.len(),
        bad.join("\n")
    );
}
