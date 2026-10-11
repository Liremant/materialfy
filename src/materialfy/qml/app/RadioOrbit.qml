import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import Md3
import Materialfy.Core

// Сцена «Радио» на главной (из орбиты «Моей волны»): в центре — фигура группы выбранного сида с его обложкой
// и кнопкой, вокруг по эллипсу — сиды станций группами («Недавние треки», «Артисты», «Альбомы и плейлисты»,
// «Любой трек» с «+»). Места — равными шагами по длине дуги, внизу свободная дуга; заголовок группы стоит
// на орбите перед ней; выбранный сид притягивается к центру на 14 %. Подпись под центром — что за станция
// и действия. Узкая сцена — центр сверху, сиды чипами под ним. Движение — только переходы свойств.
Item {
    id: root

    property var groups: []                // Radio.seeds: [{key, title, items: [{uri, label, cover, kind}]}]
    property string selected               // URI выбранного сида
    property bool locked: false            // нет воспроизведения на этом ПК — сиды неактивны
    property bool loading: false
    property bool playing: false           // играет станция выбранного сида
    property bool signedIn: true
    property bool premium: true
    property string errorText
    property bool compact: false

    signal picked(string uri)
    signal addRequested(Item seed)
    signal playClicked()
    signal openList()
    signal saveRequested()
    signal refreshRequested()
    signal connectRequested()
    signal moreRequested()
    signal loginRequested()

    readonly property bool reduced: Theme.reducedMotion === true
    readonly property bool chipMode: width < 600
    readonly property real seedSize: compact || width < 900 ? 48 : 56
    // до входа орбиты нет: сцена — только центр с подписью, без пустой полосы над ним
    readonly property real sceneHeight: chipMode || !signedIn ? 0 : (compact ? 400 : 460)

    implicitHeight: chipMode ? chipColumn.y + chipColumn.implicitHeight + 16
                             : Math.max(sceneHeight, caption.y + caption.implicitHeight + 16)

    // Тональные пары групп: цвет / контейнер / текст на них; фигура группы
    readonly property var styles: ({
        recent:      { role: "primary", shape: "sunny" },
        artists:     { role: "tertiary", shape: "cookie4" },
        collections: { role: "secondary", shape: "cookie9" },
        any:         { role: "neutral", shape: "cookie6" }
    })
    function roleColor(role) { return role === "neutral" ? Theme.fgSurfaceVariant : Theme[role] }
    function roleBox(role) { return role === "neutral" ? Theme.surfaceVariant : Theme[role + "Container"] }
    function roleOn(role) { return role === "neutral" ? Theme.surface : Theme["fg" + role.charAt(0).toUpperCase() + role.slice(1)] }

    // Группы для показа: «Любой трек» всегда есть и заканчивается «+»
    readonly property var shownGroups: {
        const out = []
        if (!signedIn)
            return out
        let any = null
        for (const g of (groups ?? [])) {
            if (!g || !g.items)
                continue
            if (g.key === "any")
                any = g
            else if (g.items.length > 0)
                out.push(g)
        }
        const anyItems = (any ? any.items : []).concat([{ uri: "", label: "Найти трек", cover: "", kind: "add" }])
        out.push({ key: "any", title: any && any.title ? any.title : "Любой трек", items: anyItems })
        return out
    }

    readonly property var current: {
        for (const g of shownGroups)
            for (let j = 0; j < g.items.length; j++)
                if (g.items[j].uri !== "" && g.items[j].uri === selected)
                    return { group: g, item: g.items[j], first: j === 0 }
        return null
    }
    readonly property var currentStyle: current ? (styles[current.group.key] ?? styles.any) : styles.recent

    // ---- Геометрия орбиты (как в макете 20) ----
    readonly property real cx: width / 2
    readonly property real cy: signedIn ? sceneHeight * 0.47 : heroSize / 2 + 24
    readonly property real rx: width * 0.44
    readonly property real ry: sceneHeight * 0.36
    readonly property real heroSize: signedIn ? Math.min(ry * 1.3, compact ? 200 : 236) : (compact ? 176 : 200)
    readonly property real freeArc: 100

    // Места: [{x, y, ux, uy, title: true|false, g, j}], равными шагами по длине дуги
    readonly property var slots: {
        if (chipMode || width <= 0)
            return []
        const a0 = 90 + freeArc / 2, a1 = 90 - freeArc / 2 + 360
        const pts = []
        let len = 0, px = 0, py = 0
        for (let a = a0; a <= a1; a += 0.5) {
            const t = a * Math.PI / 180
            const x = cx + rx * Math.cos(t), y = cy + ry * Math.sin(t)
            if (pts.length)
                len += Math.hypot(x - px, y - py)
            pts.push({ x: x, y: y, l: len })
            px = x
            py = y
        }
        const at = l => {
            let k = 0
            while (k < pts.length - 1 && pts[k].l < l)
                k++
            return pts[k]
        }
        const list = []
        shownGroups.forEach((g, gi) => {
            list.push({ w: 2, title: true, g: gi, j: -1 })
            g.items.forEach((_, j) => list.push({ w: 1, title: false, g: gi, j: j }))
        })
        const total = list.reduce((s, x) => s + x.w, 0)
        let acc = 0.3
        const out = []
        for (const s of list) {
            const p = at((acc + s.w / 2) / (total + 0.6) * len)
            acc += s.w
            out.push({ x: p.x, y: p.y, ux: (p.x - cx) / rx, uy: (p.y - cy) / ry, title: s.title, g: s.g, j: s.j })
        }
        return out
    }

    // ---- Орбита: пунктир по занятой дуге ----
    Shape {
        visible: !root.chipMode && root.slots.length > 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.outlineVariant
            strokeWidth: 2
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            dashPattern: [0.5, 3.5]
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.rx
                radiusY: root.ry
                startAngle: 90 + root.freeArc / 2
                sweepAngle: 360 - root.freeArc
            }
        }
    }

    // ---- Заголовки групп на орбите ----
    Repeater {
        model: root.chipMode ? [] : root.slots.filter(s => s.title)
        Label {
            required property var modelData
            readonly property var group: root.shownGroups[modelData.g]
            readonly property var groupStyle: root.styles[group ? group.key : "any"] ?? root.styles.any
            x: modelData.x - implicitWidth / 2
            y: modelData.y - implicitHeight / 2
            Behavior on x { enabled: !root.reduced; NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            Behavior on y { enabled: !root.reduced; NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            text: group ? group.title : ""
            type: "labelLarge"
            weight: 600
            color: root.roleColor(groupStyle.role)
            opacity: root.locked ? 0.38 : 1
        }
    }

    // ---- Сиды ----
    Repeater {
        model: root.chipMode ? [] : root.slots.filter(s => !s.title)
        Item {
            id: seed
            required property var modelData
            readonly property var group: root.shownGroups[modelData.g]
            readonly property var item: group ? group.items[modelData.j] ?? ({}) : ({})
            readonly property var style: root.styles[group ? group.key : "any"] ?? root.styles.any
            readonly property bool add: item.kind === "add"
            readonly property bool on: !add && item.uri !== "" && item.uri === root.selected
            readonly property real k: on ? 0.86 : 1
            width: root.seedSize
            height: root.seedSize
            x: root.cx + (modelData.x - root.cx) * k - width / 2
            y: root.cy + (modelData.y - root.cy) * k - height / 2
            z: on ? 2 : 1
            Behavior on x { enabled: !root.reduced; NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            Behavior on y { enabled: !root.reduced; NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            opacity: root.locked ? 0.38 : 1
            enabled: !root.locked && root.signedIn

            // ореол цвета группы у выбранного
            MorphShape {
                anchors.centerIn: parent
                width: parent.width + 18
                height: width
                shape: seed.on ? seed.style.shape : "circle"
                color: root.roleBox(seed.style.role)
                scale: seed.on ? 1 : 0.6
                opacity: seed.on ? 1 : 0
                Behavior on scale { enabled: !root.reduced; NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: root.reduced ? 0 : Theme.motion.effectsDefault } }
            }
            MorphImage {
                anchors.fill: parent
                visible: !seed.add && (seed.item.cover ?? "") !== ""
                source: visible ? seed.item.cover : ""
                shape: seed.on ? seed.style.shape : area.containsMouse ? "cookie12" : "circle"
                duration: root.reduced ? 0 : Theme.motion.spatialDefault
            }
            MorphShape {
                anchors.fill: parent
                visible: seed.add || (seed.item.cover ?? "") === ""
                shape: seed.on ? seed.style.shape : area.containsMouse ? "cookie12" : "circle"
                duration: root.reduced ? 0 : Theme.motion.spatialDefault
                color: seed.add ? Theme.surfaceVariant : root.roleBox(seed.style.role)
                Icon {
                    anchors.centerIn: parent
                    name: seed.add ? "add" : ({ track: "music_note", artist: "person", album: "album", playlist: "queue_music" })[seed.item.kind] ?? "radio"
                    size: root.seedSize * 0.42
                    color: Theme.fgSurfaceVariant
                }
            }
            // подпись — внутрь орбиты, по нормали к центру (на верхней дуге — под кружком)
            Label {
                width: 74
                x: seed.width / 2 - seed.modelData.ux * (seed.width / 2 + 6 + 44 * Math.abs(seed.modelData.ux)) - width / 2
                y: seed.height / 2 - seed.modelData.uy * (seed.height / 2 + 12) - implicitHeight / 2
                horizontalAlignment: Text.AlignHCenter
                text: seed.item.label ?? ""
                type: "labelSmall"
                weight: seed.on ? 700 : 500
                color: seed.on ? root.roleColor(seed.style.role) : Theme.fgSurfaceVariant
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: seed.add ? root.addRequested(seed) : root.picked(seed.item.uri)
            }
        }
    }

    // ---- Центр ----
    Item {
        id: hero
        width: root.chipMode ? Math.min(176, root.width * 0.5) : root.heroSize
        height: width
        x: root.cx - width / 2
        y: root.chipMode ? 16 : root.cy - height / 2
        z: 3
        readonly property bool closed: root.locked || !root.signedIn

        MorphShape {
            anchors.fill: parent
            shape: hero.closed ? "cookie12" : root.currentStyle.shape
            duration: root.reduced ? 0 : Theme.motion.spatialSlow
            color: hero.closed ? Theme.surfaceContainerHigh : root.roleBox(root.currentStyle.role)
            Behavior on color { enabled: !Theme.transitioning && !root.reduced; ColorAnimation { duration: Theme.motion.effectsSlow } }
        }
        MorphImage {
            width: parent.width * 0.7
            height: width
            anchors.centerIn: parent
            visible: !hero.closed && root.current !== null && (root.current.item.cover ?? "") !== ""
            source: visible ? root.current.item.cover : ""
            shape: root.playing ? "cookie6" : "clover4"
            duration: root.reduced ? 0 : Theme.motion.spatialSlow
        }
        PlayButton {
            anchors.centerIn: parent
            visible: !hero.closed && !root.loading
            size: 72
            playing: root.playing
            spin: false
            pausedShape: "cookie6"
            playingShape: "cookie9"
            enabled: root.current !== null
            onClicked: root.playClicked()
        }
        LoadingIndicator {
            anchors.centerIn: parent
            visible: root.loading && !hero.closed
            size: 84
            color: Theme.primary
        }
        Icon {
            anchors.centerIn: parent
            visible: hero.closed
            name: "lock"
            size: 32
            color: Theme.fgSurfaceVariant
        }
    }

    // ---- Подпись под центром ----
    ColumnLayout {
        id: caption
        width: Math.min(460, root.width - 32)
        x: root.cx - width / 2
        y: hero.y + hero.height + (root.chipMode ? 12 : 8)
        spacing: 2

        readonly property string kindText: {
            const c = root.current
            if (!c)
                return "Радио"
            return ({ track: "Радио по треку", artist: "Радио по исполнителю", album: "Радио по альбому", playlist: "Радио по плейлисту" })[c.item.kind] ?? "Радио"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: !root.signedIn || root.locked ? "Радио недоступно"
                : root.loading ? "Радио"
                : (root.playing ? "Сейчас играет · " : "") + caption.kindText
                  + (root.current && root.current.first && root.current.group.key === "recent" ? " · последний прослушанный" : "")
            type: "labelLarge"
            color: Theme.primary
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !root.signedIn ? "Войдите в аккаунт Spotify"
                : root.locked ? (root.premium ? "Подключите воспроизведение на этом компьютере" : "Радио Spotify играет только с Premium")
                : root.loading ? "Собираем станцию…"
                : root.current ? root.current.item.label ?? "" : "Выберите трек, исполнителя или плейлист"
            type: root.locked || !root.signedIn || root.loading ? "titleLarge" : "headlineSmall"
            weight: 500
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !root.signedIn ? "Станции по вашим трекам, исполнителям и плейлистам появятся после входа."
                : root.locked ? (root.premium
                    ? "Станции Spotify приходят только через сессию воспроизведения (Web API их не отдаёт). Отдельный вход в браузере, нужен Spotify Premium."
                    : "Станции приходят через сессию воспроизведения, а она доступна только с подпиской Premium.")
                : root.errorText !== "" ? root.errorText
                : root.loading ? "50 треков одним пакетом"
                : "50 треков · каждый запуск — новый микс"
            type: "bodySmall"
            color: root.errorText !== "" && !root.locked && root.signedIn ? Theme.error : Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
        }
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            spacing: 8
            visible: !root.loading
            // вход / подключение воспроизведения
            Button {
                visible: !root.signedIn
                text: "Войти"
                icon: "login"
                onClicked: root.loginRequested()
            }
            Button {
                visible: root.signedIn && root.locked
                text: root.premium ? "Подключить воспроизведение" : "Подробнее о Premium"
                icon: root.premium ? "login" : "workspace_premium"
                onClicked: root.connectRequested()
            }
            Button {
                visible: root.signedIn && root.locked && root.premium
                text: "Подробнее"
                style: "text"
                onClicked: root.moreRequested()
            }
            // станция
            Button {
                visible: root.signedIn && !root.locked && root.current !== null
                text: "Список треков"
                icon: "format_list_bulleted"
                style: "tonal"
                size: "xs"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.openList()
            }
            IconButton {
                visible: root.signedIn && !root.locked && root.current !== null
                icon: "bookmark_add"
                size: "xs"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.saveRequested()
            }
            IconButton {
                visible: root.signedIn && !root.locked && root.current !== null
                icon: "refresh"
                size: "xs"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.refreshRequested()
            }
        }
    }

    // ---- Узкая сцена: группы сидов чипами под подписью ----
    Column {
        id: chipColumn
        visible: root.chipMode
        x: 16
        y: caption.y + caption.implicitHeight + 16
        width: root.width - 32
        spacing: 12
        Repeater {
            model: root.chipMode ? root.shownGroups : []
            Column {
                id: chipGroup
                required property var modelData
                readonly property var style: root.styles[modelData.key] ?? root.styles.any
                width: chipColumn.width
                spacing: 6
                opacity: root.locked ? 0.38 : 1
                enabled: !root.locked && root.signedIn
                Label { text: chipGroup.modelData.title; type: "titleSmall"; weight: 600; color: root.roleColor(chipGroup.style.role) }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: chipGroup.modelData.items
                        Item {
                            id: chip
                            required property var modelData
                            readonly property bool add: modelData.kind === "add"
                            readonly property bool on: !add && modelData.uri === root.selected
                            implicitWidth: chipRow.implicitWidth + 24
                            implicitHeight: 36
                            Rectangle {
                                id: chipBg
                                anchors.fill: parent
                                radius: chip.on ? 10 : height / 2
                                color: chip.on ? root.roleColor(chipGroup.style.role) : root.roleBox(chipGroup.style.role)
                                Behavior on radius { enabled: !root.reduced; NumberAnimation { duration: Theme.motion.spatialFast; easing.type: Easing.OutBack } }
                            }
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6
                                MorphImage {
                                    visible: !chip.add && (chip.modelData.cover ?? "") !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    source: visible ? chip.modelData.cover : ""
                                    shape: chip.on ? chipGroup.style.shape : "circle"
                                }
                                Icon { visible: chip.add; name: "add"; size: 18; anchors.verticalCenter: parent.verticalCenter; color: Theme.fgSurfaceVariant }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData.label ?? ""
                                    type: "labelLarge"
                                    color: chip.on ? root.roleOn(chipGroup.style.role) : Theme.fgSurfaceVariant
                                }
                            }
                            StateLayer {
                                anchors.fill: parent
                                radius: chipBg.radius
                                onClicked: chip.add ? root.addRequested(chip) : root.picked(chip.modelData.uri)
                            }
                        }
                    }
                }
            }
        }
    }
}
