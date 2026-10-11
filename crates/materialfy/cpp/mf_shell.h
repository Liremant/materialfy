// Мелкие помощники Qt, которых нет в cxx-qt-lib. Владелец — агент «shell».
#pragma once

#include <QtCore/QObject>
#include <QtCore/QRectF>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtGui/QColor>
#include <QtQml/QQmlApplicationEngine>

#include <cstdint>

#include "rust/cxx.h"

namespace mf {

// QApplication (Qt Widgets: Qt.labs.platform берёт из него трей и меню на всех ОС).
// Аргументы копируются и живут до конца процесса.
void app_create(rust::Slice<const rust::String> args);
int app_exec();
// Удалить QApplication в конце run (после движка и остановки фоновых потоков)
void app_destroy();
void app_quit();
void app_set_names(const QString& app, const QString& org, const QString& desktop);
void app_set_quit_on_last_window_closed(bool value);
void app_set_window_icon(const QString& path);
// QFontDatabase::addApplicationFont; -1 — ошибка
int app_add_font(const QString& path);

// Буфер обмена (Auth.copyToClipboard, Catalog.copyLink)
void copy_to_clipboard(const QString& text);

// Объект, отданный в QML из слота, иначе станет JavaScriptOwnership и попадёт под сборщик мусора
void set_cpp_ownership(QObject* object);

// Системная тема: true — тёмная (QStyleHints::colorScheme() != Light)
bool system_color_scheme_dark();
// Подписка на QStyleHints::colorSchemeChanged → Rust system_dark_changed(bool)
void watch_color_scheme();
// Подписка на QGuiApplication::applicationStateChanged → Rust app_active_changed(bool) (опрос удалённого плеера)
void watch_app_state();
// Каталог в файловом менеджере (Settings.openCacheFolder)
bool open_local_folder(const QString& path);

// Загрузка QML: движок, контекстные свойства, начальные свойства корня
void engine_add_import_path(QQmlApplicationEngine& engine, const QString& path);
void engine_set_context_bool(QQmlApplicationEngine& engine, const QString& name, bool value);
// Создать все синглтоны модуля заранее (как qmlRegisterSingletonInstance в Python-версии)
void engine_touch_singletons(QQmlApplicationEngine& engine, const QStringList& names);
bool engine_has_root(const QQmlApplicationEngine& engine);
// Первый корневой объект (QQuickWindow) или nullptr
QObject* engine_root_object(const QQmlApplicationEngine& engine);
// Дисковый кэш картинок (images.py): у каждого NAM свой QNetworkDiskCache на общий каталог, только HTTP/1.1
void engine_install_caching_nam(QQmlApplicationEngine& engine, const QString& dir, std::int64_t max_bytes);
// Прокси для этих NAM (потокобезопасно, действует на следующие запросы):
// 0 — без прокси, 1 — системный, 2 — HTTP, 3 — SOCKS5, 4 — заблокировать (неверные настройки)
void set_image_proxy(int mode, const QString& host, int port, const QString& user, const QString& password);

// Есть ли у объекта свойство (property(name).isValid(), как `is not None` в app.py)
bool object_has_property(QObject* object, const QString& name);
// Окно, которое показывают AppRequest::RaiseWindow (держится через QPointer)
void set_main_window(QObject* window);
// Потокобезопасно: выполнить в GUI-потоке show/raise/requestActivate главного окна или выход
void post_raise_window();
void post_quit();
// Через delay мс: grabWindow().save(path) и выход
void schedule_screenshot(QObject* window, const QString& path, int delay_ms);

// Самый быстрый монитор — основным (display.py). Строка для лога.
QString prefer_fastest_screen();

// IconMetrics.ink: смещение центра контура глифа и его размер (icons.py, _measure)
QRectF icon_measure(const QString& text, int size);

} // namespace mf
