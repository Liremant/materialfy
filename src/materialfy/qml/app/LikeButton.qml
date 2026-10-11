import QtQuick
import Md3
import Materialfy.Core

// «Мне нравится» для трека (dict из модели или Player.track). Состояние — из Library, клик — переключить.
IconButton {
    id: root

    property var track: ({})
    readonly property string _id: track && track.trackId ? String(track.trackId) : ""
    readonly property bool liked: Library.likesRevision >= 0 && _id !== "" && Library.isLiked(_id)

    icon: "favorite"
    checkable: true
    autoToggle: false
    checked: liked
    enabled: _id !== ""
    onClicked: Library.toggleLike(track)

    // Короткий «удар сердца» при лайке
    onLikedChanged: if (liked && _ready) beat.restart()
    property bool _ready: false
    Component.onCompleted: _ready = true
    SequentialAnimation {
        id: beat
        NumberAnimation { target: root; property: "scale"; to: 1.22; duration: 110; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
    }
}
