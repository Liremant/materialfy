// Нативная рамка окна без хрома на Windows (WM_NCCALCSIZE + WM_NCHITTEST). Владелец — агент «shell».
// Стиль окна получает WS_THICKFRAME и компанию обратно (Qt снял их из-за FramelessWindowHint):
// плавный нативный ресайз, Aero Snap, Win+стрелки, анимации, тень DWM. Хром Windows не рисует —
// вся площадь клиентская. Перетаскивание — в QML (TopBar → startSystemMove, ему нужен WS_SYSMENU),
// HTCAPTION не возвращаем: в той же полосе живут сайдбар и кнопки.
#include "winframe.h"

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
#include <windowsx.h>

#include <QtCore/QAbstractNativeEventFilter>
#include <QtCore/QByteArray>
#include <QtCore/QCoreApplication>
#include <QtCore/QMetaObject>
#include <QtCore/QPointer>
#include <QtGui/QGuiApplication>
#include <QtGui/QWindow>

#include <algorithm>

namespace mf {

namespace {

// WS_THICKFRAME и компания: нативный ресайз, Aero Snap, Win+стрелки, анимации
void
apply_frame_style(HWND hwnd)
{
  const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
  const LONG_PTR want = style | WS_THICKFRAME | WS_CAPTION | WS_MAXIMIZEBOX | WS_MINIMIZEBOX | WS_SYSMENU;
  if (want == style)
    return;
  SetWindowLongPtrW(hwnd, GWL_STYLE, want);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

bool
taskbar_autohide()
{
  APPBARDATA data{};
  data.cbSize = sizeof(data);
  return (SHAppBarMessage(ABM_GETSTATE, &data) & ABS_AUTOHIDE) != 0;
}

class FrameFilter : public QAbstractNativeEventFilter
{
public:
  FrameFilter(QWindow* window, HWND hwnd, int grip)
    : m_window(window)
    , m_hwnd(hwnd)
    , m_grip(grip)
  {
  }

  bool nativeEventFilter(const QByteArray& type, void* message, qintptr* result) override
  {
    if (type != "windows_generic_MSG")
      return false;
    auto* msg = static_cast<MSG*>(message);
    if (msg->hwnd != m_hwnd)
      return false;
    switch (msg->message) {
      case WM_NCCALCSIZE:
        if (!msg->wParam)
          return false;
        if (IsZoomed(m_hwnd))
          fit_maximized(reinterpret_cast<NCCALCSIZE_PARAMS*>(msg->lParam)->rgrc[0]);
        *result = 0;
        return true;
      case WM_NCHITTEST:
        *result = hit_test(GET_X_LPARAM(msg->lParam), GET_Y_LPARAM(msg->lParam));
        return true;
      case WM_STYLECHANGED:
        // Qt пересчитывает стиль из флагов окна (например, «поверх всех окон») и снимает WS_THICKFRAME —
        // возвращаем после того, как Qt закончит
        if (msg->wParam == static_cast<WPARAM>(GWL_STYLE)
            && !(reinterpret_cast<const STYLESTRUCT*>(msg->lParam)->styleNew & WS_THICKFRAME)) {
          QMetaObject::invokeMethod(
            QCoreApplication::instance(), [hwnd = m_hwnd] { apply_frame_style(hwnd); }, Qt::QueuedConnection);
        }
        return false;
      default:
        return false;
    }
  }

private:
  // Развёрнутое окно со WS_THICKFRAME Windows кладёт за края монитора на толщину рамки — обрезаем
  // клиентскую область по рабочей области монитора (если Qt уже ограничил окно ею, ничего не меняется).
  void fit_maximized(RECT& rect) const
  {
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(MonitorFromWindow(m_hwnd, MONITOR_DEFAULTTONEAREST), &info))
      return;
    RECT work = info.rcWork;
    // Панель задач с автоскрытием не выезжает над окном во весь монитор — оставляем ей 1 px
    if (EqualRect(&info.rcWork, &info.rcMonitor) && taskbar_autohide())
      work.bottom -= 1;
    rect.left = std::max(rect.left, work.left);
    rect.top = std::max(rect.top, work.top);
    rect.right = std::min(rect.right, work.right);
    rect.bottom = std::min(rect.bottom, work.bottom);
  }

  LRESULT hit_test(int x, int y) const
  {
    if (IsZoomed(m_hwnd) || (m_window && (m_window->windowStates() & Qt::WindowFullScreen)))
      return HTCLIENT;
    RECT rect;
    if (!GetWindowRect(m_hwnd, &rect))
      return HTCLIENT;
    const UINT dpi = GetDpiForWindow(m_hwnd);
    const int g = MulDiv(m_grip, dpi ? static_cast<int>(dpi) : 96, 96);
    const bool left = x - rect.left < g;
    const bool right = rect.right - x <= g;
    const bool top = y - rect.top < g;
    const bool bottom = rect.bottom - y <= g;
    if (top && left)
      return HTTOPLEFT;
    if (top && right)
      return HTTOPRIGHT;
    if (bottom && left)
      return HTBOTTOMLEFT;
    if (bottom && right)
      return HTBOTTOMRIGHT;
    if (left)
      return HTLEFT;
    if (right)
      return HTRIGHT;
    if (top)
      return HTTOP;
    if (bottom)
      return HTBOTTOM;
    return HTCLIENT;
  }

  QPointer<QWindow> m_window;
  HWND m_hwnd;
  int m_grip;
};

} // namespace

bool
winframe_install(QObject* object, int grip)
{
  auto* window = qobject_cast<QWindow*>(object);
  if (!window)
    return false;
  auto hwnd = reinterpret_cast<HWND>(window->winId());
  if (!hwnd)
    return false;

  // Фильтр — раньше SetWindowPos: он должен поймать WM_NCCALCSIZE от SWP_FRAMECHANGED.
  // Живёт до конца процесса (окно главное).
  QGuiApplication::instance()->installNativeEventFilter(new FrameFilter(window, hwnd, grip));

  apply_frame_style(hwnd);

  // Тень DWM (Windows 10 и 11)
  const MARGINS margins{ 0, 0, 0, 1 };
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  // Windows 11: скруглённые углы MD3. DWM рисует их сам (вместе с тонкой обводкой) и делает прямыми
  // у развёрнутого окна и на весь экран. Windows 10 атрибута не знает — вызов вернёт ошибку, углы прямые.
  constexpr DWORD corner_preference = 33; // DWMWA_WINDOW_CORNER_PREFERENCE (SDK 10.0.22000+)
  constexpr int corner_round = 2;         // DWMWCP_ROUND
  DwmSetWindowAttribute(hwnd, corner_preference, &corner_round, sizeof(corner_round));
  return true;
}

} // namespace mf

#else

namespace mf {

bool
winframe_install(QObject* object, int grip)
{
  (void)object;
  (void)grip;
  return false;
}

} // namespace mf

#endif
