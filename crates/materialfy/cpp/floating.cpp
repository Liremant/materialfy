// Плеер вне главного окна: островок у верхнего края экрана (FloatingIsland.qml) и виджет в панели задач
// Windows (TaskbarPlayer.qml). Окна создаёт QML, здесь — то, чего из QML не сделать: стиль окна Win32,
// маска ввода, встраивание в Shell_TrayWnd, клавиши без фокуса.
//
// Панель задач: окно становится дочерним Shell_TrayWnd (через QWindow::fromWinId + setParent — Qt сам
// ставит WS_CHILD вместо WS_POPUP и знает, что окно дочернее: координаты мыши и mapToGlobal верны). Место —
// у области уведомлений (TrayNotifyWnd), у левого края или у значков приложений: их границы — из UI Automation
// (кнопки Windows 11 нарисованы XAML, своих окон у них нет). Окно другого процесса как родитель — законно, но
// Explorer при перезапуске уносит дочерние окна с собой: тогда floating_taskbar_place отвечает -1, и QML создаёт
// окно заново. Не встроилось (нет прав, другая оболочка) — окно поверх всех над панелью.
#include "floating.h"

#include <QtGui/QRegion>
#include <QtGui/QWindow>

namespace mf {

void
floating_set_mask(QObject* object, int x, int y, int w, int h)
{
  auto* window = qobject_cast<QWindow*>(object);
  if (!window)
    return;
  // Qt переводит маску в физические пиксели сам: Windows — SetWindowRgn, X11 — XShape (ввод и отрисовка)
  window->setMask(w > 0 && h > 0 ? QRegion(x, y, w, h) : QRegion());
}

} // namespace mf

#if defined(_WIN32)

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <objbase.h>
#include <UIAutomation.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <wrl/client.h>

#include <QtCore/QMetaObject>
#include <QtCore/QPointer>
#include <QtCore/QVariant>
#include <QtGui/QGuiApplication>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <string>
#include <utility>

using Microsoft::WRL::ComPtr;

