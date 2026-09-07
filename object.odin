package qml

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------
// QObject layer.
//
// This is the part that makes QML useful: exposing Odin state as
// properties QML can bind to, slots QML can call, and signals that push
// updates back.
//
// Qt normally learns about an object's properties and methods from tables
// that `moc` generates at compile time. DOtherSide instead builds those
// tables at runtime from the definition structs in types.odin -- which is
// the only reason any of this is possible from a non-C++ language.
//
// Everything funnels through one callback. Qt does not call your slot
// directly; it calls `dispatch` with the slot's name boxed in a QVariant,
// and dispatch looks it up. Property reads and writes are slots too, so
// they arrive the same way.
// ---------------------------------------------------------------------

// A slot implementation.
//
//	obj    - the Object being called; obj.data is your own struct
//	args   - the slot's arguments, already unboxed from argv[1:]
//	result - write your return value here with variant_set_*; ignore for
//	         slots declared .Void
Slot_Proc :: proc(obj: ^Object, args: []DosQVariant, result: DosQVariant)

// --- class description ------------------------------------------------
//
// A Class is a description you build up and then hand to object_new. It
// owns nothing at runtime; after the object exists you can destroy it.

Signal_Desc :: struct {
	name:   string,
	params: []MetaType,
}

Slot_Desc :: struct {
	name:   string,
	ret:    MetaType,
	params: []MetaType,
	fn:     Slot_Proc,
}

Prop_Desc :: struct {
	name:   string,
	type:   MetaType,
	read:   string,
	write:  string,
	notify: string,
}

Class :: struct {
	name:    string,
	signals: [dynamic]Signal_Desc,
	slots:   [dynamic]Slot_Desc,
	props:   [dynamic]Prop_Desc,
}

class_make :: proc(name: string) -> Class {
	return Class {
		name = name,
		signals = make([dynamic]Signal_Desc),
		slots = make([dynamic]Slot_Desc),
		props = make([dynamic]Prop_Desc),
	}
}

class_destroy :: proc(cl: ^Class) {
	delete(cl.signals)
	delete(cl.slots)
	delete(cl.props)
}

class_signal :: proc(cl: ^Class, name: string, params: []MetaType = nil) {
	append(&cl.signals, Signal_Desc{name = name, params = params})
}

class_slot :: proc(
	cl: ^Class,
	name: string,
	fn: Slot_Proc,
	ret: MetaType = .Void,
	params: []MetaType = nil,
) {
	append(&cl.slots, Slot_Desc{name = name, ret = ret, params = params, fn = fn})
}

// A property needs a read slot; write and notify are optional. Omitting
// write makes it read-only from QML. Omitting notify means QML bindings
// will not update when the value changes -- almost always a mistake.
class_property :: proc(
	cl: ^Class,
	name: string,
	type: MetaType,
	read: string,
	write: string = "",
	notify: string = "",
) {
	append(
		&cl.props,
		Prop_Desc{name = name, type = type, read = read, write = write, notify = notify},
	)
}

// --- the object -------------------------------------------------------

Object :: struct {
	qobject:    DosQObject,
	metaobject: DosQMetaObject,
	data:       rawptr, // your struct; dispatch hands it back to you
	handlers:   map[string]Slot_Proc,

	// Called by object_destroy before anything else is released, so a
	// type that embeds an Object as its first field can free its own
	// allocations without engine.odin knowing the type exists. List_Model
	// uses this; leave it nil otherwise.
	on_destroy: proc(obj: ^Object),
}

@(private)
opt_cstring :: proc(pool: ^[dynamic]cstring, s: string) -> cstring {
	if len(s) == 0 {
		return nil
	}
	cs := strings.clone_to_cstring(s)
	append(pool, cs)
	return cs
}

// Builds the runtime metaobject and instantiates the QObject.
//
// `data` is an opaque pointer stored on the Object and handed back to
// every slot; point it at your own state struct.
//
// Returns nil if the class is unusable or Qt refuses to build the
// metaobject. Both are programmer errors rather than runtime conditions,
// so they are reported on stderr as well.
object_new :: proc(cl: ^Class, data: rawptr = nil) -> ^Object {
	obj := new(Object)
	if !object_init(obj, cl, data) {
		free(obj)
		return nil
	}
	return obj
}

