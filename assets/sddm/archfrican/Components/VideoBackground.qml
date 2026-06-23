// Opt-in animated video background (astronaut/qylock style). Imports QtMultimedia, so it's loaded ONLY
// via Background.qml's Loader — if qt6-multimedia isn't installed this file fails to load and the
// Loader falls back to the static/aurora background (nothing breaks). Set backgroundMode=video +
// backgroundVideo=<path> in theme.conf and `pacman -S qt6-multimedia` to enable. Silent (no audio out).
import QtQuick 2.15
import QtMultimedia

Item {
    id: video
    property alias source: player.source

    MediaPlayer {
        id: player
        loops: MediaPlayer.Infinite
        videoOutput: vout
    }
    VideoOutput {
        id: vout
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }
    Component.onCompleted: if (player.source != "") player.play()
}
