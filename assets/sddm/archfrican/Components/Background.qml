// Background dispatcher — picks the layer by config.backgroundMode and ALWAYS keeps a fail-safe base
// gradient underneath. The fancy layer (aurora motion / video) is loaded via a Loader, so if its Qt
// module is missing or it errors, we silently fall back to the gradient (+ optional static image).
// Order of resilience: base gradient -> optional image -> Loader(aurora|video) -> legibility dim.
import QtQuick 2.15

Item {
    id: bg
    property string mode: "motion"            // motion | image | video
    property color bgTop:    "#2c2c2e"
    property color bgBottom: "#1c1c1e"
    property color accent:   "#0a84ff"
    property color tint2:    "#bf5af2"
    property color tint3:    "#64d2ff"
    property string imagePath: ""
    property string videoPath: ""

    // 1. fail-safe gradient — always present
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: bg.bgTop }
            GradientStop { position: 0.55; color: Qt.darker(bg.bgBottom, 1.05) }
            GradientStop { position: 1.0; color: bg.bgBottom }
        }
    }

    // 2. optional static image — premium "image" mode, or a richer base if one is provided
    Image {
        anchors.fill: parent
        source: bg.imagePath
        visible: bg.imagePath !== "" && status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }

    // 3. the fancy layer — graceful; only for motion/video
    Loader {
        id: fancy
        anchors.fill: parent
        active: bg.mode === "motion" || bg.mode === "video"
        source: bg.mode === "video"  ? "VideoBackground.qml"
              : bg.mode === "motion" ? "AuroraBackground.qml"
              : ""
        onStatusChanged: if (status === Loader.Error)
                             console.log("archfrican greeter: background fell back to the static base")
        onLoaded: {
            if (bg.mode === "motion") {
                item.bgTop = bg.bgTop; item.bgBottom = bg.bgBottom
                item.accent = bg.accent; item.tint2 = bg.tint2; item.tint3 = bg.tint3
            } else if (bg.mode === "video") {
                item.source = bg.videoPath
            }
        }
    }

    // 4. subtle dim for text legibility over any background
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.18 }
}