// The shared half of object_new, split out so `model.odin` can reuse it:
// a model is an Object whose metaobject derives from QAbstractListModel
// rather than QObject, and whose instantiation takes a callbacks struct.
// Nothing else about it differs.
//
//	obj       - already allocated and zeroed; the caller frees it on failure
//	super     - superclass metaobject; nil means plain QObject
//	model_cbs - non-nil instantiates a QAbstractListModel instead
//
// `obj` is what Qt hands back to every callback, so a struct embedding an
// Object must keep it as its *first* field: the same pointer is cast to
// ^Object by dispatch and to the outer type by the model callbacks.
object_init :: proc(
	obj: ^Object,
	cl: ^Class,
	data: rawptr = nil,
	super: DosQMetaObject = nil,
	model_cbs: ^DosQAbstractItemModelCallbacks = nil,
) -> bool {
	// tprintf below allocates in the temp allocator; the mark/release
	// guard hands that memory back on return instead of relying on the
	// caller ever calling free_all.
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	if cl == nil || len(cl.name) == 0 {
		// An empty name would reach dos_qmetaobject_create as a nil
		// class_name, which Qt dereferences.
		fmt.eprintln("odin-qml: object_init needs a Class with a non-empty name")
		return false
	}

	obj.data = data
	obj.handlers = make(map[string]Slot_Proc)

	// DOtherSide copies these into C++ vectors inside
	// dos_qmetaobject_create, so everything allocated here can be freed
	// as soon as that call returns.
	strs := make([dynamic]cstring)
	params_pool := make([dynamic][]ParameterDefinition)
	defer {
		for s in strs {
			delete(s)
		}
		delete(strs)
		for p in params_pool {
			delete(p)
		}
		delete(params_pool)
	}

	build_params :: proc(
		pool: ^[dynamic][]ParameterDefinition,
		strs: ^[dynamic]cstring,
		types: []MetaType,
	) -> [^]ParameterDefinition {
		if len(types) == 0 {
			return nil
		}
		out := make([]ParameterDefinition, len(types))
		for t, i in types {
			out[i] = ParameterDefinition {
				name     = opt_cstring(strs, fmt.tprintf("arg%d", i)),
				metaType = c.int(t),
			}
		}
		append(pool, out)
		return raw_data(out)
	}

	sig_defs := make([]SignalDefinition, len(cl.signals))
	defer delete(sig_defs)
	for s, i in cl.signals {
		sig_defs[i] = SignalDefinition {
			name            = opt_cstring(&strs, s.name),
			parametersCount = c.int(len(s.params)),
			parameters      = build_params(&params_pool, &strs, s.params),
		}
	}

	slot_defs := make([]SlotDefinition, len(cl.slots))
	defer delete(slot_defs)
	for s, i in cl.slots {
		slot_defs[i] = SlotDefinition {
			name            = opt_cstring(&strs, s.name),
			returnMetaType  = c.int(s.ret),
			parametersCount = c.int(len(s.params)),
			parameters      = build_params(&params_pool, &strs, s.params),
		}
	}

	prop_defs := make([]PropertyDefinition, len(cl.props))
	defer delete(prop_defs)
	for p, i in cl.props {
		prop_defs[i] = PropertyDefinition {
			name             = opt_cstring(&strs, p.name),
			propertyMetaType = c.int(p.type),
			readSlot         = opt_cstring(&strs, p.read),
			writeSlot        = opt_cstring(&strs, p.write),
			notifySignal     = opt_cstring(&strs, p.notify),
		}
	}

	signals := SignalDefinitions {
		count       = c.int(len(sig_defs)),
		definitions = raw_data(sig_defs),
	}
	slots := SlotDefinitions {
		count       = c.int(len(slot_defs)),
		definitions = raw_data(slot_defs),
	}
	props := PropertyDefinitions {
		count       = c.int(len(prop_defs)),
		definitions = raw_data(prop_defs),
	}

	// Handler names are cloned: the Class may be destroyed while the
	// Object lives on.
	for s in cl.slots {
		// Assigning to an existing key keeps the original key string, so
		// a duplicate name would leak its clone. Overwrite in place.
		if _, exists := obj.handlers[s.name]; exists {
			obj.handlers[s.name] = s.fn
		} else {
			obj.handlers[strings.clone(s.name)] = s.fn
		}
	}

	super_mo := super
	if super_mo == nil {
		super_mo = dos_qobject_qmetaobject()
	}

	class_name := opt_cstring(&strs, cl.name)
	obj.metaobject = dos_qmetaobject_create(
		super_mo,
		class_name,
		&signals,
		&slots,
		&props,
	)
	if obj.metaobject == nil {
		fmt.eprintfln("odin-qml: could not build a metaobject for %q", cl.name)
		object_free_handlers(obj)
		return false
	}

	if model_cbs != nil {
		// The model handle is a QObject underneath -- QAbstractListModel
		// derives from it, and DOtherSide's own delete for a model is
		// dos_qobject_delete.
		obj.qobject = cast(DosQObject)dos_qabstractlistmodel_create(
			obj,
			obj.metaobject,
			dispatch,
			model_cbs,
		)
	} else {
		obj.qobject = dos_qobject_create(obj, obj.metaobject, dispatch)
	}
	if obj.qobject == nil {
		fmt.eprintfln("odin-qml: could not instantiate %q", cl.name)
		dos_qmetaobject_delete(obj.metaobject)
		obj.metaobject = nil
		object_free_handlers(obj)
		return false
	}
	return true
}

