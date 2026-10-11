//! История прослушиваний (исполнитель «services-core»): локальная (librespot-воспроизведение Spotify не
//! записывает; засчёт после 30 с или половины трека, ≤ 500 записей, mf_platform::dirs::history_file()) +
//! /me/player/recently-played, слияние (data::journal::merged). Перенос spotifast/src/history.rs.
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, Weak};

use md3_model::{PlayContext, TrackItem, contexts};
use sf_api::Operation;
use sf_player::{PlayerEvent, PlayerHandle};
use tokio::runtime::Handle;
use tokio::sync::broadcast;

use crate::auth::{AuthEvent, AuthService};
use crate::data::journal::{self, Journal};
use crate::data::known;
use crate::lock;

/// Сколько записей Spotify держать в памяти.
const REMOTE_KEPT: usize = 200;

/// Одно прослушивание.
#[derive(Clone, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlayRecord {
    pub track: TrackItem,
    pub context: PlayContext,
    /// ISO-время
    pub played_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HistoryEvent {
    Changed,
}

#[derive(Default)]
struct State {
    journal: Journal,
    remote: Vec<PlayRecord>,
    /// поздний ответ Web API после выхода отбрасывается
    generation: u64,
}

pub struct HistoryService {
    rt: Handle,
    auth: Arc<AuthService>,
    player: PlayerHandle,
    events: broadcast::Sender<HistoryEvent>,
    path: PathBuf,
    state: Mutex<State>,
    me: Weak<HistoryService>,
}

/// Тип контекста Web API (Context.type) → PlayContext.kind.
fn context_kind(kind: &str) -> &str {
    match kind {
        "collection" => contexts::LIKED,
        "playlist" => contexts::PLAYLIST,
        "album" => contexts::ALBUM,
        "artist" => contexts::ARTIST,
        "show" => contexts::SHOW,
        other => other,
    }
}

impl HistoryService {
    /// Слушает PlayerEvent::TrackStarted/TrackEnded (только local = true пишется локально).
    pub fn new(rt: Handle, auth: Arc<AuthService>, player: PlayerHandle) -> Arc<Self> {
        Self::with_file(rt, auth, player, mf_platform::dirs::history_file())
    }

    /// То же с другим файлом истории (тесты).
    pub fn with_file(rt: Handle, auth: Arc<AuthService>, player: PlayerHandle, path: PathBuf) -> Arc<Self> {
        let journal = Journal::load(&path);
        let service = Arc::new_cyclic(|me| Self {
            rt,
            auth,
            player,
            events: broadcast::channel(64).0,
            path,
            state: Mutex::new(State { journal, ..Default::default() }),
            me: me.clone(),
        });
        service.spawn_listeners();
        service
    }

    fn spawn_listeners(&self) {
        let mut player = self.player.subscribe().events;
        let me = self.me.clone();
        self.rt.spawn(async move {
            loop {
                match player.recv().await {
                    Ok(PlayerEvent::TrackEnded(ended)) => {
                        let Some(service) = me.upgrade() else { return };
                        if ended.local {
                            service.note_played(ended.track, ended.context, ended.played);
                        }
                    }
                    Ok(_) | Err(broadcast::error::RecvError::Lagged(_)) => {}
                    Err(broadcast::error::RecvError::Closed) => return,
                }
            }
        });
        let mut auth = self.auth.subscribe();
        let me = self.me.clone();
        self.rt.spawn(async move {
            loop {
                match auth.recv().await {
                    Ok(AuthEvent::SignedIn(_)) => {
                        let Some(service) = me.upgrade() else { return };
                        service.refresh();
                    }
                    Ok(AuthEvent::SignedOut) => {
                        let Some(service) = me.upgrade() else { return };
                        {
                            let mut state = lock(&service.state);
                            state.generation += 1;
                            state.remote.clear();
                        }
                        let _ = service.events.send(HistoryEvent::Changed);
                    }
                    Ok(_) | Err(broadcast::error::RecvError::Lagged(_)) => {}
                    Err(broadcast::error::RecvError::Closed) => return,
                }
            }
        });
    }

