//! Модели списков для QML (владелец — «shell»). Мосты создают их через DictListModel::create
//! и применяют изменения сервисов через [`apply_list_change`].
pub mod list_model;
pub mod track_filter;

use std::pin::Pin;
use std::sync::Arc;

use serde::Serialize;
use md3_model::{ListChange, PlayContext, TrackItem};

pub use list_model::{ModelKind, Row, qobject::DictListModel};

/// Элемент (TrackItem, AlbumItem…) → строка модели.
pub fn to_row<T: Serialize>(item: &T) -> Row {
    match serde_json::to_value(item) {
        Ok(serde_json::Value::Object(map)) => Arc::new(map),
        _ => Arc::new(serde_json::Map::new()),
    }
}

pub fn to_rows<T: Serialize>(items: &[T]) -> Vec<Row> {
    items.iter().map(to_row).collect()
}

/// Применить изменение списка из sf-services к модели (в GUI-потоке).
pub fn apply_list_change<T: Serialize>(model: Pin<&mut DictListModel>, change: &ListChange<T>) {
    match change {
        ListChange::Reset(items) => model.reset_rows(to_rows(items)),
        ListChange::Append(items) => model.append_rows(to_rows(items)),
        ListChange::Insert { at, items } => model.insert_rows(*at, to_rows(items)),
        ListChange::Remove { at, count } => model.remove_rows(*at, *count),
        ListChange::Move { from, to } => model.move_row(*from, *to),
        ListChange::Loading(value) => model.set_loading(*value),
    }
}

/// Треки и контекст из модели, которую QML передал в Player.playFrom / shuffleFrom:
/// DictListModel (вида Track) или TrackFilter (найденные строки + контекст источника). Иное → None.
///
/// # Safety
/// `object` — живой QObject из QML (или null); вызывать в GUI-потоке.
pub unsafe fn tracks_from_model(object: *mut cxx_qt::QObject) -> Option<(Vec<TrackItem>, PlayContext)> {
    use cxx_qt::casting::Downcast;
    let object = unsafe { object.as_ref() }?;
    if let Some(model) = object.downcast::<DictListModel>() {
        let items = model
            .rows()
            .iter()
            .filter_map(|row| serde_json::from_value(serde_json::Value::Object((**row).clone())).ok())
            .collect();
        return Some((items, model.context().clone()));
    }
    track_filter::tracks_from_filter(object)
}
