import QtQuick

// Поверхность-контейнер MD3 (плавающие панели референса).
Rectangle {
    property string level: "container"   // lowest | low | container | high | highest | surface
    property int elevation: 0
    property real translucency: 0          // 0..1 — сквозь поверхность виден фон окна

    radius: Theme.shape.extraLarge
    color: Qt.alpha(_base, 1 - translucency)
    readonly property color _base: ({
        lowest: Theme.surfaceContainerLowest,
        low: Theme.surfaceContainerLow,
        container: Theme.surfaceContainer,
        high: Theme.surfaceContainerHigh,
        highest: Theme.surfaceContainerHighest,
        surface: Theme.surface
    })[level] ?? Theme.surfaceContainer
}
