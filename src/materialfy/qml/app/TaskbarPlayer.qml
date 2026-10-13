import QtQuick
import Md3
import Materialfy.Core

// Плеер в панели задач Windows: окно встраивается в Shell_TrayWnd слева от области уведомлений
// (WindowShell.taskbarPlace, cpp/floating.cpp) — обложка, название и исполнитель, «играть» и «дальше»
// («назад» — при наведении). Фон прозрачный: под ним акрил панели; текст — по теме панели задач.
// Раз в 2 с окно встаёт на место заново (панель сменила размер, Explorer перезапустился). Не встроилось —
// висит поверх панели там же; Explorer унёс окно с собой — lost(), Main.qml создаёт его заново.
Window {
    id: root

    // --set taskbarEmbed=false — сразу запасной вариант (окно поверх панели), для проверки
    property bool embed: true
    signal lost()
    // --set floatingShot=<path.png>: снимок окна через 9 с без встраивания; --set taskbarTheme=dark|light — тема панели
    property string shotPath: ""
    property string forcedTheme: ""
    Timer {
        interval: 9000
        running: root.shotPath !== ""
        onTriggered: root.contentItem.grabToImage(result => result.saveToFile(root.shotPath))
    }

    readonly property int slotWidth: 240
    // 1 — в панели задач, 2 — поверх неё, 0 — некуда (вертикальная или узкая панель): окно спрятано
    property int placement: 0

    // Тема самой панели задач (Параметры → Персонализация → Цвета → «Режим Windows»), не приложения
    readonly property bool colorMode: Settings.floatingPlayerStyle === "color"
    readonly property bool darkBar: forcedTheme !== "" ? forcedTheme === "dark"
        : Settings.systemTaskbarTheme !== "" ? Settings.systemTaskbarTheme === "dark"
        : Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
    readonly property color ink: colorMode ? Theme.fgPrimaryContainer : (darkBar ? "#ffffff" : "#1b1b1b")
    readonly property color inkDim: colorMode ? Qt.alpha(Theme.fgPrimaryContainer, 0.72) : (darkBar ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(0, 0, 0, 0.62))
    readonly property color pillBg: colorMode ? Theme.primaryContainer : "transparent"

    width: slotWidth
    height: 40
    color: "transparent"
    title: "Materialfy"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    // Без владельца: окно, принадлежащее главному, Windows прячет вместе с ним
    transientParent: null

    property bool _ready: false
    property bool _fullscreenBusy: false
    visible: _ready && placement > 0 && !(placement === 2 && _fullscreenBusy)

    function place() {
        if (shotPath !== "") {
            placement = 1
            return
        }
        const result = WindowShell.taskbarPlace(root, slotWidth, embed)
        if (result < 0) {
            placement = 0
            root.lost()
            return
        }
        placement = result
    }
    Component.onCompleted: {
        WindowShell.makeToolWindow(root)
        place()
        _ready = true
    }
    Component.onDestruction: WindowShell.taskbarDetach(root)
    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            root.place()
            // поверх панели и полноэкранное приложение впереди — не висеть над ним (встроенное прячется с панелью)
            root._fullscreenBusy = root.placement === 2 && WindowShell.fullscreenBusy()
        }
    }

    Item {
        id: content
        anchors.fill: parent

        HoverHandler { id: hover }
        // Слой подложки (в цветном режиме — пилюля primaryContainer, в чёрном — слой наведения)
        Rectangle {
            anchors.fill: parent
            radius: root.colorMode ? height / 2 : 6
            color: root.colorMode ? root.pillBg : root.ink
            opacity: root.colorMode ? 1 : (hover.hovered ? 0.07 : 0)
            Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
        }

        // Колесо — громкость (±5 % за щелчок); проценты — вместо исполнителя на секунду
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                if (Player.remote === true && Player.canSetVolume === false)
                    return
                const touchpad = event.pixelDelta.y !== 0 && event.angleDelta.y % 120 !== 0
                const d = touchpad ? event.pixelDelta.y / 600 : event.angleDelta.y / 120 * 0.05
                Player.volume = Math.max(0, Math.min(1, Player.volume + d))
                volumeShown.restart()
            }
        }
        Timer { id: volumeShown; interval: 1000 }

        // Обложка и подписи — одна цель: клик поднимает главное окно
        Item {
            id: track
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 6

            Item {
                id: cover
                width: 28
                height: 28
                anchors.verticalCenter: parent.verticalCenter
                MorphImage {
                    anchors.fill: parent
                    visible: Player.cover !== ""
                    source: Player.cover
                    placeholderColor: Qt.alpha(root.ink, 0.12)
                    fallbackKind: Player.album !== "" ? "album" : "track"
                    fallbackArtist: Player.artist.split(", ")[0]
                    fallbackTitle: Player.album !== "" ? Player.album : Player.title
                    shape: "softSquare"
                }
                Rectangle {
                    anchors.fill: parent
                    visible: Player.cover === ""
                    radius: 6
                    color: Qt.alpha(root.ink, 0.12)
                    Icon { anchors.centerIn: parent; name: Player.isEpisode ? "podcasts" : "music_note"; size: 16; color: root.inkDim }
                }
            }
            Column {
                anchors.left: cover.right
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Label {
                    width: parent.width
                    text: Player.title
                    type: "labelMedium"
                    color: root.ink
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: volumeShown.running ? I18n.t("Volume") + " " + Math.round(Player.volume * 100) + "%" : Player.artist
                    type: "labelSmall"
                    weight: 400
                    color: root.inkDim
                    elide: Text.ElideRight
                }
            }
            TapHandler { onTapped: WindowShell.raiseMain() }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            // «назад» — только при наведении: место отдаётся названию
            BarButton {
                icon: "skip_previous"
                width: hover.hovered ? 30 : 0
                opacity: hover.hovered ? 1 : 0
                visible: width > 0.5
                clip: true
                Behavior on width { NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
                onClicked: Player.previous()
            }
            BarButton { icon: Player.playing ? "pause" : "play_arrow"; filled: true; onClicked: Player.togglePlay() }
            BarButton { icon: "skip_next"; filled: true; onClicked: Player.next() }
        }
    }

    component BarButton: Item {
        id: button
        property string icon
        property bool filled: false
        signal clicked()
        width: 30
        height: 30
        Icon { anchors.centerIn: parent; name: button.icon; size: 20; fill: button.filled ? 1 : 0; color: root.ink }
        StateLayer {
            anchors.fill: parent
            radius: 6
            color: root.ink
            onClicked: button.clicked()
        }
    }
}
