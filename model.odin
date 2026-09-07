package qml

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------
// List models.
//
// A QAbstractListModel is how a QML ListView, Repeater or GridView reads
// a sequence of rows out of native code. It is the same machinery as the
// QObject layer -- a runtime metaobject, one dispatch callback -- with a
// second set of callbacks bolted on that Qt calls to ask how many rows
// there are and what is in them.
//
// The division of labour is: you keep the data in whatever Odin form you
// like, and answer two questions about it.
//
//	roles     - the names your QML delegate uses (`model.name`, `model.size`)
//	row_count - how many rows there are right now
//	get_data  - what is in row `row` for role index `role`
//
// Qt caches aggressively and will not notice you mutating the backing
// slice, so every change has to be announced: model_reset for a wholesale
// replacement, model_insert_rows / model_remove_rows for a splice,
// model_row_changed for an in-place edit. A model that renders once and
// then goes stale is almost always a missing announcement.
// ---------------------------------------------------------------------

// Qt::UserRole. Roles below this belong to Qt (DisplayRole, ToolTipRole,
// ...); custom roles start here, so role index `i` is USER_ROLE + i.
USER_ROLE :: 256

// Qt::ItemIsSelectable | Qt::ItemIsEnabled -- what a plain, non-editable
// list row is.
@(private)
DEFAULT_ITEM_FLAGS :: 1 | 32

// Qt's own calls always supply an index, but a QModelIndex& formed from
// a null pointer is reachable through DOtherSide, and dereferencing one
// is a segfault rather than a warning. Nil counts as invalid.
@(private)
index_valid :: proc "contextless" (i: DosQModelIndex) -> bool {
	return i != nil && dos_qmodelindex_isValid(i)
}

Row_Count_Proc :: proc(m: ^List_Model) -> int

// Fills `result` with the value of one cell, using variant_set_*.
//
//	row  - 0 ..< row_count, already bounds-checked
//	role - an index into the `roles` slice the model was built with, not
//	       the raw Qt role number; cast it to your own enum
//
// Leaving `result` untouched is legal and reaches QML as `undefined`.
Data_Proc :: proc(m: ^List_Model, row: int, role: int, result: DosQVariant)

// Writes one cell back, for models QML edits. Return false to refuse.
// Announcing the change is *not* automatic: call model_row_changed.
Set_Data_Proc :: proc(m: ^List_Model, row: int, role: int, value: DosQVariant) -> bool

List_Model :: struct {
	// Must stay first. Qt hands one pointer back to everything: dispatch
	// casts it to ^Object, the model callbacks cast it to ^List_Model.
	// Both are only true if the Object sits at offset 0.
	using obj: Object,

	// The model handle and the QObject handle are the same C++ object seen
	// through different types. Kept separately because the model calls
	// below want it typed.
	handle:    DosQAbstractListModel,

	// Held inside the model rather than passed by value: DOtherSide stores
	// the pointer and it is not documented to copy the struct.
	callbacks: DosQAbstractItemModelCallbacks,

	roles:     []string, // cloned; index i is Qt role USER_ROLE + i
	role_ids:  []c.int,  // scratch for model_row_changed

	row_count: Row_Count_Proc,
	get_data:  Data_Proc,
	set_data:  Set_Data_Proc,
}

// Builds the metaobject, instantiates the model and returns it ready to
// expose. `cl` may carry ordinary signals, slots and properties as well --
// a model is a QObject, so a file browser can put `path` and `navigate()`
// on the same object as its rows.
//
// `data` is the same opaque pointer object_new takes; slots reach it as
// `obj.data`, and the model callbacks as `m.data`.
//
// Returns nil on failure, having reported the reason on stderr.
model_new :: proc(
	cl: ^Class,
	roles: []string,
	row_count: Row_Count_Proc,
	get_data: Data_Proc,
	data: rawptr = nil,
	set_data: Set_Data_Proc = nil,
) -> ^List_Model {
	if row_count == nil || get_data == nil {
		fmt.eprintln("odin-qml: model_new needs both a row_count and a get_data procedure")
		return nil
	}
	if len(roles) == 0 {
		// With no roles QML has no names to bind to, and the delegate can
		// only ever show blanks.
		fmt.eprintln("odin-qml: model_new needs at least one role name")
		return nil
	}

	m := new(List_Model)
	m.row_count = row_count
	m.get_data = get_data
	m.set_data = set_data
	m.on_destroy = model_on_destroy

	// The Class may not outlive the model, so the names are cloned.
	m.roles = make([]string, len(roles))
	m.role_ids = make([]c.int, len(roles))
	for r, i in roles {
		m.roles[i] = strings.clone(r)
		m.role_ids[i] = c.int(USER_ROLE + i)
	}

	// Filled in before object_init, because DOtherSide may call straight
	// into them -- roleNames in particular -- while constructing.
	m.callbacks = DosQAbstractItemModelCallbacks {
		rowCount     = cb_row_count,
		columnCount  = cb_column_count,
		data         = cb_data,
		setData      = cb_set_data,
		roleNames    = cb_role_names,
		flags        = cb_flags,
		headerData   = cb_header_data,
		index        = cb_index,
		parent       = cb_parent,
		hasChildren  = cb_has_children,
		canFetchMore = cb_can_fetch_more,
		fetchMore    = cb_fetch_more,
	}

	if !object_init(
		&m.obj,
		cl,
		data,
		dos_qabstractlistmodel_qmetaobject(),
		&m.callbacks,
	) {
		model_free_roles(m)
		free(m)
		return nil
	}
	m.handle = cast(DosQAbstractListModel)m.obj.qobject
	return m
}

