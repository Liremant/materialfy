#include "mf_shell.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QLibraryInfo>
#include <QtCore/QLocale>
#include <QtCore/QMetaObject>
#include <QtCore/QMutex>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QTranslator>
#include <QtCore/QUrl>
#include <QtGui/QClipboard>
#include <QtGui/QDesktopServices>
#include <QtGui/QFont>
#include <QtGui/QFontDatabase>
#include <QtGui/QFontMetricsF>
#include <QtGui/QGuiApplication>
#include <QtGui/QIcon>
#include <QtGui/QImage>
#include <QtGui/QPainter>
#include <QtGui/QScreen>
#include <QtGui/QStyleHints>
#include <QtGui/QWindow>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkDiskCache>
#include <QtNetwork/QNetworkProxy>
#include <QtNetwork/QNetworkRequest>
#include <QtQml/QQmlContext>
#include <QtQml/QQmlEngine>
#include <QtQml/QQmlNetworkAccessManagerFactory>
#include <QtQuick/QQuickWindow>
#include <QtWidgets/QApplication>

#include <algorithm>
#include <string>
#include <vector>

#if defined(Q_OS_LINUX)
#include <dlfcn.h>
#endif

#if defined(Q_OS_WIN)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shobjidl.h>
#endif

#include "materialfy/src/qt/ffi.cxx.h"

namespace mf {

namespace {
std::vector<std::string>&
arg_storage()
{
  static std::vector<std::string> storage;
  return storage;
}
std::vector<char*>&
argv_storage()
{
  static std::vector<char*> argv;
  return argv;
}
int argc_storage = 0;
// Удаляется в app_destroy — после движка и остановки tokio
QApplication* app = nullptr;
QPointer<QWindow> main_window;

// Только HTTP/1.1: по HTTP/2 сервер обложек Яндекса отвечает REFUSED_STREAM, когда страница
// разом просит десятки картинок, и часть обложек не появляется.
class Http1Nam : public QNetworkAccessManager
{
public:
  using QNetworkAccessManager::QNetworkAccessManager;

protected:
  QNetworkReply* createRequest(Operation op, const QNetworkRequest& request, QIODevice* data) override
  {
    QNetworkRequest copy(request);
    copy.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    return QNetworkAccessManager::createRequest(op, copy, data);
  }
};

// Прокси картинок из настроек «Сеть»: общий для всех NAM, читается на каждый запрос
QMutex proxy_mutex;
int proxy_mode = 1;
QNetworkProxy proxy_manual;

class SettingsProxyFactory : public QNetworkProxyFactory
{
public:
  QList<QNetworkProxy> queryProxy(const QNetworkProxyQuery& query) override
  {
    int mode;
    QNetworkProxy manual;
    {
      QMutexLocker lock(&proxy_mutex);
      mode = proxy_mode;
      manual = proxy_manual;
    }
    switch (mode) {
      case 0:
        return { QNetworkProxy(QNetworkProxy::NoProxy) };
      case 2:
      case 3:
        return { manual };
      case 4:
        // неверные настройки: тип не подходит для HTTP — запрос падает с ProxyNotFoundError, а не идёт напрямую
        return { QNetworkProxy(QNetworkProxy::FtpCachingProxy) };
      default:
        return systemProxyForQuery(query);
    }
  }
};

// QML создаёт NAM в своих потоках загрузки — у каждого свой QNetworkDiskCache на общий каталог
class CachingNamFactory : public QQmlNetworkAccessManagerFactory
{
public:
  CachingNamFactory(QString dir, qint64 bytes)
    : m_dir(std::move(dir))
    , m_bytes(bytes)
  {
  }

