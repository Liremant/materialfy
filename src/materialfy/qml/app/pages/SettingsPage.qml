import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Настройки: аккаунт и разрешения, воспроизведение, Spotify Connect, сеть, хранилище, внешний вид.
// Каждая строка пишет в Settings сразу; прокси — черновиком формы и кнопкой «Применить».
Page {
    id: page
    title: I18n.t("Settings")

    property string section           // раздел из маршрута: прокрутить к нему при открытии

    readonly property bool signedIn: Auth.state === "signedIn"
    readonly property var account: Auth.account ?? ({})
    readonly property bool compact: width < 760

    readonly property var sections: [
        { key: "account", text: I18n.t("Account"), icon: "account_circle" },
        { key: "playback", text: I18n.t("Playback"), icon: "graphic_eq" },
        { key: "connect", text: "Spotify Connect", icon: "speaker_group" },
        { key: "network", text: I18n.t("Network"), icon: "lan" },
        { key: "storage", text: I18n.t("Storage"), icon: "database" },
        { key: "appearance", text: I18n.t("Appearance"), icon: "palette" }
    ]
    property string currentSection: "account"

    readonly property var backdropModes: [
        { mode: "gauss", text: I18n.t("Soft"), hint: I18n.t("Even blur with no blotches or banding: the cover melts smoothly into color") },
        { mode: "glass", text: I18n.t("Frosted glass"), hint: I18n.t("The cover shows through as if behind frosted glass, with fine grain on top") },
        { mode: "palette", text: I18n.t("Gradient"), hint: I18n.t("No cover: a smooth gradient of theme colors") },
        { mode: "blobs", text: I18n.t("Blobs"), hint: I18n.t("Large color blobs") }
    ]

    readonly property var transitions: [
        { mode: "wipe", text: I18n.t("Wipe"), hint: I18n.t("New colors and background slide in from the side: left to right for the next track, right to left for the previous one") },
        { mode: "ripple", text: I18n.t("Ripple from cover"), hint: I18n.t("New colors and background spread out from the cover in a wavy-edged shape") },
        { mode: "dissolve", text: I18n.t("Dissolve"), hint: I18n.t("Old colors and background gently fade away, revealing the new ones") },
        { mode: "liquid", text: I18n.t("Liquid"), hint: I18n.t("The old image flows and melts away in an uneven wave toward the transition") }
    ]

    readonly property var variantNames: ({
        content: I18n.t("From cover"), tonalSpot: I18n.t("Calm"), vibrant: I18n.t("Vibrant"), expressive: I18n.t("Expressive"),
        fidelity: I18n.t("Fidelity"), neutral: I18n.t("Neutral"), monochrome: I18n.t("Monochrome")
    })

    readonly property var bitrates: [
        { value: 96, text: "96", hint: I18n.t("96 kbps — saves data") },
        { value: 160, text: "160", hint: I18n.t("160 kbps — same as the regular Spotify app") },
        { value: 320, text: "320", hint: I18n.t("320 kbps — the best quality Spotify serves. Lossless isn’t available") }
    ]

    // ---- Прокрутка к разделам ----
    function cardFor(key) {
        switch (key) {
        case "account": return accountCard
        case "playback": return playbackCard
        case "connect": return connectCard
        case "network": return networkCard
        case "storage": return storageCard
        case "appearance": return appearanceCard
        }
        return null
    }
    function _cardY(card) {
        return card.mapToItem(page.flickable.contentItem, 0, 0).y - nav.height - 16
    }
    function scrollToSection(key, animated) {
        const card = cardFor(key)
        if (!card)
            return
        currentSection = key
        _following = false
        page.flickable.scrollTo(Math.max(0, _cardY(card)), animated && !Theme.reducedMotion)
        followTimer.restart()
    }
    // во время программной прокрутки выбранный чип не прыгает по промежуточным карточкам
    property bool _following: true
    Timer { id: followTimer; interval: Theme.motion.spatialDefault + 200; onTriggered: page._following = true }
    function _followScroll() {
        if (!_following)
            return
        const y = page.flickable.contentY
        let cur = sections[0].key
        for (const s of sections) {
            const card = cardFor(s.key)
            if (card && _cardY(card) <= y + 40)
                cur = s.key
        }
        if (page.flickable.contentY >= page.flickable.maxY - 2)
            cur = sections[sections.length - 1].key
        currentSection = cur
    }
    Connections {
        target: page.flickable
        function onContentYChanged() { page._followScroll() }
    }

    Component.onCompleted: {
        Settings.refreshAudioDevices()
        Settings.refreshCacheUsage()
        if (signedIn)
            Devices.refresh()
        if (section !== "")
            openSection.start()
    }
    // раскладка карточек готова не сразу после создания страницы
    Timer { id: openSection; interval: 60; onTriggered: page.scrollToSection(page.section, false) }

    // ---- Липкий ряд разделов ----
    Item {
        id: navHost
        Layout.fillWidth: true
        Layout.topMargin: -8
        implicitHeight: nav.height
        z: 10
        readonly property real stick: Math.max(0, page.flickable.contentY - y - 8)
        transform: Translate { y: navHost.stick }

        Rectangle {
            x: -page.sideMargin
            width: page.width
            y: -8
            height: nav.height + 16
            color: Theme.surfaceContainer     // цвет панели контента (Surface level "container")
            opacity: navHost.stick > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsFast } }
        }
        SettingsNav {
            id: nav
            width: parent.width
            sections: page.sections
            current: page.currentSection
            onPicked: key => page.scrollToSection(key, true)
        }
    }

    // ================= Аккаунт =================
    SettingsCard {
        id: accountCard
        title: I18n.t("Spotify account")
        icon: "account_circle"

        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            Item {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                Avatar {
                    anchors.fill: parent
                    size: 72
                    visible: (page.account.avatar ?? "") === ""
                    name: page.signedIn ? (page.account.displayName ?? "") : ""
                }
                MorphImage {
                    anchors.fill: parent
                    visible: (page.account.avatar ?? "") !== ""
                    source: page.account.avatar ?? ""
                    shape: "cookie9"
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    Layout.fillWidth: true
                    text: page.signedIn ? (page.account.displayName || page.account.id || I18n.t("Spotify account")) : I18n.t("Not signed in")
                    type: "headlineSmall"
                    weight: 600
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: page.signedIn
                          ? [page.account.uri ?? "", page.account.country ?? ""].filter(x => x).join("  ·  ")
                          : I18n.t("Sign in to see your library and control playback")
                    type: "bodyMedium"
                    color: Theme.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                StatusChip {
                    visible: page.signedIn
                    Layout.topMargin: 4
                    kind: Auth.premium ? "ok" : "neutral"
                    icon: Auth.premium ? "workspace_premium" : ""
                    text: Auth.premium ? "Premium" : "Free"
                }
            }
            Button {
                visible: page.signedIn
                Layout.alignment: Qt.AlignTop
                text: page.compact ? "" : I18n.t("Sign out")
                icon: "logout"
                style: "outlined"
                onClicked: Auth.signOut()
            }
            Button {
                visible: !page.signedIn
                Layout.alignment: Qt.AlignTop
                text: I18n.t("Sign in")
                icon: "login"
                onClicked: page.router ? page.router.reset("account") : Auth.startLogin()
            }
        }

        SettingsBanner {
            kind: "error"
            shown: page.signedIn && !Auth.premium
            title: I18n.t("Playback requires Premium")
            text: I18n.t("Spotify only allows listening in third-party apps with Premium. Without it, library, search and controlling other devices still work.")
            actionText: I18n.t("Check again")
            actionIcon: "refresh"
            onAction: Auth.refreshProfile()
        }
        SettingsBanner {
            kind: "info"
            shown: page.signedIn && Auth.premium && Auth.playbackState === "none"
            title: I18n.t("Playback on this computer isn’t allowed")
            text: I18n.t("Signing in through a Spotify session plays audio here and lets your library bypass Web API limits. A browser window will open.")
            actionText: I18n.t("Allow")
            actionIcon: "open_in_new"
            onAction: Auth.authorizePlayback()
        }

        // До входа — вход (Premium — через сессию); после — необязательный вход Web API общего ключа:
        // запасной путь для разделов, которых нет в сессии, и единственный вход без Premium.
        SettingRow {
            id: webRow
            readonly property string ws: Auth.webState
            title: page.signedIn ? I18n.t("Web API · optional") : I18n.t("Spotify sign-in")
            description: !page.signedIn
                         ? (Auth.state === "awaitingBrowser" ? I18n.t("Confirm sign-in in your browser")
                            : Auth.state === "connecting" || Auth.state === "checking" ? I18n.t("Signing in…")
                            : Auth.state === "error" ? (Auth.errorText || I18n.t("Sign-in failed"))
                            : I18n.t("One sign-in with Spotify Premium: library and music right here. Without Premium, sign in via the Web API"))
                         : ws === "ready" ? I18n.t("Connected: fallback for sections the Spotify session doesn’t cover")
                         : ws === "authorizing" ? I18n.t("Confirm sign-in in your browser")
                         : ws === "error" ? (Auth.errorText || I18n.t("Couldn’t connect the Web API"))
                         : I18n.t("Not needed with Premium: almost everything goes through the session. Spotify rate-limits the shared key")
            Row {
                spacing: 8
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.signedIn && webRow.ws === "ready"
                    kind: "ok"
                    text: I18n.t("Connected")
                }
                LoadingIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.signedIn && webRow.ws === "authorizing"
                    size: 28
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.signedIn && (webRow.ws === "none" || webRow.ws === "error")
                    text: I18n.t("Connect")
                    icon: "open_in_new"
                    style: "outlined"
                    size: "xs"
                    onClicked: Auth.startWebLogin()
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !page.signedIn
                    text: Auth.state === "error" ? I18n.t("Retry") : I18n.t("Sign in")
                    icon: "open_in_new"
                    style: "filled"
                    size: "xs"
                    onClicked: Auth.state === "error" ? Auth.retry() : Auth.startLogin()
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !page.signedIn && Auth.state !== "awaitingBrowser" && Auth.state !== "connecting"
                    text: I18n.t("Without Premium")
                    style: "text"
                    size: "xs"
                    onClicked: Auth.startWebLogin()
                }
            }
        }

        SettingRow {
            id: playbackRow
            readonly property string st: Auth.playbackState
            enabled: page.signedIn
            opacity: enabled ? 1 : 0.5
            title: I18n.t("Spotify session and audio here")
            description: !page.signedIn ? I18n.t("Turns on when you sign in with Spotify Premium")
                         : st === "ready" ? I18n.t("Audio plays on this computer and the library goes through the session; it shows up in Spotify Connect")
                         : st === "authorizing" ? I18n.t("Confirm permission in your browser")
                         : st === "connecting" ? I18n.t("Connecting to Spotify…")
                         : st === "error" ? (Auth.playbackError || I18n.t("Couldn’t connect playback"))
                         : st === "premiumRequired" || !Auth.premium ? I18n.t("Spotify Premium required: without it, only the library and remote control via the Web API")
                         : I18n.t("Sign in through a Spotify session: audio here and a library without Web API limits")
            Row {
                spacing: 8
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "ready"
                    kind: "ok"
                    text: I18n.t("Connected")
                }
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.signedIn && (playbackRow.st === "premiumRequired" || (!Auth.premium && playbackRow.st === "none"))
                    kind: "warn"
                    text: I18n.t("Premium required")
                }
                LoadingIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "authorizing" || playbackRow.st === "connecting"
                    size: 28
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "ready"
                    // без Web API сессия — единственный вход: отключить её = выйти
                    text: Auth.webState !== "ready" && Auth.personalState !== "ready" ? I18n.t("Sign out") : I18n.t("Disconnect")
                    style: "text"
                    size: "xs"
                    onClicked: Auth.disablePlayback()
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "authorizing"
                    text: I18n.t("Cancel")
                    style: "text"
                    size: "xs"
                    onClicked: Auth.cancelLogin()
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Auth.premium && (playbackRow.st === "none" || playbackRow.st === "error")
                    text: playbackRow.st === "error" ? I18n.t("Retry") : I18n.t("Allow")
                    icon: "open_in_new"
                    size: "xs"
                    onClicked: Auth.authorizePlayback()
                }
            }
        }

        // общий Client ID упёрся в 429/квоту: что через сессию — работает, остальное ждёт
        SettingsBanner {
            kind: "info"
            shown: page.signedIn && Settings.webApiLimit !== ""
            title: I18n.t("Web API is rate-limited")
            text: Settings.webApiLimit
            actionText: Auth.personalState === "ready" ? "" : I18n.t("Own Client ID")
            actionIcon: "key"
            onAction: {
                clientIdField.text = Auth.personalClientId
                personalRow.editing = true
                clientIdField.forceActiveFocus()
            }
        }

        SettingRow {
            id: personalRow
            property bool editing: false
            enabled: page.signedIn
            opacity: enabled ? 1 : 0.5
            title: I18n.t("Personal Spotify app")
            description: Auth.personalState === "ready" ? I18n.t("Client ID {0} — requests go through your app", Auth.personalClientId)
                         : Auth.personalState === "authorizing" ? I18n.t("Confirm access in your browser")
                         : Auth.personalState === "error" ? I18n.t("Couldn’t connect your personal app")
                         : I18n.t("Optional: your own Client ID from developer.spotify.com removes the shared request limits")
            Row {
                spacing: 8
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Auth.personalState === "ready"
                    kind: "ok"
                    text: I18n.t("Configured")
                }
                LoadingIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Auth.personalState === "authorizing"
                    size: 28
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !personalRow.editing
                    text: Auth.personalState === "ready" ? I18n.t("Edit") : I18n.t("Set up")
                    icon: Auth.personalState === "ready" ? "" : "key"
                    style: Auth.personalState === "ready" ? "text" : "outlined"
                    size: "xs"
                    onClicked: {
                        clientIdField.text = Auth.personalClientId
                        personalRow.editing = true
                        clientIdField.forceActiveFocus()
                    }
                }
            }
        }
        // форма Client ID раскрывается под строкой
        Item {
            id: personalForm
            Layout.fillWidth: true
            implicitHeight: personalRow.editing ? formCol.implicitHeight : 0
            Behavior on implicitHeight { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            opacity: personalRow.editing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsDefault } }
            visible: implicitHeight > 0.5
            clip: true

            ColumnLayout {
                id: formCol
                width: parent.width
                spacing: 12
                TextField {
                    id: clientIdField
                    Layout.fillWidth: true
                    Layout.maximumWidth: 480
                    label: "Client ID"
                    placeholderText: I18n.t("32 characters from the Spotify developer dashboard")
                    leadingIcon: "key"
                    supportingText: I18n.t("App redirect URI: http://127.0.0.1:8989/login")
                    onAccepted: saveClientId.clicked()
                }
                Row {
                    spacing: 8
                    Button {
                        id: saveClientId
                        text: I18n.t("Save")
                        size: "xs"
                        enabled: clientIdField.text.trim() !== ""
                        onClicked: {
                            Auth.setPersonalClientId(clientIdField.text.trim())
                            personalRow.editing = false
                        }
                    }
                    Button {
                        visible: Auth.personalClientId !== ""
                        text: I18n.t("Remove")
                        style: "text"
                        size: "xs"
                        onClicked: {
                            Auth.setPersonalClientId("")
                            personalRow.editing = false
                        }
                    }
                    Button {
                        text: I18n.t("Cancel")
                        style: "text"
                        size: "xs"
                        onClicked: personalRow.editing = false
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: Auth.tokenStorage === "keyring"
                  ? I18n.t("Permissions are stored in Windows Credential Manager. “Sign out” removes all three; the cache stays.")
                  : I18n.t("Secret storage is unavailable: permissions last until the app closes. “Sign out” removes all three; the cache stays.")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }

    // ================= Воспроизведение =================
    SettingsCard {
        id: playbackCard
        title: I18n.t("Playback")
        icon: "graphic_eq"

        SettingsBanner {
            kind: "info"
            icon: "restart_alt"
            shown: Settings.engineRestartPending === true
            busy: Auth.playbackState === "connecting"
            title: I18n.t("Audio restart needed")
            text: I18n.t("New settings take effect after a restart; the track will resume from the same spot.")
            actionText: I18n.t("Apply")
            onAction: Settings.applyEngineSettings()
        }

        SettingRow {
            title: I18n.t("Audio quality")
            description: (page.bitrates.find(b => b.value === Settings.bitrate) ?? page.bitrates[1]).hint
            ButtonGroup {
                model: page.bitrates.map(b => I18n.t("{0} kbps", b.text))
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: page.bitrates.findIndex(b => b.value === Settings.bitrate)
                onActivated: i => Settings.bitrate = page.bitrates[i].value
            }
        }
        SettingRow {
            title: I18n.t("Volume normalization")
            description: I18n.t("Tracks play at the same loudness")
            Switch { checked: Settings.normalisation; onToggled: c => Settings.normalisation = c }
        }
        SettingRow {
            title: I18n.t("Gapless playback")
            description: I18n.t("The next track starts without silence — for live albums and mixes")
            Switch { checked: Settings.gapless; onToggled: c => Settings.gapless = c }
        }
        SettingRow {
            title: I18n.t("Autoplay")
            description: I18n.t("When an album or playlist ends, similar music plays")
            Switch { checked: Settings.autoplay; onToggled: c => Settings.autoplay = c }
        }
        SettingRow {
            title: I18n.t("Crossfade")
            enabled: Settings.gapless
            opacity: enabled ? 1 : 0.5
            description: !Settings.gapless ? I18n.t("Works together with “Gapless playback”")
                : Settings.crossfade > 0 ? I18n.t("The end of a track fades out as the next one fades in")
                : I18n.t("Off: tracks play back to back")
            Slider {
                width: 220
                from: 0
                to: 12
                stepSize: 1
                value: Settings.crossfade
                valueText: v => Math.round(v) === 0 ? I18n.t("None") : I18n.t("{0} s", Math.round(v))
                onMoved: v => Settings.crossfade = Math.round(v)
            }
        }
        SettingRow {
            title: I18n.t("Playback speed")
            description: I18n.t("Pitch stays the same. Applies on this computer")
            Slider {
                width: 220
                from: 0.5
                to: 2
                stepSize: 0.05
                value: Settings.playbackSpeed
                valueText: v => { const p = (Math.round(v * 100) / 100).toString().split("."); return p.length > 1 ? I18n.t("{0}.{1}×", p[0], p[1]) : p[0] + "×" }
                onMoved: v => Settings.playbackSpeed = Math.round(v * 20) / 20
            }
        }
        SettingRow {
            title: I18n.t("Output device")
            description: I18n.t("Where this computer’s audio goes")
            MenuField {
                width: page.compact ? 220 : 280
                leadingIcon: "speaker"
                model: [{ id: "", text: I18n.t("System default") }].concat((Settings.audioDevices ?? []).map(d => ({ id: d, text: d })))
                currentValue: Settings.audioDevice
                onActivated: v => Settings.audioDevice = v
            }
        }
        SettingRow {
            title: I18n.t("Volume")
            enabled: !Player.remote
            opacity: enabled ? 1 : 0.5
            description: Player.remote ? I18n.t("Another device is playing — its volume is in the mini player") : ""
            Slider {
                width: 220
                from: 0
                to: 1
                stepSize: 0.01
                value: Settings.volume
                valueText: v => Math.round(v * 100) + " %"
                onMoved: v => Player.volume = v
            }
        }
    }

    // ================= Spotify Connect =================
    SettingsCard {
        id: connectCard
        title: "Spotify Connect"
        icon: "speaker_group"

        SettingRow {
            title: I18n.t("Device name")
            description: I18n.t("How this computer appears in Spotify on your phone and other devices")
            TextField {
                id: deviceNameField
                width: page.compact ? 220 : 280
                text: Settings.deviceName
                placeholderText: Devices.thisDeviceName || "Materialfy"
                leadingIcon: "computer"
                function commit() {
                    const t = text.trim()
                    if (t !== Settings.deviceName)
                        Settings.deviceName = t
                }
                onAccepted: commit()
                Connections {
                    target: deviceNameField.inputItem
                    function onActiveFocusChanged() {
                        if (!deviceNameField.inputItem.activeFocus)
                            deviceNameField.commit()
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            enabled: page.signedIn
            opacity: enabled ? 1 : 0.5

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label { Layout.fillWidth: true; text: I18n.t("Account devices"); type: "bodyLarge" }
                    Label {
                        Layout.fillWidth: true
                        text: !page.signedIn ? I18n.t("Sign in to see devices")
                              : Devices.errorText !== "" ? Devices.errorText
                              : I18n.t("From Spotify and your local network. “Play there” moves playback")
                        type: "bodySmall"
                        color: Devices.errorText !== "" ? Theme.error : Theme.fgSurfaceVariant
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                }
                LoadingIndicator { visible: Devices.loading; size: 28 }
                IconButton {
                    icon: "refresh"
                    enabled: !Devices.loading
                    onClicked: Devices.refresh()
                }
            }

            Repeater {
                model: page.signedIn ? Devices.devices : null
                DeviceRow {
                    required property int index
                    required property var model
                    Layout.fillWidth: true
                    variant: "settings"
                    device: Devices.devices.get(index)
                    busy: Devices.transferringTo !== "" && Devices.transferringTo === model.id
                    disabled: model.isRestricted === true
                    onActivated: {
                        if (model.source === "zeroconf" && !model.isActive)
                            Devices.activateReceiver(model.name)
                        else
                            Devices.transfer(model.id)
                    }
                }
            }
            Label {
                visible: page.signedIn && !Devices.loading && Devices.devices.count === 0
                Layout.fillWidth: true
                text: I18n.t("No other devices found. Open Spotify on your phone or speaker and tap “Refresh”.")
                type: "bodyMedium"
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }

        Label {
            Layout.fillWidth: true
            text: I18n.t("Google Cast and Chromecast aren’t supported.")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }

    // ================= Сеть =================
    SettingsCard {
        id: networkCard
        title: I18n.t("Network")
        icon: "lan"

        // черновик формы: начальные значения — применённые настройки
        QtObject {
            id: proxy
            property string mode: Settings.proxyMode || "off"
            property string host: Settings.proxyHost
            property string port: Settings.proxyPort
            property string username: Settings.proxyUsername
            property string password: ""
            readonly property bool manual: mode === "http" || mode === "socks"
            readonly property bool dirty: mode !== (Settings.proxyMode || "off")
                || (manual && (host !== Settings.proxyHost || port !== Settings.proxyPort
                               || username !== Settings.proxyUsername || password !== ""))
            readonly property bool valid: !manual || (host.trim() !== "" && /^\d{1,5}$/.test(port.trim()) && Number(port) <= 65535)
            function reset() {
                mode = Settings.proxyMode || "off"
                host = Settings.proxyHost
                port = Settings.proxyPort
                username = Settings.proxyUsername
                password = ""
                hostField.text = host
                portField.text = port
                userField.text = username
                passField.text = ""
            }
            function apply() {
                Settings.applyProxy(mode, host.trim(), port.trim(), username.trim(), password)
            }
        }
        Connections {
            target: Settings
            function onProxyStateChanged() {
                if (Settings.proxyState === "ok")
                    proxy.reset()
            }
        }

        readonly property var modes: ["off", "system", "http", "socks"]
        SettingRow {
            title: I18n.t("Proxy")
            description: proxy.mode === "off" ? I18n.t("Direct, no proxy")
                         : proxy.mode === "system" ? I18n.t("Same as Windows settings")
                         : proxy.mode === "http" ? I18n.t("HTTP proxy (CONNECT)") : I18n.t("SOCKS5 proxy")
            ButtonGroup {
                model: [I18n.t("Off"), I18n.t("System proxy"), "HTTP", "SOCKS5"]
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: networkCard.modes.indexOf(proxy.mode)
                onActivated: i => proxy.mode = networkCard.modes[i]
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: proxy.manual ? fields.implicitHeight : 0
            Behavior on implicitHeight { NumberAnimation { duration: Theme.motion.spatialDefault; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasized } }
            opacity: proxy.manual ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.motion.effectsDefault } }
            visible: implicitHeight > 0.5
            clip: true

            GridLayout {
                id: fields
                width: parent.width
                columns: page.compact ? 1 : 2
                columnSpacing: 16
                rowSpacing: 12
                TextField {
                    id: hostField
                    Layout.fillWidth: true
                    label: I18n.t("Host")
                    placeholderText: "proxy.example.com"
                    text: Settings.proxyHost
                    onEdited: proxy.host = text
                }
                TextField {
                    id: portField
                    Layout.fillWidth: true
                    label: I18n.t("Port")
                    placeholderText: proxy.mode === "socks" ? "1080" : "8080"
                    text: Settings.proxyPort
                    inputMethodHints: Qt.ImhDigitsOnly
                    maximumLength: 5
                    error: text !== "" && !/^\d{1,5}$/.test(text)
                    onEdited: proxy.port = text
                }
                TextField {
                    id: userField
                    Layout.fillWidth: true
                    label: I18n.t("Username")
                    placeholderText: I18n.t("optional")
                    text: Settings.proxyUsername
                    onEdited: proxy.username = text
                }
                TextField {
                    id: passField
                    Layout.fillWidth: true
                    label: I18n.t("Password")
                    placeholderText: Settings.proxyUsername !== "" ? I18n.t("empty — unchanged") : I18n.t("optional")
                    echoMode: TextInput.Password
                    onEdited: proxy.password = text
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: proxy.dirty || Settings.proxyState !== ""
            StatusChip {
                visible: Settings.proxyState === "ok" && !proxy.dirty
                kind: "ok"
                text: I18n.t("Applied")
            }
            LoadingIndicator { visible: Settings.proxyState === "applying"; size: 28 }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: Settings.proxyState === "applying" ? I18n.t("Checking the connection through the proxy…")
                      : Settings.proxyState === "error" ? (Settings.proxyError || I18n.t("Proxy isn’t responding"))
                      : ""
                type: "bodyMedium"
                color: Settings.proxyState === "error" ? Theme.error : Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
            Item { Layout.fillWidth: true; visible: Settings.proxyState !== "applying" && Settings.proxyState !== "error" }
            Button {
                visible: proxy.dirty
                text: I18n.t("Revert")
                style: "text"
                onClicked: proxy.reset()
            }
            Button {
                visible: proxy.dirty
                enabled: proxy.valid && Settings.proxyState !== "applying"
                text: I18n.t("Apply")
                icon: "check"
                onClicked: proxy.apply()
            }
        }

        Label {
            Layout.fillWidth: true
            text: I18n.t("The proxy password is stored in Credential Manager. Local network device discovery bypasses the proxy.")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }

    // ================= Хранилище =================
    SettingsCard {
        id: storageCard
        title: I18n.t("Storage")
        icon: "database"

        SettingRow {
            title: I18n.t("Audio cache")
            description: I18n.t("Played tracks are saved to disk and won’t be downloaded again")
            Switch { checked: Settings.audioCache; onToggled: c => Settings.audioCache = c }
        }
        SettingRow {
            title: I18n.t("Cache size")
            enabled: Settings.audioCache
            opacity: enabled ? 1 : 0.5
            description: I18n.t("Older tracks are removed when the cache is full")
            Slider {
                width: 220
                from: 256
                to: 10240
                stepSize: 256
                value: Settings.audioCacheMb
                valueText: v => v >= 1024 ? I18n.t("{0} GB", I18n.decimal(v / 1024, v % 1024 ? 1 : 0)) : I18n.t("{0} MB", Math.round(v))
                onMoved: v => Settings.audioCacheMb = Math.round(v / 256) * 256
            }
        }
        StorageBar {
            Layout.fillWidth: true
            usage: Settings.cacheUsage ?? ({})
            limit: Settings.audioCache ? Settings.audioCacheMb * 1024 * 1024 : 0
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Button {
                text: I18n.t("Clear cache")
                icon: "delete_sweep"
                style: "outlined"
                onClicked: {
                    Settings.clearCache()
                    // занятые файлы (звук играющего трека) остаются — об этом не сообщаем, объём обновит мост
                    const w = page.Window.window
                    if (w && typeof w.notify === "function")
                        w.notify(I18n.t("Cache cleared"))
                }
            }
            Button {
                text: I18n.t("Open folder")
                icon: "folder_open"
                style: "text"
                onClicked: Settings.openCacheFolder()
            }
        }
        Label {
            Layout.fillWidth: true
            text: I18n.t("Clearing doesn’t sign you out or touch your settings.")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }

    // ================= Внешний вид =================
    SettingsCard {
        id: appearanceCard
        title: I18n.t("Appearance")
        icon: "palette"

        SettingRow {
            title: I18n.t("Language")
            // "system" (default) follows the OS UI language; the language names stay in their own language
            ButtonGroup {
                model: [I18n.t("System default"), "English", "Русский"]
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: Settings.language === "en" ? 1 : Settings.language === "ru" ? 2 : 0
                onActivated: i => Settings.language = ["system", "en", "ru"][i]
            }
        }

        SettingRow {
            title: I18n.t("Theme")
            ButtonGroup {
                model: [{ text: I18n.t("System"), icon: "contrast" }, { text: I18n.t("Light"), icon: "light_mode" }, { text: I18n.t("Dark"), icon: "dark_mode" }]
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: ["system", "light", "dark"].indexOf(Settings.themeMode)
                onActivated: i => Settings.themeMode = ["system", "light", "dark"][i]
            }
        }

        SettingRow {
            title: I18n.t("Color from cover")
            description: I18n.t("The app recolors to match the playing track’s cover")
            Switch { checked: Settings.accentFromCover; onToggled: c => Settings.accentFromCover = c }
        }

        SettingRow {
            title: I18n.t("Accent color")
            description: Settings.accentFromCover ? I18n.t("When nothing is playing") : I18n.t("The app’s main color")
            Flow {
                width: Math.min(8 * 40, Math.max(160, page.width - 2 * page.sideMargin - 48))
                spacing: 8
                Repeater {
                    model: [String(Theme.defaultSeed).toUpperCase(), "#1ED760", "#FF6D00", "#E8175D", "#6750A4", "#00A3FF", "#00BFA5", "#FFCC00"]
                    MorphShape {
                        required property string modelData
                        readonly property bool current: Settings.customSeed.toUpperCase() === modelData
                        width: 32
                        height: 32
                        shape: current ? "cookie6" : "circle"
                        color: modelData
                        MorphShape {
                            anchors.centerIn: parent
                            width: 12; height: 12
                            visible: parent.current
                            shape: "circle"
                            color: "white"
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Settings.customSeed = parent.modelData }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            Label { text: I18n.t("Color scheme"); type: "bodyLarge" }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: ThemeEngine.variants
                    Chip {
                        required property string modelData
                        text: page.variantNames[modelData] ?? modelData
                        selected: Settings.schemeVariant === modelData
                        onClicked: Settings.schemeVariant = modelData
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            Label { text: I18n.t("Color and background transition"); type: "bodyLarge" }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: page.transitions
                    Chip {
                        required property var modelData
                        text: modelData.text
                        selected: Settings.trackTransition === modelData.mode
                        onClicked: Settings.trackTransition = modelData.mode
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: (page.transitions.find(m => m.mode === Settings.trackTransition) ?? page.transitions[0]).hint
                type: "bodyMedium"
                color: Theme.fgSurfaceVariant
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            Label { text: I18n.t("Cover background"); type: "bodyLarge" }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: page.backdropModes
                    Chip {
                        required property var modelData
                        text: modelData.text
                        selected: Settings.backdropMode === modelData.mode
                        onClicked: Settings.backdropMode = modelData.mode
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: (page.backdropModes.find(m => m.mode === Settings.backdropMode) ?? page.backdropModes[0]).hint
                type: "bodyMedium"
                color: Theme.fgSurfaceVariant
            }
        }
        SettingRow {
            title: I18n.t("Animations")
            description: Settings.animations === "reduced" ? I18n.t("No motion or morphing: only short fades")
                         : Settings.animations === "full" ? I18n.t("All transitions, waves and morphs")
                         : Settings.systemReducedMotion === true ? I18n.t("Follows Windows: animation effects are currently off")
                         : I18n.t("Follows Windows “Animation effects”")
            ButtonGroup {
                model: [I18n.t("System default"), I18n.t("Full"), I18n.t("Minimal")]
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: ["system", "full", "reduced"].indexOf(Settings.animations)
                onActivated: i => Settings.animations = ["system", "full", "reduced"][i]
            }
        }
        SettingRow {
            title: I18n.t("Player background blur")
            enabled: Settings.backdropMode !== "palette"
            opacity: enabled ? 1 : 0.5
            description: Settings.backdropMode === "palette" ? I18n.t("The gradient doesn’t depend on the cover")
                : I18n.t("{0}% · 0 is a sharp cover, 100 is color only", Math.round(Settings.nowPlayingBlur * 100))
            Slider {
                width: 220
                from: 0
                to: 1
                stepSize: 0.05
                value: Settings.nowPlayingBlur
                valueText: v => Math.round(v * 100) + " %"
                onMoved: v => Settings.nowPlayingBlur = Math.round(v * 20) / 20
            }
        }
        SettingRow {
            title: I18n.t("Blur drift")
            description: Settings.nowPlayingDrift > 0
                ? I18n.t("Background colors slowly shift while music plays")
                : I18n.t("Off — the blur stays still")
            Slider {
                width: 220
                from: 0
                to: 1
                stepSize: 0.05
                value: Settings.nowPlayingDrift
                valueText: v => v > 0 ? Math.round(v * 100) + " %" : I18n.t("off")
                onMoved: v => Settings.nowPlayingDrift = Math.round(v * 20) / 20
            }
        }
        SettingRow {
            title: I18n.t("Save power in background")
            description: I18n.t("While the window is out of focus, decorative animations (progress wave, shapes, background shimmer) pause to reduce CPU load. Lyrics keep going")
            Switch { checked: Settings.calmWhenInactive; onToggled: c => Settings.calmWhenInactive = c }
        }
        SettingRow {
            title: I18n.t("Spinning cover frame")
            description: I18n.t("While music plays, the shaped cover frame slowly rotates; the image itself stays still")
            Switch { checked: Settings.coverSpin; onToggled: c => Settings.coverSpin = c }
        }
        SettingRow {
            title: I18n.t("Cover pulses to the beat")
            description: I18n.t("In the full-screen player, the cover gently pulses with the music’s loudness")
            Switch { checked: Settings.coverPulse; onToggled: c => Settings.coverPulse = c }
        }
        SettingRow {
            title: I18n.t("Ambient background")
            description: I18n.t("The playing track’s cover, blurred behind the whole window as a soft colored glow")
            Switch { checked: Settings.ambientBackground; onToggled: c => Settings.ambientBackground = c }
        }
    }

    SettingsCard {
        title: I18n.t("Window")
        icon: "web_asset"

        SettingRow {
            title: I18n.t("Compact sidebar")
            description: I18n.t("Icons only. Turns on automatically in a narrow window")
            Switch { checked: Settings.sidebarCollapsed; onToggled: c => Settings.sidebarCollapsed = c }
        }
        SettingRow {
            title: I18n.t("Minimize to tray on close")
            description: I18n.t("Closing the window hides it in the tray and the music keeps playing. Quit from the tray menu or with Ctrl+Q")
            Switch { checked: Settings.closeToTray; onToggled: c => Settings.closeToTray = c }
        }
        SettingRow {
            title: I18n.t("Mouse wheel scroll step")
            description: I18n.t("{0} px per notch; grows up to ×2 when scrolling fast", Settings.wheelStep)
            Slider {
                width: 220
                from: 60
                to: 480
                stepSize: 20
                value: Settings.wheelStep
                valueText: v => Math.round(v) + " px"
                onMoved: v => Settings.wheelStep = Math.round(v)
            }
        }
    }

    SettingsCard {
        title: I18n.t("About the app")
        icon: "info"

        SettingRow {
            title: "Materialfy 0.1"
            description: I18n.t("An unofficial Spotify client in Material 3 Expressive style. Playback requires Spotify Premium; no lossless, crossfade or offline downloads.")
        }
        Label {
            Layout.fillWidth: true
            text: I18n.t("Based on spotifast (crmne, MIT) and yamusic-md3 (yaskorinov, MIT); not affiliated with Spotify AB. Playback: librespot (MIT). Fonts: Google Sans (OFL), Material Symbols (Apache 2.0).")
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }
}
