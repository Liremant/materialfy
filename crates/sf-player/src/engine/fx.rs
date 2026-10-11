//! Скорость воспроизведения и кроссфейд: живые настройки, которые вывод звука читает на каждом пакете.
//! Меняются без перезапуска движка; позиция трека в интерфейсе тоже учитывает скорость.

use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;

pub use super::stretch::SPEED_RANGE;

/// The longest crossfade Settings offers.
pub const CROSSFADE_MAX: Duration = Duration::from_secs(12);

static SPEED: AtomicU32 = AtomicU32::new(1.0f32.to_bits());
static CROSSFADE_MS: AtomicU32 = AtomicU32::new(0);

/// How fast the music plays, 1.0 being as recorded.
pub fn speed() -> f32 {
    f32::from_bits(SPEED.load(Ordering::Relaxed))
}

pub fn set_speed(speed: f32) {
    let speed = if speed.is_finite() { speed.clamp(*SPEED_RANGE.start(), *SPEED_RANGE.end()) } else { 1.0 };
    SPEED.store(speed.to_bits(), Ordering::Relaxed);
}

/// How long one track fades into the next; zero is off.
pub fn crossfade() -> Duration {
    Duration::from_millis(u64::from(CROSSFADE_MS.load(Ordering::Relaxed)))
}

pub fn set_crossfade(length: Duration) {
    let ms = length.min(CROSSFADE_MAX).as_millis() as u32;
    CROSSFADE_MS.store(ms, Ordering::Relaxed);
}

/// Track time that passes in `elapsed` of wall time at the current speed.
pub fn track_elapsed_ms(elapsed: Duration) -> u32 {
    (elapsed.as_secs_f64() * f64::from(speed()) * 1_000.0) as u32
}
