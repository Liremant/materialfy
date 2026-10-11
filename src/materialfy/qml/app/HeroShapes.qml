import QtQuick
import Md3

// Плавающие фигуры за шапкой страницы. Кладётся ВНЕ прокручиваемой области (иначе её clip режет
// фигуры по краю) и едет вместе с шапкой по scroll; заходит под прозрачную верхнюю панель, сверху
// и снизу фигуры растворяются — видимой рамки нет. Стоит, когда шапка уехала из виду.
Item {
    id: root

    property real headerHeight: 320        // высота шапки, за которой плавают фигуры
    property real scroll: 0                // насколько прокручена страница
    property real contentX: 0              // область шапки по горизонтали
    property real contentWidth: width
    property string seed
    property real shapesOpacity: 0.75
    property bool active: true

    readonly property real above: 64       // высота верхней панели над страницей
    readonly property real below: 140      // запас под шапкой на растворение

    visible: active && scroll < headerHeight + below
    y: -above - scroll
    height: above + headerHeight + below

    layer.enabled: visible
    layer.effect: ShaderEffect {
        property real fadeTop: root.above * 1.6 / Math.max(1, root.height)
        property real fadeBottom: root.below * 1.4 / Math.max(1, root.height)
        fragmentShader: Qt.resolvedUrl("shaders/edgefade.frag.qsb")
    }

    FloatingShapes {
        x: root.contentX
        y: root.above
        width: root.contentWidth
        height: root.headerHeight
        seed: root.seed
        opacity: root.shapesOpacity
        running: root.visible
    }
}
