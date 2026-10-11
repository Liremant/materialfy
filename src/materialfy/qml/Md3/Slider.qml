import QtQuick

// Слайдер MD3 Expressive: толстый трек, хэндл-полоса с зазорами, stop-точка,
// всплывающее значение при перетаскивании.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0
    property real trackHeight: 16
    property real handleHeight: 44
    property real gap: 6
    property bool showValue: true
    property var valueText: v => Math.round(v * 100) + "%"
    property color activeColor: Theme.primary
    property color inactiveColor: Theme.secondaryContainer
    property color handleColor: Theme.primary

    readonly property alias pressed: area.pressed
    readonly property real position: to === from ? 0 : (value - from) / (to - from)

    signal moved(real value)

    implicitWidth: 240
    implicitHeight: handleHeight

    function _setFromX(x) {
        let p = Math.max(0, Math.min(1, (x - _usableX0) / (_usableX1 - _usableX0)))
        let v = from + p * (to - from)
        if (stepSize > 0)
            v = from + Math.round((v - from) / stepSize) * stepSize
        if (v !== value) {
            value = v
            moved(v)
        }
    }

    property real _handleW: area.pressed ? 2 : 4
    Behavior on _handleW { NumberAnimation { duration: Theme.motion.effectsFast } }
    readonly property real _usableX0: _handleW / 2
    readonly property real _usableX1: width - _handleW / 2
    readonly property real _handleX: _usableX0 + (_usableX1 - _usableX0) * position
    readonly property real _outer: trackHeight / 2
    readonly property real _inner: 2

    // Активная часть
    Rectangle {
        readonly property real w: root._handleX - root._handleW / 2 - root.gap
        visible: w > 0
        x: 0
        width: Math.max(w, 0)
        height: root.trackHeight
        anchors.verticalCenter: parent.verticalCenter
        color: root.activeColor
        topLeftRadius: Math.min(root._outer, width / 2)
        bottomLeftRadius: Math.min(root._outer, width / 2)
        topRightRadius: Math.min(root._inner, width / 2)
        bottomRightRadius: Math.min(root._inner, width / 2)
    }

    // Неактивная часть
    Rectangle {
        id: inactive
        readonly property real x0: root._handleX + root._handleW / 2 + root.gap
        visible: root.width - x0 > 0
        x: x0
        width: Math.max(root.width - x0, 0)
        height: root.trackHeight
        anchors.verticalCenter: parent.verticalCenter
        color: root.inactiveColor
        topRightRadius: Math.min(root._outer, width / 2)
        bottomRightRadius: Math.min(root._outer, width / 2)
        topLeftRadius: Math.min(root._inner, width / 2)
        bottomLeftRadius: Math.min(root._inner, width / 2)

        Rectangle {
            width: 4
            height: 4
            radius: 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: (root.trackHeight - 4) / 2
            color: root.activeColor
            visible: parent.width > root.trackHeight
        }
    }

    // Хэндл
    Rectangle {
        id: handle
        width: root._handleW
        height: root.handleHeight
        radius: width / 2
        x: root._handleX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.handleColor
    }

    // Значение над хэндлом
    Rectangle {
        visible: opacity > 0
        opacity: root.showValue && area.pressed ? 1 : 0
        scale: opacity
        transformOrigin: Item.Bottom
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsDefault } }
        width: Math.max(48, valueLabel.implicitWidth + 24)
        height: 44
        radius: height / 2
        color: Theme.inverseSurface
        x: handle.x + handle.width / 2 - width / 2
        y: handle.y - height - 4

        Label {
            id: valueLabel
            anchors.centerIn: parent
            type: "labelLarge"
            color: Theme.fgInverseSurface
            text: root.valueText(root.value)
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => root._setFromX(mouse.x)
        onPositionChanged: mouse => { if (pressed) root._setFromX(mouse.x) }
        onWheel: wheel => {
            const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 50
            const v = Math.max(root.from, Math.min(root.to, root.value + (wheel.angleDelta.y > 0 ? step : -step)))
            if (v !== root.value) { root.value = v; root.moved(v) }
        }
    }
}
