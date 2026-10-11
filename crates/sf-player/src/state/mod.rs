//! Внутренние модули «queue-state»: актор плеера, модель очереди (queue.md), слияние Local/Remote, удержания.
//! Новые файлы верхнего слоя sf-player создавать только здесь; объявлять в этом mod.rs. Тесты очереди — здесь же.
pub(crate) mod actor;
pub mod backend;
/// Spotify Connect через сессию librespot (кластер connect-state, команды другим устройствам)
pub mod connect;
pub mod core;
pub(crate) mod diff;
pub(crate) mod host;
pub mod map;
pub mod session;
#[cfg(test)]
mod tests;
