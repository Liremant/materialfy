//! Коллекция аккаунта через сессию librespot (spclient /collection/v2/*), без квоты Web API.
//!
//! Наборы (set) проверены на живом аккаунте: «collection» — любимые треки и сохранённые альбомы вместе,
//! «artist» — подписки на исполнителей, «show» — сохранённые подкасты, «listenlater» — «Ваши выпуски»
//! (набора «album» нет: 403). Сервис отдаёт набор по URI, а не по времени добавления — порядок
//! «новые сверху» наводится здесь. Протокол — collection2v2 (librespot его не собирает, поля пишутся
//! и читаются вручную):
//!   PageRequest { username = 1; set = 2; pagination_token = 3; limit = 4 }
//!   PageResponse { repeated CollectionItem items = 1; next_page_token = 2; sync_token = 3 }
//!   CollectionItem { uri = 1; added_at = 2 (секунды); is_removed = 3 }
//!   WriteRequest { username = 1; set = 2; repeated CollectionItem items = 3; client_update_id = 4 }
//!   /contains: { username = 1; set = 2; repeated CollectionItem items = 3 } → { repeated bool found = 1 }
//!     (строки в поле 3 вместо сообщений — 400).
//! Подробности строк — пачками extended-metadata (TRACK_V4, ALBUM_V4, ARTIST_V4).
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures::{StreamExt as _, TryStreamExt as _};
use librespot_core::{Session, SpotifyUri};
use librespot_metadata::artist::Artist as SessionArtist;
use librespot_protocol::extended_metadata::{BatchedEntityRequest, EntityRequest, ExtensionQuery};
use librespot_protocol::extension_kind::ExtensionKind;
use protobuf::{EnumOrUnknown, Message as _};
use reqwest::header::{ACCEPT, CONTENT_TYPE, HeaderMap, HeaderValue};
use sf_api::models::{Album, Artist, PlayableItem, Track};

use super::new_releases::{self, ReleaseRef};
use super::session_reads::{self, Failure};

/// Любимые треки и сохранённые альбомы.
pub const SET_COLLECTION: &str = "collection";
/// Подписки на исполнителей.
pub const SET_ARTIST: &str = "artist";
/// Сохранённые подкасты.
pub const SET_SHOW: &str = "show";
/// «Ваши выпуски» (сохранённые выпуски подкастов).
pub const SET_LISTEN_LATER: &str = "listenlater";

/// Тип тела коллекции: на application/x-protobuf сервис отвечает 400.
const COLLECTION_TYPE: &str = "application/vnd.collection-v2.spotify.proto";
/// Строк в одной странице чтения (сервис сам режет больше — тогда просто будет больше страниц).
const PAGE_LIMIT: i32 = 500;
/// Потолок страниц одного набора.
const MAX_PAGES: usize = 200;
/// URI в одном запросе /contains и /write.
const URI_CHUNK: usize = 100;
/// Сущностей в одном пакетном запросе extended-metadata.
const METADATA_BATCH: usize = 50;
/// Пакетов метаданных в полёте одновременно.
const METADATA_PARALLEL: usize = 4;
/// Сколько ждать одну страницу набора или один пакет метаданных (весь набор большой библиотеки —
/// десятки страниц, поэтому срок — на страницу, а не на чтение целиком).
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
/// Пауза перед повтором страницы или пакета, не ответивших с первого раза.
const RETRY_PAUSE: Duration = Duration::from_millis(600);
/// Сколько живёт прочитанный набор: «Любимые треки» и альбомы при входе читают один и тот же
/// «collection» — второй берёт ответ первого. Запись в набор его сбрасывает.
const SET_CACHE_TTL: Duration = Duration::from_secs(20);

/// Строка набора: URI и время добавления (секунды с эпохи; 0 — неизвестно).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CollectionItem {
    pub uri: String,
    pub added_at: i64,
}

impl CollectionItem {
    /// Время добавления, как его пишет Web API (added_at); None — неизвестно.
    pub fn added_at_iso(&self) -> Option<String> {
        (self.added_at > 0)
            .then(|| jiff::Timestamp::from_second(self.added_at).ok())
            .flatten()
            .map(|time| time.to_string())
    }
}

/// Страница набора: живые строки (снятые пропущены) и токен следующей ("" — последняя).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CollectionPage {
    pub items: Vec<CollectionItem>,
    pub next_token: String,
    pub sync_token: String,
    /// строк в ответе вместе со снятыми: страница из одних снятых — не конец набора
    pub rows: usize,
}

