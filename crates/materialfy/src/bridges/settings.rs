// Settings: персистентные свойства (ключи mf_platform::SettingKey) с сигналами <имя>Changed. Значения кэшируются в мосте,
// запись — сразу в SettingsStore; изменения из других мест (Player.volume, AuthService::apply_proxy) приходят подпиской.
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QStringList, QVariant};

use crate::qt::QVariantMap;
use mf_platform::{SettingKey, SettingValue, SettingsStore};

use super::{Delivery, forward_events, forward_watch};
use crate::context::ctx;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QString, theme_mode, cxx_name = "themeMode", READ, WRITE = set_theme_mode, NOTIFY = theme_mode_changed)]
        #[qproperty(QString, scheme_variant, cxx_name = "schemeVariant", READ, WRITE = set_scheme_variant, NOTIFY = scheme_variant_changed)]
        #[qproperty(bool, accent_from_cover, cxx_name = "accentFromCover", READ, WRITE = set_accent_from_cover, NOTIFY = accent_from_cover_changed)]
        #[qproperty(QString, custom_seed, cxx_name = "customSeed", READ, WRITE = set_custom_seed, NOTIFY = custom_seed_changed)]
        #[qproperty(bool, window_buttons, cxx_name = "windowButtons", READ = window_buttons_value, WRITE = set_window_buttons, NOTIFY = window_buttons_changed)]
        #[qproperty(QString, track_transition, cxx_name = "trackTransition", READ, WRITE = set_track_transition, NOTIFY = track_transition_changed)]
        #[qproperty(QString, backdrop_mode, cxx_name = "backdropMode", READ, WRITE = set_backdrop_mode, NOTIFY = backdrop_mode_changed)]
        #[qproperty(f64, now_playing_blur, cxx_name = "nowPlayingBlur", READ, WRITE = set_now_playing_blur, NOTIFY = now_playing_blur_changed)]
        #[qproperty(f64, now_playing_drift, cxx_name = "nowPlayingDrift", READ, WRITE = set_now_playing_drift, NOTIFY = now_playing_drift_changed)]
        #[qproperty(bool, ambient_background, cxx_name = "ambientBackground", READ, WRITE = set_ambient_background, NOTIFY = ambient_background_changed)]
        #[qproperty(bool, cover_spin, cxx_name = "coverSpin", READ, WRITE = set_cover_spin, NOTIFY = cover_spin_changed)]
        #[qproperty(bool, cover_pulse, cxx_name = "coverPulse", READ, WRITE = set_cover_pulse, NOTIFY = cover_pulse_changed)]
        #[qproperty(bool, calm_when_inactive, cxx_name = "calmWhenInactive", READ, WRITE = set_calm_when_inactive, NOTIFY = calm_when_inactive_changed)]
        #[qproperty(QString, animations, READ, WRITE = set_animations, NOTIFY = animations_changed)]
        #[qproperty(bool, right_panel_open, cxx_name = "rightPanelOpen", READ, WRITE = set_right_panel_open, NOTIFY = right_panel_open_changed)]
        #[qproperty(QString, right_panel_tab, cxx_name = "rightPanelTab", READ, WRITE = set_right_panel_tab, NOTIFY = right_panel_tab_changed)]
        #[qproperty(bool, sidebar_collapsed, cxx_name = "sidebarCollapsed", READ, WRITE = set_sidebar_collapsed, NOTIFY = sidebar_collapsed_changed)]
        #[qproperty(i32, window_width, cxx_name = "windowWidth", READ, WRITE = set_window_width, NOTIFY = window_width_changed)]
        #[qproperty(i32, window_height, cxx_name = "windowHeight", READ, WRITE = set_window_height, NOTIFY = window_height_changed)]
        #[qproperty(i32, window_x, cxx_name = "windowX", READ, WRITE = set_window_x, NOTIFY = window_x_changed)]
        #[qproperty(i32, window_y, cxx_name = "windowY", READ, WRITE = set_window_y, NOTIFY = window_y_changed)]
        #[qproperty(bool, window_maximized, cxx_name = "windowMaximized", READ, WRITE = set_window_maximized, NOTIFY = window_maximized_changed)]
        #[qproperty(QString, library_view, cxx_name = "libraryView", READ, WRITE = set_library_view, NOTIFY = library_view_changed)]
        #[qproperty(QString, library_sort, cxx_name = "librarySort", READ, WRITE = set_library_sort, NOTIFY = library_sort_changed)]
        #[qproperty(QString, home_hidden, cxx_name = "homeHidden", READ, WRITE = set_home_hidden, NOTIFY = home_hidden_changed)]
        #[qproperty(i32, bitrate, READ, WRITE = set_bitrate, NOTIFY = bitrate_changed)]
        #[qproperty(bool, normalisation, READ, WRITE = set_normalisation, NOTIFY = normalisation_changed)]
        #[qproperty(bool, gapless, READ, WRITE = set_gapless, NOTIFY = gapless_changed)]
        #[qproperty(bool, autoplay, READ, WRITE = set_autoplay, NOTIFY = autoplay_changed)]
        #[qproperty(f64, volume, READ, WRITE = set_volume, NOTIFY = volume_changed)]
        #[qproperty(QString, audio_device, cxx_name = "audioDevice", READ, WRITE = set_audio_device, NOTIFY = audio_device_changed)]
        #[qproperty(bool, audio_cache, cxx_name = "audioCache", READ, WRITE = set_audio_cache, NOTIFY = audio_cache_changed)]
        #[qproperty(i32, audio_cache_mb, cxx_name = "audioCacheMb", READ, WRITE = set_audio_cache_mb, NOTIFY = audio_cache_mb_changed)]
        #[qproperty(bool, playback_authorized, cxx_name = "playbackAuthorized", READ, WRITE = set_playback_authorized, NOTIFY = playback_authorized_changed)]
        #[qproperty(f64, playback_speed, cxx_name = "playbackSpeed", READ, WRITE = set_playback_speed, NOTIFY = playback_speed_changed)]
        #[qproperty(i32, crossfade, READ, WRITE = set_crossfade, NOTIFY = crossfade_changed)]
        #[qproperty(QString, device_name, cxx_name = "deviceName", READ, WRITE = set_device_name, NOTIFY = device_name_changed)]
        #[qproperty(QString, web_client_id, cxx_name = "webClientId", READ, WRITE = set_web_client_id, NOTIFY = web_client_id_changed)]
        #[qproperty(QString, proxy_mode, cxx_name = "proxyMode", READ, NOTIFY = proxy_mode_changed)]
        #[qproperty(QString, proxy_host, cxx_name = "proxyHost", READ, NOTIFY = proxy_host_changed)]
        #[qproperty(QString, proxy_port, cxx_name = "proxyPort", READ, NOTIFY = proxy_port_changed)]
        #[qproperty(QString, proxy_username, cxx_name = "proxyUsername", READ, NOTIFY = proxy_username_changed)]
        #[qproperty(bool, close_to_tray, cxx_name = "closeToTray", READ, WRITE = set_close_to_tray, NOTIFY = close_to_tray_changed)]
        #[qproperty(i32, wheel_step, cxx_name = "wheelStep", READ, WRITE = set_wheel_step, NOTIFY = wheel_step_changed)]
        #[qproperty(QStringList, audio_devices, cxx_name = "audioDevices", READ, NOTIFY = audio_devices_changed)]
        #[qproperty(QMap_QString_QVariant, cache_usage, cxx_name = "cacheUsage", READ, NOTIFY = cache_usage_changed)]
        #[qproperty(bool, engine_restart_pending, cxx_name = "engineRestartPending", READ, NOTIFY = engine_restart_pending_changed)]
        #[qproperty(QString, proxy_state, cxx_name = "proxyState", READ, NOTIFY = proxy_state_changed)]
        #[qproperty(QString, proxy_error, cxx_name = "proxyError", READ, NOTIFY = proxy_state_changed)]
        #[qproperty(bool, system_reduced_motion, cxx_name = "systemReducedMotion", READ, CONSTANT)]
        /// тема панели задач для значка трея: "dark", "light" или "" (неизвестно — QML смотрит на тему Qt)
        #[qproperty(QString, system_taskbar_theme, cxx_name = "systemTaskbarTheme", READ, CONSTANT)]
        type Settings = super::SettingsRust;

        fn window_buttons_value(self: &Settings) -> bool;

        fn set_theme_mode(self: Pin<&mut Settings>, value: QString);
        fn set_scheme_variant(self: Pin<&mut Settings>, value: QString);
        fn set_accent_from_cover(self: Pin<&mut Settings>, value: bool);
        fn set_custom_seed(self: Pin<&mut Settings>, value: QString);
        fn set_window_buttons(self: Pin<&mut Settings>, value: bool);
        fn set_track_transition(self: Pin<&mut Settings>, value: QString);
        fn set_backdrop_mode(self: Pin<&mut Settings>, value: QString);
        fn set_now_playing_blur(self: Pin<&mut Settings>, value: f64);
        fn set_now_playing_drift(self: Pin<&mut Settings>, value: f64);
        fn set_ambient_background(self: Pin<&mut Settings>, value: bool);
        fn set_cover_spin(self: Pin<&mut Settings>, value: bool);
        fn set_cover_pulse(self: Pin<&mut Settings>, value: bool);
        fn set_calm_when_inactive(self: Pin<&mut Settings>, value: bool);
        fn set_animations(self: Pin<&mut Settings>, value: QString);
        fn set_right_panel_open(self: Pin<&mut Settings>, value: bool);
        fn set_right_panel_tab(self: Pin<&mut Settings>, value: QString);
        fn set_sidebar_collapsed(self: Pin<&mut Settings>, value: bool);
        fn set_window_width(self: Pin<&mut Settings>, value: i32);
        fn set_window_height(self: Pin<&mut Settings>, value: i32);
        fn set_window_x(self: Pin<&mut Settings>, value: i32);
        fn set_window_y(self: Pin<&mut Settings>, value: i32);
        fn set_window_maximized(self: Pin<&mut Settings>, value: bool);
        fn set_library_view(self: Pin<&mut Settings>, value: QString);
        fn set_library_sort(self: Pin<&mut Settings>, value: QString);
        fn set_home_hidden(self: Pin<&mut Settings>, value: QString);
        fn set_bitrate(self: Pin<&mut Settings>, value: i32);
        fn set_normalisation(self: Pin<&mut Settings>, value: bool);
        fn set_gapless(self: Pin<&mut Settings>, value: bool);
        fn set_autoplay(self: Pin<&mut Settings>, value: bool);
        fn set_volume(self: Pin<&mut Settings>, value: f64);
        fn set_audio_device(self: Pin<&mut Settings>, value: QString);
        fn set_audio_cache(self: Pin<&mut Settings>, value: bool);
        fn set_audio_cache_mb(self: Pin<&mut Settings>, value: i32);
        fn set_playback_authorized(self: Pin<&mut Settings>, value: bool);
        fn set_playback_speed(self: Pin<&mut Settings>, value: f64);
        fn set_crossfade(self: Pin<&mut Settings>, value: i32);
        fn set_device_name(self: Pin<&mut Settings>, value: QString);
        fn set_web_client_id(self: Pin<&mut Settings>, value: QString);
        fn set_close_to_tray(self: Pin<&mut Settings>, value: bool);
        fn set_wheel_step(self: Pin<&mut Settings>, value: i32);

        #[qsignal]
        #[cxx_name = "themeModeChanged"]
        fn theme_mode_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "schemeVariantChanged"]
        fn scheme_variant_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "accentFromCoverChanged"]
        fn accent_from_cover_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "customSeedChanged"]
        fn custom_seed_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "windowButtonsChanged"]
        fn window_buttons_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "trackTransitionChanged"]
        fn track_transition_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "backdropModeChanged"]
        fn backdrop_mode_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "nowPlayingBlurChanged"]
        fn now_playing_blur_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "nowPlayingDriftChanged"]
        fn now_playing_drift_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "ambientBackgroundChanged"]
        fn ambient_background_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "coverSpinChanged"]
        fn cover_spin_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "coverPulseChanged"]
        fn cover_pulse_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "calmWhenInactiveChanged"]
        fn calm_when_inactive_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "animationsChanged"]
        fn animations_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "rightPanelOpenChanged"]
        fn right_panel_open_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "rightPanelTabChanged"]
        fn right_panel_tab_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "sidebarCollapsedChanged"]
        fn sidebar_collapsed_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "windowWidthChanged"]
        fn window_width_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "windowHeightChanged"]
        fn window_height_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "windowXChanged"]
        fn window_x_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "windowYChanged"]
        fn window_y_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "windowMaximizedChanged"]
        fn window_maximized_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "libraryViewChanged"]
        fn library_view_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "librarySortChanged"]
        fn library_sort_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "homeHiddenChanged"]
        fn home_hidden_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "bitrateChanged"]
        fn bitrate_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "normalisationChanged"]
        fn normalisation_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "gaplessChanged"]
        fn gapless_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "autoplayChanged"]
        fn autoplay_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "volumeChanged"]
        fn volume_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "audioDeviceChanged"]
        fn audio_device_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "audioCacheChanged"]
        fn audio_cache_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "audioCacheMbChanged"]
        fn audio_cache_mb_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "playbackAuthorizedChanged"]
        fn playback_authorized_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "playbackSpeedChanged"]
        fn playback_speed_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "crossfadeChanged"]
        fn crossfade_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "deviceNameChanged"]
        fn device_name_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "webClientIdChanged"]
        fn web_client_id_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "proxyModeChanged"]
        fn proxy_mode_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "proxyHostChanged"]
        fn proxy_host_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "proxyPortChanged"]
        fn proxy_port_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "proxyUsernameChanged"]
        fn proxy_username_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "closeToTrayChanged"]
        fn close_to_tray_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "wheelStepChanged"]
        fn wheel_step_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "audioDevicesChanged"]
        fn audio_devices_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "cacheUsageChanged"]
        fn cache_usage_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "engineRestartPendingChanged"]
        fn engine_restart_pending_changed(self: Pin<&mut Settings>);
        #[qsignal]
        #[cxx_name = "proxyStateChanged"]
        fn proxy_state_changed(self: Pin<&mut Settings>);

        /// Перечитать устройства вывода (sf_player::output_devices в spawn_blocking).
        #[qinvokable]
        #[cxx_name = "refreshAudioDevices"]
        fn refresh_audio_devices(self: Pin<&mut Settings>);
        /// Пересчитать занятое место (mf_platform::dirs::cache_usage в spawn_blocking).
        #[qinvokable]
        #[cxx_name = "refreshCacheUsage"]
        fn refresh_cache_usage(self: Pin<&mut Settings>);
        /// Очистить кэш (вход не трогается), затем refreshCacheUsage.
        #[qinvokable]
        #[cxx_name = "clearCache"]
        fn clear_cache(self: Pin<&mut Settings>);
        /// Открыть каталог кэша в проводнике.
        #[qinvokable]
        #[cxx_name = "openCacheFolder"]
        fn open_cache_folder(self: &Settings);
        /// «Применить» в ApplyBar: перезапуск движка с новыми настройками (auth.restart_engine).
        #[qinvokable]
        #[cxx_name = "applyEngineSettings"]
        fn apply_engine_settings(self: Pin<&mut Settings>);
        /// Применить прокси (пароль — в хранилище секретов, не в настройки).
        #[qinvokable]
        #[cxx_name = "applyProxy"]
        fn apply_proxy(self: Pin<&mut Settings>, mode: &QString, host: &QString, port: &QString, username: &QString, password: &QString);
    }

    impl cxx_qt::Threading for Settings {}
    impl cxx_qt::Initialize for Settings {}
}

