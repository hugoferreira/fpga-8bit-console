#ifndef INLAY_H
#define INLAY_H

#include <stddef.h>

typedef unsigned char la_u8;
typedef unsigned short la_u16;
typedef unsigned long la_u32;
typedef signed long la_i32;

#define LA_INVALID_HANDLE ((la_u16)0xffff)
#define LA_FORMAT_VERSION 1
#define LA_TARGET_VERSION 1

typedef struct {
    const char *data;
    la_u16 length;
} LaSlice;

typedef struct {
    la_u16 source_id;
    la_u16 line;
    la_u16 column;
    la_u16 length;
} LaSpan;

typedef enum {
    LA_OK = 0,
    LA_ERR_WORKSPACE,
    LA_ERR_SOURCE_CAPACITY,
    LA_ERR_TOKEN_CAPACITY,
    LA_ERR_NAME_CAPACITY,
    LA_ERR_STRUCT_CAPACITY,
    LA_ERR_FIELD_CAPACITY,
    LA_ERR_LOCATION_CAPACITY,
    LA_ERR_EXPRESSION_CAPACITY,
    LA_ERR_NESTING_CAPACITY,
    LA_ERR_OPERATION_CAPACITY,
    LA_ERR_SYNTAX,
    LA_ERR_DUPLICATE_STRUCT,
    LA_ERR_DUPLICATE_FIELD,
    LA_ERR_UNKNOWN_TYPE,
    LA_ERR_LAYOUT_CYCLE,
    LA_ERR_UNKNOWN_FIELD,
    LA_ERR_BAD_PROPERTY,
    LA_ERR_ASSERTION,
    LA_ERR_DUPLICATE_LOCATION,
    LA_ERR_LOCATION_TYPE,
    LA_ERR_UNSUPPORTED_OPERATION,
    LA_ERR_ACCESS_WIDTH,
    LA_ERR_DISPLACEMENT,
    LA_ERR_RESERVED_SYMBOL,
    LA_ERR_DEFERRED_FEATURE,
    LA_ERR_NATIVE_OUTPUT_DEFERRED,
    LA_ERR_IO,
    LA_ERR_MODULE_WORKSPACE,
    LA_ERR_MODULE_CAPACITY,
    LA_ERR_MODULE_SOURCE_CAPACITY,
    LA_ERR_MODULE_LINE_CAPACITY,
    LA_ERR_MODULE_DEPTH,
    LA_ERR_MODULE_NOT_FOUND,
    LA_ERR_MODULE_CYCLE,
    LA_ERR_MODULE_DUPLICATE,
    LA_ERR_MODULE_SYNTAX,
    LA_ERR_POOL_CAPACITY,
    LA_ERR_PROCEDURE_CAPACITY,
    LA_ERR_PARAMETER_CAPACITY,
    LA_ERR_LOCAL_CAPACITY,
    LA_ERR_DUPLICATE_POOL,
    LA_ERR_DUPLICATE_PROCEDURE,
    LA_ERR_DUPLICATE_PARAMETER,
    LA_ERR_DUPLICATE_LOCAL,
    LA_ERR_INDEXED_FIELD,
    LA_ERR_INDEX_LOCATION,
    LA_ERR_INDEX_STRIDE,
    LA_ERR_UNKNOWN_POOL,
    LA_ERR_POOL_STRATEGY,
    LA_ERR_PROCEDURE_SCOPE,
    LA_ERR_FRAME_LOCAL,
    LA_ERR_FRAME_STACK_MUTATION,
    LA_ERR_MEMBER_ROLE,
    LA_ERR_MEMBER_PLACEMENT,
    LA_ERR_CONVENTION,
    LA_ERR_INVOKE_CAPACITY,
    LA_ERR_UNKNOWN_PROCEDURE,
    LA_ERR_INVOKE_BINDING,
    LA_ERR_INVOKE_SCRATCH,
    LA_ERR_LOCAL_SYNTAX_MIGRATION,
    LA_ERR_ENUM_CAPACITY,
    LA_ERR_ENUM_MEMBER_CAPACITY,
    LA_ERR_UNION_CAPACITY,
    LA_ERR_OVERLAY_CAPACITY,
    LA_ERR_DUPLICATE_ENUM,
    LA_ERR_DUPLICATE_ENUM_MEMBER,
    LA_ERR_DUPLICATE_UNION,
    LA_ERR_DUPLICATE_OVERLAY,
    LA_ERR_ENUM_UNDERLYING,
    LA_ERR_ENUM_EMPTY,
    LA_ERR_ENUM_VALUE,
    LA_ERR_AGGREGATE_EMPTY,
    LA_ERR_LAYOUT_POLICY,
    LA_ERR_LAYOUT_ALIGNMENT,
    LA_ERR_FIELD_OFFSET,
    LA_ERR_UNION_OFFSET,
    LA_ERR_OVERLAY_TYPE,
    LA_ERR_OVERLAY_BASE,
    LA_ERR_OVERLAY_ALIGNMENT,
    LA_ERR_NAMESPACE_CAPACITY,
    LA_ERR_EXPORT_CAPACITY,
    LA_ERR_NAMESPACE_DEPTH,
    LA_ERR_DUPLICATE_NAMESPACE,
    LA_ERR_DUPLICATE_EXPORT,
    LA_ERR_PRIVATE_NAME,
    LA_ERR_UNKNOWN_EXPORT,
    LA_ERR_CONSTANT_CAPACITY,
    LA_ERR_DUPLICATE_CONSTANT,
    LA_ERR_UNKNOWN_CONSTANT
} LaDiagnosticCode;