/// Набор, в котором Spotify держит URI: трек и альбом — «collection», исполнитель — «artist»,
/// подкаст — «show», выпуск — «listenlater». Плейлисты живут в rootlist, не здесь.
pub fn set_for(uri: &str) -> Option<&'static str> {
    match uri.split(':').nth(1)? {
        "track" | "album" => Some(SET_COLLECTION),
        "artist" => Some(SET_ARTIST),
        "show" => Some(SET_SHOW),
        "episode" => Some(SET_LISTEN_LATER),
        _ => None,
    }
}

// --- protobuf вручную ------------------------------------------------------------------------------

fn put_varint(buf: &mut Vec<u8>, mut value: u64) {
    while value >= 0x80 {
        buf.push((value as u8) | 0x80);
        value >>= 7;
    }
    buf.push(value as u8);
}

fn put_bytes(buf: &mut Vec<u8>, field: u32, bytes: &[u8]) {
    if bytes.is_empty() {
        return;
    }
    put_varint(buf, u64::from(field << 3 | 2));
    put_varint(buf, bytes.len() as u64);
    buf.extend_from_slice(bytes);
}

fn put_number(buf: &mut Vec<u8>, field: u32, value: u64) {
    if value == 0 {
        return;
    }
    put_varint(buf, u64::from(field << 3));
    put_varint(buf, value);
}

/// CollectionItem { uri = 1; added_at = 2; is_removed = 3 }.
fn item_message(uri: &str, added_at: i64, removed: bool) -> Vec<u8> {
    let mut buf = Vec::new();
    put_bytes(&mut buf, 1, uri.as_bytes());
    put_number(&mut buf, 2, u64::try_from(added_at).unwrap_or_default());
    put_number(&mut buf, 3, u64::from(removed));
    buf
}

/// PageRequest.
pub fn page_request(username: &str, set: &str, token: &str, limit: i32) -> Vec<u8> {
    let mut buf = Vec::new();
    put_bytes(&mut buf, 1, username.as_bytes());
    put_bytes(&mut buf, 2, set.as_bytes());
    put_bytes(&mut buf, 3, token.as_bytes());
    put_number(&mut buf, 4, u64::try_from(limit).unwrap_or_default());
    buf
}

/// WriteRequest: добавить (с временем `now`) или снять каждый из `uris`.
pub fn write_request(
    username: &str,
    set: &str,
    uris: &[String],
    add: bool,
    now: i64,
    update_id: &str,
) -> Vec<u8> {
    let mut buf = Vec::new();
    put_bytes(&mut buf, 1, username.as_bytes());
    put_bytes(&mut buf, 2, set.as_bytes());
    for uri in uris {
        let item = if add {
            item_message(uri, now, false)
        } else {
            item_message(uri, 0, true)
        };
        put_bytes(&mut buf, 3, &item);
    }
    put_bytes(&mut buf, 4, update_id.as_bytes());
    buf
}

/// Запрос /contains: строки — сообщениями CollectionItem в поле 3.
pub fn contains_request(username: &str, set: &str, uris: &[String]) -> Vec<u8> {
    let mut buf = Vec::new();
    put_bytes(&mut buf, 1, username.as_bytes());
    put_bytes(&mut buf, 2, set.as_bytes());
    for uri in uris {
        put_bytes(&mut buf, 3, &item_message(uri, 0, false));
    }
    buf
}

enum Value<'a> {
    Varint(u64),
    Bytes(&'a [u8]),
}

struct Reader<'a> {
    bytes: &'a [u8],
}

impl<'a> Reader<'a> {
    fn varint(&mut self) -> Option<u64> {
        let mut value = 0u64;
        for shift in (0..64).step_by(7) {
            let (&byte, rest) = self.bytes.split_first()?;
            self.bytes = rest;
            value |= u64::from(byte & 0x7f) << shift;
            if byte & 0x80 == 0 {
                return Some(value);
            }
        }
        None
    }

