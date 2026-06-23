// Archfrican — a minimal, elegant macOS-style SDDM greeter. Pure QtQuick (Qt6), no extra modules,
// no GraphicalEffects/blur (kept reliable on old GPUs). Colors come from theme.conf (the `config`
// object), each with a hard fallback so a missing key can never break the login. Layout: a soft
// vertical gradient, a large thin clock + date up top, a centered card (avatar · user · password),
// a discreet session picker, and subtle power controls.
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: 1920
    height: 1080

    // ---- palette (theme.conf -> config, with fallbacks) ----
    readonly property color cBgTop:   config.bgTop      || "#2c2c2e"
    readonly property color cBgBot:   config.bgBottom   || "#1c1c1e"
    readonly property color cField:   config.fieldBg    || "#3a3a3c"
    readonly property color cAccent:  config.accentColor|| "#0a84ff"
    readonly property color cText:    config.textColor  || "#f5f5f7"
    readonly property color cDim:     config.dimColor   || "#8e8e93"
    readonly property string cFont:   config.fontFamily || "Inter"

    gradient: Gradient {
        GradientStop { position: 0.0; color: root.cBgTop }
        GradientStop { position: 1.0; color: root.cBgBot }
    }

    property int sessionIndex: sessionModel.lastIndex

    function doLogin() {
        message.text = ""
        sddm.login(userField.currentText, passwordField.text, root.sessionIndex)
    }

    // ---- clock + date ----
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.16
        spacing: 2
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cText
            font.family: root.cFont
            font.pixelSize: 82
            font.weight: Font.Thin
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cDim
            font.family: root.cFont
            font.pixelSize: 20
            text: Qt.formatDate(new Date(), "dddd, MMMM d")
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            clock.text = Qt.formatTime(new Date(), "HH:mm")
            dateText.text = Qt.formatDate(new Date(), "dddd, MMMM d")
        }
    }

    // ---- centered login card ----
    Column {
        anchors.centerIn: parent
        spacing: 18
        width: 320

        // avatar: a circle with the selected user's initial (no image dependency)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96; radius: 48
            color: root.cField
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            Text {
                anchors.centerIn: parent
                color: root.cText
                font.family: root.cFont
                font.pixelSize: 40
                font.weight: Font.Light
                text: (userField.currentText || "?").charAt(0).toUpperCase()
            }
        }

        // user selector (looks like a label for a single user; a real picker for many)
        ComboBox {
            id: userField
            anchors.horizontalCenter: parent.horizontalCenter
            width: implicitWidth
            model: userModel
            textRole: "name"
            currentIndex: userModel.lastIndex
            flat: true
            font.family: root.cFont
            font.pixelSize: 20
            contentItem: Text {
                text: userField.currentText
                color: root.cText
                font: userField.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            indicator: Item {}                      // hide the dropdown arrow — keep it clean
            background: Item {}
        }

        // password field — rounded, translucent, accent on focus
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: 46
            radius: 12
            color: root.cField
            border.width: passwordField.activeFocus ? 2 : 1
            border.color: passwordField.activeFocus ? root.cAccent : Qt.rgba(1, 1, 1, 0.10)
            TextField {
                id: passwordField
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                echoMode: TextInput.Password
                placeholderText: "Password"
                color: root.cText
                placeholderTextColor: root.cDim
                font.family: root.cFont
                font.pixelSize: 16
                verticalAlignment: TextInput.AlignVCenter
                background: Item {}                 // the wrapper Rectangle is the visible field
                focus: true
                onAccepted: root.doLogin()
            }
        }

        // status / error line
        Text {
            id: message
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cAccent
            font.family: root.cFont
            font.pixelSize: 13
            text: ""
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            message.text = "Incorrect password — try again"
            passwordField.selectAll()
            passwordField.forceActiveFocus()
        }
    }

    // ---- discreet session picker (bottom-left) ----
    ComboBox {
        id: sessionField
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        model: sessionModel
        textRole: "name"
        currentIndex: sessionModel.lastIndex
        flat: true
        font.family: root.cFont
        font.pixelSize: 13
        onActivated: root.sessionIndex = currentIndex
        contentItem: Text {
            text: "Session: " + sessionField.currentText
            color: root.cDim
            font: sessionField.font
            verticalAlignment: Text.AlignVCenter
        }
        indicator: Item {}
        background: Item {}
    }

    // ---- power controls (bottom-right) ----
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 22

        Text {
            visible: sddm.canSuspend
            text: "Suspend"
            color: suspendArea.containsMouse ? root.cText : root.cDim
            font.family: root.cFont
            font.pixelSize: 13
            MouseArea { id: suspendArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sddm.suspend() }
        }
        Text {
            visible: sddm.canReboot
            text: "Restart"
            color: rebootArea.containsMouse ? root.cText : root.cDim
            font.family: root.cFont
            font.pixelSize: 13
            MouseArea { id: rebootArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sddm.reboot() }
        }
        Text {
            visible: sddm.canPowerOff
            text: "Shut Down"
            color: poweroffArea.containsMouse ? root.cText : root.cDim
            font.family: root.cFont
            font.pixelSize: 13
            MouseArea { id: poweroffArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sddm.powerOff() }
        }
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}
