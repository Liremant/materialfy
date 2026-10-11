import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Исполнитель: шапка (фото в фигуре, подписчики, Слушать / Радио / Подписаться), популярные треки,
// альбомы и синглы, релизы с участием, похожие исполнители.
Page {
    id: page

    property string artistId
    readonly property QtObject artist: Catalog.artist(artistId)
    readonly property var info: artist ? artist.info : ({})
    property bool allPopular: false
    property bool allAlbums: false

    title: info.name ?? ""
    showHeader: false

    readonly property bool followed: Library.savedRevision >= 0 && (info.uri ?? "") !== "" ? Library.isSaved(info.uri) : info.followed === true

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

    underlay: HeroShapes {
        width: page.width
        active: page.visible
        headerHeight: hero.height + 24
        scroll: page.flickable.contentY
        contentX: page.sideMargin - 16
        contentWidth: page.width - 2 * contentX
        seed: page.info.name ?? ""
        shapesOpacity: 0.6
    }

    // ---- Шапка ----
    Item {
        id: hero
        Layout.fillWidth: true
        Layout.preferredHeight: heroRow.implicitHeight + 32

        RowLayout {
            id: heroRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: page.width < 560 ? 20 : 32
            Behavior on spacing { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }

            MorphImage {
                Layout.preferredWidth: page.width > 760 ? 208 : page.width < 560 ? 104 : 144
                Layout.preferredHeight: Layout.preferredWidth
                Behavior on Layout.preferredWidth { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
                source: page.info.coverLarge || page.info.cover || ""
                shape: page.playingHere && Player.playing ? "cookie12" : "circle"
                duration: Theme.motion.spatialSlow
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: "ИСПОЛНИТЕЛЬ"; type: "labelLarge"; color: Theme.primary; font.letterSpacing: 1.2 }
                Label {
                    Layout.fillWidth: true
                    text: page.info.name ?? ""
                    type: page.width > 760 ? "displayMedium" : page.width < 560 ? "headlineMedium" : "displaySmall"
                    weight: 700
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
                Label {
                    visible: text !== ""
                    Layout.fillWidth: true
                    text: [page.followersText(page.info.followers ?? 0), page.info.genres ?? ""].filter(x => x).join("  ·  ")
                    type: "bodyLarge"
                    color: Theme.fgSurfaceVariant
                }
                // в узком окне кнопки переносятся, а не распирают шапку
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 12
                    visible: (page.info.name ?? "") !== ""
                    Button {
                        visible: page.artist && page.artist.popular.count > 0
                        text: "Слушать"
                        icon: "play_arrow"
                        size: "m"
                        onClicked: Player.playFrom(page.artist.popular, 0)
                    }
                    Button {
                        text: "Радио исполнителя"
                        icon: "radio"
                        style: "tonal"
                        size: "m"
                        enabled: !Radio.locked
                        onClicked: Radio.playStation("artist:" + page.artistId, page.info.name ?? "")
                    }
                    Button {
                        text: page.followed ? "Вы подписаны" : "Подписаться"
                        icon: page.followed ? "check" : "person_add"
                        style: "outlined"
                        size: "m"
                        checkable: true
                        checked: page.followed
                        autoToggle: false
                        onClicked: Library.toggleSaved(page.info.uri ?? "")
                    }
                }
            }
        }
    }

    readonly property bool playingHere: Radio.active && Radio.stationUri !== "" && Radio.stationUri.indexOf(artistId) >= 0
                                        || artist && Player.trackId !== "" && artist.popular.find("trackId", Player.trackId) >= 0

    LoadingIndicator {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 48
        size: 64
        contained: true
        visible: page.artist && page.artist.loading
    }
    EmptyState {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 48
        visible: page.artist && page.artist.errorText !== ""
        icon: "person_off"
        title: "Исполнитель не загрузился"
        text: page.artist ? page.artist.errorText : ""
    }

    // ---- Популярные треки ----
    SectionHeader {
        visible: page.artist && page.artist.popular.count > 0
        text: "Популярные треки"
        actionText: page.artist && page.artist.popular.count > 5 ? (page.allPopular ? "Свернуть" : "Все") : ""
        onAction: page.allPopular = !page.allPopular
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: -12
        spacing: 0
        Repeater {
            model: page.artist ? page.artist.popular : null
            TrackRow {
                required property int index
                required property var model
                visible: page.allPopular || index < 5
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
                durationMs: model.durationMs
                explicit: model.explicit
                available: model.available
                liked: Library.likesRevision >= 0 && Library.isLiked(model.trackId)
                current: model.trackId === Player.trackId
                onActivated: Player.playFrom(page.artist.popular, index)
                onLikeClicked: Library.toggleLike(page.artist.popular.get(index))
                track: page.artist.popular.get(index)
            }
        }
    }

    // ---- Альбомы ----
    SectionHeader {
        visible: page.artist && page.artist.albums.count > 0
        text: "Альбомы и синглы"
        actionText: page.artist && page.artist.albums.count > tilesPerRow.value * 2 ? (page.allAlbums ? "Свернуть" : "Все") : ""
        onAction: page.allAlbums = !page.allAlbums
    }
    QtObject {
        id: tilesPerRow
        readonly property int value: Math.max(1, Math.floor((page.width - 2 * page.sideMargin + 20) / (168 + 20)))
    }
    Flow {
        Layout.fillWidth: true
        spacing: 20
        Repeater {
            model: page.artist ? page.artist.albums : null
            MediaTile {
                required property int index
                required property var model
                visible: page.allAlbums || index < tilesPerRow.value * 2
                cover: model.cover
                title: model.title
                subtitle: [model.year || "", model.kind].filter(x => x).join(" · ")
                explicit: model.explicit
                onClicked: Catalog.openAlbum(model.albumId)
            }
        }
    }

    SectionHeader {
        visible: page.artist && page.artist.alsoAlbums.count > 0
        text: "С участием"
    }
    Flow {
        Layout.fillWidth: true
        spacing: 20
        Repeater {
            model: page.artist ? page.artist.alsoAlbums : null
            MediaTile {
                required property int index
                required property var model
                visible: index < tilesPerRow.value
                cover: model.cover
                title: model.title
                subtitle: model.artists
                explicit: model.explicit
                onClicked: Catalog.openAlbum(model.albumId)
            }
        }
    }

    // ---- Похожие ----
    SectionHeader {
        visible: page.artist && page.artist.similar.count > 0
        text: "Похожие исполнители"
    }
    Flow {
        Layout.fillWidth: true
        spacing: 20
        Repeater {
            model: page.artist ? page.artist.similar : null
            MediaTile {
                required property int index
                required property var model
                visible: index < tilesPerRow.value
                size: 148
                round: true
                placeholderIcon: "person"
                cover: model.cover
                title: model.name
                onClicked: Catalog.openArtist(model.artistId)
            }
        }
    }
}
