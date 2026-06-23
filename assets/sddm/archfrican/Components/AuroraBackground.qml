// Living "aurora" background — a few large translucent colour blobs drifting behind a heavy blur, so
// they melt into soft moving light. Pure QML + QtQuick.Effects (no shaders, no qt6-5compat). Rendered
// to a HALF-RES layer texture so the full-screen blur stays cheap on old GPUs (GT 730). If QtQuick.Effects
// is unavailable this whole file fails to load and Background.qml falls back to the static gradient.
import QtQuick 2.15
import QtQuick.Effects

Item {
    id: aurora
    property color bgTop:    "#2c2c2e"
    property color bgBottom: "#1c1c1e"
    property color accent:   "#0a84ff"
    property color tint2:    "#bf5af2"
    property color tint3:    "#64d2ff"

    Item {
        id: content
        anchors.fill: parent
        layer.enabled: true
        layer.textureSize: Qt.size(Math.max(2, aurora.width / 2), Math.max(2, aurora.height / 2))
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            autoPaddingEnabled: false
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: aurora.bgTop }
                GradientStop { position: 1.0; color: aurora.bgBottom }
            }
        }

        Rectangle {
            width: aurora.width * 0.75; height: width; radius: width / 2
            color: aurora.accent; opacity: 0.22
            x: aurora.width * 0.02; y: aurora.height * 0.05
            SequentialAnimation on x { loops: Animation.Infinite
                NumberAnimation { to: aurora.width * 0.28; duration: 15000; easing.type: Easing.InOutSine }
                NumberAnimation { to: aurora.width * 0.02; duration: 15000; easing.type: Easing.InOutSine } }
            SequentialAnimation on y { loops: Animation.Infinite
                NumberAnimation { to: aurora.height * 0.30; duration: 19000; easing.type: Easing.InOutSine }
                NumberAnimation { to: aurora.height * 0.05; duration: 19000; easing.type: Easing.InOutSine } }
        }
        Rectangle {
            width: aurora.width * 0.6; height: width; radius: width / 2
            color: aurora.tint2; opacity: 0.18
            x: aurora.width * 0.55; y: aurora.height * 0.45
            SequentialAnimation on x { loops: Animation.Infinite
                NumberAnimation { to: aurora.width * 0.30; duration: 21000; easing.type: Easing.InOutSine }
                NumberAnimation { to: aurora.width * 0.55; duration: 21000; easing.type: Easing.InOutSine } }
            SequentialAnimation on y { loops: Animation.Infinite
                NumberAnimation { to: aurora.height * 0.10; duration: 17000; easing.type: Easing.InOutSine }
                NumberAnimation { to: aurora.height * 0.45; duration: 17000; easing.type: Easing.InOutSine } }
        }
        Rectangle {
            width: aurora.width * 0.5; height: width; radius: width / 2
            color: aurora.tint3; opacity: 0.16
            x: aurora.width * 0.30; y: aurora.height * 0.6
            SequentialAnimation on y { loops: Animation.Infinite
                NumberAnimation { to: aurora.height * 0.25; duration: 23000; easing.type: Easing.InOutSine }
                NumberAnimation { to: aurora.height * 0.60; duration: 23000; easing.type: Easing.InOutSine } }
        }
    }
}