  QNetworkAccessManager* create(QObject* parent) override
  {
    auto* nam = new Http1Nam(parent);
    auto* disk = new QNetworkDiskCache(nam);
    disk->setCacheDirectory(m_dir);
    disk->setMaximumCacheSize(m_bytes);
    nam->setCache(disk);
    nam->setProxyFactory(new SettingsProxyFactory);
    return nam;
  }

private:
  const QString m_dir;
  const qint64 m_bytes;
};
} // namespace

void
app_create(rust::Slice<const rust::String> args)
{
  auto& storage = arg_storage();
  storage.clear();
  for (const auto& a : args)
    storage.emplace_back(std::string(a));
  auto& argv = argv_storage();
  argv.clear();
  for (auto& s : storage)
    argv.push_back(s.data());
  argv.push_back(nullptr);
  argc_storage = static_cast<int>(storage.size());
  app = new QApplication(argc_storage, argv.data());
}

int
app_exec()
{
  return QApplication::exec();
}

void
app_destroy()
{
  delete app;
  app = nullptr;
}

void
app_quit()
{
  QCoreApplication::quit();
}

void
app_set_names(const QString& name, const QString& org, const QString& desktop)
{
  QCoreApplication::setApplicationName(name);
  QCoreApplication::setOrganizationName(org);
  QGuiApplication::setDesktopFileName(desktop);
#if defined(Q_OS_WIN)
  // AppUserModelID = имя приложения (как у ярлыков из materialfy.iss): группировка на панели задач
  SetCurrentProcessExplicitAppUserModelID(reinterpret_cast<const wchar_t*>(name.utf16()));
#endif
}

void
app_set_quit_on_last_window_closed(bool value)
{
  QGuiApplication::setQuitOnLastWindowClosed(value);
}

void
app_set_window_icon(const QString& path)
{
  QGuiApplication::setWindowIcon(QIcon(path));
}

int
app_add_font(const QString& path)
{
  return QFontDatabase::addApplicationFont(path);
}

void
app_set_qt_language(const QString& code)
{
  static QTranslator* translator = nullptr;
  if (translator) {
    QCoreApplication::removeTranslator(translator);
    delete translator;
    translator = nullptr;
  }
  const bool english = code.isEmpty() || code == QLatin1String("en");
  QLocale::setDefault(english ? QLocale(QLocale::English, QLocale::UnitedStates) : QLocale(code));
  if (english)
    return;
  // windeployqt --translations <code> puts qtbase_<code>.qm into translations/ next to the exe;
  // a development build finds it in the Qt installation.
  const QString name = QStringLiteral("qtbase_") + code;
  auto* t = new QTranslator();
  const QStringList dirs{ QCoreApplication::applicationDirPath() + QStringLiteral("/translations"),
                          QLibraryInfo::path(QLibraryInfo::TranslationsPath) };
  for (const auto& dir : dirs) {
    if (t->load(name, dir)) {
      QCoreApplication::installTranslator(t);
      translator = t;
      return;
    }
  }
  delete t;
}

void
copy_to_clipboard(const QString& text)
{
  // Windows: буфер бывает занят другим процессом (история буфера и т. п.) — OleSetClipboard
  // отказывает; повторяем с паузой. Более новое копирование отменяет повторы старого.
  static int generation = 0;
  struct Attempt
  {
    static void run(const QString& text, int gen, int left)
    {
      auto* clipboard = QGuiApplication::clipboard();
      if (!clipboard || gen != generation)
        return;
      clipboard->setText(text);
      if (left > 0 && !clipboard->ownsClipboard())
        QTimer::singleShot(80, qApp, [text, gen, left] { run(text, gen, left - 1); });
    }
  };
  Attempt::run(text, ++generation, 4);
}

void
set_cpp_ownership(QObject* object)
{
  if (object)
    QQmlEngine::setObjectOwnership(object, QQmlEngine::CppOwnership);
}

bool
system_color_scheme_dark()
{
  return QGuiApplication::styleHints()->colorScheme() != Qt::ColorScheme::Light;
}

void
watch_color_scheme()
{
  QObject::connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, qApp, [](Qt::ColorScheme scheme) {
    system_dark_changed(scheme != Qt::ColorScheme::Light);
  });
}

void
watch_app_state()
{
  QObject::connect(qApp, &QGuiApplication::applicationStateChanged, qApp, [](Qt::ApplicationState state) {
    app_active_changed(state == Qt::ApplicationActive);
  });
}

