import QtQuick
import Md3
import Materialfy.Core

// Подпись «cast · Играет на {имя}» на месте кодек-бейджа, пока играет другое устройство.
// Варианты: «{имя} · пауза», «Переносим на …», «{имя} не отвечает». brief — только имя (полоска мини-режима).
Row {
    id: root

    property bool brief: false
    // Имя держим и после пропажи устройства: снимок может уже не содержать его
    property string _name: ""
    readonly property string deviceName: (Player.device ?? {}).name ?? ""
    onDeviceNameChanged: if (deviceName !== "") _name = deviceName
    Component.onCompleted: if (deviceName !== "") _name = deviceName

    readonly property string targetId: Devices.transferringTo ?? ""
    readonly property bool moving: Player.transferring === true || targetId !== ""
    readonly property bool movingHere: moving && targetId !== "" && targetId === Devices.thisDeviceId
    readonly property bool lost: Player.deviceLost === true
    readonly property bool shown: Player.hasTrack && (Player.remote === true || lost || moving)

    function _targetName() {
        const m = Devices.devices
        const i = m && targetId !== "" ? m.find("id", targetId) : -1
        return i >= 0 ? (m.get(i).name ?? "") : ""
    }

    readonly property string text: {
        if (movingHere)
            return brief ? "Сюда…" : "Переносим на этот компьютер…"
        if (moving) {
            const t = _targetName()
            return t === "" ? "Переносим…" : brief ? t : "Переносим на «" + t + "»…"
        }
        const n = _name !== "" ? _name : "другом устройстве"
        if (lost)
            return n + " не отвечает"
        if (brief)
            return n
        return Player.playing ? "Играет на " + n : n + " · пауза"
    }
    readonly property color tint: lost ? Theme.error : moving ? Theme.fgSurfaceVariant : Theme.primary

    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
    spacing: 3

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.moving ? "sync" : root.lost ? "portable_wifi_off" : "cast"
        size: 14
        weight: 500
        color: root.tint
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.brief ? 140 : 220)
        text: root.text
        type: "labelSmall"
        color: root.tint
        elide: Text.ElideRight
    }
}
