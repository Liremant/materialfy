//! Маршрутизация чтений: плейлисты через сессию librespot (без квоты Web API), остальное — ApiGateway.
//! Тексты ошибок Web API по-русски.
use std::time::Duration;

use sf_api::models::{Page, Playlist, PlaylistItem};
use sf_api::{ApiError, ApiGateway, Operation};
use sf_player::PlayerHandle;
use sf_player::engine::session_reads::{self, Failure};

pub const PLAYLIST_PAGE: u32 = 50;

/// Сколько ждать сессию, прежде чем спросить Web API.
const SESSION_READ_TIMEOUT: Duration = Duration::from_secs(30);

/// Короткий текст ошибки для пользователя (перевод — в sf-api, ApiError::user_text).
pub fn api_error_text(error: &ApiError) -> String {
    error.user_text()
}

/// Ошибка страницы плейлиста (403/404 — Spotify не отдаёт его сторонним приложениям).
pub fn playlist_error_text(error: &ApiError) -> String {
    match error.status() {
        Some(403 | 404) => "Spotify не отдаёт треки этого плейлиста сторонним приложениям".to_owned(),
        _ => api_error_text(error),
    }
}

fn session_for(api: &ApiGateway, player: &PlayerHandle, operation: Operation) -> Option<sf_player::Session> {
    if !api.session_serves(operation) {
        return None;
    }
    let session = player.session()?;
    let account = api.account()?;
    (session.username() == account.as_str()).then_some(session)
}

/// Ответ сессии как ответ Web API; None — сессия не смогла, спросить Web API.
fn settle<T>(result: Result<Result<T, Failure>, tokio::time::error::Elapsed>) -> Option<Result<T, ApiError>> {
    match result {
        Ok(Ok(value)) => Some(Ok(value)),
        Ok(Err(Failure::Definitive(error))) => Some(Err(error)),
        Ok(Err(Failure::Retry(error))) => {
            tracing::debug!("чтение через сессию не удалось: {error:#}; спрашиваю Web API");
            None
        }
        Err(_) => {
            tracing::debug!("чтение через сессию не успело; спрашиваю Web API");
            None
        }
    }
}

/// Шапка плейлиста.
pub async fn playlist(api: &ApiGateway, player: &PlayerHandle, id: &str) -> Result<Playlist, ApiError> {
    let operation = Operation::PlaylistMetadata(api.playlist_access(id));
    if let Some(session) = session_for(api, player, operation)
        && let Some(result) =
            settle(tokio::time::timeout(SESSION_READ_TIMEOUT, session_reads::playlist(&session, id)).await)
    {
        if let Ok(playlist) = &result {
            api.observe_playlist(playlist);
        }
        return result;
    }
    let playlist = api.client_for(operation).await?.playlist(id).await?;
    api.observe_playlist(&playlist);
    Ok(playlist)
}

/// Страница строк плейлиста (по 50).
pub async fn playlist_items(
    api: &ApiGateway,
    player: &PlayerHandle,
    id: &str,
    offset: u32,
) -> Result<Page<PlaylistItem>, ApiError> {
    let operation = Operation::PlaylistItems(api.playlist_access(id));
    if let Some(session) = session_for(api, player, operation)
        && let Some(result) = settle(
            tokio::time::timeout(SESSION_READ_TIMEOUT, session_reads::items(&session, id, offset, PLAYLIST_PAGE)).await,
        )
    {
        return result;
    }
    api.client_for(operation).await?.playlist_items(id, offset, PLAYLIST_PAGE).await
}

/// Все страницы списка со смещением (`limit` за раз), с потолком `max_pages`.
pub async fn all_pages<T, F, Fut>(limit: u32, max_pages: u32, mut fetch: F) -> Result<Vec<T>, ApiError>
where
    F: FnMut(u32, u32) -> Fut,
    Fut: std::future::Future<Output = Result<Page<T>, ApiError>>,
{
    let mut items = Vec::new();
    let mut offset = 0;
    for _ in 0..max_pages {
        let page = fetch(offset, limit).await?;
        let next = page.next_offset();
        items.extend(page.items);
        match next {
            Some(next) if next > offset => offset = next,
            _ => break,
        }
    }
    Ok(items)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errors_read_in_russian() {
        assert_eq!(api_error_text(&ApiError::NotSignedIn), "Войдите в аккаунт");
        assert!(api_error_text(&ApiError::Network("x".into())).contains("прокси"));
        let refused = ApiError::Status { status: 404, message: "Not found".into() };
        assert!(playlist_error_text(&refused).contains("сторонним"));
    }

    #[tokio::test]
    async fn all_pages_follows_next_offsets() {
        let pages = all_pages(2, 10, |offset, limit| async move {
            Ok(Page {
                items: (offset..(offset + limit).min(5)).collect::<Vec<u32>>(),
                total: 5,
                limit,
                offset,
                next: (offset + limit < 5).then(|| "n".to_owned()),
            })
        })
        .await
        .unwrap();
        assert_eq!(pages, vec![0, 1, 2, 3, 4]);
    }
}