    fn take(&mut self, len: usize) -> Option<&'a [u8]> {
        if self.bytes.len() < len {
            return None;
        }
        let (head, rest) = self.bytes.split_at(len);
        self.bytes = rest;
        Some(head)
    }

    /// Следующее поле; None — конец (или битые данные: дальше не читаем).
    fn field(&mut self) -> Option<(u32, Value<'a>)> {
        if self.bytes.is_empty() {
            return None;
        }
        let tag = self.varint()?;
        let number = u32::try_from(tag >> 3).ok()?;
        let value = match tag & 7 {
            0 => Value::Varint(self.varint()?),
            1 => Value::Bytes(self.take(8)?),
            2 => {
                let len = usize::try_from(self.varint()?).ok()?;
                Value::Bytes(self.take(len)?)
            }
            5 => Value::Bytes(self.take(4)?),
            _ => return None,
        };
        Some((number, value))
    }
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// PageResponse → страница (снятые строки пропускаются).
pub fn parse_page(bytes: &[u8]) -> CollectionPage {
    let mut page = CollectionPage::default();
    let mut reader = Reader { bytes };
    while let Some((number, value)) = reader.field() {
        match (number, value) {
            (1, Value::Bytes(item)) => {
                page.rows += 1;
                let (mut uri, mut added_at, mut removed) = (String::new(), 0, false);
                let mut fields = Reader { bytes: item };
                while let Some((number, value)) = fields.field() {
                    match (number, value) {
                        (1, Value::Bytes(bytes)) => uri = text(bytes),
                        // int32 со знаком: отрицательное время — «неизвестно»
                        (2, Value::Varint(value)) => added_at = (value as i64).max(0),
                        (3, Value::Varint(flag)) => removed = flag != 0,
                        _ => {}
                    }
                }
                if !uri.is_empty() && !removed {
                    page.items.push(CollectionItem { uri, added_at });
                }
            }
            (2, Value::Bytes(bytes)) => page.next_token = text(bytes),
            (3, Value::Bytes(bytes)) => page.sync_token = text(bytes),
            _ => {}
        }
    }
    page
}

/// Ответ /contains: repeated bool found = 1 (упакованный или по одному).
pub fn parse_contains(bytes: &[u8]) -> Vec<bool> {
    let mut found = Vec::new();
    let mut reader = Reader { bytes };
    while let Some((number, value)) = reader.field() {
        match (number, value) {
            (1, Value::Varint(flag)) => found.push(flag != 0),
            (1, Value::Bytes(packed)) => {
                let mut flags = Reader { bytes: packed };
                while let Some(flag) = flags.varint() {
                    found.push(flag != 0);
                }
            }
            _ => {}
        }
    }
    found
}

/// Новые сверху (как отдаёт Web API); при равном времени — по URI, чтобы порядок не прыгал.
pub fn newest_first(items: &mut [CollectionItem]) {
    items.sort_by(|a, b| b.added_at.cmp(&a.added_at).then_with(|| a.uri.cmp(&b.uri)));
}

// --- запросы ---------------------------------------------------------------------------------------

async fn post(session: &Session, endpoint: &str, body: &[u8]) -> anyhow::Result<Vec<u8>> {
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static(COLLECTION_TYPE));
    headers.insert(ACCEPT, HeaderValue::from_static(COLLECTION_TYPE));
    Ok(session
        .spclient()
        .request(&reqwest::Method::POST, endpoint, Some(headers), Some(body))
        .await?
        .to_vec())
}

/// Одна страница набора `set` аккаунта сессии; `token` — "" для первой.
pub async fn collection_page(
    session: &Session,
    set: &str,
    token: &str,
    limit: i32,
) -> anyhow::Result<CollectionPage> {
    let body = page_request(&session.username(), set, token, limit);
    Ok(parse_page(&post(session, "/collection/v2/paging", &body).await?))
}

/// Все страницы набора по токенам: `fetch(token)` — страница с токеном ("" — первая). Конец — пустой
/// токен, пустая страница или токен, который уже был (сервис зациклился); строка, встреченная
/// дважды (набор менялся между страницами), остаётся одна. Итог — новые сверху.
pub async fn collect_pages<F, Fut>(max_pages: usize, mut fetch: F) -> anyhow::Result<Vec<CollectionItem>>
where
    F: FnMut(String) -> Fut,
    Fut: Future<Output = anyhow::Result<CollectionPage>>,
{
    let mut items = Vec::new();
    let mut seen_uris = HashSet::new();
    let mut seen_tokens = HashSet::new();
    let mut token = String::new();
    for _ in 0..max_pages {
        let page = fetch(token.clone()).await?;
        items.extend(page.items.into_iter().filter(|item| seen_uris.insert(item.uri.clone())));
        if page.rows == 0 || page.next_token.is_empty() || !seen_tokens.insert(page.next_token.clone()) {
            break;
        }
        token = page.next_token;
    }
    newest_first(&mut items);
    Ok(items)
}

