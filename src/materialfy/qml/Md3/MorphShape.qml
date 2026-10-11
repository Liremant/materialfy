import QtQuick
import QtQuick.Shapes
import "Shapes.js" as Shapes

// Фигура MD3 Expressive. При смене `shape` плавно морфится из текущей формы в новую
// (в том числе из промежуточной, если предыдущий морф ещё не закончился).
// Корень — Item, а не Shape: Shape пересчитывает свой implicit-размер из пути, а путь зависит
// от размера — в Layout это петля привязок.
Item {
    id: root

    property var shape: "circle"
    property real angle: 0                 // поворот контура, градусы (Item.rotation не трогаем)
    property int samples: 120
    property color color: Theme.primary
    property color strokeColor: "transparent"
    // true — фигура рисуется белой, а цвет накладывает шейдер (смена цвета = смена uniform, без
    // перестройки геометрии CurveRenderer). false — для белых масок: слой и шейдер не нужны.
    property bool tinted: strokeWidth === 0
    property real strokeWidth: 0
    property int duration: Theme.motion.spatialDefault
    property real overshoot: 1.4
    property real livingSpeed: 1           // скорость «дыхания» blob-фигур, 0 — заморозить
    property real pulse: 0                 // 0..1 — «дыхание» контура (см. Shapes.outline)

    property var _from: shape
    property var _to: shape
    property real _t: 0
    property real _time: 0

    function morphTo(next) {
        const current = Shapes.blend(Shapes.radii(_from, samples, _time), Shapes.radii(_to, samples, _time), _t)
        _from = current
        _to = next
        _t = 0
        morph.restart()
    }

    // Сменить фигуру сразу, без морфа
    function jumpTo(next) {
        _ready = false
        shape = next
        morph.stop()
        _from = next
        _to = next
        _t = 0
        _ready = true
    }

    // При создании привязка `shape` срабатывает после значения по умолчанию ("circle"), и без этой
    // проверки каждая фигура полсекунды морфилась из круга — ~0,35 мс/кадр на фигуру, и так при
    // каждом появлении строки в списке (прокрутка, смена трека).
    property bool _ready: false
    Component.onCompleted: { _from = shape; _to = shape; _t = 0; _ready = true }
    onShapeChanged: if (_ready) morphTo(shape)

    implicitWidth: 48
    implicitHeight: 48

    NumberAnimation {
        id: morph
        target: root
        property: "_t"
        from: 0
        to: 1
        duration: Theme.reducedMotion ? 0 : root.duration
        easing.type: Easing.OutBack
        easing.overshoot: root.overshoot
    }

    FrameAnimation {
        running: root.visible && !Theme.calm && !Theme.reducedMotion && root.livingSpeed > 0 && (Shapes.isLiving(root._from) || Shapes.isLiving(root._to))
        onTriggered: root._time += frameTime * root.livingSpeed
    }

    Shape {
        anchors.fill: parent
        z: -1   // под вложенными элементами (иконка, инициалы)
        preferredRendererType: Shape.CurveRenderer
        // Слой только у самой фигуры: иначе шейдер окрашивал бы и вложенные иконки/текст.
        layer.enabled: root.tinted && root.visible
        layer.smooth: true
        layer.effect: ShaderEffect {
            property color tint: root.color
            fragmentShader: Qt.resolvedUrl("shaders/tint.frag.qsb")
        }

        ShapePath {
            fillColor: root.tinted ? "white" : root.color
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            joinStyle: ShapePath.RoundJoin
            PathPolyline {
                path: Shapes.outline(root._from, root._to, root._t, root.samples, root.width, root.height,
                                     root.angle * Math.PI / 180, root._time, root.strokeWidth / 2, root.pulse)
            }
        }
    }
}
