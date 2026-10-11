//! Каталог (исполнитель «services-core»): альбом, исполнитель, поиск (эвристика «лучшего»), шоу и выпуски.
//! Без состояния, кроме кэша на 10 минут; маршрутизация общего/личного приложения — ApiGateway::client_for(Operation).
use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use md3_model::{
    AlbumInfo, AlbumItem, ArtistInfo, ArtistItem, EpisodeItem, PlaylistItem, SearchBest, SearchTotals, ShowItem, TrackItem,
};
use sf_api::map;
use sf_api::models::{self, Album, Artist, Track};
use sf_api::{ApiError, Operation};
use sf_player::PlayerHandle;
use sf_player::engine::session_reads;
use tokio::sync::Semaphore;

use crate::auth::AuthService;
use crate::data::{known, pathfinder, route};
use crate::{ServiceError, lock};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum SearchKind {
    #[default]
    All,
    Tracks,
    Albums,
    Artists,
    Playlists,
    Shows,
    Episodes,
}

impl SearchKind {
    /// "all" | "tracks" | "albums" | "artists" | "playlists" | "shows" | "episodes"; иное → All
    pub fn from_name(name: &str) -> Self {
        match name {
            "tracks" => Self::Tracks,
            "albums" => Self::Albums,
            "artists" => Self::Artists,
            "playlists" => Self::Playlists,
            "shows" => Self::Shows,
            "episodes" => Self::Episodes,
            _ => Self::All,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Tracks => "tracks",
            Self::Albums => "albums",
            Self::Artists => "artists",
            Self::Playlists => "playlists",
            Self::Shows => "shows",
            Self::Episodes => "episodes",
        }
    }