    /// Трек доигран/пропущен на этом ПК: засчитать, если слушали достаточно (`played` — секунды).
    pub fn note_played(&self, track: TrackItem, context: PlayContext, played: f64) {
        if track.uri.is_empty() && track.track_id.is_empty() {
            return;
        }
        if played < journal::counts_after(track.duration_ms).as_secs_f64() {
            return;
        }
        let started = jiff::Timestamp::now()
            .checked_sub(jiff::SignedDuration::from_secs_f64(played.max(0.0)))
            .unwrap_or_else(|_| jiff::Timestamp::now());
        let record = PlayRecord { track, context, played_at: started.to_string() };
        lock(&self.state).journal.record(record);
        self.save_later();
        let _ = self.events.send(HistoryEvent::Changed);
    }

    fn save_later(&self) {
        let me = self.me.clone();
        self.rt.spawn_blocking(move || {
            if let Some(service) = me.upgrade() {
                service.flush();
            }
        });
    }

    /// Последние прослушивания (локальные + Web API), новые первыми.
    pub fn recent(&self, limit: usize) -> Vec<PlayRecord> {
        let state = lock(&self.state);
        let mut plays = journal::merged(state.journal.plays(), &state.remote);
        plays.truncate(limit);
        plays
    }

    /// Недавние уникальные контексты (для сидов радио и «Недавно прослушанное»).
    pub fn recent_contexts(&self, limit: usize) -> Vec<PlayContext> {
        let mut seen = HashSet::new();
        self.recent(usize::MAX)
            .into_iter()
            .filter_map(|play| {
                let uri = play.context.context_uri.clone().filter(|uri| !uri.is_empty())?;
                seen.insert(uri).then_some(play.context)
            })
            .take(limit)
            .collect()
    }

    /// Время последнего прослушивания по URI контекста (сортировка «Недавние» и LibraryEntry.played_at).
    pub fn context_times(&self) -> HashMap<String, String> {
        let mut times = HashMap::new();
        for play in self.recent(usize::MAX) {
            if let Some(uri) = play.context.context_uri.filter(|uri| !uri.is_empty()) {
                times.entry(uri).or_insert(play.played_at);
            }
        }
        times
    }

    /// Догрузить с Web API (до 50).
    pub fn refresh(&self) {
        let me = self.me.clone();
        let generation = lock(&self.state).generation;
        self.rt.spawn(async move {
            let Some(service) = me.upgrade() else { return };
            let api = service.auth.api();
            let result = async { api.client_for(Operation::UserData).await?.recently_played(50, None, None).await }.await;
            let page = match result {
                Ok(page) => page,
                Err(error) => {
                    service.auth.note_api_error(&error);
                    tracing::debug!("история Spotify не загрузилась: {error:#}");
                    return;
                }
            };
            known::remember_recordings(page.items.iter().map(|play| &play.track));
            let records: Vec<PlayRecord> = page
                .items
                .iter()
                .map(|play| PlayRecord {
                    track: sf_api::map::track_item(&play.track),
                    context: play
                        .context
                        .as_ref()
                        .filter(|context| !context.uri.is_empty())
                        .map(|context| PlayContext::with_uri(context_kind(&context.kind), context.uri.clone()))
                        .unwrap_or_else(|| PlayContext::new(contexts::TRACKS)),
                    played_at: play.played_at.clone().unwrap_or_default(),
                })
                .collect();
            known::remember(records.iter().map(|record| &record.track));
            let added = {
                let mut state = lock(&service.state);
                if state.generation != generation {
                    return;
                }
                let added = journal::absorb_remote(&mut state.remote, records);
                state.remote.truncate(REMOTE_KEPT);
                added
            };
            if added > 0 {
                let _ = service.events.send(HistoryEvent::Changed);
            }
        });
    }

    pub fn clear(&self) {
        {
            let mut state = lock(&self.state);
            state.journal.clear();
            state.remote.clear();
        }
        self.save_later();
        let _ = self.events.send(HistoryEvent::Changed);
    }

    pub fn subscribe(&self) -> broadcast::Receiver<HistoryEvent> {
        self.events.subscribe()
    }

    /// Сохранить на диск (выход).
    pub fn flush(&self) {
        lock(&self.state).journal.save(&self.path);
    }
}
