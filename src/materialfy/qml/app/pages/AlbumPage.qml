import QtQuick
import Md3
import Materialfy.Core
import ".."

TrackListPage {
    id: page

    property string albumId
    property string trackId                   // «перейти к треку»: прокрутить к нему и подсветить
    highlightTrackId: trackId
    readonly property QtObject album: Catalog.album(albumId)
    readonly property var info: album ? album.info : ({})
    readonly property bool saved: Library.savedRevision >= 0 && (info.uri ?? "") !== "" ? Library.isSaved(info.uri) : info.saved === true

    title: info.title ? info.title + (info.version ? " (" + info.version + ")" : "") : ""
    overline: (info.kind || "Альбом").toUpperCase()
    heroImage: info.coverLarge || info.cover || ""
    heroIcon: "album"
    heroArtistRefs: info.artistRefs ?? []
    subtitle: {
        if (!info.title)
            return ""
        const parts = []
        if (info.year)
            parts.push(info.year)
        const n = album.tracks.count
        parts.push(n + " " + plural(n))
        if (info.label)
            parts.push(info.label)
        return parts.join("  ·  ")
    }
    model: album ? album.tracks : null
    emptyIcon: "album"
    emptyTitle: album && album.errorText !== "" ? "Альбом не загрузился" : "В альбоме нет треков"
    emptyText: album ? album.errorText : ""

    // сохранить альбом в библиотеку
    headerExtra: Component {
        Button {
            text: page.saved ? "В библиотеке" : "Сохранить"
            icon: page.saved ? "library_add_check" : "library_add"
            style: "tonal"
            checkable: true
            checked: page.saved
            autoToggle: false
            enabled: (page.info.uri ?? "") !== ""
            onClicked: Library.toggleSaved(page.info.uri)
        }
    }

    function plural(n) {
        const m10 = n % 10, m100 = n % 100
        if (m10 === 1 && m100 !== 11) return "трек"
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "трека"
        return "треков"
    }
}
