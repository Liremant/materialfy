import QtQuick

// Линейный прогресс MD3 Expressive: проигранная часть — бегущая волна, остаток — прямой трек
// с зазором и stop-точкой. На паузе (`wavy: false`) волна плавно выпрямляется.
// interactive: true превращает его в перемотку (сигналы moved/committed).
Item {
    id: root

    property real value: 0              // 0..1
    property bool wavy: true
    property bool interactive: false
    property real thickness: 4
    property real amplitude: 3
    property real wavelength: 40
    property real speed: 1              // периодов волны в секунду
    property real gap: 4
    property color activeColor: Theme.primary
    property color trackColor: Theme.secondaryContainer
    property color stopColor: Theme.primary

    readonly property bool dragging: drag.pressed
    property real dragValue: 0
    readonly property real shownValue: dragging ? dragValue : value

    signal moved(real value)
    signal committed(real value)

    implicitWidth: 240
    implicitHeight: Math.max(thickness + 2 * amplitude, 24) + 4

    // reduced motion: прямая линия, волна не бежит
    property real _amp: wavy && !Theme.reducedMotion ? amplitude : 0
    Behavior on _amp { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
    property real _phase: 0

    FrameAnimation {
        running: root.visible && root._amp > 0.01 && root.speed !== 0 && !Theme.calm
        onTriggered: root._phase = (root._phase + frameTime * root.speed * Math.PI * 2) % (Math.PI * 2)
    }

    readonly property real _cy: height / 2
    readonly property real _cap: thickness / 2
    readonly property real _x0: _cap
    readonly property real _x1: width - _cap
    readonly property real _activeEnd: _x0 + (_x1 - _x0) * Math.max(0, Math.min(1, shownValue))

    // Отрисовка — шейдер (shaders/wavy.frag): смена фазы и значения — только uniform'ы, без пересборки
    // контура на CPU (Shape с сотнями точек пересобирался каждый кадр бегущей волны).
    ShaderEffect {
        anchors.fill: parent
        property size size: Qt.size(width, height)
        property real thickness: root.thickness
        property real amp: root._amp
        property real k: Math.PI * 2 / root.wavelength
        property real phase: root._phase
        property real activeEnd: root._activeEnd
        property real x0: root._x0
        property real x1: root._x1
        property real trackStart: Math.min(root._x1, root._activeEnd + root.gap + root.thickness)
        property real showStop: root._activeEnd < root._x1 - root.gap - root.thickness ? 1 : 0
        property real showActive: root.shownValue > 0 ? 1 : 0
        property color activeColor: root.activeColor
        property color trackColor: root.trackColor
        property color stopColor: root.stopColor
        fragmentShader: Qt.resolvedUrl("shaders/wavy.frag.qsb")
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.topMargin: -8
        anchors.bottomMargin: -8
        enabled: root.interactive
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        preventStealing: true

        function valueAt(x) { return Math.max(0, Math.min(1, (x - root._x0) / (root._x1 - root._x0))) }

        onPressed: mouse => { root.dragValue = valueAt(mouse.x); root.moved(root.dragValue) }
        onPositionChanged: mouse => { if (pressed) { root.dragValue = valueAt(mouse.x); root.moved(root.dragValue) } }
        onReleased: root.committed(root.dragValue)
    }
}
