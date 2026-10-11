//! Нижний слой sf-player (исполнитель «engine»): librespot Engine, свой sink на fastframe-audio, EQ/лимитер,
//! tap уровня, чтение через сессию, zeroconf, обложка в файл. Наружу — через PlayerHandle (верхний слой)
//! и прямые вызовы session_reads/zeroconf/sink::output_devices из sf-services.
pub mod cover;
pub mod eq;
pub mod fx;
pub mod limiter;
/// «Новинки» через сессию: «Радар новинок», подписки, релизы исполнителей
pub mod new_releases;
pub mod player;
pub mod resample;
pub mod session_reads;
pub mod sink;
pub mod stretch;
pub mod vis;
pub mod zeroconf;

pub use player::{
    Engine, EngineConfig, EngineEvent, Interrupted, LoadSpec, LocalState, LocalTrack, Notify, Playback,
    PlaybackResume, PlayerCommand, RepeatMode, Rootlist, RootlistEntry,
};
