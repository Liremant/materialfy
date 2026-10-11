import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Md3
import Materialfy.Core

// Меню устройств Spotify Connect над кнопкой мини-плеера: «Слушать на» + обновить, текущее устройство,
// «Другие устройства», подпись про Cast. Карточка — отдельное всплывающее окно, как у Md3/Menu.
// Содержимое (Content) общее с листом снизу (DeviceSheet). Список запрашивается при открытии и по кнопке.
Item {
    id: root

    readonly property bool opened: popup.visible
    property real closedAt: 0
    readonly property int _pad: 12          // поле под тень карточки внутри прозрачного окна

    function openFor(item) {
        const g = item.mapToGlobal(0, 0)
        popup.anchorRect = Qt.rect(g.x, g.y, item.width, item.height)
        popup.area = _screenArea()
        Devices.refresh()
        popup.open()
    }
    function close() { popup.close() }

    function _screenArea() {
        const w = root.Window.window
        const s = w ? w.screen : null
        if (!s || !(s.width > 0)) {
            const o = root.mapToGlobal(0, 0)
            return Qt.rect(o.x - 400, o.y - 800, 1200, 1600)
        }
        let right = s.virtualX + s.width
        let bottom = s.virtualY + s.height
        if (s.desktopAvailableWidth > s.virtualX)
            right = Math.min(right, s.desktopAvailableWidth)
        if (s.desktopAvailableHeight > s.virtualY)
            bottom = Math.min(bottom, s.desktopAvailableHeight)
        return Qt.rect(s.virtualX, s.virtualY, right - s.virtualX, bottom - s.virtualY)
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive)
                root.close()
        }
    }

    // ---- Содержимое: меню и лист ----
    component Content: ColumnLayout {
        id: content

        property bool touch: false          // лист: действия видны кнопками, наведения нет
        signal closeRequested()

        readonly property bool signedIn: Auth.state === "signedIn"
        readonly property bool free: signedIn && Auth.premium !== true
        readonly property var active: Devices.active ?? {}
        readonly property bool hasActive: (active.id ?? "") !== ""
        readonly property string movingTo: Devices.transferringTo ?? ""

        // Этот компьютер: из списка устройств, а если его там нет — по имени из моста
        readonly property var here: {
            const m = Devices.devices
            void Devices.active
            const i = m && m.count > 0 ? m.find("isThisComputer", true) : -1
            if (i >= 0)
                return m.get(i)
            return { id: Devices.thisDeviceId ?? "", name: Devices.thisDeviceName || "Этот компьютер", type: "computer",
                     isActive: false, isThisComputer: true, isRestricted: false, supportsVolume: true, volume: -1, source: "api" }
        }
        readonly property bool hereActive: hasActive && active.isThisComputer === true
        readonly property bool needsSetup: !free && Auth.playbackState !== "ready" && Player.localState !== "ready"
        readonly property bool showHere: signedIn && !hereActive
        readonly property int others: {
            const m = Devices.devices
            void Devices.active
            if (!m)
                return 0
            let n = 0
            for (let i = 0; i < m.count; ++i) {
                const d = m.get(i)
                if (!d.isActive && !d.isThisComputer)
                    ++n
            }
            return n
        }

        spacing: 0

        // Шапка
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            Layout.leftMargin: 12
            Layout.rightMargin: 4
            spacing: 8
            Label {
                Layout.fillWidth: true
                text: "Слушать на"
                type: "titleSmall"
            }
            Item {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                LoadingIndicator {
                    running: !Theme.calm
                    anchors.centerIn: parent
                    visible: Devices.loading === true
                    size: 28
                }
                IconButton {
                    anchors.centerIn: parent
                    visible: Devices.loading !== true
                    icon: "refresh"
                    enabled: content.signedIn
                    onClicked: Devices.refresh()
                }
            }
        }

        PremiumNotice {
            visible: content.free
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 6
            compact: true
        }

        DeviceCurrent {
            visible: content.hasActive
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 6
            device: content.active
        }

        // Нигде не играет и выбрать не из чего
        ColumnLayout {
            visible: !content.hasActive && content.others === 0
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            spacing: 8
            MorphShape {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                shape: "cookie9"
                color: Theme.secondaryContainer
                Icon { anchors.centerIn: parent; name: "devices_off"; size: 30; color: Theme.fgSecondaryContainer }
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: content.signedIn ? "Нет активных устройств" : "Войдите в аккаунт"
                type: "titleSmall"
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                horizontalAlignment: Text.AlignHCenter
                text: content.signedIn
                      ? "Откройте Spotify на телефоне или колонке, и они появятся здесь. Или включите музыку на этом компьютере."
                      : "Устройства Spotify Connect появятся здесь после входа."
                type: "bodySmall"
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }

        Label {
            visible: content.showHere || content.others > 0
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.topMargin: 6
            Layout.bottomMargin: 4
            text: "Другие устройства"
            type: "labelMedium"
            color: Theme.fgSurfaceVariant
        }

        // Этот компьютер: «Слушать здесь» или «Настроить воспроизведение здесь»
        DeviceRow {
            visible: content.showHere
            Layout.fillWidth: true
            device: content.here
            touch: content.touch
            setup: content.needsSetup
            disabled: content.free
            busy: content.movingTo !== "" && content.movingTo === (content.here.id ?? "")
            onActivated: {
                if (content.needsSetup) {
                    content.closeRequested()
                    Catalog.openRequested("playback", {})
                } else {
                    Devices.transferHere()
                }
            }
        }

        Repeater {
            model: Devices.devices
            DeviceRow {
                id: row
                required property var model
                readonly property var dev: ({
                    id: model.id, name: model.name, type: model.type, isActive: model.isActive,
                    isThisComputer: model.isThisComputer, isRestricted: model.isRestricted,
                    supportsVolume: model.supportsVolume, volume: model.volume, source: model.source
                })
                visible: !dev.isActive && !dev.isThisComputer
                Layout.fillWidth: true
                device: dev
                touch: content.touch
                disabled: content.free
                busy: content.movingTo !== "" && content.movingTo === dev.id
                onActivated: dev.source === "zeroconf" ? Devices.activateReceiver(dev.name) : Devices.transfer(dev.id)
            }
        }

        Label {
            visible: content.signedIn && (Devices.errorText ?? "") !== ""
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 4
            text: Devices.errorText ?? ""
            type: "bodySmall"
            color: Theme.error
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }

        // Подпись про Google Cast
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: 1
            color: Theme.outlineVariant
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            Layout.bottomMargin: 6
            spacing: 8
            Icon { Layout.alignment: Qt.AlignTop; name: "info"; size: 16; color: Theme.fgSurfaceVariant }
            Label {
                Layout.fillWidth: true
                text: "Колонки Google Cast появляются здесь, только когда их уже включило приложение Spotify"
                type: "bodySmall"
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }
        }
    }

    // ---- Карточка во всплывающем окне ----
    T.Popup {
        id: popup

        property rect anchorRect: Qt.rect(0, 0, 0, 0)
        property rect area: Qt.rect(0, 0, 0, 0)
        readonly property real cardW: 368
        readonly property real cardH: Math.min(body.implicitHeight + 16, Math.max(200, area.height - anchorRect.height - 48))
        // над кнопкой, правым краем к её правому краю; сверху не влезает — под кнопкой
        readonly property bool below: anchorRect.y - cardH - 8 < area.y + 8
        readonly property real gx: Math.max(area.x + 8, Math.min(anchorRect.x + anchorRect.width - cardW, area.x + area.width - cardW - 8)) - root._pad
        readonly property real gy: (below ? anchorRect.y + anchorRect.height + 8 : anchorRect.y - cardH - 8) - root._pad

        popupType: T.Popup.Window
        onClosed: root.closedAt = Date.now()
        modal: false
        dim: false
        focus: true
        padding: root._pad
        background: null
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
        x: root.mapFromGlobal(gx, gy).x
        y: root.mapFromGlobal(gx, gy).y
        contentWidth: cardW
        contentHeight: cardH
        implicitWidth: contentWidth + leftPadding + rightPadding
        implicitHeight: contentHeight + topPadding + bottomPadding
        transformOrigin: below ? Item.TopRight : Item.BottomRight

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motion.effectsFast }
                NumberAnimation {
                    property: "scale"; from: Theme.reducedMotion === true ? 1 : 0.94; to: 1
                    duration: Theme.motion.spatialFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion.emphasizedDecelerate
                }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motion.effectsFast }
        }

        contentItem: Rectangle {
            id: card
            radius: Theme.shape.large
            color: Qt.alpha(Theme.surfaceContainer, 0.96)
            border.width: 1
            border.color: Qt.alpha(Theme.outlineVariant, 0.5)
            Keys.onEscapePressed: root.close()

            Elevation { target: card; level: 2 }

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 8
                clip: contentHeight > height
                contentWidth: width
                contentHeight: body.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Content {
                    id: body
                    width: flick.width
                    onCloseRequested: root.close()
                }
            }
        }
    }
}
