//! Строковые id Spotify (base62). Сериализуются строкой.
use serde::{Deserialize, Serialize};

/// id аккаунта Spotify (`User.id`), не числовой.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct AccountId(pub String);

impl AccountId {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// id плейлиста (base62, без префикса `spotify:playlist:`).
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct PlaylistId(pub String);

impl PlaylistId {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// `spotify:playlist:<id>`
    pub fn uri(&self) -> String {
        format!("spotify:playlist:{}", self.0)
    }

    /// Из id, URI `spotify:playlist:<id>` или ссылки `https://open.spotify.com/playlist/<id>?…`.
    pub fn from_uri_or_id(text: &str) -> Self {
        let text = text.trim();
        if let Some((_, rest)) = text.split_once("/playlist/") {
            let id = rest.split(['?', '#', '/']).next().unwrap_or(rest);
            return Self(id.to_owned());
        }
        Self(text.rsplit(':').next().unwrap_or(text).to_owned())
    }
}

impl std::borrow::Borrow<str> for PlaylistId {
    fn borrow(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for PlaylistId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
