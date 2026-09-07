package main

import qml "shared:odin-qml"

main :: proc() {
    qml.dos_qguiapplication_create()
    engine := qml.dos_qqmlapplicationengine_create()
    qml.dos_qqmlapplicationengine_load(engine, "main.qml")
    qml.dos_qguiapplication_exec()
}
