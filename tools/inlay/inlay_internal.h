#ifndef INLAY_INTERNAL_H
#define INLAY_INTERNAL_H

#include "inlay.h"

#include <stddef.h>
#include <string.h>

/* The bounded workspace model shared by the core modules: the
   records the passes fill, the context that owns them, and the
   functions each module publishes to the others. */

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 first_field;
    la_u16 field_count;
    la_u16 size;
    la_u16 alignment;
    la_u16 line;
    la_u8 state;
    la_u8 kind;
    la_u8 policy;
} LaStructRec;

typedef struct {
    la_u16 name;
    la_u16 type_name;
    la_u16 count;
    la_u16 offset;
    la_u16 size;
    la_u16 line;
    const char *offset_source;
    la_u16 offset_length;
    la_u8 is_pointer;
    la_u8 has_explicit_offset;
} LaFieldRec;

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 first_member;
    la_u16 member_count;
    la_u16 line;
    la_u8 size;
    la_u8 is_signed;
} LaEnumRec;

typedef struct {
    la_u16 owner;
    la_u16 name;
    la_i32 value;
    la_u16 line;
    const char *value_source;
    la_u16 value_length;
    la_u8 resolved;
} LaEnumMemberRec;

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 type_name;
    la_u16 base;
    la_u16 line;
    la_u16 numeric_base;
    la_u8 has_numeric_base;
    la_u8 volatile_access;
} LaOverlayRec;

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 type_name;
    la_u16 physical;
    la_u16 numeric_physical;
    la_u16 storage_width;
    la_u16 line;
    la_u16 procedure;
    la_u8 is_pointer;
    la_u8 role;
    la_u8 explicit_placement;
    la_u8 has_numeric_physical;
} LaLocationRec;

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 type_name;
    la_u16 count;
    la_u16 stride;
    la_u16 size;
    la_u16 alignment;
    la_u16 base;
    la_u16 table_low;
    la_u16 table_high;
    la_u16 line;
} LaPoolRec;

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 line;
    la_u16 begin_line;
    la_u16 end_line;
    la_u16 first_local;
    la_u16 local_count;
    la_u16 frame_size;
    la_u16 convention;
    la_u16 first_parameter;
    la_u16 parameter_count;
    la_u16 body_first_lineidx;
    la_u16 body_line_count;
    la_u8 naked;
    la_u8 is_inline;
    la_u8 has_nonlocal_jmp;
} LaProcedureRec;

typedef struct {
    la_u16 name;
    la_u16 parent;
    la_u16 source_id;
    la_u16 line;
    la_u16 end_line;
    la_u16 default_convention;
} LaNamespaceRec;

typedef struct {
    la_u16 name;
    la_u16 source_id;
    la_u16 line;
} LaExportRec;

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 line;
    const char *value_source;
    la_u16 value_length;
    la_i32 value;
    la_u8 resolved;
} LaConstantRec;

typedef struct {
    la_u16 name;
    la_u16 namespace_handle;
    la_u16 source_id;
    la_u16 line;
} LaLabelRec;

typedef struct {
    la_u16 name;
    la_u16 type_name;
    la_u16 procedure;
    la_u16 offset;
    la_u16 size;
    la_u16 line;
    la_u8 is_pointer;
} LaLocalRec;

typedef struct {
    la_u8 kind;        /* 0 save, 1 field read, 2 assignment, 3 reg field */
    la_u8 emitted;
    la_u8 via_accumulator;
    la_u8 rank;
    la_u8 subrank;
    la_u16 binding;
    la_u16 read_name;  /* interned handle or LA_INVALID_HANDLE */
    int read_register; /* register table index or -1 */
    la_u16 write_name;
    int write_register;
} LaInvokeItemRec;

typedef struct {
    la_u16 name;
    la_u16 source;
    la_i32 immediate;
    la_u8 source_kind;
    la_u8 scratch;
    la_u8 needs_scratch;
    la_u8 elided;
    la_u8 is_word_immediate;
    la_u8 is_field;
    la_u8 field_width;
    la_u8 field_to_scratch;
    la_u8 field_direct_register;
    la_u16 field_base;
    la_u16 field_disp;
    la_i32 field_add;
} LaInvokeBindingRec;

