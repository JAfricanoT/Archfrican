// On-screen keyboard for touchscreens. Imports QtQuick.VirtualKeyboard, so it's loaded ONLY via a
// Loader in Main — if qt6-virtualkeyboard is missing this file fails to load and the greeter simply
// has no on-screen keyboard (nothing breaks). It rises from the bottom when the input method becomes
// active (the field is focused on a touch device, or the keyboard toggle is pressed). For it to type,
// SDDM must run with InputMethod=qtvirtualkeyboard (the module writes that drop-in when enabled).
import QtQuick 2.15
import QtQuick.VirtualKeyboard

InputPanel {
    id: inputPanel
    anchors.left: parent.left
    anchors.right: parent.right
    y: active ? parent.height - height : parent.height
    Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    visible: y < parent.height
}
