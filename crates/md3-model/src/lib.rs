//! Нейтральные типы для QML: плоские элементы (serde camelCase → QVariantMap в оболочке), изменения списков,
//! контекст воспроизведения, строковые id. Ни Spotify, ни Qt здесь нет — маппинг из Web API живёт в sf-api.
//! Ключи сериализации — нормативный контракт с QML.
#![allow(clippy::new_without_default)]

pub mod context;
pub mod ids;
pub mod items;
pub mod list;
pub mod trackfilter;

pub use context::{PlayContext, contexts};
pub use ids::{AccountId, PlaylistId};
pub use items::*;
pub use list::ListChange;
