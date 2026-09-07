# The binding generator

`dos_procs.odin` is generated from the installed `DOtherSide.h` by
`tools/gen_bindings.py`. **Do not hand-edit it** — the next regeneration would
silently revert your change.

```bash
python3 tools/gen_bindings.py /usr/local/include/DOtherSide/DOtherSide.h > dos_procs.odin
```

It prints a summary to stderr and should report zero declarations needing manual
work against DOtherSide 0.9.0.

## What it does

DOtherSide typedefs every opaque handle to `void`, so in C they are all
`void *` and interchangeable. The generator maps each one to a `distinct rawptr`
declared in `types.odin`, which costs nothing at runtime and makes Odin reject
passing a `DosQVariant` where a `DosQObject` was wanted.

Anything it cannot map is emitted as a `// TODO` comment rather than dropped, so
an unmappable declaration produces a visible gap instead of a mysteriously
missing function.

## Adding a type

Three tables at the top of the script drive the mapping:

- `OPAQUE` — handles typedef'd to `void`, becoming `distinct rawptr`. Add the
  matching declaration to `types.odin` too.
- `BY_POINTER` — structs and definition types, passed as `^T`.
- `CALLBACKS` — function-pointer typedefs, already pointers, no `^`.

## Overriding a signature

`PARAM_OVERRIDES` replaces the mapped type of a single parameter, keyed by
`(function, parameter)`. It exists because the header types some array
parameters as `void **`, which maps faithfully to `^rawptr` but throws away what
Odin could have known:

```python
PARAM_OVERRIDES = {
    ("dos_qobject_signal_emit", "parameters"): "[^]DosQVariant",
}
```

With the override, callers pass `raw_data(some_slice)` directly instead of
casting. Put improvements like this in the table rather than in the generated
file — that is the whole point of the table.

## Known header quirks

- **`DOS_CALL` is optional.** Most declarations carry it; a few, including
  `dos_qmetaobject_connection_delete`, do not. The generator treats it as
  optional and reports any `DOS_API` line it still cannot parse. An earlier
  version required it and dropped those declarations without a word.
- **Some functions are declared twice.** Legal in C, rejected by Odin. The
  generator keeps the first occurrence.
- **Doxygen comments carry the ownership rules** that the C types cannot
  express — which returned `char*` must be freed, which returned handles are
  borrowed. When wrapping a new function, read the comment above it.

## After regenerating

Rebuild the examples. If DOtherSide added or renamed anything, that is where it
surfaces:

```bash
odin build examples/counter -collection:shared=$HOME/odin/shared
```
