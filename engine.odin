package qml

import "base:runtime"
import "core:strings"

// ---------------------------------------------------------------------
// Application and engine.
//
// Qt requires exactly one QGuiApplication per process, created before any
// other Qt object and destroyed last. App owns that lifetime along with a
// QQmlApplicationEngine.
// ---------------------------------------------------------------------

App :: struct {
	engine: DosQQmlApplicationEngine,
	exposed: [dynamic]^Object,
}

app_create :: proc() -> ^App {
	dos_qguiapplication_create()
	app := new(App)
	app.engine = dos_qqmlapplicationengine_create()
	app.exposed = make([dynamic]^Object)
	return app
}

// Destroys the engine, every exposed Object, and the application. Objects
// handed to app_expose are owned from here on -- do not also call
// object_destroy on them.
app_destroy :: proc(app: ^App) {
	if app == nil {
		return
	}
	// Engine first. It holds references to every exposed object, and
	// deleting an object while QML still has bindings on it produces
	// "disconnect from destroyed signal" warnings -- or worse, if the
	// object dies mid-session rather than at exit.
	dos_qqmlapplicationengine_delete(app.engine)
	for obj in app.exposed {
		object_destroy(obj)
	}
	delete(app.exposed)
	dos_qguiapplication_delete()
	free(app)
}

// Loads QML from a file path. The path is resolved against the process
// working directory, not the executable, so a binary loaded this way only
// runs from its source directory. Prefer app_load_source with #load for
// anything you intend to install.
app_load_file :: proc(app: ^App, path: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(path, context.temp_allocator)
	dos_qqmlapplicationengine_load(app.engine, cs)
}

// Loads QML from a string. Pair with #load to compile the UI into the
// executable:
//
//	UI :: #load("main.qml", string)
//	qml.app_load_source(app, UI)
app_load_source :: proc(app: ^App, source: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(source, context.temp_allocator)
	dos_qqmlapplicationengine_load_data(app.engine, cs)
}

// Adds a directory to the QML import path, for custom modules.
app_add_import_path :: proc(app: ^App, path: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(path, context.temp_allocator)
	dos_qqmlapplicationengine_add_import_path(app.engine, cs)
}

// Makes an Object visible to QML under the given name. Must be called
// before loading the QML, since bindings resolve at load time.
app_expose :: proc(app: ^App, name: string, obj: ^Object) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	ctx := dos_qqmlapplicationengine_context(app.engine)
	v := dos_qvariant_create_qobject(obj.qobject)
	defer dos_qvariant_delete(v)
	cs := strings.clone_to_cstring(name, context.temp_allocator)
	dos_qqmlcontext_setcontextproperty(ctx, cs, v)

	// app_destroy destroys everything in this list, so an object exposed
	// twice (under two names) must only be recorded once.
	for existing in app.exposed {
		if existing == obj {
			return
		}
	}
	append(&app.exposed, obj)
}

// Same, for a plain value rather than an object.
// The variant is copied into the context, so ownership stays with the
// caller: free it with variant_free once this returns.
app_expose_value :: proc(app: ^App, name: string, value: DosQVariant) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	ctx := dos_qqmlapplicationengine_context(app.engine)
	cs := strings.clone_to_cstring(name, context.temp_allocator)
	dos_qqmlcontext_setcontextproperty(ctx, cs, value)
}

// Enters Qt's event loop. Blocks until the last window closes.
app_run :: proc(app: ^App) {
	dos_qguiapplication_exec()
}

app_quit :: proc(app: ^App) {
	dos_qguiapplication_quit()
}

// Pumps pending Qt events once and returns immediately. Use instead of
// app_run when you want to drive your own main loop.
app_poll :: proc(app: ^App) {
	dos_qcoreapplication_process_events(.ProcessAllEvents)
}

// Sets the Qt Quick Controls style ("Material", "Fusion", "Basic", ...).
// Must be called before loading QML.
set_style :: proc(name: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	cs := strings.clone_to_cstring(name, context.temp_allocator)
	dos_qquickstyle_set_style(cs)
}
