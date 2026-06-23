// Big, thin clock + localized date (macOS-lock style). Core imports only — cannot fail to load.
import QtQuick 2.15

Column {
    id: clock
    spacing: 2

    property color textColor: "#f5f5f7"
    property color dimColor:  "#8e8e93"
    property string fontFamily: "Inter"

    function refresh() {
        var now = new Date()
        time.text = Qt.formatTime(now, "HH:mm")
        date.text = Qt.formatDate(now, "dddd, d MMMM")
    }

    Text {
        id: time
        anchors.horizontalCenter: parent.horizontalCenter
        color: clock.textColor
        font.family: clock.fontFamily
        font.pixelSize: 92
        font.weight: Font.Thin
        text: Qt.formatTime(new Date(), "HH:mm")
    }
    Text {
        id: date
        anchors.horizontalCenter: parent.horizontalCenter
        color: clock.dimColor
        font.family: clock.fontFamily
        font.pixelSize: 22
        font.capitalization: Font.Capitalize
        text: Qt.formatDate(new Date(), "dddd, d MMMM")
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.refresh() }
    Component.onCompleted: refresh()
}
