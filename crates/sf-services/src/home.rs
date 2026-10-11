//! Главная (исполнитель «services-extra»): полки как spotifast/src/ui/home.rs + App::load_home —
//! «Быстрый доступ» (Любимые + 5 плейлистов), «Недавно прослушанное» (история: Web API + локальная),
//! «Сделано для вас» (Discover-термины, только общий ключ), «Новинки» (ReleasesService), «Продолжить подкасты», «Топ-исполнители», «Топ-треки».
//! Не чаще раза в 10 мин без force; видимость — SettingKey::HomeHidden. Ответы старого обновления отбрасываются.
use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant};

use md3_model::{ArtistItem, EpisodeItem, HomeShelf, PlaylistItem, ShowItem, TrackItem, contexts};
use sf_api::Operation;
use tokio::runtime::Handle;
use tokio::sync::{broadcast, watch};
use mf_platform::{SettingKey, SettingsStore};

use crate::ServiceError;
use crate::auth::{AuthEvent, AuthService};
use crate::extra::shelves::{self, Play};
use crate::history::{HistoryEvent, HistoryService};
use crate::library::{LibraryEvent, LibraryService};
use crate::releases::ReleasesService;
use crate::lock;

/// Не чаще раза в 10 минут без force.
pub const REFRESH_EVERY: Duration = Duration::from_secs(600);
const HISTORY_FOR_HOME: usize = 50;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct HomeSnapshot {
    pub loading: bool,
    pub shelves: Arc<Vec<HomeShelf>>,
    pub error_text: String,
}

/// Ответы Web API последнего обновления.
#[derive(Default)]
struct HomeData {
    loaded_at: Option<Instant>,
    made_for_you: Vec<PlaylistItem>,
    podcasts: Vec<EpisodeItem>,
    top_artists: Vec<ArtistItem>,
    top_tracks: Vec<TrackItem>,
}

pub struct HomeService {
    rt: Handle,
    auth: Arc<AuthService>,
    library: Arc<LibraryService>,
    history: Arc<HistoryService>,
    releases: Arc<ReleasesService>,
    settings: Arc<SettingsStore>,
    snapshot: watch::Sender<HomeSnapshot>,
    data: Mutex<HomeData>,
    generation: AtomicU64,
    me: Weak<HomeService>,
}

impl HomeService {
    pub fn new(
        rt: Handle,
        auth: Arc<AuthService>,
        library: Arc<LibraryService>,
        history: Arc<HistoryService>,
        releases: Arc<ReleasesService>,
        settings: Arc<SettingsStore>,
    ) -> Arc<Self> {
        let service = Arc::new_cyclic(|me| Self {
            rt: rt.clone(),
            auth,
            library,
            history,
            releases,
            settings,
            snapshot: watch::channel(HomeSnapshot::default()).0,
            data: Mutex::new(HomeData::default()),
            generation: AtomicU64::new(0),
            me: me.clone(),
        });
        rt.spawn(listen(Arc::downgrade(&service)));
        service
    }

    /// Обновить полки (force — без 10-минутного ограничения).
    pub fn refresh(&self, force: bool) {
        if !self.auth.is_signed_in() {
            self.snapshot.send_replace(HomeSnapshot {
                loading: false,
                shelves: Arc::new(Vec::new()),
                error_text: ServiceError::NotSignedIn.to_string(),
            });
            return;
        }
        {
            let mut data = lock(&self.data);
            let fresh = data.loaded_at.is_some_and(|at| at.elapsed() < REFRESH_EVERY);
            if fresh && !force {
                drop(data);
                self.publish();
                return;
            }
            data.loaded_at = Some(Instant::now());
        }
        let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        self.snapshot.send_modify(|s| {
            s.loading = true;
            s.error_text.clear();
        });
        self.publish();
        self.history.refresh();
        let Some(me) = self.me.upgrade() else { return };
        self.rt.spawn(async move { me.load(generation).await });
    }

    pub fn snapshot(&self) -> HomeSnapshot {
        self.snapshot.borrow().clone()
    }

    pub fn watch(&self) -> watch::Receiver<HomeSnapshot> {
        self.snapshot.subscribe()
    }

    // --- внутреннее ----------------------------------------------------------------------------

    fn current(&self, generation: u64) -> bool {
        self.generation.load(Ordering::SeqCst) == generation
    }

