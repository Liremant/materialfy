//! Сохранённая сессия плеера (queue.md п. 9): трек и позиция возобновления, контекст, ручная очередь,
//! первые строки «Далее», shuffle. Файл пишется атомарно (временный файл + переименование).
use std::path::Path;

use md3_model::{PlayContext, TrackItem};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SessionData {
    pub version: u32,
    pub context_uri: Option<String>,
    pub context: PlayContext,
    /// трек возобновления (с данными для показа до первого Play)
    pub track: Option<TrackItem>,
    pub position_ms: u32,
    /// «Далее в очереди» — URI в порядке воспроизведения
    pub manual: Vec<String>,
    /// первые строки «Далее» (до 30)
    pub rows: Vec<TrackItem>,
    pub shuffle: bool,
}

impl SessionData {
    pub const VERSION: u32 = 1;

    pub fn load(path: &Path) -> Option<Self> {
        let bytes = std::fs::read(path).ok()?;
        match serde_json::from_slice::<Self>(&bytes) {
            Ok(data) if data.version == Self::VERSION => Some(data),
            Ok(_) => None,
            Err(error) => {
                tracing::warn!("player session not read: {error:#}");
                None
            }
        }
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        let bytes = serde_json::to_vec_pretty(self).map_err(std::io::Error::other)?;
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let temporary = path.with_extension("json.tmp");
        std::fs::write(&temporary, bytes)?;
        std::fs::rename(&temporary, path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_survives_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("sf-player-session-{}", std::process::id()));
        let path = dir.join("session.json");
        let data = SessionData {
            version: SessionData::VERSION,
            context_uri: Some("spotify:playlist:x".into()),
            context: PlayContext::with_uri("playlist", "spotify:playlist:x").titled("Плейлист"),
            track: Some(TrackItem { uri: "spotify:track:a".into(), title: "A".into(), ..Default::default() }),
            position_ms: 19_566,
            manual: vec!["spotify:track:b".into(), "spotify:track:b".into()],
            rows: vec![TrackItem { uri: "spotify:track:b".into(), ..Default::default() }],
            shuffle: true,
        };
        data.save(&path).unwrap();
        assert_eq!(SessionData::load(&path), Some(data));
        let _ = std::fs::remove_dir_all(dir);
    }
}
