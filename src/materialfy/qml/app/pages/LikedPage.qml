import QtQuick
import Md3
import Materialfy.Core
import ".."

TrackListPage {
    title: I18n.t("Liked Songs")
    overline: I18n.t("COLLECTION")
    heroIcon: "favorite"
    heroShape: "clover4"
    subtitle: Auth.state !== "signedIn" ? I18n.t("Tracks you’ve liked")
            : Library.liked.loading && Library.liked.count === 0 ? I18n.t("Loading…")
            : I18n.n(Library.liked.count, "{0} track", "{0} tracks")
    model: Auth.state === "signedIn" ? Library.liked : null
    emptyIcon: "favorite"
    emptyTitle: I18n.t("Nothing here yet")
    emptyText: I18n.t("Tap the heart on tracks to see them here")

    // Не вошли — приглашение войти
    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 420)
        visible: Auth.state !== "signedIn"
        icon: "favorite"
        shape: "clover4"
        title: I18n.t("Sign in to see your Liked Songs")
        text: I18n.t("Your saved tracks will sync from your Spotify account")
        actionText: I18n.t("Sign in")
        actionIcon: "login"
        onAction: parent.router.reset("account")
    }
}
