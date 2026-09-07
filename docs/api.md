# API reference

Every procedure here lives in package `qml`. The package has two layers:

- the **wrapper layer** (`engine.odin`, `object.odin`, `model.odin`,
  `variant.odin`) — what this document covers, and what you should write
  against;
- the **raw bindings** (`dos_procs.odin`) — a mechanical translation of
  `DOtherSide.h`, always available for anything the wrapper does not reach yet.

It covers four things, roughly in the order a program needs them: starting an
application and loading QML, describing a class and instantiating it as an
object QML can bind to, backing a `ListView` with a list model, and moving
values across the boundary as variants.

Mixing the two layers is fine and expected. `App.engine`, `Object.qobject` and
`List_Model.handle` are the raw handles, exposed deliberately so you can drop
down without ceremony — the model wrapper in particular covers only what a
flat list needs, and the column and tree calls are all still there under
`dos_qabstractitemmodel_*`.

For who frees what, see [memory.md](memory.md). Read it before writing anything
that creates variants in a loop.

---

## Application

### `app_create() -> ^App`

Creates the `QGuiApplication` and a `QQmlApplicationEngine`. Qt permits exactly
one application object per process, so call this once, before any other Qt call,
and pair it with `app_destroy`.

```odin
app := qml.app_create()
defer qml.app_destroy(app)
```

### `app_destroy(app: ^App)`

Tears down, in order: the engine, every object passed to `app_expose`, then the
application. The order matters — deleting an object the engine still has
bindings on produces `disconnect from destroyed signal` warnings at best.

Objects handed to `app_expose` are owned from here on. Do not also call
`object_destroy` on them.

### `app_load_file(app: ^App, path: string)`

Loads QML from a file, resolved against the **process working directory**, not
the executable. A binary that loads this way only runs from its source
directory; prefer `app_load_source` for anything you intend to install.

### `app_load_source(app: ^App, source: string)`

Loads QML from a string. Pairs with `#load` to compile the interface into the
executable:

```odin
UI :: #load("main.qml", string)
qml.app_load_source(app, UI)
```

### `app_add_import_path(app: ^App, path: string)`

Adds a directory to the QML import path, for custom QML modules.

### `app_expose(app: ^App, name: string, obj: ^Object)`

Makes an object visible to QML as a context property under `name`. **Must be
called before loading the QML** — bindings resolve at load time, and an object
exposed afterwards is invisible to everything already parsed.

Exposing the same object under two names is fine; it is only destroyed once.

### `app_expose_value(app: ^App, name: string, value: DosQVariant)`

The same, for a plain value. The variant is copied into the context, so free
yours with `variant_free` once this returns.

### `app_run(app: ^App)`

Enters Qt's event loop. Blocks until the last window closes.

### `app_poll(app: ^App)`

Pumps pending Qt events once and returns. Use instead of `app_run` when you want
to drive your own main loop:

```odin
for running {
	qml.app_poll(app)
	simulate(&world)
	free_all(context.temp_allocator)
}
```

### `app_quit(app: ^App)`

Asks the event loop to exit. `app_run` returns shortly afterwards.

### `set_style(name: string)`

Sets the Qt Quick Controls style — `"Material"`, `"Fusion"`, `"Basic"`,
`"Universal"`. Must be called before loading QML. Not tied to an `App`, because
Qt's own API is process-global here.

---

## Describing a class

A `Class` is a description you build, hand to `object_new`, and then throw away.
It owns nothing at runtime; the object copies what it needs.

### `class_make(name: string) -> Class`

The name is what Qt reports as the metaobject's class name. It must not be
empty.

### `class_destroy(cl: ^Class)`

Frees the description. Safe as soon as `object_new` has returned.

### `class_signal(cl: ^Class, name: string, params: []MetaType = nil)`

Declares a signal. Emit it later with `object_emit`.

### `class_slot(cl, name: string, fn: Slot_Proc, ret: MetaType = .Void, params: []MetaType = nil)`

Declares a method QML can call. `params` describes what QML passes in; `ret` is
what you write into `result`.

```odin
qml.class_slot(&cl, "say", say, .Void, {.QString})
qml.class_slot(&cl, "getValue", get_value, .Int)
```

### `class_property(cl, name: string, type: MetaType, read: string, write: string = "", notify: string = "")`

Declares a property. `read`, `write` and `notify` name a slot, a slot, and a
signal you have already declared on the same class.

Omitting `write` makes the property read-only from QML. Omitting `notify` means
QML bindings never re-evaluate when the value changes — almost always a mistake,
and a quiet one, since the interface simply shows a stale value forever.

---

## Objects

### `Slot_Proc :: proc(obj: ^Object, args: []DosQVariant, result: DosQVariant)`

