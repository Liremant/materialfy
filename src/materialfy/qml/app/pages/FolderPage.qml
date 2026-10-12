import QtQuick
import Materialfy.Core

// Папка rootlist отдельной страницей: её плейлисты и вложенные папки — сеткой или списком, как в
// библиотеке (Settings.libraryView), с хлебными крошками «Библиотека › Папка». Открывается кликом по
// папке в сайдбаре или в библиотеке; стрелка папки в сайдбаре раскрывает её на месте.
LibraryPage {
    id: folderPage

    // Открыта без названия (startPage=folder:<id>) — название из дерева папок; дерево могло ещё грузиться
    property int _revision: 0
    folderTitle: _revision >= 0 ? _titleIn(Library.items("playlists", "all", "spotify"), 0) : ""
    Connections {
        target: Library
        function onEntriesChanged() { folderPage._revision++ }
    }
    function _titleIn(model, depth) {
        for (let i = 0; model && i < model.count && depth < 8; i++) {
            const e = model.get(i)
            if (e.kind !== "folder")
                continue
            if (e.id === folderId)
                return e.title ?? ""
            const inner = _titleIn(Library.folderChildren(e.id), depth + 1)
            if (inner !== "")
                return inner
        }
        return ""
    }
}
