import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core

// Правая выдвижная панель: очередь / текст песни.
Surface {
    id: root

    level: "container"
    translucency: Settings.ambientBackground && Player.cover !== "" ? 0.3 : 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        anchors.bottomMargin: 0
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            ButtonGroup {
                model: [{ text: I18n.t("Queue"), icon: "queue_music" }, { text: I18n.t("Song lyrics"), icon: "title" }]
                autoSelect: false
                currentIndex: Settings.rightPanelTab === "lyrics" ? 1 : 0
                onActivated: i => Settings.rightPanelTab = i === 1 ? "lyrics" : "queue"
            }
            Item { Layout.fillWidth: true }
            IconButton { icon: "close"; onClicked: Settings.rightPanelOpen = false }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            QueueView {
                anchors.fill: parent
                visible: Settings.rightPanelTab !== "lyrics"
            }
            LyricsView {
                anchors.fill: parent
                anchors.bottomMargin: 16
                visible: Settings.rightPanelTab === "lyrics" && Settings.rightPanelOpen
                fontSize: 22
                anchorPos: 0.3
            }
        }
    }
}
