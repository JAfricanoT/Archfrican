// Power controls — Nerd Font icons (suspend · restart · shut down) with an inline confirmation, so a
// stray click never powers the machine off. Core imports only. Uses the global SDDM power API.
import QtQuick 2.15

Row {
    id: power
    spacing: 18

    property color textColor: "#f5f5f7"
    property color dimColor:  "#8e8e93"
    property string fontFamily: "Inter"
    property string iconFont: "JetBrainsMono Nerd Font"

    // "" | suspend | reboot | poweroff
    property string armed: ""
    function run(action) {
        if (action === "suspend" && sddm.canSuspend) sddm.suspend()
        else if (action === "reboot" && sddm.canReboot) sddm.reboot()
        else if (action === "poweroff" && sddm.canPowerOff) sddm.powerOff()
    }

    // --- the three icons (hidden while a confirmation is showing) ---
    Repeater {
        model: [
            { act: "suspend",  glyph: "", show: sddm.canSuspend  },
            { act: "reboot",   glyph: "", show: sddm.canReboot   },
            { act: "poweroff", glyph: "", show: sddm.canPowerOff }
        ]
        Text {
            visible: power.armed === "" && modelData.show
            text: modelData.glyph
            color: iconArea.containsMouse ? power.textColor : power.dimColor
            font.family: power.iconFont
            font.pixelSize: 18
            Behavior on color { ColorAnimation { duration: 100 } }
            MouseArea {
                id: iconArea; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: power.armed = modelData.act
            }
        }
    }

    // --- inline confirmation ---
    Text {
        visible: power.armed !== ""
        color: power.dimColor
        font.family: power.fontFamily
        font.pixelSize: 13
        anchors.verticalCenter: parent.verticalCenter
        text: power.armed === "poweroff" ? "Shut down?"
            : power.armed === "reboot"   ? "Restart?"
            : "Suspend?"
    }
    Text {
        visible: power.armed !== ""
        text: "Yes"
        color: yesArea.containsMouse ? "#ff6961" : power.textColor
        font.family: power.fontFamily; font.pixelSize: 13
        anchors.verticalCenter: parent.verticalCenter
        MouseArea {
            id: yesArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: { var a = power.armed; power.armed = ""; power.run(a) }
        }
    }
    Text {
        visible: power.armed !== ""
        text: "Cancel"
        color: cancelArea.containsMouse ? power.textColor : power.dimColor
        font.family: power.fontFamily; font.pixelSize: 13
        anchors.verticalCenter: parent.verticalCenter
        MouseArea {
            id: cancelArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: power.armed = ""
        }
    }
}
