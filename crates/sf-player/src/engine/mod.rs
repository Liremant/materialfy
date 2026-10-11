//! Нижний слой sf-player (исполнитель «engine»): librespot Engine, свой sink на fastframe-audio, EQ/лимитер,
//! tap уровня, чтение через сессию, zeroconf, обложка в файл. Наружу — через PlayerHandle (верхний слой)
//! и прямые вызовы session_reads/zeroconf/sink::output_devices из sf-services.
pub mod cover;
pub mod eq;
pub mod limiter;
pub mod player;
pub mod resample;
pub mod session_reads;
pub mod sink;
pub mod vis;
pub mod zeroconf;

pub use player::{
    Engine, EngineConfig, EngineEvent, Interrupted, LoadSpec, LocalState, LocalTrack, Notify, Playback,
    PlaybackResume, PlayerCommand, RepeatMode, Rootlist, RootlistEntry,
};