The signature every slot has.

- `obj.data` is the opaque pointer you passed to `object_new`, so slots need no
  globals.
- `args` are the arguments from QML, already unboxed from Qt's `argv[1:]`.
- `result` is where you write a return value with `variant_set_*`. Ignore it for
  slots declared `.Void`.

The variants in `args` and `result` belong to Qt. Do not free them, and do not
keep them past the end of the call.

### `object_new(cl: ^Class, data: rawptr = nil) -> ^Object`

Builds the runtime metaobject and instantiates the QObject. Returns nil, with a
message on stderr, if the class has no name or Qt refuses to build the
metaobject.

### `object_destroy(obj: ^Object)`

Destroys the QObject and everything `object_new` allocated. Do **not** call this
on an object you passed to `app_expose` — `app_destroy` owns those, and doing
both is a double free.

### `object_emit(obj: ^Object, signal: string, args: ..DosQVariant)`

Emits a signal by name. Every QML binding on a property whose notify signal this
is will re-evaluate, which is how updates reach the interface:

```odin
increment :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	ctr := cast(^Counter)obj.data
	ctr.value += 1
	qml.object_emit(obj, "valueChanged")
}
```

You own any variants you pass as `args`; free them after the call returns.

A misspelled signal name is a silent no-op, so watch stderr the first time a
binding refuses to update.

---

## List models

A `List_Model` is a `QAbstractListModel`: the thing a QML `ListView`,
`GridView` or `Repeater` binds its `model` property to. It is an `Object` with
a second set of callbacks attached, so the same object can carry ordinary
signals, slots and properties alongside its rows.

You keep the data in whatever Odin form suits you and answer two questions
about it: how many rows there are, and what is in one.

### `model_new(cl, roles, row_count, get_data, data = nil, set_data = nil) -> ^List_Model`

```odin
Role :: enum { Name, Size }
ROLES := []string{"name", "size"}

row_count :: proc(m: ^qml.List_Model) -> int {
	return len((cast(^Store)m.data).entries)
}

get_data :: proc(m: ^qml.List_Model, row: int, role: int, result: qml.DosQVariant) {
	e := (cast(^Store)m.data).entries[row]
	switch Role(role) {
	case .Name: qml.variant_set_string(result, e.name)
	case .Size: qml.variant_set_i64(result, e.size)
	}
}

model := qml.model_new(&cl, ROLES, row_count, get_data, &store)
qml.app_expose(app, "entries", &model.obj)
```

`roles` are the names the delegate uses — `model.name`, `model.size`. They are
cloned, so the slice need not outlive the call.

`data` is the same opaque pointer `object_new` takes. Slots reach it as
`obj.data`, model callbacks as `m.data`.

Returns nil, with a message on stderr, if there are no roles or either
procedure is missing.

`List_Model` embeds its `Object` as the first field — Qt hands one pointer
back to both `dispatch` and the model callbacks, so the two must coincide.
That is also why `&model.obj` and `cast(^qml.List_Model)obj` are both valid.

### `Data_Proc :: proc(m: ^List_Model, row: int, role: int, result: DosQVariant)`

`row` is already bounds-checked against `row_count`. `role` is an **index into
the `roles` slice**, not Qt's raw role number — cast it to your own enum.
Leaving `result` untouched reaches QML as `undefined`.

Qt asks for its own roles (`DisplayRole` and friends) whether or not the
delegate mentions them; those never reach `get_data`.

### `Set_Data_Proc :: proc(m, row, role: int, value: DosQVariant) -> bool`

Optional. Supplying one marks rows `Qt::ItemIsEditable`. Return false to refuse
the write. Announcing the change is not automatic — call `model_row_changed`.

### `model_destroy(m: ^List_Model)`

As `object_destroy`, and with the same caveat: a model passed to `app_expose`
belongs to `app_destroy`.

### Announcing changes

Qt caches, and will not notice you mutating the backing data. Every change has
to be announced, and announced *around* itself — the begin call before the
data changes, the end call after — because views read the model in between to
work out what moved.

| Call | When |
| ---- | ---- |
| `model_begin_reset(m)` / `model_end_reset(m)` | wholesale replacement |
| `model_begin_insert_rows(m, first, last)` / `model_end_insert_rows(m)` | rows appearing |
| `model_begin_remove_rows(m, first, last)` / `model_end_remove_rows(m)` | rows disappearing |
| `model_row_changed(m, row, roles = nil)` | an in-place edit, *after* the fact |
| `model_rows_changed(m, first, last, roles = nil)` | the same for a range |

