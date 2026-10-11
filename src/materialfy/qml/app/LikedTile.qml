import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core

// Большая плитка «Любимые треки» (две ячейки сетки библиотеки): градиент primaryContainer → tertiaryContainer,
// образцы треков, фигура-ореол с сердцем (cookie12 → flower8 при наведении), «Слушать».
Item {
    id: root

    property int trackCount: Library.liked ? Library.liked.count : 0
    readonly property bool hovered: area.containsMouse || playArea.containsMouse

    signal clicked()
    signal playClicked()
    signal menuRequested(point point)

    implicitWidth: 358
    implicitHeight: 216

    function _plural(n) {
        const m10 = n % 10, m100 = n % 100
        if (m10 === 1 && m100 !== 11) return "трек"
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "трека"
        return "треков"
    }
    // «Исполнитель Трек · …» по первым строкам Любимых
    readonly property string sample: {
        const m = Library.liked
        const out = []
        for (let i = 0; m && i < Math.min(6, m.count); i++) {
            const t = m.get(i)
            out.push((t.artists ?? "") + " " + (t.title ?? ""))
        }
        return out.join(" · ")
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.shape.extraLarge
        clip: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.primaryContainer }
            GradientStop { position: 1; color: Theme.tertiaryContainer }
        }

        MorphShape {
            x: parent.width - width + 18
            y: -26
            width: 150
            height: 150
            shape: root.hovered ? "flower8" : "cookie12"
            color: Qt.alpha(Theme.fgPrimaryContainer, 0.18)
            Icon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -10
                anchors.verticalCenterOffset: 10
                name: "favorite"
                size: 56
                fill: 1
                color: Theme.fgPrimaryContainer
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 24
            anchors.rightMargin: 96
            anchors.bottomMargin: 20
            spacing: 2
            Label {
                visible: text !== ""
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                text: root.sample
                type: "bodySmall"
                color: Theme.fgPrimaryContainer
                opacity: 0.85
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label { text: "Любимые треки"; type: "headlineMedium"; weight: 500; color: Theme.fgPrimaryContainer }
            Label {
                text: Library.liked && Library.liked.loading && root.trackCount === 0 ? "Загружаем…"
                    : root.trackCount + " " + root._plural(root.trackCount)
                type: "bodyMedium"
                color: Theme.fgPrimaryContainer
                opacity: 0.8
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? root.menuRequested(root.mapToItem(null, mouse.x, mouse.y)) : root.clicked()
    }

    PlayButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20
        size: 56
        spin: false
        pausedShape: "cookie6"
        playingShape: "cookie9"
        playing: Player.playing && Player.source === "liked"
        onClicked: root.playClicked()
        MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }
}
