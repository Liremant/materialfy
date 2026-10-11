import QtQuick
import Md3

// Стек страниц. Живые экземпляры страниц хранятся в стеке, поэтому «назад» сохраняет прокрутку и состояние.
// Переходы MD3: между разделами — fade through, вглубь/назад — shared axis X.
Item {
    id: root

    // имя страницы → url компонента
    property var pages: ({})
    property var stack: []                 // [{ name, props, item }]
    readonly property int depth: stack.length
    readonly property var current: stack.length ? stack[stack.length - 1] : null
    readonly property string currentName: current ? current.name : ""
    readonly property string rootName: stack.length ? stack[0].name : ""
    readonly property Item currentItem: current ? current.item : null

    property var _components: ({})
    property var _leaving: []               // элементы, которые уничтожить после анимации
    property Item _out: null

    function _same(entry, name, props) {
        return entry && entry.name === name && JSON.stringify(entry.props ?? {}) === JSON.stringify(props ?? {})
    }

    function push(name, props) {
        if (_same(current, name, props))
            return
        const entry = _make(name, props)
        if (!entry)
            return
        const prev = currentItem
        stack = stack.concat([entry])
        _animate(prev, entry.item, "forward")
    }

    // Переход в раздел верхнего уровня: стек сбрасывается.
    function reset(name, props) {
        if (depth === 1 && _same(current, name, props))
            return
        const prev = currentItem
        const entry = _make(name, props)
        if (!entry)
            return
        _leaving = _leaving.concat(stack.map(e => e.item).filter(i => i !== prev))
        if (prev)
            _leaving = _leaving.concat([prev])
        stack = [entry]
        _animate(prev, entry.item, "fade")
    }

    function back() {
        if (depth < 2)
            return false
        const popped = stack[stack.length - 1]
        stack = stack.slice(0, -1)
        _leaving = _leaving.concat([popped.item])
        const next = currentItem
        next.visible = true
        _animate(popped.item, next, "back")
        return true
    }

    function _make(name, props) {
        const url = pages[name]
        if (!url) {
            console.error("Router: нет страницы", name)
            return null
        }
        let comp = _components[name]
        if (!comp) {
            comp = Qt.createComponent(url)
            _components[name] = comp
        }
        if (comp.status === Component.Error) {
            console.error("Router:", comp.errorString())
            return null
        }
        const item = comp.createObject(container, Object.assign({ router: root }, props ?? {}))
        // не anchors.fill: анимации переходов двигают x
        item.width = Qt.binding(() => container.width)
        item.height = Qt.binding(() => container.height)
        item.opacity = 0
        return { name: name, props: props ?? {}, item: item }
    }

    function _animate(from, to, kind) {
        if (anim.running)
            anim.complete()
        _out = from
        from = from ?? dummy
        // Разделы (fade through): новая страница всплывает снизу и чуть «дорастает» до размера.
        // Вглубь/назад (shared axis X): страницы едут по горизонтали навстречу друг другу.
        const axis = kind === "fade" ? "y" : "x"
        const d = kind === "forward" ? 140 : kind === "back" ? -140 : 72
        outFade.target = from
        outMove.target = from
        outMove.property = axis
        outMove.to = kind === "fade" ? -24 : -d / 2
        outScale.target = from
        outScale.to = kind === "fade" ? 0.97 : 1
        inFade.target = to
        inMove.target = to
        inMove.property = axis
        inMove.from = d
        inScale.target = to
        inScale.from = kind === "fade" ? 0.94 : 1
        to.x = 0
        to.y = 0
        to.visible = true
        to.z = 1
        from.z = 0
        anim.start()
    }

    Item {
        id: container
        anchors.fill: parent
    }

    Item { id: dummy; visible: false }

    ParallelAnimation {
        id: anim

        NumberAnimation { id: outFade; property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation {
            id: outMove; duration: 300
            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedAccelerate
        }
        NumberAnimation { id: outScale; property: "scale"; duration: 300; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            ParallelAnimation {
                NumberAnimation { id: inFade; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation {
                    id: inMove; to: 0; duration: 560
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedDecelerate
                }
                NumberAnimation {
                    id: inScale; property: "scale"; to: 1; duration: 560
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedDecelerate
                }
            }
        }

        onFinished: {
            if (root._out) {
                root._out.visible = false
                root._out.x = 0
                root._out.y = 0
                root._out.scale = 1
            }
            for (const item of root._leaving)
                item.destroy()
            root._leaving = []
            root._out = null
        }
    }
}