/// Тип свойства QML ↔ значение хранилища.
trait Field: Sized + PartialEq + Clone {
    fn load(store: &SettingsStore, key: SettingKey) -> Self;
    fn to_value(&self) -> SettingValue;
}

impl Field for QString {
    fn load(store: &SettingsStore, key: SettingKey) -> Self {
        if key == SettingKey::CustomSeed {
            return QString::from(super::theme::custom_seed(store).as_str());
        }
        QString::from(store.get_str(key).as_str())
    }
    fn to_value(&self) -> SettingValue {
        SettingValue::Str(self.to_string())
    }
}

impl Field for bool {
    fn load(store: &SettingsStore, key: SettingKey) -> Self {
        store.get_bool(key)
    }
    fn to_value(&self) -> SettingValue {
        SettingValue::Bool(*self)
    }
}

impl Field for i32 {
    fn load(store: &SettingsStore, key: SettingKey) -> Self {
        store.get_int(key).clamp(i32::MIN as i64, i32::MAX as i64) as i32
    }
    fn to_value(&self) -> SettingValue {
        SettingValue::Int(*self as i64)
    }
}

impl Field for f64 {
    fn load(store: &SettingsStore, key: SettingKey) -> Self {
        store.get_f64(key)
    }
    fn to_value(&self) -> SettingValue {
        SettingValue::Float(*self)
    }
}