typedef struct {
    LaDiagnosticCode code;
    LaSpan span;
    LaSlice arg0;
    LaSlice arg1;
    la_i32 value;
    la_i32 limit;
} LaDiagnostic;

typedef enum {
    LA_PROPERTY_STRUCT_SIZE = 1,
    LA_PROPERTY_STRUCT_ALIGN,
    LA_PROPERTY_FIELD_OFFSET,
    LA_PROPERTY_FIELD_SIZE,
    LA_PROPERTY_FIELD_COUNT,
    LA_PROPERTY_FIELD_STRIDE
} LaPropertyKind;

typedef enum {
    LA_AGGREGATE_STRUCT = 1,
    LA_AGGREGATE_UNION
} LaAggregateKind;

typedef enum {
    LA_LAYOUT_PACKED = 1,
    LA_LAYOUT_ALIGNED
} LaLayoutPolicy;

typedef enum {
    LA_TARGET_OP_LOAD8_PTR_DISP = 1,
    LA_TARGET_OP_STORE8_PTR_DISP,
    LA_TARGET_OP_LOAD8_PTR_INDEXED,
    LA_TARGET_OP_STORE8_PTR_INDEXED,
    LA_TARGET_OP_ADDRESS_POOL_TABLE,
    LA_TARGET_OP_PROC_FRAME,
    LA_TARGET_OP_PROC_NAKED,
    LA_TARGET_OP_PROC_RETURN,
    LA_TARGET_OP_LOAD8_FRAME_LOCAL,
    LA_TARGET_OP_STORE8_FRAME_LOCAL,
    LA_TARGET_OP_STORE_PTR_FRAME,
    LA_TARGET_OP_LOAD_PTR_FRAME,
    LA_TARGET_OP_INVOKE_SAVE,
    LA_TARGET_OP_INVOKE_ASSIGN,
    LA_TARGET_OP_INVOKE_CALL,
    LA_TARGET_OP_LOAD8_OVERLAY_DISP,
    LA_TARGET_OP_STORE8_OVERLAY_DISP,
    LA_TARGET_OP_DATA_PROC_LOW,
    LA_TARGET_OP_DATA_PROC_HIGH,
    LA_TARGET_OP_DATA_PROC_FULL,
    LA_TARGET_OP_MATERIALIZE_FIELD_OFFSET,
    LA_TARGET_OP_VALUE_MOV,
    LA_TARGET_OP_VALUE_CMP
} LaTargetOperationKind;

typedef enum {
    LA_EVENT_HEADER = 1,
    LA_EVENT_PROPERTY,
    LA_EVENT_PROCEDURE_MEMBER,
    LA_EVENT_RAW,
    LA_EVENT_TARGET_OPERATION,
    LA_EVENT_ENUM_MEMBER,
    LA_EVENT_OVERLAY,
    LA_EVENT_CONSTANT
} LaEventKind;

typedef enum {
    LA_MEMBER_INPUT = 1,
    LA_MEMBER_RETURN,
    LA_MEMBER_FRAME
} LaMemberRole;

typedef enum {
    LA_PLACEMENT_PHYSICAL = 1,
    LA_PLACEMENT_FRAME
} LaPlacementKind;

typedef enum {
    LA_SOURCE_PHYSICAL = 1,
    LA_SOURCE_IMMEDIATE
} LaSourceKind;

typedef struct {
    la_u16 handle;
    LaSlice name;
    LaSlice underlying;
    la_u16 size;
    la_u8 is_signed;
} LaEnumRecord;

typedef struct {
    la_u16 handle;
    la_u16 enum_handle;
    LaSlice name;
    la_i32 value;
} LaEnumMemberRecord;

typedef struct {
    la_u16 handle;
    LaSlice name;
    LaAggregateKind kind;
    LaLayoutPolicy policy;
    la_u16 size;
    la_u16 alignment;
} LaAggregateRecord;

typedef struct {
    la_u16 aggregate_handle;
    LaSlice name;
    la_u16 offset;
    la_u16 size;
    la_u8 has_explicit_offset;
} LaFieldLayoutRecord;

typedef struct {
    la_u16 handle;
    LaSlice name;
    la_u16 aggregate_handle;
    LaSlice base;
    la_u16 required_alignment;
} LaOverlayRecord;

