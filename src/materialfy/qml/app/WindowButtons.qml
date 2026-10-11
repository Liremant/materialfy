import QtQuick
import Md3

// Кнопки окна MD3: свернуть, развернуть / свернуть в окно, закрыть. Рамку окна рисует приложение, поэтому
// кнопки есть на всех ОС и во всех раскладках (в мини-плеере — свои, в пилюле MiniMode).
// Окно на весь экран (F11) кнопка «свернуть в окно» возвращает в обычное.
Row {
    id: root

    required property Window window
    readonly property bool expanded: !!window && (window.visibility === Window.Maximized || window.visibility === Window.FullScreen)

    // и для двойного клика по пустому месту верхней панели
    function toggleMaximized() {
        window.visibility = expanded ? Window.Windowed : Window.Maximized
    }

    spacing: 4

    component WindowButton: IconButton {
        id: button
        property string label
        size: "xs"
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: button.clicked()
    }

    WindowButton {
        icon: "remove"
        label: I18n.t("Minimize")
        onClicked: root.window.showMinimized()
    }
    WindowButton {
        icon: root.expanded ? "collapse_content" : "expand_content"
        label: root.expanded ? I18n.t("Restore down") : I18n.t("Maximize")
        onClicked: root.toggleMaximized()
    }
    WindowButton {
        icon: "close"
        label: I18n.t("Close")
        // наведение подсвечивает «закрыть» цветом ошибки — как красная кнопка системной рамки, но в тонах темы
        iconColor: hovered ? Theme.error : Theme.fgSurfaceVariant
        onClicked: root.window.close()
    }
}
