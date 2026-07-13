// The login card: avatar (accent ring) · user · glass password field with show/hide · caps/layout
// indicators · spinner · shake-on-fail. Core imports only (cannot fail to load) and self-contained:
// it talks to the global SDDM objects (sddm, userModel, keyboard) directly. The password field here is
// the fail-safe heart of the whole greeter, so it never lives behind a Loader.
import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: card
    width: 340
    implicitHeight: col.implicitHeight

    // ---- theming (set by Main from the palette) ----
    property color accentColor: "#0a84ff"
    property color textColor:   "#f5f5f7"
    property color dimColor:    "#8e8e93"
    property color fieldBg:     "#3a3a3c"
    property string fontFamily: "Inter"
    property string iconFont:   "JetBrainsMono Nerd Font"
    property int    sessionIndex: 0
    property bool   authenticating: false

    function focusPassword() { password.forceActiveFocus() }
    function attemptLogin() {
        if (card.authenticating) return
        message.isError = false
        message.text = ""
        card.authenticating = true
        sddm.login(userBox.currentText, password.text, card.sessionIndex)
    }

    // shake offset (animated on failure)
    property real shakeX: 0
    transform: Translate { x: card.shakeX }
    SequentialAnimation {
        id: shake
        loops: 2
        NumberAnimation { target: card; property: "shakeX"; to: 9;  duration: 45 }
        NumberAnimation { target: card; property: "shakeX"; to: -9; duration: 45 }
        NumberAnimation { target: card; property: "shakeX"; to: 0;  duration: 45 }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            card.authenticating = false
            message.isError = true
            message.text = "Contraseña incorrecta"
            shake.start()
            password.selectAll()
            password.forceActiveFocus()
        }
        function onLoginSucceeded() { /* keep the spinner until SDDM tears us down */ }
    }

    Column {
        id: col
        width: parent.width
        spacing: 16

        // ---- avatar: accent-ringed circle with the user's initial ----
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 104; height: 104; radius: 52
            color: card.fieldBg
            border.width: 2
            border.color: card.accentColor
            Text {
                anchors.centerIn: parent
                color: card.textColor
                font.family: card.fontFamily
                font.pixelSize: 44
                font.weight: Font.Light
                text: (userBox.currentText || "?").charAt(0).toUpperCase()
            }
        }

        // ---- user selector (label-like for one user; a picker for many) ----
        ComboBox {
            id: userBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, parent.width)
            model: userModel
            textRole: "name"
            currentIndex: userModel.lastIndex
            flat: true
            font.family: card.fontFamily
            font.pixelSize: 21
            contentItem: Text {
                text: userBox.currentText
                color: card.textColor
                font: userBox.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            indicator: Item {}
            background: Item {}
        }

        // ---- glass password field + show/hide toggle ----
        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: 48
            radius: 14
            color: Qt.rgba(card.fieldBg.r, card.fieldBg.g, card.fieldBg.b, 0.72)
            border.width: password.activeFocus ? 2 : 1
            border.color: password.activeFocus ? card.accentColor : Qt.rgba(1, 1, 1, 0.12)
            Behavior on border.color { ColorAnimation { duration: 120 } }

            TextField {
                id: password
                anchors.left: parent.left; anchors.right: reveal.left
                anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                echoMode: revealOn ? TextInput.Normal : TextInput.Password
                placeholderText: "Contraseña"
                color: card.textColor
                placeholderTextColor: card.dimColor
                font.family: card.fontFamily
                font.pixelSize: 16
                verticalAlignment: TextInput.AlignVCenter
                background: Item {}
                focus: true
                enabled: !card.authenticating
                property bool revealOn: false
                onAccepted: card.attemptLogin()
            }
            // show/hide eye (Nerd Font)
            Text {
                id: reveal
                anchors.right: spinner.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 22 : 0
                visible: password.text.length > 0 && !card.authenticating
                color: revealArea.containsMouse ? card.textColor : card.dimColor
                font.family: card.iconFont
                font.pixelSize: 16
                text: password.revealOn ? "" : ""   // eye-slash / eye
                MouseArea {
                    id: revealArea; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: password.revealOn = !password.revealOn
                }
            }
            // login spinner (custom, accent-colored)
            Item {
                id: spinner
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                visible: card.authenticating
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: card.accentColor
                    opacity: 0.35
                }
                Rectangle {
                    width: 18; height: 18; radius: 9
                    color: "transparent"
                    border.width: 2
                    border.color: card.accentColor
                    // a quarter-arc illusion: a small dot orbiting
                    Rectangle {
                        width: 4; height: 4; radius: 2; color: card.accentColor
                        x: parent.width / 2 - 2; y: -1
                    }
                    RotationAnimator on rotation {
                        running: spinner.visible; loops: Animation.Infinite
                        from: 0; to: 360; duration: 800
                    }
                }
            }
        }

        // ---- caps lock + keyboard layout indicators (SDDM `keyboard` object) ----
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14
            height: 16
            Text {
                visible: (typeof keyboard !== "undefined") && keyboard.capsLock
                color: card.accentColor
                font.family: card.fontFamily
                font.pixelSize: 12
                text: "⇪ Bloq Mayús"
            }
            Text {
                id: layoutText
                visible: (typeof keyboard !== "undefined") && keyboard.layouts && keyboard.layouts.length > 1
                color: layoutArea.containsMouse ? card.textColor : card.dimColor
                font.family: card.fontFamily
                font.pixelSize: 12
                text: {
                    if (typeof keyboard === "undefined" || !keyboard.layouts) return ""
                    var l = keyboard.layouts[keyboard.currentLayout]
                    return l ? ("⌨ " + (l.shortName || l.longName || "")) : ""
                }
                MouseArea {
                    id: layoutArea; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof keyboard !== "undefined" && keyboard.layouts)
                            keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
                    }
                }
            }
        }

        // ---- status / error line + FIDO2 cue ----
        Text {
            id: message
            anchors.horizontalCenter: parent.horizontalCenter
            property bool isError: false
            color: isError ? "#ff6961" : card.dimColor
            font.family: card.fontFamily
            font.pixelSize: 13
            text: ""
        }
    }
}
