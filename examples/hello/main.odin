// The smallest possible odin-qml program, written against the raw
// bindings to show what the App wrapper in engine.odin is doing. Real
// programs should use that wrapper -- see examples/counter.
package main

import qml "shared:odin-qml"

main :: proc() {
	qml.dos_qguiapplication_create()
	defer qml.dos_qguiapplication_delete()

	engine := qml.dos_qqmlapplicationengine_create()
	defer qml.dos_qqmlapplicationengine_delete(engine)

	qml.dos_qqmlapplicationengine_load(engine, "main.qml")
	qml.dos_qguiapplication_exec()
}
