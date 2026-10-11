import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Поиск: поле с задержкой ввода, фильтры-чипы. «Всё» — лучший результат + по несколько из каждой
// категории, остальные фильтры — полный список одной категории.
Page {
    id: page
    title: "Поиск"
    showHeader: false

    property int filter: 0
    readonly property var filters: [
        { text: "Все", type: "all" }, { text: "Треки", type: "tracks" }, { text: "Альбомы", type: "albums" },
        { text: "Исполнители", type: "artists" }, { text: "Плейлисты", type: "playlists" },
        { text: "Подкасты", type: "shows" }, { text: "Выпуски", type: "episodes" }
    ]
    function showFilter(type) { filter = Math.max(0, filters.findIndex(f => f.type === type)) }
    readonly property string type: filters[filter].type
    readonly property bool all: type === "all"
    readonly property bool signedIn: Auth.state === "signedIn"
    // в старом бинарнике новых моделей поиска может ещё не быть
    readonly property var showsModel: Catalog.searchShows ?? null
    readonly property var episodesModel: Catalog.searchEpisodes ?? null
    readonly property int perRow: Math.max(1, Math.floor((width - 2 * sideMargin + 20) / (168 + 20)))

    function followersText(n) {
        if (!(n > 0))
            return ""
        const num = n >= 1e6 ? (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(".", ",") + " млн"
                  : n >= 1e4 ? Math.round(n / 1e3) + " тыс." : String(n)
        const m10 = n % 10, m100 = n % 100
        const word = n >= 1e4 || (m10 >= 5 || m10 === 0 || (m100 >= 11 && m100 <= 14)) ? "подписчиков"
                   : m10 === 1 ? "подписчик" : "подписчика"
        return num + " " + word
    }
    function focusSearch() { field.inputItem.forceActiveFocus() }
    // запрос уже запущен снаружи (Catalog.openUri("spotify:search:…")): только показать его
    function showQuery(q) {
        if (q === "" || q === field.text)
            return
        filter = 0
        field.text = q
        debounce.stop()
    }
    Component.onCompleted: {
        showQuery(Catalog.searchQuery)
        Qt.callLater(focusSearch)
    }

    Timer {
        id: debounce
        interval: 350
        onTriggered: Catalog.search(field.text, page.type)
    }
    onTypeChanged: if (field.text.trim() !== "") Catalog.search(field.text, page.type)

    SearchField {
        id: field
        Layout.fillWidth: true
        Layout.maximumWidth: 720
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
        implicitHeight: 56
        placeholder: "Трек, альбом, исполнитель, плейлист или подкаст"
        onTextChanged: debounce.restart()
    }

    Flow {
        Layout.fillWidth: true
        Layout.maximumWidth: 720
        Layout.alignment: Qt.AlignHCenter
        spacing: 8
        Repeater {
            model: page.filters
            Chip {
                required property var modelData
                required property int index
                text: modelData.text
                selected: page.filter === index
                onClicked: page.filter = index
            }
        }
    }

    // ---- Состояния ----
    EmptyState {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 48
        visible: !page.signedIn || Catalog.searchState === "idle" || Catalog.searchState === "empty" || Catalog.searchState === "error"
        icon: !page.signedIn ? "login" : Catalog.searchState === "empty" ? "search_off"
            : Catalog.searchState === "error" ? "cloud_off" : "travel_explore"
        title: !page.signedIn ? "Войдите, чтобы искать"
             : Catalog.searchState === "empty" ? "Ничего не нашлось"
             : Catalog.searchState === "error" ? "Поиск не ответил"
             : "Что послушаем?"
        text: !page.signedIn ? "Поиск работает через ваш аккаунт Spotify"
            : Catalog.searchState === "empty" ? "Попробуйте написать иначе или выбрать другой фильтр"
            : Catalog.searchState === "error" ? "Проверьте соединение и попробуйте ещё раз"
            : "Ищите треки, альбомы, исполнителей, плейлисты и подкасты. Ссылку open.spotify.com можно просто вставить"
        actionText: !page.signedIn ? "Войти" : ""
        actionIcon: "login"
        onAction: page.router.reset("account")
    }
    LoadingIndicator {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 48
        size: 64
        contained: true
        visible: page.signedIn && Catalog.searchState === "loading"
    }

    // ---- Результаты ----
    ColumnLayout {
        id: results
        Layout.fillWidth: true
        spacing: 24
        visible: page.signedIn && Catalog.searchState === "ok"

        // Лучший результат
        Item {
            id: bestCard
            readonly property var best: Catalog.best
            readonly property var item: best.item ?? ({})
            visible: page.all && best.type !== undefined
            Layout.fillWidth: true
            Layout.preferredHeight: 168

            Rectangle {
                anchors.fill: parent
                radius: Theme.shape.extraLarge
                color: Theme.surfaceContainerHigh
            }
            StateLayer {
                anchors.fill: parent
                radius: Theme.shape.extraLarge
                onClicked: page.openBest()
            }
            RowLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 24
                MorphImage {
                    Layout.preferredWidth: 128
                    Layout.preferredHeight: 128
                    source: bestCard.item.coverLarge || bestCard.item.cover || ""
                    shape: bestCard.best.type === "artist" ? "circle" : "softSquare"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label {
                        text: ({ track: "ТРЕК", album: (bestCard.item.kind || "Альбом").toUpperCase(), artist: "ИСПОЛНИТЕЛЬ", playlist: "ПЛЕЙЛИСТ", show: "ПОДКАСТ" })[bestCard.best.type] ?? ""
                        type: "labelLarge"
                        color: Theme.primary
                        font.letterSpacing: 1.2
                    }
                    Label {
                        Layout.fillWidth: true
                        text: bestCard.item.title ?? bestCard.item.name ?? ""
                        type: "headlineMedium"
                        weight: 700
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: bestCard.item.artists || bestCard.item.owner || bestCard.item.publisher
                              || page.followersText(bestCard.item.followers ?? 0)
                              || bestCard.item.genres || ""
                        type: "bodyLarge"
                        color: Theme.fgSurfaceVariant
                    }
                }
                PlayButton {
                    visible: bestCard.best.type === "track"
                    size: 64
                    playing: Player.playing && Player.trackId === (bestCard.item.trackId ?? "-")
                    onClicked: page.openBest()
                }
            }
        }

        // Треки
        SectionHeader {
            visible: Catalog.searchTracks.count > 0 && (page.all || page.type === "tracks")
            text: "Треки"
            actionText: page.all && Catalog.totals.tracks > 5 ? "Все" : ""
            onAction: page.showFilter("tracks")
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: -12
            visible: page.all || page.type === "tracks"
            spacing: 0
            Repeater {
                model: Catalog.searchTracks
                TrackRow {
                    required property int index
                    required property var model
                    visible: !page.all || index < 5
                    Layout.fillWidth: true
                    trackId: model.trackId
                    title: model.title
                    version: model.version
                    artists: model.artists
                    artistRefs: model.artistRefs
                    albumId: model.albumId
                    album: model.album
                    cover: model.cover
                    durationMs: model.durationMs
                    explicit: model.explicit
                    available: model.available
                    liked: Library.likesRevision >= 0 && Library.isLiked(model.trackId)
                    current: model.trackId === Player.trackId
                    onActivated: Player.playFrom(Catalog.searchTracks, index)
                    onLikeClicked: Library.toggleLike(Catalog.searchTracks.get(index))
                    track: Catalog.searchTracks.get(index)
                }
            }
        }

        // Исполнители
        SectionHeader {
            visible: Catalog.searchArtists.count > 0 && (page.all || page.type === "artists")
            text: "Исполнители"
            actionText: page.all && Catalog.totals.artists > page.perRow ? "Все" : ""
            onAction: page.showFilter("artists")
        }
        Flow {
            Layout.fillWidth: true
            visible: page.all || page.type === "artists"
            spacing: 20
            Repeater {
                model: Catalog.searchArtists
                MediaTile {
                    required property int index
                    required property var model
                    visible: !page.all || index < page.perRow
                    size: 148
                    round: true
                    placeholderIcon: "person"
                    cover: model.cover
                    title: model.name
                    onClicked: Catalog.openArtist(model.artistId)
                }
            }
        }

        // Альбомы
        SectionHeader {
            visible: Catalog.searchAlbums.count > 0 && (page.all || page.type === "albums")
            text: "Альбомы"
            actionText: page.all && Catalog.totals.albums > page.perRow ? "Все" : ""
            onAction: page.showFilter("albums")
        }
        Flow {
            Layout.fillWidth: true
            visible: page.all || page.type === "albums"
            spacing: 20
            Repeater {
                model: Catalog.searchAlbums
                MediaTile {
                    required property int index
                    required property var model
                    visible: !page.all || index < page.perRow
                    cover: model.cover
                    title: model.title
                    subtitle: [model.artists, model.year || ""].filter(x => x).join(" · ")
                    explicit: model.explicit
                    onClicked: Catalog.openAlbum(model.albumId)
                }
            }
        }

        // Плейлисты
        SectionHeader {
            visible: Catalog.searchPlaylists.count > 0 && (page.all || page.type === "playlists")
            text: "Плейлисты"
            actionText: page.all && Catalog.totals.playlists > page.perRow ? "Все" : ""
            onAction: page.showFilter("playlists")
        }
        Flow {
            Layout.fillWidth: true
            visible: page.all || page.type === "playlists"
            spacing: 20
            Repeater {
                model: Catalog.searchPlaylists
                MediaTile {
                    required property int index
                    required property var model
                    visible: !page.all || index < page.perRow
                    placeholderIcon: "queue_music"
                    cover: model.cover
                    title: model.title
                    subtitle: model.owner
                    onClicked: {
                        const p = Catalog.searchPlaylists.get(index)
                        Catalog.openPlaylist({ playlistId: p.playlistId, title: p.title, cover: p.cover })
                    }
                }
            }
        }

        // Подкасты
        SectionHeader {
            visible: page.showsModel !== null && page.showsModel.count > 0 && (page.all || page.type === "shows")
            text: "Подкасты"
            actionText: page.all && (Catalog.totals.shows ?? 0) > page.perRow ? "Все" : ""
            onAction: page.showFilter("shows")
        }
        Flow {
            Layout.fillWidth: true
            visible: page.all || page.type === "shows"
            spacing: 20
            Repeater {
                model: page.showsModel
                MediaTile {
                    required property int index
                    required property var model
                    visible: !page.all || index < page.perRow
                    placeholderIcon: "podcasts"
                    cover: model.cover
                    title: model.name
                    subtitle: model.publisher
                    explicit: model.explicit
                    onClicked: Catalog.openShow(model.showId)
                }
            }
        }

        // Выпуски
        SectionHeader {
            visible: page.episodesModel !== null && page.episodesModel.count > 0 && (page.all || page.type === "episodes")
            text: "Выпуски"
            actionText: page.all && (Catalog.totals.episodes ?? 0) > 3 ? "Все" : ""
            onAction: page.showFilter("episodes")
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: -12
            visible: page.all || page.type === "episodes"
            spacing: 0
            Repeater {
                model: page.episodesModel
                EpisodeRow {
                    required property int index
                    visible: !page.all || index < 3
                    Layout.fillWidth: true
                    compact: true
                    episode: page.episodesModel.get(index)
                }
            }
        }
    }

    function openBest() {
        const b = Catalog.best
        if (!b.type)
            return
        if (b.type === "artist") Catalog.openArtist(b.item.artistId)
        else if (b.type === "album") Catalog.openAlbum(b.item.albumId)
        else if (b.type === "playlist") Catalog.openPlaylist({ playlistId: b.item.playlistId, title: b.item.title, cover: b.item.cover })
        else if (b.type === "show") Catalog.openShow(b.item.showId)
        else if (b.type === "track") {
            const row = Catalog.searchTracks.find("trackId", b.item.trackId)
            if (row >= 0) Player.playFrom(Catalog.searchTracks, row)
        }
    }
}