namespace mf {

namespace {

// Обёртка Qt над Shell_TrayWnd — родитель встроенного окна. Одна: виджет в панели задач один.
QPointer<QWindow> tray_host;

// Отпустить родителя: сначала окно — сиротой (удаление обёртки удалило бы и её дочерние QWindow), потом обёртку
void
release_host(QWindow* window)
{
  if (window && window->parent())
    window->setParent(nullptr);
  delete tray_host.data();
}

// HWND окна — только у платформы windows: у offscreen (снимки) winId — просто счётчик, не дескриптор
HWND
native(QWindow* window)
{
  if (!window || QGuiApplication::platformName() != QLatin1String("windows"))
    return nullptr;
  return reinterpret_cast<HWND>(window->winId());
}

int
px(double logical, double scale)
{
  return static_cast<int>(std::lround(logical * scale));
}

// ---- Панель задач и места на ней (физические пиксели экрана) ----

struct Bar
{
  HWND tray = nullptr;
  RECT rect{};
  double scale = 1;
  LONG notify_left = 0; // левый край области уведомлений
};

// true — есть горизонтальная панель
bool
read_bar(Bar& bar)
{
  // MATERIALFY_TASKBAR_CLASS — класс окна-панели вместо Shell_TrayWnd: проверка перезапуска Explorer на окне-подделке
  static const std::wstring tray_class =
    qEnvironmentVariable("MATERIALFY_TASKBAR_CLASS", QStringLiteral("Shell_TrayWnd")).toStdWString();
  bar.tray = FindWindowW(tray_class.c_str(), nullptr);
  if (!bar.tray || !GetWindowRect(bar.tray, &bar.rect))
    return false; // Explorer перезапускается — панели пока нет
  // Сторона экрана — из ABM_GETTASKBARPOS (у скрытой панели прямоугольник окна почти весь за краем)
  APPBARDATA appbar{};
  appbar.cbSize = sizeof(appbar);
  const bool horizontal = SHAppBarMessage(ABM_GETTASKBARPOS, &appbar)
    ? appbar.uEdge == ABE_TOP || appbar.uEdge == ABE_BOTTOM
    : bar.rect.right - bar.rect.left > bar.rect.bottom - bar.rect.top;
  if (!horizontal)
    return false; // в вертикальную панель (Windows 10) виджет не влезает
  const UINT dpi = GetDpiForWindow(bar.tray);
  bar.scale = (dpi ? dpi : 96) / 96.0;
  // Нет области уведомлений — примерно её ширина от правого края
  bar.notify_left = bar.rect.right - px(200, bar.scale);
  RECT notify{};
  HWND notify_wnd = FindWindowExW(bar.tray, nullptr, L"TrayNotifyWnd", nullptr);
  if (notify_wnd && GetWindowRect(notify_wnd, &notify) && notify.right > notify.left && notify.left > bar.rect.left)
    bar.notify_left = notify.left;
  return true;
}

// Кнопки панели через UI Automation: «Пуск», поиск, представление задач и значки приложений — одна группа
// (по центру или слева), «Виджеты» (погода) — слева от неё. false — UIA нет или кнопок не нашлось.
bool
taskbar_buttons(HWND tray, RECT& apps, RECT& widgets)
{
  static ComPtr<IUIAutomation> uia;
  if (!uia) {
    // Qt уже инициализировал COM в GUI-потоке (OLE для перетаскивания); второй вызов безвреден
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&uia))))
      return false;
  }
  ComPtr<IUIAutomationElement> root;
  if (FAILED(uia->ElementFromHandle(tray, &root)) || !root)
    return false;
  VARIANT button{};
  button.vt = VT_I4;
  button.lVal = UIA_ButtonControlTypeId;
  ComPtr<IUIAutomationCondition> condition;
  if (FAILED(uia->CreatePropertyCondition(UIA_ControlTypePropertyId, button, &condition)))
    return false;
  ComPtr<IUIAutomationElementArray> found;
  if (FAILED(root->FindAll(TreeScope_Descendants, condition.Get(), &found)) || !found)
    return false;
  int count = 0;
  found->get_Length(&count);
  bool any = false;
  widgets = RECT{};
  for (int i = 0; i < count; ++i) {
    ComPtr<IUIAutomationElement> element;
    if (FAILED(found->GetElement(i, &element)) || !element)
      continue;
    BSTR id = nullptr;
    BSTR cls = nullptr;
    element->get_CurrentAutomationId(&id);
    element->get_CurrentClassName(&cls);
    const std::wstring automation_id = id ? id : L"";
    const std::wstring class_name = cls ? cls : L"";
    SysFreeString(id);
    SysFreeString(cls);
    RECT r{};
    if (FAILED(element->get_CurrentBoundingRectangle(&r)) || r.right <= r.left)
      continue;
    if (automation_id == L"WidgetsButton") {
      widgets = r;
    } else if (automation_id == L"StartButton" || automation_id == L"SearchButton" || automation_id == L"TaskViewButton"
               || class_name == L"Taskbar.TaskListButtonAutomationPeer" || class_name.find(L"SearchBox") != std::wstring::npos) {
      if (!any)
        apps = r;
      apps.left = std::min(apps.left, r.left);
      apps.right = std::max(apps.right, r.right);
      any = true;
    }
  }
  return any;
}

// Места для левого края окна шириной w: «left», «appsLeft», «appsRight», «tray» и свободный отрезок [lo, hi]
struct Places
{
  LONG lo = 0;
  LONG hi = 0;
  std::array<std::pair<const char*, LONG>, 4> anchors{};
};

Places
places(const Bar& bar, int w, bool with_buttons)
{
  const LONG gap = px(8, bar.scale);
  Places p;
  p.lo = bar.rect.left + gap;
  p.hi = bar.notify_left - gap - w;
  const LONG center = (bar.rect.left + bar.rect.right) / 2;
  RECT apps{ center - px(240, bar.scale), 0, center + px(240, bar.scale), 0 }; // без UIA — примерно
  RECT widgets{};
  const bool found = with_buttons && taskbar_buttons(bar.tray, apps, widgets);
  if (found && widgets.right > widgets.left && widgets.right < apps.left)
    p.lo = std::max(p.lo, widgets.right + gap);
  LONG left = p.lo;
  // значки слева (не по центру): «после Пуска и поиска» — сразу за группой
  if (found && apps.left - p.lo < w + gap)
    left = apps.right + gap;
  auto clamp = [&](LONG x) { return std::max(p.lo, std::min(x, p.hi)); };
  p.anchors = { { { "left", clamp(left) },
                  { "appsLeft", clamp(apps.left - gap - w) },
                  { "appsRight", clamp(apps.right + gap) },
                  { "tray", p.hi } } };
  return p;
}

LONG
position_x(const Places& p, const QString& pos)
{
  for (const auto& [name, x] : p.anchors)
    if (pos == QLatin1String(name))
      return x;
  bool ok = false;
  const double f = pos.toDouble(&ok);
  if (!ok || !std::isfinite(f))
    return p.hi;
  return p.lo + static_cast<LONG>(std::lround(std::clamp(f, 0.0, 1.0) * (p.hi - p.lo)));
}

