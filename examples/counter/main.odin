package main

import "core:fmt"
import qml "../.."

// Your own state. The Object hands this back to every slot via obj.data,
// so slots stay free of globals.
Counter :: struct {
	value: int,
}

get_value :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	ctr := cast(^Counter)obj.data
	qml.variant_set_int(result, ctr.value)
}

increment :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	ctr := cast(^Counter)obj.data
	ctr.value += 1
	// Tells QML the property changed; any binding on `counter.value`
	// re-evaluates and calls get_value again.
	qml.object_emit(obj, "valueChanged")
}

reset :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	ctr := cast(^Counter)obj.data
	ctr.value = 0
	qml.object_emit(obj, "valueChanged")
}

// Takes an argument from QML.
say :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	if len(args) == 0 {
		return
	}
	msg := qml.variant_to_string(args[0])
	defer delete(msg)
	fmt.println("QML says:", msg)
}

UI :: #load("main.qml", string)

main :: proc() {
	counter := Counter{}

	app := qml.app_create()
	defer qml.app_destroy(app)

	cl := qml.class_make("Counter")
	defer qml.class_destroy(&cl)

	qml.class_signal(&cl, "valueChanged")
	qml.class_slot(&cl, "getValue", get_value, .Int)
	qml.class_slot(&cl, "increment", increment)
	qml.class_slot(&cl, "reset", reset)
	qml.class_slot(&cl, "say", say, .Void, {.QString})
	qml.class_property(&cl, "value", .Int, read = "getValue", notify = "valueChanged")

	obj := qml.object_new(&cl, &counter)

	// Must happen before the QML loads, since bindings resolve at load.
	qml.app_expose(app, "counter", obj)
	qml.app_load_source(app, UI)
	qml.app_run(app)

	fmt.println("final value:", counter.value)
}