fn store() -> &'static SettingsStore {
    &ctx().services.settings
}

// (поле, тип, ключ, сеттер, сигнал) — одна строка на свойство
// readonly — только чтение из QML (пишет сервис, например прокси после проверки в AuthService::apply_proxy)
macro_rules! settings {
    ($( $field:ident : $ty:ty = $key:ident, $setter:ident, $signal:ident; )*
     @readonly { $( $rfield:ident : $rty:ty = $rkey:ident, $rsignal:ident; )* }) => {
        pub struct SettingsRust {
            $( $field: $ty, )*
            $( $rfield: $rty, )*
            audio_devices: QStringList,
            cache_usage: QVariantMap,
            engine_restart_pending: bool,
            proxy_state: QString,
            proxy_error: QString,
            system_reduced_motion: bool,
            system_taskbar_theme: QString,
        }

        impl Default for SettingsRust {
            fn default() -> Self {
                let store = store();
                Self {
                    $( $field: <$ty as Field>::load(store, SettingKey::$key), )*
                    $( $rfield: <$rty as Field>::load(store, SettingKey::$rkey), )*
                    audio_devices: QStringList::default(),
                    cache_usage: QVariantMap::default(),
                    engine_restart_pending: false,
                    proxy_state: QString::default(),
                    proxy_error: QString::default(),
                    system_reduced_motion: mf_platform::system::reduced_motion(),
                    system_taskbar_theme: QString::from(match mf_platform::system::taskbar_dark() {
                        Some(true) => "dark",
                        Some(false) => "light",
                        None => "",
                    }),
                }
            }
        }

        impl qobject::Settings {
            $(
                fn $setter(mut self: Pin<&mut Self>, value: $ty) {
                    if self.$field == value {
                        return;
                    }
                    self.as_mut().rust_mut().$field = value.clone();
                    store().set(SettingKey::$key, value.to_value());
                    self.$signal();
                }
            )*

            /// Значение изменилось в хранилище (не через этот мост) — перечитать и оповестить.
            fn reload(mut self: Pin<&mut Self>, key: SettingKey) {
                match key {
                    $(
                        SettingKey::$key => {
                            let value = <$ty as Field>::load(store(), key);
                            if self.$field != value {
                                self.as_mut().rust_mut().$field = value;
                                self.$signal();
                            }
                        }
                    )*
                    $(
                        SettingKey::$rkey => {
                            let value = <$rty as Field>::load(store(), key);
                            if self.$rfield != value {
                                self.as_mut().rust_mut().$rfield = value;
                                self.$rsignal();
                            }
                        }
                    )*
                    // служебные ключи без свойства QML (Pins, HiddenTracks)
                    _ => {}
                }
            }
        }
    };
}

