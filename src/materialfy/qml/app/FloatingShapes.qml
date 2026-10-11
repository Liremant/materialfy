import QtQuick
import Md3

// Фон шапки: несколько крупных фигур MD3 Expressive медленно плывут и вращаются.
// Раскладка детерминирована от seed (у каждого плейлиста своя). Движение — только трансформации
// (x/y/rotation), путь фигур не пересчитывается; анимация стоит, когда running = false.
Item {
    id: root

    property color color: Theme.surfaceContainerHighest
    property int count: 6
    property string seed: ""
    property bool running: visible

    property real _t: 0

    // Простой детерминированный ГПСЧ (mulberry32) от строки
    function _rng(str) {
        let h = 1779033703 ^ str.length
        for (let i = 0; i < str.length; i++) {
            h = Math.imul(h ^ str.charCodeAt(i), 3432918353)
            h = (h << 13) | (h >>> 19)
        }
        let a = h >>> 0
        return () => {
            a = (a + 0x6D2B79F5) | 0
            let t = Math.imul(a ^ (a >>> 15), 1 | a)
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }

    readonly property var _specs: {
        const rnd = _rng(seed + "#")
        const shapes = ["cookie9", "flower8", "clover4", "cookie6", "sunny", "flower6", "cookie12", "scallop"]
        const out = []
        for (let i = 0; i < count; i++) {
            out.push({
                shape: shapes[Math.floor(rnd() * shapes.length)],
                // по ширине — равномерно по полосам, чтобы фигуры не слипались
                x: (i + 0.15 + 0.7 * rnd()) / count,
                y: 0.15 + 0.7 * rnd(),
                size: 0.55 + 0.6 * rnd(),          // доля высоты
                ax: 18 + 30 * rnd(), ay: 10 + 22 * rnd(),
                sx: 0.05 + 0.08 * rnd(), sy: 0.04 + 0.07 * rnd(),
                ph: rnd() * 6.28,
                r0: rnd() * 360, rs: (rnd() < 0.5 ? -1 : 1) * (3 + 5 * rnd())
            })
        }
        return out
    }

    FrameAnimation {
        running: root.running && !Theme.calm
        onTriggered: root._t += frameTime
    }

    Repeater {
        model: root._specs
        MorphShape {
            required property var modelData
            readonly property real side: modelData.size * root.height
            width: side
            height: side
            x: modelData.x * root.width - side / 2 + modelData.ax * Math.sin(root._t * modelData.sx * 6.28 + modelData.ph)
            y: modelData.y * root.height - side / 2 + modelData.ay * Math.cos(root._t * modelData.sy * 6.28 + modelData.ph)
            rotation: modelData.r0 + root._t * modelData.rs
            shape: modelData.shape
            color: root.color
        }
    }
}
