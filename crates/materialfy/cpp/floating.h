#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>

namespace mf {

// Плеер вне главного окна (настройка floatingPlayer): островок у верхнего края экрана и виджет в панели задач.
// window — QWindow* (Window из QML). Вне Windows — заглушки (false / 0 / ""), кроме floating_set_mask.

// Окно-островок: не в панели задач и Alt+Tab, не забирает фокус (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE),
// DWM не скругляет углы. false — не Windows или нет HWND.
bool floating_tool_window(QObject* window);

// Где окно ловит мышь и рисуется: прямоугольник в логических пикселях окна; w <= 0 — всё окно.
// Остальная (прозрачная) часть окна пропускает клики к окнам под ним (Windows — регион окна, X11 — XShape).
void floating_set_mask(QObject* window, int x, int y, int w, int h);

// На переднем плане полноэкранное приложение, игра или презентация (SHQueryUserNotificationState):
// островок поверх них не нужен.
bool floating_fullscreen_busy();

// Виджет в панели задач Windows: встроить окно дочерним в Shell_TrayWnd и поставить на место.
// width × height — размер в логических пикселях (масштаб — DPI панели; высота не больше панели без полей),
// embed: false — сразу запасной вариант. pos — место (настройка taskbarWidgetPos): "tray" — у области уведомлений,
// "left" — у левого края (после «Пуска» и поиска, если значки слева), "appsLeft" / "appsRight" — слева / справа
// от значков приложений, или доля 0..1 свободной ширины панели ("0.42").
// Возвращает 1 — встроено, 2 — запасной вариант (окно поверх всех над панелью), 0 — некуда (нет панели, она
// вертикальная или узкая), -1 — окно потеряно (Explorer перезапустился и забрал дочернее окно с собой) — его надо
// создать заново. Вызывается раз в 2 с: заодно ловит смену размера и DPI панели и перезапуск Explorer.
int floating_taskbar_place(QObject* window, int width, int height, bool embed, const QString& pos);

// Перетаскивание виджета вдоль панели за курсором: phase 0 — начало (запоминает, где схватили), 1 — шаг,
// 2 — конец. В пределах 24 px окно липнет к местам «left», «appsLeft», «appsRight», «tray». Возвращает место
// в формате taskbarWidgetPos ("" — не вышло).
QString floating_taskbar_drag(QObject* window, int width, int height, int phase);

// Вынуть окно из панели задач (перед удалением окна)
void floating_taskbar_detach(QObject* window);

// Клавиши без фокуса: пока курсор над окном, ← → ↑ ↓ и пробел (без Ctrl, Alt, Win) не доходят до активного окна,
// а вызывают у window QML-функцию floatingKey(code): 1 ←, 2 →, 3 ↑, 4 ↓, 5 пробел. Windows — низкоуровневый
// хук клавиатуры (WH_KEYBOARD_LL) только на время наведения: on — поставить, false — снять. Курсор ушёл с окна —
// клавиши снова идут как обычно, даже если снять хук забыли. Вне Windows — false (фокус не забираем).
bool floating_key_hook(QObject* window, bool on);

} // namespace mf
