import QtQuick

// Фигура MD3 Expressive. При смене `shape` плавно морфится из текущей формы в новую
// (в том числе из промежуточной, если предыдущий морф ещё не закончился).
// Рисует шейдер shaders/shape.frag: контур — полярная функция, морф, цвет, поворот, «дыхание» —
// uniform'ы. Раньше здесь был PathPolyline из 120 точек: JS пересобирал его каждый кадр морфа,
// CurveRenderer заново триангулировал, а цвет накладывал отдельный слой.
// Корень — Item: вложенные элементы (иконка, инициалы) лежат поверх фигуры.
Item {
    id: root

    property var shape: "circle"
    property real angle: 0                 // поворот контура, градусы (Item.rotation не трогаем)
    property int samples: 120              // не используется (контур считает шейдер), оставлено для совместимости
    property color color: Theme.primary
    property color strokeColor: "transparent"
    property bool tinted: true             // не используется: цвет — всегда uniform
    property real strokeWidth: 0           // обводка внутрь контура, px
    property alias duration: m.duration
    property alias overshoot: m.overshoot
    property alias livingSpeed: m.livingSpeed // скорость «дыхания» blob-фигур, 0 — заморозить
    property real pulse: 0                 // 0..1 — «дыхание» контура: впадины глубже, фигура чуть шире
    // Растворение по вертикали без слоя (см. shape.frag): (u0, du, v0, dv) по y шейдера, 0 — нет
    property alias fade: fx.fade
    readonly property alias pad: fx.pad    // насколько шейдер выходит за элемент с каждой стороны, px

    function morphTo(next) { m.morphTo(next) }
    // Сменить фигуру сразу, без морфа (привязка m.shape не рвётся)
    function jumpTo(next) { m._ready = false; shape = next; m._set(next); m._ready = true }

    implicitWidth: 48
    implicitHeight: 48

    ShapeMorph {
        id: m
        shape: root.shape
        active: root.visible && root.opacity > 0
    }

    ShaderEffect {
        id: fx
        // чуть больше элемента: перелёт морфа (OutBack) не должен упираться в край прямоугольника
        readonly property real pad: Math.ceil(Math.min(root.width, root.height) * 0.06) + 1
        x: -pad
        y: -pad
        width: root.width + 2 * pad
        height: root.height + 2 * pad
        z: -1   // под вложенными элементами (иконка, инициалы)
        visible: root.width > 0 && root.height > 0 && (root.color.a > 0 || root.strokeWidth > 0)
        blending: true

        property vector4d a0: m.a[0]
        property vector4d a1: m.a[1]
        property vector4d a2: m.a[2]
        property vector4d a3: m.a[3]
        property vector4d b0: m.b[0]
        property vector4d b1: m.b[1]
        property vector4d b2: m.b[2]
        property vector4d b3: m.b[3]
        property vector4d c0: m.c[0]
        property vector4d c1: m.c[1]
        property vector4d c2: m.c[2]
        property vector4d c3: m.c[3]
        property vector4d morph: Qt.vector4d(m.s, m.t, root.angle * Math.PI / 180, root.pulse)
        property vector4d misc: Qt.vector4d(m.time, root.strokeWidth, 1, 0)
        property vector4d box: Qt.vector4d(width / Math.max(1, root.width), height / Math.max(1, root.height), 1, 1)
        property color fill: root.color
        property color stroke: root.strokeColor
        property vector4d fade
        fragmentShader: "shaders/shape.frag.qsb"
    }
}
