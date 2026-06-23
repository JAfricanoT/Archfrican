// Discreet session picker (SDDM auto-lists /usr/share/wayland-sessions/*.desktop, e.g. niri). Core
// imports only. Exposes `sessionIndex` for Main to forward to sddm.login.
import QtQuick 2.15
import QtQuick.Controls 2.15

ComboBox {
    id: sessionBox
    property color textColor: "#f5f5f7"
    property color dimColor:  "#8e8e93"
    property string fontFamily: "Inter"
    property alias sessionIndex: sessionBox.currentIndex

    model: sessionModel
    textRole: "name"
    currentIndex: sessionModel.lastIndex
    flat: true
    font.family: fontFamily
    font.pixelSize: 13

    contentItem: Text {
        text: "  " + sessionBox.currentText
        color: sessionHover.hovered ? sessionBox.textColor : sessionBox.dimColor
        font: sessionBox.font
        verticalAlignment: Text.AlignVCenter
        Behavior on color { ColorAnimation { duration: 100 } }
    }
    indicator: Item {}
    background: Item {}
    HoverHandler { id: sessionHover }
}
