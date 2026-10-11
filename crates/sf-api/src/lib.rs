//! Spotify Web API без UI: клиент (лимиты 429/Retry-After, квота), маршрутизация общего/личного приложения,
//! serde-модели, HTTP с прокси, ссылки, обложки плейлистов, маппинг в md3-model.

use std::fmt;

pub mod client;
pub mod gateway;
pub mod http;
pub mod limits;
pub mod link;
pub mod map;
pub mod models;
pub mod playlist_cover;
pub mod util;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ApiSource {
    Shared,
    Personal,
}

impl fmt::Display for ApiSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Shared => formatter.write_str("shared"),
            Self::Personal => formatter.write_str("personal"),
        }
    }
}

pub use client::{ApiClient, ApiError, NetActivity, PlayRequest, TokenProvider, WebTokens};
pub use gateway::{AccountId, ApiGateway, Operation, PlaylistAccess, PlaylistId, SessionState};
pub use http::Http;
pub use limits::{LimitKind, Priority, WebApiLimits};
