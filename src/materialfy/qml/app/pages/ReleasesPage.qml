import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Новинки: личный «Радар новинок» Spotify (шапка + треки, играет как плейлист) и сетка свежих альбомов
// и синглов исполнителей, на которых подписан пользователь (плитка открывает страницу альбома).
Page {
    id: page

    title: "Новинки"
    subtitle: "Свежая музыка от исполнителей, которых вы слушаете"

    readonly property var radar: Releases.radar ?? ({})
    readonly property string radarId: radar.playlistId ?? ""
    readonly property string radarUri: (radar.uri ?? "") !== "" ? radar.uri : (radarId !== "" ? "spotify:playlist:" + radarId : "")
    // строки «Радара» читает библиотека, как у любого плейлиста (через сессию)
    readonly property var radarTracks: radarId !== "" ? Library.playlistTracks(radarId) : null
    readonly property bool radarPlaying: radarUri !== "" && Player.contextUri === radarUri
    property bool allTracks: false
    readonly property int shownTracks: 8

    property string filter: "all"          // all | album | single
    readonly property var releases: Releases.releases ?? []
    readonly property var shown: filter === "all" ? releases : releases.filter(r => r.group === filter)
    property bool allReleases: false

    Component.onCompleted: Releases.refresh(false)
    onVisibleChanged: if (visible) Releases.refresh(false)

    function plural(n, one, few, many) {
        const m10 = n % 10, m100 = n % 100
        if (m10 === 1 && m100 !== 11) return one
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few
        return many
    }
    function openRadar() {
        router.push("playlist", { playlistId: radarId, playlistTitle: radar.title ?? "", cover: radar.cover ?? "" })
    }
    function playRadar() {
        if (radarPlaying && Player.hasTrack)
            Player.togglePlay()
        else if (radarTracks && radarTracks.count > 0)
            Player.playFrom(radarTracks, 0)
        else
            Player.playContext(radarUri, "")
    }

    QtObject {
        id: tilesPerRow
        readonly property int value: Math.max(1, Math.floor((page.width - 2 * page.sideMargin + 20) / (168 + 20)))
    }

    // ---- «Радар новинок» ----
    SectionHeader {
        text: "Радар новинок"
        actionText: page.radarId !== "" ? "Открыть плейлист" : ""
        onAction: page.openRadar()
    }

    LoadingIndicator {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 16
        size: 48
        contained: true
        visible: page.radarId === "" && !Releases.radarChecked && Auth.state === "signedIn"
    }

    // не нашёлся: Spotify не отдал категорию «Сделано для вас», а в библиотеке его нет
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: missingRow.implicitHeight + 32
        visible: page.radarId === "" && Releases.radarChecked
        Rectangle {
            anchors.fill: parent
            radius: 24
            color: Theme.surfaceContainerLow
        }
        RowLayout {
            id: missingRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 16
            spacing: 16
            MorphShape {
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                shape: "cookie9"
                color: Theme.secondaryContainer
                Icon { anchors.centerIn: parent; name: "new_releases"; size: 28; color: Theme.fgSecondaryContainer }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { Layout.fillWidth: true; text: "«Радар новинок» не нашёлся"; type: "titleMedium"; weight: 600 }
                Label {
                    Layout.fillWidth: true
                    text: "Spotify собирает его по пятницам для тех, кто слушает достаточно музыки. Если он есть в вашем Spotify, сохраните его в библиотеку — и он появится здесь."
                    type: "bodyMedium"
                    color: Theme.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
        }
    }

    // шапка «Радара»: обложка, название, описание, Слушать / Перемешать
    RowLayout {
        Layout.fillWidth: true
        visible: page.radarId !== ""
        spacing: page.width < 560 ? 16 : 24

        MorphImage {
            Layout.preferredWidth: page.width < 560 ? 104 : 144
            Layout.preferredHeight: Layout.preferredWidth
            source: page.radar.cover ?? ""
            shape: page.radarPlaying && Player.playing ? "cookie12" : "cookie9"
            duration: Theme.motion.spatialSlow
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.openRadar() }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Label { text: "ПЛЕЙЛИСТ · SPOTIFY"; type: "labelLarge"; color: Theme.primary; font.letterSpacing: 1.2 }
            Label {
                Layout.fillWidth: true
                text: page.radar.title ?? ""
                type: page.width < 560 ? "headlineSmall" : "headlineMedium"
                weight: 700
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: page.radar.description ?? ""
                type: "bodyMedium"
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 12
                Button {
                    text: page.radarPlaying && Player.playing ? "Пауза" : "Слушать"
                    icon: page.radarPlaying && Player.playing ? "pause" : "play_arrow"
                    size: "m"
                    onClicked: page.playRadar()
                }
                Button {
                    text: "Перемешать"
                    icon: "shuffle"
                    style: "tonal"
                    size: "m"
                    onClicked: page.radarTracks && page.radarTracks.count > 0 ? Player.shuffleFrom(page.radarTracks) : Player.shuffleContext(page.radarUri)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: -8
        visible: page.radarId !== ""
        spacing: 0
        Repeater {
            model: page.radarTracks
            TrackRow {
                required property int index
                required property var model
                visible: page.allTracks || index < page.shownTracks
                Layout.fillWidth: true
                number: index + 1
                trackId: model.trackId
                title: model.title
                version: model.version
                artists: model.artists
                artistRefs: model.artistRefs
                albumId: model.albumId
                album: model.album
                cover: model.cover
                uri: model.uri ?? ""
                durationMs: model.durationMs
                explicit: model.explicit
                available: model.available
                liked: Library.likesRevision >= 0 && Library.isLiked(model.trackId)
                current: model.trackId === Player.trackId
                track: page.radarTracks.get(index)
                // с этого трека — плейлистом: дальше играет весь «Радар»
                onActivated: Player.playFrom(page.radarTracks, index)
                onLikeClicked: Library.toggleLike(page.radarTracks.get(index))
            }
        }
        LoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            size: 40
            visible: page.radarTracks !== null && page.radarTracks.loading && page.radarTracks.count === 0
        }
        Button {
            Layout.alignment: Qt.AlignLeft
            Layout.topMargin: 4
            visible: page.radarTracks !== null && page.radarTracks.count > page.shownTracks
            text: page.allTracks ? "Свернуть" : "Все " + page.radarTracks.count + " " + page.plural(page.radarTracks.count, "трек", "трека", "треков")
            style: "text"
            onClicked: page.allTracks = !page.allTracks
        }
    }

    // ---- Новые релизы ----
    SectionHeader {
        text: "Новые релизы ваших исполнителей"
        actionText: Releases.loading ? "" : "Обновить"
        onAction: Releases.refresh(true)
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: -12
        spacing: 8
        visible: page.releases.length > 0
        Chip { text: "Все"; selected: page.filter === "all"; onClicked: page.filter = "all" }
        Chip { text: "Альбомы"; selected: page.filter === "album"; onClicked: page.filter = "album" }
        Chip { text: "Синглы и EP"; selected: page.filter === "single"; onClicked: page.filter = "single" }
        Item { Layout.fillWidth: true }
        Label {
            text: "за 6 недель"
            type: "bodyMedium"
            color: Theme.fgSurfaceVariant
        }
    }

    LoadingIndicator {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 24
        size: 64
        contained: true
        visible: Releases.loading && page.releases.length === 0
    }
    EmptyState {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 24
        visible: !Releases.loading && page.releases.length === 0
        icon: "album"
        title: Releases.errorText !== "" ? "Новинки не загрузились" : "Пока ничего нового"
        text: Releases.errorText !== "" ? Releases.errorText
              : "За последние 6 недель у ваших исполнителей не было релизов. Подпишитесь на исполнителей — их новинки появятся здесь."
        actionText: Releases.errorText !== "" ? "Повторить" : ""
        actionIcon: "refresh"
        onAction: Releases.refresh(true)
    }

    Flow {
        Layout.fillWidth: true
        spacing: 20
        Repeater {
            model: page.shown
            MediaTile {
                required property int index
                required property var modelData
                visible: page.allReleases || index < tilesPerRow.value * 3
                cover: modelData.cover ?? ""
                title: modelData.title ?? ""
                subtitle: [modelData.artists ?? "", modelData.dateLabel ?? ""].filter(x => x).join(" · ")
                badge: modelData.group === "single" ? (modelData.kind ?? "").toUpperCase() : ""
                explicit: modelData.explicit === true
                showPlay: true
                playing: Player.playing && (modelData.uri ?? "") !== "" && Player.contextUri === modelData.uri
                onClicked: Catalog.openAlbum(modelData.albumId)
                onPlayClicked: {
                    if (Player.contextUri === modelData.uri && Player.hasTrack)
                        Player.togglePlay()
                    else
                        Player.playContext(modelData.uri, "")
                }
            }
        }
    }
    Button {
        Layout.alignment: Qt.AlignHCenter
        visible: page.shown.length > tilesPerRow.value * 3
        text: page.allReleases ? "Свернуть" : "Показать все (" + page.shown.length + ")"
        style: "tonal"
        onClicked: page.allReleases = !page.allReleases
    }
}