settings! {
    theme_mode: QString = ThemeMode, set_theme_mode, theme_mode_changed;
    scheme_variant: QString = SchemeVariant, set_scheme_variant, scheme_variant_changed;
    accent_from_cover: bool = AccentFromCover, set_accent_from_cover, accent_from_cover_changed;
    custom_seed: QString = CustomSeed, set_custom_seed, custom_seed_changed;
    window_buttons: bool = WindowButtons, set_window_buttons, window_buttons_changed;
    track_transition: QString = TrackTransition, set_track_transition, track_transition_changed;
    backdrop_mode: QString = BackdropMode, set_backdrop_mode, backdrop_mode_changed;
    now_playing_blur: f64 = NowPlayingBlur, set_now_playing_blur, now_playing_blur_changed;
    now_playing_drift: f64 = NowPlayingDrift, set_now_playing_drift, now_playing_drift_changed;
    ambient_background: bool = AmbientBackground, set_ambient_background, ambient_background_changed;
    cover_spin: bool = CoverSpin, set_cover_spin, cover_spin_changed;
    cover_pulse: bool = CoverPulse, set_cover_pulse, cover_pulse_changed;
    calm_when_inactive: bool = CalmWhenInactive, set_calm_when_inactive, calm_when_inactive_changed;
    animations: QString = Animations, set_animations, animations_changed;
    right_panel_open: bool = RightPanelOpen, set_right_panel_open, right_panel_open_changed;
    right_panel_tab: QString = RightPanelTab, set_right_panel_tab, right_panel_tab_changed;
    sidebar_collapsed: bool = SidebarCollapsed, set_sidebar_collapsed, sidebar_collapsed_changed;
    window_width: i32 = WindowWidth, set_window_width, window_width_changed;
    window_height: i32 = WindowHeight, set_window_height, window_height_changed;
    window_x: i32 = WindowX, set_window_x, window_x_changed;
    window_y: i32 = WindowY, set_window_y, window_y_changed;
    window_maximized: bool = WindowMaximized, set_window_maximized, window_maximized_changed;
    library_view: QString = LibraryView, set_library_view, library_view_changed;
    library_sort: QString = LibrarySort, set_library_sort, library_sort_changed;
    home_hidden: QString = HomeHidden, set_home_hidden, home_hidden_changed;
    bitrate: i32 = Bitrate, set_bitrate, bitrate_changed;
    normalisation: bool = Normalisation, set_normalisation, normalisation_changed;
    gapless: bool = Gapless, set_gapless, gapless_changed;
    autoplay: bool = Autoplay, set_autoplay, autoplay_changed;
    volume: f64 = Volume, set_volume, volume_changed;
    audio_device: QString = AudioDevice, set_audio_device, audio_device_changed;
    audio_cache: bool = AudioCache, set_audio_cache, audio_cache_changed;
    audio_cache_mb: i32 = AudioCacheMb, set_audio_cache_mb, audio_cache_mb_changed;
    playback_authorized: bool = PlaybackAuthorized, set_playback_authorized, playback_authorized_changed;
    playback_speed: f64 = PlaybackSpeed, set_playback_speed, playback_speed_changed;
    crossfade: i32 = Crossfade, set_crossfade, crossfade_changed;
    device_name: QString = DeviceName, set_device_name, device_name_changed;
    web_client_id: QString = WebClientId, set_web_client_id, web_client_id_changed;
    close_to_tray: bool = CloseToTray, set_close_to_tray, close_to_tray_changed;
    wheel_step: i32 = WheelStep, set_wheel_step, wheel_step_changed;
    @readonly {
        proxy_mode: QString = ProxyMode, proxy_mode_changed;
        proxy_host: QString = ProxyHost, proxy_host_changed;
        proxy_port: QString = ProxyPort, proxy_port_changed;
        proxy_username: QString = ProxyUsername, proxy_username_changed;
    }
}