// Окно — встроенным (координаты панели) или поверх всех (координаты экрана) на месте x, по центру панели
int
move_window(QWindow* window, HWND hwnd, const Bar& bar, bool embed, LONG x, int w, int h)
{
  const LONG y = (bar.rect.top + bar.rect.bottom - h) / 2;
  if (embed && GetParent(hwnd) != bar.tray) {
    QWindow* old = tray_host.data();
    QWindow* next = QWindow::fromWinId(reinterpret_cast<WId>(bar.tray));
    if (next) {
      window->setParent(next);
      tray_host = next;
    }
    if (old && old != next)
      delete old;
  }
  if (embed && GetParent(hwnd) == bar.tray) {
    POINT origin{ x, y };
    ScreenToClient(bar.tray, &origin);
    // HWND_TOP — над содержимым панели (XAML-мостом Windows 11), иначе окно под ним не видно
    SetWindowPos(hwnd, HWND_TOP, origin.x, origin.y, w, h, SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    return 1;
  }
  // Запасной вариант: окно поверх всех там же, над панелью (её саму поднимает каждый клик по ней —
  // TOPMOST ставится заново при каждом вызове)
  release_host(window);
  SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_NOOWNERZORDER);
  return 2;
}

int
size_h(const Bar& bar, int height)
{
  return std::min(px(height, bar.scale), static_cast<int>(bar.rect.bottom - bar.rect.top) - 2 * px(4, bar.scale));
}

// Перетаскивание: где схватили (от левого края окна) и места на панели — на всё время перетаскивания
struct Drag
{
  LONG grab = 0;
  Places places;
  bool embed = true;
} drag;

// ---- Клавиши без фокуса ----

HHOOK key_hook = nullptr;
QPointer<QWindow> key_window;
HWND key_hwnd = nullptr;
std::array<bool, 6> key_down{}; // нажатия, которые мы забрали: их отпускание тоже не отдаём

int
key_code(DWORD vk)
{
  switch (vk) {
    case VK_LEFT: return 1;
    case VK_RIGHT: return 2;
    case VK_UP: return 3;
    case VK_DOWN: return 4;
    case VK_SPACE: return 5;
    default: return 0;
  }
}

bool
cursor_over_key_window()
{
  POINT p{};
  if (!key_hwnd || !GetCursorPos(&p))
    return false;
  HWND under = WindowFromPoint(p); // учитывает маску окна: прозрачная часть островка — не наша
  return under == key_hwnd || IsChild(key_hwnd, under);
}