// Releases the Odin-side allocations object_init made, leaving the Object
// itself to its owner -- which is object_new on the failure path and
// object_destroy at the end of its life.
@(private)
object_free_handlers :: proc(obj: ^Object) {
	for k in obj.handlers {
		delete(k)
	}
	delete(obj.handlers)
	obj.handlers = nil
}

// Destroys the QObject and everything object_new allocated. Do not call
// this on an object passed to app_expose -- app_destroy owns those.
object_destroy :: proc(obj: ^Object) {
	if obj == nil {
		return
	}
	if obj.on_destroy != nil {
		obj.on_destroy(obj)
	}
	// A QAbstractListModel is a QObject; DOtherSide has no separate
	// delete for it, and this is the call nimqml makes too.
	dos_qobject_delete(obj.qobject)
	dos_qmetaobject_delete(obj.metaobject)
	object_free_handlers(obj)
	free(obj)
}

// Emits a signal. QML property bindings that depend on a property whose
// notify signal this is will re-evaluate.
object_emit :: proc(obj: ^Object, signal: string, args: ..DosQVariant) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(signal, context.temp_allocator)
	if len(args) == 0 {
		dos_qobject_signal_emit(obj.qobject, cs, 0, nil)
	} else {
		dos_qobject_signal_emit(obj.qobject, cs, c.int(len(args)), raw_data(args))
	}
}

// --- dispatch ---------------------------------------------------------

// Every slot call, property read and property write from QML arrives
// here.
//
// The "c" calling convention strips Odin's implicit context pointer, so
// the first statement has to put one back before anything allocates.
// Omitting it is the single most common way to crash an Odin FFI
// callback.
//
// DOtherSide builds argv as [result, arg0, arg1, ...] -- argv[0] is the
// QVariant to write a return value into, and argc counts it.
@(private)
dispatch :: proc "c" (
	self: rawptr,
	slot_name: DosQVariant,
	argc: c.int,
	argv: [^]DosQVariant,
) {
	context = runtime.default_context()
	// Qt calls this for the life of the process. Without a mark/release
	// around it, every temp allocation a slot makes -- including the ones
	// object_emit and variant_string make -- accumulates in the temp arena
	// until exit. The guard is a mark/release rather than a free_all so
	// that a nested dispatch (a slot emits a signal, QML reacts by calling
	// another slot) cannot free the outer call's temp memory.
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	obj := cast(^Object)self
	if obj == nil || argc < 1 {
		return
	}

	raw := dos_qvariant_toString(slot_name)
	if raw == nil {
		return
	}
	defer dos_chararray_delete(raw)

	fn, found := obj.handlers[string(raw)]
	if !found {
		// A typo in a slot or property name lands here. QML will not
		// report it, so say something.
		fmt.eprintfln("odin-qml: no handler for slot %q", string(raw))
		return
	}

	args: []DosQVariant
	if argc > 1 {
		args = argv[1:argc]
	}
	fn(obj, args, argv[0])
}

// --- connections ------------------------------------------------------
//
// Connecting to a signal from Odin rather than from QML. The handle Qt
// returns is heap-allocated on the C++ side and has to be released, which
// is easy to miss because disconnecting is not the same thing as freeing:
// dos_qobject_disconnect_with_connection_static breaks the connection but
// leaves the handle allocated. Connection pairs both into one call.

Connection :: struct {
	handle: DosQMetaObjectConnection,
}

// The callback runs with no Odin context, exactly like a slot -- restore
// one with `context = runtime.default_context()` before allocating.
//
// `data` is passed straight back to the callback. It must outlive the
// connection; a pointer to a stack local in the calling procedure will not.
connect :: proc(
	obj: ^Object,
	signal: string,
	callback: DosQObjectConnectLambdaCallback,
	data: rawptr = nil,
	type: DosQtConnectionType = .AutoConnection,
) -> Connection {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(signal, context.temp_allocator)
	handle := dos_qobject_connect_lambda_static(obj.qobject, cs, callback, data, type)
	return Connection{handle = handle}
}

// Breaks the connection and frees its handle. Safe to call more than once
// and safe after the sender is gone -- Qt's connection object outlives the
// objects it referred to.
disconnect :: proc(conn: ^Connection) {
	if conn == nil || conn.handle == nil {
		return
	}
	dos_qobject_disconnect_with_connection_static(conn.handle)
	dos_qmetaobject_connection_delete(conn.handle)
	conn.handle = nil
}