impl qobject::Settings {
    /// Windows: рамку рисует приложение, кнопки окна нужны всегда (запись сохраняется, но не влияет).
    fn window_buttons_value(&self) -> bool {
        cfg!(target_os = "windows") || self.window_buttons
    }

    fn refresh_audio_devices(self: Pin<&mut Self>) {
        let thread = self.qt_thread();
        ctx().rt.spawn_blocking(move || {
            let devices = sf_player::output_devices();
            let _ = thread.queue(move |settings| settings.set_audio_devices(devices));
        });
    }

    fn set_audio_devices(mut self: Pin<&mut Self>, devices: Vec<String>) {
        let list: QStringList = devices.iter().map(|d| QString::from(d.as_str())).collect();
        if self.audio_devices != list {
            self.as_mut().rust_mut().audio_devices = list;
            self.audio_devices_changed();
        }
    }

    fn refresh_cache_usage(self: Pin<&mut Self>) {
        let thread = self.qt_thread();
        ctx().rt.spawn_blocking(move || {
            let usage = mf_platform::dirs::cache_usage();
            let _ = thread.queue(move |settings| settings.set_cache_usage(usage));
        });
    }

    fn set_cache_usage(mut self: Pin<&mut Self>, usage: mf_platform::dirs::CacheUsage) {
        let map = cache_usage_map(usage);
        if self.cache_usage != map {
            self.as_mut().rust_mut().cache_usage = map;
            self.cache_usage_changed();
        }
    }

