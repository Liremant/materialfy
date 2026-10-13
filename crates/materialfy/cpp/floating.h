#pragma once

#include <QtCore/QObject>

namespace mf {

// Плеер вне главного окна (настройка floatingPlayer): островок у верхнего края экрана и виджет в панели задач.
// window — QWindow* (Window из QML). Вне Windows — заглушки (false / 0), кроме floating_set_mask.

// Окно-островок: не в панели задач и Alt+Tab, не забирает фокус (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE),
// DWM не скругляет углы. false — не Windows или нет HWND.
bool floating_tool_window(QObject* window);

// Где окно ловит мышь и рисуется: прямоугольник в логических пикселях окна; w <= 0 — всё окно.
// Остальная (прозрачная) часть окна пропускает клики к окнам под ним (Windows — регион окна, X11 — XShape).
void floating_set_mask(QObject* window, int x, int y, int w, int h);

// На переднем плане полноэкранное приложение, игра или презентация (SHQueryUserNotificationState):
// островок поверх них не нужен.
bool floating_fullscreen_busy();

// Виджет в панели задач Windows: встроить окно дочерним в Shell_TrayWnd слева от области уведомлений
// и поставить на место. width — ширина в логических пикселях (масштаб — DPI панели), embed: false — сразу
// запасной вариант. Возвращает 1 — встроено, 2 — запасной вариант (окно поверх всех над панелью),
// 0 — некуда (нет панели, она вертикальная или узкая), -1 — окно потеряно (Explorer перезапустился и забрал
// дочернее окно с собой) — его надо создать заново. Вызывается раз в 2 с: заодно ловит смену размера панели
// и перезапуск Explorer.
int floating_taskbar_place(QObject* window, int width, bool embed);

// Вынуть окно из панели задач (перед удалением окна)
void floating_taskbar_detach(QObject* window);

} // namespace mf
