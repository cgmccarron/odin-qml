# odin-qml

Odin bindings for Qt QML, via [DOtherSide](https://github.com/filcuc/dotherside).

Write your application logic in Odin and your interface in QML. Qt's declarative
UI language handles layout, animation and styling; Odin handles everything else.

> **Status: early.** The raw C bindings are generated and complete. The
> ergonomic layer on top of them is not written yet. Expect to call
> `dos_*` functions directly for now, and expect the API to change.

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

```odin
package main

import "shared:odin-qml"

main :: proc() {
    qml.dos_qguiapplication_create()
    defer qml.dos_qguiapplication_delete()

    engine := qml.dos_qqmlapplicationengine_create()
    defer qml.dos_qqmlapplicationengine_delete(engine)

    qml.dos_qqmlapplicationengine_load(engine, "main.qml")
    qml.dos_qguiapplication_exec()
}
```

With `main.qml`:

```qml
import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 400
    height: 200
    Text {
        anchors.centerIn: parent
        text: "Hello from Odin"
    }
}
```

Qt 5 requires versioned imports (`import QtQuick 2.15`); Qt 6 does not.

## Layout

| Path                    | Contents                                            |
| ----------------------- | --------------------------------------------------- |
| `types.odin`            | Handle types, callback signatures, metaobject structs |
| `dos_procs.odin`        | Generated `foreign` block — **do not hand-edit**    |
| `tools/gen_bindings.py` | Generator that produces `dos_procs.odin`            |
| `examples/`             | Runnable examples                                    |

### Regenerating

`dos_procs.odin` is generated from the installed DOtherSide header. After
upgrading DOtherSide, regenerate rather than patching by hand:

```bash
python3 tools/gen_bindings.py /usr/local/include/DOtherSide/DOtherSide.h > dos_procs.odin
```

The generator emits a `// TODO` comment for anything it cannot map, so an
unmappable declaration is visible rather than silently dropped.

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
`DOtherSide.h` say which is which.

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