    /// Типы поиска Web API: каталог и плейлисты (плейлисты ищет только общее приложение).
    fn api_types(self) -> (Vec<&'static str>, bool) {
        match self {
            Self::All => (vec!["track", "artist", "album", "show", "episode"], true),
            Self::Tracks => (vec!["track"], false),
            Self::Albums => (vec!["album"], false),
            Self::Artists => (vec!["artist"], false),
            Self::Playlists => (Vec::new(), true),
            Self::Shows => (vec!["show"], false),
            Self::Episodes => (vec!["episode"], false),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct AlbumPage {
    pub info: AlbumInfo,
    /// все треки (длинные альбомы — постранично по 50)
    pub tracks: Vec<TrackItem>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArtistPage {
    pub info: ArtistInfo,
    /// /artists/{id}/top-tracks
    pub popular: Vec<TrackItem>,
    /// album,single
    pub albums: Vec<AlbumItem>,
    /// appears_on,compilation
    pub also_albums: Vec<AlbumItem>,
    /// related-artists (может быть пусто — закрыто для новых приложений)
    pub similar: Vec<ArtistItem>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct SearchResults {
    pub tracks: Vec<TrackItem>,
    pub albums: Vec<AlbumItem>,
    pub artists: Vec<ArtistItem>,
    pub playlists: Vec<PlaylistItem>,
    pub shows: Vec<ShowItem>,
    pub episodes: Vec<EpisodeItem>,
    pub totals: SearchTotals,
    /// эвристика: исполнитель с совпадающим именем, иначе первый трек
    pub best: Option<SearchBest>,
}

impl SearchResults {
    pub fn is_empty(&self) -> bool {
        self.tracks.is_empty()
            && self.albums.is_empty()
            && self.artists.is_empty()
            && self.playlists.is_empty()
            && self.shows.is_empty()
            && self.episodes.is_empty()
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ShowPage {
    pub info: ShowItem,
    /// первая страница выпусков (новые сверху)
    pub episodes: Vec<EpisodeItem>,
    pub total: i64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct EpisodePage {
    pub info: EpisodeItem,
    pub show: ShowItem,
    /// 2–3 соседних выпуска для «Ещё выпуски»
    pub more: Vec<EpisodeItem>,
}

/// Кэш страниц каталога.
const FRESH: Duration = Duration::from_secs(10 * 60);
const CACHE_KEPT: usize = 200;
/// Альбом длиннее — режется (сборники по 1000 треков).
const MAX_ALBUM_PAGES: u32 = 40;
/// Страница выпусков шоу.
const EPISODE_PAGE: u32 = 50;

#[derive(Clone)]
enum Cached {
    Album(AlbumPage),
    Artist(ArtistPage),
    Show(ShowPage),
    Episode(EpisodePage),
    Track(TrackItem),
}

pub struct CatalogService {
    auth: Arc<AuthService>,
    player: PlayerHandle,
    cache: Mutex<HashMap<String, (Instant, Cached)>>,
    /// превью исполнителя по наведению — не больше двух загрузок сразу
    artists: Semaphore,
}

/// Сколько необязательные запросы страницы (подписка, похожие) могут отстать от основного чтения:
/// под 429 общее приложение отвечает минутами, а страница без них всё равно полезна.
const EXTRAS_GRACE: Duration = Duration::from_millis(1500);

/// Ответ `main`; ответ `extras` — если успел вместе с ним или не позже `grace` после.
async fn with_extras<M: Future, E: Future>(main: M, extras: E, grace: Duration) -> (M::Output, Option<E::Output>) {
    tokio::pin!(main, extras);
    tokio::select! {
        biased;
        out = &mut main => (out, tokio::time::timeout(grace, extras).await.ok()),
        found = &mut extras => (main.await, Some(found)),
    }
}

/// Только разделы вида поиска `kind` (шлюз отвечает всеми сразу).
fn only(kind: SearchKind, mut results: models::SearchResults) -> models::SearchResults {
    let (types, playlists) = kind.api_types();
    let wanted = |name: &str| types.contains(&name);
    if !wanted("track") {
        results.tracks = None;
    }
    if !wanted("artist") {
        results.artists = None;
    }
    if !wanted("album") {
        results.albums = None;
    }
    if !wanted("show") {
        results.shows = None;
    }
    if !wanted("episode") {
        results.episodes = None;
    }
    if !playlists {
        results.playlists = None;
    }
    results
}

/// Раздел страницы, который не загрузился, остаётся пустым, а не роняет страницу.
fn or_empty<T>(section: Result<Vec<T>, ApiError>, name: &str, id: &str) -> Vec<T> {
    section.unwrap_or_else(|error| {
        tracing::debug!("{name} ({id}): {error:#}");
        Vec::new()
    })
}

/// Перевод ошибки Web API в ошибку сервиса; NotSignedIn — отдельно.
fn service_error(error: ApiError) -> ServiceError {
    match error {
        ApiError::NotSignedIn => ServiceError::NotSignedIn,
        other => ServiceError::Api(other),
    }
}

/// Треки альбома приходят без вложенного альбома — вернуть его для обложек и ссылок.
fn with_album(mut tracks: Vec<Track>, album: &Album) -> Vec<Track> {
    let mut bare = album.clone();
    bare.tracks = None;
    for track in &mut tracks {
        if track.album.is_none() {
            track.album = Some(bare.clone());
        }
    }
    tracks
}

/// Собрать страницу альбома из ответов Web API.
pub fn album_page(album: &Album, tracks: Vec<Track>) -> AlbumPage {
    let tracks = with_album(tracks, album);
    known::remember_recordings(tracks.iter());
    let items: Vec<TrackItem> = tracks.iter().map(map::track_item).collect();
    known::remember(items.iter());
    AlbumPage { info: map::album_info(album, &tracks), tracks: items }
}

/// Страница исполнителя: похожие и популярное могут отсутствовать.
pub fn artist_page(
    artist: &Artist,
    followed: bool,
    popular: &[Track],
    albums: &[Album],
    also: &[Album],
    similar: &[Artist],
) -> ArtistPage {
    known::remember_recordings(popular.iter());
    let popular: Vec<TrackItem> = popular.iter().map(map::track_item).collect();
    known::remember(popular.iter());
    ArtistPage {
        info: map::artist_info(artist, followed),
        popular,
        albums: albums.iter().map(map::album_item).collect(),
        also_albums: also.iter().map(map::album_item).collect(),
        similar: similar.iter().map(map::artist_item).collect(),
    }
}

/// Лучший результат: исполнитель, чьё имя совпало с запросом (или треков нет), иначе первый трек, альбом,
/// плейлист, шоу (ui/search.rs::all в spotifast).
pub fn best_result(query: &str, results: &models::SearchResults) -> Option<SearchBest> {
    fn best<T: serde::Serialize>(kind: &str, item: T) -> Option<SearchBest> {
        match serde_json::to_value(item) {
            Ok(serde_json::Value::Object(item)) => Some(SearchBest { kind: kind.to_owned(), item }),
            _ => None,
        }
    }
    fn first<T>(page: &Option<models::Page<T>>) -> Option<&T> {
        page.as_ref().and_then(|page| page.items.first())
    }
    let query = query.trim().to_lowercase();
    let tracks = results.tracks.as_ref().map(|page| page.items.as_slice()).unwrap_or_default();
    if let Some(artist) = first(&results.artists).filter(|artist| artist.name.to_lowercase() == query || tracks.is_empty())
    {
        return best("artist", map::artist_item(artist));
    }
    if let Some(track) = tracks.first() {
        return best("track", map::track_item(track));
    }
    if let Some(album) = first(&results.albums) {
        return best("album", map::album_item(album));
    }
    if let Some(playlist) = first(&results.playlists) {
        return best("playlist", map::playlist_item(playlist, None));
    }
    first(&results.shows).and_then(|show| best("show", map::show_item(show)))
}

/// Ответ поиска Web API → результаты для QML.
pub fn search_results(query: &str, results: &models::SearchResults, me: Option<&md3_model::AccountId>) -> SearchResults {
    let total = |page: Option<u32>| page.map(i64::from).unwrap_or(0);
    if let Some(page) = &results.tracks {
        known::remember_recordings(page.items.iter());
    }
    let tracks: Vec<TrackItem> =
        results.tracks.as_ref().map(|page| page.items.iter().map(map::track_item).collect()).unwrap_or_default();
    known::remember(tracks.iter());
    SearchResults {
        tracks,
        albums: results.albums.as_ref().map(|p| p.items.iter().map(map::album_item).collect()).unwrap_or_default(),
        artists: results.artists.as_ref().map(|p| p.items.iter().map(map::artist_item).collect()).unwrap_or_default(),
        playlists: results
            .playlists
            .as_ref()
            .map(|p| p.items.iter().map(|pl| map::playlist_item(pl, me)).collect())
            .unwrap_or_default(),
        shows: results.shows.as_ref().map(|p| p.items.iter().map(map::show_item).collect()).unwrap_or_default(),
        episodes: results
            .episodes
            .as_ref()
            .map(|p| p.items.iter().map(|ep| map::episode_item(ep, None)).collect())
            .unwrap_or_default(),
        totals: SearchTotals {
            tracks: total(results.tracks.as_ref().map(|p| p.total)),
            albums: total(results.albums.as_ref().map(|p| p.total)),
            artists: total(results.artists.as_ref().map(|p| p.total)),
            playlists: total(results.playlists.as_ref().map(|p| p.total)),
            shows: total(results.shows.as_ref().map(|p| p.total)),
            episodes: total(results.episodes.as_ref().map(|p| p.total)),
        },
        best: best_result(query, results),
    }
}

impl CatalogService {
    pub fn new(auth: Arc<AuthService>, player: PlayerHandle) -> Arc<Self> {
        Arc::new(Self { auth, player, cache: Mutex::new(HashMap::new()), artists: Semaphore::new(2) })
    }

    fn cached(&self, key: &str) -> Option<Cached> {
        let cache = lock(&self.cache);
        cache.get(key).filter(|(at, _)| at.elapsed() < FRESH).map(|(_, value)| value.clone())
    }

    fn store(&self, key: String, value: Cached) {
        let mut cache = lock(&self.cache);
        if cache.len() >= CACHE_KEPT {
            cache.retain(|_, (at, _)| at.elapsed() < FRESH);
            if cache.len() >= CACHE_KEPT
                && let Some(oldest) = cache.iter().min_by_key(|(_, (at, _))| *at).map(|(key, _)| key.clone())
            {
                cache.remove(&oldest);
            }
        }
        cache.insert(key, (Instant::now(), value));
    }

    /// Забыть кэш (смена аккаунта, сохранение изменило «saved»).
    pub fn forget(&self) {
        lock(&self.cache).clear();
    }

    async fn client(&self, operation: Operation) -> Result<Arc<sf_api::ApiClient>, ServiceError> {
        self.auth.api().client_for(operation).await.map_err(|error| self.fail(error))
    }

    fn fail(&self, error: ApiError) -> ServiceError {
        self.auth.note_api_error(&error);
        service_error(error)
    }

    pub async fn album(&self, album_id: &str) -> Result<AlbumPage, ServiceError> {
        let key = format!("album:{album_id}");
        if let Some(Cached::Album(page)) = self.cached(&key) {
            return Ok(page);
        }
        // Альбом и все его треки — из сессии librespot (без квоты Web API); Web API — запасной путь.
        let (album, tracks, complete) = match self.session_album(album_id).await {
            Some(Ok((album, tracks))) => (album, tracks, true),
            Some(Err(error)) => return Err(self.fail(error)),
            None => self.api_album(album_id).await?,
        };
        let page = album_page(&album, tracks);
        // оборванный список не кэшируется: следующее открытие дочитает
        if complete {
            self.store(key, Cached::Album(page.clone()));
        }
        Ok(page)
    }

    /// Альбом через сессию; None — сессии нет или она не смогла.
    async fn session_album(&self, album_id: &str) -> Option<Result<(Album, Vec<Track>), ApiError>> {
        let session = route::account_session(&self.auth.api(), &self.player)?;
        route::session_read(session_reads::album_with_tracks(&session, album_id)).await
    }

    /// Альбом через Web API. Обязателен только сам альбом с первой страницей треков: следующая страница,
    /// которая не загрузилась (429, сеть), обрывает список, а не страницу; третье поле — список полон.
    async fn api_album(&self, album_id: &str) -> Result<(Album, Vec<Track>, bool), ServiceError> {
        let client = self.client(Operation::Catalog).await?;
        let album = client.album(album_id).await.map_err(|e| self.fail(e))?;
        let first = album.tracks.clone().unwrap_or_default();
        let mut next = first.next_offset();
        let mut tracks = first.items;
        for _ in 0..MAX_ALBUM_PAGES {
            let Some(offset) = next else { break };
            match client.album_tracks(album_id, offset, 50).await {
                Ok(page) => {
                    next = page.next_offset().filter(|n| *n > offset);
                    tracks.extend(page.items);
                }
                Err(error) => {
                    tracing::debug!("треки альбома {album_id} с {offset}: {error:#}");
                    return Ok((album, tracks, false));
                }
            }
        }
        Ok((album, tracks, true))
    }

    pub async fn artist(&self, artist_id: &str) -> Result<ArtistPage, ServiceError> {
        let key = format!("artist:{artist_id}");
        if let Some(Cached::Artist(page)) = self.cached(&key) {
            return Ok(page);
        }
        let _permit = self.artists.acquire().await.map_err(|_| ServiceError::Other("каталог остановлен".into()))?;
        if let Some(Cached::Artist(page)) = self.cached(&key) {
            return Ok(page);
        }
        // Страница целиком — из сессии librespot (без квоты Web API: общее приложение подолгу отвечает 429,
        // а исполнителю нужно пять запросов); Web API — запасной путь. Подписка и похожие — только Web API,
        // поэтому идут параллельно и не задерживают страницу дольше EXTRAS_GRACE.
        let uri = format!("spotify:artist:{artist_id}");
        let extras = async { tokio::join!(self.followed(&uri), self.related(artist_id)) };
        let (session, extras) = with_extras(self.session_artist(artist_id), extras, EXTRAS_GRACE).await;
        let (followed, related) = extras.unwrap_or_default();
        let page = match session {
            Some(Ok(overview)) => {
                let similar = if overview.related.is_empty() { related } else { overview.related };
                artist_page(&overview.artist, followed, &overview.top_tracks, &overview.albums, &overview.appears_on, &similar)
            }
            Some(Err(error)) => return Err(self.fail(error)),
            None => {
                let (artist, popular, albums, also) = self.api_artist(artist_id).await?;
                artist_page(&artist, followed, &popular, &albums, &also, &related)
            }
        };
        self.store(key, Cached::Artist(page.clone()));
        Ok(page)
    }

    /// Исполнитель через сессию; None — сессии нет или она не смогла.
    async fn session_artist(&self, artist_id: &str) -> Option<Result<session_reads::ArtistOverview, ApiError>> {
        let session = route::account_session(&self.auth.api(), &self.player)?;
        route::session_read(session_reads::artist(&session, artist_id)).await
    }

    /// Исполнитель через Web API. Обязателен только сам исполнитель: раздел, который не загрузился
    /// (популярное закрыто для приложений в режиме разработки, 429, лимиты), остаётся пустым.
    async fn api_artist(&self, artist_id: &str) -> Result<(Artist, Vec<Track>, Vec<Album>, Vec<Album>), ServiceError> {
        let catalog = self.client(Operation::Catalog).await?;
        let artist = catalog.artist(artist_id).await.map_err(|e| self.fail(e))?;
        let popular = async {
            let restricted = self.auth.api().client_for(Operation::UnsupportedDevelopmentMode).await?;
            restricted.artist_top_tracks(artist_id).await
        };
        let (popular, albums, also) = tokio::join!(
            popular,
            catalog.artist_albums(artist_id, "album,single", 0, 50),
            catalog.artist_albums(artist_id, "appears_on,compilation", 0, 50),
        );
        let popular = or_empty(popular, "популярное", artist_id);
        let albums = or_empty(albums.map(|page| page.items), "альбомы", artist_id);
        let also = or_empty(also.map(|page| page.items), "релизы с участием", artist_id);
        Ok((artist, popular, albums, also))
    }

    /// Похожие исполнители (закрыто для новых приложений — тогда пусто).
    async fn related(&self, artist_id: &str) -> Vec<Artist> {
        let Ok(client) = self.auth.api().client_for(Operation::UnsupportedDevelopmentMode).await else {
            return Vec::new();
        };
        client.related_artists(artist_id).await.unwrap_or_else(|error| {
            tracing::debug!("похожие исполнители {artist_id}: {error:#}");
            Vec::new()
        })
    }

    /// Подписка на исполнителя (ошибка — «не подписан»).
    async fn followed(&self, uri: &str) -> bool {
        if uri.is_empty() {
            return false;
        }
        let Ok(client) = self.auth.api().client_for(Operation::UserData).await else { return false };
        client.contains(&[uri.to_owned()]).await.ok().and_then(|found| found.first().copied()).unwrap_or(false)
    }

    pub async fn search(&self, query: &str, kind: SearchKind) -> Result<SearchResults, ServiceError> {
        let query = query.trim();
        if query.is_empty() {
            return Ok(SearchResults::default());
        }
        let api = self.auth.api();
        // Сначала — шлюз клиентов Spotify через сессию (все разделы одним запросом, без квоты Web API)
        if let Some(session) = route::account_session(&api, &self.player) {
            match pathfinder::search(&api.http(), &session, query).await {
                Ok(results) => return Ok(self.searched(query, kind, only(kind, results))),
                Err(error) => tracing::debug!("поиск через сессию не удался: {error:#}; спрашиваю Web API"),
            }
        }
        let (catalog_types, playlists) = kind.api_types();
        let split = api.personal_ready();
        let mut types = catalog_types.clone();
        if playlists && !split {
            types.push("playlist");
        }
        let catalog = async {
            if types.is_empty() {
                return Ok(models::SearchResults::default());
            }
            let operation = if split { Operation::CatalogSearch } else { Operation::PlaylistSearch };
            api.client_for(operation).await?.search(query, &types).await
        };
        let playlist_half = async {
            if !(playlists && split) {
                return Ok(None);
            }
            let client = api.client_for(Operation::PlaylistSearch).await?;
            client.search(query, &["playlist"]).await.map(|results| results.playlists)
        };
        let (catalog, playlist_half) = tokio::join!(catalog, playlist_half);
        let results = match (catalog, playlist_half) {
            (Ok(mut results), Ok(Some(playlists))) => {
                results.playlists = Some(playlists);
                results
            }
            (Ok(results), Ok(None)) => results,
            (Ok(results), Err(error)) => {
                tracing::debug!("поиск плейлистов не удался: {error:#}");
                results
            }
            (Err(error), Ok(Some(playlists))) => {
                tracing::debug!("поиск по каталогу не удался: {error:#}");
                models::SearchResults { playlists: Some(playlists), ..Default::default() }
            }
            (Err(error), _) => return Err(self.fail(error)),
        };
        Ok(self.searched(query, kind, results))
    }

    /// Ответ поиска → результаты для QML; «лучший» — только во «Всём».
    fn searched(&self, query: &str, kind: SearchKind, results: models::SearchResults) -> SearchResults {
        let api = self.auth.api();
        if let Some(page) = &results.playlists {
            api.observe_playlists(page.items.iter());
        }
        let me = api.account();
        let mut mapped = search_results(query, &results, me.as_ref());
        if kind != SearchKind::All {
            mapped.best = None;
        }
        mapped
    }

    pub async fn show(&self, show_id: &str) -> Result<ShowPage, ServiceError> {
        let key = format!("show:{show_id}");
        if let Some(Cached::Show(page)) = self.cached(&key) {
            return Ok(page);
        }
        let client = self.client(Operation::Catalog).await?;
        let show = client.show(show_id).await.map_err(|e| self.fail(e))?;
        let first = match show.episodes.clone() {
            Some(page) if !page.items.is_empty() => page,
            _ => client.show_episodes(show_id, 0, EPISODE_PAGE).await.map_err(|e| self.fail(e))?,
        };
        let total = i64::from(show.total_episodes.unwrap_or(first.total));
        let page = ShowPage {
            info: map::show_item(&show),
            episodes: first.items.iter().map(|ep| map::episode_item(ep, Some(&show))).collect(),
            total,
        };
        self.store(key, Cached::Show(page.clone()));
        Ok(page)
    }

    /// Следующая страница выпусков (по 50).
    pub async fn show_episodes(&self, show_id: &str, offset: u32) -> Result<Vec<EpisodeItem>, ServiceError> {
        let client = self.client(Operation::Catalog).await?;
        let page = client.show_episodes(show_id, offset, EPISODE_PAGE).await.map_err(|e| self.fail(e))?;
        let show = match self.cached(&format!("show:{show_id}")) {
            Some(Cached::Show(page)) => Some(page.info),
            _ => None,
        };
        Ok(page
            .items
            .iter()
            .map(|ep| {
                let mut item = map::episode_item(ep, None);
                if let Some(show) = &show {
                    if item.show_id.is_empty() {
                        item.show_id = show.show_id.clone();
                    }
                    if item.show_name.is_empty() {
                        item.show_name = show.name.clone();
                    }
                    if item.cover.is_empty() {
                        item.cover = show.cover.clone();
                        item.cover_large = show.cover_large.clone();
                    }
                }
                item
            })
            .collect())
    }

    pub async fn episode(&self, episode_id: &str) -> Result<EpisodePage, ServiceError> {
        let key = format!("episode:{episode_id}");
        if let Some(Cached::Episode(page)) = self.cached(&key) {
            return Ok(page);
        }
        let client = self.client(Operation::Catalog).await?;
        let episode = client.episode(episode_id).await.map_err(|e| self.fail(e))?;
        let show = episode.show.clone().unwrap_or_default();
        let more = if show.id.is_empty() {
            Vec::new()
        } else {
            match client.show_episodes(&show.id, 0, 6).await {
                Ok(page) => page
                    .items
                    .iter()
                    .filter(|other| other.id != episode.id)
                    .take(3)
                    .map(|other| map::episode_item(other, Some(&show)))
                    .collect(),
                Err(error) => {
                    tracing::debug!("соседние выпуски: {error:#}");
                    Vec::new()
                }
            }
        };
        let page = EpisodePage { info: map::episode_item(&episode, Some(&show)), show: map::show_item(&show), more };
        known::remember([&page.info.to_track()]);
        self.store(key, Cached::Episode(page.clone()));
        Ok(page)
    }

    pub async fn track(&self, track_id: &str) -> Result<TrackItem, ServiceError> {
        let key = format!("track:{track_id}");
        if let Some(Cached::Track(item)) = self.cached(&key) {
            return Ok(item);
        }
        let client = self.client(Operation::Catalog).await?;
        let track = client.track(track_id).await.map_err(|e| self.fail(e))?;
        known::remember_recordings([&track]);
        let item = map::track_item(&track);
        known::remember([&item]);
        self.store(key, Cached::Track(item.clone()));
        Ok(item)
    }

    /// Плеер, с которым создан каталог.
    pub fn player(&self) -> &PlayerHandle {
        &self.player
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sf_api::models::Page;

    fn artist(name: &str) -> Artist {
        Artist { id: name.to_lowercase(), name: name.to_owned(), uri: format!("spotify:artist:{name}"), ..Default::default() }
    }

    fn page<T>(items: Vec<T>) -> Option<Page<T>> {
        let total = items.len() as u32;
        Some(Page { items, total, limit: 20, offset: 0, next: None })
    }

    #[test]
    fn search_kinds_split_catalog_and_playlists() {
        assert_eq!(SearchKind::from_name("shows"), SearchKind::Shows);
        assert_eq!(SearchKind::from_name("что-то"), SearchKind::All);
        assert_eq!(SearchKind::Playlists.api_types(), (Vec::new(), true));
        assert_eq!(SearchKind::Tracks.api_types(), (vec!["track"], false));
    }

    #[test]
    fn a_search_through_the_session_keeps_only_the_asked_shelves() {
        let all = models::SearchResults {
            tracks: page(vec![track("t1")]),
            artists: page(vec![artist("Muse")]),
            albums: page(vec![Album::default()]),
            playlists: page(vec![models::Playlist::default()]),
            shows: page(vec![models::Show::default()]),
            episodes: page(vec![models::Episode::default()]),
        };
        assert_eq!(only(SearchKind::All, all.clone()), all);
        let tracks = only(SearchKind::Tracks, all.clone());
        assert!(tracks.tracks.is_some());
        assert!(tracks.artists.is_none() && tracks.albums.is_none() && tracks.playlists.is_none());
        let playlists = only(SearchKind::Playlists, all);
        assert!(playlists.playlists.is_some() && playlists.tracks.is_none() && playlists.shows.is_none());
    }

    #[test]
    fn nothing_found_has_no_best_result() {
        assert!(best_result("x", &models::SearchResults::default()).is_none());
    }

    fn track(id: &str) -> Track {
        Track { id: Some(id.to_owned()), name: format!("Song {id}"), uri: format!("spotify:track:{id}"), ..Default::default() }
    }

    #[test]
    fn an_artist_named_like_the_query_beats_the_first_song() {
        let results = models::SearchResults {
            artists: page(vec![artist("Muse")]),
            tracks: page(vec![track("t1")]),
            ..Default::default()
        };
        assert_eq!(best_result("  muse ", &results).unwrap().kind, "artist");
        let best = best_result("uprising", &results).unwrap();
        assert_eq!(best.kind, "track");
        assert_eq!(best.item["trackId"], "t1");
    }

    #[test]
    fn an_artist_without_songs_is_the_best_result() {
        let results = models::SearchResults { artists: page(vec![artist("Muse")]), ..Default::default() };
        let best = best_result("whatever", &results).unwrap();
        assert_eq!(best.kind, "artist");
        assert_eq!(best.item["name"], "Muse");
    }

    #[test]
    fn albums_then_playlists_then_shows_fill_in() {
        let album = Album { id: "a1".into(), name: "Альбом".into(), uri: "spotify:album:a1".into(), ..Default::default() };
        let results = models::SearchResults { albums: page(vec![album]), ..Default::default() };
        assert_eq!(best_result("x", &results).unwrap().kind, "album");
        let show = models::Show { id: "s1".into(), name: "Шоу".into(), uri: "spotify:show:s1".into(), ..Default::default() };
        let results = models::SearchResults { shows: page(vec![show]), ..Default::default() };
        assert_eq!(best_result("x", &results).unwrap().kind, "show");
    }

    #[test]
    fn album_tracks_get_their_album_back_for_covers_and_totals() {
        let album = Album {
            id: "a1".into(),
            name: "Альбом".into(),
            uri: "spotify:album:a1".into(),
            images: vec![models::Image { url: "big".into(), width: Some(640), height: Some(640) }],
            ..Default::default()
        };
        let mut first = track("t1");
        first.duration_ms = 1000;
        let mut second = track("t2");
        second.duration_ms = 2000;
        let page = album_page(&album, vec![first, second]);
        assert_eq!(page.tracks.len(), 2);
        assert!(page.tracks.iter().all(|row| row.album_id == "a1" && row.album == "Альбом"));
        assert_eq!(page.info.duration_ms, 3000);
        assert_eq!(page.info.item.album_id, "a1");
    }

    #[test]
    fn search_results_count_and_map_every_shelf() {
        let results = models::SearchResults {
            tracks: page(vec![track("t1"), track("t2")]),
            artists: page(vec![artist("Muse")]),
            ..Default::default()
        };
        let mapped = search_results("muse", &results, None);
        assert_eq!(mapped.totals.tracks, 2);
        assert_eq!(mapped.totals.artists, 1);
        assert_eq!(mapped.tracks[1].track_id, "t2");
        assert_eq!(mapped.best.as_ref().unwrap().kind, "artist");
        assert!(!mapped.is_empty());
        assert_eq!(known::get("spotify:track:t2").unwrap().title, "Song t2");
    }

    #[test]
    fn an_artist_page_keeps_missing_shelves_empty() {
        let page = artist_page(&artist("Muse"), true, &[track("t1")], &[], &[], &[]);
        assert!(page.info.followed);
        assert_eq!(page.popular.len(), 1);
        assert!(page.similar.is_empty());
    }

    #[test]
    fn a_failed_section_leaves_the_artist_page_standing() {
        // 403 у популярного (режим разработки), 429 у альбомов: страница всё равно собирается
        let refused = ApiError::Status { status: 403, message: "Forbidden".into() };
        let popular: Vec<Track> = or_empty(Err(refused), "популярное", "muse");
        let albums: Vec<Album> = or_empty(Err(ApiError::RateLimited), "альбомы", "muse");
        let also = or_empty(Ok(vec![Album { id: "a1".into(), name: "Live".into(), ..Default::default() }]), "", "muse");
        let page = artist_page(&artist("Muse"), false, &popular, &albums, &also, &[]);
        assert_eq!(page.info.item.name, "Muse");
        assert!(page.popular.is_empty() && page.albums.is_empty());
        assert_eq!(page.also_albums.len(), 1);
    }

    #[tokio::test]
    async fn slow_extras_do_not_hold_the_page() {
        let grace = Duration::from_millis(20);
        // подписка/похожие висят (429 у общего приложения) — страница не ждёт их дольше grace
        let (page, extras) = with_extras(async { "page" }, std::future::pending::<bool>(), grace).await;
        assert_eq!((page, extras), ("page", None));
        // успевшие — попадают на страницу, даже если ответили позже основного чтения
        let late = async {
            tokio::time::sleep(Duration::from_millis(5)).await;
            true
        };
        assert_eq!(with_extras(async { "page" }, late, grace).await, ("page", Some(true)));
        // основное чтение дольше — его ждём целиком
        let slow = async {
            tokio::time::sleep(Duration::from_millis(40)).await;
            "page"
        };
        assert_eq!(with_extras(slow, async { true }, grace).await, ("page", Some(true)));
    }
}
