import QtQuick
import QtQuick.Layouts
import Md3
import Materialfy.Core
import ".."

// «Список треков» станции: те же 50 треков, что будут играть (Radio.tracks, контекст radio).
// «Пересобрать» — новый запрос станции, «Сохранить как плейлист» — плейлист из этих треков.
TrackListPage {
    id: page

    property string seed

    Component.onCompleted: if (seed !== "") Radio.open(seed)

    // обложка сида — из групп орбиты, иначе первого трека
    readonly property string seedCover: {
        for (const g of (Radio.seeds ?? []))
            for (const it of (g.items ?? []))
                if (it.uri === seed && it.cover)
                    return it.cover
        const t = model && model.count > 0 ? model.get(0) : null
        return t ? (t.coverLarge || t.cover || "") : ""
    }

    title: Radio.stationTitle !== "" ? Radio.stationTitle : "Радио"
    overline: "РАДИО"
    heroImage: seedCover
    heroIcon: "radio"
    heroShape: "flower8"
    subtitle: model && model.count > 0 ? model.count + " треков · каждый запуск — новый микс"
            : Radio.loading ? "Собираем станцию…" : ""
    model: Radio.tracks
    emptyIcon: "radio"
    emptyTitle: Radio.loading ? "Собираем станцию…" : Radio.errorText !== "" ? "Станция не собралась" : "В станции нет треков"
    emptyText: Radio.errorText !== "" ? Radio.errorText
             : Radio.locked ? "Станции приходят через сессию воспроизведения: подключите воспроизведение на этом компьютере" : ""

    function notify(text) {
        const w = page.Window.window
        if (w && typeof w.notify === "function")
            w.notify(text, "", null)
    }

    headerExtra: Row {
        spacing: 4
        IconButton {
            icon: "refresh"
            size: "m"
            enabled: !Radio.loading
            onClicked: Radio.refresh()
        }
        IconButton {
            icon: "bookmark_add"
            size: "m"
            enabled: page.model !== null && page.model.count > 0
            onClicked: {
                Radio.save()
                page.notify("Сохраняем станцию как плейлист…")
            }
        }
    }
}
