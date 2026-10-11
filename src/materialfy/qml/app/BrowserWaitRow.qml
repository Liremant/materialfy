import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core

// «Браузер не открылся?» — открыть ссылку ещё раз или скопировать её (адрес ответа — чип у «Отмена» на странице).
ColumnLayout {
    id: root

    signal copied()

    spacing: 8

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: grid.implicitHeight + 32
        radius: Theme.shape.extraLarge
        color: Theme.surfaceContainerHigh

        GridLayout {
            id: grid
            x: 20
            y: 16
            width: parent.width - 40
            columns: width >= 460 ? 2 : 1
            columnSpacing: 16
            rowSpacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: "Браузер не открылся?"
                    type: "titleSmall"
                }
                Label {
                    Layout.fillWidth: true
                    text: "Откройте страницу ещё раз или скопируйте ссылку в нужный браузер"
                    type: "bodySmall"
                    color: Theme.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
            RowLayout {
                spacing: 8
                Button {
                    text: "Открыть снова"
                    icon: "open_in_new"
                    style: "tonal"
                    onClicked: Auth.reopenBrowser()
                }
                Button {
                    text: copiedHint.running ? "Скопировано" : "Ссылка"
                    icon: copiedHint.running ? "check" : "content_copy"
                    style: "outlined"
                    onClicked: {
                        Auth.copyAuthUrl()
                        copiedHint.restart()
                        root.copied()
                    }
                    Timer { id: copiedHint; interval: 1500 }
                }
            }
        }
    }
}