typedef struct {
    la_u16 handle;
    la_u16 hash;
    la_u8 valid;
} LaNameCacheRec;

typedef struct {
    la_i32 value;
    la_u8 family;
} LaValueRec;

typedef struct {
    la_u32 offset;
    la_u16 length;
    la_u16 source_id;
    la_u16 line;
} LaInlineLineRec;

typedef struct {
    la_u16 label;      /* interned table label */
    la_u8 is_code;     /* code column: split _lo/_hi tables */
} LaMethodColumnRec;

typedef struct {
    la_i32 member_value;
    la_u16 first_value; /* index into method_values, one per column */
    la_u16 line;
} LaMethodRowRec;

typedef struct {
    la_u16 name;
    la_u16 enum_handle;
    la_i32 low;
    la_i32 high;
    la_u16 first_column;
    la_u16 column_count;
    la_u16 first_row;
    la_u16 row_count;
    la_u16 line;
    la_u16 end_line;
} LaMethodTableRec;

typedef struct {
    la_u8 op;
} LaOperatorRec;

typedef struct {
    la_u16 sid;
    la_u16 next_field;
    la_u16 base;
    la_u16 path_length;
} LaPropertyFrame;

typedef struct {
    const LaInput *input;
    const LaEventSink *events;
    const LaDiagnosticSink *diagnostics;
    const LaTarget *target;
    const LaLimits *limits;
    LaStats *stats;
    char *source;
    char *names;
    char *line_buffer;
    char *path_buffer;
    char *resolve_buffer;
    LaStructRec *structs;
    LaFieldRec *fields;
    LaEnumRec *enums;
    LaEnumMemberRec *enum_members;
    LaOverlayRec *overlays;
    LaLocationRec *locations;
    LaPoolRec *pools;
    LaProcedureRec *procedures;
    LaNamespaceRec *namespaces;
    LaExportRec *exports;
    LaConstantRec *constants;
    LaLabelRec *labels;
    la_u16 *namespace_stack;
    LaLocalRec *locals;
    LaInvokeBindingRec *bindings;
    LaInvokeItemRec *invoke_items;
    LaValueRec *values;
    LaOperatorRec *operators;
    LaPropertyFrame *frames;
    char *inline_bodies;
    LaInlineLineRec *inline_lines;
    char *inline_line_buffers;
    LaMethodTableRec *method_tables;
    LaMethodColumnRec *method_columns;
    la_u16 *method_values;
    la_u16 method_table_count;
    la_u16 method_column_count;
    la_u16 method_value_count;
    la_u16 method_row_count;
    LaMethodRowRec *method_rows;
    la_u16 inline_body_used;
    la_u16 inline_line_count;
    la_u16 inline_depth;
    la_u16 inline_serial;
    la_u16 source_length;
    la_u16 active_source_id;
    la_u16 active_line;
    la_u8 expression_family;
    const char *legacy_cursor;
    la_u16 name_length;
    la_u16 struct_count;
    la_u16 plain_struct_count;
    la_u16 union_count;
    la_u16 field_count;
    la_u16 enum_count;
    la_u16 enum_member_count;
    la_u16 overlay_count;
    la_u16 location_count;
    la_u16 pool_count;
    la_u16 procedure_count;
    la_u16 namespace_count;
    la_u16 export_count;
    la_u16 constant_count;
    la_u16 label_count;
    la_u16 namespace_depth;
    la_u16 parameter_count;
    la_u16 local_count;
    la_u16 invoke_binding_highwater;
    la_u16 token_count;
    la_u16 operation_count;
    la_u16 current_struct;
    la_u16 current_enum;
    la_u16 current_procedure;
    la_u16 current_namespace;
    LaNameCacheRec name_cache[2];
    LaDiagnosticCode error;
} LaContext;

