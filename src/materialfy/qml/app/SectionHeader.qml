import QtQuick
import QtQuick.Layouts
import Md3

// Заголовок секции страницы с необязательной кнопкой справа («Все», «Свернуть»).
RowLayout {
    id: root

    property string text
    property string actionText
    signal action()

    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 12

    Label {
        Layout.fillWidth: true
        text: root.text
        type: "headlineSmall"
        weight: 600
    }
    Button {
        visible: root.actionText !== ""
        text: root.actionText
        style: "text"
        onClicked: root.action()
    }
}
