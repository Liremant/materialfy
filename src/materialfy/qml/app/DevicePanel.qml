import QtQuick
import Md3
import Materialfy.Core

// Вкладка «Устройства» правой панели (как боковая панель Connect в Spotify для компьютера):
// список DeviceList во всю высоту панели. Список обновляется, когда вкладка становится видна.
SmoothFlickable {
    id: root

    property bool shown: false

    onShownChanged: if (shown) Devices.refresh()
    Component.onCompleted: if (shown) Devices.refresh()

    wheelStep: Settings.wheelStep
    contentWidth: width
    contentHeight: body.implicitHeight + 16
    interactive: contentHeight > height

    DeviceList {
        id: body
        width: root.width
        onCloseRequested: Settings.rightPanelOpen = false
    }
}