enum {
    LA_OP_NONE = 0,
    LA_OP_OR,
    LA_OP_AND,
    LA_OP_EQ,
    LA_OP_NE,
    LA_OP_LT,
    LA_OP_LE,
    LA_OP_GT,
    LA_OP_GE,
    LA_OP_ADD,
    LA_OP_SUB,
    LA_OP_MUL,
    LA_OP_DIV,
    LA_OP_MOD,
    LA_OP_NOT,
    LA_OP_NEG,
    LA_OP_BOR,
    LA_OP_BXOR,
    LA_OP_BAND,
    LA_OP_SHL,
    LA_OP_SHR,
    LA_OP_BNOT,
    LA_OP_LPAREN
};

enum {
    LA_EXPR_NEUTRAL = 0,
    LA_EXPR_BITWISE = 1,
    LA_EXPR_CMPLOGIC = 2
};

/* workspace */
void *la_take(char **cursor, la_u32 *remaining, la_u32 amount);
LaSlice la_slice(const char *data, la_u16 length);
LaSlice la_text(const char *literal);
void la_set_span(LaContext *ctx, LaSpan *span,
                        la_u16 line, la_u16 column, la_u16 length);
LaDiagnosticCode la_fail(LaContext *ctx, LaDiagnosticCode code,
                                la_u16 line, la_u16 column, la_u16 length,
                                LaSlice arg0, LaSlice arg1,
                                la_i32 value, la_i32 limit);
LaDiagnosticCode la_reject(LaContext *ctx, LaDiagnosticCode code,
                                  la_u16 line, LaSlice found);
LaDiagnosticCode la_expected(LaContext *ctx, LaDiagnosticCode code,
                                    la_u16 line, LaSlice found,
                                    LaSlice wanted);
LaDiagnosticCode la_reject_at(LaContext *ctx, LaDiagnosticCode code,
                                     la_u16 line, la_u16 length,
                                     LaSlice found, LaSlice wanted);
LaDiagnosticCode la_bound(LaContext *ctx, LaDiagnosticCode code,
                                 la_u16 line, la_u16 length, LaSlice found,
                                 LaSlice wanted, la_i32 value, la_i32 limit);
int la_is_space(char value);
int la_is_ident_start(char value);
int la_is_ident(char value);
const char *la_trim_left(const char *text, const char *end);
const char *la_code_end(const char *text, const char *end);
int la_equal_text(const char *left, la_u16 left_length,
                         const char *right);
LaSlice la_name_slice(LaContext *ctx, la_u16 handle);
LaDiagnosticCode la_token(LaContext *ctx, la_u16 line, la_u16 column);
la_u16 la_intern(LaContext *ctx, const char *text, la_u16 length,
                        la_u16 line, la_u16 column);
la_u16 la_source_id_at_line(LaContext *ctx, la_u16 line);
la_u16 la_namespace_at_line(LaContext *ctx, la_u16 line);
void la_reset_lines(LaContext *ctx);
int la_next_line(LaContext *ctx, const char **start,
                        const char **end, la_u16 *line);
la_u16 la_intern_qualified(LaContext *ctx,
                                  const char *text, la_u16 length,
                                  la_u16 line, la_u16 column);
int la_line_keyword(const char *start, const char *end,
                           const char *keyword);
int la_deferred_keyword(const char *start, const char *end,
                               LaSlice *found);
int la_read_identifier(const char **cursor, const char *end,
                              const char **start, la_u16 *length);
int la_read_qualified_identifier(const char **cursor,
                                        const char *end,
                                        const char **start,
                                        la_u16 *length);
int la_take_word(const char **cursor, const char *end,
                        const char *word);
int la_write_event(LaContext *ctx, LaEvent *event);
void la_init_event(LaContext *ctx, LaEvent *event, LaEventKind kind,
                          la_u16 line, la_u16 length);
int la_unsupported(LaContext *ctx, const char *start, const char *end,
                          la_u16 line, LaSlice why);
int la_count_operation(LaContext *ctx, la_u16 line);
LaDiagnosticCode la_load_source(LaContext *ctx);

/* describe */
int la_default_strategy(LaContext *ctx, la_u8 kind);
int la_strategy_lane(LaContext *ctx, la_u8 kind, const char *text,
                            la_u16 length, la_u8 *strategy, la_u8 *lane);
