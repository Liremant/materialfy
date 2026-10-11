import QtQuick

// Текст по шкале MD3: Label { type: "titleLarge" }. Шрифт — вариативный Google Sans:
// вес и оптический размер задаются осями, а не только font.weight.
Text {
    id: root

    property string type: "bodyMedium"
    readonly property var _t: Theme.type[type] ?? Theme.type.bodyMedium
    property real weight: _t.weight      // 400..700, ось wght

    color: Theme.fgSurface
    font.family: Theme.fontFamily
    font.pixelSize: _t.size
    // С вариативным шрифтом вес — только осью: font.weight заставляет Qt брать ближайший
    // статический файл семейства (600 → Medium), и промежуточные веса пропадают.
    font.weight: Theme.variableFont ? Font.Normal : Math.round(weight)
    font.letterSpacing: _t.tracking
    font.variableAxes: Theme.fontAxes(_t.size, weight)
    lineHeight: _t.line
    lineHeightMode: Text.FixedHeight
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
