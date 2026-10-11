import QtQuick
import QtQuick.Effects

// Интерактивная поверхность MD3: слой hover/press + ripple, обрезанный по скруглению.
// Кладётся поверх содержимого компонента: StateLayer { anchors.fill: parent; radius: ... }
MouseArea {
    id: root

    property color color: Theme.fgSurface
    property real radius: 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius
    property bool ripple: true
    property bool dragged: false

    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    readonly property real _opacity: !enabled ? 0
        : dragged ? Theme.stateLayer.dragged
        : pressed ? Theme.stateLayer.pressed
        : containsMouse ? Theme.stateLayer.hover
        : activeFocus ? Theme.stateLayer.focus : 0

    Rectangle {
        anchors.fill: parent
        color: root.color
        opacity: root._opacity
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
    }

    // Ripple: слой включается только на время анимации, чтобы не держать лишних FBO.
    Item {
        id: rippleHost
        anchors.fill: parent
        visible: wave.opacity > 0
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Rectangle {
            id: wave
            property real cx: 0
            property real cy: 0
            readonly property real maxR: Math.hypot(Math.max(cx, root.width - cx), Math.max(cy, root.height - cy))
            x: cx - width / 2
            y: cy - height / 2
            width: 2 * maxR * scaleFactor
            height: width
            radius: width / 2
            color: root.color
            opacity: 0
            property real scaleFactor: 0
        }
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
    }

    ParallelAnimation {
        id: grow
        NumberAnimation {
            target: wave; property: "scaleFactor"; from: 0.1; to: 1
            duration: 450
            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedDecelerate
        }
        NumberAnimation { target: wave; property: "opacity"; to: Theme.stateLayer.pressed; duration: 75 }
    }

    NumberAnimation {
        id: fade
        target: wave; property: "opacity"; to: 0; duration: 300
    }

    onPressed: mouse => {
        if (!ripple)
            return
        fade.stop()
        wave.cx = mouse.x
        wave.cy = mouse.y
        grow.restart()
    }
    onReleased: if (ripple) fade.start()
    onCanceled: if (ripple) fade.start()
}