LaSlice la_strategy_selectors(LaContext *ctx, la_u8 kind);
int la_register_lookup(const LaContext *ctx, LaSlice slice);
int la_slice_is_register(const LaContext *ctx, LaSlice slice);
la_u16 la_append_text(LaContext *ctx, la_u16 length,
                             const char *text);
LaSlice la_accumulator_slice(const LaContext *ctx);
int la_register_allows(const LaContext *ctx, LaSlice slice,
                              la_u8 use);
LaSlice la_register_names(LaContext *ctx, la_u8 use);
int la_slice_is_accumulator(const LaContext *ctx, LaSlice slice);
const char *la_family_spelling(LaContext *ctx, la_u16 family);
const char *la_skip_spelling(const char *start, const char *end);
la_u8 la_claimed_operation(LaContext *ctx, const char *start,
                                  const char *end, la_u16 family);
int la_is_target_register(LaContext *ctx, const char *text,
                                 la_u16 length);

/* declare */
la_u16 la_find_struct_handle(LaContext *ctx, la_u16 name);
la_u16 la_find_struct_text(LaContext *ctx,
                                  const char *text, la_u16 length);
la_u16 la_find_enum_handle(LaContext *ctx, la_u16 name);
la_u16 la_find_enum_text(LaContext *ctx,
                                const char *text, la_u16 length);
la_u16 la_find_overlay_text(LaContext *ctx,
                                   const char *text, la_u16 length);
la_u16 la_find_location_text_at(LaContext *ctx,
                                       const char *text, la_u16 length,
                                       la_u16 procedure);
la_u16 la_find_location_text(LaContext *ctx,
                                    const char *text, la_u16 length);
void la_extend_qualified_base(LaContext *ctx, const char *base_start,
                                     const char **base_end, const char *close,
                                     la_u16 procedure);
int la_primitive_size(LaContext *ctx, la_u16 type_name,
                             la_u16 *size);
int la_scalar_size(LaContext *ctx, la_u16 type_name, la_u16 *size);
int la_is_code_pointer_type(LaContext *ctx, la_u16 type_name);
la_u16 la_location_storage_units(LaContext *ctx,
                                        la_u16 location_index);
LaDiagnosticCode la_resolve_type_references(LaContext *ctx);
la_u16 la_find_pool_text(LaContext *ctx,
                                const char *text, la_u16 length);
int la_name_is_exported(LaContext *ctx, la_u16 name);
la_u16 la_find_procedure_scoped(LaContext *ctx,
                                       const char *text, la_u16 length,
                                       la_u16 namespace_handle,
                                       la_u16 source_id, int *is_private);
la_u16 la_find_local_text(LaContext *ctx, la_u16 procedure,
                                 const char *text, la_u16 length);
LaDiagnosticCode la_first_pass(LaContext *ctx);
LaDiagnosticCode la_validate_exports(LaContext *ctx);
LaDiagnosticCode la_validate_labels(LaContext *ctx);
la_u16 la_procedure_at_line(LaContext *ctx, la_u16 line);

/* layout */
LaDiagnosticCode la_resolve_enums(LaContext *ctx);
LaDiagnosticCode la_resolve_layouts(LaContext *ctx);
LaDiagnosticCode la_resolve_path(LaContext *ctx,
                                        const char *root, la_u16 root_length,
                                        const char *path, la_u16 path_length,
                                        la_u16 line, la_u16 *field_out,
                                        la_u16 *offset_out);
LaDiagnosticCode la_resolve_indexed_path(
    LaContext *ctx, const char *root, la_u16 root_length,
    const char *path, la_u16 path_length, la_u16 line,
    la_u16 *field_out, la_u16 *offset_out, LaSlice *index_out,
    la_u16 *stride_out, la_u16 *count_out);
la_u16 la_field_alignment(LaContext *ctx, la_u16 field_index);
int la_emit_property(LaContext *ctx, la_u16 line,
                            LaSlice owner, LaSlice path,
                            LaPropertyKind kind, la_u16 value);