    fn clear_cache(self: Pin<&mut Self>) {
        let thread = self.qt_thread();
        ctx().rt.spawn_blocking(move || {
            // занятые файлы (аудио играющего трека) пропускаются — остальное уже удалено, пользователю не мешаем
            if let Err(error) = mf_platform::dirs::clear_cache() {
                tracing::info!("кэш очищен не полностью: {error}");
            }
            let usage = mf_platform::dirs::cache_usage();
            let _ = thread.queue(move |settings| settings.set_cache_usage(usage));
        });
    }

    fn open_cache_folder(&self) {
        let dir = mf_platform::dirs::cache_dir();
        if let Err(error) = std::fs::create_dir_all(&dir) {
            tracing::warn!("каталог кэша {}: {error}", dir.display());
        }
        if !crate::qt::open_local_folder(&dir) {
            tracing::warn!("не удалось открыть {}", dir.display());
        }
    }

    fn apply_engine_settings(self: Pin<&mut Self>) {
        ctx().services.auth.restart_engine();
    }

    fn apply_proxy(
        self: Pin<&mut Self>,
        mode: &QString,
        host: &QString,
        port: &QString,
        username: &QString,
        password: &QString,
    ) {
        ctx().services.auth.apply_proxy(sf_services::ProxyInput {
            mode: mode.to_string(),
            host: host.to_string(),
            port: port.to_string(),
            username: username.to_string(),
            password: password.to_string(),
        });
    }

