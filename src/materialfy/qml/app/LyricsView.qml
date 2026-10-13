import QtQuick
import QtQuick.Effects
import Md3
import Materialfy.Core

// Синхронный текст играющего трека с заливкой по словам (порт виджета Word Lyrics для DMS).
// Активная строка держится на высоте anchorPos; при смене строки текст едет каскадом:
// строки ниже трогаются чуть позже. Неактивные строки приглушены и размыты, паузы — «• • •».
// Клик по строке — перемотка к ней. Колесо, тачпад и перетаскивание прокручивают текст вручную:
// слежение за строкой встаёт на паузу и возвращается через resumeMs или кнопкой «К текущей строке».
Item {
    id: root

    // Базовый размер задаёт место вызова (полный плеер, боковая панель); настройка «Размер текста»
    // масштабирует его. Всё остальное (высота строки, отступы, фигуры пауз) считается от fontSize.
    property real baseFontSize: 34
    property real fontSize: baseFontSize * Settings.lyricsFontScale
    property real anchorPos: spicy ? 0.38 : 0.33
    // Подложка под текстом: "none" — прозрачно; "soft" | "strong" — затемнение в цвет темы
    readonly property string scrimMode: Settings.lyricsScrim
    readonly property real scrimAlpha: scrimMode === "strong" ? 0.6 : (scrimMode === "soft" ? 0.28 : 0)

    // Стиль отображения:
    // "normal" — классический вид: каскад, размытые соседние строки, выравнивание влево;
    // "spicy" — крупная поющаяся строка со сглаженным градиентным заполнением и свечением;
    // "karaoke" — караоке: крупная строка с чёткой заливкой по словам и подъёмом без свечения.
    readonly property string mode: Settings.lyricsMode
    readonly property bool spicy: mode === "spicy"
    readonly property bool karaoke: mode === "karaoke"

    // Параметры внешнего вида и поведения: настройки переопределяют значения по умолчанию стиля
    readonly property string align: Settings.lyricsTextAlign === "auto" ? "left" : Settings.lyricsTextAlign
    readonly property real blurAmount: Settings.lyricsBlurAmount
    readonly property bool blurInactive: blurAmount > 0.001
    readonly property string linesMode: Settings.lyricsVisibleLines === "auto" ? "all" : Settings.lyricsVisibleLines
    readonly property string fillMode: Settings.lyricsFillMode === "auto" ? "word" : Settings.lyricsFillMode
    readonly property bool motion: Settings.lyricsAnimate && !Theme.reducedMotion
    readonly property real activeScale: spicy ? 1.30 : (karaoke ? 1.20 : 1.0)
    readonly property real idleScale: spicy ? 0.97 : 1.0
    readonly property real dimAlpha: 0.35
    readonly property bool uniformDim: false
    readonly property real baseSpacingScale: spicy ? 1.08 : 1.0
    readonly property real spacingScale: baseSpacingScale * Settings.lyricsLineSpacing
    readonly property real highlightMultiplier: Settings.lyricsHighlight
    property bool showSource: Settings.lyricsShowSource

    property real fadeTopPct: 0.22
    property real fadeBottomPct: 0.18
    property int scrollDuration: !Settings.lyricsAnimate ? 0 : (spicy ? 500 : 700)
    property int scrollStagger: !Settings.lyricsAnimate ? 0 : (spicy ? 0 : 45)
    property int scrollLeadMs: 250
    property color textColor: Theme.fgSurface
    property int resumeMs: 3000

    readonly property var lines: Lyrics.lines
    // Трек уже сменился, а текст ещё от прошлого: гасим и не обрабатываем (иначе позиция 0 запускает
    // каскад прокрутки по всем строкам старого текста — несколько тяжёлых кадров подряд).
    readonly property bool stale: Lyrics.trackId !== Player.trackId
    readonly property bool live: visible && !stale && lines.length > 0
    onLiveChanged: if (live) { jumpTimer.restart(); sync(Player.positionMs / 1000); tick() }
    readonly property real rowH: fontSize * 1.22
    readonly property real lineGap: fontSize * 0.62 * root.spacingScale
    readonly property real liftPx: fontSize * 0.07
    readonly property real sidePad: Math.max(12, fontSize * 0.4)
    readonly property var scrollBezier: [0.42, 0.0, 0.58, 1.0, 1.0, 1.0]
    readonly property url fillShader: Qt.resolvedUrl("shaders/wordfill.frag.qsb")

    property real pos: 0
    property int activeIndex: -1

    signal shifted(real dy)

    onLinesChanged: {
        jumpTimer.restart()      // новый текст встаёт на место без анимации
        following = true
        manualAnim.running = false
        activeIndex = -1
        rebuild()
        tick()
    }

    // ── строки ──────────────────────────────────────────────────────────────
    // Текст на 40–60 строк — это сотни элементов-слов. Созданные разом (да ещё в двух представлениях:
    // плеер и боковая панель), они давали провал ~300 мс при каждой смене трека. Поэтому строки
    // строятся только в видимом представлении и порциями по несколько штук за кадр.
    property var _lines: []                // текст, по которому построены делегаты
    property var _pending: null            // новый текст ждёт, пока разберутся строки старого
    property int _built: 0
    property bool _tearing: false
    readonly property int buildChunk: 3

    // Разборка старых строк тоже порциями (разом — ~50 мс). Делегаты привязаны к _lines, поэтому
    // новый текст подставляется только после того, как старые строки убраны.
    function rebuild() {
        _pending = lines
        if (lineModel.count > 0)
            _tearing = true
        else
            _adopt()
        builder.running = true
    }
    function _adopt() {
        _lines = _pending ?? []
        _pending = null
        _built = 0
    }
    onVisibleChanged: if (visible && _built < _lines.length) builder.running = true

    // Трек сменился — старые строки можно убирать, не дожидаясь нового текста (он уже погас)
    onStaleChanged: if (stale) staleTeardown.restart()
    Timer {
        id: staleTeardown
        interval: 180
        onTriggered: {
            if (root.stale && lineModel.count > 0) {
                root._tearing = true
                builder.running = true
            }
        }
    }

    ListModel { id: lineModel }
    FrameAnimation {
        id: builder
        running: false
        onTriggered: {
            if (root._tearing) {
                const n = Math.min(lineModel.count, root.buildChunk * 2)
                if (n > 0)
                    lineModel.remove(lineModel.count - n, n)
                if (lineModel.count === 0) {
                    root._tearing = false
                    if (root._pending !== null) {
                        root._adopt()
                    } else {
                        root._lines = []
                        root._built = 0
                    }
                }
                return
            }
            if (!root.visible || root._built >= root._lines.length) {
                running = false
                return
            }
            const until = Math.min(root._lines.length, root._built + root.buildChunk)
            for (; root._built < until; root._built++)
                lineModel.append({ line: root._built })
            jumpTimer.restart()               // пока строится — без каскада прокрутки
            if (root._built >= root._lines.length) {
                running = false
                root.tick()
            }
        }
    }

    // ── позиция ─────────────────────────────────────────────────────────────
    // Плеер присылает позицию ~5 раз в секунду; между обновлениями — по часам,
    // мелкий дрейф подтягивается плавно, перемотка — скачком.
    property real _basePos: 0
    property real _baseTime: 0
    // пока говорит DJ, трек стоит на месте: позиция не идёт, хотя плеер «играет».
    // То же, пока трек ещё грузится: «играет» в это время оптимистично, а звука нет.
    readonly property bool advancing: Player.playing && !Player.narrating && !Player.buffering
    property bool _wasPlaying: advancing

    function playerPos() {
        return _basePos + (_wasPlaying ? (Date.now() - _baseTime) / 1000 : 0)
    }
    function sync(p) {
        _basePos = p
        _baseTime = Date.now()
    }

    Connections {
        target: Player
        function onPositionChanged() {
            if (!root.live)
                return
            const measured = Player.positionMs / 1000
            const err = measured - root.playerPos()
            root.sync(Math.abs(err) > 0.3 ? measured : root.playerPos() + err * 0.35)
            root.tick()
        }
        function onStateChanged() {
            root.sync(root.playerPos())
            root._wasPlaying = root.advancing
        }
    }

    Connections {
        target: Settings
        function onLyricsSyncMsChanged() { root.tick() }
    }

    function tick() {
        pos = playerPos() + Settings.lyricsSyncMs / 1000
        // строка становится активной (и начинает ехать) чуть раньше, чем её поют
        const at = pos + scrollLeadMs / 1000
        const L = lines
        let i = activeIndex
        if (i >= L.length || (i >= 0 && L[i].t > at) || i < -1) {
            let lo = 0, hi = L.length - 1
            i = -1
            while (lo <= hi) {
                const mid = (lo + hi) >> 1
                if (L[mid].t <= at) { i = mid; lo = mid + 1 } else hi = mid - 1
            }
        } else {
            while (i + 1 < L.length && L[i + 1].t <= at)
                i++
        }
        if (i !== activeIndex)
            activeIndex = i
    }

    FrameAnimation {
        running: root.live && root.advancing && !Theme.lowPower
        onTriggered: root.tick()
    }
    // программный рендер: заливка слов — по общим часам Ticker (~30 Гц), а не в каждом кадре монитора
    TickAnimation {
        running: root.live && root.advancing && Theme.lowPower
        onTriggered: root.tick()
    }

    function seekTo(t) {
        // строки показаны со сдвигом синхронизации — перематываем туда, где строка и правда звучит
        const at = Math.max(0, t + 0.02 - Settings.lyricsSyncMs / 1000)
        Player.seekMs(Math.round(at * 1000))
        sync(at)
        tick()
    }

    function wordProgress(w, p) {
        if (p <= w.s) return 0
        if (p >= w.e) return 1
        if (!w.p) return (p - w.s) / Math.max(0.001, w.e - w.s)
        let total = 0, done = 0
        for (const part of w.p) total += part[0]
        for (const part of w.p) {
            if (p >= part[2]) done += part[0]
            else if (p > part[1]) done += part[0] * (p - part[1]) / Math.max(0.001, part[2] - part[1])
        }
        return Math.min(1, done / total)
    }

    function easeOut(x) {
        return 1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 3)
    }

    TextMetrics {
        id: spaceMetrics
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        font.variableAxes: Theme.fontAxes(root.fontSize, 700)
        text: " "
    }

    // ── нет текста ──────────────────────────────────────────────────────────
    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 380)
        visible: !root.stale && root.lines.length === 0 && Lyrics.status !== "loading"
        icon: "title"
        shape: "flower6"
        title: !Player.hasTrack ? I18n.t("Nothing's playing")
             : Player.isEpisode ? I18n.t("Episodes don't have lyrics")
             : Lyrics.status === "error" ? I18n.t("Lyrics didn't load")
             : I18n.t("No lyrics")
        text: !Player.hasTrack ? I18n.t("Lyrics for the playing track will appear here")
            : Player.isEpisode ? I18n.t("Only songs have lyrics")
            : Lyrics.status === "error" ? I18n.t("Sources didn't respond — I'll try again on the next track")
            : I18n.t("No source has lyrics for this track")
    }
    LoadingIndicator {
        anchors.centerIn: parent
        visible: Lyrics.status === "loading" || (root.stale && Player.hasTrack)
    }

    // ── подложка под текст ──────────────────────────────────────────────────
    Rectangle {
        id: scrimRect
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        anchors.leftMargin: Math.max(4, root.sidePad * 0.25)
        anchors.rightMargin: Math.max(4, root.sidePad * 0.25)
        radius: Theme.shape.extraLarge
        color: Theme.surface
        opacity: root.lines.length > 0 && !root.stale ? root.scrimAlpha : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.motion ? 260 : 0 } }
    }

    // ── текст ───────────────────────────────────────────────────────────────
    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        visible: root.lines.length > 0 && opacity > 0
        opacity: root.stale || root._tearing ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Края растворяются в прозрачность (а не в цвет фона — под текстом бывает обложка). На программном
        // рендере — без слоя, края просто обрезаны: слой с меняющимся текстом удваивает кадры (Qt просит
        // следующий после каждого изменения содержимого) и сам стоит лишнего прохода по всему тексту
        layer.enabled: !Theme.lowPower
        layer.effect: ShaderEffect {
            property real fadeTop: root.fadeTopPx / Math.max(1, viewport.height)
            property real fadeBottom: root.fadeBottomPx / Math.max(1, viewport.height)
            property real cut: 0
            fragmentShader: Qt.resolvedUrl("shaders/edgefade.frag.qsb")
        }

        Column {
            id: col
            x: root.sidePad
            width: parent.width - root.sidePad * 2
            spacing: 0

            Repeater {
                id: lineRep
                model: lineModel
                delegate: LyricLine {}
            }
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            orientation: Qt.Vertical
            property real fineUntil: 0   // тачпад Windows: доли щелчка — сразу, без доводки (см. SmoothScroll)
            onWheel: event => {
                // тачпад узнаём по фазе жеста (см. SmoothScroll): пиксели 1:1, колесо — шагами с доводкой
                if (event.phase !== Qt.NoScrollPhase) {
                    root.userScroll(event.pixelDelta.y, false)
                } else {
                    const a = Math.abs(event.angleDelta.y)
                    const now = Date.now()
                    if (a % 120 !== 0)
                        fineUntil = now + 400
                    const notches = event.angleDelta.y !== 0 ? event.angleDelta.y / 120 : event.pixelDelta.y / 15
                    root.userScroll(notches * Settings.wheelStep, now >= fineUntil)
                }
            }
        }
        DragHandler {
            id: dragger
            target: null
            xAxis.enabled: false
            property real _last: 0
            onActiveChanged: _last = 0
            onTranslationChanged: {
                if (!active)
                    return
                root.userScroll(translation.y - _last, false)
                _last = translation.y
            }
        }
    }

    Button {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        z: 2
        size: "xs"
        style: "tonal"
        icon: "lyrics"
        text: I18n.t("Back to current line")
        visible: opacity > 0
        opacity: !root.following && root.lines.length > 0 && !root.stale ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
        onClicked: root.resumeFollowing()
    }

    Label {
        visible: root.showSource && root.lines.length > 0 && Lyrics.source !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        text: Lyrics.kind === "word" ? I18n.t("{0} · word by word", Lyrics.source) : I18n.t("{0} · line by line", Lyrics.source)
        type: "labelSmall"
        color: Theme.fgSurfaceVariant
        opacity: 0.6
    }

    // Верхнее затухание не заходит на активную строку
    readonly property real fadeTopPx: {
        const want = viewport.height * fadeTopPct
        const idx = Math.max(0, activeIndex)
        const it = lineRep.count > idx ? lineRep.itemAt(idx) : null
        if (!it || !following)
            return want
        return Math.max(0, Math.min(want, colTargetY + restY(idx) - lineGap * 0.25))
    }
    readonly property real fadeBottomPx: viewport.height * fadeBottomPct

    // Прокрутка: колонка сразу встаёт в цель, а каждая строка получает компенсирующий сдвиг,
    // который уходит в 0 со своей задержкой. Цель — «устоявшаяся» раскладка: раскрывающаяся
    // пауза двигает только строки под собой, а не весь текст туда-обратно.
    function restY(idx) {
        const it = lineRep.itemAt(idx)
        if (!it)
            return 0
        let y = it.y
        for (let j = 0; j < idx; j++) {
            const g = lineRep.itemAt(j)
            if (g && g.isGap)
                y += g.restHeight - g.height
        }
        return y
    }

    readonly property real colTargetY: {
        const idx = Math.max(0, activeIndex)
        const it = lineRep.count > idx ? lineRep.itemAt(idx) : null
        if (!it)
            return viewport.height * anchorPos
        return viewport.height * anchorPos - (restY(idx) + it.restHeight / 2)
    }

    property int _scrollIndex: -2
    onColTargetYChanged: Qt.callLater(applyScroll)

    function applyScroll() {
        if (!following)
            return
        const dy = col.y - colTargetY
        col.y = colTargetY
        const lineChanged = activeIndex !== _scrollIndex
        _scrollIndex = activeIndex
        if (lineChanged && !jumpTimer.running && Math.abs(dy) > 0.5)
            shifted(dy)
    }

    Timer { id: jumpTimer; interval: 250 }

    // ── ручная прокрутка ────────────────────────────────────────────────────
    // Пока пользователь листает, колонка стоит там, куда её увели (col.y), а активная строка
    // только подсвечивается; возврат — тем же каскадом строк, что и обычная смена строки.
    property bool following: true
    property real _manualTarget: 0
    readonly property real manualMaxY: viewport.height * anchorPos
    readonly property real manualMinY: viewport.height * anchorPos - col.height

    function _clampManual(y) { return Math.max(manualMinY, Math.min(manualMaxY, y)) }
    function userScroll(dy, smooth) {
        if (lines.length === 0)
            return
        if (following) {
            following = false
            _manualTarget = col.y
        }
        const base = smooth && manualAnim.running ? _manualTarget : col.y
        _manualTarget = _clampManual(base + dy)
        if (smooth) {
            manualAnim.running = true
        } else {
            manualAnim.running = false
            col.y = _manualTarget
        }
        resumeTimer.restart()
    }
    function resumeFollowing() {
        resumeTimer.stop()
        manualAnim.running = false
        if (following)
            return
        following = true
        const dy = col.y - colTargetY
        col.y = colTargetY
        _scrollIndex = activeIndex
        if (Math.abs(dy) > 0.5)
            shifted(dy)
    }

    Timer {
        id: resumeTimer
        interval: root.resumeMs
        onTriggered: if (!dragger.active) root.resumeFollowing(); else restart()
    }

    // доводка колеса — как в SmoothScroll: экспонента, целые пиксели
    FrameAnimation {
        id: manualAnim
        running: false
        onTriggered: {
            const d = root._manualTarget - col.y
            if (Math.abs(d) < 0.5) {
                col.y = root._manualTarget
                running = false
                return
            }
            const step = d * (1 - Math.exp(-frameTime * 14))
            col.y = Math.round(col.y + (Math.abs(step) < 1 ? Math.sign(d) : step))
        }
    }

    // ── строка ──────────────────────────────────────────────────────────────
    component LyricLine: Item {
        id: line

        required property int index
        readonly property var modelData: root._lines[index] ?? ({ gap: true, t: 0, e: 0 })

        readonly property bool isGap: !!modelData.gap
        readonly property bool isActive: index === root.activeIndex
        // root.pos читают только активная строка и предыдущая — остальные не пересчитываются каждый кадр
        readonly property bool filling: !isGap && (isActive || (index === root.activeIndex - 1 && root.pos < modelData.e))
        readonly property int dist: root.activeIndex < 0 ? index + 1 : Math.abs(index - root.activeIndex)
        readonly property real gapProgress: isGap && isActive ? Math.max(0, Math.min(1, (root.pos - modelData.t) / Math.max(0.1, modelData.e - modelData.t))) : 0
        readonly property bool hovered: hover.hovered
        // Масштаб строки зависит от стиля: в spicy и karaoke поющаяся строка крупнее соседних
        readonly property real lineScale: isActive ? root.activeScale : root.idleScale
        readonly property real lineSize: root.fontSize * lineScale
        readonly property real rowH: lineSize * 1.22
        // Фильтр видимости строк: "all" — все строки; "three" — активная и соседи; "one" — только активная
        readonly property bool inLineRange: {
            if (root.linesMode === "one")
                return root.activeIndex < 0 ? index === 0 : dist === 0
            if (root.linesMode === "three")
                return root.activeIndex < 0 ? index <= 2 : dist <= 1
            return true
        }

        width: col.width
        // Свёрнутая пауза сохраняет волосок высоты: Column не расставляет элементы нулевого размера
        readonly property real restHeight: isGap ? (isActive ? root.rowH * 1.1 + root.lineGap : 0.01) : wordsBox.height + root.lineGap
        height: restHeight
        clip: isGap

        Behavior on height {
            enabled: line.isGap
            SequentialAnimation {
                PauseAnimation { duration: Math.max(0, Math.min(7, line.index - Math.max(0, root.activeIndex) + 1)) * root.scrollStagger }
                NumberAnimation { duration: root.scrollDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.scrollBezier }
            }
        }

        // Появление нового текста: строки выплывают снизу волной, начиная от активной.
        // Непопадающие в диапазон строки мягко растворяются до 0, сохраняя раскладку.
        property real appear: 0
        // анимируется только выход из диапазона видимых строк: «волна» появления идёт своим ходом
        property real rangeOpacity: inLineRange ? 1 : 0
        Behavior on rangeOpacity {
            NumberAnimation { duration: root.motion ? 260 : 0; easing.type: Easing.OutCubic }
        }
        opacity: appear * rangeOpacity
        transform: [
            Translate { id: shift },
            Translate { y: (1 - line.appear) * root.fontSize * 1.1 }
        ]
        Component.onCompleted: Qt.callLater(() => {
            // к этому моменту activeIndex уже выставлен по позиции плеера
            const rel = line.index - Math.max(0, root.activeIndex - 2)
            if (rel < 0 || rel > 14) {        // за пределами видимого — сразу на месте
                line.appear = 1
                return
            }
            appearAnim.delayMs = (root.motion && !root.spicy) ? 120 + rel * 55 : 0
            appearAnim.start()
        })
        SequentialAnimation {
            id: appearAnim
            property int delayMs: 0
            PauseAnimation { duration: appearAnim.delayMs }
            NumberAnimation {
                target: line
                property: "appear"
                to: 1
                duration: root.motion ? (root.spicy ? 500 : 650) : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.motion.emphasizedDecelerate
            }
        }

        Connections {
            target: root
            function onShifted(dy) {
                const wasMoving = scrollAnim.running
                scrollAnim.stop()
                const rel = line.index - Math.max(0, root.activeIndex)
                // строкам за экраном анимация не нужна
                const sy = col.y + line.y + shift.y + dy
                if (sy > viewport.height * 2 || sy + line.height < -viewport.height) {
                    shift.y = 0
                    return
                }
                shift.y += dy
                scrollAnim.delayMs = wasMoving ? 0 : Math.max(0, Math.min(7, rel + 1)) * root.scrollStagger
                scrollAnim.interrupted = wasMoving   // прерванная строка не должна замирать и разгоняться заново
                scrollAnim.start()
            }
        }

        SequentialAnimation {
            id: scrollAnim
            property int delayMs: 0
            property bool interrupted: false
            PauseAnimation { duration: scrollAnim.delayMs }
            NumberAnimation {
                target: shift
                property: "y"
                to: 0
                duration: root.scrollDuration
                easing.type: scrollAnim.interrupted ? Easing.OutCubic : Easing.BezierSpline
                easing.bezierCurve: root.scrollBezier
            }
        }

        Rectangle {
            x: -root.sidePad * 0.6
            y: -root.lineGap * 0.3
            width: line.width + root.sidePad * 1.2
            height: wordsBox.height + root.lineGap * 0.6
            radius: Theme.shape.large
            color: root.textColor
            opacity: line.hovered && !line.isGap ? 0.08 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        Item {
            id: wordsBox
            visible: !line.isGap
            width: line.width
            height: line.isGap ? 0 : Math.max(1, layout.rows) * line.rowH

            // Строка, начавшая заливаться, сразу непрозрачна: неспетые слова приглушает шейдер
            opacity: line.filling ? 1 : fadeOpacity
            property real fadeOpacity: line.filling ? 1 : Math.max(0.22, root.dimAlpha * (line.hovered ? 1.9 : (root.uniformDim ? 1 : (1 - 0.1 * Math.max(0, line.dist - 1)))))
            Behavior on fadeOpacity { NumberAnimation { duration: root.motion ? 380 : 0; easing.type: Easing.OutCubic } }

            readonly property bool blurred: root.blurInactive && !line.filling && !line.hovered && line.dist < 8 && line.inLineRange
            layer.enabled: blurred
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 16
                blur: Math.min(1, (0.12 + 0.11 * Math.max(0, line.dist - 1)) * root.blurAmount)
                autoPaddingEnabled: true
            }

            // Перенос слов по строкам (Flow не умеет выравнивание, а раскладка нужна заранее).
            // Для выравнивания по центру каждая строка сдвигается на половину остатка ширины.
            readonly property var layout: {
                const n = wordRep.count
                const avail = width
                const pos = []
                const widths = []
                let x = 0, row = 0
                for (let i = 0; i < n; i++) {
                    const it = wordRep.itemAt(i)
                    const w = it ? it.implicitWidth : 0
                    const tw = it ? it.textWidth : 0
                    if (x > 0 && x + tw > avail) {
                        row++
                        x = 0
                    }
                    pos.push({ x: x, row: row })
                    x += w
                    widths[row] = x
                }
                if (root.align === "center")
                    for (let i = 0; i < pos.length; i++)
                        pos[i].x += Math.max(0, (avail - (widths[pos[i].row] ?? 0)) / 2)
                return { pos: pos, rows: row + 1 }
            }

            Repeater {
                id: wordRep
                model: line.isGap ? [] : line.modelData.w
                delegate: LyricWord {
                    lineActive: line.filling
                    fontSize: line.lineSize
                    rowH: line.rowH
                    x: wordsBox.layout.pos[index]?.x ?? 0
                    y: (wordsBox.layout.pos[index]?.row ?? 0) * line.rowH
                }
            }
        }

        // Пауза: три фигуры «дышат» и заполняются
        Row {
            visible: line.isGap
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -root.lineGap / 2
            x: root.fontSize * 0.1
            spacing: root.fontSize * 0.24
            transformOrigin: Item.Center
            scale: {
                if (!line.isActive)
                    return 0.6
                const breathe = 1 + 0.09 * Math.sin(root.pos * Math.PI * 2 / 1.9)
                const tail = Math.max(0, Math.min(1, (line.modelData.e - root.pos) / 0.45))
                return breathe * (0.35 + 0.65 * root.easeOut(tail))
            }
            opacity: line.isActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            // Вместо точек — три маленькие фигуры MD3E: «наливаются» по очереди и медленно вращаются
            Repeater {
                model: ["cookie4", "clover4", "cookie6"]
                MorphShape {
                    required property int index
                    required property string modelData
                    readonly property real fill: Math.max(0, Math.min(1, line.gapProgress * 3 - index))
                    width: root.fontSize * 0.6
                    height: width
                    shape: fill >= 1 ? "cookie9" : modelData
                    color: root.textColor
                    opacity: root.dimAlpha + (1 - root.dimAlpha) * fill
                    rotation: line.isActive ? root.pos * (index % 2 ? -40 : 50) + index * 30 : 0
                }
            }
        }

        // Обработчики, а не MouseArea: MouseArea забрала бы нажатие, и перетаскивание текста не началось бы
        HoverHandler {
            id: hover
            enabled: !line.isGap && line.inLineRange
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: !line.isGap && line.inLineRange
            onTapped: {
                root.seekTo(line.modelData.t)
                root.resumeFollowing()
            }
        }
    }

    // ── слово ───────────────────────────────────────────────────────────────
    component LyricWord: Item {
        id: word

        required property var modelData
        required property int index
        property bool lineActive: false
        // Размер слова — размер его строки (в «караоке» и «spicy» он свой у активной)
        property real fontSize: root.fontSize
        property real rowH: root.rowH

        readonly property string txt: modelData.x.replace(/\s+$/, "")
        readonly property bool spaced: /\s$/.test(modelData.x)
        readonly property real textWidth: label.implicitWidth
        readonly property real dur: modelData.e - modelData.s
        readonly property bool held: dur >= 1.1 && txt.length <= 14
        // root.pos читается, только пока строка активна
        readonly property real progress: lineActive ? root.wordProgress(modelData, root.pos) : 0
        readonly property real glow: {
            if (!lineActive)
                return 0
            if (root.spicy)
                return 0.55 * Math.sin(Math.PI * progress) * root.highlightMultiplier
            if (root.karaoke)
                return 0
            return (held ? Math.sin(Math.PI * progress) : 0) * root.highlightMultiplier
        }

        // Пробел на конце слова — из общей метрики, отмасштабированной под размер строки
        implicitWidth: label.implicitWidth + (spaced ? spaceMetrics.advanceWidth * (fontSize / Math.max(1, root.fontSize)) : 0)
        implicitHeight: rowH

        Text {
            id: label
            height: word.rowH
            verticalAlignment: Text.AlignVCenter
            text: word.txt
            font.family: Theme.fontFamily
            font.pixelSize: word.fontSize
            font.weight: Theme.variableFont ? Font.Normal : ((root.spicy && word.lineActive) ? Font.Black : Font.Bold)
            font.variableAxes: (root.spicy && word.lineActive)
                ? Theme.fontAxes(word.fontSize, 820)
                : Theme.fontAxes(word.fontSize, 700)
            color: root.textColor
            transformOrigin: Item.Bottom
            scale: !root.spicy && root.fillMode === "word" ? (1 + 0.045 * word.glow) : 1.0

            transform: Translate {
                y: (!root.spicy && word.lineActive && root.fillMode === "word") ? -root.liftPx * root.easeOut(word.progress * 1.6) : 0
                Behavior on y {
                    enabled: !root.spicy && !word.lineActive
                    NumberAnimation { duration: root.motion ? 400 : 0; easing.type: Easing.OutCubic }
                }
            }

            layer.enabled: word.lineActive && root.fillMode !== "off"
            layer.effect: ShaderEffect {
                readonly property real featherPx: word.fontSize * 0.45
                readonly property real baseFeather: root.spicy ? 0.32 : Math.min(0.5, featherPx / Math.max(1, label.width) / 2)
                property real feather: Math.max(0.001, baseFeather * root.highlightMultiplier)
                property real progress: root.fillMode === "line" ? (1.0 + feather) : (-feather + word.progress * (1 + 2 * feather))
                property real dimAlpha: root.dimAlpha
                property real glow: root.fillMode === "word" ? word.glow : 0
                fragmentShader: root.fillShader
            }
        }
    }
}
