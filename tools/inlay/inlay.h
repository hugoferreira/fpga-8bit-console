#ifndef INLAY_H
#define INLAY_H

#include <stddef.h>

typedef unsigned char la_u8;
typedef unsigned short la_u16;
typedef unsigned long la_u32;
typedef signed long la_i32;

#define LA_INVALID_HANDLE ((la_u16)0xffff)
#define LA_FORMAT_VERSION 1
#define LA_TARGET_VERSION 2

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
    LA_ERR_UNKNOWN_CONSTANT,
    LA_ERR_LABEL_CAPACITY,
    LA_ERR_DUPLICATE_LABEL,
    LA_ERR_UNKNOWN_SYMBOL,
    LA_ERR_INLINE_BODY,
    LA_ERR_INLINE_DEPTH,
    LA_ERR_INLINE_CAPACITY
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
    LA_TARGET_OP_DISPATCH_ENTRY,
    LA_TARGET_OP_TABLE_ROW,
    LA_TARGET_OP_TABLE_HOLE,
    LA_TARGET_OP_TABLE_LABEL,
    LA_TARGET_OP_DATA_CODEPTR,
    LA_TARGET_OP_MATERIALIZE_FIELD_OFFSET,
    LA_TARGET_OP_VALUE_MOV,
    LA_TARGET_OP_VALUE_CMP,
    LA_TARGET_OP_LOAD16_PTR_DISP,
    LA_TARGET_OP_STORE16_PTR_DISP,
    LA_TARGET_OP_ADD16_PHYSICAL,
    LA_TARGET_OP_SUB16_PHYSICAL,
    LA_TARGET_OP_CMP16_PHYSICAL,
    LA_TARGET_OP_INC8_PTR_DISP,
    LA_TARGET_OP_DEC8_PTR_DISP,
    LA_TARGET_OP_AND8_PTR_DISP,
    LA_TARGET_OP_OR8_PTR_DISP,
    LA_TARGET_OP_LOAD8_OVERLAY_INDEXED,
    LA_TARGET_OP_STORE8_OVERLAY_INDEXED,
    LA_TARGET_OP_ADDRESS_OVERLAY_FIELD,
    LA_TARGET_OP_INC8_OVERLAY_ABS,
    LA_TARGET_OP_DEC8_OVERLAY_ABS,
    LA_TARGET_OP_AND8_OVERLAY_ABS,
    LA_TARGET_OP_OR8_OVERLAY_ABS,
    LA_TARGET_OP_CMP8_OVERLAY_DISP,
    LA_TARGET_OP_STORE_IMM_OVERLAY_ABS,
    LA_TARGET_OP_STOREX_OVERLAY_DISP,
    LA_TARGET_OP_STOREY_OVERLAY_DISP,
    LA_TARGET_OP_AND8A_OVERLAY_DISP,
    LA_TARGET_OP_ORA8A_OVERLAY_DISP,
    LA_TARGET_OP_LOADX_OVERLAY_DISP,
    LA_TARGET_OP_LOADY_OVERLAY_DISP,
    LA_TARGET_OP_ADD8A_OVERLAY_DISP,
    LA_TARGET_OP_SUB8A_OVERLAY_DISP,
    LA_TARGET_OP_BRANCH_OVERLAY_DISP,
    LA_TARGET_OP_ADC8_OVERLAY_INDEXED,
    LA_TARGET_OP_SBC8_OVERLAY_INDEXED,
    LA_TARGET_OP_DECZ8_PTR_DISP,
    LA_TARGET_OP_TSTW_PTR_DISP,
    LA_TARGET_OP_TSTW_LOCATION,
    LA_TARGET_OP_MOVW_IMM,
    LA_TARGET_OP_MOVW_LOCATION,
    LA_TARGET_OP_STORE16_IMM_PTR_DISP,
    LA_TARGET_OP_INVOKE_TAIL,
    LA_TARGET_OP_INVOKE_FIELD
} LaTargetOperationKind;

typedef enum {
    LA_BYTE_ORDER_LITTLE = 1,
    LA_BYTE_ORDER_BIG
} LaByteOrder;

