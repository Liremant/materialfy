#pragma once

#include <QtCore/QObject>

namespace mf {

// Окно без рамки на Windows: нативный ресайз за края, Aero Snap, тень DWM (контракт §7).
// window — QWindow* корня (после load). grip — ширина зоны ресайза в логических пикселях (6).
// false — не QWindow или нет HWND.
bool winframe_install(QObject* window, int grip);

} // namespace mf
