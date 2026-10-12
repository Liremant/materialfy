// Кнопки воспроизведения под эскизом окна на панели задач Windows (issue #2). Владелец — агент «shell».
// ITaskbarList3::ThumbBarAddButtons на HWND главного окна; нажатие приходит в окно как WM_COMMAND с
// HIWORD(wParam) = THBN_CLICKED — ловит фильтр нативных событий. Состояние — из синглтона Player
// (играет → «Пауза», нет трека → кнопки неактивны), подписи — Translations.tr (mf_i18n), глифы — шрифт
// Material Symbols, светлые на тёмной панели задач и тёмные на светлой. Explorer пересоздаёт кнопку окна
// (перезапуск, окно снова показано из трея) — шлёт «TaskbarButtonCreated», тогда кнопки добавляются заново.
#include "taskbar.h"

#if defined(_WIN32)

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shobjidl.h>

#include <QtCore/QAbstractNativeEventFilter>
#include <QtCore/QByteArray>
#include <QtCore/QCoreApplication>
#include <QtCore/QPointer>
#include <QtGui/QColor>
#include <QtGui/QFont>
#include <QtGui/QGuiApplication>
#include <QtGui/QImage>
#include <QtGui/QPainter>
#include <QtGui/QPainterPath>
#include <QtGui/QWindow>
#include <QtQml/QQmlEngine>

#include <algorithm>
#include <array>
#include <cmath>
#include <cwchar>
#include <string>
#include <utility>

#include "materialfy/src/bridges/player.cxxqt.h"
#include "materialfy/src/bridges/translations.cxxqt.h"

namespace mf {

namespace {

enum Button : UINT
{
  Previous = 1,
  PlayPause = 2,
  Next = 3,
};

// Кодовые точки Material Symbols (assets/fonts/icons.json; шрифт урезан, эти глифы в нём есть — плеер ими пользуется)
constexpr char16_t glyph_previous = 0xE045; // skip_previous
constexpr char16_t glyph_play = 0xE037;     // play_arrow
constexpr char16_t glyph_pause = 0xE034;    // pause
constexpr char16_t glyph_next = 0xE044;     // skip_next

// Панель задач светлая (Параметры → Персонализация → Цвета → «Режим Windows»)
bool
taskbar_light()
{
  DWORD value = 0;
  DWORD size = sizeof(value);
  const LSTATUS status = RegGetValueW(HKEY_CURRENT_USER,
                                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                                      L"SystemUsesLightTheme",
                                      RRF_RT_REG_DWORD,
                                      nullptr,
                                      &value,
                                      &size);
  return status == ERROR_SUCCESS && value != 0;
}

// Залитый глиф по центру квадрата size×size (по контуру, а не по ячейке шрифта)
HICON
make_icon(char16_t code, int size, const QColor& color)
{
  QImage image(size, size, QImage::Format_ARGB32_Premultiplied);
  image.fill(Qt::transparent);
  QFont font(QStringLiteral("Material Symbols Rounded"));
  // Глифы нарисованы в сетке 24 с полями: play_arrow ~14/24 по высоте — так он занимает ~3/4 значка
  font.setPixelSize(std::max(8, static_cast<int>(std::lround(size * 1.25))));
  font.setVariableAxis(QFont::Tag("FILL"), 1.0f);
  font.setVariableAxis(QFont::Tag("opsz"), 20.0f);
  QPainterPath path;
  path.addText(0, 0, font, QString(QChar(code)));
  const QRectF ink = path.boundingRect();
  if (!ink.isEmpty()) {
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.translate(std::round((size - ink.width()) / 2 - ink.left()), std::round((size - ink.height()) / 2 - ink.top()));
    painter.fillPath(path, color);
  }
  return image.toHICON();
}

class ThumbBar : public QAbstractNativeEventFilter
{
public:
  ThumbBar(HWND hwnd, Player* player, Translations* translations)
    : m_hwnd(hwnd)
    , m_player(player)
    , m_translations(translations)
    , m_created(RegisterWindowMessageW(L"TaskbarButtonCreated"))
  {
    // Окно с повышенными правами иначе не получит сообщения от Explorer
    ChangeWindowMessageFilterEx(m_hwnd, m_created, MSGFLT_ALLOW, nullptr);
    ChangeWindowMessageFilterEx(m_hwnd, WM_COMMAND, MSGFLT_ALLOW, nullptr);

    auto* context = QCoreApplication::instance();
    const auto refresh = [this] { update(); };
    QObject::connect(player, &Player::stateChanged, context, refresh);
    QObject::connect(player, &Player::trackChanged, context, refresh);
    if (translations)
      QObject::connect(translations, &Translations::languageChanged, context, refresh);
    // Кнопка окна на панели задач уже могла появиться (окно показано до установки фильтра) —
    // тогда TaskbarButtonCreated не придёт; не появилась — добавление не удастся и повторится по нему
    add();
  }