typedef enum {
    LA_ACCESS_NONVOLATILE = 1,
    LA_ACCESS_VOLATILE
} LaAccessVolatility;

typedef enum {
    LA_EVENT_HEADER = 1,
    LA_EVENT_PROPERTY,
    LA_EVENT_PROCEDURE_MEMBER,
    LA_EVENT_RAW,
    LA_EVENT_TARGET_OPERATION,
    LA_EVENT_ENUM_MEMBER,
    LA_EVENT_OVERLAY,
    LA_EVENT_CONSTANT,
    LA_EVENT_LABEL,
    LA_EVENT_SCOPED_RAW,
    LA_EVENT_LOCATION
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
    LaSlice scratch;
    LaSlice clobbers;
    LaPropertyKind property;
    LaTargetOperationKind operation;
    la_u8 strategy;
    la_u8 lane;
    LaAggregateKind aggregate_kind;
    LaLayoutPolicy layout_policy;
    LaByteOrder byte_order;
    LaAccessVolatility volatility;
    la_i32 signed_value;
    la_u16 value;
    la_u16 offset;
    la_u16 stride;
    la_u16 count;
    la_u16 access_width;
    la_u8 explicit_offset;
} LaEvent;

typedef int (*LaInputRead)(void *context, char *destination, la_u16 capacity);
typedef void (*LaInputOrigin)(void *context, la_u16 expanded_line,
                              LaSpan *origin);
typedef struct {
    const char *data;
    la_u16 length;
    la_u16 source_id;
    la_u16 line;
} LaSourceLine;
typedef void (*LaInputReset)(void *context);
typedef int (*LaInputNextLine)(void *context, LaSourceLine *line);
typedef int (*LaEventWrite)(void *context, const LaEvent *event);
typedef void (*LaDiagnosticWrite)(void *context, const LaDiagnostic *diagnostic);

typedef struct {
    LaInputRead read;
    void *context;
    la_u16 source_id;
    LaInputOrigin origin;
    LaInputReset reset;
    LaInputNextLine next_line;
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
    la_u16 max_labels;
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
    la_u16 max_inline_body_bytes;
    la_u16 max_inline_body_lines;
    la_u16 max_inline_expansions;
    la_u16 max_method_tables;
    la_u16 max_method_columns;
    la_u16 max_method_rows;
    la_u16 max_method_values;
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
    la_u16 labels;
    la_u16 locations;
    la_u16 pools;
    la_u16 procedures;
    la_u16 parameters;
    la_u16 locals;
    la_u16 invoke_bindings;
    la_u16 expression_nodes;
    la_u16 nesting;
    la_u16 operations;
    la_u16 inline_expansions;
    la_u32 workspace_used;
} LaStats;

typedef struct {
    const char *name;
    const char *scalar_inputs[4];
    la_u8 scalar_input_count;
    const char *scalar_return;
} LaConvention;

typedef enum {
    LA_REGISTER_ACCUMULATOR = 1,
    LA_REGISTER_INDEX
} LaRegisterRole;

/* What a register may index, beyond its role. */
enum {
    LA_REGISTER_POINTER_INDEX  = 0x01,
    LA_REGISTER_ABSOLUTE_INDEX = 0x02
};

typedef struct {
    const char *name;
    la_u8 role;
    la_u8 uses;
} LaRegisterDesc;

/* Families of typed-operation parsing a spelling can participate in.
   The description claims spellings; the core orders the families. */
enum {
    LA_SPELL_OFFSET_MATERIALIZE  = 0x0001,
    LA_SPELL_QUALIFIED_IMMEDIATE = 0x0002,
    LA_SPELL_OVERLAY_STORE_IMM   = 0x0004,
    LA_SPELL_OVERLAY_BRANCH      = 0x0008,
    LA_SPELL_FRAME_POINTER_MOVE  = 0x0010,
    LA_SPELL_LOCAL_OPERATION     = 0x0020,
    LA_SPELL_WORD_TRANSFER       = 0x0040,
    LA_SPELL_WORD_ARITHMETIC     = 0x0080,
    LA_SPELL_BYTE_RMW            = 0x0100,
    LA_SPELL_OBSERVATION         = 0x0200,
    LA_SPELL_WORD_MOVE           = 0x0400,
    LA_SPELL_TYPED_OPERATION     = 0x0800,
    LA_SPELL_VALUE_COMPARE       = 0x1000,
    LA_SPELL_OFFSET_KEYWORD      = 0x2000
};

