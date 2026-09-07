# CLAUDE.md

Context for working on this repo.

## What this is

Odin bindings for Qt QML, via [DOtherSide](https://github.com/filcuc/dotherside)
(a C shim over Qt that builds QMetaObjects at runtime instead of using `moc`).
No other Odin QML binding exists, so there is no prior art to copy — but
[nimqml](https://github.com/filcuc/nimqml) is the reference implementation of
the same C API and is worth reading when a DOtherSide call is ambiguous.

Published at github.com/cgmccarron/odin-qml.

## Environment

- Arch Linux, Qt 6.11.2, DOtherSide built from master and installed to `/usr/local`
- `/usr/local/lib` was added to the loader path via `/etc/ld.so.conf.d/usrlocal.conf`
- Odin package is `qml`; the repo directory is `odin-qml`, so imports need an
  explicit alias: `import qml "shared:odin-qml"` (hyphens aren't valid identifiers)

## Layout

| File                    | Contents                                                    |
| ----------------------- | ----------------------------------------------------------- |
| `types.odin`            | Handles, callback signatures, metaobject definition structs |
| `dos_procs.odin`        | Generated `foreign` block, 154 procs — **do not hand-edit** |
| `variant.odin`          | QVariant create/read/set-in-place helpers                   |
| `engine.odin`           | `App`: QGuiApplication + QQmlApplicationEngine lifecycle     |
| `object.odin`           | `Class`/`Object`: runtime metaobjects, slot dispatch          |
| `tools/gen_bindings.py` | Regenerates `dos_procs.odin` from the installed header       |
| `examples/counter/`     | Working example: property binding, slots, signals             |

Regenerate bindings with:

```bash
python3 tools/gen_bindings.py /usr/local/include/DOtherSide/DOtherSide.h > dos_procs.odin
```

## Verified facts about the C API

Checked against DOtherSide source, not guessed:

- **Slot dispatch:** DOtherSide builds `argv` as `[result, arg0, arg1, ...]`.
  `argv[0]` is the QVariant to write a return value into; `argc` counts it.
- **Definition lifetime:** `dos_qmetaobject_create` calls `DOS::toVector` on the
  definition structs immediately, converting to C++ vectors of QStrings. It
  copies — the arrays and cstrings can be freed as soon as it returns.
- **`dos_qobject_signal_emit`:** `parameters` is an array of `QVariant*` with no
  result slot and no offset.
- **Model callbacks:** `parent`/`index` QModelIndex handles are owned by
  DOtherSide (never delete them); `result` is an out-param to fill, not replace.

## Gotchas already hit

- **`proc "c"` callbacks have no context.** Every one needs
  `context = runtime.default_context()` before anything allocates. Hot callbacks
  should also `defer free_all(context.temp_allocator)` — the variant string
  helpers use temp, and nothing else reclaims it.
- **`runtime.default_context()` discards `main`'s context**, so custom allocators
  set up in `main` never reach callbacks. Consider stashing a package-level
  context instead.
- **Teardown order matters.** Delete the QML engine before any object exposed to
  it, or Qt warns about disconnecting from destroyed signals. `App` owns exposed
  objects and handles this in `app_destroy`.
- **`DOtherSide.h` declares four functions twice** (`setData`, `roleNames`,
  `flags`, `headerData`). Legal C, rejected by Odin. The generator dedupes.
- **DOtherSide 0.9.0 doesn't build against Qt 6** without adding `CorePrivate` to
  the `find_package` components in `lib/CMakeLists.txt`. Documented in README.
  Not yet reported upstream — worth a PR.
- **QML resolves names at runtime.** A misspelled slot or property name is a
  silent no-op. `dispatch` logs unknown slot names to stderr for this reason.

## Current task: `model.odin`

A `QAbstractListModel` binding, so QML `ListView` can render Odin-side data.
Needed before the DU clone (see below).

Design decided but not yet written:

- `dos_qabstractlistmodel_create` takes the same first three args as
  `dos_qobject_create` plus a `DosQAbstractItemModelCallbacks` struct, so a model
  is an Object with a fourth argument. Split `object_new` into
  `object_init(obj, cl, data, super, model_cbs)` so both can share it.
- Superclass metaobject must be `dos_qabstractlistmodel_qmetaobject()`, not
  `dos_qobject_qmetaobject()`.
- `List_Model` must have `using obj: Object` as its **first** field — the same
  `self` pointer reaches `dispatch` (which casts to `^Object`) and the model
  callbacks (which cast to `^List_Model`), so `Object` has to sit at offset 0.
- Keep the callbacks struct inside the heap-allocated `List_Model`; it's unclear
  whether DOtherSide copies it.
- Only `rowCount`, `data` and `roleNames` need real implementations. `index` and
  `parent` delegate to `dos_qabstractlistmodel_index`/`_parent` and fill the
  out-param with `dos_qmodelindex_assign`. The rest are stubs, but none may be
  nil — DOtherSide calls all twelve unconditionally.
- Custom roles start at `Qt::UserRole` = 256.
- Mutating the backing slice is invisible to Qt; bracket changes with
  `beginResetModel`/`endResetModel`.

Build it incrementally: hardcode `row_count` to 5 and `data` to a constant
string first, get a `ListView` showing five rows, then wire real data.

## After that

A `du` clone — recursive directory scan, sizes rendered in a QML list — as the
first real consumer of this library. Then a file explorer. Decisions made:
start with a flat list model and click-to-navigate rather than a tree
(`QAbstractItemModel` + `TreeView` needs `createIndex`/`parent` mapping, which is
the fiddliest part of Qt's model API); and scan synchronously at first, accepting
the UI freeze, since emitting signals from a non-Qt thread needs queued
connections.

Application-specific code (role constants, `Entry` structs, the scanner) belongs
in the DU repo, not here. If it mentions files or sizes, it's not binding work.

## Building

```bash
cd examples/counter && odin run .        # relative import, no collection needed
```

Projects outside this repo need
`-collection:shared=$HOME/Projects/odin_projects/shared`, or symlink the repo
into `$(odin root)/shared` to make `shared:odin-qml` resolve everywhere.
