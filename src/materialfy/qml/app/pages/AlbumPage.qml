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
    overline: (info.kind ? I18n.any(info.kind) : I18n.t("Album")).toUpperCase()
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
        parts.push(I18n.n(n, "{0} track", "{0} tracks"))
        if (info.label)
            parts.push(info.label)
        return parts.join("  ·  ")
    }
    model: album ? album.tracks : null
    emptyIcon: "album"
    emptyTitle: album && album.errorText !== "" ? I18n.t("Album didn't load") : I18n.t("This album has no tracks")
    emptyText: album ? album.errorText : ""

    // сохранить альбом в библиотеку
    headerExtra: Component {
        Button {
            text: page.saved ? I18n.t("In library") : I18n.t("Save")
            icon: page.saved ? "library_add_check" : "library_add"
            style: "tonal"
            checkable: true
            checked: page.saved
            autoToggle: false
            enabled: (page.info.uri ?? "") !== ""
            onClicked: Library.toggleSaved(page.info.uri)
        }
    }

}
