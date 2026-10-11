import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core

// Левая навигация. compact — рейл из иконок (узкое окно или свёрнуто вручную).
//
// Геометрия одна для обоих режимов: поля 12 px, все иконки (знак, разделы, обложки плейлистов, аватар)
// центрированы на оси x = 40 — это центр рейла шириной 80. При сворачивании анимируется только ширина
// (её ведёт Main.qml), подписи гаснут, высоты не меняются — поэтому ничего не прыгает.
Item {
    id: root

    required property var router
    property bool compact: false
    readonly property bool signedIn: Auth.state === "signedIn"
    signal newPlaylistRequested()
    // Шторка (узкое окно): в раскладке ширины не занимает, по openDrawer() выезжает поверх контента
    property bool drawer: false
    // Открыта поверх контента: шторка (drawer) или раскрытый рейл, когда рейл навязан шириной окна
    property bool drawerOpen: false
    // Рейл из-за ширины окна (а не свёрнут вручную): кнопка меню раскрывает панель поверх контента
    readonly property bool forcedRail: compact && !drawer && !Settings.sidebarCollapsed
    // Закрывается анимацией — до её конца карточка шторки ещё видна
    property bool closing: false
    // Переход в шторку: место в раскладке сжимается анимацией (Main.qml), а рейл уезжает влево вместе с ним
    readonly property bool collapsing: drawer && !drawerOpen && !closing && width > 0.5
    // Панель поверх контента (карточка шторки, затемнение, своя ширина 264)
    readonly property bool floating: drawer ? !collapsing : (drawerOpen || closing)
    readonly property bool rail: (compact && !drawer && !drawerOpen) || collapsing

    function openDrawer() { closeTimer.stop(); closing = false; drawerOpen = true; panel.forceActiveFocus() }
    function closeDrawer() {
        if (!drawerOpen)
            return
        closing = true
        drawerOpen = false
        closeTimer.restart()
    }
    function go(name, props) { closeDrawer(); router.reset(name, props) }
    onDrawerChanged: { drawerOpen = false; closing = false }
    onCompactChanged: if (!compact && !drawer) { drawerOpen = false; closing = false }
    Timer { id: closeTimer; interval: Theme.motion.spatialDefault + 40; onTriggered: root.closing = false }

    readonly property real expandedWidth: 264
    readonly property real railWidth: 80
    readonly property real margin: 12
    readonly property real iconInset: 14     // квадрат иконки 28 px: 12 + 14 + 14 = 40 — ось рейла
    readonly property real labelWidth: expandedWidth - 2 * margin - iconInset - 28 - 8 - 12

    readonly property var sections: [
        { name: "home", icon: "home", text: I18n.t("Home") },
        { name: "search", icon: "search", text: I18n.t("Search") },
        { name: "releases", icon: "new_releases", text: I18n.t("New releases") },
        { name: "library", icon: "library_music", text: I18n.t("Library") },
        { name: "liked", icon: "favorite", text: I18n.t("Liked Songs") }
    ]

    // Плейлисты и папки верхнего уровня rootlist (порядок Spotify; закреплённые — первыми, их ставит сервис)
    readonly property var _source: signedIn ? Library.items("playlists", "all", "spotify") : null
    property var playlists: []
    function _rebuild() {
        const out = []
        const m = _source
        // «Любимые» — отдельным пунктом выше; дети папок — внутри папки (если папки в списке есть)
        const folders = new Set()
        for (let i = 0; m && i < m.count; i++) {
            const e = m.get(i)
            if (e.kind === "folder")
                folders.add(e.id)
        }
        for (let i = 0; m && i < m.count; i++) {
            const e = m.get(i)
            if (e.kind === "liked" || folders.has(e.folderId ?? ""))
                continue
            out.push(e)
        }
        playlists = out
    }
    on_SourceChanged: _rebuild()
    Connections {
        target: root._source
        ignoreUnknownSignals: true
        function onCountChanged() { root._rebuild() }
        function onModelReset() { root._rebuild() }
        function onDataChanged() { root._rebuild() }
    }

    implicitWidth: drawer ? 0 : compact ? railWidth : expandedWidth
    clip: !drawer && !floating
    z: drawer || floating ? 50 : 0

    component FadeLabel: Label {
        opacity: root.rail ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
    }

    // Затемнение под шторкой — на всё окно (координаты пересчитываются при открытии)
    Rectangle {
        id: scrim
        property point origin: Qt.point(0, 0)
        visible: opacity > 0
        x: -origin.x
        y: -origin.y
        width: root.Window.width
        height: root.Window.height
        color: Theme.scrim
        opacity: root.drawerOpen ? 0.32 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsDefault } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: root.closeDrawer(); onWheel: w => w.accepted = true }
    }
    onDrawerOpenChanged: if (drawerOpen) scrim.origin = root.mapToItem(null, 0, 0)

    Item {
        id: panel
        width: root.drawer ? (root.collapsing ? root.railWidth : root.expandedWidth)
             : root.drawerOpen ? root.expandedWidth : root.width
        height: root.height
        x: !root.drawer ? 0 : root.drawerOpen ? 0 : root.collapsing ? root.width - root.railWidth : -width - 24
        visible: !root.drawer || root.drawerOpen || root.collapsing || root.closing
        clip: root.floating && !root.drawer
        // шторка выезжает слева; раскрытый рейл растёт вширь из рейла (MD3: rail → drawer)
        Behavior on x {
            enabled: root.drawer && (root.drawerOpen || root.closing)
            NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedDecelerate }
        }
        Behavior on width {
            enabled: !root.drawer && root.compact
            NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized }
        }
        Keys.onEscapePressed: root.closeDrawer()

        // Пустые места панели (вокруг логотипа, между пунктами, под плейлистами) тянут окно, как верхняя
        // панель; двойной клик — развернуть. Пункты, прокрутка и карточка аккаунта забирают нажатие сами.
        DragHandler {
            property bool manual: false
            target: null
            grabPermissions: PointerHandler.TakeOverForbidden
            onActiveChanged: if (active) manual = !root.Window.window.startSystemMove()
            onCentroidChanged: if (active && manual && root.Window.window.visibility === Window.Windowed) {
                root.Window.window.x += centroid.scenePosition.x - centroid.scenePressPosition.x
                root.Window.window.y += centroid.scenePosition.y - centroid.scenePressPosition.y
            }
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: {
                const w = root.Window.window
                w.visibility = w.visibility === Window.Maximized ? Window.Windowed : Window.Maximized
            }
        }

        // Карточка шторки: скруглён правый край (MD3 modal navigation drawer)
        Rectangle {
            id: drawerBg
            visible: root.floating
            anchors.fill: parent
            anchors.leftMargin: -Theme.shape.extraLarge
            radius: Theme.shape.extraLarge
            color: Theme.surfaceContainerLow
        }
        Elevation { target: drawerBg; level: 1 }
        MouseArea { visible: root.floating; anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        anchors.leftMargin: root.margin
        anchors.rightMargin: root.margin
        spacing: 2

        // Шапка: знак «Волна-M» на оси рейла + надпись. Знак — переключатель свернуть / развернуть
        // (наведение превращает его в кнопку); в узком окне — раскрыть панель поверх контента.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.bottomMargin: 8

            SidebarLogo {
                objectName: "sidebarLogo"
                x: 40 - root.margin - markSize / 2
                anchors.verticalCenter: parent.verticalCenter
                markSize: 40
                expanded: !root.rail
                onActivated: {
                    if (root.drawer || root.drawerOpen)
                        root.closeDrawer()
                    else if (root.forcedRail)
                        root.openDrawer()
                    else
                        Settings.sidebarCollapsed = !Settings.sidebarCollapsed
                }
            }
        }

        Repeater {
            model: root.sections
            NavItem {
                required property var modelData
                Layout.fillWidth: true
                compact: root.rail
                iconInset: root.iconInset
                labelWidth: root.labelWidth
                icon: modelData.icon
                text: modelData.text
                // до входа разделы неактивны (38 %): смотреть в них нечего; «Главная» — с приглашением войти
                enabled: root.signedIn || modelData.name === "home"
                opacity: enabled ? 1 : Theme.stateLayer.disabledContent
                // «Библиотека» не подсвечена, пока внутри открыта папка — её подсвечивает пункт папки
                selected: root.router.rootName === modelData.name
                          && !(modelData.name === "library" && (root.router.current.props.folderId ?? "") !== "")
                onClicked: root.go(modelData.name)
            }
        }

        // Заголовок секции: подпись гаснет, волнистый разделитель остаётся и в рейле
        Item {
            id: sectionHeader
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.preferredHeight: 32

            FadeLabel {
                id: sectionLabel
                x: root.iconInset
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("Playlists")
                type: "labelMedium"
                color: Theme.fgSurfaceVariant
            }
            WavyDivider {
                x: root.rail ? root.iconInset : sectionLabel.x + sectionLabel.implicitWidth + 10
                width: parent.width - x - (root.rail ? root.iconInset : 40)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on x { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            }
            IconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "add"
                size: "xs"
                iconColor: Theme.primary
                enabled: root.signedIn
                onClicked: root.newPlaylistRequested()
                opacity: root.rail ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
            }
        }

        FadeLabel {
            visible: opacity > 0 && !root.signedIn
            Layout.preferredWidth: root.labelWidth + 28 + 8
            Layout.leftMargin: root.iconInset
            Layout.topMargin: 4
            text: I18n.t("Sign in to see your playlists")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            lineHeightMode: Text.ProportionalHeight
            lineHeight: 1.2
        }
        LoadingIndicator {
            visible: root.signedIn && root._source !== null && root._source.loading && root.playlists.length === 0
            Layout.leftMargin: 40 - root.margin - size / 2
            Layout.topMargin: 8
            size: 32
        }

        // Плейлисты пользователя: своя прокрутка, если их много
        ListView {
            id: playlistList
            visible: root.signedIn && count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 4
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            acceptedButtons: Qt.NoButton
            model: root.playlists
            delegate: NavItem {
                required property var modelData
                readonly property bool folder: modelData.kind === "folder"
                width: ListView.view.width
                compact: root.rail
                iconInset: root.iconInset
                labelWidth: root.labelWidth
                text: modelData.title ?? ""
                icon: folder ? "folder" : "queue_music"
                imageSource: folder ? "" : (modelData.cover ?? "")
                // папка — шеврон (только чтение), закреплённый — булавка
                trailingIcon: folder ? "chevron_right" : modelData.pinned === true ? "push_pin" : ""
                trailingColor: folder ? Theme.fgSurfaceVariant : Theme.primary
                selected: folder ? root.router.currentName === "library" && (root.router.current.props.folderId ?? "") === modelData.id
                                 : root.router.currentName === "playlist" && (root.router.current.props.playlistId ?? "") === modelData.id
                onClicked: folder ? root.go("library", { folderId: modelData.id, folderTitle: modelData.title ?? "" })
                                  : root.go("playlist", { playlistId: modelData.id, playlistTitle: modelData.title ?? "", cover: modelData.cover ?? "" })
            }
            SmoothScroll { flickable: playlistList; wheelStep: Settings.wheelStep; showScrollBar: false }
        }

        Item { Layout.fillHeight: true; visible: !playlistList.visible }

        // В рейле настройки — отдельным пунктом; в развёрнутом виде — кнопкой в карточке аккаунта
        NavItem {
            visible: root.rail
            Layout.fillWidth: true
            Layout.topMargin: 8
            compact: root.rail
            iconInset: root.iconInset
            labelWidth: root.labelWidth
            icon: "settings"
            text: I18n.t("Settings")
            selected: root.router.rootName === "settings"
            onClicked: root.go("settings")
        }

        // Карточка аккаунта: аватар на оси рейла, одна высота в обоих режимах
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.preferredHeight: 64

            Rectangle {
                anchors.fill: parent
                radius: Theme.shape.large
                color: root.router.rootName === "account" || !root.signedIn ? Theme.secondaryContainer : Theme.surfaceContainer
                Behavior on color { enabled: !Theme.transitioning; ColorAnimation { duration: Theme.motion.effectsDefault } }
            }

            Avatar {
                id: avatar
                x: 40 - root.margin - size / 2
                anchors.verticalCenter: parent.verticalCenter
                size: 40
                name: root.signedIn ? (Auth.account.displayName ?? "") : ""
                source: root.signedIn ? (Auth.account.avatar ?? "") : ""
            }

            Column {
                x: avatar.x + avatar.width + 12
                anchors.verticalCenter: parent.verticalCenter
                width: root.expandedWidth - 2 * root.margin - x - 12 - settingsButton.width
                opacity: root.rail ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
                Label {
                    width: parent.width
                    text: root.signedIn ? (Auth.account.displayName ?? "") : I18n.t("Sign in")
                    type: "titleSmall"
                    color: root.signedIn ? Theme.fgSurface : Theme.fgSecondaryContainer
                }
                Label {
                    width: parent.width
                    text: root.signedIn ? (Auth.playbackState === "authorizing" ? I18n.t("Waiting for browser…")
                                          : Auth.premium ? "Premium" : "Spotify Free")
                        : Auth.state === "awaitingBrowser" ? I18n.t("Waiting for browser…")
                        : Auth.state === "checking" || Auth.state === "connecting" ? I18n.t("Signing in…")
                        : I18n.t("Spotify account")
                    type: "bodySmall"
                    color: Theme.fgSurfaceVariant
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: Theme.shape.large
                onClicked: root.go("account")
            }

            IconButton {
                id: settingsButton
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                icon: "settings"
                checkable: true
                autoToggle: false
                checked: root.router.rootName === "settings"
                opacity: root.rail ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
                onClicked: root.go("settings")
            }
        }
    }
    }
}
