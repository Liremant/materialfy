import QtQuick
import QtQuick.Layouts
import Md3

// Плитка альбома / исполнителя / плейлиста: обложка в фигуре MD3E, название, подпись.
// При наведении фигура морфится, у исполнителей — круг. showPlay — кнопка «Слушать» на обложке по наведению;
// badge — плашка в углу («РАДИО»), pinned — булавка (локальное закрепление). ПКМ — menuRequested(точка окна).
Item {
    id: root

    property string cover
    property string title
    property string subtitle
    property bool round: false          // исполнитель
    property bool explicit: false
    property string placeholderIcon: "album"
    property real size: 168
    property var shape: round ? "circle" : "softSquare"
    property var hoverShape: round ? "cookie12" : "cookie9"
    property bool showPlay: false
    property bool playing: false        // играет из этой плитки — иконка паузы
    property string badge
    property bool pinned: false
    readonly property bool hovered: area.containsMouse || playArea.containsMouse

    signal clicked()
    signal playClicked()
    signal menuRequested(point point)

    implicitWidth: size
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        width: root.size
        spacing: 8

        Item {
            Layout.preferredWidth: root.size
            Layout.preferredHeight: root.size

            MorphImage {
                anchors.fill: parent
                visible: root.cover !== ""
                source: root.cover
                shape: root.hovered ? root.hoverShape : root.shape
                duration: Theme.motion.spatialDefault
            }
            MorphShape {
                anchors.fill: parent
                visible: root.cover === ""
                shape: root.hovered ? root.hoverShape : root.shape
                color: Theme.surfaceContainerHigh
                Icon { anchors.centerIn: parent; name: root.placeholderIcon; size: root.size * 0.3; color: Theme.fgSurfaceVariant }
            }

            Rectangle {
                visible: root.badge !== ""
                x: 8
                y: 8
                implicitWidth: badgeLabel.implicitWidth + 12
                implicitHeight: 20
                radius: 6
                color: Theme.primary
                Label { id: badgeLabel; anchors.centerIn: parent; text: root.badge; type: "labelSmall"; weight: 700; color: Theme.fgPrimary }
            }
            Rectangle {
                visible: root.pinned
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                width: 28
                height: 28
                radius: 14
                color: Theme.primaryContainer
                Icon { anchors.centerIn: parent; name: "push_pin"; size: 16; fill: 1; color: Theme.fgPrimaryContainer }
            }

            // «Слушать» по наведению: всплывает снизу и дорастает (OutBack)
            Item {
                id: playHost
                visible: root.showPlay && opacity > 0
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                width: 48
                height: 48
                opacity: root.hovered || root.playing ? 1 : 0
                scale: root.hovered || root.playing ? 1 : 0.8
                transform: Translate { y: root.hovered || root.playing ? 0 : 8; Behavior on y { NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.OutBack } } }
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsDefault } }
                Behavior on scale { NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.OutBack } }
                PlayButton {
                    anchors.fill: parent
                    size: 48
                    playing: root.playing
                    spin: false
                    pausedShape: "cookie6"
                    playingShape: "cookie9"
                    onClicked: root.playClicked()
                }
                MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
        }

        RowLayout {
            Layout.preferredWidth: root.size
            spacing: 4
            Label {
                Layout.fillWidth: implicitWidth > width
                Layout.maximumWidth: implicitWidth
                Layout.alignment: root.round ? Qt.AlignHCenter : Qt.AlignLeft
                text: root.title
                type: "titleSmall"
                horizontalAlignment: root.round ? Text.AlignHCenter : Text.AlignLeft
            }
            Rectangle {
                visible: root.explicit
                implicitWidth: 16
                implicitHeight: 16
                radius: 4
                color: Theme.surfaceContainerHighest
                Label { anchors.centerIn: parent; text: "E"; type: "labelSmall"; color: Theme.fgSurfaceVariant }
            }
            Item { Layout.fillWidth: true; visible: !root.round }
        }
        Label {
            visible: root.subtitle !== ""
            Layout.preferredWidth: root.size
            Layout.topMargin: -6
            text: root.subtitle
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            horizontalAlignment: root.round ? Text.AlignHCenter : Text.AlignLeft
        }
    }

    MouseArea {
        id: area
        z: -1
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.menuRequested(root.mapToItem(null, mouse.x, mouse.y))
            else
                root.clicked()
        }
    }
}
