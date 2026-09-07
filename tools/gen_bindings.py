#!/usr/bin/env python3
"""Generate an Odin foreign block from DOtherSide.h.

Usage:
    python3 gen_bindings.py /usr/local/include/DOtherSide/DOtherSide.h > dos_procs.odin

Anything it can't map is emitted as a commented-out line prefixed with
// TODO, so nothing is silently wrong -- you get a compile-clean file plus
an explicit list of the handful of declarations to finish by hand.
"""

import re
import sys

# --- C type -> Odin type -------------------------------------------------
# Opaque Qt handles: DOtherSide typedefs these all to `void`, so a
# `DosFoo *` in C is really `void *`. We map them to distinct rawptr
# types declared in types.odin so Odin can tell them apart.
OPAQUE = {
    "DosQVariant", "DosQModelIndex", "DosQAbstractItemModel",
    "DosQAbstractListModel", "DosQAbstractTableModel",
    "DosQQmlApplicationEngine", "DosQQuickView", "DosQQmlContext",
    "DosQHashIntQByteArray", "DosQUrl", "DosQMetaObject", "DosQObject",
    "DosQQuickImageProvider", "DosPixmap", "DosQPointer",
    "DosQMetaObjectConnection",
}

# Plain-value types.
SCALARS = {
    "void": "",
    "bool": "bool",
    "char": "u8",
    "int": "c.int",
    "unsigned int": "c.uint",
    "unsigned char": "u8",
    "long long": "c.longlong",
    "unsigned long long": "c.ulonglong",
    "float": "f32",
    "double": "f64",
    "size_t": "c.size_t",
}

# Structs and callback typedefs from DOtherSideTypes.h -- passed by
# pointer, so they become ^T in Odin.
BY_POINTER = {
    "SignalDefinitions", "SlotDefinitions", "PropertyDefinitions",
    "SignalDefinition", "SlotDefinition", "PropertyDefinition",
    "ParameterDefinition", "QmlRegisterType", "DosQVariantArray",
    "DosQAbstractItemModelCallbacks",
}

# Function-pointer typedefs -- already a pointer, no ^ needed.
CALLBACKS = {
    "DObjectCallback", "RequestPixmapCallback", "RowCountCallback",
    "ColumnCountCallback", "DataCallback", "SetDataCallback",
    "RoleNamesCallback", "FlagsCallback", "HeaderDataCallback",
    "IndexCallback", "ParentCallback", "HasChildrenCallback",
    "CanFetchMoreCallback", "FetchMoreCallback", "CreateDObject",
    "DeleteDObject", "DosQObjectConnectLambdaCallback", "DosQMetaObjectInvokeMethodCallback",
}

ENUMS = {"DosQEventLoopProcessEventFlag", "DosQtConnectionType"}

ODIN_KEYWORDS = {
    "context", "in", "map", "matrix", "using", "when", "where", "proc",
    "struct", "union", "enum", "bit_set", "import", "package", "return",
    "defer", "cast", "auto_cast", "transmute", "distinct", "if", "else",
    "for", "switch", "case", "do", "break", "continue", "fallthrough",
}


def map_type(ctype: str):
    """Map one C type to Odin. Returns None if unmappable."""
    t = ctype.strip()
    t = re.sub(r"\bconst\b", " ", t)
    t = re.sub(r"\bstruct\b", " ", t)
    t = re.sub(r"\benum\b", " ", t)

    stars = t.count("*")
    base = t.replace("*", " ").strip()
    base = re.sub(r"\s+", " ", base)

    # char* is a C string, char** an array of them.
    if base == "char":
        if stars == 1:
            return "cstring"
        if stars == 2:
            return "[^]cstring"

    if base == "unsigned char" and stars == 1:
        return "[^]u8"

    if base == "void":
        if stars == 0:
            return ""
        if stars == 1:
            return "rawptr"
        if stars == 2:
            return "^rawptr"

    # Opaque handles: one star is the handle itself (the typedef is to
    # void), two stars is an array of handles.
    if base in OPAQUE:
        if stars == 1:
            return base
        if stars == 2:
            return f"[^]{base}"
        if stars == 0:
            return None

    if base in CALLBACKS and stars == 0:
        return base

    if base in ENUMS and stars == 0:
        return base

    if base in BY_POINTER:
        if stars == 1:
            return f"^{base}"
        if stars == 0:
            return base

    if base in SCALARS and stars == 0:
        return SCALARS[base]

    if base in SCALARS and stars == 1:
        return f"^{SCALARS[base]}"

    return None


def split_params(s: str):
    """Split a parameter list on commas not nested in parentheses."""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def parse_param(p: str, idx: int):
    p = p.strip()
    if not p or p == "void":
        return None
    # Trailing identifier is the name; everything before it is the type.
    m = re.match(r"^(.*?)(\w+)\s*$", p.replace("[]", "*"))
    if not m:
        return None
    ctype, name = m.group(1), m.group(2)
    # No name given, just a type (e.g. "int") -- synthesise one.
    if not ctype.strip():
        ctype, name = name, f"arg{idx}"
    odin = map_type(ctype)
    if odin is None or odin == "":
        return None
    name = re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()
    if name in ODIN_KEYWORDS:
        name = name + "_"
    return f"{name}: {odin}"


def main(path):
    src = open(path).read()
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)

    decls, buf = [], None
    for line in src.splitlines():
        line = line.strip()
        if buf is None:
            if line.startswith("DOS_API") and "#define" not in line:
                buf = line
        else:
            buf += " " + line
        if buf is not None and ";" in buf:
            decls.append(re.sub(r"\s+", " ", buf))
            buf = None

    print("package qml\n")
    print('import "core:c"\n')
    print('foreign import dos "system:DOtherSide"\n')
    print('@(default_calling_convention="c")')
    print("foreign dos {")

    ok = skipped = 0
    seen = set()
    for d in decls:
        m = re.match(r"DOS_API\s+(.*?)\s*DOS_CALL\s+(\w+)\s*\((.*)\)\s*;", d)
        if not m:
            continue
        ret_c, name, params_c = m.group(1), m.group(2), m.group(3)

        # DOtherSide.h declares a few functions twice (legal in C,
        # rejected by Odin). Keep the first occurrence.
        if name in seen:
            continue
        seen.add(name)

        ret = map_type(ret_c)
        if ret is None:
            print(f"\t// TODO unmapped return `{ret_c}`: {name}")
            skipped += 1
            continue

        params, bad = [], False
        for i, p in enumerate(split_params(params_c)):
            if p.strip() in ("", "void"):
                continue
            got = parse_param(p, i)
            if got is None:
                print(f"\t// TODO unmapped param `{p.strip()}`: {name}")
                bad = True
                break
            params.append(got)
        if bad:
            skipped += 1
            continue

        sig = f"\t{name} :: proc({', '.join(params)})"
        if ret:
            sig += f" -> {ret}"
        print(sig + " ---")
        ok += 1

    print("}")
    print(f"\n// generated: {ok} procs, {skipped} needing manual work",
          file=sys.stderr)
    print(f"generated {ok} procs, {skipped} need manual work", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
