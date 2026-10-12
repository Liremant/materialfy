#pragma once

#include <QtCore/QObject>

namespace mf {

// Windows: кнопки «Предыдущий / Пауза-Играть / Следующий» под эскизом окна на панели задач
// (ITaskbarList3::ThumbBarAddButtons), как у Spotify. window — QWindow* корня (после load, синглтоны
// Materialfy.Core уже есть). false — не Windows, нет HWND, движка QML или Player.
bool taskbar_install(QObject* window);

} // namespace mf
