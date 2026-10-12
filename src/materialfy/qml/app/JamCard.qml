import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core

// Карточка Jam во вкладке «Друзья»: без Jam — «Начать Jam» и вход по ссылке; в Jam — ведущий, участники,
// общая очередь (первые строки Player.queue), «Скопировать приглашение», «Выйти» / «Завершить Jam».
Rectangle {
    id: root

    readonly property var jam: Social.jam ?? {}
    readonly property bool inJam: Social.inJam === true
    readonly property var members: jam.members ?? []
    property bool joining: false

    // общая очередь: строки после текущей (свои и из контекста), не больше 4
    property var upNext: []
    function readQueue() {
        const q = Player.queue
        const rows = []
        if (q) {
            for (let i = 0; i < q.count && rows.length < 4; ++i) {
                const r = q.get(i)
                if (r.section !== "current")
                    rows.push({ title: r.title ?? "", artists: r.artists ?? "", cover: r.cover ?? "" })
            }
        }
        upNext = rows
    }
    Connections {
        target: Player
        function onQueueChanged() { root.readQueue() }
    }
    Component.onCompleted: readQueue()
    onInJamChanged: if (inJam) joining = false

    implicitHeight: body.implicitHeight + 32
    radius: Theme.shape.large
    color: Theme.surfaceContainerHigh

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 12

        // Шапка: значок, «Jam», LIVE, подпись
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            MorphShape {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                shape: root.inJam ? "sunny" : "cookie9"
                color: root.inJam ? Theme.primary : Theme.secondaryContainer
                Icon {
                    anchors.centerIn: parent
                    name: "groups"
                    size: 24
                    fill: 1
                    color: root.inJam ? Theme.fgPrimary : Theme.fgSecondaryContainer
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    spacing: 8
                    Label { text: I18n.t("Jam"); type: "titleMedium" }
                    Rectangle {
                        visible: root.inJam
                        implicitWidth: live.implicitWidth + 12
                        implicitHeight: 18
                        radius: 9
                        color: Theme.primaryContainer
                        Label {
                            id: live
                            anchors.centerIn: parent
                            text: I18n.t("LIVE")
                            type: "labelSmall"
                            weight: 700
                            color: Theme.fgPrimaryContainer
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: !root.inJam ? I18n.t("Start a Jam to listen together")
                        : root.jam.isHost ? I18n.n(root.members.length, "You're hosting · {0} person", "You're hosting · {0} people")
                        : I18n.t("Hosted by {0}", root.jam.hostName ?? "")
                    type: "bodySmall"
                    color: Theme.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
            LoadingIndicator {
                visible: Social.jamBusy === true
                running: visible && !Theme.calm
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                size: 28
            }
        }

        // ---- Без Jam ----
        Label {
            visible: !root.inJam
            Layout.fillWidth: true
            text: I18n.t("Everyone you invite listens along and adds to the same queue. Playback follows the host.")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
        Flow {
            visible: !root.inJam
            Layout.fillWidth: true
            spacing: 8
            Button {
                text: I18n.t("Start a Jam")
                icon: "groups"
                enabled: Social.jamBusy !== true
                onClicked: Social.startJam()
            }
            Button {
                text: I18n.t("Join with a link")
                icon: "link"
                style: root.joining ? "tonal" : "outlined"
                enabled: Social.jamBusy !== true
                onClicked: {
                    root.joining = !root.joining
                    if (root.joining)
                        linkField.inputItem.forceActiveFocus()
                }
            }
        }
        RowLayout {
            visible: !root.inJam && root.joining
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: linkField
                Layout.fillWidth: true
                placeholderText: I18n.t("Invite link or code")
                leadingIcon: "link"
                onAccepted: if (text.trim() !== "") Social.joinJam(text)
            }
            Button {
                text: I18n.t("Join")
                style: "tonal"
                enabled: linkField.text.trim() !== "" && Social.jamBusy !== true
                onClicked: Social.joinJam(linkField.text)
            }
        }

        // ---- В Jam: участники ----
        Label {
            visible: root.inJam
            text: I18n.t("Listening")
            type: "labelMedium"
            color: Theme.fgSurfaceVariant
        }
        Repeater {
            model: root.inJam ? root.members : []
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 12
                Avatar {
                    size: 32
                    name: modelData.name ?? ""
                    source: modelData.avatar ?? ""
                }
                Label {
                    Layout.fillWidth: true
                    text: modelData.isYou ? I18n.t("{0} (you)", modelData.name ?? "") : (modelData.name ?? "")
                    type: "bodyMedium"
                }
                Label {
                    visible: modelData.isHost === true
                    text: I18n.t("Jam host")
                    type: "labelSmall"
                    color: Theme.primary
                }
            }
        }

        // ---- В Jam: общая очередь ----
        RowLayout {
            visible: root.inJam
            Layout.fillWidth: true
            Layout.topMargin: 4
            Label {
                Layout.fillWidth: true
                text: I18n.t("Shared queue")
                type: "labelMedium"
                color: Theme.fgSurfaceVariant
            }
            Button {
                text: I18n.t("Open queue")
                style: "text"
                size: "xs"
                onClicked: Settings.rightPanelTab = "queue"
            }
        }
        Label {
            visible: root.inJam && root.upNext.length === 0
            Layout.fillWidth: true
            text: I18n.t("Nothing queued yet. Tracks anyone adds show up here.")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
        Repeater {
            model: root.inJam ? root.upNext : []
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                MorphImage {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    source: modelData.cover
                    shape: "softSquare"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { Layout.fillWidth: true; text: modelData.title; type: "bodyMedium" }
                    Label { Layout.fillWidth: true; text: modelData.artists; type: "bodySmall"; color: Theme.fgSurfaceVariant }
                }
            }
        }

        // ---- В Jam: действия ----
        Flow {
            visible: root.inJam
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Button {
                text: copiedHint.running ? I18n.t("Copied") : I18n.t("Copy invite link")
                icon: copiedHint.running ? "check" : "content_copy"
                style: "tonal"
                enabled: (root.jam.shareUrl ?? "") !== ""
                onClicked: if (Social.copyJamLink()) copiedHint.restart()
                Timer { id: copiedHint; interval: 1500 }
            }
            Button {
                text: root.jam.isHost ? I18n.t("End Jam") : I18n.t("Leave Jam")
                icon: "logout"
                style: "outlined"
                enabled: Social.jamBusy !== true
                onClicked: Social.leaveJam()
            }
        }

        // ---- Ошибка ----
        RowLayout {
            visible: (Social.jamError ?? "") !== ""
            Layout.fillWidth: true
            spacing: 8
            Icon { name: "error"; size: 18; color: Theme.error }
            Label {
                Layout.fillWidth: true
                text: Social.jamError ?? ""
                type: "bodySmall"
                color: Theme.error
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
            Button {
                text: I18n.t("Retry")
                style: "text"
                size: "xs"
                onClicked: Social.refreshJam()
            }
        }
    }
}