    /// Полки по свежим данным: Web API последнего обновления + библиотека + история.
    fn publish(&self) {
        if !self.auth.is_signed_in() {
            return;
        }
        let hidden = shelves::hidden_keys(&self.settings.get_str(SettingKey::HomeHidden));
        let liked_uri = self.auth.account_id().map(|a| contexts::liked_uri(a.as_str())).unwrap_or_default();
        let playlists = self.library.playlists();
        let fresh = self.releases.snapshot();
        let built: Vec<HomeShelf> = {
            let data = lock(&self.data);
            shelves::ORDER
                .iter()
                .filter(|key| !hidden.contains(**key))
                .map(|key| match *key {
                    shelves::QUICK => {
                        let liked = self.library.liked().len() as i64;
                        shelves::shelf(key, &shelves::quick_tiles(&liked_uri, liked, &playlists))
                    }
                    shelves::RECENT => shelves::shelf(key, &shelves::recent_tiles(self.plays(), &playlists)),
                    shelves::MADE_FOR_YOU => {
                        let tiles: Vec<_> = data.made_for_you.iter().map(shelves::playlist_entry).collect();
                        shelves::shelf(key, &tiles)
                    }
                    shelves::NEW_RELEASES => {
                        shelves::shelf(key, &shelves::new_release_tiles(fresh.radar.as_ref(), &fresh.releases))
                    }
                    shelves::PODCASTS => shelves::shelf(key, &data.podcasts),
                    shelves::TOP_ARTISTS => shelves::shelf(key, &data.top_artists),
                    _ => shelves::shelf(key, &data.top_tracks),
                })
                .filter(|shelf| !shelf.items.is_empty())
                .collect()
        };
        self.snapshot.send_if_modified(|s| {
            if *s.shelves == built {
                return false;
            }
            s.shelves = Arc::new(built);
            true
        });
    }

    fn plays(&self) -> Vec<Play> {
        self.history
            .recent(HISTORY_FOR_HOME)
            .into_iter()
            .map(|r| Play {
                context: (!r.context.kind.is_empty() || r.context.context_uri.is_some()).then_some(r.context),
                track: r.track,
                played_at: r.played_at,
            })
            .collect()
    }

    fn store(&self, generation: u64, apply: impl FnOnce(&mut HomeData)) {
        if !self.current(generation) {
            return;
        }
        apply(&mut lock(&self.data));
        self.publish();
    }

