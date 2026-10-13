import QtQuick
import Qt.labs.platform as Platform
import Md3
import Materialfy.Core

// Островок («динамический вырез»): отдельное окно поверх всех у верхнего края экрана, на котором главное окно.
// Чёрное, как железо, при любой теме; прижато к краю, скруглены только нижние углы, у края — вогнутые «плечи».
// Три вида одного и того же объекта (как Dynamic Island у Apple):
//   compact  — слева обложка, справа «эквалайзер» в такт (на паузе — значок паузы): одна мысль на две стороны;
//   minimal  — давно на паузе: только обложка;
//   expanded — наведение мыши (через 120 мс; сворачивается через 400 мс после ухода) и на 2.5 с при смене трека:
//              обложка, название, перемотка, «назад / играть / дальше», лайк.
// Обложка и полоски не пропадают при смене вида, а переезжают — объект тот же, меняется только размер.
// Окно — во весь размер раскрытого островка, а мышь ловит только форма (маска окна, WindowShell.setMask):
// прозрачная часть пропускает клики к окнам под ней.
Window {
    id: root

    required property Window mainWindow
    // --set islandState=compact | minimal | expanded — вид для снимков (наведение и пауза не влияют)
    property string forcedState: ""
    // --set floatingShot=<path.png>: снимок окна через 9 с (прозрачный фон — альфа-каналом)
    property string shotPath: ""
    Timer {
        interval: 9000
        running: root.shotPath !== ""
        onTriggered: root.contentItem.grabToImage(result => result.saveToFile(root.shotPath))
    }

    // Уровни звука нужны, пока видны живые полоски (Main.qml собирает это с полноэкранным плеером)
    readonly property bool wantsLevels: visible && Player.playing && Player.isLocal === true && !Theme.lowPower

    // ---- Размеры (логические px) ----
    readonly property real compactW: 220
    readonly property real compactH: 34
    readonly property real minimalW: 46
    readonly property real expandedW: 420
    readonly property real expandedH: 152
    readonly property real ear: 8          // вогнутое скругление у края экрана

    // Цвета: Чёрный (OLED аппаратный) или Цветной (адаптивная тональная палитра)
    readonly property bool colorMode: Settings.floatingPlayerStyle === "color"
    readonly property color body: colorMode ? Theme.surfaceContainerHighest : "#000000"
    readonly property color ink: colorMode ? Theme.fgSurface : "#ffffff"
    readonly property color inkDim: colorMode ? Theme.fgSurfaceVariant : Qt.rgba(1, 1, 1, 0.62)
    readonly property color accent: colorMode ? Theme.primary : (Theme.dark ? Theme.primary : Theme.inversePrimary)

    // Без анимации размеров: reduced motion и режим для слабых ПК
    readonly property bool still: Theme.reducedMotion || Theme.lowPower

    readonly property string mode: forcedState !== "" ? forcedState
        : (_hoverExpand || _announce) ? "expanded"
        : (!Player.playing && _pausedLong) ? "minimal" : "compact"
    readonly property real targetW: mode === "expanded" ? expandedW : mode === "minimal" ? minimalW : compactW
    readonly property real targetH: mode === "expanded" ? expandedH : compactH

    width: expandedW + 2 * ear + 24        // запас на перелёт пружины
    height: expandedH + 12
    color: "transparent"
    title: "Materialfy"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    // Без владельца: окно, принадлежащее главному, Windows прячет вместе с ним (свёрнуто, в трее)
    transientParent: null
    screen: mainWindow.screen
    x: screen.virtualX + Math.round((screen.width - width) / 2)
    y: screen.virtualY

    property bool _ready: false
    property bool _fullscreenBusy: false
    visible: _ready && (!_fullscreenBusy || shotPath !== "")

    Component.onCompleted: {
        WindowShell.makeToolWindow(root)
        _applyMask()
        _ready = true
    }

    // ---- Вид: наведение, смена трека, долгая пауза ----
    property bool _hoverExpand: false
    property bool _announce: false
    property bool _pausedLong: false
    Timer { id: hoverIn; interval: 120; onTriggered: root._hoverExpand = true }
    Timer { id: hoverOut; interval: 400; onTriggered: root._hoverExpand = false }
    Timer { id: announceEnd; interval: 2500; onTriggered: root._announce = false }
    Timer {
        interval: 15000
        running: !Player.playing
        onTriggered: root._pausedLong = true
    }
    Connections {
        target: Player
        function onStateChanged() { if (Player.playing) root._pausedLong = false }
        // Новый трек — островок ненадолго раскрывается сам (важное обновление), если движение не убрано
        function onTrackChanged() {
            if (Player.uri === root._lastUri)
                return
            const first = root._lastUri === ""
            root._lastUri = Player.uri
            if (first || root.still || root._hoverExpand)
                return
            root._announce = true
            announceEnd.restart()
        }
    }
    property string _lastUri: Player.uri

    // Полноэкранное приложение (видео, игра, презентация) — островок над ним не висит
    Timer {
        interval: 2000
        repeat: true
        running: Qt.platform.os === "windows"
        triggeredOnStart: true
        onTriggered: root._fullscreenBusy = WindowShell.fullscreenBusy()
    }

    // ---- Маска окна: форма с запасом; пока форма растёт или сжимается — по большему из размеров ----
    readonly property real _maskW: Math.ceil((Math.max(island.width, targetW) + 2 * ear + 4) / 8) * 8
    readonly property real _maskH: Math.ceil((Math.max(island.height, targetH) + 4) / 8) * 8
    on_MaskWChanged: Qt.callLater(_applyMask)
    on_MaskHChanged: Qt.callLater(_applyMask)
    onWidthChanged: Qt.callLater(_applyMask)
    function _applyMask() {
        const w = Math.min(width, _maskW)
        WindowShell.setMask(root, Math.floor((width - w) / 2), 0, w, Math.min(height, _maskH))
    }

    // ---- Форма ----
    Item {
        id: island
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: root.targetW
        height: root.targetH
        // Пружина MD3 Expressive: раскрытие — с лёгким перелётом, сворачивание — ровно
        Behavior on width {
            enabled: !root.still
            NumberAnimation {
                duration: Theme.motion.spatialDefault
                easing.type: root.mode === "expanded" ? Easing.OutBack : Easing.BezierSpline
                easing.overshoot: 1.1
                easing.bezierCurve: Theme.motion.emphasized
            }
        }
        Behavior on height {
            enabled: !root.still
            NumberAnimation {
                duration: Theme.motion.spatialDefault
                easing.type: root.mode === "expanded" ? Easing.OutBack : Easing.BezierSpline
                easing.overshoot: 1.1
                easing.bezierCurve: Theme.motion.emphasized
            }
        }

        // 0 — компактный, 1 — раскрытый (с перелётом пружины чуть больше 1)
        readonly property real t: Math.max(0, (height - root.compactH) / (root.expandedH - root.compactH))
        readonly property real tc: Math.min(1, t)
        readonly property real pad: 12 + 4 * tc

        // тело: прямые верхние углы (у края экрана), скруглённые нижние
        Rectangle {
            anchors.fill: parent
            color: root.body
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Math.min(height / 2, 14 + 14 * island.tc)
            bottomRightRadius: bottomLeftRadius
            antialiasing: true
        }
        // «Плечи»: вогнутые скругления, которыми вырез переходит в край экрана
        component Ear: Item {
            id: earItem
            property bool mirrored: false
            width: root.ear
            height: root.ear
            y: 0
            clip: true
            Rectangle {
                readonly property real r: root.ear + 30
                x: earItem.mirrored ? root.ear - r : -r
                y: root.ear - r
                width: 2 * r
                height: 2 * r
                radius: r
                color: "transparent"
                border.width: 30
                border.color: root.body
                antialiasing: true
            }
        }
        Ear { x: -root.ear }
        Ear { x: island.width; mirrored: true }

        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered) {
                    hoverOut.stop()
                    hoverIn.restart()
                } else {
                    hoverIn.stop()
                    hoverOut.restart()
                }
            }
        }

        // Колесо — громкость, как у мини-плеера: щелчок ±5 %, тачпад плавно; проценты — на месте полосок
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                if (Player.remote === true && Player.canSetVolume === false)
                    return
                const touchpad = event.pixelDelta.y !== 0 && event.angleDelta.y % 120 !== 0
                const d = touchpad ? event.pixelDelta.y / 600 : event.angleDelta.y / 120 * 0.05
                Player.volume = Math.max(0, Math.min(1, Player.volume + d))
                volumeHint.shown = true
                volumeHintHide.restart()
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: islandMenu.open()
        }

        // ---- Обложка: 22 px слева в компактном виде → 64 px в раскрытом ----
        Item {
            id: cover
            readonly property real size: 22 + (64 - 22) * island.t
            x: Math.min(island.pad, (island.width - size) / 2)
            y: 6 + 10 * island.t
            width: size
            height: size
            MorphImage {
                id: coverImage
                anchors.fill: parent
                visible: Player.cover !== ""
                source: island.tc > 0.3 && Player.coverLarge !== "" ? Player.coverLarge : Player.cover
                placeholderColor: "#262626"
                fallbackKind: Player.album !== "" ? "album" : "track"
                fallbackArtist: Player.artist.split(", ")[0]
                fallbackTitle: Player.album !== "" ? Player.album : Player.title
                shape: island.tc > 0.5 && Player.playing ? "cookie12" : "softSquare"
            }
            Rectangle {
                anchors.fill: parent
                visible: Player.cover === ""
                radius: width * 0.28
                color: "#262626"
                Icon { anchors.centerIn: parent; name: Player.isEpisode ? "podcasts" : "music_note"; size: parent.width * 0.55; color: root.inkDim }
            }
            TapHandler { onTapped: WindowShell.raiseMain() }
        }

        // ---- Полоски в такт (справа); на паузе — значок паузы; при смене громкости — проценты ----
        Item {
            id: trailing
            width: 20
            height: 16
            x: island.width - island.pad - 2 - width
            y: (root.compactH - height) / 2 + (20 - (root.compactH - height) / 2) * island.tc
            opacity: Math.max(0, Math.min(1, (island.width - 90) / 40))
            visible: opacity > 0

            Bars {
                anchors.fill: parent
                opacity: Player.playing && !volumeHint.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsDefault } }
            }
            Icon {
                anchors.centerIn: parent
                name: "pause"
                fill: 1
                size: 16
                color: root.inkDim
                opacity: !Player.playing && !volumeHint.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsDefault } }
            }
        }
        Row {
            id: volumeHint
            property bool shown: false
            anchors.right: trailing.right
            anchors.verticalCenter: trailing.verticalCenter
            spacing: 3
            opacity: shown ? 1 : 0
            // в минимальном виде места справа нет — там только обложка
            visible: opacity > 0 && trailing.visible
            Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
            Timer { id: volumeHintHide; interval: 1000; onTriggered: volumeHint.shown = false }
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "volume_up"; size: 14; fill: 1; color: root.accent }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Player.volume * 100) + "%"
                type: "labelMedium"
                color: root.ink
            }
        }

        // ---- Раскрытый вид ----
        Item {
            id: details
            anchors.fill: parent
            opacity: Math.max(0, Math.min(1, (island.t - 0.55) / 0.45))
            visible: opacity > 0
            enabled: root.mode === "expanded"

            // Название и исполнитель — справа от обложки; клик поднимает главное окно
            Column {
                x: cover.x + cover.width + 12
                y: cover.y + 8
                width: island.width - x - island.pad - trailing.width - 12
                spacing: 2
                Label {
                    width: parent.width
                    text: Player.title
                    type: "titleMedium"
                    color: root.ink
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: Player.artist
                    type: "bodyMedium"
                    color: root.inkDim
                    elide: Text.ElideRight
                }
                TapHandler { onTapped: WindowShell.raiseMain() }
            }

            // Перемотка: прошло — волна — осталось
            PlayerProgress { id: progress; active: details.visible && !seek.dragging }
            Item {
                id: seekRow
                x: island.pad
                y: cover.y + 64 + 8
                width: island.width - 2 * island.pad
                height: 16
                Label {
                    id: elapsed
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    text: root._time(seek.dragging ? seek.dragValue * Player.durationMs : Player.positionMs)
                    type: "labelSmall"
                    color: root.inkDim
                }
                WavyProgress {
                    id: seek
                    anchors.left: elapsed.right
                    anchors.right: remaining.left
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    height: 14
                    thickness: 3
                    amplitude: 2
                    wavelength: 26
                    value: progress.value
                    wavy: Player.playing
                    interactive: true
                    activeColor: root.accent
                    stopColor: root.accent
                    trackColor: Qt.rgba(1, 1, 1, 0.28)
                    onCommitted: v => Player.seek(v)
                }
                Label {
                    id: remaining
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    text: "-" + root._time(Player.durationMs - (seek.dragging ? seek.dragValue * Player.durationMs : Player.positionMs))
                    type: "labelSmall"
                    color: root.inkDim
                }
            }

            // «Назад / играть / дальше» по центру, лайк справа
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: seekRow.y + seekRow.height + 4
                spacing: 12
                IslandButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip_previous"; onClicked: Player.previous() }
                PlayButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 38
                    playing: Player.playing
                    containerColor: root.ink
                    iconColor: root.body
                    spin: Player.isLocal === true && !Theme.lowPower
                    onClicked: Player.togglePlay()
                }
                IslandButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip_next"; onClicked: Player.next() }
            }
            IslandButton {
                readonly property string trackId: Player.track && Player.track.trackId ? String(Player.track.trackId) : ""
                readonly property bool liked: Library.likesRevision >= 0 && trackId !== "" && Library.isLiked(trackId)
                visible: !Player.isEpisode
                x: island.width - island.pad - width
                y: seekRow.y + seekRow.height + 4 + (38 - height) / 2
                icon: "favorite"
                filled: liked
                tint: liked ? root.accent : root.inkDim
                enabled: trackId !== ""
                onClicked: Library.toggleLike(Player.track)
            }
        }
    }

    function _time(ms) {
        const s = Math.max(0, Math.round(ms / 1000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    // Кнопка на чёрном: белый значок, белый слой наведения
    component IslandButton: Item {
        id: button
        property string icon
        property bool filled: false
        property color tint: root.ink
        signal clicked()
        width: 32
        height: 32
        opacity: enabled ? 1 : 0.4
        Icon { anchors.centerIn: parent; name: button.icon; size: 24; fill: button.filled ? 1 : 0; color: button.tint }
        StateLayer {
            anchors.fill: parent
            radius: width / 2
            color: root.ink
            onClicked: button.clicked()
        }
    }

    // Полоски: свой уровень звука (локально) — по задержанной истории уровня, волной слева направо;
    // чужое устройство — спокойная синусоида; слабый ПК — неподвижные
    component Bars: Item {
        id: bars
        property var levels: [0.45, 0.8, 0.6, 0.35]
        property var _history: []
        property real _peak: 0.05
        property real _phase: 0
        readonly property bool live: Player.playing && !Theme.lowPower && root.visible

        Connections {
            target: Player
            enabled: bars.live && Player.isLocal === true
            function onLevelChanged() {
                const h = [Player.level].concat(bars._history).slice(0, 10)
                bars._history = h
                bars._peak = Math.max(0.05, bars._peak * 0.992, Player.level)
                const gain = [0.85, 1, 0.9, 0.75]
                bars.levels = gain.map((g, i) => Math.max(0.18, Math.min(1, (h[i * 3] ?? 0) / bars._peak * g)))
            }
        }
        TickAnimation {
            running: bars.live && Player.isLocal !== true
            onTriggered: {
                bars._phase += frameTime
                bars.levels = [0, 1, 2, 3].map(i => 0.25 + 0.75 * Math.abs(Math.sin(bars._phase * (2.1 + i * 0.7) + i * 1.3)))
            }
        }

        Repeater {
            model: 4
            Rectangle {
                required property int index
                x: index * 5.5
                width: 3
                radius: 1.5
                height: Math.max(3, bars.height * bars.levels[index])
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent
                Behavior on height { enabled: !Theme.lowPower; NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            }
        }
    }

    Platform.Menu {
        id: islandMenu
        Platform.MenuItem { text: I18n.t("Open Materialfy"); onTriggered: WindowShell.raiseMain() }
        Platform.MenuSeparator {}
        Platform.MenuItem { text: I18n.t("Turn off floating player"); onTriggered: Settings.floatingPlayer = "off" }
    }
}
