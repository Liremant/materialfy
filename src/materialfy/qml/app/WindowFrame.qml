import QtQuick
import Md3

// Рамка окна без системного хрома. Забирает к себе всё содержимое окна (Component.onCompleted) и рисует
// под ним фон окна.
// Windows: углы скругляет DWM (winframe.cpp, Windows 11), здесь — только фон.
// Linux / macOS: окно прозрачное (Main.qml: color), приложение рисуется скруглённым прямоугольником радиуса
// Theme.shape.large — слоем с маской roundclip; у развёрнутого окна и на весь экран углы прямые. Прозрачные
// уголки остаются за угловыми зонами ResizeEdges: нажатие в них тянет угол окна. Тень — какую даёт система.
Item {
    id: root

    required property Window window
    // окно рисует свой край само (Linux / macOS, не развёрнуто)
    readonly property bool framed: Qt.platform.os !== "windows" && window.visibility === Window.Windowed
    // На программном рендере углы прямые: слой на всё окно — лишний проход по каждому пикселю в каждом кадре,
    // а меняющееся содержимое «живого» слоя ещё и удваивает кадры (Qt просит следующий после каждого изменения)
    readonly property bool rounded: framed && !Theme.lowPower
    readonly property real radius: rounded ? Theme.shape.large : 0
    // слой включается только после того, как содержимое перенесено: иначе эффект слоя (его ставят рядом,
    // в contentItem) попал бы внутрь самой рамки
    property bool _adopted: false

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    layer.enabled: rounded && _adopted
    layer.effect: ShaderEffect {
        readonly property real dpr: root.Screen.devicePixelRatio > 0 ? root.Screen.devicePixelRatio : 1
        property size pixelSize: Qt.size(width * dpr, height * dpr)
        property real radius: root.radius * dpr
        fragmentShader: Qt.resolvedUrl("shaders/roundclip.frag.qsb")
    }

    // Тонкая обводка: композитор Linux часто не даёт окну без рамки ни тени, ни края
    Rectangle {
        anchors.fill: parent
        z: 100000
        visible: root.framed
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.outlineVariant, 0.6)
    }

    Component.onCompleted: {
        for (const child of [...window.contentItem.children]) {
            if (child !== root)
                child.parent = root
        }
        _adopted = true
    }
}
