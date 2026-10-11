import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Настройки: аккаунт и разрешения, воспроизведение, Spotify Connect, сеть, хранилище, внешний вид.
// Каждая строка пишет в Settings сразу; прокси — черновиком формы и кнопкой «Применить».
Page {
    id: page
    title: "Настройки"

    property string section           // раздел из маршрута: прокрутить к нему при открытии

    readonly property bool signedIn: Auth.state === "signedIn"
    readonly property var account: Auth.account ?? ({})
    readonly property bool compact: width < 760

    readonly property var sections: [
        { key: "account", text: "Аккаунт", icon: "account_circle" },
        { key: "playback", text: "Воспроизведение", icon: "graphic_eq" },
        { key: "connect", text: "Spotify Connect", icon: "speaker_group" },
        { key: "network", text: "Сеть", icon: "lan" },
        { key: "storage", text: "Хранилище", icon: "database" },
        { key: "appearance", text: "Внешний вид", icon: "palette" }
    ]
    property string currentSection: "account"

    readonly property var backdropModes: [
        { mode: "gauss", text: "Мягкое", hint: "Ровное размытие без пятен и полос: обложка плавно растворяется в цвете" },
        { mode: "glass", text: "Матовое стекло", hint: "Обложка угадывается, как за матовым стеклом; поверх — мелкое зерно" },
        { mode: "palette", text: "Градиент", hint: "Без обложки: плавный градиент из цветов темы" },
        { mode: "blobs", text: "Пятна", hint: "Крупные цветовые пятна" }
    ]

    readonly property var transitions: [
        { mode: "wipe", text: "Шторка", hint: "Новые цвета и фон въезжают сбоку: слева направо — следующий трек, справа налево — предыдущий" },
        { mode: "ripple", text: "Волна от обложки", hint: "Новые цвета и фон расходятся от обложки фигурой с волнистым краем" },
        { mode: "dissolve", text: "Растворение", hint: "Старые цвета и фон спокойно тают, проявляя новые" },
        { mode: "liquid", text: "Перетекание", hint: "Старая картинка растекается и тает неровной волной в сторону перехода" }
    ]

    readonly property var variantNames: ({
        content: "По обложке", tonalSpot: "Спокойная", vibrant: "Яркая", expressive: "Выразительная",
        fidelity: "Точная", neutral: "Нейтральная", monochrome: "Монохром"
    })

    readonly property var bitrates: [
        { value: 96, text: "96", hint: "96 кбит/с — экономит трафик" },
        { value: 160, text: "160", hint: "160 кбит/с — как в обычном приложении Spotify" },
        { value: 320, text: "320", hint: "320 кбит/с — наилучшее качество, которое отдаёт Spotify. Без потерь недоступно" }
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
        title: "Аккаунт Spotify"
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
                    text: page.signedIn ? (page.account.displayName || page.account.id || "Аккаунт Spotify") : "Вы не вошли"
                    type: "headlineSmall"
                    weight: 600
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: page.signedIn
                          ? [page.account.uri ?? "", page.account.country ?? ""].filter(x => x).join("  ·  ")
                          : "Войдите, чтобы видеть библиотеку и управлять воспроизведением"
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
                text: page.compact ? "" : "Выйти"
                icon: "logout"
                style: "outlined"
                onClicked: Auth.signOut()
            }
            Button {
                visible: !page.signedIn
                Layout.alignment: Qt.AlignTop
                text: "Войти"
                icon: "login"
                onClicked: page.router ? page.router.reset("account") : Auth.startLogin()
            }
        }

        SettingsBanner {
            kind: "error"
            shown: page.signedIn && !Auth.premium
            title: "Для воспроизведения нужен Premium"
            text: "Spotify даёт слушать в сторонних приложениях только с Premium. Без него работают библиотека, поиск и управление другими устройствами."
            actionText: "Проверить снова"
            actionIcon: "refresh"
            onAction: Auth.refreshProfile()
        }
        SettingsBanner {
            kind: "info"
            shown: page.signedIn && Auth.premium && Auth.playbackState === "none"
            title: "Воспроизведение на этом компьютере не разрешено"
            text: "Spotify выдаёт ключ для звука отдельным разрешением — откроется ещё одно окно браузера."
            actionText: "Разрешить"
            actionIcon: "open_in_new"
            onAction: Auth.authorizePlayback()
        }

        SettingRow {
            title: "Доступ к библиотеке"
            description: page.signedIn ? "Плейлисты, любимые треки, поиск и управление устройствами"
                         : Auth.state === "awaitingBrowser" ? "Подтвердите вход в браузере"
                         : Auth.state === "connecting" || Auth.state === "checking" ? "Входим…"
                         : Auth.state === "error" ? (Auth.errorText || "Вход не удался")
                         : "Вход через браузер на сайте Spotify"
            Row {
                StatusChip {
                    visible: page.signedIn
                    kind: "ok"
                    text: "Подключено"
                }
                Button {
                    visible: !page.signedIn
                    text: Auth.state === "error" ? "Повторить" : "Войти"
                    icon: "open_in_new"
                    style: "filled"
                    size: "xs"
                    onClicked: Auth.state === "error" ? Auth.retry() : Auth.startLogin()
                }
            }
        }

        SettingRow {
            id: playbackRow
            readonly property string st: Auth.playbackState
            enabled: page.signedIn
            opacity: enabled ? 1 : 0.5
            title: "Воспроизведение на этом компьютере"
            description: !page.signedIn ? "Сначала войдите в аккаунт"
                         : st === "ready" ? "Звук идёт через этот компьютер; он виден в Spotify Connect"
                         : st === "authorizing" ? "Подтвердите разрешение в браузере"
                         : st === "connecting" ? "Подключаемся к Spotify…"
                         : st === "error" ? (Auth.playbackError || "Не удалось подключить воспроизведение")
                         : st === "premiumRequired" || !Auth.premium ? "Нужен Spotify Premium"
                         : "Отдельное разрешение Spotify; нужен Premium"
            Row {
                spacing: 8
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "ready"
                    kind: "ok"
                    text: "Подключено"
                }
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.signedIn && (playbackRow.st === "premiumRequired" || (!Auth.premium && playbackRow.st === "none"))
                    kind: "warn"
                    text: "Нужен Premium"
                }
                LoadingIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "authorizing" || playbackRow.st === "connecting"
                    size: 28
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "ready"
                    text: "Отключить"
                    style: "text"
                    size: "xs"
                    onClicked: Auth.disablePlayback()
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: playbackRow.st === "authorizing"
                    text: "Отмена"
                    style: "text"
                    size: "xs"
                    onClicked: Auth.cancelLogin()
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Auth.premium && (playbackRow.st === "none" || playbackRow.st === "error")
                    text: playbackRow.st === "error" ? "Повторить" : "Разрешить"
                    icon: "open_in_new"
                    size: "xs"
                    onClicked: Auth.authorizePlayback()
                }
            }
        }

        SettingRow {
            id: personalRow
            property bool editing: false
            enabled: page.signedIn
            opacity: enabled ? 1 : 0.5
            title: "Личное приложение Spotify"
            description: Auth.personalState === "ready" ? "Client ID " + Auth.personalClientId + " — запросы идут через ваше приложение"
                         : Auth.personalState === "authorizing" ? "Подтвердите доступ в браузере"
                         : Auth.personalState === "error" ? "Не удалось подключить личное приложение"
                         : "Необязательно: свой Client ID с developer.spotify.com снимает общие лимиты запросов"
            Row {
                spacing: 8
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Auth.personalState === "ready"
                    kind: "ok"
                    text: "Настроено"
                }
                LoadingIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Auth.personalState === "authorizing"
                    size: 28
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !personalRow.editing
                    text: Auth.personalState === "ready" ? "Изменить" : "Настроить"
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
                    placeholderText: "32 символа из панели разработчика Spotify"
                    leadingIcon: "key"
                    supportingText: "Redirect URI приложения: http://127.0.0.1:8989/login"
                    onAccepted: saveClientId.clicked()
                }
                Row {
                    spacing: 8
                    Button {
                        id: saveClientId
                        text: "Сохранить"
                        size: "xs"
                        enabled: clientIdField.text.trim() !== ""
                        onClicked: {
                            Auth.setPersonalClientId(clientIdField.text.trim())
                            personalRow.editing = false
                        }
                    }
                    Button {
                        visible: Auth.personalClientId !== ""
                        text: "Удалить"
                        style: "text"
                        size: "xs"
                        onClicked: {
                            Auth.setPersonalClientId("")
                            personalRow.editing = false
                        }
                    }
                    Button {
                        text: "Отмена"
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
                  ? "Разрешения хранятся в Диспетчере учётных данных Windows. «Выйти» удаляет все три; кэш остаётся."
                  : "Хранилище секретов недоступно: разрешения живут до закрытия приложения. «Выйти» удаляет все три; кэш остаётся."
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }

    // ================= Воспроизведение =================
    SettingsCard {
        id: playbackCard
        title: "Воспроизведение"
        icon: "graphic_eq"

        SettingsBanner {
            kind: "info"
            icon: "restart_alt"
            shown: Settings.engineRestartPending === true
            busy: Auth.playbackState === "connecting"
            title: "Нужен перезапуск звука"
            text: "Новые параметры начнут работать после перезапуска; трек продолжится с того же места."
            actionText: "Применить"
            onAction: Settings.applyEngineSettings()
        }

        SettingRow {
            title: "Качество звука"
            description: (page.bitrates.find(b => b.value === Settings.bitrate) ?? page.bitrates[1]).hint
            ButtonGroup {
                model: page.bitrates.map(b => b.text + " кбит/с")
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: page.bitrates.findIndex(b => b.value === Settings.bitrate)
                onActivated: i => Settings.bitrate = page.bitrates[i].value
            }
        }
        SettingRow {
            title: "Нормализация громкости"
            description: "Треки звучат одинаково громко"
            Switch { checked: Settings.normalisation; onToggled: c => Settings.normalisation = c }
        }
        SettingRow {
            title: "Без пауз между треками"
            description: "Следующий трек начинается без тишины — для концертных альбомов и миксов"
            Switch { checked: Settings.gapless; onToggled: c => Settings.gapless = c }
        }
        SettingRow {
            title: "Автовоспроизведение"
            description: "Когда альбом или плейлист закончится, играет похожая музыка"
            Switch { checked: Settings.autoplay; onToggled: c => Settings.autoplay = c }
        }
        SettingRow {
            title: "Плавный переход между треками"
            enabled: Settings.gapless
            opacity: enabled ? 1 : 0.5
            description: !Settings.gapless ? "Работает вместе с «Без пауз между треками»"
                : Settings.crossfade > 0 ? "Конец трека затихает, пока нарастает следующий"
                : "Выключено: треки идут встык"
            Slider {
                width: 220
                from: 0
                to: 12
                stepSize: 1
                value: Settings.crossfade
                valueText: v => Math.round(v) === 0 ? "Выкл." : Math.round(v) + " с"
                onMoved: v => Settings.crossfade = Math.round(v)
            }
        }
        SettingRow {
            title: "Скорость воспроизведения"
            description: "Высота голоса не меняется. Действует на этом компьютере"
            Slider {
                width: 220
                from: 0.5
                to: 2
                stepSize: 0.05
                value: Settings.playbackSpeed
                valueText: v => (Math.round(v * 100) / 100).toString().replace(".", ",") + "×"
                onMoved: v => Settings.playbackSpeed = Math.round(v * 20) / 20
            }
        }
        SettingRow {
            title: "Устройство вывода"
            description: "Куда идёт звук этого компьютера"
            MenuField {
                width: page.compact ? 220 : 280
                leadingIcon: "speaker"
                model: [{ id: "", text: "Как в системе" }].concat((Settings.audioDevices ?? []).map(d => ({ id: d, text: d })))
                currentValue: Settings.audioDevice
                onActivated: v => Settings.audioDevice = v
            }
        }
        SettingRow {
            title: "Громкость"
            enabled: !Player.remote
            opacity: enabled ? 1 : 0.5
            description: Player.remote ? "Сейчас играет другое устройство — его громкость в мини-плеере" : ""
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
            title: "Имя устройства"
            description: "Так этот компьютер виден в Spotify на телефоне и других устройствах"
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
                    Label { Layout.fillWidth: true; text: "Устройства аккаунта"; type: "bodyLarge" }
                    Label {
                        Layout.fillWidth: true
                        text: !page.signedIn ? "Войдите, чтобы видеть устройства"
                              : Devices.errorText !== "" ? Devices.errorText
                              : "Из Spotify и из локальной сети. «Играть там» переносит воспроизведение"
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
                text: "Других устройств не видно. Откройте Spotify на телефоне или колонке и нажмите «Обновить»."
                type: "bodyMedium"
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }

        Label {
            Layout.fillWidth: true
            text: "Google Cast и Chromecast не поддерживаются."
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }

    // ================= Сеть =================
    SettingsCard {
        id: networkCard
        title: "Сеть"
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
            title: "Прокси"
            description: proxy.mode === "off" ? "Напрямую, без прокси"
                         : proxy.mode === "system" ? "Как в настройках Windows"
                         : proxy.mode === "http" ? "HTTP-прокси (CONNECT)" : "SOCKS5-прокси"
            ButtonGroup {
                model: ["Выкл", "Системный", "HTTP", "SOCKS5"]
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
                    label: "Хост"
                    placeholderText: "proxy.example.com"
                    text: Settings.proxyHost
                    onEdited: proxy.host = text
                }
                TextField {
                    id: portField
                    Layout.fillWidth: true
                    label: "Порт"
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
                    label: "Логин"
                    placeholderText: "необязательно"
                    text: Settings.proxyUsername
                    onEdited: proxy.username = text
                }
                TextField {
                    id: passField
                    Layout.fillWidth: true
                    label: "Пароль"
                    placeholderText: Settings.proxyUsername !== "" ? "пусто — без изменений" : "необязательно"
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
                text: "Применено"
            }
            LoadingIndicator { visible: Settings.proxyState === "applying"; size: 28 }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: Settings.proxyState === "applying" ? "Проверяем соединение через прокси…"
                      : Settings.proxyState === "error" ? (Settings.proxyError || "Прокси не отвечает")
                      : ""
                type: "bodyMedium"
                color: Settings.proxyState === "error" ? Theme.error : Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
            Item { Layout.fillWidth: true; visible: Settings.proxyState !== "applying" && Settings.proxyState !== "error" }
            Button {
                visible: proxy.dirty
                text: "Отменить"
                style: "text"
                onClicked: proxy.reset()
            }
            Button {
                visible: proxy.dirty
                enabled: proxy.valid && Settings.proxyState !== "applying"
                text: "Применить"
                icon: "check"
                onClicked: proxy.apply()
            }
        }

        Label {
            Layout.fillWidth: true
            text: "Пароль прокси хранится в Диспетчере учётных данных. Поиск устройств в локальной сети идёт мимо прокси."
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }

    // ================= Хранилище =================
    SettingsCard {
        id: storageCard
        title: "Хранилище"
        icon: "database"

        SettingRow {
            title: "Кэш аудио"
            description: "Прослушанные треки сохраняются на диск и в следующий раз не скачиваются"
            Switch { checked: Settings.audioCache; onToggled: c => Settings.audioCache = c }
        }
        SettingRow {
            title: "Размер кэша"
            enabled: Settings.audioCache
            opacity: enabled ? 1 : 0.5
            description: "Старые треки удаляются, когда кэш заполнен"
            Slider {
                width: 220
                from: 256
                to: 10240
                stepSize: 256
                value: Settings.audioCacheMb
                valueText: v => v >= 1024 ? (v / 1024).toFixed(v % 1024 ? 1 : 0).replace(".", ",") + " ГБ" : Math.round(v) + " МБ"
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
                text: "Очистить кэш"
                icon: "delete_sweep"
                style: "outlined"
                onClicked: {
                    Settings.clearCache()
                    // занятые файлы (звук играющего трека) остаются — об этом не сообщаем, объём обновит мост
                    const w = page.Window.window
                    if (w && typeof w.notify === "function")
                        w.notify("Кэш очищен")
                }
            }
            Button {
                text: "Открыть папку"
                icon: "folder_open"
                style: "text"
                onClicked: Settings.openCacheFolder()
            }
        }
        Label {
            Layout.fillWidth: true
            text: "Очистка не выходит из аккаунта и не трогает настройки."
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }

    // ================= Внешний вид =================
    SettingsCard {
        id: appearanceCard
        title: "Внешний вид"
        icon: "palette"

        SettingRow {
            title: "Тема"
            ButtonGroup {
                model: [{ text: "Системная", icon: "contrast" }, { text: "Светлая", icon: "light_mode" }, { text: "Тёмная", icon: "dark_mode" }]
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: ["system", "light", "dark"].indexOf(Settings.themeMode)
                onActivated: i => Settings.themeMode = ["system", "light", "dark"][i]
            }
        }

        SettingRow {
            title: "Цвет из обложки"
            description: "Приложение перекрашивается под обложку играющего трека"
            Switch { checked: Settings.accentFromCover; onToggled: c => Settings.accentFromCover = c }
        }

        SettingRow {
            title: "Акцентный цвет"
            description: Settings.accentFromCover ? "Когда ничего не играет" : "Основной цвет приложения"
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
            Label { text: "Цветовая схема"; type: "bodyLarge" }
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
            Label { text: "Смена цветов и фона"; type: "bodyLarge" }
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
            Label { text: "Фон из обложки"; type: "bodyLarge" }
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
            title: "Анимации"
            description: Settings.animations === "reduced" ? "Без движения и морфов: только короткие затухания"
                         : Settings.animations === "full" ? "Все переходы, волны и морфы"
                         : Settings.systemReducedMotion === true ? "Как в Windows: сейчас эффекты анимации выключены"
                         : "Как в Windows: «Эффекты анимации»"
            ButtonGroup {
                model: ["Как в системе", "Полные", "Минимум"]
                autoSelect: false
                size: page.compact ? "xs" : "s"
                currentIndex: ["system", "full", "reduced"].indexOf(Settings.animations)
                onActivated: i => Settings.animations = ["system", "full", "reduced"][i]
            }
        }
        SettingRow {
            title: "Размытие фона плеера"
            enabled: Settings.backdropMode !== "palette"
            opacity: enabled ? 1 : 0.5
            description: Settings.backdropMode === "palette" ? "Градиент от обложки не зависит"
                : Math.round(Settings.nowPlayingBlur * 100) + " % · 0 — чёткая обложка, 100 — только цвет"
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
            title: "Плавание размытия"
            description: Settings.nowPlayingDrift > 0
                ? "Цвета фона медленно переливаются, пока играет музыка"
                : "Выключено — размытие неподвижно"
            Slider {
                width: 220
                from: 0
                to: 1
                stepSize: 0.05
                value: Settings.nowPlayingDrift
                valueText: v => v > 0 ? Math.round(v * 100) + " %" : "выкл"
                onMoved: v => Settings.nowPlayingDrift = Math.round(v * 20) / 20
            }
        }
        SettingRow {
            title: "Экономия в фоне"
            description: "Пока окно не в фокусе, декоративные анимации (волна прогресса, фигуры, перелив фона) стоят — меньше нагрузка на процессор. Текст песни продолжает идти"
            Switch { checked: Settings.calmWhenInactive; onToggled: c => Settings.calmWhenInactive = c }
        }
        SettingRow {
            title: "Рамка обложки вращается"
            description: "Пока играет музыка, фигурная рамка обложки медленно крутится; сама картинка стоит"
            Switch { checked: Settings.coverSpin; onToggled: c => Settings.coverSpin = c }
        }
        SettingRow {
            title: "Обложка дышит в такт"
            description: "В полноэкранном плеере обложка слегка пульсирует по громкости музыки"
            Switch { checked: Settings.coverPulse; onToggled: c => Settings.coverPulse = c }
        }
        SettingRow {
            title: "Атмосферный фон"
            description: "Размытая обложка играющего трека за всем окном — слабым цветным свечением"
            Switch { checked: Settings.ambientBackground; onToggled: c => Settings.ambientBackground = c }
        }
    }

    SettingsCard {
        title: "Окно"
        icon: "web_asset"

        SettingRow {
            title: "Компактная боковая панель"
            description: "Только иконки. На узком окне включается сама"
            Switch { checked: Settings.sidebarCollapsed; onToggled: c => Settings.sidebarCollapsed = c }
        }
        SettingRow {
            title: "Скрывать в трей при закрытии"
            description: "Закрытое окно прячется в значок в трее, музыка играет дальше. Выход — из меню значка или Ctrl+Q"
            Switch { checked: Settings.closeToTray; onToggled: c => Settings.closeToTray = c }
        }
        SettingRow {
            title: "Кнопки окна"
            description: "Свернуть, развернуть и закрыть — для окружений без тайлинга"
            Switch { checked: Settings.windowButtons; onToggled: c => Settings.windowButtons = c }
        }
        SettingRow {
            title: "Шаг прокрутки колесом"
            description: Settings.wheelStep + " px за щелчок; при быстрой прокрутке шаг растёт до ×2"
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
        title: "О программе"
        icon: "info"

        SettingRow {
            title: "Materialfy 0.1"
            description: "Неофициальный клиент Spotify в стиле Material 3 Expressive. Для воспроизведения нужен Spotify Premium; без lossless, кроссфейда и офлайн-загрузок."
        }
        Label {
            Layout.fillWidth: true
            text: "Основан на spotifast (crmne, MIT) и yamusic-md3 (yaskorinov, MIT); не связан со Spotify AB. Воспроизведение — librespot (MIT). Шрифты: Google Sans (OFL), Material Symbols (Apache 2.0)."
            type: "bodySmall"
            color: Theme.fgSurfaceVariant
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }
}
