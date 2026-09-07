import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 400
    height: 200
    title: "Odin + QML"

    Text {
        anchors.centerIn: parent
        text: "Hello from Odin"
        font.pixelSize: 24
    }
}
