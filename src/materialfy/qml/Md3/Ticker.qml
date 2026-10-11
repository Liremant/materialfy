pragma Singleton
import QtQuick

// Общие «часы» декоративных бесконечных анимаций (дрейф фона, бегущая волна, вращение обложки, «дыхание»
// клякс): ~30 Гц вместо частоты монитора, и все они срабатывают в одном кадре. Каждая такая анимация на
// FrameAnimation заставляла перерисовывать всё окно на 144–280 Гц, пока играет музыка.
// Подписчики — TickAnimation; таймер идёт, только пока хоть один из них запущен.
QtObject {
    id: root

    property int users: 0
    property int interval: 33
    signal tick(real dt)

    property real _last: 0
    property Timer _timer: Timer {
        interval: root.interval
        repeat: true
        running: root.users > 0
        onRunningChanged: root._last = Date.now()
        onTriggered: {
            const now = Date.now()
            // после паузы (свёрнутое окно, сон) — не прыгать на весь пропущенный интервал
            const dt = Math.min(0.1, Math.max(0, (now - root._last) / 1000))
            root._last = now
            root.tick(dt)
        }
    }
}
