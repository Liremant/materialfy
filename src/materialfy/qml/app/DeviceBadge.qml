import QtQuick
import Md3
import Materialfy.Core

// Значок устройства на обложке, пока играет другое устройство (пульт): круг primary с иконкой типа
// и обводкой цветом подложки. Пропало — errorContainer, переносим сюда — computer на secondaryContainer.
// Кладётся в угол обложки: anchors.right/bottom с отрицательным отступом.
Item {
    id: root

    property real size: 22
    property color ringColor: Theme.surfaceContainerHighest
    readonly property bool movingHere: Player.transferring === true && Devices.transferringTo !== ""
                                       && Devices.transferringTo === Devices.thisDeviceId
    readonly property bool shown: Player.hasTrack && (Player.remote === true || Player.deviceLost === true || movingHere)

    // Иконка и подпись по Device.type (как device_icon в spotifast) — общие для всех экранов устройств
    component Info: QtObject {
        property string type
        readonly property string key: (type ?? "").toLowerCase().replace(/[_\s-]/g, "")
        readonly property string icon: ({
            computer: "computer", smartphone: "smartphone", tablet: "tablet", tv: "tv", speaker: "speaker",
            avr: "speaker_group", stb: "speaker_group", audiodongle: "speaker_group",
            automobile: "directions_car", gameconsole: "sports_esports",
            castvideo: "cast", castaudio: "cast", smartwatch: "watch"
        })[key] ?? "speaker"
        readonly property string label: ({
            computer: "Компьютер", smartphone: "Телефон", tablet: "Планшет", tv: "Телевизор", speaker: "Колонка",
            avr: "Ресивер", stb: "Приставка", audiodongle: "Аудиоадаптер", automobile: "Автомобиль",
            gameconsole: "Игровая консоль", castvideo: "Google Cast", castaudio: "Google Cast", smartwatch: "Часы"
        })[key] ?? "Устройство"
    }

    Info { id: info; type: (Player.device ?? {}).type ?? "" }

    implicitWidth: size
    implicitHeight: size
    visible: scale > 0.01
    scale: shown ? 1 : 0
    Behavior on scale { NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.OutBack } }

    Rectangle {
        anchors.centerIn: parent
        width: root.size + 6
        height: width
        radius: width / 2
        color: root.ringColor
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Player.deviceLost ? Theme.errorContainer : root.movingHere ? Theme.secondaryContainer : Theme.primary
        Behavior on color { enabled: !Theme.transitioning; ColorAnimation { duration: Theme.motion.effectsDefault } }
        Icon {
            anchors.centerIn: parent
            name: Player.deviceLost ? "portable_wifi_off" : root.movingHere ? "computer" : info.icon
            size: Math.round(root.size * 0.64)
            fill: 1
            weight: 600
            color: Player.deviceLost ? Theme.fgErrorContainer : root.movingHere ? Theme.fgSecondaryContainer : Theme.fgPrimary
        }
    }
}
