import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    visible: true
    width: 360
    height: 240
    title: "odin-qml counter"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16

        Label {
            // Reading a property exposed from Odin. This re-evaluates
            // every time valueChanged fires.
            text: counter.value
            font.pixelSize: 48
            Layout.alignment: Qt.AlignHCenter
        }

        RowLayout {
            spacing: 8
            Button {
                text: "Increment"
                onClicked: counter.increment()
            }
            Button {
                text: "Reset"
                onClicked: counter.reset()
            }
            Button {
                text: "Say hello"
                onClicked: counter.say("hello from QML")
            }
        }
    }
}
