import QtQuick
import Md3
import Materialfy.Core

// Кодек играющего трека (OGG 320…) — маленькая плашка над временем в мини-плеере.
// У чужого устройства кодека нет: на этом месте RemoteLabel.
Rectangle {
    visible: Player.hasTrack && Player.codec !== "" && !Player.remote
    implicitWidth: codec.implicitWidth + 10
    implicitHeight: 16
    radius: 5
    color: Theme.surfaceContainerHigh

    Label {
        id: codec
        anchors.centerIn: parent
        text: Player.codec
        type: "labelSmall"
        weight: 600
        color: Theme.fgSurfaceVariant
    }
}
