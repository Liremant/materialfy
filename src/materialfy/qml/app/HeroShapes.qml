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
    property bool running: true            // false — фигуры на месте, без движения

    readonly property real above: 64       // высота верхней панели над страницей
    readonly property real below: 140      // запас под шапкой на растворение

    visible: active && scroll < headerHeight + below
    y: -above - scroll
    height: above + headerHeight + below
    clip: true

    // Растворение краёв считает шейдер каждой фигуры, а не слой поверх них: «живой» слой с меняющимся
    // содержимым просит у окна лишний кадр после каждого изменения (плывущие фигуры перерисовывали окно
    // дважды за тик), а на программном рендере ещё и сам стоит целого прохода по шапке.
    FloatingShapes {
        x: root.contentX
        y: root.above
        width: root.contentWidth
        height: root.headerHeight
        seed: root.seed
        opacity: root.shapesOpacity
        running: root.visible && root.running
        fadeFrom: -root.above
        fadeIn: root.above * 1.6
        fadeTo: root.headerHeight + root.below
        fadeOut: root.below * 1.4
    }
}
