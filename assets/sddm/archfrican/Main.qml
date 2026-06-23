// Archfrican — the premium login. macOS-lock layout: a living aurora background, a big thin clock, a
// centered glass card (avatar · user · password · caps/layout), and a discreet bottom bar (session ·
// keyboard · power-with-confirm). Engineered "spectacular but never explodes": the CORE (Background
// base, Clock, LoginCard, PowerMenu, SessionPicker) uses ONLY core QtQuick imports, so it cannot fail
// to load and the password field is always there. The risky layers (aurora blur, video, virtual
// keyboard) live behind Loaders that fall back silently. Palette + knobs come from theme.conf (config.*),
// each with a hard fallback. Built original (inspired by SilentSDDM/astronaut/qylock + macOS), not copied.
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "Components"

Item {
    id: root
    width: 1920
    height: 1080

    // ---- palette (theme.conf -> config, hard fallbacks) ----
    readonly property color cBgTop:   config.bgTop       || "#2c2c2e"
    readonly property color cBgBot:   config.bgBottom    || "#1c1c1e"
    readonly property color cField:   config.fieldBg     || "#3a3a3c"
    readonly property color cAccent:  config.accentColor || "#0a84ff"
    readonly property color cText:    config.textColor   || "#f5f5f7"
    readonly property color cDim:     config.dimColor    || "#8e8e93"
    readonly property string cFont:   config.fontFamily  || "Inter"
    readonly property string cIcon:   "JetBrainsMono Nerd Font"

    // ---- UX knobs (strings from theme.conf) ----
    readonly property string bgMode:  config.backgroundMode || "motion"     // motion | image | video
    readonly property bool   vkOn:    (config.virtualKeyboardEnabled || "true") !== "false"
    readonly property bool   anims:   (config.animationsEnabled || "true") !== "false"

    property int sessionIndex: sessionPicker.sessionIndex

    // ===== background (safe to instantiate; its own Loader handles the risky aurora/video) =====
    Background {
        anchors.fill: parent
        mode: root.bgMode
        bgTop: root.cBgTop; bgBottom: root.cBgBot
        accent: root.cAccent
        tint2: config.tint2 || "#bf5af2"
        tint3: config.tint3 || "#64d2ff"
        imagePath: config.backgroundImage || ""
        videoPath: config.backgroundVideo || ""
    }

    // ===== foreground (fades in once) =====
    Item {
        id: foreground
        anchors.fill: parent
        opacity: root.anims ? 0 : 1
        Component.onCompleted: if (root.anims) fadeIn.start()
        NumberAnimation { id: fadeIn; target: foreground; property: "opacity"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }

        // clock
        Clock {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.15
            textColor: root.cText; dimColor: root.cDim; fontFamily: root.cFont
        }

        // the login card (fail-safe heart)
        LoginCard {
            id: loginCard
            anchors.centerIn: parent
            accentColor: root.cAccent; textColor: root.cText; dimColor: root.cDim
            fieldBg: root.cField; fontFamily: root.cFont; iconFont: root.cIcon
            sessionIndex: root.sessionIndex
        }

        // bottom-left: session
        SessionPicker {
            id: sessionPicker
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 28
            textColor: root.cText; dimColor: root.cDim; fontFamily: root.cFont
        }

        // bottom-right: keyboard toggle + power
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 28
            spacing: 22
            Text {                              // virtual-keyboard toggle
                visible: root.vkOn
                anchors.verticalCenter: parent.verticalCenter
                text: ""                       // nf keyboard
                font.family: root.cIcon; font.pixelSize: 18
                color: kbdArea.containsMouse ? root.cText : root.cDim
                MouseArea {
                    id: kbdArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        loginCard.focusPassword()
                        if (Qt.inputMethod.visible) Qt.inputMethod.hide(); else Qt.inputMethod.show()
                    }
                }
            }
            PowerMenu {
                anchors.verticalCenter: parent.verticalCenter
                textColor: root.cText; dimColor: root.cDim; fontFamily: root.cFont; iconFont: root.cIcon
            }
        }
    }

    // ===== virtual keyboard (risky import -> Loader-gated; silent if module absent) =====
    Loader {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: root.vkOn
        source: "Components/VirtualKeyboard.qml"
        onStatusChanged: if (status === Loader.Error)
                             console.log("archfrican greeter: virtual keyboard unavailable (qt6-virtualkeyboard?)")
    }

    // type-anywhere: a keypress focuses the password field
    focus: true
    Keys.onPressed: function (event) { loginCard.focusPassword() }
    Component.onCompleted: loginCard.focusPassword()
}