typedef struct {
    LaEventKind kind;
    LaSpan span;
    LaSlice text;
    LaSlice owner;
    LaSlice path;
    LaSlice base;
    LaSlice index;
    LaSlice aux;
    LaSlice aux2;
    LaPropertyKind property;
    LaTargetOperationKind operation;
    LaAggregateKind aggregate_kind;
    LaLayoutPolicy layout_policy;
    la_i32 signed_value;
    la_u16 value;
    la_u16 offset;
    la_u16 stride;
    la_u16 count;
    la_u8 explicit_offset;
} LaEvent;

typedef int (*LaInputRead)(void *context, char *destination, la_u16 capacity);
typedef void (*LaInputOrigin)(void *context, la_u16 expanded_line,
                              LaSpan *origin);
typedef int (*LaEventWrite)(void *context, const LaEvent *event);
typedef void (*LaDiagnosticWrite)(void *context, const LaDiagnostic *diagnostic);

typedef struct {
    LaInputRead read;
    void *context;
    la_u16 source_id;
    LaInputOrigin origin;
} LaInput;

typedef struct {
    LaEventWrite write;
    void *context;
} LaEventSink;

typedef struct {
    LaDiagnosticWrite write;
    void *context;
} LaDiagnosticSink;

typedef struct {
    la_u16 max_source_bytes;
    la_u16 max_name_bytes;
    la_u16 max_tokens;
    la_u16 max_structs;
    la_u16 max_unions;
    la_u16 max_fields;
    la_u16 max_enums;
    la_u16 max_enum_members;
    la_u16 max_overlays;
    la_u16 max_namespaces;
    la_u16 max_exports;
    la_u16 max_constants;
    la_u16 max_locations;
    la_u16 max_pools;
    la_u16 max_procedures;
    la_u16 max_parameters;
    la_u16 max_locals;
    la_u16 max_invoke_bindings;
    la_u16 max_expression_nodes;
    la_u16 max_nesting;
    la_u16 max_operations;
    la_u16 max_line_bytes;
} LaLimits;

typedef struct {
    void *data;
    la_u32 size;
} LaWorkspace;

typedef struct {
    la_u16 source_bytes;
    la_u16 name_bytes;
    la_u16 tokens;
    la_u16 structures;
    la_u16 unions;
    la_u16 fields;
    la_u16 enums;
    la_u16 enum_members;
    la_u16 overlays;
    la_u16 namespaces;
    la_u16 exports;
    la_u16 constants;
    la_u16 locations;
    la_u16 pools;
    la_u16 procedures;
    la_u16 parameters;
    la_u16 locals;
    la_u16 invoke_bindings;
    la_u16 expression_nodes;
    la_u16 nesting;
    la_u16 operations;
    la_u32 workspace_used;
} LaStats;

typedef struct {
    const char *name;
    const char *scalar_inputs[4];
    la_u8 scalar_input_count;
    const char *scalar_return;
} LaConvention;

typedef struct {
    const char *name;
    la_u8 storage_unit_bits;
    la_u8 pointer_units;
    la_u8 max_displacement;
    la_u8 format_version;
    const LaConvention *conventions;
    la_u8 convention_count;
    const char *invoke_scratch_prefix;
    la_u8 invoke_scratch_units;
    la_u8 invoke_exchange_supported;
    la_u8 max_frame_temporary_units;
    la_u8 max_aggregate_alignment;
    la_u8 max_frame_alignment;
    la_u8 overlay_byte_operations;
} LaTarget;

typedef struct {
    const char *data;
    la_u16 length;
    la_u16 source_id;
    LaSlice name;
} LaSourceView;

typedef int (*LaModuleResolve)(void *context, la_u16 including_source_id,
                               LaSlice requested, LaSourceView *source);

typedef struct {
    LaModuleResolve resolve;
    void *context;
} LaModuleResolver;

typedef struct {
    la_u16 max_modules;
    la_u16 max_source_bytes;
    la_u16 max_source_lines;
    la_u16 max_include_depth;
} LaModuleLimits;

typedef struct {
    la_u16 source_id;
    LaSlice name;
} LaModuleSource;

typedef struct {
    LaInput input;
    const LaModuleSource *sources;
    la_u16 source_count;
    la_u16 expanded_bytes;
    la_u16 expanded_lines;
    la_u16 max_depth;
} LaExpandedInput;

extern const LaTarget la_target_console6502;

LaLimits la_default_limits(void);
la_u32 la_workspace_required(const LaLimits *limits);
LaDiagnosticCode la_compile(const LaInput *input,
                            const LaEventSink *events,
                            const LaDiagnosticSink *diagnostics,
                            const LaTarget *target,
                            const LaLimits *limits,
                            LaWorkspace workspace,
                            LaStats *stats);
const char *la_diagnostic_name(LaDiagnosticCode code);
LaModuleLimits la_default_module_limits(void);
la_u32 la_module_workspace_required(const LaModuleLimits *limits);
LaDiagnosticCode la_expand_modules(const LaSourceView *root,
                                   const LaModuleResolver *resolver,
                                   const LaDiagnosticSink *diagnostics,
                                   const LaModuleLimits *limits,
                                   LaWorkspace workspace,
                                   LaExpandedInput *expanded);

#endif
