//! URI-хелперы Spotify и мелочи (перенос из spotifast/src/util.rs; форматирование — в QML).

pub fn uri_id(uri: &str) -> Option<&str> {
    uri.rsplit(':').next().filter(|id| !id.is_empty())
}

pub fn uri_kind(uri: &str) -> Option<&str> {
    let mut parts = uri.split(':');
    parts.next()?;
    parts.next()
}

/// Станция Spotify по треку, плейлисту, альбому или исполнителю.
pub fn station_uri(seed: &str) -> Option<String> {
    let kind = uri_kind(seed)?;
    let id = uri_id(seed)?;
    (seed == format!("spotify:{kind}:{id}") && matches!(kind, "track" | "playlist" | "album" | "artist"))
        .then(|| format!("spotify:station:{kind}:{id}"))
}

/// Сид станции (обратное к station_uri).
pub fn station_seed(station: &str) -> Option<String> {
    let seed = format!("spotify:{}", station.strip_prefix("spotify:station:")?);
    station_uri(&seed).is_some().then_some(seed)
}

/// https://open.spotify.com/<kind>/<id>
pub fn open_spotify_url(uri: &str) -> Option<String> {
    let kind = uri_kind(uri)?;
    let id = uri_id(uri)?;
    Some(format!("https://open.spotify.com/{kind}/{id}"))
}

/// Сид из QML-формы "artist:ID" | "track:ID" | "album:ID" | "playlist:ID" или полного URI → spotify:<kind>:<id>.
pub fn seed_uri(seed: &str) -> Option<String> {
    if seed.starts_with("spotify:") {
        return Some(seed.to_owned());
    }
    let (kind, id) = seed.split_once(':')?;
    matches!(kind, "track" | "artist" | "album" | "playlist").then(|| format!("spotify:{kind}:{id}"))
}

/// Убирает HTML из описаний плейлистов/выпусков.
pub fn strip_html(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut in_tag = false;
    for character in text.chars() {
        match character {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(character),
            _ => {}
        }
    }
    out.replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#x27;", "'")
        .replace("&#39;", "'")
        .replace("&#x2F;", "/")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
}

/// Атомарная замена файла: запись во временный рядом + замена (на Windows — MoveFileEx).
pub fn replace_file(path: &std::path::Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let name = path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
    let temporary = path.with_file_name(format!(".{name}.{}.tmp", std::process::id()));
    let written = (|| {
        let mut file = std::fs::File::create(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()
    })()
    .and_then(|()| move_over(&temporary, path));
    if written.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    written
}

/// Атомарно ставит `temporary` на место `path`.
#[cfg(not(windows))]
pub fn move_over(temporary: &std::path::Path, path: &std::path::Path) -> std::io::Result<()> {
    std::fs::rename(temporary, path)
}

/// Атомарно ставит `temporary` на место `path`.
#[cfg(windows)]
pub fn move_over(temporary: &std::path::Path, path: &std::path::Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW};

    let temporary: Vec<u16> = temporary.as_os_str().encode_wide().chain(Some(0)).collect();
    let path: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
    // SAFETY: обе строки — нуль-терминированные UTF-16, живут до конца вызова.
    let moved = unsafe {
        MoveFileExW(temporary.as_ptr(), path.as_ptr(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)
    };
    if moved == 0 { Err(std::io::Error::last_os_error()) } else { Ok(()) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn radio_stations_map_to_their_seeds_and_back() {
        for kind in ["track", "playlist", "album", "artist"] {
            let seed = format!("spotify:{kind}:4uLU6hMCjMI75M1A2tKUQC");
            let station = station_uri(&seed).expect("станция");
            assert_eq!(station, format!("spotify:station:{kind}:4uLU6hMCjMI75M1A2tKUQC"));
            assert_eq!(station_seed(&station).as_deref(), Some(seed.as_str()));
        }
        for seed in ["spotify:show:abc", "spotify:episode:abc", "spotify:user:me:collection", "spotify:track:", "track:abc"] {
            assert_eq!(station_uri(seed), None, "{seed}");
        }
        assert_eq!(station_seed("spotify:playlist:abc"), None);
    }

    #[test]
    fn uris() {
        assert_eq!(uri_id("spotify:track:abc"), Some("abc"));
        assert_eq!(uri_kind("spotify:playlist:x"), Some("playlist"));
        assert_eq!(open_spotify_url("spotify:album:z").as_deref(), Some("https://open.spotify.com/album/z"));
    }

    #[test]
    fn seeds_from_qml() {
        assert_eq!(seed_uri("artist:abc").as_deref(), Some("spotify:artist:abc"));
        assert_eq!(seed_uri("spotify:track:x").as_deref(), Some("spotify:track:x"));
        assert_eq!(seed_uri("show:x"), None);
        assert_eq!(seed_uri("nothing"), None);
    }

    #[test]
    fn html_is_stripped() {
        assert_eq!(strip_html("Hi <a href=\"x\">there</a> &amp; you"), "Hi there & you");
        assert_eq!(strip_html("ONE&#x2F;TWO&#x2F;THREE"), "ONE/TWO/THREE");
    }

    #[test]
    fn files_are_replaced_whole() {
        let dir = std::env::temp_dir().join(format!("sf-api-replace-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.json");
        replace_file(&path, b"first").unwrap();
        replace_file(&path, b"second").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"second");
        let leftovers = std::fs::read_dir(&dir).unwrap().count();
        assert_eq!(leftovers, 1, "временный файл не должен оставаться");
        let _ = std::fs::remove_dir_all(dir);
    }
}
