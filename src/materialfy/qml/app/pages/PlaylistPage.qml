import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Плейлист: просмотр, а у своего / совместного — правка прямо на странице (название, описание, видимость,
// обложка, порядок, удаление и добавление треков). Каждое действие сразу уходит в Spotify и отменяется
// из Snackbar («Вернуть» / «Отменить»).
TrackListPage {
    id: page

    property string playlistId
    property string playlistTitle
    property string cover

    // Library.playlistInfo — метод: перечитываем по сигналам моста
    property var info: ({})
    property int _rev: 0
    function _reload() {
        info = playlistId !== "" ? Library.playlistInfo(playlistId) : ({})
        _rev++
    }
    Component.onCompleted: _reload()
    onPlaylistIdChanged: _reload()
    Connections {
        target: Library
        function onPlaylistInfoChanged(id) { if (id === page.playlistId) page._reload() }
        function onEntriesChanged() { page._reload() }
    }

    readonly property string myId: Auth.account ? (Auth.account.id ?? "") : ""
    readonly property bool canEdit: _rev >= 0 && playlistId !== "" && Library.canEdit(playlistId)
    readonly property bool own: (info.ownerId ?? "") !== "" && info.ownerId === myId
    readonly property bool collaborative: info.collaborative === true
    readonly property string uri: (info.uri ?? "") !== "" ? info.uri : (playlistId !== "" ? "spotify:playlist:" + playlistId : "")
    property bool panelOpen: false
    readonly property bool compactPanel: width < 760

    title: (info.title ?? "") !== "" ? info.title : playlistTitle
    overline: collaborative ? "СОВМЕСТНЫЙ ПЛЕЙЛИСТ" : "ПЛЕЙЛИСТ"
    description: info.description ?? ""
    heroImage: (info.cover ?? "") !== "" ? info.cover : cover
    model: playlistId !== "" ? Library.playlistTracks(playlistId) : null
    emptyIcon: "queue_music"
    emptyTitle: "В плейлисте нет треков"
    emptyText: canEdit ? "Нажмите «Редактировать», чтобы добавить треки" : ""
    addedColumn: collaborative ? "by" : (model && model.count > 0 && (model.get(0).addedAt ?? "") !== "" ? "at" : "")
    contentRightInset: editing && panelOpen && !compactPanel ? addPanel.panelWidth + 8 : 0
    onEditingChanged: if (!editing) panelOpen = false
    onCanEditChanged: if (!canEdit) editing = false

    function plural(n, one, few, many) {
        const m10 = n % 10, m100 = n % 100
        if (m10 === 1 && m100 !== 11) return one
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few
        return many
    }
    function notify(text, actionText, onAction) {
        const w = page.Window.window
        if (w && typeof w.notify === "function")
            w.notify(text, actionText ?? "", onAction ?? null)
    }

    // ---- Удаление с «Вернуть»: удалённые за один показ Snackbar возвращаются вместе ----
    // Web API снимает все вхождения uri, поэтому одно удаление — группа [{uri, pos}] по возрастанию pos
    property var _removed: []               // группы в порядке удаления
    Timer { id: undoWindow; interval: 5000; onTriggered: page._removed = [] }
    onTrackRemoved: row => {
        const t = model.get(row)
        if (!t || !t.uri)
            return
        const group = []
        for (let i = 0; i < model.count; i++) {
            if (i === row || model.get(i).uri === t.uri)
                group.push({ uri: t.uri, pos: i })
        }
        Library.removeTracks(playlistId, [{ uri: t.uri, pos: row }])
        _removed = _removed.concat([group])
        undoWindow.restart()
        const n = _removed.reduce((a, g) => a + g.length, 0)
        notify(n > 1 ? "Убрано треков: " + n : "«" + (t.title ?? "") + "» убран из плейлиста", "Вернуть", () => page._restore())
    }
    function _restore() {
        const list = _removed
        _removed = []
        undoWindow.stop()
        // группы — в обратном порядке удаления, внутри группы — по возрастанию pos, подряд идущие одним вызовом
        let first = -1
        for (let g = list.length - 1; g >= 0; g--) {
            const group = list[g]
            for (let i = 0; i < group.length;) {
                let j = i + 1
                while (j < group.length && group[j].pos === group[j - 1].pos + 1)
                    j++
                Library.insertTracks(playlistId, group.slice(i, j).map(x => x.uri), group[i].pos)
                first = first < 0 ? group[i].pos : Math.min(first, group[i].pos)
                i = j
            }
        }
        if (first >= 0)
            _flashAfterChange(first)
    }

    // мигнуть строкой, когда модель обновится (добавление/возврат приходят из сервиса)
    property int _pendingFlash: -1
    function _flashAfterChange(row) {
        _pendingFlash = row
        flashFallback.restart()
    }
    Timer { id: flashFallback; interval: 1200; onTriggered: page._pendingFlash = -1 }
    Connections {
        target: page.model
        ignoreUnknownSignals: true
        enabled: page._pendingFlash >= 0
        function onCountChanged() { const r = page._pendingFlash; page._pendingFlash = -1; Qt.callLater(() => page.flashRow(Math.min(r, page.model.count - 1))) }
        function onModelReset() { const r = page._pendingFlash; page._pendingFlash = -1; Qt.callLater(() => page.flashRow(Math.min(r, page.model.count - 1))) }
    }

    onMoveRequested: (from, to) => {
        const t = model.get(from)
        Library.moveTracks(playlistId, from, to)
        notify("«" + (t ? t.title ?? "" : "") + "» → позиция " + (to + 1), "Отменить", () => Library.moveTracks(page.playlistId, to, from))
    }

    // ---- Шапка: владелец, «N треков, длительность», видимость ----
    heroMeta: Flow {
        spacing: 8
        RowLayout {
            visible: (page.info.owner ?? "") !== ""
            spacing: 8
            height: 28
            Avatar { size: 24; name: page.info.owner ?? "" }
            Label {
                text: (page.info.owner ?? "") + (page.own ? " (вы)" : "")
                type: "titleSmall"
            }
        }
        Label {
            height: 28
            verticalAlignment: Text.AlignVCenter
            visible: page.model !== null && page.model.count > 0
            text: !visible ? "" : "·  " + page.model.count + " " + page.plural(page.model.count, "трек", "трека", "треков")
                  + (page.model.totalDurationMs > 0 ? ", " + page._duration(page.model.totalDurationMs) : "")
            type: "bodyMedium"
            color: Theme.fgSurfaceVariant
        }
        Rectangle {
            visible: page.own
            implicitWidth: visRow.implicitWidth + 16
            implicitHeight: 28
            radius: 8
            color: Theme.surfaceContainerHigh
            Row {
                id: visRow
                anchors.centerIn: parent
                spacing: 4
                Icon { name: page.info.public === true ? "public" : "lock"; size: 16; anchors.verticalCenter: parent.verticalCenter }
                Label { text: page.info.public === true ? "Публичный" : "Закрытый"; type: "labelMedium"; color: Theme.fgSurfaceVariant; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Rectangle {
            visible: page.canEdit && !page.own
            implicitWidth: editRow.implicitWidth + 16
            implicitHeight: 28
            radius: 8
            color: Qt.alpha(Theme.primary, 0.12)
            Row {
                id: editRow
                anchors.centerIn: parent
                spacing: 4
                Icon { name: "edit"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "Вы можете редактировать"; type: "labelMedium"; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    headerExtra: Row {
        spacing: 4
        IconButton {
            icon: "radio"
            size: "m"
            enabled: page.uri !== ""
            onClicked: {
                Radio.playStation(page.uri, page.title)
                page.notify("Радио по плейлисту «" + page.title + "»")
            }
        }
        IconButton {
            visible: page.canEdit
            icon: "edit"
            size: "m"
            onClicked: page.editing = true
        }
        Button {
            visible: !page.canEdit && !page.own && page.playlistId !== ""
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool followed: page.info.followed === true
            text: followed ? "Вы подписаны" : "Подписаться"
            icon: followed ? "check" : "add"
            style: "tonal"
            checkable: true
            autoToggle: false
            checked: followed
            onClicked: {
                if (followed) {
                    Library.unfollowPlaylist(page.playlistId)
                    page.notify("Вы отписались от «" + page.title + "»", "Вернуть", () => Library.followPlaylist(page.playlistId))
                } else {
                    Library.followPlaylist(page.playlistId)
                }
            }
        }
        IconButton {
            icon: "share"
            size: "m"
            enabled: page.uri !== ""
            onClicked: {
                Catalog.copyLink(Catalog.uriUrl(page.uri))
                page.notify("Ссылка скопирована")
            }
        }
        IconButton {
            id: moreButton
            icon: "more_horiz"
            size: "m"
            onClicked: {
                const p = moreButton.mapToItem(plMenu, 0, moreButton.height)
                plMenu.open(page._menuItems(), p)
            }
        }
    }

    heroNote: page.collaborative ? collabNote : null
    Component {
        id: collabNote
        Rectangle {
            implicitHeight: noteRow.implicitHeight + 24
            radius: Theme.shape.large
            color: Theme.surfaceContainerHigh
            RowLayout {
                id: noteRow
                x: 16
                y: 12
                width: parent.width - 32
                spacing: 12
                Icon { Layout.alignment: Qt.AlignTop; name: "group"; size: 20; color: Theme.primary }
                Label {
                    Layout.fillWidth: true
                    text: "Участников совместного плейлиста меняют только в приложении Spotify. Здесь видно, кто что добавил."
                    type: "bodySmall"
                    color: Theme.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    editHero: PlaylistEditHeader {
        playlistId: page.playlistId
        info: page.info
        cover: page.heroImage
        own: page.own
        panelOpen: page.panelOpen
        pageWidth: page.width - page.contentRightInset
        onDone: page.editing = false
        onAddTracks: { page.panelOpen = !page.panelOpen; if (page.panelOpen) Qt.callLater(addPanel.focusSearch) }
        onNotify: text => page.notify(text)
    }

    footerExtra: page.editing ? addRow : null
    Component {
        id: addRow
        Item {
            width: parent ? parent.width : 0
            height: 72
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 8
                radius: Theme.shape.large
                color: "transparent"
                border.width: 1
                border.color: Theme.outlineVariant
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Icon { name: "add"; size: 20; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: "Добавить треки"; type: "labelLarge"; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                }
                StateLayer {
                    anchors.fill: parent
                    radius: Theme.shape.large
                    color: Theme.primary
                    onClicked: { page.panelOpen = true; Qt.callLater(addPanel.focusSearch) }
                }
            }
        }
    }

    // ---- Меню «⋯» ----
    function _menuItems() {
        const items = [
            { id: "queue", text: "Добавить в очередь", icon: "queue_music", enabled: page.uri !== "" },
            { id: "pin", text: (Library.pinsRevision >= 0 && Library.isPinned(page.uri)) ? "Открепить" : "Закрепить в библиотеке",
              icon: "push_pin" }
        ]
        if (page.canEdit)
            items.push({ id: "edit", text: "Редактировать", icon: "edit" })
        if (page.own)
            items.push({ separator: true }, { id: "delete", text: "Удалить плейлист", icon: "delete" })
        else if (page.info.followed === true)
            items.push({ separator: true }, { id: "unfollow", text: "Отписаться", icon: "remove_circle" })
        return items
    }
    Menu {
        id: plMenu
        anchors.fill: parent
        z: 50
        onTriggered: (id, item) => {
            if (id === "queue") {
                Player.addUriToQueue(page.uri)
                page.notify("Плейлист добавлен в очередь")
            } else if (id === "pin") {
                const was = Library.isPinned(page.uri)
                Library.togglePin(page.uri)
                page.notify(was ? "Откреплено" : "Закреплено — только в этом приложении")
            } else if (id === "edit") {
                page.editing = true
            } else if (id === "delete" || id === "unfollow") {
                Library.unfollowPlaylist(page.playlistId)
                page.notify(id === "delete" ? "Плейлист удалён" : "Вы отписались от «" + page.title + "»",
                            "Вернуть", () => Library.followPlaylist(page.playlistId))
                if (id === "delete" && page.router)
                    page.router.back()
            }
        }
    }

    AddTracksPanel {
        id: addPanel
        anchors.fill: parent
        z: 20
        playlistId: page.playlistId
        playlistTitle: page.title
        playlistModel: page.model
        opened: page.editing && page.panelOpen
        compact: page.compactPanel
        onCloseRequested: page.panelOpen = false
        onAdded: track => {
            const pos = page.model ? page.model.count : 0
            page._flashAfterChange(pos)
            page.notify("«" + (track.title ?? "") + "» добавлен в конец", "Отменить",
                        () => Library.removeTracks(page.playlistId, [{ uri: track.uri, pos: pos }]))
        }
    }
}
