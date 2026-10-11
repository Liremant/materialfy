// Materialfy — клиент Spotify: QML (src/materialfy/qml) + бэкенд на Rust (cxx-qt, librespot).
// Оболочка: cli, context, display, engine, icons, images, models, qt, winframe; мосты QML — bridges.
// релиз на Windows — GUI-подсистема, без чёрного окна консоли; отладочная сборка оставляет консоль для логов
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod bridges;
mod cli;
mod context;
mod display;
mod engine;
mod icons;
mod images;
mod models;
mod qt;
mod winframe;

fn main() {
    let args: Vec<String> = std::env::args_os().map(|a| a.to_string_lossy().into_owned()).collect();
    let code = engine::run(cli::Cli::parse(&args));
    std::process::exit(code);
}