int la_emit_struct_properties(LaContext *ctx, la_u16 root_sid);
la_u16 la_field_leaf_size(const LaContext *ctx, la_u16 field);
int la_emit_procedure_event(LaContext *ctx, la_u16 procedure,
                                   la_u16 line,
                                   LaTargetOperationKind operation);
int la_emit_member_events(LaContext *ctx, la_u16 procedure);

/* expression */
int la_layout_query_suffix(const char *text, la_u16 length,
                                  const char **suffix,
                                  la_u16 *suffix_length);
LaDiagnosticCode la_eval_expression(LaContext *ctx,
                                           const char *text, const char *end,
                                           la_u16 line, la_i32 *result);
LaDiagnosticCode la_check_assertions(LaContext *ctx);
LaDiagnosticCode la_resolve_constants(LaContext *ctx);

/* tables */
LaDiagnosticCode la_parse_method_table(LaContext *ctx,
                                              const char *start,
                                              const char *end, la_u16 line);
LaDiagnosticCode la_parse_method_column(LaContext *ctx,
                                               const char *start,
                                               const char *end, la_u16 line);
LaDiagnosticCode la_parse_method_row(LaContext *ctx,
                                            const char *start,
                                            const char *end, la_u16 line);
int la_emit_method_table(LaContext *ctx, LaMethodTableRec *record,
                                la_u16 line);
int la_emit_pool_tables(LaContext *ctx, const char *start,
                               const char *end, la_u16 line);
int la_parse_procedure_data(LaContext *ctx,
                                   const char *start, const char *end,
                                   la_u16 line, int emit);
LaDiagnosticCode la_validate_procedure_data(LaContext *ctx);

/* operations */
int la_parse_typed_operation(LaContext *ctx,
                                    const char *start, const char *end,
                                    la_u16 line, LaEvent *event);
int la_parse_typed_word_operation(LaContext *ctx,
                                         const char *start,
                                         const char *end,
                                         la_u16 line, LaEvent *event);
int la_parse_physical_word_arithmetic(LaContext *ctx,
                                             const char *start,
                                             const char *end,
                                             la_u16 line, LaEvent *event);
int la_resolve_field_tail(LaContext *ctx, const char *start,
                                 const char *cursor, const char *close,
                                 la_u16 line, LaSlice base_type,
                                 const char **root_start, la_u16 *root_length,
                                 const char **path_start);
int la_parse_typed_byte_rmw(LaContext *ctx,
                                   const char *start, const char *end,
                                   la_u16 line, LaEvent *event);
int la_parse_observation_operation(LaContext *ctx,
                                          const char *start, const char *end,
                                          la_u16 line, LaEvent *event);
int la_parse_word_move(LaContext *ctx,
                              const char *start, const char *end,
                              la_u16 line, LaEvent *event);
int la_has_explicit_typed_operand(const char *start, const char *end);
int la_parse_overlay_branch(LaContext *ctx,
                                   const char *start, const char *end,
                                   la_u16 line, LaEvent *event);
int la_parse_overlay_store_immediate(LaContext *ctx,
                                            const char *start, const char *end,
                                            la_u16 line, LaEvent *event);
int la_parse_pool_address(LaContext *ctx,
                                 const char *start, const char *end,
                                 la_u16 line, LaEvent *event);
int la_parse_local_operation(LaContext *ctx,
                                    const char *start, const char *end,
                                    la_u16 line, LaEvent *event);
int la_parse_frame_pointer_move(LaContext *ctx,
                                       const char *start, const char *end,
                                       la_u16 line, LaEvent *event);
int la_parse_offset_materialization(LaContext *ctx,
                                           const char *start,
                                           const char *end,
                                           la_u16 line, la_u16 families,
                                           LaEvent *event);
int la_parse_qualified_immediate(LaContext *ctx,
                                        const char *start,
                                        const char *end,
                                        la_u16 line, la_u16 families,
                                        LaEvent *event);

/* invoke */
int la_parse_invoke(LaContext *ctx,
                           const char *start, const char *end,
                           la_u16 line, la_u16 caller);

/* emit */
int la_expand_inline_body(LaContext *ctx, la_u16 callee,
                                 la_u16 caller, la_u16 line);

#endif
