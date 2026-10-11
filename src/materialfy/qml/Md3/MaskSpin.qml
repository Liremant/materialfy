import QtQuick

// Медленное вращение фигуры-рамки у MorphImage (target), пока spinning. Остановившись, рамка
// доворачивается до ближайшей четверти оборота — квадрат не должен встать криво.
// Отдельный объект, а не часть MorphImage: обложек в списках сотни, а крутятся одна-две.
FrameAnimation {
    id: root

    property Item target
    property bool spinning: false
    property real speed: 8                 // градусов в секунду

    running: spinning && target !== null && target.visible && !Theme.calm && !Theme.reducedMotion
    onTriggered: target.maskRotation = (target.maskRotation + frameTime * speed) % 360

    onSpinningChanged: {
        _settle.stop()
        if (!spinning && target) {
            _settle.to = Math.round(target.maskRotation / 90) * 90
            _settle.start()
        }
    }

    property NumberAnimation _settle: NumberAnimation {
        target: root.target
        property: "maskRotation"
        duration: Theme.motion.spatialSlow
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.motion.emphasizedDecelerate
    }
}
