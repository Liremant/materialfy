import QtQuick
import Md3

// Источник перетаскивания трека в очередь: «ярлык» с обложкой едет за курсором поверх окна.
// Цели — QueueView и кнопка очереди мини-плеера: DropArea с ключом "materialfy/track",
// трек берут из drop.source.trackData() (source — строка с trackData()).
Item {
    id: root

    property Item source
    property string title
    property string cover
    readonly property alias active: drag.active

    DragHandler {
        id: drag
        target: null
        acceptedDevices: PointerDevice.Mouse
        acceptedButtons: Qt.LeftButton
        onActiveChanged: {
            if (active) {
                ghostLoader.active = true
                const ghost = ghostLoader.item
                ghost.parent = root.Window.contentItem ?? root
                ghost.place(centroid.scenePosition)
                ghost.Drag.active = true
            } else if (ghostLoader.item) {
                ghostLoader.item.Drag.drop()
                ghostLoader.active = false
            }
        }
        onCentroidChanged: if (active && ghostLoader.item) ghostLoader.item.place(centroid.scenePosition)
    }

    // Ярлык создаётся только на время перетаскивания: строк в списке много, а тянут одну
    // (раньше каждая строка держала свой скрытый ярлык с тенью и второй копией обложки)
    Loader {
        id: ghostLoader
        active: false
        sourceComponent: ghostComponent
    }

    Component {
        id: ghostComponent
        Item {
            id: ghost
            z: 10000
            Drag.keys: ["materialfy/track"]
            Drag.source: root.source
            function place(p) {
                const q = parent.mapFromItem(null, p.x, p.y)
                x = q.x
                y = q.y
            }
            Elevation { target: chip; level: 3 }
            Rectangle {
                id: chip
                x: 14
                y: 10
                width: chipRow.implicitWidth + 20
                height: 48
                radius: 24
                color: Theme.surfaceContainerHighest
                Row {
                    id: chipRow
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    MorphImage {
                        width: 32
                        height: 32
                        source: root.cover
                        shape: "circle"
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 240)
                        elide: Text.ElideRight
                        text: root.title
                        type: "labelLarge"
                        color: Theme.fgSurface
                    }
                }
            }
        }
    }
}
