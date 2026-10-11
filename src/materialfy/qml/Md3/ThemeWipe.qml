import QtQuick

// Смена темы через снимок: снимок source со старыми цветами кладётся поверх, тема переключается
// мгновенно под ним, и снимок уходит. Дешевле плавной анимации цветов: все привязки пересчитываются
// один раз, а не каждый кадр, дальше — один текстурный слой. Как уходит снимок — mode:
//   wipe     — шторка в сторону direction;
//   ripple   — новое расходится фигурой от центра originItem (без него — от центра окна);
//   dissolve — снимок равномерно тает;
//   liquid   — снимок тает по плавному шуму и «плывёт», волна идёт в сторону direction.
// Подключение: Theme.wipe = themeWipe (source — всё содержимое окна, сам ThemeWipe — вне его, поверх).
Item {
    id: root

    property Item source
    property string mode: "wipe"
    property Item originItem
    readonly property int duration: ({ ripple: 900, dissolve: 1000, liquid: 1200 })[mode] ?? 650
    readonly property bool running: _phase !== 0

    readonly property int _mode: Math.max(0, ["wipe", "ripple", "dissolve", "liquid"].indexOf(mode))
    property int _phase: 0          // 0 — нет, 1 — снимаем кадр, 2 — снимок уходит
    property int _frames: 0
    property real _dir: 1
    property point _origin: Qt.point(0.5, 0.5)
    property real _seed: 0
    property var _apply: null

    // Запуск: apply() переключает тему; вызывается, когда снимок со старыми цветами уже готов.
    function start(direction, apply) {
        anim.stop()
        _dir = direction < 0 ? -1 : 1
        _apply = apply
        _frames = 0
        _seed = Math.random() * 50
        const it = originItem
        if (it && it.visible && width > 0 && height > 0) {
            const p = mapFromItem(it, it.width / 2, it.height / 2)
            _origin = Qt.point(p.x / width, p.y / height)
        } else {
            _origin = Qt.point(0.5, 0.5)
        }
        _phase = 1
        snap.scheduleUpdate()
    }

    ShaderEffectSource {
        id: snap
        sourceItem: root._phase !== 0 ? root.source : null
        live: false
        hideSource: false
        visible: false
    }

    // Видна и во время снимка (с shown: 0): текстура источника обновляется, только когда её кто-то рисует.
    ShaderEffect {
        anchors.fill: parent
        visible: root._phase !== 0
        property variant source: snap
        property real progress: 0
        property real dir: root._dir
        property real edge: 0.22
        property real skew: 0.12
        property real shown: root._phase === 2 ? 1 : 0
        property real mode: root._mode
        property real aspect: width / Math.max(1, height)
        property real seed: root._seed
        property point origin: root._origin
        fragmentShader: Qt.resolvedUrl("shaders/wipe.frag.qsb")

        NumberAnimation on progress {
            id: anim
            running: false
            from: 0
            to: 1
            duration: root.duration
            // шторка и волна — быстро стартуют и долго тормозят; таяние — ровно
            easing.type: root._mode >= 2 ? Easing.InOutSine : Easing.BezierSpline
            easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
            onFinished: root._phase = 0
        }
    }

    // Снимок рендерится в синхронизации ближайшего кадра; на втором тике он точно готов.
    FrameAnimation {
        running: root._phase === 1
        onTriggered: {
            if (++root._frames < 2)
                return
            root._phase = 2
            if (root._apply)
                root._apply()
            root._apply = null
            anim.restart()
        }
    }
}
