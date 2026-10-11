import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core

// Строка очереди: место под ручку перетаскивания (ручка — только в «Далее в очереди» на этом компьютере,
// видна при наведении) · обложка · название/исполнители · меню · длительность 36 px.
Item {
    id: root

    property var track: ({})              // строка Player.queue (QUEUE_KEYS)
    property bool current: false
    property bool draggable: false
    property bool dragging: false
    property bool compact: false
    readonly property bool hovered: rowHover.hovered

    signal activated()
    signal dragStarted()
    signal dragMoved(real dy)
    signal dragFinished()

    implicitHeight: compact ? 56 : 64
    implicitWidth: 300

    function openMenu(item, x, y) {
        const p = item.mapToItem(null, x, y)
        Catalog.requestTrackMenu(track, p.x, p.y)
    }
    function _time(ms) {
        const s = Math.round((ms ?? 0) / 1000)
        if (s >= 3600)
            return Math.floor(s / 3600) + ":" + String(Math.floor(s / 60) % 60).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.shape.large
        color: root.dragging ? Theme.surfaceContainerHighest
             : root.current ? Qt.alpha(Theme.primary, 0.12) : "transparent"
        Behavior on color { enabled: !Theme.transitioning; ColorAnimation { duration: Theme.motion.effectsDefault } }
    }
    Elevation { target: bg; level: root.dragging ? 3 : 0 }

    // под содержимым: клик по строке — перейти к ней
    StateLayer {
        anchors.fill: parent
        radius: Theme.shape.large
        dragged: root.dragging
        onClicked: root.activated()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 2
        anchors.rightMargin: 10
        spacing: 10
        opacity: (root.track.available ?? true) ? 1 : Theme.stateLayer.disabledContent

        Item {
            id: handle
            Layout.preferredWidth: 22
            Layout.fillHeight: true
            Icon {
                anchors.centerIn: parent
                name: "drag_indicator"
                size: 20
                color: root.dragging ? Theme.primary : handleHover.hovered ? Theme.fgSurface : Theme.fgSurfaceVariant
                visible: root.draggable
                opacity: root.hovered || root.dragging || root.activeFocus ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
            }
            HoverHandler { id: handleHover; enabled: root.draggable; cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            DragHandler {
                enabled: root.draggable
                target: null
                xAxis.enabled: false
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onActiveChanged: active ? root.dragStarted() : root.dragFinished()
                onTranslationChanged: if (active) root.dragMoved(translation.y)
            }
        }

        MorphImage {
            readonly property real side: root.compact ? 40 : 48
            Layout.preferredWidth: side
            Layout.preferredHeight: side
            source: root.track.cover ?? ""
            shape: root.current ? "cookie9" : "softSquare"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Label {
                    // сжимается до ширины строки (иначе длинное название выталкивает длительность за край)
                    Layout.fillWidth: true
                    Layout.maximumWidth: implicitWidth
                    text: root.track.title ?? ""
                    type: "bodyLarge"
                    weight: 500
                    color: root.current ? Theme.primary : Theme.fgSurface
                    Behavior on color { enabled: !Theme.transitioning; ColorAnimation { duration: Theme.motion.effectsDefault } }
                }
                Rectangle {
                    visible: root.track.explicit === true
                    implicitWidth: 16
                    implicitHeight: 16
                    radius: 4
                    color: Theme.surfaceContainerHighest
                    Label { anchors.centerIn: parent; text: "E"; type: "labelSmall"; color: Theme.fgSurfaceVariant }
                }
                Item { Layout.fillWidth: true }
            }
            LinkLabel {
                Layout.fillWidth: true
                text: root.track.isEpisode ? (root.track.album || root.track.artists || "") : (root.track.artists ?? "")
                type: "bodyMedium"
                color: Theme.fgSurfaceVariant
                linkEnabled: (root.track.artistRefs ?? []).length > 0 || (root.track.isEpisode && (root.track.showId ?? "") !== "")
                previewArtistId: !root.track.isEpisode && (root.track.artistRefs ?? []).length === 1 ? root.track.artistRefs[0].id : ""
                onClicked: root.track.isEpisode ? Catalog.openShow(root.track.showId) : Catalog.openArtists(root.track.artistRefs)
            }
        }

        Item {
            implicitWidth: 28
            implicitHeight: 28
            IconButton {
                id: moreButton
                anchors.fill: parent
                icon: "more_horiz"
                size: "xs"
                iconSize: 22
                iconWeight: 700
                opacity: root.hovered || pressed ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
                onClicked: root.openMenu(moreButton, 0, moreButton.height)
            }
        }

        Label {
            Layout.preferredWidth: 36
            text: root._time(root.track.durationMs)
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            horizontalAlignment: Text.AlignRight
        }
    }

    HoverHandler { id: rowHover }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: point => root.openMenu(root, point.position.x, point.position.y)
    }
}
