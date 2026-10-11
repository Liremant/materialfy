import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core

// Строка устройства Spotify Connect: иконка в круге, имя, подпись, действие справа.
// variant "menu" — меню/лист устройств (действие проявляется при наведении; touch — видно всегда кнопкой),
// "settings" — список в настройках (действие видно всегда). setup — этот компьютер ещё не настроен
// (подпись primary «Настроить воспроизведение здесь» → экран 11); busy — идёт перенос; disabled — Free.
Item {
    id: root

    property var device: ({})           // DEVICE_KEYS
    property string variant: "menu"     // "menu" | "settings"
    property bool busy: false
    property bool disabled: false
    property bool setup: false
    property bool touch: false
    signal activated()

    readonly property var _d: device ?? {}
    readonly property bool _here: _d.isThisComputer === true
    readonly property bool _receiver: _d.source === "zeroconf"
    readonly property bool _setupBusy: setup && (Auth.playbackState === "authorizing" || Auth.playbackState === "connecting")
    readonly property bool _working: busy || _setupBusy
    readonly property bool _actionAlways: touch || variant === "settings"

    DeviceBadge.Info { id: info; type: root._d.type ?? "" }

    readonly property string title: {
        const n = _d.name ?? ""
        return (setup || (_here && disabled)) && n !== "" ? n + " (этот компьютер)" : n
    }
    readonly property string subtitle: {
        if (busy)
            return "Переносим воспроизведение…"
        if (_setupBusy)
            return "Настраиваем…"
        if (setup)
            return "Настроить воспроизведение здесь"
        if (disabled && _here)
            return "Нужен Premium"
        if (_receiver)
            return "В сети · нажмите, чтобы подключить"
        if (_here)
            return _d.isActive && variant === "settings" ? "Этот компьютер · играет" : "Этот компьютер"
        const kind = info.label
        if (_d.isRestricted || _d.supportsVolume === false)
            return kind + " · громкость только на устройстве"
        return _d.isActive && variant === "settings" ? kind + " · играет" : kind
    }
    readonly property string actionText: setup ? "" : _receiver ? "Подключить" : _here ? "Слушать здесь"
                                         : _d.isActive ? "" : "Перенести"

    implicitWidth: 320
    implicitHeight: Math.max(56, content.implicitHeight + 12)
    opacity: disabled ? Theme.stateLayer.disabledContent : 1

    Rectangle {
        anchors.fill: parent
        radius: Theme.shape.medium
        color: Theme.primary
        opacity: root.busy ? 0.10 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: root.setup ? 4 : 12
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 20
            color: root.setup ? Theme.primaryContainer : Theme.surfaceContainerHighest
            Icon {
                anchors.centerIn: parent
                name: root._receiver ? "wifi_tethering" : root.setup ? "computer" : info.icon
                size: 22
                color: root.setup ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: root.title
                type: "titleSmall"
            }
            Label {
                id: sub
                Layout.fillWidth: true
                text: root.subtitle
                type: "bodySmall"
                // «Телевизор · громкость только на устройстве» — в две строки, без многоточия
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                color: root.setup && !root._setupBusy ? Theme.primary : Theme.fgSurfaceVariant
                // смена «Перенести» ↔ «Переносим…» — короткое затухание
                Behavior on text {
                    enabled: !(Theme.reducedMotion === true)
                    SequentialAnimation {
                        NumberAnimation { target: sub; property: "opacity"; to: 0; duration: Theme.motion.effectsFast / 2 }
                        PropertyAction {}
                        NumberAnimation { target: sub; property: "opacity"; to: 1; duration: Theme.motion.effectsFast }
                    }
                }
            }
        }

        LoadingIndicator {
            running: !Theme.calm
            visible: root._working
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            size: 28
        }

        // Действие: при наведении (меню) или всегда (лист, настройки)
        Label {
            visible: !root._working && !root._actionAlways && root.actionText !== ""
            text: root.actionText
            type: "labelLarge"
            color: Theme.primary
            opacity: hit.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
        }
        Button {
            visible: !root._working && root._actionAlways && root.actionText !== ""
            text: root.actionText
            style: "tonal"
            size: "xs"
            enabled: !root.disabled
            onClicked: root.activated()
        }
        Icon {
            visible: root.setup && !root._setupBusy
            name: "chevron_right"
            size: 24
            color: Theme.primary
        }
    }

    StateLayer {
        id: hit
        anchors.fill: parent
        z: -1
        radius: Theme.shape.medium
        enabled: !root.disabled && !root._working
        onClicked: root.activated()
    }
}
