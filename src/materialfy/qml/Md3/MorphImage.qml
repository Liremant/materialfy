import QtQuick
import Materialfy.Core

// Картинка (обложка), обрезанная по фигуре MD3 с морфингом.
// Один ShaderEffect (shaders/shapeimage.frag): текстура — сама Image, маска считается аналитически,
// подложка-заглушка — тот же шейдер. Раньше на каждую обложку было два offscreen-слоя
// (маска + MultiEffect) и ещё одна фигура-заглушка; на главной таких обложек десятки.
Item {
    id: root

    property url source
    readonly property alias status: image.status
    property alias shape: m.shape
    property real angle: 0
    property alias duration: m.duration
    property alias livingSpeed: m.livingSpeed
    property real pulse: 0                  // «дыхание» фигуры; картинка внутри не двигается

    // Поворот фигуры-рамки, градусы: картинка внутри стоит. Только uniform, контур не пересчитывается.
    // Медленное вращение — MaskSpin.
    property real maskRotation: 0

    function jumpTo(next) { m._ready = false; shape = next; m._set(next); m._ready = true }

    // Картинка грузится, когда элемент впервые показан: скрытые плитки (свёрнутые ряды «Все»), закрытые
    // панели не держат декодированные обложки. Показанная однажды не выгружается. eager — грузить сразу.
    property bool eager: false

    // Не загрузилась — ещё попытка (сетевой менеджер к тому времени переходит на другое зеркало Spotify), потом
    // запасная обложка по названию (Covers: iTunes, Deezer, Яндекс). Повтор — с меткой #rN: Qt помнит неудачную
    // загрузку адреса и тот же адрес сразу отдал бы ту же ошибку; фрагмент на сервер не уходит. fallbackKind: "album" | "track" |
    // "artist"; fallbackArtist — первый исполнитель; fallbackTitle — альбом или трек (у исполнителя пусто).
    property string fallbackKind
    property string fallbackArtist
    property string fallbackTitle
    property int _tries: 0
    property url _fallback
    property string _fallbackKey
    onSourceChanged: {
        _tries = 0
        _fallback = ""
        _fallbackKey = ""
        retry.stop()
    }
    function _failed() {
        if (_tries < 1) {
            retry.restart()
        } else if (fallbackKind !== "" && fallbackArtist !== "" && _fallbackKey === "" && _fallback.toString() === "") {
            _fallbackKey = Covers.find(fallbackKind, fallbackArtist, fallbackTitle)
        }
    }
    Timer {
        id: retry
        interval: 1500
        onTriggered: root._tries += 1
    }
    Connections {
        target: root._fallbackKey !== "" ? Covers : null
        function onFound(key, url) {
            if (key === root._fallbackKey && url !== "")
                root._fallback = url
        }
    }

    property bool _shownOnce: false
    onVisibleChanged: if (visible) _shownOnce = true
    Component.onCompleted: if (visible) _shownOnce = true
    property color placeholderColor: Theme.surfaceContainerHighest

    ShapeMorph {
        id: m
        active: root.visible && root.opacity > 0
    }

    Image {
        id: image
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        // Грузим, когда размер уже известен: иначе первая загрузка шла с размером 0 (128 px), а сразу
        // за ней — вторая под настоящий размер. Размер — с запасом до ступени: четверть старшей степени
        // двойки (не меньше 16 px): 48 → 48, 168 → 192, 440 → 448 — шаги ресайза окна не перезагружают
        // картинку каждый раз, а лишних пикселей не больше ~1,5×. Каждый пиксель стоит памяти трижды:
        // QImage в кэше Qt Quick и текстура (у драйвера D3D11 — ещё и своя копия).
        function _fit(px) {
            const step = Math.max(16, Math.pow(2, Math.floor(Math.log2(Math.max(1, px)))) / 4)
            return Math.max(16, Math.ceil(px / step) * step)
        }
        readonly property bool _sized: root.width > 0 && root.height > 0
        // Гейт декода: реальный источник подставляется, только когда ImageGate дал слот.
        // _hold — запрошено и ждёт очереди; null-источник никуда не уходит, заявка снимается.
        property bool _gateOn: false
        property bool _hold: false
        readonly property string _want: !_sized || !(root.eager || root._shownOnce) || root.source.toString() === "" ? ""
              : root._fallback.toString() !== "" ? root._fallback
              : root._tries > 0 ? root.source + "#r" + root._tries : root.source
        function qmlContinue() {
            _gateOn = true
            image.source = _want
        }
        function _releaseGate() {
            if (_hold) {
                _hold = false
                ImageGate.release(root)
            }
        }
        on_WantChanged: {
            if (_want === "") {
                _releaseGate()
                _gateOn = false
                image.source = ""
            } else if (!_hold && !_gateOn) {
                if (ImageGate.acquire(root)) {
                    _gateOn = true
                    image.source = _want
                } else {
                    _hold = true
                }
            } else if (_gateOn) {
                image.source = _want
            }
        }
        // обложка ушла из виду (делегат переиспользован/скрыт) — слот отдаём очереди
        on_VisibleChanged: if (!root.visible) _releaseGate()
        Component.onDestruction: _releaseGate()
        source: _gateOn ? _want : ""
        sourceSize: Qt.size(_fit(root.width * Screen.devicePixelRatio), _fit(root.height * Screen.devicePixelRatio))
        retainWhileLoading: true
        smooth: true
        property bool shown: false          // был хоть один кадр (при перезагрузке виден прежний)
        onStatusChanged: {
            if (status === Image.Ready)
                shown = true
            else if (status === Image.Error || status === Image.Null)
                shown = false
            if (status === Image.Ready || status === Image.Error) {
                _gateOn = false
                _releaseGate()
            }
            if (status === Image.Error)
                root._failed()
        }
    }

    ShaderEffect {
        id: fx
        readonly property real pad: Math.ceil(Math.min(root.width, root.height) * 0.06) + 1
        x: -pad
        y: -pad
        width: root.width + 2 * pad
        height: root.height + 2 * pad
        visible: root.width > 0 && root.height > 0 && (ready > 0 || root.placeholderColor.a > 0)

        readonly property real ready: image.shown && image.source.toString() !== "" ? 1 : 0
        property real _shown: ready
        // на программном рендере обложка появляется сразу: затухания десятков обложек, догружающихся
        // вразнобой, держали бы перерисовку окна секунду-другую после открытия страницы
        Behavior on _shown { enabled: !Theme.reducedMotion && !Theme.lowPower; NumberAnimation { duration: 150 } }

        property var source: image
        property vector4d a0: m.a[0]
        property vector4d a1: m.a[1]
        property vector4d a2: m.a[2]
        property vector4d a3: m.a[3]
        property vector4d b0: m.b[0]
        property vector4d b1: m.b[1]
        property vector4d b2: m.b[2]
        property vector4d b3: m.b[3]
        property vector4d c0: m.c[0]
        property vector4d c1: m.c[1]
        property vector4d c2: m.c[2]
        property vector4d c3: m.c[3]
        property vector4d morph: Qt.vector4d(m.s, m.t, (root.angle + root.maskRotation) * Math.PI / 180, root.pulse)
        property vector4d misc: Qt.vector4d(m.time, 0, _shown, 0)
        // box.zw — PreserveAspectCrop: какая доля текстуры видна по осям
        readonly property real _iw: Math.max(1, image.implicitWidth)
        readonly property real _ih: Math.max(1, image.implicitHeight)
        readonly property real _k: (root.width / Math.max(1, root.height)) / (_iw / _ih)
        property vector4d box: Qt.vector4d(width / Math.max(1, root.width), height / Math.max(1, root.height),
                                           _k < 1 ? _k : 1, _k > 1 ? 1 / _k : 1)
        property color fill: root.placeholderColor
        property color stroke: "transparent"
        fragmentShader: "shaders/shapeimage.frag.qsb"
    }
}
