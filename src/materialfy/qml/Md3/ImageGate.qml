pragma Singleton
import QtQuick

// Глобальный лимит одновременных загрузок обложек. Десятки MorphImage одной страницы запрашивают
// декод разом — QQuickPixmapDecoder душит GUI-поток и открытие страницы встаёт под 100 % ядра.
// Очередь пускает по двенадцати: декод растянут на пару кадров дольше, но окно остаётся живым.
QtObject {
    id: root

    property int running: 0
    readonly property int limit: 12
    property var _queue: []

    function acquire(item) {
        if (root.running < root.limit) {
            root.running++
            return true
        }
        root._queue.push(item)
        return false
    }

    // item обязан вызвать release, когда загрузка кончилась (Ready/Error/Null) или источник сменился на ""
    function release(item) {
        root.running = Math.max(0, root.running - 1)
        while (root._queue.length > 0 && root.running < root.limit) {
            const next = root._queue.shift()
            if (next !== null && next.qmlContinue !== undefined) {
                root.running++
                next.qmlContinue()
            }
        }
    }
}
