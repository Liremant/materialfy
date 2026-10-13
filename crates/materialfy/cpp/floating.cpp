// Плеер вне главного окна: островок у верхнего края экрана (FloatingIsland.qml) и виджет в панели задач
// Windows (TaskbarPlayer.qml). Окна создаёт QML, здесь — то, чего из QML не сделать: стиль окна Win32,
// маска ввода, встраивание в Shell_TrayWnd.
//
// Панель задач: окно становится дочерним Shell_TrayWnd (через QWindow::fromWinId + setParent — Qt сам
// ставит WS_CHILD вместо WS_POPUP и знает, что окно дочернее: координаты мыши и mapToGlobal верны) и встаёт
// слева от области уведомлений (TrayNotifyWnd). Окно другого процесса как родитель — законно, но Explorer при
// перезапуске уносит дочерние окна с собой: тогда floating_taskbar_place отвечает -1, и QML создаёт окно заново.
// Не встроилось (нет прав, другая оболочка) — окно поверх всех над панелью, место — из ABM_GETTASKBARPOS.
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
#include <dwmapi.h>
#include <shellapi.h>

#include <QtCore/QPointer>

#include <cmath>

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

int
px(double logical, double scale)
{
  return static_cast<int>(std::lround(logical * scale));
}

} // namespace

bool
floating_tool_window(QObject* object)
{
  auto* window = qobject_cast<QWindow*>(object);
  if (!window)
    return false;
  auto hwnd = reinterpret_cast<HWND>(window->winId());
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
  // Форму рисует QML (скруглены только нижние углы); Windows 11 не скругляет окно сам и не прячет его при Aero Peek
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
floating_taskbar_place(QObject* object, int width, bool embed)
{
  auto* window = qobject_cast<QWindow*>(object);
  if (!window)
    return 0;
  auto hwnd = reinterpret_cast<HWND>(window->winId());
  if (!hwnd || !IsWindow(hwnd)) {
    // HWND ушёл вместе со старой панелью: окно — сиротой, чтобы удаление обёртки его не задело
    release_host(window);
    return -1;
  }

  HWND tray = FindWindowW(L"Shell_TrayWnd", nullptr);
  RECT bar{};
  if (!tray || !GetWindowRect(tray, &bar)) {
    // Explorer перезапускается — панели пока нет
    release_host(window);
    return 0;
  }
  // Сторона экрана — из ABM_GETTASKBARPOS (у скрытой панели прямоугольник окна почти весь за краем)
  APPBARDATA appbar{};
  appbar.cbSize = sizeof(appbar);
  const bool horizontal = SHAppBarMessage(ABM_GETTASKBARPOS, &appbar)
    ? appbar.uEdge == ABE_TOP || appbar.uEdge == ABE_BOTTOM
    : bar.right - bar.left > bar.bottom - bar.top;
  if (!horizontal) {
    // в вертикальную панель (Windows 10) виджет в 240 px не влезает
    release_host(window);
    return 0;
  }

  UINT dpi = GetDpiForWindow(tray);
  const double scale = (dpi ? dpi : 96) / 96.0;
  // Правый край — левее области уведомлений; нет её — примерно её ширина от правого края
  LONG right = bar.right - px(200, scale);
  RECT notify{};
  HWND notify_wnd = FindWindowExW(tray, nullptr, L"TrayNotifyWnd", nullptr);
  if (notify_wnd && GetWindowRect(notify_wnd, &notify) && notify.right > notify.left && notify.left > bar.left)
    right = notify.left;
  right -= px(8, scale);
  const int margin = px(4, scale);
  const int w = px(width, scale);
  const int h = (bar.bottom - bar.top) - 2 * margin;
  RECT slot{ right - w, bar.top + margin, right, bar.top + margin + h };
  if (h <= 0 || slot.left < bar.left + px(160, scale)) {
    // узкий экран: виджет залез бы на «Пуск» и значки
    release_host(window);
    return 0;
  }

  if (embed && GetParent(hwnd) != tray) {
    QWindow* old = tray_host.data();
    QWindow* next = QWindow::fromWinId(reinterpret_cast<WId>(tray));
    if (next) {
      window->setParent(next);
      tray_host = next;
    }
    if (old && old != next)
      delete old;
  }
  if (embed && GetParent(hwnd) == tray) {
    POINT origin{ slot.left, slot.top };
    ScreenToClient(tray, &origin);
    // HWND_TOP — над содержимым панели (XAML-мостом Windows 11), иначе окно под ним не видно
    SetWindowPos(hwnd, HWND_TOP, origin.x, origin.y, w, h, SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    return 1;
  }

  // Запасной вариант: окно поверх всех там же, над панелью (её саму поднимает каждый клик по ней —
  // TOPMOST ставится заново при каждом вызове)
  release_host(window);
  RECT area = bar;
  if (SHAppBarMessage(ABM_GETTASKBARPOS, &appbar))
    area = appbar.rc;
  const int dy = area.top - bar.top;
  SetWindowPos(hwnd, HWND_TOPMOST, slot.left, slot.top + dy, w, h, SWP_NOACTIVATE | SWP_NOOWNERZORDER);
  return 2;
}

void
floating_taskbar_detach(QObject* object)
{
  release_host(qobject_cast<QWindow*>(object));
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
floating_taskbar_place(QObject* window, int width, bool embed)
{
  (void)window;
  (void)width;
  (void)embed;
  return 0;
}

void
floating_taskbar_detach(QObject* window)
{
  (void)window;
}

} // namespace mf

#endif
