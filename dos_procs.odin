package qml

import "core:c"

foreign import dos "system:DOtherSide"

@(default_calling_convention="c")
foreign dos {
	dos_qcoreapplication_application_dir_path :: proc() -> cstring ---
	dos_qcoreapplication_process_events :: proc(flags: DosQEventLoopProcessEventFlag) ---
	dos_qcoreapplication_process_events_timed :: proc(flags: DosQEventLoopProcessEventFlag, ms: c.int) ---
	dos_qguiapplication_create :: proc() ---
	dos_qguiapplication_exec :: proc() ---
	dos_qguiapplication_quit :: proc() ---
	dos_qguiapplication_delete :: proc() ---
	dos_qapplication_create :: proc() ---
	dos_qapplication_exec :: proc() ---
	dos_qapplication_quit :: proc() ---
	dos_qapplication_delete :: proc() ---
	dos_qqmlapplicationengine_create :: proc() -> DosQQmlApplicationEngine ---
	dos_qqmlapplicationengine_load :: proc(vptr: DosQQmlApplicationEngine, filename: cstring) ---
	dos_qqmlapplicationengine_load_url :: proc(vptr: DosQQmlApplicationEngine, url: DosQUrl) ---
	dos_qqmlapplicationengine_load_data :: proc(vptr: DosQQmlApplicationEngine, data: cstring) ---
	dos_qqmlapplicationengine_add_import_path :: proc(vptr: DosQQmlApplicationEngine, path: cstring) ---
	dos_qqmlapplicationengine_context :: proc(vptr: DosQQmlApplicationEngine) -> DosQQmlContext ---
	dos_qqmlapplicationengine_addImageProvider :: proc(vptr: DosQQmlApplicationEngine, name: cstring, vptr_i: DosQQuickImageProvider) ---
	dos_qqmlapplicationengine_delete :: proc(vptr: DosQQmlApplicationEngine) ---
	dos_qquickimageprovider_create :: proc(callback: RequestPixmapCallback) -> DosQQuickImageProvider ---
	dos_qquickimageprovider_delete :: proc(vptr: DosQQuickImageProvider) ---
	dos_qpixmap_create :: proc() -> DosPixmap ---
	dos_qpixmap_create_qpixmap :: proc(other: DosPixmap) -> DosPixmap ---
	dos_qpixmap_create_width_and_height :: proc(width: c.int, height: c.int) -> DosPixmap ---
	dos_qpixmap_delete :: proc(vptr: DosPixmap) ---
	dos_qpixmap_load :: proc(vptr: DosPixmap, filepath: cstring, format: cstring) ---
	dos_qpixmap_loadFromData :: proc(vptr: DosPixmap, data: [^]u8, len: c.uint) ---
	dos_qpixmap_fill :: proc(vptr: DosPixmap, r: u8, g: u8, b: u8, a: u8) ---
	dos_qpixmap_assign :: proc(vptr: DosPixmap, other: DosPixmap) ---
	dos_qpixmap_isNull :: proc(vptr: DosPixmap) -> bool ---
	dos_qquickstyle_set_style :: proc(style: cstring) ---
	dos_qquickstyle_set_fallback_style :: proc(style: cstring) ---
	dos_qquickview_create :: proc() -> DosQQuickView ---
	dos_qquickview_show :: proc(vptr: DosQQuickView) ---
	dos_qquickview_source :: proc(vptr: DosQQuickView) -> cstring ---
	dos_qquickview_set_source_url :: proc(vptr: DosQQuickView, url: DosQUrl) ---
	dos_qquickview_set_source :: proc(vptr: DosQQuickView, filename: cstring) ---
	dos_qquickview_set_resize_mode :: proc(vptr: DosQQuickView, resize_mode: c.int) ---
	dos_qquickview_delete :: proc(vptr: DosQQuickView) ---
	dos_qquickview_rootContext :: proc(vptr: DosQQuickView) -> DosQQmlContext ---
	dos_qqmlcontext_baseUrl :: proc(vptr: DosQQmlContext) -> cstring ---
	dos_qqmlcontext_setcontextproperty :: proc(vptr: DosQQmlContext, name: cstring, value: DosQVariant) ---
	dos_chararray_delete :: proc(ptr: cstring) ---
	dos_qvariantarray_delete :: proc(ptr: ^DosQVariantArray) ---
	dos_qvariant_create :: proc() -> DosQVariant ---
	dos_qvariant_create_int :: proc(value: c.int) -> DosQVariant ---
	dos_qvariant_create_longlong :: proc(value: c.longlong) -> DosQVariant ---
	dos_qvariant_create_ulonglong :: proc(value: c.ulonglong) -> DosQVariant ---
	dos_qvariant_create_bool :: proc(value: bool) -> DosQVariant ---
	dos_qvariant_create_string :: proc(value: cstring) -> DosQVariant ---
	dos_qvariant_create_qobject :: proc(value: DosQObject) -> DosQVariant ---
	dos_qvariant_create_qvariant :: proc(value: DosQVariant) -> DosQVariant ---
	dos_qvariant_create_float :: proc(value: f32) -> DosQVariant ---
	dos_qvariant_create_double :: proc(value: f64) -> DosQVariant ---
	dos_qvariant_create_array :: proc(size: c.int, array: [^]DosQVariant) -> DosQVariant ---
	dos_qvariant_setInt :: proc(vptr: DosQVariant, value: c.int) ---
	dos_qvariant_setLongLong :: proc(vptr: DosQVariant, value: c.longlong) ---
	dos_qvariant_setULongLong :: proc(vptr: DosQVariant, value: c.ulonglong) ---
	dos_qvariant_setBool :: proc(vptr: DosQVariant, value: bool) ---
	dos_qvariant_setFloat :: proc(vptr: DosQVariant, value: f32) ---
	dos_qvariant_setDouble :: proc(vptr: DosQVariant, value: f64) ---
	dos_qvariant_setString :: proc(vptr: DosQVariant, value: cstring) ---
	dos_qvariant_setQObject :: proc(vptr: DosQVariant, value: DosQObject) ---
	dos_qvariant_setArray :: proc(vptr: DosQVariant, size: c.int, array: [^]DosQVariant) ---
	dos_qvariant_isnull :: proc(vptr: DosQVariant) -> bool ---
	dos_qvariant_delete :: proc(vptr: DosQVariant) ---
	dos_qvariant_assign :: proc(vptr: DosQVariant, other: DosQVariant) ---
	dos_qvariant_toInt :: proc(vptr: DosQVariant) -> c.int ---
	dos_qvariant_toLongLong :: proc(vptr: DosQVariant) -> c.longlong ---
	dos_qvariant_toULongLong :: proc(vptr: DosQVariant) -> c.ulonglong ---
	dos_qvariant_toBool :: proc(vptr: DosQVariant) -> bool ---
	dos_qvariant_toString :: proc(vptr: DosQVariant) -> cstring ---
	dos_qvariant_toFloat :: proc(vptr: DosQVariant) -> f32 ---
	dos_qvariant_toDouble :: proc(vptr: DosQVariant) -> f64 ---
	dos_qvariant_toArray :: proc(vptr: DosQVariant) -> ^DosQVariantArray ---
	dos_qvariant_toQObject :: proc(vptr: DosQVariant) -> DosQObject ---
	dos_qmetaobject_create :: proc(super_class_meta_object: DosQMetaObject, class_name: cstring, signal_definitions: ^SignalDefinitions, slot_definitions: ^SlotDefinitions, property_definitions: ^PropertyDefinitions) -> DosQMetaObject ---
	dos_qmetaobject_delete :: proc(vptr: DosQMetaObject) ---
	dos_qmetaobject_invoke_method :: proc(context_: DosQObject, callback: DosQMetaObjectInvokeMethodCallback, callback_data: rawptr, connection_type: DosQtConnectionType) -> bool ---
	dos_qabstractlistmodel_qmetaobject :: proc() -> DosQMetaObject ---
	dos_qabstractlistmodel_create :: proc(callback_object: rawptr, meta_object: DosQMetaObject, d_object_callback: DObjectCallback, callbacks: ^DosQAbstractItemModelCallbacks) -> DosQAbstractListModel ---
	dos_qabstractlistmodel_index :: proc(vptr: DosQAbstractListModel, row: c.int, column: c.int, parent: DosQModelIndex) -> DosQModelIndex ---
	dos_qabstractlistmodel_parent :: proc(vptr: DosQAbstractListModel, child: DosQModelIndex) -> DosQModelIndex ---
	dos_qabstractlistmodel_columnCount :: proc(vptr: DosQAbstractListModel, parent: DosQModelIndex) -> c.int ---
	dos_qabstracttablemodel_qmetaobject :: proc() -> DosQMetaObject ---
	dos_qabstracttablemodel_create :: proc(callback_object: rawptr, meta_object: DosQMetaObject, d_object_callback: DObjectCallback, callbacks: ^DosQAbstractItemModelCallbacks) -> DosQAbstractTableModel ---
	dos_qabstracttablemodel_index :: proc(vptr: DosQAbstractTableModel, row: c.int, column: c.int, parent: DosQModelIndex) -> DosQModelIndex ---
	dos_qabstracttablemodel_parent :: proc(vptr: DosQAbstractTableModel, child: DosQModelIndex) -> DosQModelIndex ---
	dos_qabstractitemmodel_qmetaobject :: proc() -> DosQMetaObject ---
	dos_qabstractitemmodel_create :: proc(callback_object: rawptr, meta_object: DosQMetaObject, d_object_callback: DObjectCallback, callbacks: ^DosQAbstractItemModelCallbacks) -> DosQAbstractItemModel ---
	dos_qabstractitemmodel_setData :: proc(vptr: DosQAbstractItemModel, index: DosQModelIndex, data: DosQVariant, role: c.int) -> bool ---
	dos_qabstractitemmodel_roleNames :: proc(vptr: DosQAbstractItemModel) -> DosQHashIntQByteArray ---
	dos_qabstractitemmodel_flags :: proc(vptr: DosQAbstractItemModel, index: DosQModelIndex) -> c.int ---
	dos_qabstractitemmodel_headerData :: proc(vptr: DosQAbstractItemModel, section: c.int, orientation: c.int, role: c.int) -> DosQVariant ---
	dos_qabstractitemmodel_hasChildren :: proc(vptr: DosQAbstractItemModel, parent_index: DosQModelIndex) -> bool ---
	dos_qabstractitemmodel_hasIndex :: proc(vptr: DosQAbstractItemModel, row: c.int, column: c.int, dos_parent_index: DosQModelIndex) -> bool ---
	dos_qabstractitemmodel_canFetchMore :: proc(vptr: DosQAbstractItemModel, parent_index: DosQModelIndex) -> bool ---
	dos_qabstractitemmodel_fetchMore :: proc(vptr: DosQAbstractItemModel, parent_index: DosQModelIndex) ---
	dos_qabstractitemmodel_beginInsertRows :: proc(vptr: DosQAbstractItemModel, parent: DosQModelIndex, first: c.int, last: c.int) ---
	dos_qabstractitemmodel_endInsertRows :: proc(vptr: DosQAbstractItemModel) ---
	dos_qabstractitemmodel_beginRemoveRows :: proc(vptr: DosQAbstractItemModel, parent: DosQModelIndex, first: c.int, last: c.int) ---
	dos_qabstractitemmodel_endRemoveRows :: proc(vptr: DosQAbstractItemModel) ---
	dos_qabstractitemmodel_beginInsertColumns :: proc(vptr: DosQAbstractItemModel, parent: DosQModelIndex, first: c.int, last: c.int) ---
	dos_qabstractitemmodel_endInsertColumns :: proc(vptr: DosQAbstractItemModel) ---
	dos_qabstractitemmodel_beginRemoveColumns :: proc(vptr: DosQAbstractItemModel, parent: DosQModelIndex, first: c.int, last: c.int) ---
	dos_qabstractitemmodel_endRemoveColumns :: proc(vptr: DosQAbstractItemModel) ---
	dos_qabstractitemmodel_beginResetModel :: proc(vptr: DosQAbstractItemModel) ---
	dos_qabstractitemmodel_endResetModel :: proc(vptr: DosQAbstractItemModel) ---
	dos_qabstractitemmodel_dataChanged :: proc(vptr: DosQAbstractItemModel, top_left: DosQModelIndex, bottom_right: DosQModelIndex, roles_ptr: ^c.int, roles_length: c.int) ---
	dos_qabstractitemmodel_createIndex :: proc(vptr: DosQAbstractItemModel, row: c.int, column: c.int, data: rawptr) -> DosQModelIndex ---
	dos_qobject_qmetaobject :: proc() -> DosQMetaObject ---
	dos_qobject_create :: proc(d_object_pointer: rawptr, meta_object: DosQMetaObject, d_object_callback: DObjectCallback) -> DosQObject ---
	dos_qobject_signal_emit :: proc(vptr: DosQObject, name: cstring, parameters_count: c.int, parameters: [^]DosQVariant) ---
	dos_qobject_objectName :: proc(vptr: DosQObject) -> cstring ---
	dos_qobject_setObjectName :: proc(vptr: DosQObject, name: cstring) ---
	dos_qobject_delete :: proc(vptr: DosQObject) ---
	dos_qobject_deleteLater :: proc(vptr: DosQObject) ---
	dos_qobject_property :: proc(vptr: DosQObject, property_name: cstring) -> DosQVariant ---
	dos_qobject_setProperty :: proc(vptr: DosQObject, property_name: cstring, value: DosQVariant) -> bool ---
	dos_slot_macro :: proc(str: cstring) -> cstring ---
	dos_signal_macro :: proc(str: cstring) -> cstring ---
	dos_qobject_connect_lambda_static :: proc(sender: DosQObject, signal: cstring, callback: DosQObjectConnectLambdaCallback, callback_data: rawptr, connection_type: DosQtConnectionType) -> DosQMetaObjectConnection ---
	dos_qobject_connect_lambda_with_context_static :: proc(sender: DosQObject, signal: cstring, context_: DosQObject, callback: DosQObjectConnectLambdaCallback, callback_data: rawptr, connection_type: DosQtConnectionType) -> DosQMetaObjectConnection ---
	dos_qobject_connect_static :: proc(sender: DosQObject, signal: cstring, receiver: DosQObject, slot: cstring, connection_type: DosQtConnectionType) -> DosQMetaObjectConnection ---
	dos_qobject_disconnect_static :: proc(sender: DosQObject, signal: cstring, receiver: DosQObject, slot: cstring) ---
	dos_qobject_disconnect_with_connection_static :: proc(connection: DosQMetaObjectConnection) ---
	dos_qmetaobject_connection_delete :: proc(self: DosQMetaObjectConnection) ---
	dos_qmodelindex_create :: proc() -> DosQModelIndex ---
	dos_qmodelindex_create_qmodelindex :: proc(index: DosQModelIndex) -> DosQModelIndex ---
	dos_qmodelindex_delete :: proc(vptr: DosQModelIndex) ---
	dos_qmodelindex_row :: proc(vptr: DosQModelIndex) -> c.int ---
	dos_qmodelindex_column :: proc(vptr: DosQModelIndex) -> c.int ---
	dos_qmodelindex_isValid :: proc(vptr: DosQModelIndex) -> bool ---
	dos_qmodelindex_data :: proc(vptr: DosQModelIndex, role: c.int) -> DosQVariant ---
	dos_qmodelindex_parent :: proc(vptr: DosQModelIndex) -> DosQModelIndex ---
	dos_qmodelindex_child :: proc(vptr: DosQModelIndex, row: c.int, column: c.int) -> DosQModelIndex ---
	dos_qmodelindex_sibling :: proc(vptr: DosQModelIndex, row: c.int, column: c.int) -> DosQModelIndex ---
	dos_qmodelindex_assign :: proc(l: DosQModelIndex, r: DosQModelIndex) ---
	dos_qmodelindex_internalPointer :: proc(vptr: DosQModelIndex) -> rawptr ---
	dos_qhash_int_qbytearray_create :: proc() -> DosQHashIntQByteArray ---
	dos_qhash_int_qbytearray_delete :: proc(vptr: DosQHashIntQByteArray) ---
	dos_qhash_int_qbytearray_insert :: proc(vptr: DosQHashIntQByteArray, key: c.int, value: cstring) ---
	dos_qhash_int_qbytearray_value :: proc(vptr: DosQHashIntQByteArray, key: c.int) -> cstring ---
	dos_qresource_register :: proc(filename: cstring) ---
	dos_qurl_create :: proc(url: cstring, parsing_mode: c.int) -> DosQUrl ---
	dos_qurl_delete :: proc(vptr: DosQUrl) ---
	dos_qurl_to_string :: proc(vptr: DosQUrl) -> cstring ---
	dos_qurl_isValid :: proc(vptr: DosQUrl) -> bool ---
	dos_qdeclarative_qmlregistertype :: proc(qml_register_type: ^QmlRegisterType) -> c.int ---
	dos_qdeclarative_qmlregistersingletontype :: proc(qml_register_type: ^QmlRegisterType) -> c.int ---
	dos_qpointer_create :: proc(object: DosQObject) -> DosQPointer ---
	dos_qpointer_delete :: proc(self: DosQPointer) ---
	dos_qpointer_is_null :: proc(self: DosQPointer) -> bool ---
	dos_qpointer_clear :: proc(self: DosQPointer) ---
	dos_qpointer_data :: proc(self: DosQPointer) -> DosQObject ---
}