/// `call` не дольше REQUEST_TIMEOUT; не вышло — ещё раз после паузы.
async fn twice<T, Fut>(what: &str, mut call: impl FnMut() -> Fut) -> anyhow::Result<T>
where
    Fut: Future<Output = anyhow::Result<T>>,
{
    let first = match tokio::time::timeout(REQUEST_TIMEOUT, call()).await {
        Ok(Ok(value)) => return Ok(value),
        Ok(Err(error)) => error,
        Err(_) => anyhow::anyhow!("{what} timed out"),
    };
    tracing::debug!("{what}: {first:#}; asking once more");
    tokio::time::sleep(RETRY_PAUSE).await;
    match tokio::time::timeout(REQUEST_TIMEOUT, call()).await {
        Ok(result) => result,
        Err(_) => Err(anyhow::anyhow!("{what} timed out")),
    }
}

/// Весь набор `set` страницами по `limit` строк, новые сверху — без общего кэша.
pub async fn collection_all_paged(session: &Session, set: &str, limit: i32) -> anyhow::Result<Vec<CollectionItem>> {
    collect_pages(MAX_PAGES, |token| async move {
        twice("collection page", || collection_page(session, set, &token, limit)).await
    })
    .await
}

type SetSlot = Arc<tokio::sync::Mutex<Option<(Instant, Arc<Vec<CollectionItem>>)>>>;

/// Прочитанные наборы: (аккаунт, набор) → когда и что прочитано.
fn set_cache() -> &'static Mutex<HashMap<(String, String), SetSlot>> {
    static CACHE: std::sync::OnceLock<Mutex<HashMap<(String, String), SetSlot>>> = std::sync::OnceLock::new();
    CACHE.get_or_init(Default::default)
}

fn set_slot(username: &str, set: &str) -> SetSlot {
    let mut cache = set_cache().lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    cache.entry((username.to_owned(), set.to_owned())).or_default().clone()
}

/// Забыть прочитанный набор (после записи в него).
fn forget_set(username: &str, set: &str) {
    let mut cache = set_cache().lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    cache.remove(&(username.to_owned(), set.to_owned()));
}

/// Весь набор `set`, новые сверху. Одновременные чтения одного набора ждут одно; ответ живёт
/// SET_CACHE_TTL (запись в набор его сбрасывает).
pub async fn collection_all(session: &Session, set: &str) -> anyhow::Result<Vec<CollectionItem>> {
    let username = session.username();
    let slot = set_slot(&username, set);
    let mut cached = slot.lock().await;
    if let Some((at, items)) = cached.as_ref()
        && at.elapsed() < SET_CACHE_TTL
    {
        return Ok(items.as_ref().clone());
    }
    let items = Arc::new(collection_all_paged(session, set, PAGE_LIMIT).await?);
    *cached = Some((Instant::now(), Arc::clone(&items)));
    Ok(items.as_ref().clone())
}

/// Добавить (`add`) или снять `uris` в наборе `set` — как это делают клиенты Spotify.
pub async fn collection_write(
    session: &Session,
    set: &str,
    uris: &[String],
    add: bool,
) -> anyhow::Result<()> {
    let username = session.username();
    forget_set(&username, set);
    let now = jiff::Timestamp::now().as_second();
    for chunk in uris.chunks(URI_CHUNK) {
        let update_id = format!("{:032x}", rand::random::<u128>());
        let body = write_request(&username, set, chunk, add, now, &update_id);
        post(session, "/collection/v2/write", &body).await?;
    }
    Ok(())
}

/// Есть ли каждый из `uris` в наборе `set` — в том же порядке.
pub async fn collection_contains(
    session: &Session,
    set: &str,
    uris: &[String],
) -> anyhow::Result<Vec<bool>> {
    let username = session.username();
    let mut found = Vec::with_capacity(uris.len());
    for chunk in uris.chunks(URI_CHUNK) {
        let body = contains_request(&username, set, chunk);
        let flags = parse_contains(&post(session, "/collection/v2/contains", &body).await?);
        anyhow::ensure!(
            flags.len() == chunk.len(),
            "the collection answered for {} URIs out of {}",
            flags.len(),
            chunk.len()
        );
        found.extend(flags);
    }
    Ok(found)
}

