import QtQuick
import QtQuick.Effects

// Картинка (обложка), обрезанная по фигуре MD3 с морфингом.
Item {
    id: root

    property alias source: image.source
    property alias status: image.status
    property alias shape: mask.shape
    property alias angle: mask.angle
    property alias duration: mask.duration
    property alias livingSpeed: mask.livingSpeed
    property alias pulse: mask.pulse        // «дыхание» фигуры; картинка внутри не двигается

    // Поворот фигуры-рамки, градусы: картинка внутри стоит. Трансформация, контур не пересчитывается
    // (в отличие от angle). Медленное вращение — MaskSpin.
    property real maskRotation: 0

    function jumpTo(next) { mask.jumpTo(next) }
    property color placeholderColor: Theme.surfaceContainerHighest

    // Подложка, пока картинка грузится (та же фигура).
    MorphShape {
        anchors.fill: parent
        rotation: root.maskRotation
        shape: mask.shape
        angle: mask.angle
        pulse: mask.pulse
        duration: mask.duration
        color: root.placeholderColor
        // заглушка — только пока у этой обложки не было ни кадра; при перезагрузке под новый размер видна старая
        visible: image.source.toString() === "" || image.shownSource !== image.source || image.status === Image.Error
    }

    Image {
        id: image
        anchors.fill: parent
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        // размер декодирования — ступенями по 128 px: иначе каждый шаг ресайза окна перезагружал обложку
        readonly property int _step: 128
        sourceSize: Qt.size(Math.max(_step, Math.ceil(root.width * Screen.devicePixelRatio / _step) * _step),
                            Math.max(_step, Math.ceil(root.height * Screen.devicePixelRatio / _step) * _step))
        retainWhileLoading: true
        property url shownSource: ""
        onStatusChanged: if (status === Image.Ready) shownSource = source
    }

    // Слой — на обёртке: поворот самой фигуры должен попасть в текстуру маски
    Item {
        id: maskLayer
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        MorphShape {
            id: mask
            anchors.fill: parent
            rotation: root.maskRotation
            color: "white"
            tinted: false   // белая маска: шейдер окраски не нужен
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: image
        visible: image.status === Image.Ready
        maskEnabled: true
        maskSource: maskLayer
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