/* One claim: this spelling participates in this family, naming this
   semantic operation there. A spelling may be claimed by several
   families; a family whose parser selects the operation from the
   operand shape claims it with the shape's primary operation. */
typedef struct {
    const char *spelling;
    la_u16 family;
    la_u8 operation;
} LaSpellingDesc;

/* A declarable lowering: template lines emitted for one semantic
   operation. Slots: %b base, %a aux (source name or branch label),
   %d displacement, %D displacement+1, %l immediate low byte,
   %h immediate high byte, %i byte-update immediate, %o owner, %p path,
   %% literal percent. */
typedef struct {
    la_u8 operation;
    const char *reason;
    const char *const *lines;
} LaLoweringDesc;

/* The tables a description knows how to emit. The kind fixes what a
   row denotes; the strategy fixes how the rows are cut. */
typedef enum {
    LA_STRATEGY_DISPATCH_TABLE = 1,
    LA_STRATEGY_VALUE_TABLE,
    LA_STRATEGY_POOL_TABLE
} LaStrategyKind;

/* One lane of a strategy: the rows of one emitted table. `selectors`
   is the space-separated list of spellings that name this lane at a
   declaration site (`data u8 low(P)`), empty when the lane is reachable
   only through its strategy; `suffix` extends the generated table
   label; `units` is the storage one row occupies; `row` emits a filled
   entry and `hole` an absent one - a lane without `hole` rejects
   absence. */
typedef struct {
    const char *selectors;
    const char *suffix;
    la_u8 units;
    const char *const *row;
    const char *const *hole;
} LaStrategyLane;

/* A declarable data-emission strategy. The core owns the loops - domain
   coverage, row order, capacity - and the strategy owns the lane count,
   the label form and the row text. */
typedef struct {
    la_u8 kind;
    const char *name;
    const char *reason;
    la_u8 is_default;
    la_u8 lane_count;
    const LaStrategyLane *lanes;
    const char *const *label;
} LaStrategyDesc;

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
    la_u8 pointer_word_operations;
    LaByteOrder byte_order;
    const char *word_accumulator;
    la_u8 physical_word_arithmetic;
    la_u8 pointer_byte_rmw_operations;
    la_u8 indexed_overlay_byte_operations;
    la_u8 code_pointer_units;
    LaByteOrder code_pointer_byte_order;
    const LaRegisterDesc *registers;
    la_u8 register_count;
    const LaSpellingDesc *spellings;
    la_u16 spelling_count;
    const LaLoweringDesc *lowerings;
    la_u16 lowering_count;
    const LaStrategyDesc *strategies;
    la_u8 strategy_count;
    /* Raw spellings the core must recognize without emitting them:
       instructions that move the stack pointer under a live frame, the
       raw return a procedure must spell `ret` instead, and transfers
       that can leave an inline body. All NULL-terminated. */
    const char *const *stack_mutators;
    const char *raw_return;
    const char *const *nonlocal_transfers;
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
    la_u16 max_edges;
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
    la_u32 total_source_bytes;
    la_u32 total_source_lines;
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
const char *la_operation_name(la_u8 operation);
LaModuleLimits la_default_module_limits(void);
la_u32 la_module_workspace_required(const LaModuleLimits *limits);
LaDiagnosticCode la_expand_modules(const LaSourceView *root,
                                   const LaModuleResolver *resolver,
                                   const LaDiagnosticSink *diagnostics,
                                   const LaModuleLimits *limits,
                                   LaWorkspace workspace,
                                   LaExpandedInput *expanded);

#endif