// Destroys the model. Do not call this on a model passed to app_expose --
// app_destroy owns those, and will reach the same code through
// object_destroy.
model_destroy :: proc(m: ^List_Model) {
	object_destroy(&m.obj)
}

@(private)
model_on_destroy :: proc(obj: ^Object) {
	model_free_roles(cast(^List_Model)obj)
}

@(private)
model_free_roles :: proc(m: ^List_Model) {
	for r in m.roles {
		delete(r)
	}
	delete(m.roles)
	delete(m.role_ids)
	m.roles = nil
	m.role_ids = nil
}

// --- announcing changes ----------------------------------------------
//
// Qt has to be told about every change to the backing data, and told
// *around* it: the begin call is made before the data changes and the end
// call after. Views read the model in between to work out what moved.

// Brackets a wholesale replacement of the data. The blunt instrument --
// every view rebuilds every delegate and loses its scroll position and
// selection -- but the only correct one when the change is not a simple
// splice.
//
//	qml.model_begin_reset(m)
//	replace_the_entries()
//	qml.model_end_reset(m)
model_begin_reset :: proc(m: ^List_Model) {
	dos_qabstractitemmodel_beginResetModel(cast(DosQAbstractItemModel)m.handle)
}

model_end_reset :: proc(m: ^List_Model) {
	dos_qabstractitemmodel_endResetModel(cast(DosQAbstractItemModel)m.handle)
}

// `first` and `last` are inclusive, and are the positions the new rows
// will occupy once inserted -- appending one row to a list of 10 is
// (10, 10), not (11, 11).
model_begin_insert_rows :: proc(m: ^List_Model, first: int, last: int) {
	parent := dos_qmodelindex_create()
	defer dos_qmodelindex_delete(parent)
	dos_qabstractitemmodel_beginInsertRows(
		cast(DosQAbstractItemModel)m.handle,
		parent,
		c.int(first),
		c.int(last),
	)
}

model_end_insert_rows :: proc(m: ^List_Model) {
	dos_qabstractitemmodel_endInsertRows(cast(DosQAbstractItemModel)m.handle)
}

// Inclusive, and the rows must still be present when this is called.
model_begin_remove_rows :: proc(m: ^List_Model, first: int, last: int) {
	parent := dos_qmodelindex_create()
	defer dos_qmodelindex_delete(parent)
	dos_qabstractitemmodel_beginRemoveRows(
		cast(DosQAbstractItemModel)m.handle,
		parent,
		c.int(first),
		c.int(last),
	)
}

model_end_remove_rows :: proc(m: ^List_Model) {
	dos_qabstractitemmodel_endRemoveRows(cast(DosQAbstractItemModel)m.handle)
}

// Announces that rows first..last (inclusive) changed in place. Unlike
// the others this is called *after* the change, since nothing is moving
// and the view only needs to re-read.
//
// `roles` are role indices, as passed to Data_Proc; an empty slice means
// every role changed.
model_rows_changed :: proc(m: ^List_Model, first: int, last: int, roles: []int = nil) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// The parent has to be a real invalid index, not a null pointer:
	// DOtherSide dereferences it to form the QModelIndex& Qt is passed,
	// and Qt hands that straight back to rowCount().
	parent := dos_qmodelindex_create()
	defer dos_qmodelindex_delete(parent)

	top_left := dos_qabstractlistmodel_index(m.handle, c.int(first), 0, parent)
	bottom_right := dos_qabstractlistmodel_index(m.handle, c.int(last), 0, parent)
	defer dos_qmodelindex_delete(top_left)
	defer dos_qmodelindex_delete(bottom_right)

	ids: [^]c.int
	count: c.int
	if len(roles) > 0 {
		buf := make([]c.int, len(roles), context.temp_allocator)
		for r, i in roles {
			buf[i] = c.int(USER_ROLE + r)
		}
		ids = raw_data(buf)
		count = c.int(len(buf))
	}
	dos_qabstractitemmodel_dataChanged(
		cast(DosQAbstractItemModel)m.handle,
		top_left,
		bottom_right,
		ids,
		count,
	)
}

model_row_changed :: proc(m: ^List_Model, row: int, roles: []int = nil) {
	model_rows_changed(m, row, row, roles)
}

