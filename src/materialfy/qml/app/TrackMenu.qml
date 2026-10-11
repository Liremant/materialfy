import QtQuick
import Md3
import Materialfy.Core

// Меню трека (ПКМ или «⋯»): радио, очередь, плейлисты, ссылки, переходы.
// Один экземпляр на окно: show(track, point); действия разбирает владелец через triggered(id, track, item).
// playlistId — свой плейлист, открытый на странице (пункт «Убрать из этого плейлиста», нужен track.pos).
// В мини-плеере сверху — то, чего в нём нет (перемешивание, повтор, поверх окон, развернуть);
// эти пункты меню выполняет само.
Item {
    id: root

    property var track: ({})
    property string playlistId
    readonly property bool opened: menu.opened

    signal triggered(string id, var track, var item)

    readonly property string _id: track.trackId ?? ""
    readonly property bool _episode: track.isEpisode === true
    readonly property bool _isCurrent: Player.hasTrack && _id !== "" && Player.trackId === _id
    readonly property var _refs: (track.artistRefs ?? []).filter(r => r && r.id)
    readonly property var _win: root.Window.window
    readonly property bool _mini: !!_win && _win.layoutMode === "mini"

    function show(t, point) {
        track = t ?? ({})
        if (_id === "" && (track.uri ?? "") === "" && !_mini)
            return
        menu.open(_items(), point)
    }
    function close() { menu.close() }

    function _playlistItems() {
        const out = [{ id: "playlist:new", text: "Новый плейлист…", icon: "add" }]
        const model = Library.playlists
        const me = Auth.account ? (Auth.account.id ?? "") : ""
        const own = []
        for (let i = 0; model && i < model.count; i++) {
            const p = model.get(i)
            if (!((me !== "" && p.ownerId === me) || p.canEdit === true))
                continue
            own.push({ id: "playlist:" + p.playlistId, text: p.title, icon: "queue_music" })
        }
        if (own.length > 0)
            out.push({ separator: true })
        return out.concat(own)
    }

    function _shareItems() {
        const out = [{ id: "share:track", text: _episode ? "Скопировать ссылку на выпуск" : "Скопировать ссылку на трек", icon: "content_copy" }]
        if (_refs.length === 1)
            out.push({ id: "share:artist:" + _refs[0].id, text: "Скопировать ссылку на исполнителя", icon: "person" })
        else
            for (const r of _refs)
                out.push({ id: "share:artist:" + r.id, text: "Ссылка на " + r.name, icon: "person" })
        return out
    }

    function _radioItems() {
        if (_episode)
            return []
        const out = [{ id: "radio:track", text: "Радио по треку", icon: "radio" }]
        if (_refs.length === 1)
            out.push({ id: "radio:artist:" + _refs[0].id, text: "Радио по исполнителю", icon: "person" })
        else if (_refs.length > 1)
            out.push({ id: "radio:artists", text: "Радио по исполнителю", icon: "person",
                       submenu: _refs.map(r => ({ id: "radio:artist:" + r.id, text: r.name, icon: "person" })) })
        return out
    }

    function _miniItems() {
        const onTop = _win && "pinnedOnTop" in _win && _win.canPin !== false
        const items = [
            { id: "mini:shuffle", text: "Перемешивать", icon: "shuffle", checked: Player.shuffle,
              enabled: Player.hasTrack && Player.source !== "radio" },
            { id: "mini:repeat", text: "Повтор", icon: Player.repeat === "one" ? "repeat_one" : "repeat",
              checked: Player.repeat !== "off", enabled: Player.hasTrack }
        ]
        if (onTop)
            items.push({ id: "mini:ontop", text: "Поверх всех окон", icon: "push_pin", checked: !!_win.pinnedOnTop })
        if (_win && typeof _win.expandFromMini === "function")
            items.push({ id: "mini:expand", text: "Развернуть", icon: "open_in_full" })
        return items
    }

    function _miniAction(id) {
        if (id === "mini:shuffle")
            Player.shuffle = !Player.shuffle
        else if (id === "mini:repeat")
            Player.cycleRepeat()
        else if (id === "mini:ontop" && _win && "pinnedOnTop" in _win)
            _win.pinnedOnTop = !_win.pinnedOnTop
        else if (id === "mini:expand" && _win && typeof _win.expandFromMini === "function")
            _win.expandFromMini()
    }

    function _items() {
        const mini = _mini ? _miniItems() : []
        if (_id === "" && (track.uri ?? "") === "")
            return mini
        if (mini.length > 0)
            mini.push({ separator: true })
        const hasAlbum = (track.albumId ?? "") !== ""
        const liked = Library.likesRevision >= 0 && _id !== "" && Library.isLiked(_id)
        let items = mini.concat(_radioItems())
        if (items.length > mini.length)
            items.push({ separator: true })
        items.push({ id: "addqueue", text: "Добавить в очередь", icon: "queue_music", enabled: (track.uri ?? "") !== "" })
        // в мини-режиме повтор уже в верхней группе
        if (_isCurrent && !_mini)
            items.push({ id: "repeat", text: "Повторять", icon: Player.repeat === "one" ? "repeat_one" : "repeat",
                         checked: Player.repeat !== "off" })
        if (_isCurrent && Player.source === "radio")
            items.push({ id: "dislike", text: "Не рекомендовать", icon: "thumb_down" })
        items.push(
            { id: "queue", text: "Открыть очередь", icon: "queue_music" },
            { separator: true }
        )
        if (!_episode) {
            items.push({ id: "like", text: liked ? "Убрать из любимых" : "Сохранить в любимые", icon: "favorite" },
                       { id: "playlist", text: "Добавить в плейлист", icon: "playlist_add", submenu: _playlistItems() })
            if (root.playlistId !== "" && typeof track.pos === "number")
                items.push({ id: "removefromplaylist", text: "Убрать из этого плейлиста", icon: "remove_circle" })
            if (hasAlbum) {
                const saved = Library.savedRevision >= 0 && Library.isSaved("spotify:album:" + track.albumId)
                items.push({ id: "save", text: saved ? "Убрать альбом из библиотеки" : "Сохранить альбом", icon: saved ? "library_add_check" : "library_add" })
            }
        } else {
            const saved = Library.savedRevision >= 0 && Library.isSaved(track.uri ?? "")
            items.push({ id: "save", text: saved ? "Убрать выпуск из библиотеки" : "Сохранить выпуск", icon: saved ? "library_add_check" : "library_add" })
        }
        items.push({ id: "share", text: "Поделиться", icon: "share", submenu: _shareItems() }, { separator: true })
        if (_episode)
            items.push({ id: "goto:show", text: "Перейти к подкасту", icon: "podcasts", enabled: (track.showId ?? "") !== "" })
        else
            items.push(
                { id: "goto:album", text: "Перейти к альбому", icon: "album", enabled: hasAlbum },
                { id: "goto:artist", text: "Перейти к исполнителю", icon: "person", enabled: _refs.length > 0 }
            )
        return items
    }

    anchors.fill: parent

    Menu {
        id: menu
        anchors.fill: parent
        onTriggered: (id, item) => {
            if (id.startsWith("mini:"))
                root._miniAction(id)
            else
                root.triggered(id, root.track, item)
        }
    }
}
