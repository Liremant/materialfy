import QtQuick
import Md3
import Materialfy.Core

// Кнопка устройств Spotify Connect. Играет здесь (или нигде) — IconButton speaker_group;
// играет на другом устройстве — залитый чип primary с иконкой и именем; пропало — errorContainer;
// идёт перенос — secondaryContainer с индикатором. Сама открывает DeviceMenu, в узком окне — DeviceSheet.
Item {
    id: root

    property bool iconOnly: false          // узкий мини-плеер: в чипе только иконка
    readonly property bool menuOpen: (menuLoader.item !== null && menuLoader.item.opened)
                                     || (sheetLoader.item !== null && sheetLoader.item.sheet.opened)

    readonly property string movingTo: Devices.transferringTo ?? ""
    readonly property bool moving: Player.transferring === true || movingTo !== ""
    readonly property bool movingHere: moving && (movingTo === "" || movingTo === Devices.thisDeviceId)
    readonly property bool lost: Player.deviceLost === true
    readonly property bool chip: Player.remote === true || lost || (moving && !(Player.isLocal === true && movingHere))
    readonly property bool _instant: Theme.reducedMotion === true

    property string _name: ""
    readonly property string deviceName: (Player.device ?? {}).name ?? ""
    onDeviceNameChanged: if (deviceName !== "") _name = deviceName
    Component.onCompleted: if (deviceName !== "") _name = deviceName

    DeviceBadge.Info { id: info; type: (Player.device ?? {}).type ?? "" }

    function _targetName() {
        const m = Devices.devices
        const i = m && movingTo !== "" ? m.find("id", movingTo) : -1
        return i >= 0 ? (m.get(i).name ?? "") : ""
    }
    readonly property string label: movingHere ? "Сюда…" : moving ? (_targetName() || "Переносим…") : _name

    function toggle() {
        if (menuOpen) {
            if (menuLoader.item) menuLoader.item.close()
            if (sheetLoader.item) sheetLoader.item.sheet.close()
            return
        }
        // нажатие на кнопку уже закрыло меню (клик мимо карточки) — не открываем его снова
        if (menuLoader.item && Date.now() - menuLoader.item.closedAt < 300)
            return
        const w = root.Window.window
        if (w && w.layoutMode === "compact") {
            sheetLoader.active = true
            sheetLoader.item.sheet.openSheet()
        } else {
            menuLoader.active = true
            menuLoader.item.openFor(root)
        }
    }

    implicitHeight: 40
    implicitWidth: chip ? chipRow.implicitWidth + (iconOnly ? 20 : 24) : 40
    Behavior on implicitWidth {
        enabled: !root._instant
        NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized }
    }

    // ---- Обычная кнопка ----
    IconButton {
        anchors.centerIn: parent
        visible: opacity > 0.01
        opacity: root.chip ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
        icon: "speaker_group"
        checkable: true
        autoToggle: false
        checked: root.menuOpen
        onClicked: root.toggle()
    }

    // ---- Чип устройства ----
    Item {
        id: chipBox
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: root.chip ? 1 : 0
        clip: true
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }

        readonly property color bg: root.lost ? Theme.errorContainer : root.moving ? Theme.secondaryContainer : Theme.primary
        readonly property color fg: root.lost ? Theme.fgErrorContainer : root.moving ? Theme.fgSecondaryContainer : Theme.fgPrimary

        Rectangle {
            id: chipBg
            anchors.fill: parent
            radius: chipHit.pressed || root.menuOpen ? 12 : height / 2
            color: chipBox.bg
            Behavior on radius { NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.OutBack; easing.overshoot: Theme.motion.overshoot } }
            Behavior on color { enabled: !Theme.transitioning; ColorAnimation { duration: Theme.motion.effectsDefault } }
        }
        Row {
            id: chipRow
            x: root.iconOnly ? (parent.width - width) / 2 : 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            LoadingIndicator {
                running: !Theme.calm
                visible: root.moving && !root.lost
                anchors.verticalCenter: parent.verticalCenter
                size: 20
                color: chipBox.fg
            }
            Icon {
                visible: !root.moving || root.lost
                anchors.verticalCenter: parent.verticalCenter
                name: root.lost ? "portable_wifi_off" : info.icon
                size: 20
                fill: 1
                weight: 500
                color: chipBox.fg
            }
            Label {
                visible: !root.iconOnly
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 140)
                text: root.label
                type: "labelLarge"
                color: chipBox.fg
                elide: Text.ElideRight
            }
        }
        StateLayer {
            id: chipHit
            anchors.fill: parent
            enabled: root.chip
            radius: chipBg.radius
            color: chipBox.fg
            onClicked: root.toggle()
        }
    }

    Loader { id: menuLoader; active: false; sourceComponent: DeviceMenu {} }
    // Loader грузит только Item, а лист — Popup: оборачиваем
    Loader {
        id: sheetLoader
        active: false
        sourceComponent: Item {
            readonly property alias sheet: sheet
            DeviceSheet { id: sheet }
        }
    }
}