// --- callbacks --------------------------------------------------------
//
// The twelve procedures Qt reaches the model through. None may be nil:
// DOtherSide dereferences all of them without checking, so the ones with
// nothing to say are still written out as stubs.
//
// Every one is `proc "c"` and so starts without a context. The three that
// can allocate -- through user code or string conversion -- restore one;
// the rest touch nothing that needs it.
//
// `parent`, `index` and `child` handles belong to DOtherSide and must not
// be deleted. `result` is an out-parameter to fill, never to replace.

@(private)
cb_row_count :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^c.int) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	m := cast(^List_Model)self
	// A list is flat: only the invisible root has rows. Answering
	// otherwise is what turns a ListView into an infinite recursion.
	if index_valid(parent) {
		result^ = 0
		return
	}
	result^ = c.int(m.row_count(m))
}

@(private)
cb_column_count :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^c.int) {
	context = runtime.default_context()
	result^ = index_valid(parent) ? 0 : 1
}

@(private)
cb_data :: proc "c" (self: rawptr, index: DosQModelIndex, role: c.int, result: DosQVariant) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	m := cast(^List_Model)self
	if !index_valid(index) {
		return
	}

	// Qt asks for its own roles too -- DisplayRole, ToolTipRole and the
	// rest -- whether or not the delegate mentions them. Leaving those
	// unset gives QML `undefined`, which is the honest answer for a model
	// that only defines custom roles.
	idx := int(role) - USER_ROLE
	if idx < 0 || idx >= len(m.roles) {
		return
	}

	row := int(dos_qmodelindex_row(index))
	// Qt can hold an index briefly outside the current row count -- during
	// a reset, or a view repainting on data that just shrank.
	if row < 0 || row >= m.row_count(m) {
		return
	}
	m.get_data(m, row, idx, result)
}

@(private)
cb_set_data :: proc "c" (
	self: rawptr,
	index: DosQModelIndex,
	value: DosQVariant,
	role: c.int,
	result: ^bool,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	m := cast(^List_Model)self
	result^ = false
	if m.set_data == nil || !index_valid(index) {
		return
	}
	idx := int(role) - USER_ROLE
	if idx < 0 || idx >= len(m.roles) {
		return
	}
	row := int(dos_qmodelindex_row(index))
	if row < 0 || row >= m.row_count(m) {
		return
	}
	result^ = m.set_data(m, row, idx, value)
}

@(private)
cb_role_names :: proc "c" (self: rawptr, result: DosQHashIntQByteArray) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	m := cast(^List_Model)self
	for name, i in m.roles {
		cs := strings.clone_to_cstring(name, context.temp_allocator)
		dos_qhash_int_qbytearray_insert(result, c.int(USER_ROLE + i), cs)
	}
}

@(private)
cb_flags :: proc "c" (self: rawptr, index: DosQModelIndex, result: ^c.int) {
	context = runtime.default_context()
	m := cast(^List_Model)self
	if !index_valid(index) {
		result^ = 0
		return
	}
	result^ = DEFAULT_ITEM_FLAGS
	if m.set_data != nil {
		result^ |= 2 // Qt::ItemIsEditable
	}
}

// Headers are a table and tree concern; a ListView never asks. Leaving
// the variant untouched is the same as returning an invalid QVariant.
@(private)
cb_header_data :: proc "c" (
	self: rawptr,
	section: c.int,
	orientation: c.int,
	role: c.int,
	result: DosQVariant,
) {
}

// index() and parent() are pure structure, and a flat list's structure is
// exactly QAbstractListModel's own. Delegating means the QModelIndex
// carries whatever internal bookkeeping Qt expects, which hand-rolling it
// would not.
@(private)
cb_index :: proc "c" (
	self: rawptr,
	row: c.int,
	column: c.int,
	parent: DosQModelIndex,
	result: DosQModelIndex,
) {
	context = runtime.default_context()
	m := cast(^List_Model)self
	if m.handle == nil {
		return
	}
	idx := dos_qabstractlistmodel_index(m.handle, row, column, parent)
	defer dos_qmodelindex_delete(idx)
	// Assign into the out-param; the caller owns `result`.
	dos_qmodelindex_assign(result, idx)
}

@(private)
cb_parent :: proc "c" (self: rawptr, child: DosQModelIndex, result: DosQModelIndex) {
	context = runtime.default_context()
	m := cast(^List_Model)self
	if m.handle == nil {
		return
	}
	idx := dos_qabstractlistmodel_parent(m.handle, child)
	defer dos_qmodelindex_delete(idx)
	dos_qmodelindex_assign(result, idx)
}

@(private)
cb_has_children :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^bool) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	m := cast(^List_Model)self
	result^ = !index_valid(parent) && m.row_count(m) > 0
}

// Incremental loading is not wired up: the model always has everything it
// is going to have.
@(private)
cb_can_fetch_more :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^bool) {
	context = runtime.default_context()
	result^ = false
}

@(private)
cb_fetch_more :: proc "c" (self: rawptr, parent: DosQModelIndex) {
}
