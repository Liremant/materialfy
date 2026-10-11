//! Внутренние модули «services-extra» (станции радио, медиаклавиши/SMTC/MPRIS, приёмники zeroconf…).
//! Новые файлы части 2 sf-services создавать только здесь; объявлять в этом mod.rs.

/// список устройств Connect: слияние Web API, этого ПК и приёмников mDNS
pub mod connect;
/// панель «Сейчас играет» и медиаклавиши (fastframe-now-playing)
#[cfg(any(windows, target_os = "macos", target_os = "linux"))]
pub mod media;
/// группы сидов радио
pub mod seeds;
/// состав полок главной
pub mod shelves;
