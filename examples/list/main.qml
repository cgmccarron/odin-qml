import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    visible: true
    width: 420
    height: 480
    title: "odin-qml list model"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4

            // The model is the Odin object itself. Role names declared in
            // model_new become properties on each delegate's `model`.
            model: items

            delegate: ItemDelegate {
                width: ListView.view.width
                onClicked: items.toggle(index)

                contentItem: RowLayout {
                    spacing: 12
                    Label {
                        text: model.name
                        font.strikeout: model.done
                        Layout.fillWidth: true
                    }
                    Label {
                        text: (model.size / 1024).toFixed(1) + " KiB"
                        opacity: 0.6
                    }
                    ToolButton {
                        text: "×"
                        onClicked: items.remove(index)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Button { text: "Add"; onClicked: items.add() }
            Button { text: "Reset"; onClicked: items.reset() }
            Item { Layout.fillWidth: true }
            // Not a role: an ordinary property on the same object.
            Label { text: items.count + " rows" }
        }
    }
}