bool
open_local_folder(const QString& path)
{
  return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void
engine_add_import_path(QQmlApplicationEngine& engine, const QString& path)
{
  engine.addImportPath(path);
}

void
engine_set_context_bool(QQmlApplicationEngine& engine, const QString& name, bool value)
{
  engine.rootContext()->setContextProperty(name, value);
}

void
engine_touch_singletons(QQmlApplicationEngine& engine, const QStringList& names)
{
  for (const auto& name : names)
    engine.singletonInstance<QObject*>(QStringLiteral("Materialfy.Core"), name);
}

bool
engine_has_root(const QQmlApplicationEngine& engine)
{
  return !engine.rootObjects().isEmpty();
}

QObject*
engine_root_object(const QQmlApplicationEngine& engine)
{
  const auto roots = engine.rootObjects();
  return roots.isEmpty() ? nullptr : roots.first();
}

void
engine_install_caching_nam(QQmlApplicationEngine& engine, const QString& dir, std::int64_t max_bytes)
{
  // Фабрика должна жить дольше движка — не удаляется
  engine.setNetworkAccessManagerFactory(new CachingNamFactory(dir, static_cast<qint64>(max_bytes)));
}

void
set_image_proxy(int mode, const QString& host, int port, const QString& user, const QString& password)
{
  QNetworkProxy manual;
  // SOCKS5 по умолчанию разрешает имена на стороне прокси (как socks5h в sf-auth)
  if (mode == 2 || mode == 3)
    manual = QNetworkProxy(mode == 3 ? QNetworkProxy::Socks5Proxy : QNetworkProxy::HttpProxy,
                           host,
                           static_cast<quint16>(port),
                           user,
                           password);
  QMutexLocker lock(&proxy_mutex);
  proxy_mode = mode;
  proxy_manual = manual;
}

bool
object_has_property(QObject* object, const QString& name)
{
  return object && object->property(name.toUtf8().constData()).isValid();
}

void
set_main_window(QObject* window)
{
  main_window = qobject_cast<QWindow*>(window);
}

void
post_raise_window()
{
  if (!QCoreApplication::instance())
    return;
  QMetaObject::invokeMethod(
    QCoreApplication::instance(),
    [] {
      if (!main_window)
        return;
      main_window->show();
      // свёрнутое окно show() не разворачивает
      if (main_window->windowStates() & Qt::WindowMinimized)
        main_window->setWindowStates(main_window->windowStates() & ~Qt::WindowMinimized);
      main_window->raise();
      main_window->requestActivate();
    },
    Qt::QueuedConnection);
}

void
post_quit()
{
  if (!QCoreApplication::instance())
    return;
  QMetaObject::invokeMethod(QCoreApplication::instance(), [] { QCoreApplication::quit(); }, Qt::QueuedConnection);
}

void
schedule_screenshot(QObject* window, const QString& path, int delay_ms)
{
  QPointer<QQuickWindow> target = qobject_cast<QQuickWindow*>(window);
  QTimer::singleShot(delay_ms, qApp, [target, path] {
    if (target && !target->grabWindow().save(path))
      qWarning("could not save screenshot %s", qPrintable(path));
    QCoreApplication::quit();
  });
}

QString
prefer_fastest_screen()
{
#if defined(Q_OS_LINUX)
  // Qt Quick берёт период vsync у primaryScreen(); на Wayland это может быть 60-герцовый монитор,
  // и анимации на 144 Гц идут по таймеру 60 Гц. Публичного API нет — экспортируемая функция
  // QWindowSystemInterface::handlePrimaryScreenChanged (её зовут платформенные плагины).
  const auto screens = QGuiApplication::screens();
  if (screens.size() < 2)
    return QStringLiteral("primary screen: single monitor");
  QScreen* primary = QGuiApplication::primaryScreen();
  QScreen* fastest = *std::max_element(
    screens.begin(), screens.end(), [](QScreen* a, QScreen* b) { return a->refreshRate() < b->refreshRate(); });
  if (fastest == primary || fastest->refreshRate() <= primary->refreshRate() + 0.5)
    return QStringLiteral("primary screen: %1 is already the fastest").arg(primary->name());

  using SetPrimary = void (*)(void*);
  auto set_primary = reinterpret_cast<SetPrimary>(
    dlsym(RTLD_DEFAULT, "_ZN22QWindowSystemInterface26handlePrimaryScreenChangedEP15QPlatformScreen"));
  if (!set_primary)
    return QStringLiteral("primary screen: could not hook into Qt (no handlePrimaryScreenChanged)");
  void* platform_screen = fastest->handle();
  if (!platform_screen)
    return QStringLiteral("primary screen: the screen has no platform object");
  const QString before =
    QStringLiteral("%1 (%2 Hz)").arg(primary->name()).arg(qRound(primary->refreshRate()));
  set_primary(platform_screen);
  QScreen* now = QGuiApplication::primaryScreen();
  return QStringLiteral("primary screen: %1 → %2 (%3 Hz)")
    .arg(before, now->name())
    .arg(qRound(now->refreshRate()));
#else
  return QStringLiteral("primary screen: refresh-rate switching is not supported on this OS");
#endif
}

QRectF
icon_measure(const QString& text, int size)
{
  if (text.isEmpty() || size <= 0)
    return {};
  QFont font(QStringLiteral("Material Symbols Rounded"));
  font.setPixelSize(size);
  font.setVariableAxis(QFont::Tag("FILL"), 1);
  font.setVariableAxis(QFont::Tag("opsz"), static_cast<float>(std::clamp(size, 20, 48)));
  const QFontMetricsF metrics(font);
  const qreal advance = metrics.horizontalAdvance(text);
  const qreal height = metrics.height();
  const int w = static_cast<int>(advance) + 8;
  const int h = static_cast<int>(height) + 8;
  QImage image(w, h, QImage::Format_Alpha8);
  image.fill(0);
  {
    QPainter painter(&image);
    painter.setFont(font);
    painter.setPen(Qt::black);
    painter.drawText(QRectF(4, 4, advance, height), Qt::AlignLeft | Qt::AlignTop, text);
  }

  constexpr uchar threshold = 96;
  int top = -1, bottom = -1, left = -1, right = -1;
  for (int y = 0; y < h; ++y) {
    const uchar* row = image.constScanLine(y);
    int first = -1, last = -1;
    for (int x = 0; x < w; ++x) {
      if (row[x] > threshold) {
        if (first < 0)
          first = x;
        last = x;
      }
    }
    if (first < 0)
      continue;
    if (top < 0)
      top = y;
    bottom = y;
    left = left < 0 ? first : std::min(left, first);
    right = right < 0 ? last : std::max(right, last);
  }
  if (top < 0)
    return {};
  const qreal cx = (left + right + 1) / 2.0 - (4 + advance / 2);
  const qreal cy = (top + bottom + 1) / 2.0 - (4 + height / 2);
  return QRectF(cx, cy, right - left + 1, bottom - top + 1);
}

} // namespace mf
