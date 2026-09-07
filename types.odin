package qml

import "core:c"

// ---------------------------------------------------------------------
// Opaque handles.
//
// DOtherSide declares all of these as `typedef void DosFoo;` so that in C
// every one of them is just `void *`. Making them `distinct` here costs
// nothing at runtime but means Odin will reject passing a DosQVariant
// where a DosQObject was wanted -- a mistake C would have accepted
// silently and paid for with a segfault.
// ---------------------------------------------------------------------

DosQVariant              :: distinct rawptr
DosQModelIndex           :: distinct rawptr
DosQAbstractItemModel    :: distinct rawptr
DosQAbstractListModel    :: distinct rawptr
DosQAbstractTableModel   :: distinct rawptr
DosQQmlApplicationEngine :: distinct rawptr
DosQQuickView            :: distinct rawptr
DosQQmlContext           :: distinct rawptr
DosQHashIntQByteArray    :: distinct rawptr
DosQUrl                  :: distinct rawptr
DosQMetaObject           :: distinct rawptr
DosQObject               :: distinct rawptr
DosQQuickImageProvider   :: distinct rawptr
DosPixmap                :: distinct rawptr
DosQPointer              :: distinct rawptr
DosQMetaObjectConnection :: distinct rawptr

// ---------------------------------------------------------------------
// Callbacks.
//
// The "c" calling convention is mandatory. Odin's native convention
// passes a hidden `context` pointer that C knows nothing about; declaring
// "c" removes it. The flip side is that inside these procedures there is
// no context, so `context = runtime.default_context()` must be the first
// statement before anything allocates, prints or appends.
// ---------------------------------------------------------------------

DObjectCallback :: proc "c" (
	self:      rawptr,
	slot_name: DosQVariant,
	argc:      c.int,
	argv:      [^]DosQVariant,
)

RequestPixmapCallback :: proc "c" (
	id:              cstring,
	width:           ^c.int,
	height:          ^c.int,
	requested_width: c.int,
	requested_height: c.int,
	result:          DosPixmap,
)

RowCountCallback     :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^c.int)
ColumnCountCallback  :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^c.int)
DataCallback         :: proc "c" (self: rawptr, index: DosQModelIndex, role: c.int, result: DosQVariant)
SetDataCallback      :: proc "c" (self: rawptr, index: DosQModelIndex, value: DosQVariant, role: c.int, result: ^bool)
RoleNamesCallback    :: proc "c" (self: rawptr, result: DosQHashIntQByteArray)
FlagsCallback        :: proc "c" (self: rawptr, index: DosQModelIndex, result: ^c.int)
HeaderDataCallback   :: proc "c" (self: rawptr, section: c.int, orientation: c.int, role: c.int, result: DosQVariant)
IndexCallback        :: proc "c" (self: rawptr, row: c.int, column: c.int, parent: DosQModelIndex, result: DosQModelIndex)
ParentCallback       :: proc "c" (self: rawptr, child: DosQModelIndex, result: DosQModelIndex)
HasChildrenCallback  :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^bool)
CanFetchMoreCallback :: proc "c" (self: rawptr, parent: DosQModelIndex, result: ^bool)
FetchMoreCallback    :: proc "c" (self: rawptr, parent: DosQModelIndex)

CreateDObject :: proc "c" (id: c.int, wrapper: rawptr, binded_qobject: ^rawptr, dos_qobject: ^rawptr)
DeleteDObject :: proc "c" (id: c.int, binded_qobject: rawptr)

DosQObjectConnectLambdaCallback    :: proc "c" (callback_data: rawptr, argc: c.int, argv: [^]DosQVariant)
DosQMetaObjectInvokeMethodCallback :: proc "c" (callback_data: rawptr)

// ---------------------------------------------------------------------
// Metaobject definition structs.
//
// These are the only structs whose memory layout has to match C exactly,
// because DOtherSide walks them field by field to build the QMetaObject.
// Odin lays fields out in declaration order with natural alignment, which
// happens to match what C does here -- including the 4 bytes of padding
// after each `c.int` that precedes a pointer. Do not reorder fields.
// ---------------------------------------------------------------------

ParameterDefinition :: struct {
	name:     cstring,
	metaType: c.int,
}

SignalDefinition :: struct {
	name:            cstring,
	parametersCount: c.int,
	parameters:      [^]ParameterDefinition,
}

SignalDefinitions :: struct {
	count:       c.int,
	definitions: [^]SignalDefinition,
}

SlotDefinition :: struct {
	name:            cstring,
	returnMetaType:  c.int,
	parametersCount: c.int,
	parameters:      [^]ParameterDefinition,
}

SlotDefinitions :: struct {
	count:       c.int,
	definitions: [^]SlotDefinition,
}

PropertyDefinition :: struct {
	name:             cstring,
	propertyMetaType: c.int,
	readSlot:         cstring,
	writeSlot:        cstring,
	notifySignal:     cstring,
}

PropertyDefinitions :: struct {
	count:       c.int,
	definitions: [^]PropertyDefinition,
}

DosQVariantArray :: struct {
	size: c.int,
	data: [^]DosQVariant,
}

QmlRegisterType :: struct {
	major:            c.int,
	minor:            c.int,
	uri:              cstring,
	qml:              cstring,
	staticMetaObject: DosQMetaObject,
	createDObject:    CreateDObject,
	deleteDObject:    DeleteDObject,
}

DosQAbstractItemModelCallbacks :: struct {
	rowCount:     RowCountCallback,
	columnCount:  ColumnCountCallback,
	data:         DataCallback,
	setData:      SetDataCallback,
	roleNames:    RoleNamesCallback,
	flags:        FlagsCallback,
	headerData:   HeaderDataCallback,
	index:        IndexCallback,
	parent:       ParentCallback,
	hasChildren:  HasChildrenCallback,
	canFetchMore: CanFetchMoreCallback,
	fetchMore:    FetchMoreCallback,
}

// ---------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------

DosQEventLoopProcessEventFlag :: enum c.int {
	ProcessAllEvents                  = 0x00,
	ExcludeUserInputEvents            = 0x01,
	ProcessExcludeSocketNotifiers     = 0x02,
	ProcessAllEventsWaitForMoreEvents = 0x03,
}

DosQtConnectionType :: enum c.int {
	AutoConnection     = 0,
	DirectConnection   = 1,
	QueuedConnection   = 2,
	BlockingConnection = 3,
	UniqueConnection   = 0x80,
}

// ---------------------------------------------------------------------
// QMetaType ids.
//
// These are Qt's own numbers from QMetaType::Type, not DOtherSide's. They
// are stable across Qt 5 and 6 for the basic types, but verify against
// your qmetatype.h before trusting anything beyond this list:
//   /usr/include/qt6/QtCore/qmetatype.h
// ---------------------------------------------------------------------

MetaType :: enum c.int {
	UnknownType = 0,
	Bool        = 1,
	Int         = 2,
	UInt        = 3,
	LongLong    = 4,
	ULongLong   = 5,
	Double      = 6,
	QChar       = 7,
	QVariantMap = 8,
	QVariantList = 9,
	QString     = 10,
	QStringList = 11,
	QByteArray  = 12,
	Float       = 38,
	Void        = 43,
	QObjectStar = 39,
}
