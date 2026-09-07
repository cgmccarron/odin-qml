# Memory and ownership

Two allocators and two heaps meet in this library: Odin's, and Qt's C++ heap
reached through DOtherSide. Nothing reference-counts across that line, so
ownership is a convention. This page is the convention.

## The short version

| Thing | Owner | Released by |
| --- | --- | --- |
| `^App` from `app_create` | you | `app_destroy` |
| `^Object` from `object_new` | you | `object_destroy` |
| `^Object` after `app_expose` | the `App` | `app_destroy` — not you |
| `Class` from `class_make` | you | `class_destroy`, any time after `object_new` |
| Variant from `variant_*` | you | `variant_free` |
| Variant in a slot's `args` / `result` | Qt | nobody — do not free |
| String from `variant_to_string` | you | `delete` |
| `Connection` from `connect` | you | `disconnect` |
| `cstring` from a raw `dos_*_toString` | you | `dos_chararray_delete` |

## Objects and the engine

`app_expose` takes ownership. The single most tempting mistake is symmetry:

```odin
obj := qml.object_new(&cl, &state)
defer qml.object_destroy(obj)      // WRONG once app_expose is called

qml.app_expose(app, "state", obj)
defer qml.app_destroy(app)         // this destroys obj too -> double free
```

Write it without the first `defer`. `app_destroy` deletes the engine before the
objects, deliberately: an object destroyed while QML still holds bindings on it
warns at best and crashes at worst.

Objects you never expose — helpers you drive from Odin alone — are yours, and
`object_destroy` is the right call for them.

A `List_Model` follows the same rule through the same code: `app_expose` takes
`&model.obj`, and `app_destroy` reaches it as an `Object`. Its cloned role
names are freed by the `on_destroy` hook `model_new` installs, so there is
nothing extra to release — and nothing extra to release *twice*.

## Variants

Anything named `variant_*` that *creates* returns memory you own:

```odin
v := qml.variant_string("hello")
defer qml.variant_free(v)
qml.object_emit(obj, "somethingHappened", v)
```

Anything Qt hands *you* — the `args` slice and the `result` variant inside a
slot — belongs to Qt. Freeing those is a double free, and keeping a pointer past
the end of the call is a use-after-free. Copy the value out instead:

```odin
say :: proc(obj: ^qml.Object, args: []qml.DosQVariant, result: qml.DosQVariant) {
	msg := qml.variant_to_string(args[0])   // a copy, owned by you
	defer delete(msg)
	fmt.println("QML says:", msg)
}
```

Emitting in a loop is the place this bites. One unfreed variant per frame is a
slow leak that only shows up after an hour of running.

## Strings across the boundary

Odin strings are not NUL-terminated; C requires that they are. Every wrapper
that takes a `string` converts it internally, in the temp allocator, and
releases it before returning — you never see the conversion.

In the other direction, DOtherSide functions returning `cstring` return
heap-allocated memory. The type system cannot distinguish those from borrowed
strings, so:

- through the wrapper: `variant_to_string` already copies and frees. Just
  `delete` the Odin string it gives you.
- through the raw bindings: call `dos_chararray_delete` yourself. The doxygen
  comments in `DOtherSide.h` say which functions need it.

## The temp allocator

Odin's default temp allocator is an arena that only resets when something calls
`free_all` on it. In a program whose main loop is `app_run`, nothing ever does —
so a library that allocated temporaries and left them would grow the arena for
the life of the process.

This library does not leave them. Every wrapper that uses the temp allocator
brackets its own use with `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()`, a
mark/release pair, and the callback that Qt drives every slot call and property
read through does the same. Nothing accumulates, and **you do not need to call
`free_all` on the library's behalf**.

The guard is a mark/release rather than a `free_all` for a specific reason:
dispatch re-enters. A slot emits a signal, QML reacts to it synchronously by
calling a second slot, and that inner call would otherwise free temp memory the
outer call was still using.

Your own temporaries are still yours. If your slots use `context.temp_allocator`
they are released when the slot returns, which is usually what you want. If you
drive your own loop with `app_poll`, call `free_all(context.temp_allocator)`
once per iteration as you would in any Odin program.

## Callbacks have no context

Every procedure Qt calls into is declared `proc "c"`, which strips Odin's
implicit `context` pointer. Inside one there is no allocator, no logger and no
temp allocator, so anything that allocates, prints or appends will fault.
Restore it first:

```odin
on_signal :: proc "c" (data: rawptr, argc: c.int, argv: [^]qml.DosQVariant) {
	context = runtime.default_context()
	// ...
}
```

Slot procedures written against `Slot_Proc` are ordinary Odin procedures and
already have a context — the library's dispatch callback restores it before
calling you. This only concerns callbacks you hand to the raw bindings yourself,
such as the one `connect` takes.

## Checking your own work

Odin's tracking allocator finds leaks on your side of the line. It cannot see
Qt's heap, so run it against a program that exits — drive the interface with
`app_poll` for a fixed number of iterations rather than `app_run`:

```odin
import "core:mem"

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer {
		for _, entry in track.allocation_map {
			fmt.eprintfln("%v leaked %v bytes", entry.location, entry.size)
		}
		mem.tracking_allocator_destroy(&track)
	}

	run()
}
```

For the C++ side, `valgrind --leak-check=full` works, but expect a large volume
of noise: Qt keeps a great deal of state alive intentionally until process exit,
and static QML type registrations are reported as reachable. Compare two runs
that differ only in how many times your code did the thing you suspect, rather
than reading absolute numbers.
