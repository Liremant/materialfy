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
    property real anchorPos: spicy ? 0.36 : 0.33
    // Подложка под текстом: "none" — прозрачно; "soft" | "strong" — затемнение в цвет темы
    readonly property string scrimMode: Settings.lyricsScrim
    readonly property real scrimAlpha: scrimMode === "strong" ? 0.6 : (scrimMode === "soft" ? 0.28 : 0)

    // Стиль отображения:
    // "normal" — классический вид: каскад, размытые соседние строки, выравнивание влево;
    // "spicy" — выразительная волна по словам с широким градиентным заполнением и мягким свечением;
    // "karaoke" — караоке: крупная строка с чёткой заливкой по словам и плавным увеличением.
    readonly property string mode: Settings.lyricsMode
    readonly property bool spicy: mode === "spicy"
    readonly property bool karaoke: mode === "karaoke"

    // Параметры внешнего вида и поведения: настройки переопределяют значения по умолчанию стиля
    readonly property string align: Settings.lyricsTextAlign
    readonly property real blurAmount: Settings.lyricsBlurAmount
    readonly property bool blurInactive: blurAmount > 0.001
    readonly property string linesMode: Settings.lyricsVisibleLines
    readonly property string fillMode: Settings.lyricsFillMode
    readonly property bool motion: Settings.lyricsAnimate && !Theme.reducedMotion

    // Ручные настройки акцента строки, амплитуды волны слов и прозрачности соседних строк
    // (с безопасным запасом по умолчанию, если мост Settings собран без новых ключей).
    readonly property real userActiveScale: Settings.lyricsActiveScale ?? 0
    readonly property real activeScale: userActiveScale >= 1.0
        ? userActiveScale
        : (spicy ? 1.12 : (karaoke ? 1.20 : 1.0))
    readonly property real idleScale: Settings.lyricsIdleScale > 0 ? Settings.lyricsIdleScale : 1.0
    readonly property real wordBounce: Settings.lyricsWordBounce ?? 1.0
    readonly property real dimAlpha: Settings.lyricsDimOpacity ?? (spicy ? 0.34 : 0.35)
    readonly property bool uniformDim: fillMode === "off"
    readonly property real baseSpacingScale: spicy ? 1.12 : 1.0
    readonly property real spacingScale: baseSpacingScale * Settings.lyricsLineSpacing
    readonly property real highlightMultiplier: Settings.lyricsHighlight
    property bool showSource: Settings.lyricsShowSource

    // Число видимых строк вокруг активной: "one"/"1" → 0, "three"/"3" → 1, "all"/"15" → все,
    // либо любое число N из ползунка «Видимые строки» (показывает N строк вокруг текущей).
    readonly property int maxVisibleDist: {
        const s = String(linesMode ?? "all").trim()
        if (s === "all" || s === "")
            return 999
        if (s === "one")
            return 0
        if (s === "three")
            return 1
        const n = parseInt(s, 10)
        if (!isNaN(n) && n >= 1)
            return n >= 15 ? 999 : Math.floor((n - 1) / 2)
        return 999
    }

    property real fadeTopPct: 0.22
    property real fadeBottomPct: 0.18
    property int scrollDuration: !Settings.lyricsAnimate ? 0 : (Settings.lyricsScrollMs >= 0 ? Settings.lyricsScrollMs : (spicy ? 420 : (karaoke ? 480 : 650)))
    property int scrollStagger: !Settings.lyricsAnimate ? 0 : (Settings.lyricsStaggerMs >= 0 ? Settings.lyricsStaggerMs : (spicy ? 28 : (karaoke ? 32 : 45)))
    // Плавное упреждение прокрутки: строка мягко доезжает к anchorPos к началу первой ноты,
    // а подсветка и заливка идут точно по позиции аудио (см. tick()).
    property int scrollLeadMs: 240
    readonly property int scrollAheadMs: !Settings.lyricsAnimate ? 0 : (spicy ? 240 : Math.max(scrollLeadMs, Math.round(scrollDuration * 0.48)))
    property color textColor: Theme.fgSurface
    property int resumeMs: 3000

    readonly property var lines: Lyrics.lines
    // Трек уже сменился, а текст ещё от прошлого: гасим и не обрабатываем (иначе позиция 0 запускает
    // каскад прокрутки по всем строкам старого текста — несколько тяжёлых кадров подряд).
    readonly property bool stale: Lyrics.trackId !== Player.trackId
    readonly property bool live: visible && !stale && lines.length > 0
    onLiveChanged: if (live) { jumpTimer.restart(); sync(Player.positionMs / 1000); tick() }

    // Шрифт изначально растеризуется в полном размере активной строки (fontSize * activeScale):
    // тогда у активной строки масштаб слоя равен ровно 1.0 (100% нативная резкость пикселей без мыла),
    // а неактивные строки плавно уменьшаются через GPU Scale (idleScale / activeScale) без перестройки раскладки!
    readonly property real activeFontPx: Math.round(fontSize * activeScale)
    readonly property real rowH: activeFontPx * 1.22
    readonly property real lineGap: fontSize * 0.56 * root.spacingScale
    readonly property real liftPx: fontSize * 0.075 * root.wordBounce
    readonly property real sidePad: Math.max(12, fontSize * 0.4)
    readonly property var scrollBezier: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]
    readonly property url fillShader: Qt.resolvedUrl("shaders/wordfill.frag.qsb")

    property real pos: 0
    property int activeIndex: -1
    property int _targetScrollIndex: -1
    readonly property int scrollIndex: _targetScrollIndex

    signal shifted(real dy)

    onLinesChanged: {
        jumpTimer.restart()      // новый текст встаёт на место без анимации
        following = true
        manualAnim.running = false
        activeIndex = -1
        _targetScrollIndex = -1
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
                    } else if (!root.stale && root.lines.length > 0) {
                        root._lines = root.lines
                        root._built = 0
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
    property real _seekTarget: 0
    property real _seekStartMs: 0
    property real _seekGuardUntil: 0
    // пока говорит DJ, трек стоит на месте: позиция не идёт, хотя плеер «играет».
    // То же, пока трек ещё грузится: «играет» в это время оптимистично, а звука нет.
    readonly property bool advancing: Player.playing && !Player.narrating && !Player.buffering
    property bool _wasPlaying: advancing
    onAdvancingChanged: resyncPlayback()

    function playerPos() {
        return _basePos + (_wasPlaying ? (Date.now() - _baseTime) / 1000 : 0)
    }
    function sync(p) {
        _basePos = p
        _baseTime = Date.now()
    }

    // Пауза/буферизация: возвращаемся к измеренной позиции, а не к замороженной
    function resyncPlayback() {
        if (root.advancing && !root._wasPlaying)
            root.sync(Player.positionMs / 1000)
        else
            root.sync(root.playerPos())
        root._wasPlaying = root.advancing
    }

    Connections {
        target: Player
        function onPositionChanged() {
            if (!root.live)
                return
            const now = Date.now()
            const measured = Player.positionMs / 1000
            // После клика по строке плеер может ещё до ~1 с присылать старую позицию до перемотки
            if (now < root._seekGuardUntil && Math.abs(measured - root._seekTarget) > 0.35) {
                if (now - root._seekStartMs < 1000)
                    root._seekGuardUntil = now + 180
                return
            }
            const cur = root.playerPos()
            const err = measured - cur
            if (err < -0.08 || Math.abs(err) > 0.3)
                root.sync(measured)
            else
                // подтягиваем только вперёд: с откатом назад текст пятился посреди слога
                root.sync(Math.max(root.pos, cur + err * 0.35))
            root.tick()
        }
        function onStateChanged() { root.resyncPlayback() }
    }

    function tick() {
        pos = playerPos()
        const L = lines

        // Подсветка и заливка идут ровно по позиции: активна всегда строго одна текущая строка
        const at = pos
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

        // Упреждение прокрутки: колонка начинает движение чуть заранее
        const atScroll = pos + scrollAheadMs / 1000
        let si = _targetScrollIndex
        if (si >= L.length || (si >= 0 && L[si].t > atScroll) || si < -1) {
            let lo = 0, hi = L.length - 1
            si = -1
            while (lo <= hi) {
                const mid = (lo + hi) >> 1
                if (L[mid].t <= atScroll) { si = mid; lo = mid + 1 } else hi = mid - 1
            }
        } else {
            while (si + 1 < L.length && L[si + 1].t <= atScroll)
                si++
        }
        if (si !== _targetScrollIndex)
            _targetScrollIndex = si
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
        // клик по строке перематывает к её началу с защитой от старого отсчёта плеера
        const at = Math.max(0, t)
        const now = Date.now()
        _seekTarget = at
        _seekStartMs = now
        _seekGuardUntil = now + 350
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
        font.pixelSize: root.activeFontPx
        font.variableAxes: Theme.fontAxes(root.activeFontPx, 700)
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

    // Верхнее затухание не заходит на целевую строку (используем scrollIndex, как и colTargetY)
    readonly property real fadeTopTarget: {
        const want = viewport.height * fadeTopPct
        const idx = Math.max(0, scrollIndex)
        const it = lineRep.count > idx ? lineRep.itemAt(idx) : null
        if (!it || !following)
            return want
        return Math.max(0, Math.min(want, colTargetY + restY(idx) - lineGap * 0.25))
    }
    property real fadeTopPx: fadeTopTarget
    Behavior on fadeTopPx {
        NumberAnimation { duration: root.motion ? 240 : 0; easing.type: Easing.OutCubic }
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
        const idx = Math.max(0, scrollIndex)
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
        _scrollIndex = scrollIndex
        if (!jumpTimer.running && Math.abs(dy) > 0.5)
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
        _scrollIndex = scrollIndex
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
        // Активна всегда строго одна строка (isActive): две строки никогда не поют одновременно.
        // Для плавного завершения волны последнего слова предыдущей строки даём 240 мс «хвоста» затухания.
        readonly property bool filling: !isGap && isActive
        readonly property bool wordsAnimating: !isGap && (isActive || (index === root.activeIndex - 1 && (root.pos - (modelData.e ?? 0)) < 0.24))
        readonly property bool isTarget: !isGap && (isActive || (root.following && index === root.activeIndex + 1 && ((modelData.t ?? 0) - root.pos) <= 0.11))
        readonly property int dist: root.activeIndex < 0 ? index + 1 : Math.abs(index - root.activeIndex)
        readonly property real gapProgress: isGap && isActive ? Math.max(0, Math.min(1, (root.pos - (modelData.t ?? 0)) / Math.max(0.1, (modelData.e ?? 0) - (modelData.t ?? 0)))) : 0
        readonly property bool hovered: hover.hovered

        // И в Spicy, и в Караоке, и при ручном увеличении масштаба строки шрифт всегда отрендерен
        // в полном размере activeFontPx (масштаб 1.0 на активной строке = 100% чёткость без мыла),
        // а неактивные строки мягко уменьшены до idleNormScale через GPU Scale без перестройки текста!
        readonly property real idleNormScale: root.idleScale / Math.max(1.0, root.activeScale)
        readonly property real targetScale: !isGap ? (isTarget ? 1.0 : idleNormScale) : 1.0
        property real lineScale: targetScale
        Behavior on lineScale {
            enabled: root.motion && !Theme.lowPower
            NumberAnimation {
                duration: root.karaoke ? 280 : 250
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.scrollBezier
            }
        }
        readonly property real lineSize: root.activeFontPx
        readonly property real rowH: root.rowH

        // Фильтр видимости строк (ползунок от 1 до 15 / Все)
        readonly property bool inLineRange: {
            if (root.maxVisibleDist >= 999)
                return true
            return root.activeIndex < 0 ? index <= root.maxVisibleDist : dist <= root.maxVisibleDist
        }

        width: col.width
        // Свёрнутая пауза сохраняет волосок высоты: Column не расставляет элементы нулевого размера.
        // Раскрывается она вместе с прокруткой (scrollIndex), чтобы колонка не дёргалась.
        readonly property real restHeight: isGap
            ? ((isActive || index === root.scrollIndex) ? root.rowH * 1.1 + root.lineGap : 0.01)
            : wordsBox.height + root.lineGap
        height: restHeight
        clip: isGap

        Behavior on height {
            enabled: line.isGap
            SequentialAnimation {
                PauseAnimation { duration: Math.max(0, Math.min(7, line.index - Math.max(0, root.scrollIndex) + 1)) * root.scrollStagger }
                NumberAnimation { duration: root.scrollDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.scrollBezier }
            }
        }

        // Появление нового текста: строки выплывают снизу волной, начиная от активной.
        // Непопадающие в диапазон строки мягко растворяются до 0, сохраняя раскладку.
        property real appear: 0
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
            const rel = line.index - Math.max(0, root.activeIndex - 2)
            if (rel < 0 || rel > 14) {
                line.appear = 1
                return
            }
            appearAnim.delayMs = root.motion ? (root.spicy ? 60 + rel * 35 : 110 + rel * 50) : 0
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
                duration: root.motion ? (root.spicy ? 480 : 620) : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.motion.emphasizedDecelerate
            }
        }

        Connections {
            target: root
            function onShifted(dy) {
                const wasMoving = scrollAnim.running
                scrollAnim.stop()
                const anchor = root.scrollIndex >= 0 ? root.scrollIndex : Math.max(0, root.activeIndex)
                const rel = line.index - anchor
                // строкам за экраном анимация не нужна
                const sy = col.y + line.y + shift.y + dy
                if (sy > viewport.height * 2 || sy + line.height < -viewport.height) {
                    shift.y = 0
                    return
                }
                shift.y += dy
                scrollAnim.delayMs = wasMoving ? 0 : Math.max(0, Math.min(7, rel + 1)) * root.scrollStagger
                scrollAnim.interrupted = wasMoving
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

            // Подъём всей строки целиком в режиме «Вся строка» (fillMode === "line")
            property real wholeLineLift: (line.filling && root.fillMode === "line" && root.motion)
                ? -root.liftPx * (root.spicy ? 0.85 : 0.55)
                : 0
            Behavior on wholeLineLift {
                enabled: root.motion && !Theme.lowPower
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            transform: [
                Scale {
                    origin.x: root.align === "center" ? wordsBox.width / 2 : (root.align === "right" ? wordsBox.width : 0)
                    origin.y: wordsBox.height / 2
                    xScale: line.lineScale
                    yScale: line.lineScale
                },
                Translate {
                    y: wordsBox.wholeLineLift
                }
            ]

            // В режиме «word» активная строка сразу непрозрачна (1.0), а неспетые слова внутри неё
            // приглушены ровно до root.dimAlpha без двойного умножения.
            // В режиме «line» («Вся строка: активная строка загорается целиком») вся строка плавно
            // вспыхивает до 1.0 за 220 мс. В режиме «off» все строки остаются ярко читаемыми.
            readonly property real inactiveOpacity: root.fillMode === "off"
                ? (line.hovered ? 0.92 : 0.78)
                : Math.max(
                    0.12,
                    root.dimAlpha * (line.hovered ? 1.85 : (1 - (root.spicy ? 0.11 : 0.09) * Math.max(0, line.dist - 1)))
                )
            property real fadeOpacity: line.filling ? 1.0 : inactiveOpacity
            Behavior on fadeOpacity {
                NumberAnimation {
                    duration: root.motion ? (root.spicy ? 210 : 280) : 0
                    easing.type: Easing.OutCubic
                }
            }
            opacity: (line.filling && root.fillMode === "word") ? 1.0 : fadeOpacity

            // Активная и наведённая строки полностью чёткие, а соседние строки плавно размываются
            // пропорционально расстоянию (как applyBlur в Spicy Lyrics).
            readonly property real rawBlur: (line.isTarget || line.filling || line.hovered)
                ? 0.0
                : Math.min(1, ((root.spicy ? 0.15 : 0.12) + (root.spicy ? 0.13 : 0.11) * Math.max(0, line.dist - 1)) * root.blurAmount)
            property real lineBlur: rawBlur
            Behavior on lineBlur {
                enabled: root.motion && !Theme.lowPower
                NumberAnimation { duration: root.spicy ? 220 : 260; easing.type: Easing.OutCubic }
            }

            readonly property bool blurred: root.blurInactive && line.inLineRange && line.dist < 12
                && (lineBlur > 0.001 || rawBlur > 0.001)
            layer.enabled: blurred
            layer.smooth: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: root.spicy ? 18 : 16
                blur: wordsBox.lineBlur
                autoPaddingEnabled: true
            }

            // Перенос слов по строкам с поддержкой выравнивания влево, по центру и вправо.
            // Так как на активной строке lineScale == 1.0, доступная ширина равна полной ширине колонки!
            readonly property var layout: {
                const n = wordRep.count
                const avail = Math.max(1, width)
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
                    widths[row] = x - (it && it.spaced ? Math.max(0, w - tw) : 0)
                }
                let maxW = 0
                for (let r = 0; r <= row; r++)
                    if ((widths[r] ?? 0) > maxW) maxW = widths[r]
                if (root.align === "center") {
                    for (let i = 0; i < pos.length; i++)
                        pos[i].x += Math.max(0, (maxW - (widths[pos[i].row] ?? 0)) / 2)
                } else if (root.align === "right") {
                    for (let i = 0; i < pos.length; i++)
                        pos[i].x += Math.max(0, maxW - (widths[pos[i].row] ?? 0))
                }
                return { pos: pos, rows: row + 1, lineWidth: maxW }
            }

            Item {
                id: lineWords
                x: root.align === "center"
                    ? Math.max(0, (wordsBox.width - (wordsBox.layout?.lineWidth ?? 0)) / 2)
                    : (root.align === "right" ? Math.max(0, wordsBox.width - (wordsBox.layout?.lineWidth ?? 0)) : 0)
                width: Math.max(1, wordsBox.layout?.lineWidth ?? 0)
                height: wordsBox.height

                Repeater {
                    id: wordRep
                    model: line.isGap ? [] : line.modelData.w
                    delegate: LyricWord {
                        lineActive: line.filling
                        wordAnimating: line.wordsAnimating
                        // 1 — слово уже спели, 2 — в активной строке, 0 — ещё не пели
                        sungState: (root.activeIndex >= 0 && line.index < root.activeIndex) ? 1
                                 : (line.filling ? 2 : 0)
                        fontSize: line.lineSize
                        rowH: line.rowH
                        useWordShader: line.filling && root.fillMode === "word"
                        x: wordsBox.layout.pos[index]?.x ?? 0
                        y: (wordsBox.layout.pos[index]?.row ?? 0) * line.rowH
                    }
                }
            }
        }

        // Пауза: три фигуры «дышат» и заполняются
        Row {
            visible: line.isGap
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -root.lineGap / 2
            x: root.align === "center"
                ? Math.max(0, (parent.width - width) / 2)
                : (root.align === "right" ? Math.max(0, parent.width - width - root.fontSize * 0.1) : root.fontSize * 0.1)
            spacing: root.fontSize * 0.24
            transformOrigin: Item.Center
            scale: {
                if (!line.isActive)
                    return 0.6
                const breathe = 1 + 0.09 * Math.sin(root.pos * Math.PI * 2 / 1.9)
                const tail = Math.max(0, Math.min(1, ((line.modelData.e ?? 0) - root.pos) / 0.45))
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
        property bool wordAnimating: false
        property bool useWordShader: false
        property real fontSize: root.activeFontPx
        property real rowH: root.rowH

        readonly property string txt: modelData.x.replace(/\s+$/, "")
        readonly property bool spaced: /\s$/.test(modelData.x)
        readonly property real textWidth: label.implicitWidth
        readonly property real dur: Math.max(0.001, (modelData.e ?? 0) - (modelData.s ?? 0))
        readonly property bool held: dur >= 0.95 && txt.length <= 14
        // root.pos читается только пока строка активна (или доигрывает хвост 240 мс)
        readonly property real progress: lineActive ? root.wordProgress(modelData, root.pos) : (sungState === 1 ? 1 : 0)
        required property int sungState

        // Плавная кривая Эрмита (smoothstep) и трёхфазная огибающая (Attack → Sustain → Release)
        // в реальном времени (секундах), как пружины в Spicy Lyrics:
        // слово быстро всплывает за ~220 мс, держится на гребне волны, пока звучит нота, и мягко
        // опускается за ~210 мс после окончания, образуя непрерывную бегущую волну по соседним словам.
        function ease(x) { return x <= 0 ? 0 : (x >= 1 ? 1 : x * x * (3 - 2 * x)) }

        readonly property real envelope: {
            if (!wordAnimating || root.fillMode !== "word")
                return 0
            const s = (modelData.s ?? 0) - 0.03
            const e = (modelData.e ?? 0)
            const t = root.pos
            const attack = Math.min(0.24, Math.max(0.14, dur * 0.65))
            const release = 0.21
            if (t <= s)
                return 0
            if (t >= e + release)
                return 0
            if (t < s + attack)
                return word.ease((t - s) / attack)
            if (t <= e)
                return 1.0
            return 1.0 - word.ease((t - e) / release)
        }

        readonly property bool alreadySung: sungState === 1 || (lineActive && root.pos >= (modelData.e ?? 0))

        // Масштаб слова в Spicy: 0.96 (до пения) → 1.0 + 0.072*bounce (на гребне) → 1.00 (спето)
        readonly property real sungScale: {
            if (!root.spicy || root.karaoke || root.fillMode !== "word")
                return 1.0
            const env = word.envelope
            const rest = word.alreadySung ? 1.0 : 0.96
            if (env <= 0.001)
                return rest
            const peak = 1.0 + 0.072 * root.wordBounce
            const vibrato = (word.held && env > 0.85) ? 0.014 * root.wordBounce * Math.sin((root.pos - (modelData.s ?? 0)) * Math.PI * 4.5) : 0
            return rest + (peak - rest) * env + vibrato
        }

        // Вертикальный подъём слова («волна» Spicy Lyrics):
        // до пения слово чуть ниже (+0.014em), на гребне поднимается до −0.088em (~3.5–4.5 px) и садится в 0
        readonly property real sungLiftEm: {
            if (!root.spicy || root.karaoke || root.fillMode !== "word")
                return 0
            const env = word.envelope
            const rest = word.alreadySung ? 0.0 : 0.014 * root.wordBounce
            if (env <= 0.001)
                return rest
            const peak = -0.088 * root.wordBounce
            return rest + (peak - rest) * env
        }

        readonly property real glow: {
            if (!wordAnimating)
                return 0
            if (root.fillMode === "line")
                return root.spicy && lineActive ? 0.45 * root.highlightMultiplier : 0
            if (root.fillMode !== "word")
                return 0
            if (root.spicy)
                return 0.90 * word.envelope * root.highlightMultiplier
            if (root.karaoke)
                return 0
            return (held ? Math.sin(Math.PI * progress) : 0) * root.highlightMultiplier
        }

        // Пробел на конце слова — из общей метрики, отмасштабированной под размер строки
        implicitWidth: label.implicitWidth + (spaced ? spaceMetrics.advanceWidth * (fontSize / Math.max(1, root.activeFontPx)) : 0)
        implicitHeight: rowH

        // Мягкий световой ореол вокруг поющегося слова в Spicy (аналог --text-shadow-blur-radius в Spicy Lyrics):
        // включается только в стиле Spicy на том слове, которое прямо сейчас светится.
        Text {
            id: glowHalo
            visible: root.spicy && word.glow > 0.015 && !Theme.lowPower && root.motion
            anchors.centerIn: label
            text: word.txt
            font.family: Theme.fontFamily
            font.pixelSize: word.fontSize
            font.weight: Theme.variableFont ? Font.Normal : Font.Bold
            font.variableAxes: Theme.fontAxes(word.fontSize, 700)
            color: root.textColor
            opacity: Math.min(0.68, word.glow * 0.58)
            scale: label.scale * 1.04
            transform: Translate { y: wordTranslate.y }
            layer.enabled: visible
            layer.smooth: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 20
                blur: 0.78
                autoPaddingEnabled: true
            }
        }

        Text {
            id: label
            // Google Sans рисует ≈1.36em в высоту, а строка держит 1.22em: текстура слоя без запаса
            // срезала нижние выносные элементы. Добираем высоту паддингом — текст остаётся на месте.
            readonly property real layerOverscan: Math.ceil(word.fontSize * 0.25)
            height: word.rowH + 2 * layerOverscan
            topPadding: layerOverscan
            bottomPadding: layerOverscan
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
            text: word.txt
            font.family: Theme.fontFamily
            font.pixelSize: word.fontSize
            font.weight: Theme.variableFont ? Font.Normal : Font.Bold
            font.variableAxes: Theme.fontAxes(word.fontSize, 700)
            color: root.textColor
            transformOrigin: root.spicy ? Item.Center : Item.Bottom
            scale: root.spicy ? word.sungScale
                 : (word.useWordShader ? (1 + 0.045 * word.glow * root.wordBounce) : 1.0)
            Behavior on scale {
                enabled: root.spicy && root.motion && !Theme.lowPower
                NumberAnimation { duration: 95; easing.type: Easing.OutQuad }
            }

            transform: Translate {
                id: wordTranslate
                y: root.spicy ? word.sungLiftEm * word.fontSize
                   : (word.lineActive && word.useWordShader
                      ? -root.liftPx * (root.karaoke ? Math.sin(Math.PI * word.progress) : root.easeOut(word.progress * 1.6))
                      : 0)
                Behavior on y {
                    enabled: root.motion && !Theme.lowPower && (root.spicy || !word.lineActive)
                    NumberAnimation { duration: root.spicy ? 105 : 360; easing.type: Easing.OutCubic }
                }
            }

            // Держим слой включённым на всех словах активной строки в режиме «word», чтобы сглаживание
            // и чёткость шрифта не менялись скачком при переходе от слова к слову; на остальных
            // неактивных строках и в режимах «line»/«off» слои слов полностью выключены.
            layer.enabled: word.useWordShader
            layer.smooth: true
            layer.effect: ShaderEffect {
                // Адаптивная ширина градиента в пикселях: и короткие, и длинные слова получают
                // одинаково мягкий край заливки в Spicy и Классике, а в Караоке — чёткий срез.
                readonly property real featherPx: word.fontSize * (root.spicy ? 0.72 : 0.45)
                readonly property real baseFeather: root.karaoke
                    ? 0.002
                    : (root.spicy
                        ? Math.max(0.34, Math.min(0.62, featherPx / Math.max(1, label.width)))
                        : Math.min(0.5, featherPx / Math.max(1, label.width) / 2))
                property real feather: Math.max(0.001, baseFeather * root.highlightMultiplier)
                property real progress: -feather + word.progress * (1 + 2 * feather)
                property real dimAlpha: root.dimAlpha
                property real glow: word.glow
                fragmentShader: root.fillShader
            }
        }
    }
}
