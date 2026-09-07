package main

import "core:fmt"
import qml "shared:odin-qml"

// The model's rows. Ordinary Odin data -- the binding never sees this
// type, it only calls back to ask what is in row N.
Item :: struct {
	name: string,
	size: int,
	done: bool,
}

// One constant per role name, in the same order as ROLES below. Data_Proc
// receives an index into that slice, so this enum is what the index means.
Role :: enum {
	Name,
	Size,
	Done,
}

ROLES := []string{"name", "size", "done"}

Store :: struct {
	items: [dynamic]Item,
	next:  int,
}

// --- model callbacks --------------------------------------------------

row_count :: proc(m: ^qml.List_Model) -> int {
	st := cast(^Store)m.data
	return len(st.items)
}

get_data :: proc(m: ^qml.List_Model, row: int, role: int, result: qml.DosQVariant) {
	st := cast(^Store)m.data
	it := st.items[row]
	switch Role(role) {
	case .Name:
		qml.variant_set_string(result, it.name)
	case .Size:
		qml.variant_set_int(result, it.size)
	case .Done:
		qml.variant_set_bool(result, it.done)
	}
}

// --- slots ------------------------------------------------------------

model_of :: proc(obj: ^qml.Object) -> ^qml.List_Model {
	// The Object is the model's first field, so the pointers coincide.
	return cast(^qml.List_Model)obj
}

add :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	m := model_of(obj)
	st := cast(^Store)m.data

	// Appending is a splice, so Qt is told where the new row lands before
	// it exists: a view keeps its scroll position and animates the insert.
	n := len(st.items)
	qml.model_begin_insert_rows(m, n, n)
	append(&st.items, Item{name = fmt.aprintf("item %d", st.next), size = st.next * 1024})
	st.next += 1
	qml.model_end_insert_rows(m)
}

remove :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	m := model_of(obj)
	st := cast(^Store)m.data
	if len(args) < 1 {
		return
	}
	row := qml.variant_to_int(args[0])
	if row < 0 || row >= len(st.items) {
		return
	}

	qml.model_begin_remove_rows(m, row, row)
	delete(st.items[row].name)
	ordered_remove(&st.items, row)
	qml.model_end_remove_rows(m)
}

// An in-place edit: nothing moves, so the announcement comes after the
// change and names the row and the role that went stale.
toggle :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	m := model_of(obj)
	st := cast(^Store)m.data
	if len(args) < 1 {
		return
	}
	row := qml.variant_to_int(args[0])
	if row < 0 || row >= len(st.items) {
		return
	}

	st.items[row].done = !st.items[row].done
	qml.model_row_changed(m, row, {int(Role.Done)})
}

// Replacing everything at once. Cruder -- every delegate is rebuilt and
// the view forgets where it was -- but it is the only correct call when
// the change is not a simple insert or remove.
reset :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	m := model_of(obj)
	st := cast(^Store)m.data

	qml.model_begin_reset(m)
	for it in st.items {
		delete(it.name)
	}
	clear(&st.items)
	st.next = 0
	for i in 0 ..< 5 {
		append(&st.items, Item{name = fmt.aprintf("item %d", i), size = i * 1024})
	}
	st.next = 5
	qml.model_end_reset(m)
}

count :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	st := cast(^Store)obj.data
	qml.variant_set_int(result, len(st.items))
}

UI :: #load("main.qml", string)

main :: proc() {
	store := Store{items = make([dynamic]Item)}
	defer {
		for it in store.items {
			delete(it.name)
		}
		delete(store.items)
	}

	app := qml.app_create()
	defer qml.app_destroy(app)

	// A model is a QObject as well, so the same class carries the slots
	// the delegate calls and a plain property for the row count.
	cl := qml.class_make("ItemModel")
	defer qml.class_destroy(&cl)

	qml.class_signal(&cl, "countChanged")
	qml.class_slot(&cl, "count", count, .Int)
	qml.class_slot(&cl, "add", add)
	qml.class_slot(&cl, "remove", remove, .Void, {.Int})
	qml.class_slot(&cl, "toggle", toggle, .Void, {.Int})
	qml.class_slot(&cl, "reset", reset)
	qml.class_property(&cl, "count", .Int, read = "count", notify = "countChanged")

	model := qml.model_new(&cl, ROLES, row_count, get_data, &store)
	if model == nil {
		return
	}

	qml.app_expose(app, "items", &model.obj)
	qml.app_load_source(app, UI)
	qml.app_run(app)
}