    /// engineRestartPending и proxyState/proxyError — из AuthSnapshot (флаг ведёт AuthService).
    fn on_auth(mut self: Pin<&mut Self>, snapshot: sf_services::AuthSnapshot) {
        if self.engine_restart_pending != snapshot.engine_restart_pending {
            self.as_mut().rust_mut().engine_restart_pending = snapshot.engine_restart_pending;
            self.as_mut().engine_restart_pending_changed();
        }
        let state = QString::from(snapshot.proxy_state.as_str());
        let error = QString::from(snapshot.proxy_error.as_str());
        if self.proxy_state != state || self.proxy_error != error {
            self.as_mut().rust_mut().proxy_state = state;
            self.as_mut().rust_mut().proxy_error = error;
            self.as_mut().proxy_state_changed();
        }
    }

    fn on_store(mut self: Pin<&mut Self>, delivery: Delivery<SettingKey>) {
        match delivery {
            Delivery::Event(key) => self.reload(key),
            Delivery::Lagged => {
                for key in SettingKey::ALL {
                    self.as_mut().reload(key);
                }
            }
        }
    }
}

/// {audio, covers, playlists, lyrics, total} в байтах (числа QML — double: размеры больше i32).
fn cache_usage_map(usage: mf_platform::dirs::CacheUsage) -> QVariantMap {
    let total = usage.total();
    let mut map = QVariantMap::default();
    for (key, bytes) in
        [("audio", usage.audio), ("covers", usage.covers), ("playlists", usage.playlists), ("lyrics", usage.lyrics), ("total", total)]
    {
        map.insert(QString::from(key), QVariant::from(&(bytes as f64)));
    }
    map
}

impl cxx_qt::Initialize for qobject::Settings {
    fn initialize(mut self: Pin<&mut Self>) {
        // нули до первого подсчёта: QML не видит undefined
        self.as_mut().rust_mut().cache_usage = cache_usage_map(Default::default());
        if !ctx().flags.screenshot {
            self.as_mut().refresh_audio_devices();
            self.as_mut().refresh_cache_usage();
        }
        forward_events(self.qt_thread(), store().subscribe(), Self::on_store);
        let auth = ctx().services.auth.watch();
        self.as_mut().on_auth(auth.borrow().clone());
        forward_watch(self.qt_thread(), auth, Self::on_auth);
    }
}
