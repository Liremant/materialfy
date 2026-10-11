//! Вход в Spotify без UI: PKCE-гранты (oauth), хранилище секретов (credentials), прокси (proxy).
//! Нижний крейт sf-*: от него зависят sf-api, sf-player, sf-services.

pub mod credentials;
pub mod oauth;
pub mod proxy;

pub use credentials::{Lease, Loaded, ProxyPassword, Slot, Store};
pub use oauth::{
    DEFAULT_WEB_CLIENT_ID, Flow, Grant, PLAYBACK_CLIENT_ID, PLAYBACK_REDIRECT_PORT, StoredToken, TokenEndpointError,
    TokenResponse, WEB_REDIRECT_PORT,
};
pub use proxy::{ManualProxy, ProxyConfig, ProxyMode};

/// Открыть URL в браузере по умолчанию (не блокирует).
pub fn open_browser(url: &str) -> Result<(), String> {
    open::that_detached(url).map_err(|e| e.to_string())
}
