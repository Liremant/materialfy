import QtQuick
import Md3

// Пилюля «только чтение»: папки rootlist и чужие плейлисты (изменить их можно только в Spotify).
Rectangle {
    id: root

    property string text: "только чтение"
    property string icon: "lock"

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 24
    radius: height / 2
    color: Theme.surfaceContainerHigh

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Icon { anchors.verticalCenter: parent.verticalCenter; name: root.icon; size: 14; color: Theme.fgSurfaceVariant }
        Label { anchors.verticalCenter: parent.verticalCenter; text: root.text; type: "labelSmall"; color: Theme.fgSurfaceVariant }
    }
}
