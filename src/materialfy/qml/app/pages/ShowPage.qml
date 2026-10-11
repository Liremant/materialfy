import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Подкаст: шапка (обложка, издатель, «Слушать последний» / «Продолжить» / «Пауза», подписка),
// описание, выпуски с фильтрами и сортировкой (локально), догрузка страницами по 50.
Page {
    id: page

    property string showId
    readonly property QtObject show: Catalog.show(showId)
    readonly property var info: show ? show.info : ({})
    readonly property var episodes: show ? show.episodes : null
    readonly property bool compact: width < 840     // окно 900 px (рейл) или 1280 с правой панелью
    readonly property bool saved: Library.savedRevision >= 0 && (info.uri ?? "") !== "" ? Library.isSaved(info.uri) : info.saved === true

    property string filter: "all"          // all | unfinished | new | saved
    property bool newestFirst: true
    property bool descriptionOpen: false

    title: info.name ?? ""
    showHeader: false
    readonly property bool heroTitle: true     // название — в шапке; в верхней панели — после прокрутки

    readonly property var filters: [
        { key: "all", text: "Все" }, { key: "unfinished", text: "Недослушанные" },
        { key: "new", text: "Новые" }, { key: "saved", text: "Сохранённые" }
    ]

    // ---- Выпуски: фильтр и порядок на стороне QML ----
    property int _revision: 0
    Connections {
        target: page.episodes
        function onCountChanged() { page._revision++ }
        function onModelReset() { page._revision++ }
        function onDataChanged() { page._revision++ }
    }
    readonly property var allEpisodes: {
        const _ = _revision
        const out = []
        if (!episodes)
            return out
        for (let i = 0; i < episodes.count; i++)
            out.push(episodes.get(i))
        return out
    }
    readonly property var shownEpisodes: {
        const _ = Library.savedRevision
        let list = allEpisodes.filter(e => {
            switch (page.filter) {
            case "unfinished": return (e.resumeMs ?? 0) > 0 && e.fullyPlayed !== true
            case "new": return (e.resumeMs ?? 0) === 0 && e.fullyPlayed !== true
            case "saved": return Library.isSaved(e.uri ?? "")
            }
            return true
        })
        // с сервера выпуски приходят от новых к старым
        if (!newestFirst)
            list = list.slice().reverse()
        return list
    }
    readonly property var playingEpisode: Player.isEpisode ? allEpisodes.find(e => e.uri === Player.uri) ?? null : null
    readonly property var resumeEpisode: allEpisodes.find(e => (e.resumeMs ?? 0) > 0 && e.fullyPlayed !== true) ?? null
    readonly property bool hasMore: episodes !== null && episodes.count < (show ? show.total : 0)

    function mainAction() {
        if (playingEpisode)
            Player.togglePlay()
        else if (resumeEpisode)
            Player.playEpisode(resumeEpisode.uri, resumeEpisode.resumeMs)
        else if (allEpisodes.length > 0)
            Player.playEpisode(allEpisodes[0].uri, allEpisodes[0].fullyPlayed ? 0 : (allEpisodes[0].resumeMs ?? 0))
    }
    function _episodesWord(n) {
        const m10 = n % 10, m100 = n % 100
        if (m10 === 1 && m100 !== 11) return "выпуск"
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "выпуска"
        return "выпусков"
    }
    // идёт догрузка следующей страницы (ShowData.loadingMore; повторный loadMore() безопасен)
    readonly property bool loadingMore: show !== null && show.loadingMore === true
    function loadMore() {
        if (hasMore && show && !show.loading && !loadingMore)
            show.loadMore()
    }
    // догрузка, когда до конца списка остаётся меньше экрана
    Connections {
        target: page.flickable
        function onContentYChanged() {
            if (page.hasMore && page.flickable.contentY > page.flickable.maxY - page.height)
                page.loadMore()
        }
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
        visible: (page.info.name ?? "") !== "" || (page.show !== null && page.show.loading)
        Layout.fillWidth: true
        Layout.preferredHeight: heroRow.implicitHeight + 32

        RowLayout {
            id: heroRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: page.compact ? 20 : 32

            MorphImage {
                Layout.preferredWidth: page.compact ? 150 : 200
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignTop
                Behavior on Layout.preferredWidth { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
                source: page.info.coverLarge || page.info.cover || ""
                shape: page.playingEpisode && Player.playing ? "cookie9" : "softSquare"
                duration: Theme.motion.spatialSlow
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: "ПОДКАСТ"; type: "labelMedium"; color: Theme.primary; font.letterSpacing: 1.2 }
                Label {
                    Layout.fillWidth: true
                    text: page.info.name ?? ""
                    type: page.compact ? "headlineMedium" : "displaySmall"
                    weight: 600
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: page.info.publisher ?? ""
                    type: "titleMedium"
                    font.pixelSize: 18
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: {
                        const n = (page.show && page.show.total) || (page.info.totalEpisodes ?? 0)
                        return [n > 0 ? n + " " + page._episodesWord(n) : "", page.info.explicit ? "18+" : ""].filter(x => x).join(" · ")
                    }
                    type: "bodyMedium"
                    color: Theme.fgSurfaceVariant
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 12
                    visible: (page.info.name ?? "") !== ""
                    Button {
                        size: "m"
                        enabled: page.allEpisodes.length > 0
                        icon: page.playingEpisode && Player.playing ? "pause" : "play_arrow"
                        text: page.playingEpisode ? (Player.playing ? "Пауза" : "Продолжить")
                            : page.resumeEpisode ? "Продолжить" + (page.resumeEpisode.number ? " · вып. " + page.resumeEpisode.number : "")
                            : "Слушать последний"
                        onClicked: page.mainAction()
                    }
                    Button {
                        size: "m"
                        style: "tonal"
                        icon: page.saved ? "library_add_check" : "library_add"
                        text: page.compact ? "" : page.saved ? "В библиотеке" : "Подписаться"
                        onClicked: Library.toggleSaved(page.info.uri ?? "")
                    }
                    IconButton {
                        size: "m"
                        icon: "share"
                        onClicked: {
                            Catalog.copyLink(Catalog.uriUrl(page.info.uri ?? ""))
                            snackbar.show("Ссылка скопирована")
                        }
                    }
                }
            }
        }
    }

    // ---- Описание ----
    ColumnLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: 880
        visible: (page.info.description ?? "") !== ""
        spacing: 4
        Item {
            Layout.fillWidth: true
            implicitHeight: page.descriptionOpen ? fullText.implicitHeight : Math.min(fullText.implicitHeight, 2 * 24)
            Behavior on implicitHeight { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            clip: true
            Label {
                id: fullText
                width: parent.width
                text: page.info.description ?? ""
                textFormat: Text.PlainText
                type: "bodyLarge"
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }
        Button {
            visible: fullText.implicitHeight > 2 * 24 + 2
            text: page.descriptionOpen ? "Свернуть" : "Ещё"
            style: "text"
            size: "xs"
            onClicked: page.descriptionOpen = !page.descriptionOpen
        }
    }

    // ---- Выпуски ----
    SectionHeader {
        visible: (page.info.name ?? "") !== ""
        text: "Выпуски"
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: -8
        visible: (page.info.name ?? "") !== ""
        spacing: 8
        Flickable {
            Layout.fillWidth: true
            implicitHeight: 32
            contentWidth: chips.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width
            clip: true
            Row {
                id: chips
                spacing: 8
                Repeater {
                    model: page.filters
                    Chip {
                        required property var modelData
                        text: modelData.text
                        selected: page.filter === modelData.key
                        onClicked: page.filter = modelData.key
                    }
                }
            }
        }
        Chip {
            icon: "swap_vert"
            // в узкой странице — только значок: место нужнее фильтрам
            text: page.width < 640 ? "" : page.newestFirst ? "Сначала новые" : "Сначала старые"
            onClicked: page.newestFirst = !page.newestFirst
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: page.shownEpisodes
            ColumnLayout {
                id: epItem
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 0
                WavyDivider {
                    visible: epItem.index > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: (page.compact ? 64 : 88) + 28
                    Layout.rightMargin: 12
                    Layout.preferredHeight: 8
                }
                EpisodeRow {
                    Layout.fillWidth: true
                    episode: epItem.modelData
                    compact: page.compact
                }
            }
        }
    }

    // загрузка: три строки-заготовки
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.show !== null && page.show.loading
        spacing: 16
        Repeater {
            model: 3
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Rectangle {
                    Layout.preferredWidth: page.compact ? 64 : 88
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: Theme.shape.large
                    color: Theme.surfaceContainerHigh
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle { Layout.preferredWidth: 120; Layout.preferredHeight: 12; radius: 6; color: Theme.surfaceContainerHigh }
                    Rectangle { Layout.fillWidth: true; Layout.maximumWidth: 420; Layout.preferredHeight: 18; radius: 9; color: Theme.surfaceContainerHigh }
                    Rectangle { Layout.fillWidth: true; Layout.maximumWidth: 560; Layout.preferredHeight: 12; radius: 6; color: Theme.surfaceContainerHigh }
                }
            }
        }
    }

    EmptyState {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 24
        visible: page.show !== null && !page.show.loading && page.show.errorText === ""
                 && page.allEpisodes.length > 0 && page.shownEpisodes.length === 0
        icon: page.filter === "saved" ? "bookmark" : "podcasts"
        title: page.filter === "unfinished" ? "Нет недослушанных выпусков"
             : page.filter === "new" ? "Новых выпусков нет"
             : "Нет сохранённых выпусков"
        text: page.hasMore ? "Подгружены не все выпуски — прокрутите ниже или загрузите ещё" : ""
        actionText: page.hasMore ? "Загрузить ещё" : ""
        actionIcon: "expand_more"
        onAction: page.loadMore()
    }
    EmptyState {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 48
        visible: page.show !== null && !page.show.loading && page.show.errorText !== ""
        icon: "cloud_off"
        title: "Подкаст не загрузился"
        text: page.show ? page.show.errorText : ""
    }

    LoadingIndicator {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
        visible: page.loadingMore
        size: 40
    }
    Button {
        Layout.alignment: Qt.AlignHCenter
        visible: page.hasMore && page.show !== null && !page.show.loading && !page.loadingMore && page.shownEpisodes.length > 0
        text: "Ещё выпуски"
        icon: "expand_more"
        style: "text"
        onClicked: page.loadMore()
    }

    Snackbar {
        id: snackbar
        parent: page
        anchors.fill: parent
        z: 50
    }
}