    async fn load(self: Arc<Self>, generation: u64) {
        let api = self.auth.api();
        let me = self.auth.account_id();

        let top_artists = async {
            let client = api.client_for(Operation::UserData).await?;
            let page = client.top_artists("medium_term", shelves::TOP_LIMIT).await?;
            let items: Vec<ArtistItem> = page.items.iter().map(sf_api::map::artist_item).collect();
            self.store(generation, |d| d.top_artists = items);
            Ok::<_, sf_api::ApiError>(())
        };
        let top_tracks = async {
            let client = api.client_for(Operation::UserData).await?;
            let page = client.top_tracks("short_term", shelves::TOP_LIMIT, 0).await?;
            let items: Vec<TrackItem> = page.items.iter().map(sf_api::map::track_item).collect();
            self.store(generation, |d| d.top_tracks = items);
            Ok::<_, sf_api::ApiError>(())
        };
        // «Сделано для вас» — только общий ключ: личное приложение плейлисты Spotify не видит
        let made_for_you = async {
            let client = api.client_for(Operation::PlaylistSearch).await?;
            let mut all = Vec::new();
            let mut seen = HashSet::new();
            for term in shelves::DISCOVER_TERMS {
                match client.search(term, &["playlist"]).await {
                    Ok(results) => {
                        let found = results
                            .playlists
                            .map(|p| p.items)
                            .unwrap_or_default()
                            .iter()
                            .map(|p| sf_api::map::playlist_item(p, me.as_ref()))
                            .collect();
                        all.extend(shelves::made_for_you(term, found).into_iter().filter(|p| seen.insert(p.playlist_id.clone())));
                    }
                    Err(e) => tracing::debug!("главная: «{term}» не найден: {e}"),
                }
            }
            self.store(generation, |d| d.made_for_you = all);
            Ok::<_, sf_api::ApiError>(())
        };
        let podcasts = async {
            let mut shows: Vec<ShowItem> = self.library.shows();
            if shows.is_empty() {
                let client = api.client_for(Operation::UserData).await?;
                let page = client.saved_shows(0, 50).await?;
                shows = page.items.iter().map(|s| sf_api::map::show_item(&s.show)).collect();
            }
            shows.retain(|s| !s.show_id.is_empty());
            shows.truncate(shelves::HOME_PODCAST_SHOWS);
            if shows.is_empty() {
                self.store(generation, |d| d.podcasts.clear());
                return Ok(());
            }
            let client = api.client_for(Operation::Catalog).await?;
            let mut podcasts = Vec::new();
            for show in shows {
                match client.show_episodes(&show.show_id, 0, shelves::EPISODES_PER_SHOW).await {
                    Ok(page) => {
                        let episodes = page.items.iter().map(|e| sf_api::map::episode_item(e, None)).collect();
                        podcasts.push((show, episodes));
                    }
                    // полка необязательная: квота/429 — без этого шоу
                    Err(e) => tracing::debug!("главная: выпуски {}: {e}", show.show_id),
                }
            }
            let today = jiff::Zoned::now().date();
            let shelf = shelves::podcast_episodes(&podcasts, today);
            self.store(generation, |d| d.podcasts = shelf);
            Ok::<_, sf_api::ApiError>(())
        };
        let (a, b, c, d) = tokio::join!(top_artists, top_tracks, made_for_you, podcasts);
        let errors: Vec<String> =
            [a, b, c, d].into_iter().filter_map(Result::err).map(|e| ServiceError::from(e).to_string()).collect();
        if !self.current(generation) {
            return;
        }
        let empty = self.snapshot.borrow().shelves.is_empty();
        // полки — дополнение: ошибка видна, только если не вышло ничего
        let error = (errors.len() == 4 && empty).then(|| errors[0].clone());
        self.snapshot.send_modify(|s| {
            s.loading = false;
            s.error_text = error.unwrap_or_default();
        });
    }

    fn clear(&self) {
        self.generation.fetch_add(1, Ordering::SeqCst);
        *lock(&self.data) = HomeData::default();
        self.snapshot.send_replace(HomeSnapshot::default());
    }
}

/// Вход/выход, библиотека, история и скрытие полок → полки.
async fn listen(weak: Weak<HomeService>) {
    let Some(me) = weak.upgrade() else { return };
    let mut auth = me.auth.subscribe();
    let mut library = me.library.subscribe();
    let mut history = me.history.subscribe();
    let mut settings = me.settings.subscribe();
    let mut releases = me.releases.watch();
    drop(me);
    loop {
        tokio::select! {
            event = auth.recv() => {
                let Some(me) = weak.upgrade() else { break };
                match event {
                    Ok(AuthEvent::SignedIn(_)) => me.refresh(true),
                    Ok(AuthEvent::SignedOut) => me.clear(),
                    Ok(_) => {}
                    Err(broadcast::error::RecvError::Lagged(_)) => me.publish(),
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            },
            event = library.recv() => match event {
                Ok(LibraryEvent::Playlists(_) | LibraryEvent::Liked(_) | LibraryEvent::Shows(_) | LibraryEvent::PinsChanged)
                | Err(broadcast::error::RecvError::Lagged(_)) => {
                    let Some(me) = weak.upgrade() else { break };
                    me.publish();
                }
                Ok(_) => {}
                Err(broadcast::error::RecvError::Closed) => break,
            },
            event = history.recv() => match event {
                Ok(HistoryEvent::Changed) | Err(broadcast::error::RecvError::Lagged(_)) => {
                    let Some(me) = weak.upgrade() else { break };
                    me.publish();
                }
                Err(broadcast::error::RecvError::Closed) => break,
            },
            changed = releases.changed() => {
                if changed.is_err() {
                    break;
                }
                let Some(me) = weak.upgrade() else { break };
                me.publish();
            },
            key = settings.recv() => match key {
                Ok(SettingKey::HomeHidden) | Err(broadcast::error::RecvError::Lagged(_)) => {
                    let Some(me) = weak.upgrade() else { break };
                    me.publish();
                }
                Ok(_) => {}
                Err(broadcast::error::RecvError::Closed) => break,
            },
        }
    }
}
