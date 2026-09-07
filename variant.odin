package qml

import "base:runtime"
import "core:c"
import "core:strings"

// ---------------------------------------------------------------------
// QVariant helpers.
//
// QVariant is the box every value travels in when it crosses between Odin
// and QML. The raw dos_qvariant_* functions are usable directly; these
// wrappers exist mainly to handle two things the C API leaves to you:
// converting Odin strings to NUL-terminated cstrings, and freeing the
// heap-allocated char* that the to-string functions return.
// ---------------------------------------------------------------------

// Every variant_* constructor below returns a heap-allocated QVariant the
// caller owns and must release with variant_free. The ones Qt hands you --
// argv entries inside a slot -- are Qt's and must not be freed.
variant_new :: proc() -> DosQVariant {
	return dos_qvariant_create()
}

variant_int :: proc(v: int) -> DosQVariant {
	return dos_qvariant_create_int(c.int(v))
}

variant_bool :: proc(v: bool) -> DosQVariant {
	return dos_qvariant_create_bool(v)
}

variant_f64 :: proc(v: f64) -> DosQVariant {
	return dos_qvariant_create_double(v)
}

variant_i64 :: proc(v: i64) -> DosQVariant {
	return dos_qvariant_create_longlong(c.longlong(v))
}

// The cstring is copied into the QVariant by Qt, so the temporary
// allocation does not need to outlive this call.
variant_string :: proc(v: string) -> DosQVariant {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(v, context.temp_allocator)
	return dos_qvariant_create_string(cs)
}

variant_object :: proc(v: DosQObject) -> DosQVariant {
	return dos_qvariant_create_qobject(v)
}

variant_free :: proc(v: DosQVariant) {
	dos_qvariant_delete(v)
}

variant_is_null :: proc(v: DosQVariant) -> bool {
	return dos_qvariant_isnull(v)
}

// --- reading ---------------------------------------------------------

variant_to_int :: proc(v: DosQVariant) -> int {
	return int(dos_qvariant_toInt(v))
}

variant_to_bool :: proc(v: DosQVariant) -> bool {
	return dos_qvariant_toBool(v)
}

variant_to_f64 :: proc(v: DosQVariant) -> f64 {
	return dos_qvariant_toDouble(v)
}

variant_to_i64 :: proc(v: DosQVariant) -> i64 {
	return i64(dos_qvariant_toLongLong(v))
}

// Returns an Odin string owned by the caller. dos_qvariant_toString hands
// back heap memory that Qt expects you to release with
// dos_chararray_delete, so this copies and frees rather than leaking.
variant_to_string :: proc(v: DosQVariant, allocator := context.allocator) -> string {
	raw := dos_qvariant_toString(v)
	if raw == nil {
		return ""
	}
	defer dos_chararray_delete(raw)
	return strings.clone(string(raw), allocator)
}

// --- writing in place -------------------------------------------------
//
// Used to fill argv[0] inside a slot: the QVariant already exists and Qt
// reads it after the callback returns, so you assign into it rather than
// creating a new one.

variant_set_int :: proc(v: DosQVariant, value: int) {
	dos_qvariant_setInt(v, c.int(value))
}

variant_set_bool :: proc(v: DosQVariant, value: bool) {
	dos_qvariant_setBool(v, value)
}

variant_set_f64 :: proc(v: DosQVariant, value: f64) {
	dos_qvariant_setDouble(v, value)
}

variant_set_i64 :: proc(v: DosQVariant, value: i64) {
	dos_qvariant_setLongLong(v, c.longlong(value))
}

variant_set_string :: proc(v: DosQVariant, value: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(value, context.temp_allocator)
	dos_qvariant_setString(v, cs)
}

variant_set_object :: proc(v: DosQVariant, value: DosQObject) {
	dos_qvariant_setQObject(v, value)
}