`first` and `last` are inclusive. For an insert they are the positions the new
rows *will* occupy — appending one row to a list of ten is `(10, 10)`. For a
remove the rows must still be present when `model_begin_remove_rows` is called.

`roles` are role indices, as in `Data_Proc`; nil means every role changed.

A reset is the blunt instrument: every delegate is rebuilt and the view loses
its scroll position and selection. It is still the only correct call when the
change is not a simple splice.

A model that renders once and then goes stale is almost always a missing
announcement.

### `object_init(obj, cl, data = nil, super = nil, model_cbs = nil) -> bool`

The half of `object_new` that builds the metaobject, exposed because
`model_new` needs it. Call it directly only if you are wrapping another
DOtherSide class the same way a model does: pass that class's metaobject as
`super`, and `obj` must be allocated, zeroed, and have its `Object` at offset
zero. On failure it leaves nothing allocated and the caller frees `obj`.

`Object.on_destroy`, if set, runs at the start of `object_destroy` — that is
how a model frees its role names without `engine.odin` knowing models exist.

---

## Connections

Connecting to a signal from Odin rather than from QML.

### `connect(obj, signal: string, callback, data: rawptr = nil, type := DosQtConnectionType.AutoConnection) -> Connection`

The callback is a `proc "c"` and runs with no Odin context — restore one with
`context = runtime.default_context()` before allocating, exactly as in a slot.

`data` is handed straight back to the callback and must outlive the connection.

### `disconnect(conn: ^Connection)`

Breaks the connection **and** frees its handle. These are two separate
operations in the C API and it is easy to do only the first;
`dos_qobject_disconnect_with_connection_static` leaves the handle allocated.
`disconnect` does both, is safe to call twice, and is safe after the sender is
already gone.

---

## Variants

`QVariant` is the box every value travels in across the boundary.

### Creating — you own the result

`variant_new`, `variant_int`, `variant_bool`, `variant_f64`, `variant_i64`,
`variant_string`, `variant_object` each return a heap-allocated variant. Free it
with `variant_free`.

### `variant_free(v: DosQVariant)` / `variant_is_null(v) -> bool`

### Reading

`variant_to_int`, `variant_to_bool`, `variant_to_f64`, `variant_to_i64` return
by value and allocate nothing.

`variant_to_string(v, allocator := context.allocator) -> string` returns a
string **you own**. Qt hands back a heap `char*` that must be released with
`dos_chararray_delete`; the wrapper copies and releases it for you, leaving you
one ordinary Odin string to `delete`.

```odin
msg := qml.variant_to_string(args[0])
defer delete(msg)
```

### Writing in place

`variant_set_int`, `variant_set_bool`, `variant_set_f64`, `variant_set_i64`,
`variant_set_string`, `variant_set_object`.

Use these on `result` inside a slot: the variant already exists, Qt reads it
after you return, and creating a new one would only leak.

---

## MetaType

Qt's own type ids, from `QMetaType::Type` — not DOtherSide's.

| Odin | QML sees |
| --- | --- |
| `.Bool` | `bool` |
| `.Int`, `.LongLong` | `int` |
| `.Double`, `.Float` | `real` |
| `.QString` | `string` |
| `.QVariantList`, `.QVariantMap` | `var` |
| `.QObjectStar` | an object with its own properties |
| `.Void` | slot return only |

The values are stable across Qt 5 and 6 for these basic types. Verify anything
beyond the list against your own `qmetatype.h`
(`/usr/include/qt6/QtCore/qmetatype.h`).

---

## Raw bindings

`dos_procs.odin` is generated and should not be hand-edited — see
[generator.md](generator.md). The handle types (`DosQObject`, `DosQVariant`, and
the rest) are `distinct rawptr`, which costs nothing at runtime but makes Odin
reject passing a variant where an object was wanted — a mistake C accepts
silently and pays for with a segfault.

What the wrapper does not reach yet, and what to call instead:

| Missing | Raw entry point |
| ------- | --------------- |
| Tree models | `dos_qabstractitemmodel_create`, plus `createIndex`/`parent` mapping of your own |
| Table models | `dos_qabstracttablemodel_create` |
| Column insert/remove on a model | `dos_qabstractitemmodel_begin*Columns` / `end*Columns` |
| Header data | the `headerData` callback, currently a stub in `model.odin` |
| QML type registration | `dos_qdeclarative_qmlregistertype` |
| Image providers | `dos_qquickimageprovider_create` |

One rule carries over from `model.odin` to any of these: a `DosQModelIndex`
argument must never be nil. DOtherSide dereferences it to form the
`QModelIndex&` it hands Qt, so a nil "no parent" argument is a segfault inside
Qt rather than a warning. Pass `dos_qmodelindex_create()` and delete it after.
