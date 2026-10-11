import QtQuick
import QtQuick.Layouts
import Md3

// Карточка «Играет из …»: обложка 40 px, тип и название контекста, chevron_right. Клик — открыть контекст.
Item {
    id: root

    property var context: ({})             // Player.queueContext {type, uri, title, cover}
    signal clicked()

    readonly property string kind: context.type ?? ""
    readonly property var kindNames: ({
        playlist: "Плейлист", album: "Альбом", artist: "Исполнитель", show: "Подкаст", episode: "Подкаст",
        liked: "Любимые треки", radio: "Радио", search: "Поиск", tracks: "Треки"
    })
    // подпись над названием, как в макете: «Играет из плейлиста»
    readonly property var fromNames: ({
        playlist: "Играет из плейлиста", album: "Играет из альбома", artist: "Играет исполнитель",
        show: "Играет из подкаста", episode: "Играет из подкаста", liked: "Играет из библиотеки",
        radio: "Играет радио", search: "Играет из поиска", tracks: "Играет из недавних"
    })
    readonly property var kindIcons: ({
        playlist: "queue_music", album: "album", artist: "person", show: "podcasts", episode: "podcasts",
        liked: "favorite", radio: "radio", search: "search", tracks: "history"
    })

    implicitHeight: 64
    implicitWidth: 280

    Rectangle {
        anchors.fill: parent
        radius: Theme.shape.largeIncreased
        color: Theme.surfaceContainerHigh
    }
    StateLayer {
        anchors.fill: parent
        radius: Theme.shape.largeIncreased
        onClicked: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 12

        Item {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            MorphImage {
                anchors.fill: parent
                visible: (root.context.cover ?? "") !== ""
                source: root.context.cover ?? ""
                shape: root.kind === "artist" ? "circle" : "softSquare"
            }
            MorphShape {
                anchors.fill: parent
                visible: (root.context.cover ?? "") === ""
                shape: root.kind === "liked" ? "cookie9" : "softSquare"
                color: root.kind === "liked" ? Theme.primaryContainer : Theme.secondaryContainer
                Icon {
                    anchors.centerIn: parent
                    name: root.kindIcons[root.kind] ?? "queue_music"
                    size: 22
                    fill: 1
                    color: root.kind === "liked" ? Theme.fgPrimaryContainer : Theme.fgSecondaryContainer
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: root.fromNames[root.kind] ?? "Играет из"
                type: "labelMedium"
                color: Theme.fgSurfaceVariant
            }
            Label {
                Layout.fillWidth: true
                text: root.context.title || (root.kindNames[root.kind] ?? "")
                type: "titleSmall"
                weight: 600
            }
        }
        Icon {
            name: "chevron_right"
            size: 22
        }
    }
}
