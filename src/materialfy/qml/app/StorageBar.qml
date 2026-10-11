import QtQuick
import QtQuick.Layouts
import Md3

// Занятое место: полоса 12 px из сегментов (зазор 2 px) и легенда.
// usage — Settings.cacheUsage {audio, covers, playlists, lyrics, total} в байтах; limit — предел кэша в байтах.
ColumnLayout {
    id: root

    property var usage: ({})
    property real limit: 0

    readonly property var parts: [
        { key: "audio", text: "Аудио", color: Theme.primary },
        { key: "covers", text: "Обложки", color: Theme.tertiary },
        { key: "playlists", text: "Плейлисты", color: Theme.secondary },
        { key: "lyrics", text: "Тексты", color: Theme.outline }
    ]
    readonly property real total: Number((usage ?? {}).total ?? 0)
                                  || parts.reduce((s, p) => s + Number((usage ?? {})[p.key] ?? 0), 0)
    readonly property real _scale: Math.max(total, limit, 1)

    function formatBytes(b) {
        b = Number(b) || 0
        if (b >= 1024 * 1024 * 1024)
            return (b / 1024 / 1024 / 1024).toFixed(1).replace(".", ",") + " ГБ"
        if (b >= 1024 * 1024)
            return Math.round(b / 1024 / 1024) + " МБ"
        if (b >= 1024)
            return Math.round(b / 1024) + " КБ"
        return b + " Б"
    }

    Layout.fillWidth: true
    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        Label {
            Layout.fillWidth: true
            text: "Занято " + root.formatBytes(root.total)
            type: "titleSmall"
        }
        Label {
            visible: root.limit > 0
            text: "из " + root.formatBytes(root.limit)
            type: "bodyMedium"
            color: Theme.fgSurfaceVariant
        }
    }

    Item {
        id: bar
        Layout.fillWidth: true
        implicitHeight: 12

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.surfaceContainerHighest
        }
        Row {
            id: segs
            anchors.fill: parent
            spacing: 2
            Repeater {
                model: root.parts
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real bytes: Number((root.usage ?? {})[modelData.key] ?? 0)
                    height: bar.height
                    width: bytes > 0 ? Math.max(4, (bar.width - 6) * bytes / root._scale) : 0
                    visible: width > 0
                    radius: 3
                    color: modelData.color
                    Behavior on width { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 16
        Repeater {
            model: root.parts
            Row {
                required property var modelData
                spacing: 6
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 5
                    color: modelData.color
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text + " · " + root.formatBytes((root.usage ?? {})[modelData.key] ?? 0)
                    type: "bodySmall"
                    color: Theme.fgSurfaceVariant
                }
            }
        }
    }
}
