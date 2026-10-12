import QtQuick

// Индикатор загрузки MD3 Expressive: фигура морфится по кругу пресетов и вращается.
// Работает только пока виден (running && visible), иначе не тратит кадры.
Item {
    id: root

    property bool running: true
    property bool contained: false        // подложка-круг (вариант «contained»)
    property real size: 48
    property color color: contained ? Theme.fgPrimaryContainer : Theme.primary
    // reduced motion — статичная фигура
    readonly property bool active: running && visible && Theme.reducedMotion !== true

    readonly property var sequence: ["cookie9", "pentagonish", "pill", "sunny", "cookie4", "circle", "flower6"]
    property int _i: 0

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.primaryContainer
        visible: root.contained
    }

    MorphShape {
        id: shape
        anchors.centerIn: parent
        width: root.size * (root.contained ? 0.6 : 0.79)
        height: width
        color: root.color
        samples: 72
        // программный рендер: фигуры сменяются без морфа, вращение — по часам Ticker (~30 Гц), а не в каждом
        // кадре монитора: кадр там рисует процессор, а индикатор крутится всё время загрузки
        duration: Theme.lowPower ? 0 : 500
        overshoot: 1.2
        shape: root._shapeAt(root._i)
        rotation: 0

        NumberAnimation on rotation {
            running: root.active && !Theme.lowPower
            from: 0
            to: 360
            duration: 2600
            loops: Animation.Infinite
        }
        TickAnimation {
            running: root.active && Theme.lowPower
            onTriggered: shape.rotation = (shape.rotation + frameTime * 360 / 2.6) % 360
        }
    }

    Timer {
        interval: 650
        repeat: true
        running: root.active
        onTriggered: root._i = (root._i + 1) % root.sequence.length
    }

    function _shapeAt(i) {
        const name = sequence[i]
        // фигуры, которых нет в пресетах, описываем на месте
        if (name === "pentagonish")
            return { kind: "flower", n: 5, depth: 0.16, p: 3 }
        if (name === "pill")
            return { kind: "square", p: 2.4, aspect: 1.35 }
        return name
    }
}