/// URI по наборам, с их местами в исходном списке; URI без набора (плейлист…) — отдельно.
fn by_set(uris: &[String]) -> (Vec<(&'static str, Vec<usize>)>, Vec<usize>) {
    let mut groups: Vec<(&'static str, Vec<usize>)> = Vec::new();
    let mut unknown = Vec::new();
    for (index, uri) in uris.iter().enumerate() {
        match set_for(uri) {
            Some(set) => match groups.iter_mut().find(|(name, _)| *name == set) {
                Some((_, places)) => places.push(index),
                None => groups.push((set, vec![index])),
            },
            None => unknown.push(index),
        }
    }
    (groups, unknown)
}

/// Сохранить/снять URI разных видов: каждый — в своём наборе. URI без набора — ошибка.
pub async fn write(session: &Session, uris: &[String], add: bool) -> anyhow::Result<()> {
    let (groups, unknown) = by_set(uris);
    if let Some(&index) = unknown.first() {
        anyhow::bail!("{} isn't stored in the collection", uris[index]);
    }
    for (set, places) in groups {
        let chunk: Vec<String> = places.iter().map(|&index| uris[index].clone()).collect();
        collection_write(session, set, &chunk, add).await?;
    }
    Ok(())
}

/// Как /me/library/contains: для каждого URI — сохранён ли он (каждый вид — в своём наборе).
/// URI без набора — ошибка (плейлисты знает rootlist).
pub async fn contains(session: &Session, uris: &[String]) -> anyhow::Result<Vec<bool>> {
    let (groups, unknown) = by_set(uris);
    if let Some(&index) = unknown.first() {
        anyhow::bail!("{} isn't stored in the collection", uris[index]);
    }
    let mut found = vec![false; uris.len()];
    for (set, places) in groups {
        let chunk: Vec<String> = places.iter().map(|&index| uris[index].clone()).collect();
        for (place, flag) in places.iter().zip(collection_contains(session, set, &chunk).await?) {
            found[*place] = flag;
        }
    }
    Ok(found)
}

// --- подробности строк -----------------------------------------------------------------------------

/// Треки по URI одним пакетом (≤ ~100 за раз разумно). Трека, которого Spotify больше не отдаёт
/// (404, 451) или о котором ответил невнятно (другой код, нечитаемые байты, нет ответа), в ответе
/// нет: длинная коллекция не должна вставать из-за одной странной строки. Не ответил пакет целиком
/// (сеть, ошибка провайдера) — ещё раз, затем Failure::Retry.
pub async fn tracks(session: &Session, uris: &[String]) -> Result<HashMap<String, Track>, Failure> {
    let parsed: Vec<SpotifyUri> = uris
        .iter()
        .filter_map(|uri| SpotifyUri::from_uri(uri).ok())
        .filter(|uri| matches!(uri, SpotifyUri::Track { .. }))
        .collect();
    let lenient = || async {
        session_reads::metadata_lenient(session, parsed.iter()).await.map_err(|failure| match failure {
            Failure::Retry(error) => error,
            Failure::Definitive(error) => anyhow::anyhow!("{error}"),
        })
    };
    let (answers, problems) = twice("track metadata", lenient).await.map_err(Failure::Retry)?;
    for problem in &problems {
        tracing::debug!("collection row skipped: {problem}");
    }
    Ok(answers
        .into_iter()
        .filter_map(|(uri, item)| match item {
            PlayableItem::Track(track) => Some((uri, track)),
            PlayableItem::Episode(_) => None,
        })
        .collect())
}

/// Альбомы по URI (пачками ALBUM_V4, с датой выхода и числом треков). Альбома, которого Spotify
/// не отдаёт, в ответе нет.
pub async fn albums(session: &Session, uris: &[String]) -> anyhow::Result<HashMap<String, Album>> {
    let refs: Vec<ReleaseRef> = uris
        .iter()
        .filter_map(|uri| uri.strip_prefix("spotify:album:"))
        .map(|id| ReleaseRef {
            album_id: id.to_owned(),
            group: "album",
        })
        .collect();
    // futures собраны заранее: замыкание внутри потока не проходит проверку Send у tokio::spawn
    let requests: Vec<_> = refs
        .chunks(METADATA_BATCH)
        .map(|chunk| twice("album metadata", move || new_releases::release_details(session, chunk)))
        .collect();
    let batches: Vec<Vec<Album>> = futures::stream::iter(requests)
        .buffered(METADATA_PARALLEL)
        .try_collect()
        .await?;
    Ok(batches
        .into_iter()
        .flatten()
        .map(|album| (album.uri.clone(), album))
        .collect())
}

/// Исполнители по URI (пачками ARTIST_V4: имя, фото, популярность). Исполнителя, которого Spotify
/// не отдаёт, в ответе нет.
pub async fn artists(session: &Session, uris: &[String]) -> anyhow::Result<HashMap<String, Artist>> {
    let uris: Vec<&String> = uris
        .iter()
        .filter(|uri| uri.starts_with("spotify:artist:"))
        .collect();
    let requests: Vec<_> = uris
        .chunks(METADATA_BATCH)
        .map(|chunk| twice("artist metadata", move || artist_batch(session, chunk)))
        .collect();
    let batches: Vec<Vec<Artist>> = futures::stream::iter(requests)
        .buffered(METADATA_PARALLEL)
        .try_collect()
        .await?;
    Ok(batches
        .into_iter()
        .flatten()
        .map(|artist| (artist.uri.clone(), artist))
        .collect())
}

async fn artist_batch(session: &Session, uris: &[&String]) -> anyhow::Result<Vec<Artist>> {
    let mut request = BatchedEntityRequest::new();
    for uri in uris {
        request.entity_request.push(EntityRequest {
            entity_uri: (*uri).clone(),
            query: vec![ExtensionQuery {
                extension_kind: EnumOrUnknown::new(ExtensionKind::ARTIST_V4),
                ..Default::default()
            }],
            ..Default::default()
        });
    }
    let response = session.spclient().get_extended_metadata(request).await?;
    let mut artists = Vec::new();
    for array in response.extended_metadata {
        let provider = array.header.provider_error_status;
        anyhow::ensure!(
            matches!(provider, 0 | 200),
            "metadata provider answered {provider}"
        );
        if array.extension_kind.enum_value() != Ok(ExtensionKind::ARTIST_V4) {
            continue;
        }
        for data in array.extension_data {
            if !matches!(data.header.status_code, 0 | 200) {
                continue;
            }
            let artist = data.extension_data.as_ref().and_then(|any| {
                let message =
                    librespot_protocol::metadata::Artist::parse_from_bytes(&any.value).ok()?;
                SessionArtist::try_from(&message).ok()
            });
            artists.extend(artist.as_ref().map(session_reads::web_artist));
        }
    }
    Ok(artists)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Ответ живого аккаунта (две строки набора «artist» и токен следующей страницы).
    fn sample_page() -> Vec<u8> {
        let mut buf = Vec::new();
        for (uri, at, removed) in [
            ("spotify:artist:3v1PSxYgbjp8MAglSecAgP", 1_692_896_987i64, false),
            ("spotify:artist:gone", 1_700_000_000, true),
            ("spotify:artist:4YWj8sohRDjL9deiuRvEEY", 1_708_682_373, false),
        ] {
            put_bytes(&mut buf, 1, &item_message(uri, at, removed));
        }
        put_bytes(&mut buf, 2, b"next-token");
        put_bytes(&mut buf, 3, b"1791726013562");
        buf
    }

    #[test]
    fn page_request_matches_the_wire_format() {
        let body = page_request("me", "artist", "", 300);
        assert_eq!(body, [0x0a, 2, b'm', b'e', 0x12, 6, b'a', b'r', b't', b'i', b's', b't', 0x20, 0xac, 0x02]);
        let with_token = page_request("me", "artist", "t", 1);
        assert_eq!(&with_token[12..], [0x1a, 1, b't', 0x20, 1]);
    }

    #[test]
    fn pages_skip_removed_rows_and_keep_tokens_and_times() {
        let page = parse_page(&sample_page());
        assert_eq!(
            page.items,
            vec![
                CollectionItem { uri: "spotify:artist:3v1PSxYgbjp8MAglSecAgP".into(), added_at: 1_692_896_987 },
                CollectionItem { uri: "spotify:artist:4YWj8sohRDjL9deiuRvEEY".into(), added_at: 1_708_682_373 },
            ]
        );
        assert_eq!(page.next_token, "next-token");
        assert_eq!(page.sync_token, "1791726013562");
        assert_eq!(parse_page(b"\xff\xff"), CollectionPage::default(), "broken bytes read as nothing");
    }

    /// Ответ /paging: строки (uri, время, снята ли) и токен следующей страницы.
    fn wire_page(rows: &[(&str, i64, bool)], next: &str) -> Vec<u8> {
        let mut buf = Vec::new();
        for (uri, at, removed) in rows {
            put_bytes(&mut buf, 1, &item_message(uri, *at, *removed));
        }
        put_bytes(&mut buf, 2, next.as_bytes());
        put_bytes(&mut buf, 3, b"sync");
        buf
    }

    /// Сервис из готовых страниц: токен → байты ответа; запросы пишутся в `asked`.
    async fn serve(
        pages: &HashMap<&str, Vec<u8>>,
        asked: &Mutex<Vec<String>>,
        max_pages: usize,
    ) -> anyhow::Result<Vec<CollectionItem>> {
        collect_pages(max_pages, |token| {
            asked.lock().unwrap().push(token.clone());
            let page = pages.get(token.as_str()).map(|bytes| parse_page(bytes));
            async move { page.ok_or_else(|| anyhow::anyhow!("no page for {token:?}")) }
        })
        .await
    }

    fn uris(items: &[CollectionItem]) -> Vec<&str> {
        items.iter().map(|item| item.uri.as_str()).collect()
    }

    #[tokio::test]
    async fn every_page_is_followed_by_its_token_and_sorted_newest_first() {
        // limit 2: 5 треков и альбом на трёх страницах, порядок сервиса — по URI
        let pages = HashMap::from([
            ("", wire_page(&[("spotify:album:a", 50, false), ("spotify:track:1", 10, false)], "p2")),
            ("p2", wire_page(&[("spotify:track:2", 40, false), ("spotify:track:3", 30, false)], "p3")),
            ("p3", wire_page(&[("spotify:track:4", 20, false), ("spotify:track:5", 0, false)], "")),
        ]);
        let asked = Mutex::new(Vec::new());
        let items = serve(&pages, &asked, 200).await.unwrap();
        assert_eq!(*asked.lock().unwrap(), ["", "p2", "p3"]);
        assert_eq!(
            uris(&items),
            ["spotify:album:a", "spotify:track:2", "spotify:track:3", "spotify:track:4", "spotify:track:1", "spotify:track:5"],
            "newest first, unknown time last"
        );
    }

    #[tokio::test]
    async fn a_page_of_only_removed_rows_is_not_the_end() {
        let pages = HashMap::from([
            ("", wire_page(&[("spotify:track:1", 10, false)], "p2")),
            ("p2", wire_page(&[("spotify:track:gone1", 0, true), ("spotify:track:gone2", 0, true)], "p3")),
            ("p3", wire_page(&[("spotify:track:3", 30, false)], "")),
        ]);
        let asked = Mutex::new(Vec::new());
        let items = serve(&pages, &asked, 200).await.unwrap();
        assert_eq!(uris(&items), ["spotify:track:3", "spotify:track:1"]);
        assert_eq!(asked.lock().unwrap().len(), 3);
    }

    #[tokio::test]
    async fn paging_stops_on_an_empty_page_a_repeated_token_or_the_page_cap() {
        // пустая страница с токеном — конец
        let pages = HashMap::from([
            ("", wire_page(&[("spotify:track:1", 10, false)], "p2")),
            ("p2", wire_page(&[], "p3")),
        ]);
        let asked = Mutex::new(Vec::new());
        assert_eq!(uris(&serve(&pages, &asked, 200).await.unwrap()), ["spotify:track:1"]);
        assert_eq!(asked.lock().unwrap().len(), 2);
        // сервис зациклился: p2 → p3 → p2; строка, пришедшая дважды, остаётся одна
        let pages = HashMap::from([
            ("", wire_page(&[("spotify:track:1", 10, false)], "p2")),
            ("p2", wire_page(&[("spotify:track:2", 20, false)], "p3")),
            ("p3", wire_page(&[("spotify:track:2", 20, false), ("spotify:track:3", 5, false)], "p2")),
        ]);
        let asked = Mutex::new(Vec::new());
        let items = serve(&pages, &asked, 200).await.unwrap();
        assert_eq!(uris(&items), ["spotify:track:2", "spotify:track:1", "spotify:track:3"]);
        assert_eq!(*asked.lock().unwrap(), ["", "p2", "p3"]);
        // потолок страниц
        let asked = Mutex::new(Vec::new());
        assert_eq!(serve(&pages, &asked, 1).await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn a_failed_page_fails_the_whole_read() {
        let pages = HashMap::from([("", wire_page(&[("spotify:track:1", 10, false)], "missing"))]);
        let asked = Mutex::new(Vec::new());
        let error = serve(&pages, &asked, 200).await.unwrap_err();
        assert!(error.to_string().contains("missing"), "{error}");
    }

    #[test]
    fn small_pages_are_asked_for_with_their_limit() {
        let body = page_request("me", "collection", "tok", 5);
        assert!(body.ends_with(&[0x1a, 3, b't', b'o', b'k', 0x20, 5]));
    }

    #[test]
    fn newest_rows_come_first() {
        let mut items = parse_page(&sample_page()).items;
        newest_first(&mut items);
        assert_eq!(items[0].uri, "spotify:artist:4YWj8sohRDjL9deiuRvEEY");
        assert_eq!(items[0].added_at_iso().as_deref(), Some("2024-02-23T09:59:33Z"));
        assert_eq!(CollectionItem { uri: String::new(), added_at: 0 }.added_at_iso(), None);
    }

    #[test]
    fn writes_add_with_a_time_and_remove_with_a_flag() {
        let uris = vec!["spotify:track:a".to_owned()];
        let add = write_request("me", "collection", &uris, true, 300, "id");
        let mut expected = Vec::new();
        put_bytes(&mut expected, 1, b"me");
        put_bytes(&mut expected, 2, b"collection");
        put_bytes(&mut expected, 3, &[0x0a, 15, b's', b'p', b'o', b't', b'i', b'f', b'y', b':', b't', b'r', b'a', b'c', b'k', b':', b'a', 0x10, 0xac, 0x02]);
        put_bytes(&mut expected, 4, b"id");
        assert_eq!(add, expected);
        let remove = write_request("me", "collection", &uris, false, 300, "id");
        let mut expected = Vec::new();
        put_bytes(&mut expected, 1, b"me");
        put_bytes(&mut expected, 2, b"collection");
        put_bytes(&mut expected, 3, &item_message("spotify:track:a", 0, true));
        put_bytes(&mut expected, 4, b"id");
        assert_eq!(remove, expected);
        assert!(item_message("spotify:track:a", 0, true).ends_with(&[0x18, 1]), "is_removed is set, no time");
    }

    #[test]
    fn contains_wraps_each_uri_and_reads_packed_or_single_flags() {
        let body = contains_request("me", "artist", &["spotify:artist:x".to_owned()]);
        assert_eq!(&body[12..], [0x1a, 18, 0x0a, 16, b's', b'p', b'o', b't', b'i', b'f', b'y', b':', b'a', b'r', b't', b'i', b's', b't', b':', b'x']);
        // живые ответы: «0a 02 01 00» — [true, false]
        assert_eq!(parse_contains(&[0x0a, 0x02, 0x01, 0x00]), vec![true, false]);
        assert_eq!(parse_contains(&[0x08, 0x01, 0x08, 0x00]), vec![true, false]);
        assert!(parse_contains(&[]).is_empty());
    }

    #[test]
    fn uris_are_grouped_by_their_set() {
        assert_eq!(set_for("spotify:track:a"), Some(SET_COLLECTION));
        assert_eq!(set_for("spotify:album:a"), Some(SET_COLLECTION));
        assert_eq!(set_for("spotify:artist:a"), Some(SET_ARTIST));
        assert_eq!(set_for("spotify:show:a"), Some(SET_SHOW));
        assert_eq!(set_for("spotify:episode:a"), Some(SET_LISTEN_LATER));
        assert_eq!(set_for("spotify:playlist:a"), None);
        let uris: Vec<String> = ["spotify:artist:1", "spotify:track:2", "spotify:playlist:3", "spotify:album:4"]
            .map(str::to_owned)
            .to_vec();
        let (groups, unknown) = by_set(&uris);
        assert_eq!(groups, vec![(SET_ARTIST, vec![0]), (SET_COLLECTION, vec![1, 3])]);
        assert_eq!(unknown, vec![2]);
    }
}
