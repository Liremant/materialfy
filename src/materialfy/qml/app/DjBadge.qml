import QtQuick
import Md3
import Materialfy.Core

// The "DJ" pill on the cover while Spotify's DJ talks between tracks on this computer.
// Placed in a corner of the cover with anchors, like DeviceBadge.
Rectangle {
    id: root

    readonly property bool shown: Player.narrating === true

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 32
    radius: height / 2
    color: Theme.tertiaryContainer
    visible: scale > 0.01
    scale: shown ? 1 : 0
    Behavior on scale { NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.OutBack } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            tight: true
            name: "mic"
            size: 18
            color: Theme.fgTertiaryContainer
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t("DJ")
            type: "labelLarge"
            weight: 600
            color: Theme.fgTertiaryContainer
        }
    }

    HoverHandler { id: hover }
    Rectangle {
        visible: hover.hovered
        anchors.top: parent.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        width: tip.implicitWidth + 20
        height: tip.implicitHeight + 12
        radius: Theme.shape.small
        color: Theme.inverseSurface
        Label {
            id: tip
            anchors.centerIn: parent
            text: I18n.t("The DJ is talking. Turn the voice off in Settings → Playback")
            type: "bodySmall"
            color: Theme.fgInverseSurface
        }
    }
}
