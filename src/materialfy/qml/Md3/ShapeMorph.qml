import QtQuick
import "Shapes.js" as Shapes

// Состояние морфа фигуры для шейдеров shape/shapeimage (MorphShape, MorphImage).
// Текущая фигура = mix(mix(A, B, s), C, t): анимируется одно число t, контур считает GPU.
// Прерванный морф «замораживается» в паре (A, B, s) — без пересчёта точек на CPU.
QtObject {
    id: root

    property var shape: "circle"
    property int duration: Theme.motion.spatialDefault
    property real overshoot: 1.4
    property real livingSpeed: 1           // скорость «дыхания» клякс, 0 — заморозить
    property bool active: true             // не виден — морф откладывается до появления, «дыхание» стоит

    property var a: Shapes.pack("circle")
    property var b: a
    property var c: a
    property real s: 0
    property real t: 0
    property real time: 0
    property bool _living: false
    property var _pending: undefined       // фигура, сменённая, пока элемент скрыт

    onActiveChanged: {
        if (active && _pending !== undefined) {
            const next = _pending
            _pending = undefined
            morphTo(next)
        }
    }

    // При создании привязка `shape` срабатывает после значения по умолчанию — без _ready каждая
    // фигура морфилась бы из круга при каждом появлении строки в списке.
    property bool _ready: false
    Component.onCompleted: { _set(shape); _ready = true }
    onShapeChanged: if (_ready) morphTo(shape)

    function _set(next) {
        _pending = undefined
        _anim.stop()
        const p = Shapes.pack(next)
        a = p; b = p; c = p
        s = 0; t = 0
        _living = Shapes.isLiving(next)
    }

    // Сменить фигуру сразу, без морфа
    function jumpTo(next) {
        _ready = false
        shape = next
        _set(next)
        _ready = true
    }

    function morphTo(next) {
        if (duration <= 0 || Theme.reducedMotion) {
            _set(next)
            return
        }
        // скрытая фигура не анимируется: морф сыграет, когда её покажут
        if (!active) {
            _anim.stop()
            if (t !== 0 || s !== 0) {
                a = c; b = c; s = 0; t = 0
            }
            _pending = next
            return
        }
        if (_anim.running) {
            // прерванный морф: из пары (A, B) остаётся преобладающая, к ней — прежняя цель с долей t
            a = s < 0.5 ? a : b
            b = c
            s = t
        } else {
            a = c; b = c; s = 0
        }
        c = Shapes.pack(next)
        t = 0
        _living = _living || Shapes.isLiving(next)
        _anim.restart()
    }

    property NumberAnimation _anim: NumberAnimation {
        target: root
        property: "t"
        from: 0
        to: 1
        duration: root.duration
        easing.type: Easing.OutBack
        easing.overshoot: root.overshoot
        onFinished: {
            root.a = root.c; root.b = root.c; root.s = 0; root.t = 0
            root._living = Shapes.isLiving(root.shape)
        }
    }

    property TickAnimation _breath: TickAnimation {
        running: root.active && root._living && root.livingSpeed > 0 && !Theme.quiet && !Theme.reducedMotion
        onTriggered: root.time += frameTime * root.livingSpeed
    }
}