  bool nativeEventFilter(const QByteArray& type, void* message, qintptr* result) override
  {
    if (type != "windows_generic_MSG")
      return false;
    auto* msg = static_cast<MSG*>(message);
    if (msg->hwnd != m_hwnd)
      return false;
    if (msg->message == m_created && m_created) {
      // Новая кнопка (Explorer перезапущен, окно снова показано) — старый объект и кнопки недействительны
      reset();
      add();
      return false;
    }
    switch (msg->message) {
      case WM_COMMAND:
        if (HIWORD(msg->wParam) != THBN_CLICKED)
          return false;
        clicked(LOWORD(msg->wParam));
        // result бывает нулевым (Qt передаёт так сообщения, пришедшие не через оконную процедуру)
        if (result)
          *result = 0;
        return true;
      case WM_SETTINGCHANGE:
        // Сменилась тема Windows (светлая / тёмная панель задач) — перерисовать глифы
        if (msg->lParam && std::wcscmp(reinterpret_cast<const wchar_t*>(msg->lParam), L"ImmersiveColorSet") == 0) {
          QMetaObject::invokeMethod(QCoreApplication::instance(), [this] { update(true); }, Qt::QueuedConnection);
        }
        return false;
      case WM_DPICHANGED:
      case WM_DISPLAYCHANGE:
        QMetaObject::invokeMethod(QCoreApplication::instance(), [this] { update(true); }, Qt::QueuedConnection);
        return false;
      default:
        return false;
    }
  }

private:
  void clicked(UINT id) const
  {
    if (!m_player || !m_player->getHasTrack())
      return;
    switch (id) {
      case Previous:
        m_player->previous();
        break;
      case PlayPause:
        m_player->togglePlay();
        break;
      case Next:
        m_player->next();
        break;
      default:
        break;
    }
  }

  void reset()
  {
    if (m_list)
      m_list->Release();
    m_list = nullptr;
    m_added = false;
  }

  bool ensure_list()
  {
    if (m_list)
      return true;
    ITaskbarList3* list = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list))))
      return false;
    if (FAILED(list->HrInit())) {
      list->Release();
      return false;
    }
    m_list = list;
    return true;
  }

  // Значки под текущий размер (SM_CXSMICON при DPI панели задач) и цвет панели задач
  void ensure_icons(bool force)
  {
    const int size = GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForSystem());
    const bool light = taskbar_light();
    if (!force && size == m_icon_size && light == m_light && m_icons[0])
      return;
    // Старые значки живут до следующего ThumbBarUpdateButtons (панель задач могла ещё не забрать копию)
    drop_old_icons();
    m_old_icons = m_icons;
    m_icon_size = size;
    m_light = light;
    const QColor color = light ? QColor(0x1f, 0x1f, 0x1f) : QColor(Qt::white);
    m_icons = { make_icon(glyph_previous, size, color),
                make_icon(glyph_play, size, color),
                make_icon(glyph_pause, size, color),
                make_icon(glyph_next, size, color) };
  }

  void drop_old_icons()
  {
    for (HICON& icon : m_old_icons) {
      if (icon)
        DestroyIcon(icon);
      icon = nullptr;
    }
  }

  QString tr(const char* text) const
  {
    const QString en = QString::fromUtf8(text);
    return m_translations ? m_translations->tr(en) : en;
  }

  std::array<THUMBBUTTON, 3> buttons()
  {
    const bool enabled = m_player && m_player->getHasTrack();
    const bool playing = m_player && m_player->getPlaying();
    // Подписи — те же, что в меню значка в трее (Main.qml)
    const std::array<std::pair<HICON, QString>, 3> spec{ {
      { m_icons[0], tr("Previous track") },
      { playing ? m_icons[2] : m_icons[1], playing ? tr("Pause") : tr("Resume") },
      { m_icons[3], tr("Next track") },
    } };
    std::array<THUMBBUTTON, 3> out{};
    for (size_t i = 0; i < out.size(); ++i) {
      THUMBBUTTON& b = out[i];
      b.dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
      b.iId = static_cast<UINT>(Previous + i);
      b.hIcon = spec[i].first;
      const std::wstring tip = spec[i].second.toStdWString();
      wcsncpy_s(b.szTip, tip.c_str(), _TRUNCATE);
      b.dwFlags = enabled ? THBF_ENABLED : THBF_DISABLED;
    }
    return out;
  }

  void add()
  {
    if (!ensure_list())
      return;
    ensure_icons(false);
    auto list = buttons();
    // Кнопки на окне уже есть (второй вызов без пересоздания кнопки окна) — Add вернёт ошибку, обновляем их
    m_added = SUCCEEDED(m_list->ThumbBarAddButtons(m_hwnd, static_cast<UINT>(list.size()), list.data()))
              || SUCCEEDED(m_list->ThumbBarUpdateButtons(m_hwnd, static_cast<UINT>(list.size()), list.data()));
    if (m_added)
      drop_old_icons();
  }

  void update(bool restyle = false)
  {
    if (!m_added) {
      add();
      return;
    }
    ensure_icons(restyle);
    auto list = buttons();
    if (SUCCEEDED(m_list->ThumbBarUpdateButtons(m_hwnd, static_cast<UINT>(list.size()), list.data())))
      drop_old_icons();
  }

  HWND m_hwnd;
  QPointer<Player> m_player;
  QPointer<Translations> m_translations;
  UINT m_created;
  ITaskbarList3* m_list = nullptr;
  bool m_added = false;
  // previous, play, pause, next
  std::array<HICON, 4> m_icons{};
  std::array<HICON, 4> m_old_icons{};
  int m_icon_size = 0;
  bool m_light = false;
};

} // namespace

bool
taskbar_install(QObject* object)
{
  auto* window = qobject_cast<QWindow*>(object);
  if (!window)
    return false;
  auto hwnd = reinterpret_cast<HWND>(window->winId());
  QQmlEngine* engine = qmlEngine(object);
  if (!hwnd || !engine)
    return false;
  auto* player = engine->singletonInstance<Player*>("Materialfy.Core", "Player");
  if (!player)
    return false;
  auto* translations = engine->singletonInstance<Translations*>("Materialfy.Core", "Translations");
  // Живёт до конца процесса (окно главное)
  QGuiApplication::instance()->installNativeEventFilter(new ThumbBar(hwnd, player, translations));
  return true;
}

} // namespace mf

#else

namespace mf {

bool
taskbar_install(QObject* window)
{
  (void)window;
  return false;
}

} // namespace mf

#endif
