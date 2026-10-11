import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// Аккаунт. До входа — «Войти через Spotify» по шагам (PKCE в браузере, ответ на 127.0.0.1:8989):
// ждём браузер → подключаемся → «Готово, {имя}» с переходом ко второму шагу (воспроизведение здесь).
// После входа — сводка аккаунта. Смена состояния — сквозное затухание.
Page {
    id: page

    property string st: Auth.state
    readonly property var account: Auth.account ?? {}
    readonly property bool premium: Auth.premium === true
    readonly property string displayName: account.displayName ?? ""
    readonly property bool _instant: Theme.reducedMotion === true

    // «Готово, {имя}» — только если вход прошёл через браузер, пока страница открыта (а не восстановилась сессия)
    property bool _sawBrowser: st === "awaitingBrowser"
    onStChanged: {
        if (st === "awaitingBrowser")
            _sawBrowser = true
        else if (st === "signedOut")
            _sawBrowser = false
    }
    readonly property string view: st === "signedIn" ? (_sawBrowser ? "welcome" : "account")
                                 : st === "checking" ? "checking"
                                 : st === "awaitingBrowser" ? "browser"
                                 : st === "connecting" ? "connecting"
                                 : st === "error" ? "error" : "signedOut"
    property string shown: view
    onViewChanged: {
        if (_instant || !visible) {
            swap.stop()
            shown = view
            body.opacity = 1
            body.scale = 1
            shift.y = 0
        } else {
            swap.restart()
        }
    }
    readonly property bool login: shown !== "account"
    // рейл / низкое окно: меньше арт, короткие тексты, шаги без меток
    readonly property bool compact: width < 860 || height < 700

    title: login ? "Вход" : "Аккаунт"
    showHeader: !login

    function _go(name, props) {
        if (page.router)
            page.router.push(name, props)
    }
    function _proxy() { _go("settings", { section: "network" }) }

    // Пояснения к ошибкам входа (тексты ошибок — из Auth.errorText)
    function _errorHint(text) {
        if (text.indexOf("отменён") >= 0)
            return "На странице Spotify нажата «Отмена». Попробуйте ещё раз — разрешение можно отозвать в настройках аккаунта Spotify."
        if (text.indexOf("занят") >= 0)
            return "Закройте программу, которая слушает этот порт, или перезапустите компьютер и повторите вход."
        if (text.indexOf("не отвечает") >= 0)
            return "Проверьте подключение к интернету. Если Spotify доступен только через прокси — включите его в настройках сети."
        if (text.indexOf("разным аккаунтам") >= 0)
            return "Выйдите на accounts.spotify.com из лишнего аккаунта и войдите заново."
        return ""
    }

    SequentialAnimation {
        id: swap
        NumberAnimation { target: body; property: "opacity"; to: 0; duration: Theme.motion.effectsFast; easing.type: Easing.InCubic }
        ScriptAction { script: page.shown = page.view }
        ParallelAnimation {
            NumberAnimation { target: body; property: "opacity"; to: 1; duration: Theme.motion.effectsDefault; easing.type: Easing.OutCubic }
            NumberAnimation {
                target: shift; property: "y"; from: 8; to: 0; duration: Theme.motion.spatialFast
                easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedDecelerate
            }
            NumberAnimation {
                target: body; property: "scale"; from: 0.98; to: 1; duration: Theme.motion.spatialFast
                easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedDecelerate
            }
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight

        ColumnLayout {
            id: body
            width: parent.width
            transform: Translate { id: shift }
            spacing: 0

            // ================= Вход =================
            ColumnLayout {
                visible: page.login
                Layout.fillWidth: true
                Layout.maximumWidth: page.compact ? 560 : 640
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: page.compact ? 0 : 8
                spacing: page.compact ? 10 : 12

                // Арт: фигуры (не вошли / ошибка / готово) или индикатор (ждём, подключаемся)
                Item {
                    id: art
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: page.compact ? 120 : 156
                    Layout.preferredHeight: page.compact ? 120 : 156
                    Layout.bottomMargin: page.compact ? 0 : 4
                    readonly property bool waiting: page.shown === "checking" || page.shown === "browser" || page.shown === "connecting"
                    readonly property bool failed: page.shown === "error"
                    readonly property bool done: page.shown === "welcome"

                    MorphShape {
                        visible: !art.waiting
                        anchors.centerIn: parent
                        width: art.width
                        height: art.height
                        shape: art.failed ? "flower8" : art.done ? "sunny" : "cookie12"
                        duration: page._instant ? 0 : Theme.motion.spatialSlow
                        overshoot: 1.05
                        color: art.failed ? Theme.errorContainer : Theme.primaryContainer
                        opacity: 0.35
                        rotation: art.done ? 20 : 12
                        Behavior on rotation { enabled: !page._instant; NumberAnimation { duration: Theme.motion.spatialSlow; easing.type: Easing.OutCubic } }
                    }
                    MorphShape {
                        visible: !art.waiting
                        anchors.centerIn: parent
                        width: Math.round(art.width * 120 / 156)
                        height: width
                        shape: art.failed ? "flower6" : art.done ? "sunny" : "cookie9"
                        duration: page._instant ? 0 : Theme.motion.spatialDefault
                        overshoot: 1.15
                        color: art.failed ? Theme.errorContainer : art.done ? Theme.primary : Theme.secondaryContainer
                        Icon {
                            anchors.centerIn: parent
                            name: art.failed ? "cloud_off" : art.done ? "check" : "library_music"
                            size: page.compact ? 36 : 46
                            fill: 1
                            color: art.failed ? Theme.fgErrorContainer : art.done ? Theme.fgPrimary : Theme.fgSecondaryContainer
                        }
                    }
                    LoadingIndicator {
                        visible: art.waiting
                        anchors.centerIn: parent
                        size: page.compact ? 80 : 96
                        contained: true
                        running: !Theme.calm && !page._instant
                    }
                }

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: ({
                        checking: "Подключаемся к Spotify…",
                        connecting: "Подключаемся к Spotify…",
                        browser: "Подтвердите вход в браузере",
                        error: "Не получилось войти",
                        welcome: "Готово" + (page.displayName !== "" ? ", " + page.displayName : "")
                    })[page.shown] ?? "Войдите через Spotify"
                    type: page.compact ? "headlineSmall" : "headlineMedium"
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
                Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 460
                    Layout.alignment: Qt.AlignHCenter
                    visible: text !== ""
                    horizontalAlignment: Text.AlignHCenter
                    text: ({
                        checking: "Проверяем сохранённую сессию",
                        connecting: "Проверяем аккаунт и загружаем медиатеку",
                        browser: page.compact ? "Нажмите «Принять» на accounts.spotify.com — окно вернётся само."
                                              : "Мы открыли страницу accounts.spotify.com. Нажмите там «Принять», и окно вернётся само.",
                        error: "",
                        welcome: "Медиатека, поиск и пульт для ваших устройств уже работают. Осталось решить, будет ли музыка играть на этом компьютере."
                    })[page.shown] ?? (page.compact ? "Пароль вводится только на сайте Spotify. Потом можно включить воспроизведение здесь (Premium)." : "Вход открывается в браузере. Пароль вводится только на сайте Spotify, Materialfy его не видит. "
                                       + (Qt.platform.os === "windows" ? "Ключи хранятся в диспетчере учётных данных Windows."
                                          : Qt.platform.os === "osx" ? "Ключи хранятся в связке ключей macOS."
                                          : "Ключи хранятся в связке ключей системы."))
                    type: "bodyMedium"
                    color: Theme.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 1.25
                }

                // Плашка ошибки
                Rectangle {
                    visible: page.shown === "error"
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: errRow.implicitHeight + 24
                    radius: Theme.shape.large
                    color: Theme.errorContainer
                    RowLayout {
                        id: errRow
                        x: 16
                        y: 12
                        width: parent.width - 32
                        spacing: 12
                        Icon { Layout.alignment: Qt.AlignTop; name: "error"; size: 20; color: Theme.fgErrorContainer }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                text: Auth.errorText !== "" ? Auth.errorText : "Spotify не ответил"
                                type: "titleSmall"
                                color: Theme.fgErrorContainer
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: page._errorHint(Auth.errorText)
                                type: "bodySmall"
                                color: Theme.fgErrorContainer
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                            }
                        }
                    }
                }

                LoginSteps {
                    visible: page.shown !== "checking"
                    Layout.fillWidth: true
                    Layout.topMargin: page.compact ? 6 : 12
                    compact: page.compact
                    // выделен шаг, который выполняется сейчас; до нажатия «Войти» — ни один
                    active: page.shown === "welcome" ? 2 : page.shown === "browser" || page.shown === "connecting" ? 1 : 0
                    done1: page.shown === "welcome"
                    waitingText: page.shown === "browser" ? "Ждём подтверждения…" : page.shown === "connecting" ? "Входим…" : ""
                }

                BrowserWaitRow {
                    visible: page.shown === "browser" && !page.compact
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                }

                // Действия
                RowLayout {
                    visible: page.shown !== "checking" && page.shown !== "connecting"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    spacing: 12

                    Button {
                        visible: page.shown === "signedOut"
                        text: "Войти через Spotify"
                        icon: "open_in_new"
                        size: "m"
                        onClicked: Auth.startLogin()
                    }
                    Button {
                        visible: page.shown === "error"
                        text: "Повторить"
                        icon: "refresh"
                        size: "m"
                        onClicked: Auth.retry()
                    }
                    Button {
                        visible: page.shown === "signedOut" || page.shown === "error"
                        text: "Настройки прокси"
                        icon: "lan"
                        style: "text"
                        onClicked: page._proxy()
                    }
                    // в рейле — кнопки вместо карточки «Браузер не открылся?»
                    Button {
                        visible: page.shown === "browser" && page.compact
                        text: "Открыть снова"
                        icon: "open_in_new"
                        style: "tonal"
                        onClicked: Auth.reopenBrowser()
                    }
                    Button {
                        visible: page.shown === "browser" && page.compact
                        text: "Ссылка"
                        icon: "content_copy"
                        style: "outlined"
                        onClicked: Auth.copyAuthUrl()
                    }
                    // адрес ответа — чип рядом с «Отмена»
                    Item {
                        visible: page.shown === "browser" && !page.compact
                        implicitWidth: addrRow.implicitWidth + 20
                        implicitHeight: 40
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 28
                            radius: Theme.shape.small
                            color: Theme.surfaceContainerHighest
                            Row {
                                id: addrRow
                                anchors.centerIn: parent
                                spacing: 6
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: "lock"; size: 16; color: Theme.fgSurfaceVariant }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Ответ придёт на 127.0.0.1:" + (Auth.authPort > 0 ? Auth.authPort : 8989) + " · ваш компьютер"
                                    type: "labelMedium"
                                    color: Theme.fgSurfaceVariant
                                }
                            }
                        }
                    }
                    Button {
                        visible: page.shown === "browser"
                        text: "Отмена"
                        style: "text"
                        onClicked: Auth.cancelLogin()
                    }
                    Button {
                        visible: page.shown === "welcome"
                        text: "Дальше: слушать здесь"
                        icon: "speaker"
                        size: "m"
                        onClicked: page._go("playback")
                    }
                    Button {
                        visible: page.shown === "welcome"
                        text: "Позже, только пульт"
                        style: "text"
                        onClicked: page.router ? page.router.reset("home") : null
                    }
                }

                Label {
                    visible: !page.compact && (page.shown === "signedOut" || page.shown === "error")
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 24
                    text: "Materialfy · не связан со Spotify AB"
                    type: "bodySmall"
                    color: Theme.fgSurfaceVariant
                }
            }

            // ================= Аккаунт =================
            ColumnLayout {
                visible: !page.login
                Layout.fillWidth: true
                Layout.maximumWidth: 640
                spacing: 16

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: signedInRow.implicitHeight + 48
                    radius: Theme.shape.extraLarge
                    color: Theme.surfaceContainerHigh

                    RowLayout {
                        id: signedInRow
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 20

                        Item {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 72
                            Avatar { anchors.fill: parent; size: 72; name: page.displayName }
                            MorphImage {
                                anchors.fill: parent
                                visible: (page.account.avatar ?? "") !== "" && status === Image.Ready
                                source: page.account.avatar ?? ""
                                shape: "cookie9"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0      // чипы переносятся, а не распирают карточку
                            spacing: 4
                            Label { Layout.fillWidth: true; text: page.displayName !== "" ? page.displayName : "Аккаунт Spotify"; type: "headlineSmall"; weight: 600 }
                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: page.account.email ?? ""
                                type: "bodyMedium"
                                color: Theme.fgSurfaceVariant
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 8
                                Chip {
                                    text: page.premium ? "Spotify Premium" : "Spotify Free"
                                    icon: page.premium ? "workspace_premium" : "block"
                                }
                                Chip {
                                    visible: Auth.tokenStorage === "keyring"
                                    text: Qt.platform.os === "windows" ? "Ключи в диспетчере учётных данных" : "Ключи в связке ключей"
                                    icon: "lock"
                                }
                                Chip {
                                    text: Auth.playbackState === "ready" ? "Играет на этом компьютере"
                                        : Auth.playbackState === "premiumRequired" ? "Только пульт"
                                        : "Воспроизведение здесь не настроено"
                                    icon: Auth.playbackState === "ready" ? "computer" : "cast"
                                    onClicked: page._go("playback")
                                }
                            }
                            // узкая карточка: кнопки под подписями, а не справа
                            Flow {
                                visible: signedInRow.width < 520
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                spacing: 8
                                Button { text: "Воспроизведение"; icon: "speaker"; style: "tonal"; onClicked: page._go("playback") }
                                Button { text: "Выйти"; icon: "logout"; style: "outlined"; onClicked: Auth.signOut() }
                            }
                        }
                        ColumnLayout {
                            visible: signedInRow.width >= 520
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignTop
                            spacing: 8
                            Button { Layout.fillWidth: true; text: "Воспроизведение"; icon: "speaker"; style: "tonal"; onClicked: page._go("playback") }
                            Button { Layout.fillWidth: true; text: "Выйти"; icon: "logout"; style: "outlined"; onClicked: Auth.signOut() }
                        }
                    }
                }

                PremiumNotice {
                    visible: !page.premium && page.st === "signedIn"
                    Layout.fillWidth: true
                }

                Label {
                    Layout.fillWidth: true
                    text: "Выход удаляет ключи этого компьютера из хранилища. Разрешения приложения можно отозвать на spotify.com в разделе «Приложения»."
                    type: "bodySmall"
                    color: Theme.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 1.25
                }
            }
        }
    }
}
