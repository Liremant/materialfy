import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Исполнитель: шапка (широкое фото фоном, если есть; фото в фигуре, слушатели в месяц, подписчики, Слушать / Радио / Подписаться), популярные треки,
// альбомы и синглы, релизы с участием, «Об исполнителе», похожие исполнители.
Page {
    id: page

    property string artistId
    readonly property QtObject artist: Catalog.artist(artistId)
    readonly property var info: artist ? artist.info : ({})
    property bool allPopular: false
    property bool allAlbums: false

    title: info.name ?? ""
    showHeader: false
    readonly property bool heroTitle: true     // имя — в шапке; в верхней панели — после прокрутки

    readonly property bool followed: Library.savedRevision >= 0 && (info.uri ?? "") !== "" ? Library.isSaved(info.uri) : info.followed === true

    // 12,3 млн / 450 тыс. / 8 765 — I18n.nCompact (после «млн»/«тыс.» — родительный множественного)
    function followersText(n) {
        return n > 0 ? I18n.nCompact(n, "{0} follower", "{0} followers") : ""
    }
    function listenersText(n) {
        return n > 0 ? I18n.nCompact(n, "{0} monthly listener", "{0} monthly listeners") : ""
    }

    // Биография приходит без HTML (sf-services), но на всякий случай теги срезаем и здесь
    readonly property string biography: (info.biography ?? "").replace(/<[^>]*>/g, "").trim()
    property bool bioOpen: false
    readonly property int bioLines: 4

    // Широкая шапка исполнителя — фон шапки страницы; пока не загрузилась или её нет — фигуры, как раньше
    readonly property string headerImage: info.headerImage ?? ""
    readonly property bool hasBanner: headerImage !== "" && bannerImage.status !== Image.Error
    readonly property bool bannerShown: bannerImage.status === Image.Ready

    underlay: [
        HeroShapes {
            width: page.width
            active: page.visible && !page.bannerShown
            headerHeight: hero.height + 24
            scroll: page.flickable.contentY
            contentX: page.sideMargin - 16
            contentWidth: page.width - 2 * contentX
            seed: page.info.name ?? ""
            shapesOpacity: 0.6
        },
        // Фото во всю ширину: уходит под прозрачную верхнюю панель, внизу растворяется в поверхности.
        // Поверх — скрим цвета поверхности: текст шапки читается и в светлой, и в тёмной теме.
        Item {
            id: banner
            readonly property real above: 64      // верхняя панель над страницей
            readonly property real below: 120     // запас под шапкой на растворение
            readonly property color tone: Theme.surfaceContainer
            width: page.width
            height: above + 8 + hero.height + below
            y: -above - page.flickable.contentY
            visible: page.hasBanner && page.visible && page.flickable.contentY < height
            opacity: page.bannerShown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsSlow } }
            clip: true

            layer.enabled: visible
            layer.effect: ShaderEffect {
                property real fadeTop: 24 / Math.max(1, banner.height)
                property real fadeBottom: banner.below * 1.3 / Math.max(1, banner.height)
                fragmentShader: Qt.resolvedUrl("../shaders/edgefade.frag.qsb")
            }

            Image {
                id: bannerImage
                width: parent.width
                height: parent.height
                y: page.flickable.contentY * 0.35   // лёгкий параллакс
                source: page.headerImage
                sourceSize.width: 2400
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            // сверху — чуть приглушить под кнопками панели, к низу шапки — почти поверхность
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(banner.tone, 0.7) }
                    GradientStop { position: 0.12; color: Qt.alpha(banner.tone, 0.5) }
                    GradientStop { position: 0.28; color: Qt.alpha(banner.tone, 0.3) }
                    GradientStop { position: 0.5; color: Qt.alpha(banner.tone, 0.7) }
                    GradientStop { position: 0.8; color: Qt.alpha(banner.tone, 0.9) }
                    GradientStop { position: 1.0; color: Qt.alpha(banner.tone, 0.95) }
                }
            }
            // слева, под текстом шапки, плотнее; справа фото остаётся ярким
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(banner.tone, 0.65) }
                    GradientStop { position: 0.6; color: Qt.alpha(banner.tone, 0.3) }
                    GradientStop { position: 1.0; color: Qt.alpha(banner.tone, 0.0) }
                }
            }
        }
    ]

    // ---- Шапка ----
    Item {
        id: hero
        Layout.fillWidth: true
        // с фото шапка выше: имя и кнопки опускаются к низу картинки
        Layout.preferredHeight: page.hasBanner ? Math.max(heroRow.implicitHeight + 32, Math.round(Math.min(440, Math.max(260, page.width * 0.3))))
                                               : heroRow.implicitHeight + 32

        RowLayout {
            id: heroRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
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
                Label { text: I18n.t("ARTIST"); type: "labelLarge"; color: Theme.primary; font.letterSpacing: 1.2 }
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
                    text: page.listenersText(page.info.listeners ?? 0)
                    type: "titleMedium"
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
                        text: I18n.t("Play")
                        icon: "play_arrow"
                        size: "m"
                        onClicked: Player.playFrom(page.artist.popular, 0)
                    }
                    Button {
                        text: I18n.t("Artist’s radio")
                        icon: "radio"
                        style: "tonal"
                        size: "m"
                        enabled: !Radio.locked
                        onClicked: Radio.playStation("artist:" + page.artistId, page.info.name ?? "")
                    }
                    IconButton {
                        Accessible.name: page.followed ? I18n.t("Following") : I18n.t("Follow")
                        icon: page.followed ? "how_to_reg" : "person_add"
                        style: page.followed ? "tonal" : "standard"
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
        title: I18n.t("Couldn't load artist")
        text: page.artist ? page.artist.errorText : ""
    }

    // ---- Популярные треки ----
    SectionHeader {
        visible: page.artist && page.artist.popular.count > 0
        text: I18n.t("Popular tracks")
        actionText: page.artist && page.artist.popular.count > 5 ? (page.allPopular ? I18n.t("Show less") : I18n.t("All")) : ""
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
                coverLarge: model.coverLarge ?? ""
                uri: model.uri ?? ""
                durationMs: model.durationMs
                explicit: model.explicit
                available: model.available
                playCount: model.playCount ?? 0
                showPlays: true
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
        text: I18n.t("Albums and singles")
        actionText: page.artist && page.artist.albums.count > tilesPerRow.value * 2 ? (page.allAlbums ? I18n.t("Show less") : I18n.t("All")) : ""
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
                subtitle: [model.year || "", model.kind ? I18n.any(model.kind) : ""].filter(x => x).join(" · ")
                explicit: model.explicit
                onClicked: Catalog.openAlbum(model.albumId)
            }
        }
    }

    SectionHeader {
        visible: page.artist && page.artist.alsoAlbums.count > 0
        text: I18n.t("Appears on")
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

    // ---- Об исполнителе ----
    SectionHeader {
        visible: page.biography !== ""
        text: I18n.t("About")
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: 880
        Layout.topMargin: -12
        visible: page.biography !== ""
        spacing: 4
        Item {
            readonly property real clamped: page.bioLines * Theme.type.bodyLarge.line
            Layout.fillWidth: true
            implicitHeight: page.bioOpen ? bioText.implicitHeight : Math.min(bioText.implicitHeight, clamped)
            Behavior on implicitHeight { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            clip: true
            Label {
                id: bioText
                width: parent.width
                text: page.biography
                textFormat: Text.PlainText
                type: "bodyLarge"
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                verticalAlignment: Text.AlignTop
            }
        }
        Button {
            visible: bioText.implicitHeight > page.bioLines * Theme.type.bodyLarge.line + 2
            text: page.bioOpen ? I18n.t("Show less") : I18n.t("More")
            style: "text"
            size: "xs"
            onClicked: page.bioOpen = !page.bioOpen
        }
    }

    // ---- Похожие ----
    SectionHeader {
        visible: page.artist && page.artist.similar.count > 0
        text: I18n.t("Fans also like")
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