LRESULT CALLBACK
key_proc(int code, WPARAM wparam, LPARAM lparam)
{
  if (code == HC_ACTION) {
    const auto* key = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    const int k = key_code(key->vkCode);
    const bool down = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
    if (k && !down && key_down[k]) {
      key_down[k] = false;
      return 1;
    }
    const auto held = [](int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; };
    if (k && down && key_window && !(key->flags & LLKHF_INJECTED) && !held(VK_CONTROL) && !held(VK_MENU)
        && !held(VK_LWIN) && !held(VK_RWIN) && cursor_over_key_window()) {
      // Автоповтор: громкость идёт шагами дальше, трек и пауза — один раз на нажатие
      const bool repeat = key_down[k];
      key_down[k] = true;
      if (!repeat || k == 3 || k == 4)
        QMetaObject::invokeMethod(key_window.data(), "floatingKey", Qt::QueuedConnection, Q_ARG(QVariant, QVariant(k)));
      return 1;
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

} // namespace

bool
floating_tool_window(QObject* object)
{
  HWND hwnd = native(qobject_cast<QWindow*>(object));
  if (!hwnd)
    return false;
  // Qt ставит то же по флагам Tool и WindowDoesNotAcceptFocus; здесь — наверняка: без WS_EX_APPWINDOW окна нет
  // ни в панели задач, ни в Alt+Tab, с WS_EX_NOACTIVATE клик по нему не уводит фокус у окна, где печатают
  const LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  const LONG_PTR want = (ex | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) & ~LONG_PTR(WS_EX_APPWINDOW);
  if (want != ex) {
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, want);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }
  // Форму рисует QML; Windows 11 не скругляет окно сам и не прячет его при Aero Peek
  constexpr DWORD corner_preference = 33; // DWMWA_WINDOW_CORNER_PREFERENCE
  const int corners = 1;                  // DWMWCP_DONOTROUND
  DwmSetWindowAttribute(hwnd, corner_preference, &corners, sizeof(corners));
  const BOOL exclude = TRUE;
  DwmSetWindowAttribute(hwnd, DWMWA_EXCLUDED_FROM_PEEK, &exclude, sizeof(exclude));
  return true;
}

bool
floating_fullscreen_busy()
{
  QUERY_USER_NOTIFICATION_STATE state{};
  if (FAILED(SHQueryUserNotificationState(&state)))
    return false;
  return state == QUNS_BUSY || state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE;
}

int
floating_taskbar_place(QObject* object, int width, int height, bool embed, const QString& pos)
{
  auto* window = qobject_cast<QWindow*>(object);
  HWND hwnd = native(window);
  if (!hwnd)
    return 0;
  if (!IsWindow(hwnd)) {
    // HWND ушёл вместе со старой панелью: окно — сиротой, чтобы удаление обёртки его не задело
    release_host(window);
    return -1;
  }
  Bar bar;
  if (!read_bar(bar)) {
    release_host(window);
    return 0;
  }
  const int w = px(width, bar.scale);
  const int h = size_h(bar, height);
  // кнопки панели нужны только местам у значков и у левого края — у трея хватает TrayNotifyWnd
  const Places p = places(bar, w, pos != QLatin1String("tray"));
  if (h <= 0 || p.hi < p.lo) {
    // узкий экран: виджет залез бы на «Пуск» и значки
    release_host(window);
    return 0;
  }
  return move_window(window, hwnd, bar, embed, position_x(p, pos), w, h);
}

QString
floating_taskbar_drag(QObject* object, int width, int height, int phase)
{
  auto* window = qobject_cast<QWindow*>(object);
  HWND hwnd = native(window);
  Bar bar;
  POINT cursor{};
  RECT now{};
  if (!hwnd || !IsWindow(hwnd) || !read_bar(bar) || !GetCursorPos(&cursor) || !GetWindowRect(hwnd, &now))
    return {};
  const int w = px(width, bar.scale);
  if (phase == 0) {
    drag.grab = cursor.x - now.left;
    drag.places = places(bar, w, true);
    drag.embed = GetParent(hwnd) == bar.tray;
  }
  const Places& p = drag.places;
  if (p.hi < p.lo)
    return {};
  LONG x = std::max(p.lo, std::min(cursor.x - drag.grab, p.hi));
  QString pos;
  const LONG snap = px(24, bar.scale);
  LONG best = snap + 1;
  for (const auto& [name, ax] : p.anchors) {
    if (std::abs(x - ax) <= snap && std::abs(x - ax) < best) {
      best = std::abs(x - ax);
      pos = QString::fromLatin1(name);
    }
  }
  if (!pos.isEmpty())
    x = position_x(p, pos);
  else
    pos = QString::number(p.hi > p.lo ? double(x - p.lo) / double(p.hi - p.lo) : 1.0, 'f', 4);
  move_window(window, hwnd, bar, drag.embed, x, w, size_h(bar, height));
  return pos;
}

void
floating_taskbar_detach(QObject* object)
{
  release_host(qobject_cast<QWindow*>(object));
}

bool
floating_key_hook(QObject* object, bool on)
{
  auto* window = qobject_cast<QWindow*>(object);
  if (!on) {
    // снимает только своё окно: островок и виджет могли смениться местами
    if (key_hook && (!window || window == key_window.data() || !key_window)) {
      UnhookWindowsHookEx(key_hook);
      key_hook = nullptr;
      key_window = nullptr;
      key_hwnd = nullptr;
      key_down = {};
    }
    return true;
  }
  HWND hwnd = native(window);
  if (!hwnd)
    return false;
  key_window = window;
  key_hwnd = hwnd;
  if (!key_hook)
    key_hook = SetWindowsHookExW(WH_KEYBOARD_LL, key_proc, GetModuleHandleW(nullptr), 0);
  return key_hook != nullptr;
}

} // namespace mf

#else

namespace mf {

bool
floating_tool_window(QObject* window)
{
  (void)window;
  return false;
}

bool
floating_fullscreen_busy()
{
  return false;
}

int
floating_taskbar_place(QObject* window, int width, int height, bool embed, const QString& pos)
{
  (void)window;
  (void)width;
  (void)height;
  (void)embed;
  (void)pos;
  return 0;
}

QString
floating_taskbar_drag(QObject* window, int width, int height, int phase)
{
  (void)window;
  (void)width;
  (void)height;
  (void)phase;
  return {};
}

void
floating_taskbar_detach(QObject* window)
{
  (void)window;
}

bool
floating_key_hook(QObject* window, bool on)
{
  (void)window;
  (void)on;
  return false;
}

} // namespace mf

#endif
