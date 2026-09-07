# odin-qml

Odin bindings for Qt QML, via [DOtherSide](https://github.com/filcuc/dotherside).

Write your application logic in Odin and your interface in QML. Qt's declarative
UI language handles layout, animation and styling; Odin handles everything else.

> **Status: usable, early.** The raw C bindings are generated and complete, and
> there is a wrapper layer over them covering applications, objects, properties,
> signals, slots, variants and list models. Tree models
> (`QAbstractItemModel`) and QML type registration are not wrapped yet — reach
> for the raw `dos_*` functions there. The API may still change.

## Documentation

- [docs/api.md](docs/api.md) — the wrapper API, procedure by procedure
- [docs/memory.md](docs/memory.md) — who owns what, and what must be freed
- [docs/generator.md](docs/generator.md) — regenerating the raw bindings

## Why this exists

Qt is a C++ library, and its object system depends on `moc`, a code generator
that runs before compilation to produce the metaobject tables QML reads at
runtime. Neither the C++ ABI nor `moc` is reachable from Odin.

DOtherSide solves both problems: it exposes a pure C API, and it builds Qt
metaobjects *at runtime* rather than relying on `moc`. That runtime
construction is what makes QML bindings possible from any non-C++ language.
This repository is the Odin side of that bridge.

## Requirements

- Qt 6.2+ or Qt 5.12+, including the QML/Quick modules
- DOtherSide, built and installed
- Odin (any recent build)

## Installing DOtherSide

Install Qt with its **private** development headers. DOtherSide uses
`QMetaObjectBuilder`, which lives in Qt's private API — this is not optional.

```bash
# Arch
sudo pacman -S qt6-base qt6-declarative qt6-quickcontrols2 cmake

# Debian/Ubuntu
sudo apt install qt6-base-dev qt6-base-private-dev qt6-declarative-dev cmake

# Fedora
sudo dnf install qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtdeclarative-devel cmake
```

Then build:

```bash
git clone https://github.com/filcuc/dotherside.git
cd dotherside
```

**Patch required for Qt 6.** As of DOtherSide 0.9.0, `lib/CMakeLists.txt`
requests the `Core` component but not `CorePrivate`. Under Qt 5 the private
target was created automatically alongside `Core`; under Qt 6 it must be
requested explicitly. Without this, CMake's generate step fails with
`Target "DOtherSide" links to: Qt::CorePrivate but the target was not found`,
and the build then dies on a missing `qmetaobjectbuilder_p.h`.

Edit line 5 of `lib/CMakeLists.txt`:

```cmake
find_package(Qt6 COMPONENTS Core CorePrivate Qml Gui Quick QuickControls2 Widgets)
```

Then:

```bash
mkdir build && cd build
cmake ..
cmake --build .
sudo make install
sudo ldconfig
```

If the compile fails on warnings, the project builds with `-Werror` and newer
compilers emit warnings it was never tested against. Reconfigure with
`-DCMAKE_CXX_FLAGS=-Wno-error`.

Verify:

```bash
ls /usr/local/include/DOtherSide/
nm -D --defined-only /usr/local/lib/libDOtherSide.so | grep -c ' T dos_'
```

You should see two headers and roughly 158 exported symbols.

To force the Qt 5 path instead, configure with
`-DCMAKE_DISABLE_FIND_PACKAGE_Qt6=ON`. Note that DOtherSide built against Qt 5
and Qt 6 produce the same soname, so the two cannot coexist on one system.

## Installing odin-qml

Clone into a directory you use as an Odin collection:

```bash
mkdir -p ~/odin/shared
git clone https://github.com/<you>/odin-qml.git ~/odin/shared/odin-qml
```

Build your project with that directory as a collection:

```bash
odin run . -collection:shared=$HOME/odin/shared
```

The repository directory is `odin-qml`; the package inside it is `qml`.

## Usage

Interface in QML, logic in Odin. `main.qml`:

```qml
import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 300
    height: 200

    Column {
        anchors.centerIn: parent
        spacing: 12

        // Reads a property backed by Odin state. Re-evaluates whenever
        // the property's notify signal fires.
        Label { text: counter.value; font.pixelSize: 40 }

        // Calls an Odin procedure.
        Button { text: "Increment"; onClicked: counter.increment() }
    }
}
```

`main.odin`:

```odin
package main

import qml "shared:odin-qml"

// Your own state. The Object hands this back to every slot, so slots
// stay free of globals.
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
    qml.object_emit(obj, "valueChanged")   // tells QML to re-read
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
    qml.class_property(&cl, "value", .Int, read = "getValue", notify = "valueChanged")

    obj := qml.object_new(&cl, &counter)

    // Must precede the load: QML bindings resolve at load time.
    qml.app_expose(app, "counter", obj)
    qml.app_load_source(app, UI)
    qml.app_run(app)
}
```

`examples/counter` is this program, complete and runnable. `examples/hello` is
the same idea written against the raw bindings, for when you want to see what
the wrapper is doing. `examples/list` is a `ListView` backed by an Odin slice,
covering the other half of the library.

### Lists

A `ListView` needs a model rather than a property. `model_new` builds one from
a set of role names and two procedures — how many rows there are, and what is
in one:

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

```qml
ListView {
    model: entries
    delegate: Label { text: model.name + "  " + model.size }
}
```

A model is a QObject too, so the same `Class` can carry the slots the delegate
calls. Qt will not notice you mutating the backing data, so changes have to be
announced — `model_begin_insert_rows`/`model_end_insert_rows` around an insert,
`model_row_changed` after an edit, `model_begin_reset`/`model_end_reset` around
a wholesale replacement. See [docs/api.md](docs/api.md#list-models).

Qt 5 requires versioned imports (`import QtQuick 2.15`); Qt 6 does not.

### How it fits together

A `Class` describes signals, slots and properties. `object_new` turns that
description into a real Qt metaobject at runtime and instantiates a QObject
against it. `app_expose` publishes that object to QML under a name.

From there QML sees an ordinary Qt object: `counter.value` is a property it can
bind to, `counter.increment()` is a method it can call. Qt routes all of it —
slot calls, property reads, property writes — through a single callback, which
looks the name up and calls your procedure.

The consequence worth remembering: **a property only updates in the interface if
its notify signal fires.** A property declared without one, or a slot that
changes state without emitting, produces an interface that is correct once and
then quietly stale.

## Layout

| Path                    | Contents                                              |
| ----------------------- | ----------------------------------------------------- |
| `engine.odin`           | `App` — application, engine, loading, exposing         |
| `object.odin`           | `Class`, `Object`, dispatch, signals, connections      |
| `model.odin`            | `List_Model` — `QAbstractListModel` for `ListView`     |
| `variant.odin`          | `QVariant` conversions                                 |
| `types.odin`            | Handle types, callback signatures, metaobject structs  |
| `dos_procs.odin`        | Generated `foreign` block — **do not hand-edit**      |
| `tools/gen_bindings.py` | Generator that produces `dos_procs.odin`              |
| `docs/`                 | API reference, memory model, generator notes           |
| `examples/`             | Runnable examples                                      |

### Regenerating

`dos_procs.odin` is generated from the installed DOtherSide header. After
upgrading DOtherSide, regenerate rather than patching by hand:

```bash
python3 tools/gen_bindings.py /usr/local/include/DOtherSide/DOtherSide.h > dos_procs.odin
```

The generator emits a `// TODO` comment for anything it cannot map, so an
unmappable declaration is visible rather than silently dropped. See
[docs/generator.md](docs/generator.md) for the type tables and the header
quirks it works around.

## Notes and gotchas

**Callbacks must restore the context.** Every callback crossing into Qt is
declared `proc "c"`, which strips Odin's implicit `context` pointer. Inside
such a procedure there is no allocator, so anything that allocates, prints or
appends will fault. Restore it first:

```odin
on_call :: proc "c" (self: rawptr, slot_name: qml.DosQVariant, argc: c.int, argv: [^]qml.DosQVariant) {
    context = runtime.default_context()
    // ...
}
```

**Some returned strings must be freed.** Functions returning `cstring` — such
as `dos_qvariant_toString` and `dos_qobject_objectName` — return heap-allocated
memory that must be released with `dos_chararray_delete`. The type system does
not distinguish these from borrowed strings; the doxygen comments in
`DOtherSide.h` say which is which. The wrapper layer handles this for you:
`variant_to_string` copies and frees, returning an ordinary Odin string.

**`app_expose` takes ownership.** An object you expose is destroyed by
`app_destroy`. Calling `object_destroy` on it as well is a double free — see
[docs/memory.md](docs/memory.md) for the full ownership table.

**Callbacks must restore the context** — including any you pass to the raw
bindings. The wrapper's own dispatch does this before calling your slots, so
`Slot_Proc` procedures are ordinary Odin code.

**QML resolves names at runtime.** A misspelled property or slot name produces
a console warning, not a compile error. In a metaobject-driven binding a
mistyped slot name is a silent no-op. Watch stderr.

**Private Qt API.** DOtherSide depends on `QMetaObjectBuilder`, which carries
no compatibility guarantee across Qt releases. A Qt update can break the
DOtherSide build. Qt itself warns about this at configure time.

**Do not reorder struct fields** in `types.odin`. The metaobject definition
structs must match C's layout byte for byte.

## Licensing

This binding is released under [LICENSE](LICENSE).

DOtherSide itself is LGPL-3.0. Linking against it dynamically — which is what
`foreign import "system:DOtherSide"` does — does not impose the LGPL on your
own code, but static linking carries obligations. Qt's own licensing applies
separately and independently.

## Prior art

- [nimqml](https://github.com/filcuc/nimqml) — Nim, the most complete DOtherSide binding
- [qml_zig](https://github.com/kassane/qml_zig) — Zig
- [dqml](https://github.com/filcuc/dqml) — D, unmaintained
- [qml-rust](https://github.com/White-Oak/qml-rust) — Rust, unmaintained

nimqml is the best reference when a DOtherSide call is unclear. It uses Nim
macros to hide the metaobject boilerplate; Odin has no macro system, so that
ceremony is explicit here.
