import QtQuick
import Md3
import Materialfy.Core
import ".."

TrackListPage {
    title: "Любимые треки"
    overline: "КОЛЛЕКЦИЯ"
    heroIcon: "favorite"
    heroShape: "clover4"
    subtitle: Auth.state !== "signedIn" ? "Треки, которые вы отметили"
            : Library.liked.loading && Library.liked.count === 0 ? "Загружаем…"
            : Library.liked.count + " " + plural(Library.liked.count, "трек", "трека", "треков")
    model: Auth.state === "signedIn" ? Library.liked : null
    emptyIcon: "favorite"
    emptyTitle: "Пока пусто"
    emptyText: "Отмечайте треки сердечком — они появятся здесь"

    function plural(n, one, few, many) {
        const m10 = n % 10, m100 = n % 100
        if (m10 === 1 && m100 !== 11) return one
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few
        return many
    }

    // Не вошли — приглашение войти
    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 420)
        visible: Auth.state !== "signedIn"
        icon: "favorite"
        shape: "clover4"
        title: "Войдите, чтобы увидеть любимые треки"
        text: "Сохранённые треки подтянутся из вашего аккаунта Spotify"
        actionText: "Войти"
        actionIcon: "login"
        onAction: parent.router.reset("account")
    }
}
