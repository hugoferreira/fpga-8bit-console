#include "inlay.h"

#include <string.h>

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
    LaValueRec *values;
    LaOperatorRec *operators;
    LaPropertyFrame *frames;
    char *inline_bodies;
    LaInlineLineRec *inline_lines;
    char *inline_line_buffers;
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

static const LaConvention la_console6502_conventions[] = {
    {"console6502", {"a", "x", "y", 0}, 3, "a"}
};

const LaTarget la_target_console6502 = {
    "console6502", 8, 2, 255, LA_TARGET_VERSION,
    la_console6502_conventions, 1,
    "t", 8, 0, 0, 16, 1, 1, 1, LA_BYTE_ORDER_LITTLE, "ab", 1, 1, 1,
    2, LA_BYTE_ORDER_LITTLE
};

static la_u32 la_align_size(la_u32 value)
{
    la_u32 alignment;
    alignment = (la_u32)sizeof(void *);
    return (value + alignment - 1) & ~(alignment - 1);
}

LaLimits la_default_limits(void)
{
    LaLimits limits;
    limits.max_source_bytes = 32767;
    /* Full multi-module games exceed the original 8 KiB interned-name arena. */
    limits.max_name_bytes = 16384;
    limits.max_tokens = 8192;
    limits.max_structs = 128;
    limits.max_unions = 64;
    limits.max_fields = 1024;
    limits.max_enums = 128;
    limits.max_enum_members = 512;
    limits.max_overlays = 128;
    limits.max_namespaces = 128;
    limits.max_exports = 256;
    limits.max_constants = 512;
    limits.max_labels = 512;
    limits.max_locations = 256;
    limits.max_pools = 64;
    limits.max_procedures = 256;
    limits.max_parameters = 512;
    limits.max_locals = 512;
    limits.max_invoke_bindings = 64;
    limits.max_expression_nodes = 256;
    limits.max_nesting = 32;
    limits.max_operations = 2048;
    limits.max_line_bytes = 512;
    limits.max_inline_body_bytes = 8192;
    limits.max_inline_body_lines = 256;
    limits.max_inline_expansions = 256;
    return limits;
}

la_u32 la_workspace_required(const LaLimits *limits)
{
    la_u32 total;
    total = 0;
    total += la_align_size((la_u32)limits->max_source_bytes + 1);
    total += la_align_size((la_u32)limits->max_name_bytes + 1);
    total += la_align_size((la_u32)limits->max_line_bytes + 1);
    total += la_align_size((la_u32)limits->max_line_bytes + 1);
    total += la_align_size((la_u32)limits->max_line_bytes + 1);
    total += la_align_size(
        ((la_u32)limits->max_structs + limits->max_unions) *
        sizeof(LaStructRec));
    total += la_align_size((la_u32)limits->max_fields * sizeof(LaFieldRec));
    total += la_align_size((la_u32)limits->max_enums * sizeof(LaEnumRec));
    total += la_align_size((la_u32)limits->max_enum_members *
                           sizeof(LaEnumMemberRec));
    total += la_align_size((la_u32)limits->max_overlays *
                           sizeof(LaOverlayRec));
    total += la_align_size((la_u32)limits->max_namespaces *
                           sizeof(LaNamespaceRec));
    total += la_align_size((la_u32)limits->max_exports *
                           sizeof(LaExportRec));
    total += la_align_size((la_u32)limits->max_constants *
                           sizeof(LaConstantRec));
    total += la_align_size((la_u32)limits->max_labels *
                           sizeof(LaLabelRec));
    total += la_align_size((la_u32)limits->max_nesting * sizeof(la_u16));
    total += la_align_size((la_u32)limits->max_locations * sizeof(LaLocationRec));
    total += la_align_size((la_u32)limits->max_pools * sizeof(LaPoolRec));
    total += la_align_size((la_u32)limits->max_procedures *
                           sizeof(LaProcedureRec));
    total += la_align_size((la_u32)limits->max_locals * sizeof(LaLocalRec));
    total += la_align_size((la_u32)limits->max_invoke_bindings *
                           sizeof(LaInvokeBindingRec));
    total += la_align_size((la_u32)limits->max_expression_nodes * sizeof(LaValueRec));
    total += la_align_size((la_u32)limits->max_expression_nodes * sizeof(LaOperatorRec));
    total += la_align_size((la_u32)limits->max_inline_body_bytes + 1);
    total += la_align_size((la_u32)limits->max_inline_body_lines *
                           sizeof(LaInlineLineRec));
    total += la_align_size(8u * ((la_u32)limits->max_line_bytes + 1));
    total += la_align_size((la_u32)limits->max_nesting * sizeof(LaPropertyFrame));
    return total;
}

static void *la_take(char **cursor, la_u32 *remaining, la_u32 amount)
{
    void *result;
    la_u32 aligned;
    aligned = la_align_size(amount);
    if (*remaining < aligned) {
        return 0;
    }
    result = *cursor;
    *cursor += aligned;
    *remaining -= aligned;
    return result;
}

static LaSlice la_slice(const char *data, la_u16 length)
{
    LaSlice slice;
    slice.data = data;
    slice.length = length;
    return slice;
}

static void la_set_span(LaContext *ctx, LaSpan *span,
                        la_u16 line, la_u16 column, la_u16 length)
{
    span->source_id = ctx->input->next_line != 0 ?
        ctx->active_source_id : ctx->input->source_id;
    span->line = line;
    span->column = column;
    span->length = length;
    if (ctx->input->next_line == 0 && ctx->input->origin != 0) {
        ctx->input->origin(ctx->input->context, line, span);
        span->column = column;
        span->length = length;
    }
}

static LaDiagnosticCode la_fail(LaContext *ctx, LaDiagnosticCode code,
                                la_u16 line, la_u16 column, la_u16 length,
                                LaSlice arg0, LaSlice arg1,
                                la_i32 value, la_i32 limit)
{
    LaDiagnostic diagnostic;
    if (ctx->error != LA_OK) {
        return ctx->error;
    }
    ctx->error = code;
    diagnostic.code = code;
    la_set_span(ctx, &diagnostic.span, line, column, length);
    diagnostic.arg0 = arg0;
    diagnostic.arg1 = arg1;
    diagnostic.value = value;
    diagnostic.limit = limit;
    if (ctx->diagnostics != 0 && ctx->diagnostics->write != 0) {
        ctx->diagnostics->write(ctx->diagnostics->context, &diagnostic);
    }
    return code;
}

static int la_is_space(char value)
{
    return value == ' ' || value == '\t' || value == '\r';
}

static int la_is_ident_start(char value)
{
    return (value >= 'A' && value <= 'Z') ||
           (value >= 'a' && value <= 'z') || value == '_';
}

static int la_is_ident(char value)
{
    return la_is_ident_start(value) || (value >= '0' && value <= '9');
}

static const char *la_trim_left(const char *text, const char *end)
{
    while (text < end && la_is_space(*text)) {
        ++text;
    }
    return text;
}

static const char *la_trim_right(const char *text, const char *end)
{
    while (end > text && la_is_space(end[-1])) {
        --end;
    }
    return end;
}

static const char *la_code_end(const char *text, const char *end)
{
    const char *cursor;
    cursor = text;
    while (cursor < end && *cursor != ';') ++cursor;
    return la_trim_right(text, cursor);
}

static int la_equal_text(const char *left, la_u16 left_length,
                         const char *right)
{
    la_u16 right_length;
    right_length = (la_u16)strlen(right);
    return left_length == right_length &&
           memcmp(left, right, left_length) == 0;
}

static LaSlice la_name_slice(LaContext *ctx, la_u16 handle)
{
    const char *name;
    if (handle == LA_INVALID_HANDLE) {
        return la_slice("", 0);
    }
    name = ctx->names + handle;
    return la_slice(name, (la_u16)strlen(name));
}

static LaDiagnosticCode la_token(LaContext *ctx, la_u16 line, la_u16 column)
{
    if (ctx->token_count >= ctx->limits->max_tokens) {
        return la_fail(ctx, LA_ERR_TOKEN_CAPACITY, line, column, 1,
                       la_slice("tokens", 6), la_slice("", 0),
                       ctx->token_count + 1, ctx->limits->max_tokens);
    }
    ++ctx->token_count;
    if (ctx->token_count > ctx->stats->tokens) {
        ctx->stats->tokens = ctx->token_count;
    }
    return LA_OK;
}

static la_u16 la_name_hash(const char *text, la_u16 length)
{
    la_u16 hash;
    la_u16 index;
    hash = 21661;
    for (index = 0; index < length; ++index) {
        hash = (la_u16)((hash ^ (la_u8)text[index]) * 251);
    }
    return hash;
}

static void la_cache_name(LaContext *ctx, la_u16 handle, la_u16 hash)
{
    ctx->name_cache[1] = ctx->name_cache[0];
    ctx->name_cache[0].handle = handle;
    ctx->name_cache[0].hash = hash;
    ctx->name_cache[0].valid = 1;
}

static la_u16 la_intern(LaContext *ctx, const char *text, la_u16 length,
                        la_u16 line, la_u16 column)
{
    la_u16 cursor;
    la_u16 hash;
    la_u16 cached;
    hash = la_name_hash(text, length);
    for (cached = 0; cached < 2; ++cached) {
        LaNameCacheRec *entry;
        const char *existing;
        la_u16 handle;
        entry = &ctx->name_cache[cached];
        if (!entry->valid || entry->hash != hash) continue;
        handle = entry->handle;
        existing = ctx->names + handle;
        if (strlen(existing) == length &&
            memcmp(existing, text, length) == 0) {
            if (cached != 0) la_cache_name(ctx, handle, hash);
            return handle;
        }
    }
    cursor = 0;
    while (cursor < ctx->name_length) {
        la_u16 existing_length;
        existing_length = (la_u16)strlen(ctx->names + cursor);
        if (existing_length == length &&
            memcmp(ctx->names + cursor, text, length) == 0) {
            la_cache_name(ctx, cursor, hash);
            return cursor;
        }
        cursor = (la_u16)(cursor + existing_length + 1);
    }
    if ((la_u32)ctx->name_length + length + 1 >
        ctx->limits->max_name_bytes) {
        la_fail(ctx, LA_ERR_NAME_CAPACITY, line, column, length,
                la_slice(text, length), la_slice("names", 5),
                ctx->name_length + length + 1,
                ctx->limits->max_name_bytes);
        return LA_INVALID_HANDLE;
    }
    cursor = ctx->name_length;
    memcpy(ctx->names + cursor, text, length);
    ctx->names[cursor + length] = 0;
    ctx->name_length = (la_u16)(ctx->name_length + length + 1);
    ctx->stats->name_bytes = ctx->name_length;
    la_cache_name(ctx, cursor, hash);
    return cursor;
}

static int la_read_identifier(const char **cursor, const char *end,
                              const char **start, la_u16 *length);
static int la_read_qualified_identifier(const char **cursor,
                                        const char *end,
                                        const char **start,
                                        la_u16 *length);
static int la_take_word(const char **cursor, const char *end,
                        const char *word);
static int la_name_is_exported(LaContext *ctx, la_u16 name);

static la_u16 la_source_id_at_line(LaContext *ctx, la_u16 line)
{
    LaSpan span;
    la_set_span(ctx, &span, line, 1, 1);
    return span.source_id;
}

static la_u16 la_namespace_at_line(LaContext *ctx, la_u16 line)
{
    la_u16 index;
    la_u16 result;
    result = LA_INVALID_HANDLE;
    for (index = 0; index < ctx->namespace_count; ++index) {
        if (ctx->namespaces[index].source_id == ctx->active_source_id &&
            line > ctx->namespaces[index].line &&
            line < ctx->namespaces[index].end_line) {
            result = index;
        }
    }
    return result;
}

static void la_reset_lines(LaContext *ctx)
{
    ctx->active_source_id = ctx->input->source_id;
    ctx->active_line = 0;
    if (ctx->input->next_line != 0) {
        if (ctx->input->reset != 0) ctx->input->reset(ctx->input->context);
    } else {
        ctx->legacy_cursor = ctx->source;
    }
}

static int la_next_line(LaContext *ctx, const char **start,
                        const char **end, la_u16 *line)
{
    if (ctx->input->next_line != 0) {
        LaSourceLine source_line;
        int result;
        result = ctx->input->next_line(ctx->input->context, &source_line);
        if (result <= 0) return result;
        *start = source_line.data;
        *end = source_line.data + source_line.length;
        *line = source_line.line;
        ctx->active_source_id = source_line.source_id;
        ctx->active_line = source_line.line;
        return 1;
    }
    if (ctx->legacy_cursor >= ctx->source + ctx->source_length) return 0;
    *start = ctx->legacy_cursor;
    *end = *start;
    while (*end < ctx->source + ctx->source_length && **end != '\n') ++*end;
    ctx->legacy_cursor = *end;
    if (ctx->legacy_cursor < ctx->source + ctx->source_length) {
        ++ctx->legacy_cursor;
    }
    ++ctx->active_line;
    *line = ctx->active_line;
    return 1;
}

static la_u16 la_intern_qualified(LaContext *ctx,
                                  const char *text, la_u16 length,
                                  la_u16 line, la_u16 column)
{
    LaSlice owner;
    la_u16 total;
    if (ctx->current_namespace == LA_INVALID_HANDLE ||
        memchr(text, '.', length) != 0) {
        return la_intern(ctx, text, length, line, column);
    }
    owner = la_name_slice(
        ctx, ctx->namespaces[ctx->current_namespace].name);
    total = (la_u16)(owner.length + 1 + length);
    if ((la_u32)total + 1 > ctx->limits->max_line_bytes) {
        la_fail(ctx, LA_ERR_NAME_CAPACITY, line, column, length,
                la_slice(text, length), la_slice("qualified name", 14),
                total + 1, ctx->limits->max_line_bytes);
        return LA_INVALID_HANDLE;
    }
    memcpy(ctx->line_buffer, owner.data, owner.length);
    ctx->line_buffer[owner.length] = '.';
    memcpy(ctx->line_buffer + owner.length + 1, text, length);
    ctx->line_buffer[total] = 0;
    return la_intern(ctx, ctx->line_buffer, total, line, column);
}

static LaDiagnosticCode la_parse_namespace(LaContext *ctx,
                                           const char *start,
                                           const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    la_u16 name_length;
    la_u16 name;
    la_u16 index;
    LaNamespaceRec *record;
    cursor = la_trim_left(start, end) + 9;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("namespace name", 14),
                       la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor != end) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1,
                       (la_u16)(end - cursor),
                       la_slice("namespace NAME", 14),
                       la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
    }
    if (ctx->namespace_depth >= ctx->limits->max_nesting) {
        return la_fail(ctx, LA_ERR_NAMESPACE_DEPTH, line, 1, name_length,
                       la_slice(name_start, name_length),
                       la_slice("namespace depth", 15),
                       ctx->namespace_depth + 1,
                       ctx->limits->max_nesting);
    }
    if (ctx->namespace_count >= ctx->limits->max_namespaces) {
        return la_fail(ctx, LA_ERR_NAMESPACE_CAPACITY, line, 1, name_length,
                       la_slice(name_start, name_length),
                       la_slice("namespaces", 10),
                       ctx->namespace_count + 1,
                       ctx->limits->max_namespaces);
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    for (index = 0; index < ctx->namespace_count; ++index) {
        if (ctx->namespaces[index].name == name) {
            return la_fail(ctx, LA_ERR_DUPLICATE_NAMESPACE, line, 1,
                           name_length, la_name_slice(ctx, name),
                           la_slice("", 0), 0, 0);
        }
    }
    ctx->namespace_stack[ctx->namespace_depth++] = ctx->current_namespace;
    record = &ctx->namespaces[ctx->namespace_count];
    record->name = name;
    record->parent = ctx->current_namespace;
    record->source_id = la_source_id_at_line(ctx, line);
    record->line = line;
    record->end_line = 0;
    ctx->current_namespace = ctx->namespace_count++;
    ctx->stats->namespaces = ctx->namespace_count;
    if (ctx->namespace_depth > ctx->stats->nesting) {
        ctx->stats->nesting = ctx->namespace_depth;
    }
    return LA_OK;
}

static LaDiagnosticCode la_parse_export(LaContext *ctx,
                                        const char *start,
                                        const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    la_u16 name_length;
    la_u16 name;
    la_u16 index;
    if (ctx->current_namespace == LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 6,
                       la_slice("export inside namespace", 23),
                       la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(start, end) + 6;
    cursor = la_trim_left(cursor, end);
    if (la_take_word(&cursor, end, "namespace")) {
        cursor = la_trim_left(cursor, end);
    }
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("export name", 11), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor != end) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1,
                       (la_u16)(end - cursor), la_slice("export NAME", 11),
                       la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
    }
    if (ctx->export_count >= ctx->limits->max_exports) {
        return la_fail(ctx, LA_ERR_EXPORT_CAPACITY, line, 1, name_length,
                       la_slice(name_start, name_length),
                       la_slice("exports", 7), ctx->export_count + 1,
                       ctx->limits->max_exports);
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    for (index = 0; index < ctx->export_count; ++index) {
        if (ctx->exports[index].name == name) {
            return la_fail(ctx, LA_ERR_DUPLICATE_EXPORT, line, 1,
                           name_length, la_name_slice(ctx, name),
                           la_slice("", 0), 0, 0);
        }
    }
    ctx->exports[ctx->export_count].name = name;
    ctx->exports[ctx->export_count].source_id =
        la_source_id_at_line(ctx, line);
    ctx->exports[ctx->export_count].line = line;
    ++ctx->export_count;
    ctx->stats->exports = ctx->export_count;
    return LA_OK;
}

static int la_parse_constant(LaContext *ctx, const char *start,
                             const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *value_start;
    la_u16 name_length;
    la_u16 name;
    la_u16 index;
    LaConstantRec *constant;
    cursor = la_trim_left(start, end);
    if (!la_read_identifier(
            &cursor, end, &name_start, &name_length)) return 0;
    cursor = la_trim_left(cursor, end);
    if (cursor == end || *cursor != '=') return 0;
    ++cursor;
    value_start = la_trim_left(cursor, end);
    if (value_start == end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("constant expression", 19),
                la_slice("", 0), 0, 0);
        return -1;
    }
    if (ctx->constant_count >= ctx->limits->max_constants) {
        la_fail(ctx, LA_ERR_CONSTANT_CAPACITY, line, 1, name_length,
                la_slice(name_start, name_length),
                la_slice("constants", 9), ctx->constant_count + 1,
                ctx->limits->max_constants);
        return -1;
    }
    name = la_intern_qualified(
        ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return -1;
    for (index = 0; index < ctx->constant_count; ++index) {
        if (ctx->constants[index].name == name) {
            la_fail(ctx, LA_ERR_DUPLICATE_CONSTANT, line, 1, name_length,
                    la_name_slice(ctx, name), la_slice("", 0), 0, 0);
            return -1;
        }
    }
    constant = &ctx->constants[ctx->constant_count++];
    memset(constant, 0, sizeof(*constant));
    constant->name = name;
    constant->namespace_handle = ctx->current_namespace;
    constant->source_id = la_source_id_at_line(ctx, line);
    constant->line = line;
    constant->value_source = value_start;
    constant->value_length = (la_u16)(end - value_start);
    ctx->stats->constants = ctx->constant_count;
    return 1;
}

static int la_parse_scoped_label(LaContext *ctx, const char *start,
                                 const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    la_u16 name_length;
    la_u16 name;
    la_u16 index;
    LaLabelRec *label;
    cursor = la_trim_left(start, end);
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return 0;
    }
    cursor = la_trim_left(cursor, end);
    if (cursor == end || *cursor != ':') return 0;
    ++cursor;
    cursor = la_trim_left(cursor, end);
    if (cursor != end) return 0;
    if (ctx->label_count >= ctx->limits->max_labels) {
        la_fail(ctx, LA_ERR_LABEL_CAPACITY, line, 1, name_length,
                la_slice(name_start, name_length), la_slice("labels", 6),
                ctx->label_count + 1, ctx->limits->max_labels);
        return -1;
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return -1;
    for (index = 0; index < ctx->label_count; ++index) {
        if (ctx->labels[index].name == name) {
            la_fail(ctx, LA_ERR_DUPLICATE_LABEL, line, 1, name_length,
                    la_name_slice(ctx, name), la_slice("", 0), 0, 0);
            return -1;
        }
    }
    label = &ctx->labels[ctx->label_count++];
    label->name = name;
    label->namespace_handle = ctx->current_namespace;
    label->source_id = la_source_id_at_line(ctx, line);
    label->line = line;
    ctx->stats->labels = ctx->label_count;
    return 1;
}

static la_u16 la_find_struct_handle(LaContext *ctx, la_u16 name)
{
    la_u16 index;
    for (index = 0; index < ctx->struct_count; ++index) {
        if (ctx->structs[index].name == name) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static la_u16 la_find_struct_text(LaContext *ctx,
                                  const char *text, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < ctx->struct_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->structs[index].name);
        if (name.length == length && memcmp(name.data, text, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static la_u16 la_find_enum_handle(LaContext *ctx, la_u16 name)
{
    la_u16 index;
    for (index = 0; index < ctx->enum_count; ++index) {
        if (ctx->enums[index].name == name) return index;
    }
    return LA_INVALID_HANDLE;
}

static la_u16 la_find_enum_text(LaContext *ctx,
                                const char *text, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < ctx->enum_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->enums[index].name);
        if (name.length == length && memcmp(name.data, text, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static la_u16 la_find_overlay_text(LaContext *ctx,
                                   const char *text, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < ctx->overlay_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->overlays[index].name);
        if (name.length == length && memcmp(name.data, text, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static la_u16 la_find_location_text_at(LaContext *ctx,
                                       const char *text, la_u16 length,
                                       la_u16 procedure)
{
    la_u16 index;
    la_u16 global;
    global = LA_INVALID_HANDLE;
    for (index = 0; index < ctx->location_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->locations[index].name);
        if (name.length == length && memcmp(name.data, text, length) == 0) {
            if (ctx->locations[index].procedure == procedure) return index;
            if (ctx->locations[index].procedure == LA_INVALID_HANDLE) {
                global = index;
            }
        }
    }
    return global;
}

static la_u16 la_find_location_text(LaContext *ctx,
                                    const char *text, la_u16 length)
{
    return la_find_location_text_at(ctx, text, length, LA_INVALID_HANDLE);
}

/* Advance *base_end across dotted components while the accumulated name is not
   yet a known location or overlay, so a namespace-qualified operand base such
   as `Machine.object` is read whole. Stops at the shortest resolving prefix;
   if none resolves, *base_end is left unchanged so callers report the leading
   name. */
static void la_extend_qualified_base(LaContext *ctx, const char *base_start,
                                     const char **base_end, const char *close,
                                     la_u16 procedure)
{
    const char *scan;
    scan = *base_end;
    while (la_find_location_text_at(
               ctx, base_start, (la_u16)(scan - base_start), procedure) ==
               LA_INVALID_HANDLE &&
           la_find_overlay_text(
               ctx, base_start, (la_u16)(scan - base_start)) ==
               LA_INVALID_HANDLE &&
           scan < close && *scan == '.' && scan + 1 < close &&
           la_is_ident_start(scan[1])) {
        ++scan;
        while (scan < close && la_is_ident(*scan)) ++scan;
        *base_end = scan;
    }
}

static int la_primitive_size(LaContext *ctx, la_u16 type_name,
                             la_u16 *size)
{
    LaSlice type;
    type = la_name_slice(ctx, type_name);
    if (la_equal_text(type.data, type.length, "u8") ||
        la_equal_text(type.data, type.length, "i8")) {
        *size = 1;
        return 1;
    }
    if (la_equal_text(type.data, type.length, "u16") ||
        la_equal_text(type.data, type.length, "i16")) {
        *size = 2;
        return 1;
    }
    if (la_equal_text(type.data, type.length, "codeptr")) {
        *size = ctx->target->code_pointer_units;
        return ctx->target->code_pointer_units != 0;
    }
    return 0;
}

static int la_scalar_size(LaContext *ctx, la_u16 type_name, la_u16 *size)
{
    la_u16 enumeration;
    if (la_primitive_size(ctx, type_name, size)) return 1;
    enumeration = la_find_enum_handle(ctx, type_name);
    if (enumeration == LA_INVALID_HANDLE) return 0;
    *size = ctx->enums[enumeration].size;
    return 1;
}

static int la_is_code_pointer_type(LaContext *ctx, la_u16 type_name)
{
    LaSlice type;
    type = la_name_slice(ctx, type_name);
    return la_equal_text(type.data, type.length, "codeptr");
}

static la_u16 la_location_storage_units(LaContext *ctx,
                                        la_u16 location_index)
{
    la_u16 size;
    if (ctx->locations[location_index].is_pointer) {
        return ctx->target->pointer_units;
    }
    if (la_scalar_size(
            ctx, ctx->locations[location_index].type_name, &size)) {
        return size;
    }
    return 1;
}

static la_u16 la_checked_type_name(LaContext *ctx, la_u16 type_name,
                                   la_u16 source_id, la_u16 line)
{
    la_u16 sid;
    la_u16 eid;
    la_u16 owner_source;
    la_u16 owner_namespace;
    sid = la_find_struct_handle(ctx, type_name);
    eid = la_find_enum_handle(ctx, type_name);
    owner_source = source_id;
    owner_namespace = LA_INVALID_HANDLE;
    if (sid != LA_INVALID_HANDLE) {
        owner_source = ctx->structs[sid].source_id;
        owner_namespace = ctx->structs[sid].namespace_handle;
    } else if (eid != LA_INVALID_HANDLE) {
        owner_source = ctx->enums[eid].source_id;
        owner_namespace = ctx->enums[eid].namespace_handle;
    }
    if (owner_namespace != LA_INVALID_HANDLE &&
        owner_source != source_id &&
        !la_name_is_exported(ctx, type_name)) {
        la_fail(ctx, LA_ERR_PRIVATE_NAME, line, 1, 1,
                la_name_slice(ctx, type_name),
                la_slice("export", 6), 0, 0);
        return LA_INVALID_HANDLE;
    }
    return type_name;
}

static la_u16 la_resolve_type_name(LaContext *ctx, la_u16 type_name,
                                   la_u16 namespace_handle,
                                   la_u16 source_id, la_u16 line)
{
    LaSlice written;
    la_u16 size;
    la_u16 sid;
    la_u16 eid;
    la_u16 scope;
    written = la_name_slice(ctx, type_name);
    if (la_primitive_size(ctx, type_name, &size)) return type_name;
    if (memchr(written.data, '.', written.length) != 0) {
        sid = la_find_struct_text(ctx, written.data, written.length);
        if (sid != LA_INVALID_HANDLE) {
            return la_checked_type_name(
                ctx, ctx->structs[sid].name, source_id, line);
        }
        eid = la_find_enum_text(ctx, written.data, written.length);
        if (eid != LA_INVALID_HANDLE) {
            return la_checked_type_name(
                ctx, ctx->enums[eid].name, source_id, line);
        }
        return type_name;
    }
    scope = namespace_handle;
    while (scope != LA_INVALID_HANDLE) {
        LaSlice owner;
        la_u16 total;
        owner = la_name_slice(ctx, ctx->namespaces[scope].name);
        total = (la_u16)(owner.length + 1 + written.length);
        if ((la_u32)total + 1 <= ctx->limits->max_line_bytes) {
            memcpy(ctx->path_buffer, owner.data, owner.length);
            ctx->path_buffer[owner.length] = '.';
            memcpy(ctx->path_buffer + owner.length + 1,
                   written.data, written.length);
            sid = la_find_struct_text(ctx, ctx->path_buffer, total);
            if (sid != LA_INVALID_HANDLE) {
                return la_checked_type_name(
                    ctx, ctx->structs[sid].name, source_id, line);
            }
            eid = la_find_enum_text(ctx, ctx->path_buffer, total);
            if (eid != LA_INVALID_HANDLE) {
                return la_checked_type_name(
                    ctx, ctx->enums[eid].name, source_id, line);
            }
        }
        scope = ctx->namespaces[scope].parent;
    }
    sid = la_find_struct_handle(ctx, type_name);
    if (sid != LA_INVALID_HANDLE) {
        return la_checked_type_name(
            ctx, ctx->structs[sid].name, source_id, line);
    }
    eid = la_find_enum_handle(ctx, type_name);
    if (eid != LA_INVALID_HANDLE) {
        return la_checked_type_name(
            ctx, ctx->enums[eid].name, source_id, line);
    }
    return type_name;
}

static LaDiagnosticCode la_resolve_type_references(LaContext *ctx)
{
    la_u16 sid;
    la_u16 index;
    for (sid = 0; sid < ctx->struct_count; ++sid) {
        LaStructRec *owner;
        owner = &ctx->structs[sid];
        for (index = owner->first_field;
             index < owner->first_field + owner->field_count; ++index) {
            ctx->fields[index].type_name = la_resolve_type_name(
                ctx, ctx->fields[index].type_name,
                owner->namespace_handle, owner->source_id,
                ctx->fields[index].line);
            if (ctx->fields[index].type_name == LA_INVALID_HANDLE) {
                return ctx->error;
            }
        }
    }
    for (index = 0; index < ctx->overlay_count; ++index) {
        ctx->overlays[index].type_name = la_resolve_type_name(
            ctx, ctx->overlays[index].type_name,
            ctx->overlays[index].namespace_handle,
            ctx->overlays[index].source_id, ctx->overlays[index].line);
        if (ctx->overlays[index].type_name == LA_INVALID_HANDLE) {
            return ctx->error;
        }
    }
    for (index = 0; index < ctx->pool_count; ++index) {
        ctx->pools[index].type_name = la_resolve_type_name(
            ctx, ctx->pools[index].type_name,
            ctx->pools[index].namespace_handle,
            ctx->pools[index].source_id, ctx->pools[index].line);
        if (ctx->pools[index].type_name == LA_INVALID_HANDLE) {
            return ctx->error;
        }
    }
    for (index = 0; index < ctx->location_count; ++index) {
        ctx->locations[index].type_name = la_resolve_type_name(
            ctx, ctx->locations[index].type_name,
            ctx->locations[index].namespace_handle,
            ctx->locations[index].source_id, ctx->locations[index].line);
        if (ctx->locations[index].type_name == LA_INVALID_HANDLE) {
            return ctx->error;
        }
    }
    for (index = 0; index < ctx->local_count; ++index) {
        LaProcedureRec *procedure;
        procedure = &ctx->procedures[ctx->locals[index].procedure];
        ctx->locals[index].type_name = la_resolve_type_name(
            ctx, ctx->locals[index].type_name,
            procedure->namespace_handle, procedure->source_id,
            ctx->locals[index].line);
        if (ctx->locals[index].type_name == LA_INVALID_HANDLE) {
            return ctx->error;
        }
    }
    return LA_OK;
}

static int la_line_keyword(const char *start, const char *end,
                           const char *keyword)
{
    la_u16 length;
    const char *cursor;
    cursor = la_trim_left(start, end);
    length = (la_u16)strlen(keyword);
    return (la_u16)(end - cursor) >= length &&
           memcmp(cursor, keyword, length) == 0 &&
           ((la_u16)(end - cursor) == length ||
            la_is_space(cursor[length]) || cursor[length] == ':');
}

static int la_deferred_keyword(const char *start, const char *end,
                               LaSlice *found)
{
    static const char *keywords[] = {
        "callconv", "invoke", "object", "interface", "method_table"
    };
    la_u16 index;
    const char *cursor;
    cursor = la_trim_left(start, end);
    for (index = 0; index < (la_u16)(sizeof(keywords) / sizeof(keywords[0]));
         ++index) {
        la_u16 length;
        length = (la_u16)strlen(keywords[index]);
        if ((la_u16)(end - cursor) >= length &&
            memcmp(cursor, keywords[index], length) == 0 &&
            ((la_u16)(end - cursor) == length ||
             la_is_space(cursor[length]))) {
            *found = la_slice(cursor, length);
            return 1;
        }
    }
    return 0;
}

static int la_read_identifier(const char **cursor, const char *end,
                              const char **start, la_u16 *length);
static int la_take_word(const char **cursor, const char *end,
                        const char *word);

static LaDiagnosticCode la_parse_aggregate(LaContext *ctx,
                                           const char *start,
                                           const char *end, la_u16 line,
                                           LaAggregateKind kind)
{
    const char *cursor;
    const char *name_start;
    la_u16 name_length;
    la_u16 name;
    la_u16 alignment;
    LaLayoutPolicy policy;
    cursor = la_trim_left(start, end);
    cursor += kind == LA_AGGREGATE_STRUCT ? 6 : 5;
    cursor = la_trim_left(cursor, end);
    name_start = cursor;
    if (cursor >= end || !la_is_ident_start(*cursor)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line,
                       (la_u16)(cursor - start + 1), 1,
                       la_slice("aggregate name", 14), la_slice("", 0), 0, 0);
    }
    while (cursor < end && la_is_ident(*cursor)) {
        ++cursor;
    }
    name_length = (la_u16)(cursor - name_start);
    if (la_token(ctx, line, (la_u16)(name_start - start + 1)) != LA_OK) {
        return ctx->error;
    }
    cursor = la_trim_left(cursor, end);
    policy = LA_LAYOUT_PACKED;
    alignment = 1;
    if (cursor != end) {
        if (la_equal_text(cursor, (la_u16)(end - cursor), "packed")) {
            policy = LA_LAYOUT_PACKED;
        } else if ((la_u16)(end - cursor) >= 9 &&
                   memcmp(cursor, "aligned(", 8) == 0 &&
                   end[-1] == ')') {
            la_u32 parsed;
            const char *number;
            number = cursor + 8;
            parsed = 0;
            if (number == end - 1) {
                return la_fail(ctx, LA_ERR_LAYOUT_POLICY, line,
                               (la_u16)(cursor - start + 1),
                               (la_u16)(end - cursor),
                               la_slice(cursor, (la_u16)(end - cursor)),
                               la_slice("aligned(power-of-two)", 21), 0, 0);
            }
            while (number < end - 1 && *number >= '0' && *number <= '9') {
                parsed = parsed * 10 + (la_u32)(*number++ - '0');
            }
            if (number != end - 1 || parsed == 0 || parsed > 255 ||
                (parsed & (parsed - 1)) != 0 ||
                parsed > ctx->target->max_aggregate_alignment) {
                return la_fail(ctx, LA_ERR_LAYOUT_ALIGNMENT, line,
                               (la_u16)(cursor - start + 1),
                               (la_u16)(end - cursor),
                               la_slice(cursor, (la_u16)(end - cursor)),
                               la_slice("target maximum", 14),
                               (la_i32)parsed,
                               ctx->target->max_aggregate_alignment);
            }
            policy = LA_LAYOUT_ALIGNED;
            alignment = (la_u16)parsed;
        } else {
            return la_fail(ctx, LA_ERR_LAYOUT_POLICY, line,
                           (la_u16)(cursor - start + 1),
                           (la_u16)(end - cursor),
                           la_slice(cursor, (la_u16)(end - cursor)),
                           la_slice("packed or aligned(N)", 20), 0, 0);
        }
    }
    name = la_intern_qualified(ctx, name_start, name_length, line,
                               (la_u16)(name_start - start + 1));
    if (name == LA_INVALID_HANDLE) {
        return ctx->error;
    }
    if (la_find_struct_handle(ctx, name) != LA_INVALID_HANDLE ||
        la_find_enum_handle(ctx, name) != LA_INVALID_HANDLE) {
        return la_fail(ctx, kind == LA_AGGREGATE_STRUCT ?
                       LA_ERR_DUPLICATE_STRUCT : LA_ERR_DUPLICATE_UNION, line,
                       (la_u16)(name_start - start + 1), name_length,
                       la_name_slice(ctx, name), la_slice("", 0), 0, 0);
    }
    if ((kind == LA_AGGREGATE_STRUCT &&
         ctx->plain_struct_count >= ctx->limits->max_structs) ||
        (kind == LA_AGGREGATE_UNION &&
         ctx->union_count >= ctx->limits->max_unions)) {
        if (kind == LA_AGGREGATE_STRUCT) {
            return la_fail(ctx, LA_ERR_STRUCT_CAPACITY,
                           line, 1, name_length, la_name_slice(ctx, name),
                           la_slice("structures", 10),
                           ctx->plain_struct_count + 1,
                           ctx->limits->max_structs);
        }
        return la_fail(ctx, LA_ERR_UNION_CAPACITY,
                       line, 1, name_length, la_name_slice(ctx, name),
                       la_slice("unions", 6), ctx->union_count + 1,
                       ctx->limits->max_unions);
    }
    ctx->current_struct = ctx->struct_count;
    ctx->structs[ctx->struct_count].name = name;
    ctx->structs[ctx->struct_count].namespace_handle =
        ctx->current_namespace;
    ctx->structs[ctx->struct_count].source_id =
        la_source_id_at_line(ctx, line);
    ctx->structs[ctx->struct_count].first_field = ctx->field_count;
    ctx->structs[ctx->struct_count].field_count = 0;
    ctx->structs[ctx->struct_count].size = 0;
    ctx->structs[ctx->struct_count].alignment = alignment;
    ctx->structs[ctx->struct_count].line = line;
    ctx->structs[ctx->struct_count].state = 0;
    ctx->structs[ctx->struct_count].kind = (la_u8)kind;
    ctx->structs[ctx->struct_count].policy = (la_u8)policy;
    ++ctx->struct_count;
    if (kind == LA_AGGREGATE_STRUCT) {
        ++ctx->plain_struct_count;
        ctx->stats->structures = ctx->plain_struct_count;
    } else {
        ++ctx->union_count;
        ctx->stats->unions = ctx->union_count;
    }
    return LA_OK;
}

static LaDiagnosticCode la_parse_field(LaContext *ctx,
                                       const char *start, const char *end,
                                       la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *type_start;
    la_u16 name_length;
    la_u16 type_length;
    la_u16 name;
    la_u16 type_name;
    la_u16 count;
    la_u16 field_index;
    int is_pointer;
    int has_explicit_offset;
    const char *offset_start;
    cursor = la_trim_left(start, end);
    name_start = cursor;
    if (cursor >= end || !la_is_ident_start(*cursor)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("field name", 10), la_slice("", 0), 0, 0);
    }
    while (cursor < end && la_is_ident(*cursor)) {
        ++cursor;
    }
    name_length = (la_u16)(cursor - name_start);
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor != ':') {
        return la_fail(ctx, LA_ERR_SYNTAX, line,
                       (la_u16)(cursor - start + 1), 1,
                       la_slice(":", 1), la_slice("", 0), 0, 0);
    }
    ++cursor;
    cursor = la_trim_left(cursor, end);
    is_pointer = 0;
    if ((la_u16)(end - cursor) >= 3 &&
        memcmp(cursor, "ptr", 3) == 0 &&
        (cursor + 3 == end || la_is_space(cursor[3]))) {
        is_pointer = 1;
        cursor += 3;
        cursor = la_trim_left(cursor, end);
    }
    if (!la_read_qualified_identifier(
            &cursor, end, &type_start, &type_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line,
                       (la_u16)(cursor - start + 1), 1,
                       la_slice("field type", 10), la_slice("", 0), 0, 0);
    }
    count = 1;
    has_explicit_offset = 0;
    offset_start = 0;
    cursor = la_trim_left(cursor, end);
    if (cursor < end && *cursor == '[') {
        la_u32 parsed;
        ++cursor;
        parsed = 0;
        if (cursor >= end || *cursor < '0' || *cursor > '9') {
            return la_fail(ctx, LA_ERR_SYNTAX, line,
                           (la_u16)(cursor - start + 1), 1,
                           la_slice("positive array count", 20),
                           la_slice("", 0), 0, 0);
        }
        while (cursor < end && *cursor >= '0' && *cursor <= '9') {
            parsed = parsed * 10 + (la_u32)(*cursor - '0');
            ++cursor;
        }
        if (cursor >= end || *cursor != ']' || parsed == 0 || parsed > 65535) {
            return la_fail(ctx, LA_ERR_SYNTAX, line,
                           (la_u16)(cursor - start + 1), 1,
                           la_slice("valid array count", 17),
                           la_slice("", 0), (la_i32)parsed, 65535);
        }
        count = (la_u16)parsed;
        ++cursor;
        cursor = la_trim_left(cursor, end);
    }
    if (la_take_word(&cursor, end, "at")) {
        if (ctx->structs[ctx->current_struct].kind == LA_AGGREGATE_UNION) {
            return la_fail(ctx, LA_ERR_UNION_OFFSET, line,
                           (la_u16)(cursor - start + 1), 2,
                           la_slice(name_start, name_length),
                           la_name_slice(
                               ctx, ctx->structs[ctx->current_struct].name),
                           0, 0);
        }
        offset_start = la_trim_left(cursor, end);
        if (offset_start == end) {
            return la_fail(ctx, LA_ERR_FIELD_OFFSET, line,
                           (la_u16)(cursor - start + 1), 1,
                           la_slice("constant expression", 19),
                           la_slice("", 0), 0, 0);
        }
        has_explicit_offset = 1;
        cursor = end;
    }
    if (cursor != end) {
        return la_fail(ctx, LA_ERR_SYNTAX, line,
                       (la_u16)(cursor - start + 1),
                       (la_u16)(end - cursor),
                       la_slice("end of field", 12),
                       la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
    }
    if (la_token(ctx, line, (la_u16)(name_start - start + 1)) != LA_OK ||
        la_token(ctx, line, (la_u16)(type_start - start + 1)) != LA_OK) {
        return ctx->error;
    }
    name = la_intern(ctx, name_start, name_length, line,
                     (la_u16)(name_start - start + 1));
    type_name = la_intern(ctx, type_start, type_length, line,
                          (la_u16)(type_start - start + 1));
    if (name == LA_INVALID_HANDLE || type_name == LA_INVALID_HANDLE) {
        return ctx->error;
    }
    for (field_index = ctx->structs[ctx->current_struct].first_field;
         field_index < ctx->field_count; ++field_index) {
        if (ctx->fields[field_index].name == name) {
            return la_fail(ctx, LA_ERR_DUPLICATE_FIELD, line,
                           (la_u16)(name_start - start + 1), name_length,
                           la_name_slice(ctx, name),
                           la_name_slice(ctx,
                               ctx->structs[ctx->current_struct].name), 0, 0);
        }
    }
    if (ctx->field_count >= ctx->limits->max_fields) {
        return la_fail(ctx, LA_ERR_FIELD_CAPACITY, line, 1, name_length,
                       la_name_slice(ctx, name), la_slice("fields", 6),
                       ctx->field_count + 1, ctx->limits->max_fields);
    }
    ctx->fields[ctx->field_count].name = name;
    ctx->fields[ctx->field_count].type_name = type_name;
    ctx->fields[ctx->field_count].count = count;
    ctx->fields[ctx->field_count].offset = 0;
    ctx->fields[ctx->field_count].size = 0;
    ctx->fields[ctx->field_count].line = line;
    ctx->fields[ctx->field_count].offset_source =
        has_explicit_offset ? offset_start : 0;
    ctx->fields[ctx->field_count].offset_length =
        has_explicit_offset ? (la_u16)(end - offset_start) : 0;
    ctx->fields[ctx->field_count].is_pointer = (la_u8)is_pointer;
    ctx->fields[ctx->field_count].has_explicit_offset =
        (la_u8)has_explicit_offset;
    ++ctx->field_count;
    ++ctx->structs[ctx->current_struct].field_count;
    ctx->stats->fields = ctx->field_count;
    return LA_OK;
}

static LaDiagnosticCode la_parse_enum(LaContext *ctx,
                                      const char *start, const char *end,
                                      la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *type_start;
    la_u16 name_length;
    la_u16 type_length;
    la_u16 name;
    LaEnumRec *record;
    cursor = la_trim_left(start, end) + 4;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("enum name", 9), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':' ||
        !la_read_qualified_identifier(
            &cursor, end, &type_start, &type_length) ||
        la_trim_left(cursor, end) != end) {
        return la_fail(ctx, LA_ERR_ENUM_UNDERLYING, line, 1, 1,
                       la_slice("u8, i8, u16, or i16", 20),
                       la_slice("", 0), 0, 0);
    }
    if (!(la_equal_text(type_start, type_length, "u8") ||
          la_equal_text(type_start, type_length, "i8") ||
          la_equal_text(type_start, type_length, "u16") ||
          la_equal_text(type_start, type_length, "i16"))) {
        return la_fail(ctx, LA_ERR_ENUM_UNDERLYING, line, 1, type_length,
                       la_slice(type_start, type_length),
                       la_slice("u8, i8, u16, or i16", 20), 0, 0);
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    if (la_find_enum_handle(ctx, name) != LA_INVALID_HANDLE ||
        la_find_struct_handle(ctx, name) != LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_DUPLICATE_ENUM, line, 1, name_length,
                       la_name_slice(ctx, name), la_slice("", 0), 0, 0);
    }
    if (ctx->enum_count >= ctx->limits->max_enums) {
        return la_fail(ctx, LA_ERR_ENUM_CAPACITY, line, 1, name_length,
                       la_slice("enums", 5), la_slice("", 0),
                       ctx->enum_count + 1, ctx->limits->max_enums);
    }
    record = &ctx->enums[ctx->enum_count];
    memset(record, 0, sizeof(*record));
    record->name = name;
    record->namespace_handle = ctx->current_namespace;
    record->source_id = la_source_id_at_line(ctx, line);
    record->first_member = ctx->enum_member_count;
    record->line = line;
    record->size = (la_u8)(type_length == 3 ? 2 : 1);
    record->is_signed = (la_u8)(type_start[0] == 'i');
    ctx->current_enum = ctx->enum_count++;
    ctx->stats->enums = ctx->enum_count;
    return LA_OK;
}

static LaDiagnosticCode la_parse_enum_member(LaContext *ctx,
                                             const char *start,
                                             const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *value_start;
    la_u16 name_length;
    la_u16 name;
    la_u16 index;
    LaEnumRec *owner;
    LaEnumMemberRec *member;
    cursor = la_trim_left(start, end);
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("enum member", 11), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != '=') {
        return la_fail(ctx, LA_ERR_ENUM_VALUE, line, 1, 1,
                       la_slice("explicit enum value", 19),
                       la_slice("", 0), 0, 0);
    }
    value_start = la_trim_left(cursor, end);
    if (value_start == end) {
        return la_fail(ctx, LA_ERR_ENUM_VALUE, line, 1, 1,
                       la_slice("enum value expression", 21),
                       la_slice("", 0), 0, 0);
    }
    owner = &ctx->enums[ctx->current_enum];
    name = la_intern(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    for (index = owner->first_member;
         index < owner->first_member + owner->member_count; ++index) {
        if (ctx->enum_members[index].name == name) {
            return la_fail(ctx, LA_ERR_DUPLICATE_ENUM_MEMBER, line, 1,
                           name_length, la_name_slice(ctx, name),
                           la_name_slice(ctx, owner->name), 0, 0);
        }
    }
    if (ctx->enum_member_count >= ctx->limits->max_enum_members) {
        return la_fail(ctx, LA_ERR_ENUM_MEMBER_CAPACITY, line, 1, name_length,
                       la_slice("enum members", 12), la_slice("", 0),
                       ctx->enum_member_count + 1,
                       ctx->limits->max_enum_members);
    }
    member = &ctx->enum_members[ctx->enum_member_count++];
    memset(member, 0, sizeof(*member));
    member->owner = ctx->current_enum;
    member->name = name;
    member->line = line;
    member->value_source = value_start;
    member->value_length = (la_u16)(end - value_start);
    ++owner->member_count;
    ctx->stats->enum_members = ctx->enum_member_count;
    return LA_OK;
}

static LaDiagnosticCode la_parse_overlay(LaContext *ctx,
                                         const char *start,
                                         const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *type_start;
    const char *base_start;
    const char *base_end;
    la_u16 name_length;
    la_u16 type_length;
    la_u16 base_length;
    la_u16 name;
    LaOverlayRec *overlay;
    la_u32 numeric;
    int is_numeric;
    int volatile_access;
    int radix;
    int digits;
    cursor = la_trim_left(start, end) + 7;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("overlay name", 12), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':' ||
        !la_read_identifier(&cursor, end, &type_start, &type_length) ||
        !la_take_word(&cursor, end, "at")) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("overlay NAME : TYPE at BASE", 27),
                       la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    base_start = cursor;
    numeric = 0;
    radix = 10;
    digits = 0;
    is_numeric = cursor < end &&
        ((*cursor >= '0' && *cursor <= '9') || *cursor == '$');
    if (is_numeric) {
        if (*cursor == '$') {
            radix = 16;
            ++cursor;
        } else if ((la_u16)(end - cursor) >= 2 && cursor[0] == '0' &&
                   (cursor[1] == 'x' || cursor[1] == 'X')) {
            radix = 16;
            cursor += 2;
        }
        while (cursor < end) {
            int digit;
            digit = -1;
            if (*cursor >= '0' && *cursor <= '9') {
                digit = *cursor - '0';
            } else if (radix == 16 && *cursor >= 'a' && *cursor <= 'f') {
                digit = *cursor - 'a' + 10;
            } else if (radix == 16 && *cursor >= 'A' && *cursor <= 'F') {
                digit = *cursor - 'A' + 10;
            }
            if (digit < 0 || digit >= radix) break;
            numeric = numeric * (la_u32)radix + (la_u32)digit;
            ++cursor;
            ++digits;
        }
        base_end = cursor;
        if (digits == 0 || numeric > 65535) {
            return la_fail(ctx, LA_ERR_OVERLAY_BASE, line, 1,
                           (la_u16)(cursor - base_start),
                           la_slice(base_start,
                                    (la_u16)(cursor - base_start)),
                           la_slice("16-bit fixed address", 20),
                           (la_i32)numeric, 65535);
        }
    } else if (!la_read_identifier(&cursor, end, &base_start, &base_length)) {
        return la_fail(ctx, LA_ERR_OVERLAY_BASE, line, 1, 1,
                       la_slice("target symbol", 13), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    volatile_access = 0;
    if (la_take_word(&cursor, end, "volatile")) {
        volatile_access = 1;
        cursor = la_trim_left(cursor, end);
    }
    if (cursor != end) {
        return la_fail(ctx, LA_ERR_OVERLAY_BASE, line, 1,
                       (la_u16)(end - cursor),
                       la_slice(cursor, (la_u16)(end - cursor)),
                       la_slice("single base", 11), 0, 0);
    }
    if (is_numeric) base_length = (la_u16)(base_end - base_start);
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    if (la_find_overlay_text(
            ctx, ctx->names + name,
            (la_u16)strlen(ctx->names + name)) != LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_DUPLICATE_OVERLAY, line, 1, name_length,
                       la_name_slice(ctx, name), la_slice("", 0), 0, 0);
    }
    if (ctx->overlay_count >= ctx->limits->max_overlays) {
        return la_fail(ctx, LA_ERR_OVERLAY_CAPACITY, line, 1, name_length,
                       la_slice("overlays", 8), la_slice("", 0),
                       ctx->overlay_count + 1, ctx->limits->max_overlays);
    }
    overlay = &ctx->overlays[ctx->overlay_count++];
    memset(overlay, 0, sizeof(*overlay));
    overlay->name = name;
    overlay->namespace_handle = ctx->current_namespace;
    overlay->source_id = la_source_id_at_line(ctx, line);
    overlay->type_name =
        la_intern(ctx, type_start, type_length, line, 1);
    overlay->base = la_intern(ctx, base_start, base_length, line, 1);
    if (overlay->type_name == LA_INVALID_HANDLE ||
        overlay->base == LA_INVALID_HANDLE) return ctx->error;
    overlay->line = line;
    overlay->has_numeric_base = (la_u8)is_numeric;
    overlay->numeric_base = (la_u16)numeric;
    overlay->volatile_access = (la_u8)volatile_access;
    ctx->stats->overlays = ctx->overlay_count;
    return LA_OK;
}

static LaDiagnosticCode la_parse_location(LaContext *ctx,
                                          const char *start, const char *end,
                                          la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *type_start;
    la_u16 name_length;
    la_u16 type_length;
    la_u16 name;
    la_u16 type_name;
    la_u16 storage_width;
    la_u32 numeric;
    int is_pointer;
    int has_fixed_address;
    const char *physical_start;
    la_u16 physical_length;
    int radix;
    int digits;
    cursor = la_trim_left(start, end) + 8;
    cursor = la_trim_left(cursor, end);
    name_start = cursor;
    if (cursor >= end || !la_is_ident_start(*cursor)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("location name", 13), la_slice("", 0), 0, 0);
    }
    while (cursor < end && la_is_ident(*cursor)) {
        ++cursor;
    }
    name_length = (la_u16)(cursor - name_start);
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor != ':') {
        return la_fail(ctx, LA_ERR_SYNTAX, line,
                       (la_u16)(cursor - start + 1), 1,
                       la_slice(":", 1), la_slice("", 0), 0, 0);
    }
    ++cursor;
    cursor = la_trim_left(cursor, end);
    is_pointer = la_take_word(&cursor, end, "ptr");
    if (!la_read_qualified_identifier(&cursor, end, &type_start,
                                      &type_length)) {
        return la_fail(ctx, LA_ERR_LOCATION_TYPE, line,
                       (la_u16)(cursor - start + 1), 1,
                       la_slice("scalar, ptr T, or codeptr", 25),
                       la_slice("", 0), 0, 0);
    }
    storage_width = 0;
    if (is_pointer) {
        storage_width = ctx->target->pointer_units;
    } else if (la_equal_text(type_start, type_length, "u8") ||
               la_equal_text(type_start, type_length, "i8")) {
        storage_width = 1;
    } else if (la_equal_text(type_start, type_length, "u16") ||
               la_equal_text(type_start, type_length, "i16")) {
        storage_width = 2;
    } else if (la_equal_text(type_start, type_length, "codeptr")) {
        storage_width = ctx->target->code_pointer_units;
    }
    if (storage_width == 0) {
        return la_fail(ctx, LA_ERR_LOCATION_TYPE, line,
                       (la_u16)(type_start - start + 1), type_length,
                       la_slice("scalar, ptr T, or codeptr", 25),
                       la_slice(type_start, type_length), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    has_fixed_address = 0;
    numeric = 0;
    physical_start = name_start;
    physical_length = name_length;
    if (la_take_word(&cursor, end, "at")) {
        cursor = la_trim_left(cursor, end);
        physical_start = cursor;
        radix = 10;
        digits = 0;
        if (cursor < end && *cursor == '$') {
            radix = 16;
            ++cursor;
        } else if ((la_u16)(end - cursor) >= 2 &&
                   cursor[0] == '0' &&
                   (cursor[1] == 'x' || cursor[1] == 'X')) {
            radix = 16;
            cursor += 2;
        }
        while (cursor < end) {
            int digit;
            digit = -1;
            if (*cursor >= '0' && *cursor <= '9') {
                digit = *cursor - '0';
            } else if (radix == 16 && *cursor >= 'a' && *cursor <= 'f') {
                digit = *cursor - 'a' + 10;
            } else if (radix == 16 && *cursor >= 'A' && *cursor <= 'F') {
                digit = *cursor - 'A' + 10;
            }
            if (digit < 0 || digit >= radix) break;
            numeric = numeric * (la_u32)radix + (la_u32)digit;
            ++cursor;
            ++digits;
        }
        physical_length = (la_u16)(cursor - physical_start);
        if (digits == 0 || numeric > 65535) {
            return la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                           physical_length,
                           la_slice("16-bit fixed address", 20),
                           la_slice(physical_start, physical_length),
                           (la_i32)numeric, 65535);
        }
        has_fixed_address = 1;
    }
    cursor = la_trim_left(cursor, end);
    if (cursor != end) {
        return la_fail(ctx, LA_ERR_SYNTAX, line,
                       (la_u16)(cursor - start + 1),
                       (la_u16)(end - cursor),
                       la_slice("end of location", 15),
                       la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    type_name = la_intern(ctx, type_start, type_length, line, 1);
    if (name == LA_INVALID_HANDLE || type_name == LA_INVALID_HANDLE) {
        return ctx->error;
    }
    if (la_find_location_text(
            ctx, ctx->names + name,
            (la_u16)strlen(ctx->names + name)) != LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_DUPLICATE_LOCATION, line, 1, name_length,
                       la_name_slice(ctx, name), la_slice("", 0), 0, 0);
    }
    if (ctx->location_count >= ctx->limits->max_locations) {
        return la_fail(ctx, LA_ERR_LOCATION_CAPACITY, line, 1, name_length,
                       la_name_slice(ctx, name), la_slice("locations", 9),
                       ctx->location_count + 1,
                       ctx->limits->max_locations);
    }
    ctx->locations[ctx->location_count].name = name;
    ctx->locations[ctx->location_count].namespace_handle =
        ctx->current_namespace;
    ctx->locations[ctx->location_count].source_id =
        la_source_id_at_line(ctx, line);
    ctx->locations[ctx->location_count].type_name = type_name;
    ctx->locations[ctx->location_count].physical =
        has_fixed_address ?
            la_intern(ctx, physical_start, physical_length, line, 1) : name;
    ctx->locations[ctx->location_count].numeric_physical = (la_u16)numeric;
    ctx->locations[ctx->location_count].storage_width = storage_width;
    ctx->locations[ctx->location_count].line = line;
    ctx->locations[ctx->location_count].procedure = LA_INVALID_HANDLE;
    ctx->locations[ctx->location_count].is_pointer = (la_u8)is_pointer;
    ctx->locations[ctx->location_count].role = LA_MEMBER_INPUT;
    ctx->locations[ctx->location_count].explicit_placement = 1;
    ctx->locations[ctx->location_count].has_numeric_physical =
        (la_u8)has_fixed_address;
    ++ctx->location_count;
    ctx->stats->locations = ctx->location_count;
    return LA_OK;
}

static la_u16 la_find_pool_text(LaContext *ctx,
                                const char *text, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < ctx->pool_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->pools[index].name);
        if (name.length == length && memcmp(name.data, text, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static la_u16 la_find_procedure_text(LaContext *ctx,
                                     const char *text, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < ctx->procedure_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->procedures[index].name);
        if (name.length == length && memcmp(name.data, text, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static int la_name_is_exported(LaContext *ctx, la_u16 name)
{
    la_u16 index;
    for (index = 0; index < ctx->export_count; ++index) {
        if (ctx->exports[index].name == name) return 1;
    }
    return 0;
}

static la_u16 la_find_procedure_scoped(LaContext *ctx,
                                       const char *text, la_u16 length,
                                       la_u16 namespace_handle,
                                       la_u16 source_id, int *is_private)
{
    la_u16 procedure;
    la_u16 scope;
    *is_private = 0;
    if (memchr(text, '.', length) != 0) {
        procedure = la_find_procedure_text(ctx, text, length);
    } else {
        procedure = LA_INVALID_HANDLE;
        scope = namespace_handle;
        while (scope != LA_INVALID_HANDLE) {
            LaSlice owner;
            la_u16 total;
            owner = la_name_slice(ctx, ctx->namespaces[scope].name);
            total = (la_u16)(owner.length + 1 + length);
            if ((la_u32)total + 1 <= ctx->limits->max_line_bytes) {
                memcpy(ctx->path_buffer, owner.data, owner.length);
                ctx->path_buffer[owner.length] = '.';
                memcpy(ctx->path_buffer + owner.length + 1, text, length);
                ctx->path_buffer[total] = 0;
                procedure = la_find_procedure_text(
                    ctx, ctx->path_buffer, total);
                if (procedure != LA_INVALID_HANDLE) break;
            }
            scope = ctx->namespaces[scope].parent;
        }
        if (procedure == LA_INVALID_HANDLE) {
            procedure = la_find_procedure_text(ctx, text, length);
        }
    }
    if (procedure != LA_INVALID_HANDLE &&
        ctx->procedures[procedure].namespace_handle != LA_INVALID_HANDLE &&
        ctx->procedures[procedure].source_id != source_id &&
        !la_name_is_exported(ctx, ctx->procedures[procedure].name)) {
        *is_private = 1;
    }
    return procedure;
}

static la_u16 la_find_local_text(LaContext *ctx, la_u16 procedure,
                                 const char *text, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < ctx->local_count; ++index) {
        LaSlice name;
        if (ctx->locals[index].procedure != procedure) continue;
        name = la_name_slice(ctx, ctx->locals[index].name);
        if (name.length == length && memcmp(name.data, text, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static int la_read_identifier(const char **cursor, const char *end,
                              const char **start, la_u16 *length)
{
    const char *value;
    *cursor = la_trim_left(*cursor, end);
    value = *cursor;
    if (value >= end || !la_is_ident_start(*value)) return 0;
    while (*cursor < end && la_is_ident(**cursor)) ++*cursor;
    *start = value;
    *length = (la_u16)(*cursor - value);
    return 1;
}

static int la_read_qualified_identifier(const char **cursor,
                                        const char *end,
                                        const char **start,
                                        la_u16 *length)
{
    const char *component;
    la_u16 component_length;
    if (!la_read_identifier(cursor, end, start, length)) return 0;
    while (*cursor < end && **cursor == '.') {
        ++*cursor;
        if (!la_read_identifier(cursor, end, &component,
                                &component_length)) {
            return 0;
        }
        *length = (la_u16)(*cursor - *start);
    }
    return 1;
}

static int la_take_word(const char **cursor, const char *end,
                        const char *word)
{
    la_u16 length;
    *cursor = la_trim_left(*cursor, end);
    length = (la_u16)strlen(word);
    if ((la_u16)(end - *cursor) < length ||
        memcmp(*cursor, word, length) != 0 ||
        ((la_u16)(end - *cursor) > length &&
         !la_is_space((*cursor)[length]))) {
        return 0;
    }
    *cursor += length;
    return 1;
}

static LaDiagnosticCode la_parse_pool(LaContext *ctx,
                                      const char *start, const char *end,
                                      la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *type_start;
    const char *base_start;
    const char *low_start;
    const char *high_start;
    la_u16 name_length;
    la_u16 type_length;
    la_u16 base_length;
    la_u16 low_length;
    la_u16 high_length;
    la_u32 count;
    LaPoolRec *pool;
    cursor = la_trim_left(start, end) + 4;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("pool name", 9), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':') {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice(":", 1), la_slice("", 0), 0, 0);
    }
    if (!la_read_qualified_identifier(
            &cursor, end, &type_start, &type_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("pool element type", 17),
                       la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != '[') {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("[count]", 7), la_slice("", 0), 0, 0);
    }
    count = 0;
    while (cursor < end && *cursor >= '0' && *cursor <= '9') {
        count = count * 10 + (la_u32)(*cursor++ - '0');
    }
    if (count == 0 || count > 65535 || cursor >= end || *cursor++ != ']') {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("positive pool count", 19),
                       la_slice("", 0), (la_i32)count, 65535);
    }
    if (!la_take_word(&cursor, end, "at") ||
        !la_read_identifier(&cursor, end, &base_start, &base_length) ||
        !la_take_word(&cursor, end, "table") ||
        !la_read_identifier(&cursor, end, &low_start, &low_length)) {
        return la_fail(ctx, LA_ERR_POOL_STRATEGY, line, 1, 1,
                       la_slice("at BASE table LOW, HIGH", 23),
                       la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ',' ||
        !la_read_identifier(&cursor, end, &high_start, &high_length) ||
        la_trim_left(cursor, end) != end) {
        return la_fail(ctx, LA_ERR_POOL_STRATEGY, line, 1, 1,
                       la_slice("at BASE table LOW, HIGH", 23),
                       la_slice("", 0), 0, 0);
    }
    {
        la_u16 qualified_name;
        qualified_name = la_intern_qualified(
            ctx, name_start, name_length, line, 1);
        if (qualified_name == LA_INVALID_HANDLE) return ctx->error;
        if (la_find_pool_text(
                ctx, ctx->names + qualified_name,
                (la_u16)strlen(ctx->names + qualified_name)) !=
            LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_DUPLICATE_POOL, line, 1, name_length,
                           la_name_slice(ctx, qualified_name),
                           la_slice("", 0), 0, 0);
        }
    }
    if (ctx->pool_count >= ctx->limits->max_pools) {
        return la_fail(ctx, LA_ERR_POOL_CAPACITY, line, 1, name_length,
                       la_slice("pools", 5), la_slice("", 0),
                       ctx->pool_count + 1, ctx->limits->max_pools);
    }
    pool = &ctx->pools[ctx->pool_count++];
    pool->name = la_intern_qualified(
        ctx, name_start, name_length, line, 1);
    pool->namespace_handle = ctx->current_namespace;
    pool->source_id = la_source_id_at_line(ctx, line);
    pool->type_name = la_intern(ctx, type_start, type_length, line, 1);
    pool->base = la_intern(ctx, base_start, base_length, line, 1);
    pool->table_low = la_intern(ctx, low_start, low_length, line, 1);
    pool->table_high = la_intern(ctx, high_start, high_length, line, 1);
    if (pool->name == LA_INVALID_HANDLE ||
        pool->type_name == LA_INVALID_HANDLE ||
        pool->base == LA_INVALID_HANDLE ||
        pool->table_low == LA_INVALID_HANDLE ||
        pool->table_high == LA_INVALID_HANDLE) return ctx->error;
    pool->count = (la_u16)count;
    pool->stride = 0;
    pool->size = 0;
    pool->alignment = 1;
    pool->line = line;
    ctx->stats->pools = ctx->pool_count;
    return LA_OK;
}

static LaDiagnosticCode la_parse_procedure(LaContext *ctx,
                                           const char *start,
                                           const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    la_u16 name_length;
    la_u16 name;
    la_u16 index;
    LaProcedureRec *procedure;
    cursor = la_trim_left(start, end) + 4;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("procedure name", 14), la_slice("", 0), 0, 0);
    }
    while (cursor < end && *cursor == '.') {
        const char *component_start;
        la_u16 component_length;
        ++cursor;
        if (!la_read_identifier(&cursor, end, &component_start,
                                &component_length)) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_slice("qualified procedure name", 24),
                           la_slice("", 0), 0, 0);
        }
        name_length = (la_u16)(cursor - name_start);
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    for (index = 0; index < ctx->procedure_count; ++index) {
        LaSlice existing;
        existing = la_name_slice(ctx, ctx->procedures[index].name);
        if (ctx->procedures[index].name == name) {
            return la_fail(ctx, LA_ERR_DUPLICATE_PROCEDURE, line, 1,
                           name_length, existing, la_slice("", 0), 0, 0);
        }
    }
    if (ctx->procedure_count >= ctx->limits->max_procedures) {
        return la_fail(ctx, LA_ERR_PROCEDURE_CAPACITY, line, 1, name_length,
                       la_slice("procedures", 10), la_slice("", 0),
                       ctx->procedure_count + 1,
                       ctx->limits->max_procedures);
    }
    procedure = &ctx->procedures[ctx->procedure_count];
    memset(procedure, 0, sizeof(*procedure));
    procedure->name = name;
    procedure->namespace_handle = ctx->current_namespace;
    procedure->source_id = la_source_id_at_line(ctx, line);
    if (procedure->name == LA_INVALID_HANDLE) return ctx->error;
    procedure->convention = LA_INVALID_HANDLE;
    cursor = la_trim_left(cursor, end);
    if (la_take_word(&cursor, end, "inline")) {
        procedure->is_inline = 1;
        cursor = la_trim_left(cursor, end);
    }
    if (la_take_word(&cursor, end, "using")) {
        const char *convention_start;
        la_u16 convention_length;
        la_u16 convention_index;
        if (!la_read_identifier(&cursor, end, &convention_start,
                                &convention_length)) {
            return la_fail(ctx, LA_ERR_CONVENTION, line, 1, 1,
                           la_slice("convention", 10), la_slice("", 0), 0, 0);
        }
        convention_index = LA_INVALID_HANDLE;
        for (index = 0; index < ctx->target->convention_count; ++index) {
            const char *candidate;
            candidate = ctx->target->conventions[index].name;
            if (la_equal_text(convention_start, convention_length,
                              candidate)) {
                convention_index = index;
                break;
            }
        }
        if (convention_index == LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_CONVENTION, line, 1,
                           convention_length,
                           la_slice(convention_start, convention_length),
                           la_slice(ctx->target->name,
                                    (la_u16)strlen(ctx->target->name)),
                           0, 0);
        }
        procedure->convention = convention_index;
    }
    cursor = la_trim_left(cursor, end);
    if (procedure->is_inline && cursor != end) {
        return la_fail(ctx, LA_ERR_INLINE_BODY, line, 1,
                       (la_u16)(end - cursor),
                       la_slice("inline takes no frame mode", 26),
                       la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
    }
    if (cursor != end) {
        if (la_equal_text(cursor, (la_u16)(end - cursor), "naked")) {
            procedure->naked = 1;
        } else if (!la_equal_text(cursor, (la_u16)(end - cursor), "frame")) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1,
                           (la_u16)(end - cursor),
                           la_slice("[using CONVENTION] [frame|naked]", 34),
                           la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
        }
    }
    procedure->line = line;
    procedure->first_local = ctx->local_count;
    procedure->first_parameter = ctx->location_count;
    ctx->current_procedure = ctx->procedure_count++;
    ctx->stats->procedures = ctx->procedure_count;
    return LA_OK;
}

static LaDiagnosticCode la_parse_member(LaContext *ctx,
                                        const char *start,
                                        const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *type_start;
    const char *physical_start;
    la_u16 name_length;
    la_u16 type_length;
    la_u16 physical_length;
    la_u16 index;
    int is_pointer;
    LaLocationRec *parameter;
    LaProcedureRec *procedure;
    int role;
    int is_local;
    int explicit_placement;
    procedure = &ctx->procedures[ctx->current_procedure];
    cursor = la_trim_left(start, end);
    if (la_line_keyword(cursor, end, "local")) {
        return la_fail(ctx, LA_ERR_LOCAL_SYNTAX_MIGRATION, line, 1, 5,
                       la_slice("local", 5),
                       la_slice("NAME : TYPE in frame", 20), 0, 0);
    }
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("parameter", 9), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':') {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice(":", 1), la_slice("", 0), 0, 0);
    }
    cursor = la_trim_left(cursor, end);
    is_pointer = la_take_word(&cursor, end, "ptr");
    if (!la_read_qualified_identifier(
            &cursor, end, &type_start, &type_length)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("member type", 11), la_slice("", 0), 0, 0);
    }
    role = LA_MEMBER_INPUT;
    is_local = 0;
    explicit_placement = 0;
    physical_start = 0;
    physical_length = 0;
    cursor = la_trim_left(cursor, end);
    if (la_take_word(&cursor, end, "return")) {
        role = LA_MEMBER_RETURN;
        cursor = la_trim_left(cursor, end);
        if (cursor != end) {
            if (!la_take_word(&cursor, end, "in") ||
                !la_read_qualified_identifier(&cursor, end, &physical_start,
                                              &physical_length) ||
                la_trim_left(cursor, end) != end) {
                return la_fail(ctx, LA_ERR_MEMBER_ROLE, line, 1, 1,
                               la_slice("return [in PHYSICAL]", 20),
                               la_slice("", 0), 0, 0);
            }
            explicit_placement = 1;
            if (la_equal_text(physical_start, physical_length, "frame")) {
                return la_fail(ctx, LA_ERR_MEMBER_ROLE, line, 1,
                               physical_length,
                               la_slice("return cannot use frame", 23),
                               la_slice("NAME : TYPE in frame", 20), 0, 0);
            }
        }
    } else if (la_take_word(&cursor, end, "in")) {
        if (!la_read_qualified_identifier(&cursor, end, &physical_start,
                                          &physical_length) ||
            la_trim_left(cursor, end) != end) {
            return la_fail(ctx, LA_ERR_MEMBER_PLACEMENT, line, 1, 1,
                           la_slice("in PHYSICAL", 11), la_slice("", 0), 0, 0);
        }
        if (la_equal_text(physical_start, physical_length, "frame")) {
            is_local = 1;
        } else {
            explicit_placement = 1;
        }
    } else if (cursor != end) {
        return la_fail(ctx, LA_ERR_MEMBER_ROLE, line, 1,
                       (la_u16)(end - cursor),
                       la_slice("in PLACE or return [in PLACE]", 29),
                       la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
    }
    if (is_local) {
        LaLocalRec *local;
        if (procedure->is_inline) {
            return la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, name_length,
                           la_slice(name_start, name_length),
                           la_slice("inline has no frame", 19), 0, 0);
        }
        if (procedure->naked) {
            return la_fail(ctx, LA_ERR_FRAME_LOCAL, line, 1, name_length,
                           la_slice(name_start, name_length),
                           la_slice("naked", 5), 0, 0);
        }
        if (la_find_local_text(ctx, ctx->current_procedure,
                               name_start, name_length) != LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_DUPLICATE_LOCAL, line, 1, name_length,
                           la_slice(name_start, name_length),
                           la_slice("", 0), 0, 0);
        }
        for (index = 0; index < ctx->location_count; ++index) {
            LaSlice other;
            if (ctx->locations[index].procedure != ctx->current_procedure)
                continue;
            other = la_name_slice(ctx, ctx->locations[index].name);
            if (other.length == name_length &&
                memcmp(other.data, name_start, name_length) == 0) {
                return la_fail(ctx, LA_ERR_DUPLICATE_LOCAL, line, 1,
                               name_length, other, la_slice("", 0), 0, 0);
            }
        }
        if (ctx->local_count >= ctx->limits->max_locals) {
            return la_fail(ctx, LA_ERR_LOCAL_CAPACITY, line, 1, name_length,
                           la_slice("locals", 6), la_slice("", 0),
                           ctx->local_count + 1, ctx->limits->max_locals);
        }
        local = &ctx->locals[ctx->local_count++];
        memset(local, 0, sizeof(*local));
        local->name = la_intern(ctx, name_start, name_length, line, 1);
        local->type_name = la_intern(ctx, type_start, type_length, line, 1);
        if (local->name == LA_INVALID_HANDLE ||
            local->type_name == LA_INVALID_HANDLE) return ctx->error;
        local->procedure = ctx->current_procedure;
        local->line = line;
        local->is_pointer = (la_u8)is_pointer;
        ++procedure->local_count;
        ctx->stats->locals = ctx->local_count;
        return LA_OK;
    }
    if (la_find_local_text(ctx, ctx->current_procedure,
                           name_start, name_length) != LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_DUPLICATE_PARAMETER, line, 1,
                       name_length, la_slice(name_start, name_length),
                       la_slice("procedure member", 16), 0, 0);
    }
    for (index = 0; index < ctx->location_count; ++index) {
        LaSlice name;
        if (ctx->locations[index].procedure != ctx->current_procedure) continue;
        name = la_name_slice(ctx, ctx->locations[index].name);
        if (name.length == name_length &&
            memcmp(name.data, name_start, name_length) == 0) {
            return la_fail(ctx, LA_ERR_DUPLICATE_PARAMETER, line, 1,
                           name_length, name, la_slice("", 0), 0, 0);
        }
    }
    if (ctx->parameter_count >= ctx->limits->max_parameters) {
        return la_fail(ctx, LA_ERR_PARAMETER_CAPACITY, line, 1, name_length,
                       la_slice("parameters", 10), la_slice("", 0),
                       ctx->parameter_count + 1,
                       ctx->limits->max_parameters);
    }
    if (ctx->location_count >= ctx->limits->max_locations) {
        return la_fail(ctx, LA_ERR_LOCATION_CAPACITY, line, 1, name_length,
                       la_slice("locations", 9), la_slice("", 0),
                       ctx->location_count + 1,
                       ctx->limits->max_locations);
    }
    parameter = &ctx->locations[ctx->location_count++];
    memset(parameter, 0, sizeof(*parameter));
    parameter->name = la_intern(ctx, name_start, name_length, line, 1);
    parameter->namespace_handle = procedure->namespace_handle;
    parameter->source_id = procedure->source_id;
    parameter->type_name = la_intern(ctx, type_start, type_length, line, 1);
    parameter->physical = LA_INVALID_HANDLE;
    if (explicit_placement) {
        parameter->physical =
            la_intern(ctx, physical_start, physical_length, line, 1);
    }
    if (parameter->name == LA_INVALID_HANDLE ||
        parameter->type_name == LA_INVALID_HANDLE ||
        (explicit_placement &&
         parameter->physical == LA_INVALID_HANDLE)) return ctx->error;
    parameter->line = line;
    parameter->procedure = ctx->current_procedure;
    parameter->is_pointer = (la_u8)is_pointer;
    parameter->role = (la_u8)role;
    parameter->explicit_placement = (la_u8)explicit_placement;
    ++ctx->parameter_count;
    ++procedure->parameter_count;
    ctx->stats->parameters = ctx->parameter_count;
    ctx->stats->locations = ctx->location_count;
    return LA_OK;
}

static LaDiagnosticCode la_first_pass(LaContext *ctx)
{
    const char *cursor;
    la_u16 line;
    int in_struct;
    int in_enum;
    int in_procedure;
    int in_body;
    la_reset_lines(ctx);
    line = 0;
    in_struct = 0;
    in_enum = 0;
    in_procedure = 0;
    in_body = 0;
    ctx->current_struct = LA_INVALID_HANDLE;
    ctx->current_enum = LA_INVALID_HANDLE;
    ctx->current_procedure = LA_INVALID_HANDLE;
    ctx->current_namespace = LA_INVALID_HANDLE;
    ctx->namespace_depth = 0;
    while (1) {
        const char *line_end;
        const char *content_end;
        const char *trimmed;
        LaSlice deferred;
        if (la_next_line(ctx, &cursor, &line_end, &line) <= 0) break;
        content_end = line_end;
        while (content_end > cursor &&
               (content_end[-1] == '\r' || content_end[-1] == ' ' ||
                content_end[-1] == '\t')) {
            --content_end;
        }
        content_end = la_code_end(cursor, content_end);
        trimmed = la_trim_left(cursor, content_end);
        if (trimmed < content_end && *trimmed != ';') {
            if (in_struct) {
                if (la_line_keyword(trimmed, content_end, "end")) {
                    if (ctx->structs[ctx->current_struct].kind ==
                            LA_AGGREGATE_UNION &&
                        ctx->structs[ctx->current_struct].field_count == 0) {
                        return la_fail(
                            ctx, LA_ERR_AGGREGATE_EMPTY,
                            ctx->structs[ctx->current_struct].line, 1, 1,
                            la_name_slice(
                                ctx,
                                ctx->structs[ctx->current_struct].name),
                            la_slice("union", 5), 0, 1);
                    }
                    in_struct = 0;
                    ctx->current_struct = LA_INVALID_HANDLE;
                } else if (la_parse_field(ctx, cursor, content_end, line) !=
                           LA_OK) {
                    return ctx->error;
                }
            } else if (in_enum) {
                if (la_line_keyword(trimmed, content_end, "end")) {
                    if (ctx->enums[ctx->current_enum].member_count == 0) {
                        return la_fail(
                            ctx, LA_ERR_ENUM_EMPTY,
                            ctx->enums[ctx->current_enum].line, 1, 1,
                            la_name_slice(
                                ctx, ctx->enums[ctx->current_enum].name),
                            la_slice("", 0), 0, 1);
                    }
                    in_enum = 0;
                    ctx->current_enum = LA_INVALID_HANDLE;
                } else if (la_parse_enum_member(
                               ctx, cursor, content_end, line) != LA_OK) {
                    return ctx->error;
                }
            } else if (in_procedure) {
                LaProcedureRec *procedure;
                procedure = &ctx->procedures[ctx->current_procedure];
                if (!in_body) {
                    if (la_line_keyword(trimmed, content_end, "begin")) {
                        if (!la_equal_text(trimmed,
                                           (la_u16)(content_end - trimmed),
                                           "begin")) {
                            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                                           la_slice("begin", 5),
                                           la_slice("", 0), 0, 0);
                        }
                        procedure->begin_line = line;
                        in_body = 1;
                    } else if (la_parse_member(ctx, cursor, content_end,
                                               line) != LA_OK) {
                        return ctx->error;
                    }
                } else if (la_line_keyword(trimmed, content_end, "end")) {
                    if (!la_equal_text(trimmed,
                                       (la_u16)(content_end - trimmed),
                                       "end")) {
                        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                                       la_slice("end", 3),
                                       la_slice("", 0), 0, 0);
                    }
                    procedure->end_line = line;
                    in_procedure = 0;
                    in_body = 0;
                    ctx->current_procedure = LA_INVALID_HANDLE;
                } else if (procedure->local_count != 0) {
                    static const char *mutators[] = {
                        "pha", "pla", "php", "plp", "txs"
                    };
                    la_u16 mutator;
                    for (mutator = 0;
                         mutator < (la_u16)(sizeof(mutators) /
                                            sizeof(mutators[0]));
                         ++mutator) {
                        if (la_line_keyword(trimmed, content_end,
                                            mutators[mutator])) {
                            return la_fail(
                                ctx, LA_ERR_FRAME_STACK_MUTATION, line, 1,
                                (la_u16)strlen(mutators[mutator]),
                                la_slice(mutators[mutator],
                                         (la_u16)strlen(mutators[mutator])),
                                la_name_slice(ctx, procedure->name), 0, 0);
                        }
                    }
                    if (la_line_keyword(trimmed, content_end, "rts")) {
                        return la_fail(ctx, LA_ERR_FRAME_STACK_MUTATION,
                                       line, 1, 3, la_slice("rts", 3),
                                       la_slice("use ret", 7), 0, 0);
                    }
                }
            } else if (la_line_keyword(trimmed, content_end, "namespace")) {
                if (la_parse_namespace(ctx, cursor, content_end, line) !=
                    LA_OK) {
                    return ctx->error;
                }
            } else if (la_line_keyword(trimmed, content_end, "export")) {
                if (la_parse_export(ctx, cursor, content_end, line) !=
                    LA_OK) {
                    return ctx->error;
                }
            } else if (la_line_keyword(trimmed, content_end, "end")) {
                if (!la_equal_text(trimmed,
                                   (la_u16)(content_end - trimmed), "end") ||
                    ctx->namespace_depth == 0) {
                    return la_fail(ctx, LA_ERR_SYNTAX, line, 1,
                                   (la_u16)(content_end - trimmed),
                                   la_slice("namespace end", 13),
                                   la_slice(trimmed,
                                            (la_u16)(content_end - trimmed)),
                                   0, 0);
                }
                ctx->namespaces[ctx->current_namespace].end_line = line;
                ctx->current_namespace =
                    ctx->namespace_stack[--ctx->namespace_depth];
            } else if (la_line_keyword(trimmed, content_end, "struct")) {
                if (la_parse_aggregate(ctx, cursor, content_end, line,
                                       LA_AGGREGATE_STRUCT) != LA_OK) {
                    return ctx->error;
                }
                in_struct = 1;
            } else if (la_line_keyword(trimmed, content_end, "union")) {
                if (la_parse_aggregate(ctx, cursor, content_end, line,
                                       LA_AGGREGATE_UNION) != LA_OK) {
                    return ctx->error;
                }
                in_struct = 1;
            } else if (la_line_keyword(trimmed, content_end, "enum")) {
                if (la_parse_enum(ctx, cursor, content_end, line) != LA_OK) {
                    return ctx->error;
                }
                in_enum = 1;
            } else if (la_line_keyword(trimmed, content_end, "overlay")) {
                if (la_parse_overlay(ctx, cursor, content_end, line) !=
                    LA_OK) return ctx->error;
            } else if (la_line_keyword(trimmed, content_end, "pool")) {
                if (la_parse_pool(ctx, cursor, content_end, line) != LA_OK) {
                    return ctx->error;
                }
            } else if (la_line_keyword(trimmed, content_end, "proc")) {
                if (la_parse_procedure(ctx, cursor, content_end, line) !=
                    LA_OK) return ctx->error;
                in_procedure = 1;
                in_body = 0;
            } else if (la_line_keyword(trimmed, content_end, "location")) {
                if (la_parse_location(ctx, cursor, content_end, line) !=
                    LA_OK) {
                    return ctx->error;
                }
            } else if (ctx->current_namespace != LA_INVALID_HANDLE) {
                int parsed_constant;
                int parsed_label;
                parsed_constant = la_parse_constant(
                    ctx, cursor, content_end, line);
                if (parsed_constant < 0) return ctx->error;
                parsed_label = 0;
                if (parsed_constant == 0) {
                    parsed_label = la_parse_scoped_label(
                        ctx, cursor, content_end, line);
                    if (parsed_label < 0) return ctx->error;
                }
                if (parsed_constant == 0 && parsed_label == 0 &&
                    la_deferred_keyword(
                        trimmed, content_end, &deferred)) {
                    return la_fail(ctx, LA_ERR_DEFERRED_FEATURE, line,
                                   (la_u16)(trimmed - cursor + 1),
                                   deferred.length, deferred,
                                   la_slice("", 0), 0, 0);
                }
            } else if (la_deferred_keyword(trimmed, content_end, &deferred)) {
                return la_fail(ctx, LA_ERR_DEFERRED_FEATURE, line,
                               (la_u16)(trimmed - cursor + 1),
                               deferred.length, deferred, la_slice("", 0),
                               0, 0);
            } else if ((la_u16)(content_end - trimmed) >= 5 &&
                       memcmp(trimmed, "__la_", 5) == 0) {
                return la_fail(ctx, LA_ERR_RESERVED_SYMBOL, line,
                               (la_u16)(trimmed - cursor + 1), 5,
                               la_slice(trimmed, 5), la_slice("__la_", 5),
                               0, 0);
            }
        }
    }
    if (in_struct || in_enum || in_procedure || ctx->namespace_depth != 0) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("end", 3), la_slice("", 0), 0, 0);
    }
    return LA_OK;
}

static LaDiagnosticCode la_eval_expression(LaContext *ctx,
                                           const char *text,
                                           const char *end,
                                           la_u16 line, la_i32 *result);

static LaDiagnosticCode la_validate_exports(LaContext *ctx)
{
    la_u16 export_index;
    for (export_index = 0;
         export_index < ctx->export_count; ++export_index) {
        la_u16 name;
        la_u16 index;
        int found;
        name = ctx->exports[export_index].name;
        found = 0;
        for (index = 0; index < ctx->namespace_count; ++index) {
            if (ctx->namespaces[index].name == name) found = 1;
        }
        if (la_find_struct_handle(ctx, name) != LA_INVALID_HANDLE ||
            la_find_enum_handle(ctx, name) != LA_INVALID_HANDLE) {
            found = 1;
        }
        for (index = 0; index < ctx->overlay_count; ++index) {
            if (ctx->overlays[index].name == name) found = 1;
        }
        for (index = 0; index < ctx->location_count; ++index) {
            if (ctx->locations[index].procedure == LA_INVALID_HANDLE &&
                ctx->locations[index].name == name) found = 1;
        }
        for (index = 0; index < ctx->pool_count; ++index) {
            if (ctx->pools[index].name == name) found = 1;
        }
        for (index = 0; index < ctx->procedure_count; ++index) {
            if (ctx->procedures[index].name == name) found = 1;
        }
        for (index = 0; index < ctx->constant_count; ++index) {
            if (ctx->constants[index].name == name) found = 1;
        }
        for (index = 0; index < ctx->label_count; ++index) {
            if (ctx->labels[index].name == name) found = 1;
        }
        if (!found) {
            return la_fail(
                ctx, LA_ERR_UNKNOWN_EXPORT,
                ctx->exports[export_index].line, 1, 1,
                la_name_slice(ctx, name), la_slice("", 0), 0, 0);
        }
    }
    return LA_OK;
}

static LaDiagnosticCode la_validate_labels(LaContext *ctx)
{
    la_u16 label_index;
    for (label_index = 0; label_index < ctx->label_count; ++label_index) {
        la_u16 index;
        LaLabelRec *label;
        label = &ctx->labels[label_index];
        for (index = 0; index < ctx->constant_count; ++index) {
            if (ctx->constants[index].name == label->name) {
                return la_fail(ctx, LA_ERR_DUPLICATE_LABEL, label->line,
                               1, 1, la_name_slice(ctx, label->name),
                               la_slice("constant", 8), 0, 0);
            }
        }
        for (index = 0; index < ctx->procedure_count; ++index) {
            if (ctx->procedures[index].name == label->name) {
                return la_fail(ctx, LA_ERR_DUPLICATE_LABEL, label->line,
                               1, 1, la_name_slice(ctx, label->name),
                               la_slice("procedure", 9), 0, 0);
            }
        }
    }
    return LA_OK;
}

static LaDiagnosticCode la_resolve_enums(LaContext *ctx)
{
    la_u16 index;
    for (index = 0; index < ctx->enum_member_count; ++index) {
        LaEnumMemberRec *member;
        LaEnumRec *owner;
        la_i32 value;
        la_i32 minimum;
        la_i32 maximum;
        member = &ctx->enum_members[index];
        owner = &ctx->enums[member->owner];
        ctx->active_source_id = owner->source_id;
        if (la_eval_expression(
                ctx, member->value_source,
                member->value_source + member->value_length,
                member->line, &value) != LA_OK) return ctx->error;
        if (owner->is_signed) {
            minimum = owner->size == 1 ? -128 : -32768;
            maximum = owner->size == 1 ? 127 : 32767;
        } else {
            minimum = 0;
            maximum = owner->size == 1 ? 255 : 65535;
        }
        if (value < minimum || value > maximum) {
            return la_fail(ctx, LA_ERR_ENUM_VALUE, member->line, 1, 1,
                           la_name_slice(ctx, member->name),
                           la_name_slice(ctx, owner->name), value, maximum);
        }
        member->value = value;
        member->resolved = 1;
    }
    return LA_OK;
}

static la_u16 la_round_up(la_u16 value, la_u16 alignment)
{
    la_u32 result;
    result = ((la_u32)value + alignment - 1) &
             ~((la_u32)alignment - 1);
    return result > 65535 ? LA_INVALID_HANDLE : (la_u16)result;
}

static LaDiagnosticCode la_resolve_layouts(LaContext *ctx)
{
    la_u16 unresolved;
    la_u16 index;
    int progress;
    for (index = 0; index < ctx->location_count; ++index) {
        if (ctx->locations[index].is_pointer) {
            if (la_find_struct_handle(ctx, ctx->locations[index].type_name) ==
                LA_INVALID_HANDLE) {
                return la_fail(
                    ctx, LA_ERR_UNKNOWN_TYPE, ctx->locations[index].line,
                    1, 1,
                    la_name_slice(ctx, ctx->locations[index].type_name),
                    la_slice("", 0), 0, 0);
            }
        } else {
            la_u16 size;
            if (!la_scalar_size(ctx, ctx->locations[index].type_name,
                                &size)) {
                return la_fail(
                    ctx, LA_ERR_UNKNOWN_TYPE, ctx->locations[index].line,
                    1, 1,
                    la_name_slice(ctx, ctx->locations[index].type_name),
                    la_slice("scalar parameter", 16), 0, 0);
            }
        }
    }
    unresolved = ctx->struct_count;
    do {
        progress = 0;
        for (index = 0; index < ctx->struct_count; ++index) {
            LaStructRec *record;
            la_u16 field_index;
            la_u16 offset;
            la_u16 extent;
            int ready;
            record = &ctx->structs[index];
            if (record->state != 0) {
                continue;
            }
            ready = 1;
            offset = 0;
            extent = 0;
            for (field_index = record->first_field;
                 field_index < record->first_field + record->field_count;
                 ++field_index) {
                LaFieldRec *field;
                la_u16 unit_size;
                la_u16 unit_alignment;
                la_u16 nested;
                la_u16 enumeration;
                la_u16 placement;
                field = &ctx->fields[field_index];
                nested = LA_INVALID_HANDLE;
                enumeration = LA_INVALID_HANDLE;
                if (field->is_pointer) {
                    nested = la_find_struct_handle(ctx, field->type_name);
                    if (nested == LA_INVALID_HANDLE) {
                        return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, field->line,
                                       1, 1,
                                       la_name_slice(ctx, field->type_name),
                                       la_name_slice(ctx, record->name), 0, 0);
                    }
                    unit_size = ctx->target->pointer_units;
                    unit_alignment = unit_size;
                } else if (!la_primitive_size(ctx, field->type_name,
                                              &unit_size)) {
                    enumeration =
                        la_find_enum_handle(ctx, field->type_name);
                    if (enumeration != LA_INVALID_HANDLE) {
                        unit_size = ctx->enums[enumeration].size;
                        unit_alignment = unit_size;
                    } else {
                    nested = la_find_struct_handle(ctx, field->type_name);
                    if (nested == LA_INVALID_HANDLE) {
                        return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, field->line,
                                       1, 1,
                                       la_name_slice(ctx, field->type_name),
                                       la_name_slice(ctx, record->name), 0, 0);
                    }
                    if (ctx->structs[nested].state == 0) {
                        ready = 0;
                        break;
                    }
                    unit_size = ctx->structs[nested].size;
                    unit_alignment = ctx->structs[nested].alignment;
                    }
                } else {
                    unit_alignment = unit_size;
                }
                if (record->policy == LA_LAYOUT_PACKED) {
                    unit_alignment = 1;
                } else if (unit_alignment > record->alignment) {
                    unit_alignment = record->alignment;
                }
                placement = record->kind == LA_AGGREGATE_UNION ? 0 : offset;
                if (record->kind == LA_AGGREGATE_STRUCT &&
                    field->has_explicit_offset) {
                    la_i32 requested;
                    ctx->active_source_id = record->source_id;
                    if (la_eval_expression(
                            ctx, field->offset_source,
                            field->offset_source + field->offset_length,
                            field->line, &requested) != LA_OK) {
                        return ctx->error;
                    }
                    if (requested < 0 || requested > 65535 ||
                        requested < offset) {
                        return la_fail(
                            ctx, LA_ERR_FIELD_OFFSET, field->line, 1, 1,
                            la_name_slice(ctx, field->name),
                            la_name_slice(ctx, record->name),
                            requested, offset);
                    }
                    if ((requested % unit_alignment) != 0) {
                        return la_fail(
                            ctx, LA_ERR_FIELD_OFFSET, field->line, 1, 1,
                            la_name_slice(ctx, field->name),
                            la_slice("effective alignment", 19),
                            requested, unit_alignment);
                    }
                    placement = (la_u16)requested;
                } else if (record->kind == LA_AGGREGATE_STRUCT &&
                           record->policy == LA_LAYOUT_ALIGNED) {
                    placement = la_round_up(offset, unit_alignment);
                    if (placement == LA_INVALID_HANDLE) {
                        return la_fail(ctx, LA_ERR_FIELD_OFFSET,
                                       field->line, 1, 1,
                                       la_name_slice(ctx, field->name),
                                       la_slice("layout overflow", 15),
                                       offset, 65535);
                    }
                }
                if ((la_u32)unit_size * field->count + placement > 65535) {
                    return la_fail(ctx, LA_ERR_SYNTAX, field->line, 1, 1,
                                   la_slice("layout overflow", 15),
                                   la_name_slice(ctx, field->name), 0, 65535);
                }
                field->offset = placement;
                field->size = (la_u16)(unit_size * field->count);
                if (record->kind == LA_AGGREGATE_STRUCT) {
                    offset = (la_u16)(placement + field->size);
                    extent = offset;
                } else if (field->size > extent) {
                    extent = field->size;
                }
            }
            if (ready) {
                if (record->policy == LA_LAYOUT_ALIGNED) {
                    record->size = la_round_up(extent, record->alignment);
                    if (record->size == LA_INVALID_HANDLE) {
                        return la_fail(ctx, LA_ERR_LAYOUT_ALIGNMENT,
                                       record->line, 1, 1,
                                       la_name_slice(ctx, record->name),
                                       la_slice("layout overflow", 15),
                                       extent, 65535);
                    }
                } else {
                    record->size = extent;
                }
                record->state = 1;
                --unresolved;
                progress = 1;
            }
        }
    } while (unresolved != 0 && progress);
    if (unresolved != 0) {
        for (index = 0; index < ctx->struct_count; ++index) {
            if (ctx->structs[index].state == 0) {
                return la_fail(ctx, LA_ERR_LAYOUT_CYCLE,
                               ctx->structs[index].line, 1, 1,
                               la_name_slice(ctx, ctx->structs[index].name),
                               la_slice("", 0), unresolved, 0);
            }
        }
    }
    for (index = 0; index < ctx->pool_count; ++index) {
        la_u16 sid;
        LaPoolRec *pool;
        pool = &ctx->pools[index];
        sid = la_find_struct_handle(ctx, pool->type_name);
        if (sid == LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, pool->line, 1, 1,
                           la_name_slice(ctx, pool->type_name),
                           la_name_slice(ctx, pool->name), 0, 0);
        }
        pool->stride = ctx->structs[sid].size;
        pool->alignment = ctx->structs[sid].alignment;
        if ((la_u32)pool->stride * pool->count > 65535) {
            return la_fail(ctx, LA_ERR_SYNTAX, pool->line, 1, 1,
                           la_slice("pool size overflow", 18),
                           la_name_slice(ctx, pool->name),
                           (la_i32)((la_u32)pool->stride * pool->count),
                           65535);
        }
        pool->size = (la_u16)(pool->stride * pool->count);
    }
    for (index = 0; index < ctx->overlay_count; ++index) {
        la_u16 sid;
        LaOverlayRec *overlay;
        overlay = &ctx->overlays[index];
        sid = la_find_struct_handle(ctx, overlay->type_name);
        if (sid == LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_OVERLAY_TYPE, overlay->line, 1, 1,
                           la_name_slice(ctx, overlay->type_name),
                           la_name_slice(ctx, overlay->name), 0, 0);
        }
        if (overlay->has_numeric_base &&
            overlay->numeric_base % ctx->structs[sid].alignment != 0) {
            return la_fail(ctx, LA_ERR_OVERLAY_ALIGNMENT, overlay->line,
                           1, 1, la_name_slice(ctx, overlay->name),
                           la_name_slice(ctx, overlay->type_name),
                           overlay->numeric_base,
                           ctx->structs[sid].alignment);
        }
    }
    for (index = 0; index < ctx->procedure_count; ++index) {
        LaProcedureRec *procedure;
        const LaConvention *convention;
        la_u16 member_index;
        la_u16 local_index;
        la_u16 scalar_slot;
        procedure = &ctx->procedures[index];
        convention = procedure->convention == LA_INVALID_HANDLE ? 0 :
            &ctx->target->conventions[procedure->convention];
        scalar_slot = 0;
        for (member_index = procedure->first_parameter;
             member_index < procedure->first_parameter +
                            procedure->parameter_count;
             ++member_index) {
            LaLocationRec *member;
            member = &ctx->locations[member_index];
            member->storage_width =
                la_location_storage_units(ctx, member_index);
            if (member->physical != LA_INVALID_HANDLE) {
                LaSlice placement;
                la_u16 declared;
                placement = la_name_slice(ctx, member->physical);
                declared = la_find_location_text(
                    ctx, placement.data, placement.length);
                if (declared != LA_INVALID_HANDLE &&
                    ctx->locations[declared].procedure ==
                        LA_INVALID_HANDLE) {
                    if (member->storage_width !=
                        ctx->locations[declared].storage_width ||
                        member->is_pointer !=
                        ctx->locations[declared].is_pointer) {
                        return la_fail(
                            ctx, LA_ERR_MEMBER_PLACEMENT, member->line,
                            1, placement.length, placement,
                            la_slice("compatible typed location", 25),
                            member->storage_width,
                            ctx->locations[declared].storage_width);
                    }
                    member->physical = ctx->locations[declared].physical;
                    continue;
                }
                if (memchr(placement.data, '.', placement.length) != 0) {
                    return la_fail(
                        ctx, LA_ERR_MEMBER_PLACEMENT, member->line,
                        1, placement.length, placement,
                        la_slice("declared qualified location", 27), 0, 0);
                }
                continue;
            }
            if (procedure->convention == LA_INVALID_HANDLE) {
                return la_fail(ctx, LA_ERR_MEMBER_PLACEMENT, member->line,
                               1, 1, la_name_slice(ctx, member->name),
                               la_slice("using convention or in physical", 31),
                               0, 0);
            }
            if (member->is_pointer) {
                return la_fail(ctx, LA_ERR_MEMBER_PLACEMENT, member->line,
                               1, 1, la_name_slice(ctx, member->name),
                               la_slice("explicit pointer location", 25),
                               0, 0);
            }
            if (member->role == LA_MEMBER_RETURN) {
                member->physical = la_intern(
                    ctx, convention->scalar_return,
                    (la_u16)strlen(convention->scalar_return),
                    member->line, 1);
            } else {
                int assigned;
                assigned = 0;
                while (scalar_slot < convention->scalar_input_count &&
                       !assigned) {
                    la_u16 other_index;
                    int used;
                    used = 0;
                    for (other_index = procedure->first_parameter;
                         other_index < procedure->first_parameter +
                                       procedure->parameter_count;
                         ++other_index) {
                        LaLocationRec *other;
                        LaSlice physical;
                        other = &ctx->locations[other_index];
                        if (other == member ||
                            other->physical == LA_INVALID_HANDLE ||
                            other->role != LA_MEMBER_INPUT) continue;
                        physical = la_name_slice(ctx, other->physical);
                        if (la_equal_text(physical.data, physical.length,
                                          convention->
                                              scalar_inputs[scalar_slot])) {
                            used = 1;
                            break;
                        }
                    }
                    if (!used) {
                        member->physical = la_intern(
                            ctx, convention->scalar_inputs[scalar_slot],
                            (la_u16)strlen(
                                convention->scalar_inputs[scalar_slot]),
                            member->line, 1);
                        assigned = 1;
                    }
                    ++scalar_slot;
                }
                if (!assigned) {
                    return la_fail(ctx, LA_ERR_CONVENTION, member->line,
                                   1, 1, la_name_slice(ctx, member->name),
                                   la_slice("scalar input locations", 22),
                                   convention->scalar_input_count + 1,
                                   convention->scalar_input_count);
                }
            }
            if (member->physical == LA_INVALID_HANDLE) return ctx->error;
        }
        procedure->frame_size = 0;
        for (local_index = procedure->first_local;
             local_index < procedure->first_local + procedure->local_count;
             ++local_index) {
            LaLocalRec *local;
            la_u16 size;
            local = &ctx->locals[local_index];
            if (local->is_pointer) {
                if (la_find_struct_handle(ctx, local->type_name) ==
                    LA_INVALID_HANDLE) {
                    return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, local->line,
                                   1, 1,
                                   la_name_slice(ctx, local->type_name),
                                   la_slice("pointer local", 13), 0, 0);
                }
                size = ctx->target->pointer_units;
            } else if (!la_scalar_size(ctx, local->type_name, &size)) {
                la_u16 sid;
                sid = la_find_struct_handle(ctx, local->type_name);
                if (sid == LA_INVALID_HANDLE) {
                    return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, local->line,
                                   1, 1,
                                   la_name_slice(ctx, local->type_name),
                                   la_slice("frame local", 11), 0, 0);
                }
                size = ctx->structs[sid].size;
                if (ctx->structs[sid].alignment >
                    ctx->target->max_frame_alignment) {
                    return la_fail(
                        ctx, LA_ERR_LAYOUT_ALIGNMENT, local->line, 1, 1,
                        la_name_slice(ctx, local->name),
                        la_slice("frame alignment", 15),
                        ctx->structs[sid].alignment,
                        ctx->target->max_frame_alignment);
                }
            }
            if ((la_u32)procedure->frame_size + size > 255) {
                return la_fail(ctx, LA_ERR_FRAME_LOCAL, local->line, 1, 1,
                               la_name_slice(ctx, local->name),
                               la_slice("frame bytes", 11),
                               procedure->frame_size + size, 255);
            }
            local->offset = procedure->frame_size;
            local->size = size;
            procedure->frame_size =
                (la_u16)(procedure->frame_size + size);
        }
    }
    return LA_OK;
}

static la_u16 la_find_field(LaContext *ctx, la_u16 sid,
                            const char *name, la_u16 length)
{
    la_u16 index;
    LaStructRec *record;
    record = &ctx->structs[sid];
    for (index = record->first_field;
         index < record->first_field + record->field_count; ++index) {
        LaSlice field_name;
        field_name = la_name_slice(ctx, ctx->fields[index].name);
        if (field_name.length == length &&
            memcmp(field_name.data, name, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

static LaDiagnosticCode la_resolve_path(LaContext *ctx,
                                        const char *root, la_u16 root_length,
                                        const char *path, la_u16 path_length,
                                        la_u16 line, la_u16 *field_out,
                                        la_u16 *offset_out)
{
    la_u16 sid;
    la_u16 total;
    const char *cursor;
    const char *end;
    sid = la_find_struct_text(ctx, root, root_length);
    if (sid == LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, line, 1, root_length,
                       la_slice(root, root_length), la_slice("", 0), 0, 0);
    }
    total = 0;
    cursor = path;
    end = path + path_length;
    while (cursor < end) {
        const char *component_end;
        la_u16 field_index;
        component_end = cursor;
        while (component_end < end && *component_end != '.') {
            ++component_end;
        }
        field_index = la_find_field(ctx, sid, cursor,
                                    (la_u16)(component_end - cursor));
        if (field_index == LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_UNKNOWN_FIELD, line, 1,
                           (la_u16)(component_end - cursor),
                           la_slice(cursor,
                                    (la_u16)(component_end - cursor)),
                           la_name_slice(ctx, ctx->structs[sid].name), 0, 0);
        }
        total = (la_u16)(total + ctx->fields[field_index].offset);
        if (component_end == end) {
            *field_out = field_index;
            *offset_out = total;
            return LA_OK;
        }
        if (ctx->fields[field_index].is_pointer) {
            sid = LA_INVALID_HANDLE;
        } else {
            sid = la_find_struct_handle(ctx,
                                        ctx->fields[field_index].type_name);
        }
        if (sid == LA_INVALID_HANDLE || ctx->fields[field_index].count != 1) {
            return la_fail(ctx, LA_ERR_UNKNOWN_FIELD, line, 1,
                           (la_u16)(component_end - cursor),
                           la_slice(cursor,
                                    (la_u16)(component_end - cursor)),
                           la_slice("non-structure", 13), 0, 0);
        }
        cursor = component_end + 1;
    }
    return la_fail(ctx, LA_ERR_UNKNOWN_FIELD, line, 1, path_length,
                   la_slice(path, path_length), la_slice("", 0), 0, 0);
}

static LaDiagnosticCode la_resolve_indexed_path(
    LaContext *ctx, const char *root, la_u16 root_length,
    const char *path, la_u16 path_length, la_u16 line,
    la_u16 *field_out, la_u16 *offset_out, LaSlice *index_out,
    la_u16 *stride_out, la_u16 *count_out)
{
    la_u16 sid;
    la_u16 total;
    const char *cursor;
    const char *end;
    int saw_index;
    sid = la_find_struct_text(ctx, root, root_length);
    if (sid == LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, line, 1, root_length,
                       la_slice(root, root_length), la_slice("", 0), 0, 0);
    }
    total = 0;
    cursor = path;
    end = path + path_length;
    saw_index = 0;
    index_out->data = 0;
    index_out->length = 0;
    *stride_out = 0;
    *count_out = 0;
    while (cursor < end) {
        const char *name_end;
        const char *component_end;
        const char *index_start;
        const char *index_end;
        la_u16 field_index;
        int indexed;
        name_end = cursor;
        while (name_end < end && *name_end != '.' && *name_end != '[') {
            ++name_end;
        }
        component_end = name_end;
        indexed = 0;
        index_start = 0;
        index_end = 0;
        if (name_end < end && *name_end == '[') {
            indexed = 1;
            index_start = name_end + 1;
            index_end = index_start;
            while (index_end < end && *index_end != ']') ++index_end;
            if (index_end == end || index_end == index_start) {
                return la_fail(ctx, LA_ERR_INDEXED_FIELD, line, 1,
                               (la_u16)(end - name_end),
                               la_slice(name_end,
                                        (la_u16)(end - name_end)),
                               la_slice("closed physical index", 21), 0, 0);
            }
            component_end = index_end + 1;
        }
        field_index = la_find_field(ctx, sid, cursor,
                                    (la_u16)(name_end - cursor));
        if (field_index == LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_UNKNOWN_FIELD, line, 1,
                           (la_u16)(name_end - cursor),
                           la_slice(cursor, (la_u16)(name_end - cursor)),
                           la_name_slice(ctx, ctx->structs[sid].name), 0, 0);
        }
        total = (la_u16)(total + ctx->fields[field_index].offset);
        if (indexed) {
            const char *check;
            LaSlice expected;
            if (saw_index || ctx->fields[field_index].count == 1) {
                if (saw_index) {
                    expected = la_slice("one index", 9);
                } else {
                    expected = la_slice("array field", 11);
                }
                return la_fail(ctx, LA_ERR_INDEXED_FIELD, line, 1,
                               (la_u16)(component_end - cursor),
                               la_slice(cursor,
                                        (la_u16)(component_end - cursor)),
                               expected,
                               ctx->fields[field_index].count, 0);
            }
            check = index_start;
            if (!la_is_ident_start(*check)) {
                return la_fail(ctx, LA_ERR_INDEX_LOCATION, line, 1,
                               (la_u16)(index_end - index_start),
                               la_slice(index_start,
                                        (la_u16)(index_end - index_start)),
                               la_slice("physical index", 14), 0, 0);
            }
            while (check < index_end && la_is_ident(*check)) ++check;
            if (check != index_end) {
                return la_fail(ctx, LA_ERR_INDEX_LOCATION, line, 1,
                               (la_u16)(index_end - index_start),
                               la_slice(index_start,
                                        (la_u16)(index_end - index_start)),
                               la_slice("physical index", 14), 0, 0);
            }
            index_out->data = index_start;
            index_out->length = (la_u16)(index_end - index_start);
            *stride_out = (la_u16)(ctx->fields[field_index].size /
                                   ctx->fields[field_index].count);
            *count_out = ctx->fields[field_index].count;
            saw_index = 1;
        } else if (ctx->fields[field_index].count != 1) {
            return la_fail(ctx, LA_ERR_INDEXED_FIELD, line, 1,
                           (la_u16)(name_end - cursor),
                           la_slice(cursor, (la_u16)(name_end - cursor)),
                           la_slice("array index", 11), 0, 0);
        }
        if (component_end == end) {
            *field_out = field_index;
            *offset_out = total;
            if (!saw_index) {
                return la_fail(ctx, LA_ERR_INDEXED_FIELD, line, 1,
                               path_length, la_slice(path, path_length),
                               la_slice("indexed array", 13), 0, 0);
            }
            return LA_OK;
        }
        if (*component_end != '.') {
            return la_fail(ctx, LA_ERR_INDEXED_FIELD, line, 1,
                           (la_u16)(end - component_end),
                           la_slice(component_end,
                                    (la_u16)(end - component_end)),
                           la_slice(".", 1), 0, 0);
        }
        if (ctx->fields[field_index].is_pointer) {
            sid = LA_INVALID_HANDLE;
        } else {
            sid = la_find_struct_handle(ctx,
                                        ctx->fields[field_index].type_name);
        }
        if (sid == LA_INVALID_HANDLE) {
            return la_fail(ctx, LA_ERR_UNKNOWN_FIELD, line, 1,
                           (la_u16)(name_end - cursor),
                           la_slice(cursor, (la_u16)(name_end - cursor)),
                           la_slice("non-structure", 13), 0, 0);
        }
        cursor = component_end + 1;
    }
    return la_fail(ctx, LA_ERR_INDEXED_FIELD, line, 1, path_length,
                   la_slice(path, path_length), la_slice("", 0), 0, 0);
}

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

/* Expression families for the bitwise/comparison mixing rule. A bitwise
   operand of a comparison, equality or logical operator must be
   parenthesized, and vice versa; parentheses and plain arithmetic reset a
   value to the neutral family. */
enum {
    LA_EXPR_NEUTRAL = 0,
    LA_EXPR_BITWISE = 1,
    LA_EXPR_CMPLOGIC = 2
};

static int la_precedence(la_u8 op)
{
    if (op == LA_OP_OR) return 1;
    if (op == LA_OP_AND) return 2;
    if (op == LA_OP_EQ || op == LA_OP_NE) return 3;
    if (op == LA_OP_LT || op == LA_OP_LE ||
        op == LA_OP_GT || op == LA_OP_GE) return 4;
    if (op == LA_OP_BOR) return 5;
    if (op == LA_OP_BXOR) return 6;
    if (op == LA_OP_BAND) return 7;
    if (op == LA_OP_SHL || op == LA_OP_SHR) return 8;
    if (op == LA_OP_ADD || op == LA_OP_SUB) return 9;
    if (op == LA_OP_MUL || op == LA_OP_DIV || op == LA_OP_MOD) return 10;
    if (op == LA_OP_NOT || op == LA_OP_NEG || op == LA_OP_BNOT) return 11;
    return 0;
}

static la_u8 la_op_family(la_u8 op)
{
    if (op == LA_OP_BOR || op == LA_OP_BXOR || op == LA_OP_BAND ||
        op == LA_OP_SHL || op == LA_OP_SHR || op == LA_OP_BNOT) {
        return LA_EXPR_BITWISE;
    }
    if (op == LA_OP_OR || op == LA_OP_AND ||
        op == LA_OP_EQ || op == LA_OP_NE ||
        op == LA_OP_LT || op == LA_OP_LE ||
        op == LA_OP_GT || op == LA_OP_GE || op == LA_OP_NOT) {
        return LA_EXPR_CMPLOGIC;
    }
    return LA_EXPR_NEUTRAL;
}

static int la_family_conflict(la_u8 op_family, la_u8 operand_family)
{
    if (op_family == LA_EXPR_BITWISE &&
        operand_family == LA_EXPR_CMPLOGIC) return 1;
    if (op_family == LA_EXPR_CMPLOGIC &&
        operand_family == LA_EXPR_BITWISE) return 1;
    return 0;
}

static int la_layout_query_suffix(const char *text, la_u16 length,
                                  const char **suffix,
                                  la_u16 *suffix_length)
{
    if (la_equal_text(text, length, "offset")) {
        *suffix = "offset";
        *suffix_length = 6;
    } else if (la_equal_text(text, length, "sizeof")) {
        *suffix = "size";
        *suffix_length = 4;
    } else if (la_equal_text(text, length, "alignof")) {
        *suffix = "align";
        *suffix_length = 5;
    } else if (la_equal_text(text, length, "countof")) {
        *suffix = "count";
        *suffix_length = 5;
    } else if (la_equal_text(text, length, "strideof")) {
        *suffix = "stride";
        *suffix_length = 6;
    } else {
        return 0;
    }
    return 1;
}

static la_u16 la_field_alignment(LaContext *ctx, la_u16 field_index)
{
    LaFieldRec *field;
    la_u16 alignment;
    la_u16 owner;
    la_u16 nested;
    la_u16 enumeration;
    field = &ctx->fields[field_index];
    if (field->is_pointer) {
        alignment = ctx->target->pointer_units;
    } else if (la_primitive_size(ctx, field->type_name, &alignment)) {
        /* Primitive size is its native alignment. */
    } else {
        enumeration = la_find_enum_handle(ctx, field->type_name);
        if (enumeration != LA_INVALID_HANDLE) {
            alignment = ctx->enums[enumeration].size;
        } else {
            nested = la_find_struct_handle(ctx, field->type_name);
            if (nested == LA_INVALID_HANDLE) return 0;
            alignment = ctx->structs[nested].alignment;
        }
    }
    for (owner = 0; owner < ctx->struct_count; ++owner) {
        LaStructRec *record;
        record = &ctx->structs[owner];
        if (field_index >= record->first_field &&
            field_index < record->first_field + record->field_count) {
            if (record->policy == LA_LAYOUT_PACKED) return 1;
            if (alignment > record->alignment) {
                alignment = record->alignment;
            }
            break;
        }
    }
    return alignment;
}

static LaDiagnosticCode la_apply_operator(LaContext *ctx, la_u8 op,
                                          la_u16 *value_count,
                                          la_u16 line)
{
    la_i32 left;
    la_i32 right;
    la_u8 op_family;
    op_family = la_op_family(op);
    if (op == LA_OP_NOT || op == LA_OP_NEG || op == LA_OP_BNOT) {
        if (*value_count < 1) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_slice("expression operand", 18),
                           la_slice("", 0), 0, 0);
        }
        if (la_family_conflict(op_family,
                               ctx->values[*value_count - 1].family)) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_slice("parenthesized bitwise mix", 25),
                           la_slice("", 0), 0, 0);
        }
        right = ctx->values[*value_count - 1].value;
        ctx->values[*value_count - 1].value =
            op == LA_OP_NOT ? !right :
            op == LA_OP_BNOT ? (la_i32)~(la_u32)right : -right;
        ctx->values[*value_count - 1].family = op_family;
        return LA_OK;
    }
    if (*value_count < 2) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("binary operands", 15),
                       la_slice("", 0), 0, 0);
    }
    if (la_family_conflict(op_family,
                           ctx->values[*value_count - 1].family) ||
        la_family_conflict(op_family,
                           ctx->values[*value_count - 2].family)) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("parenthesized bitwise mix", 25),
                       la_slice("", 0), 0, 0);
    }
    right = ctx->values[*value_count - 1].value;
    left = ctx->values[*value_count - 2].value;
    *value_count = (la_u16)(*value_count - 1);
    switch (op) {
    case LA_OP_OR: left = left || right; break;
    case LA_OP_AND: left = left && right; break;
    case LA_OP_EQ: left = left == right; break;
    case LA_OP_NE: left = left != right; break;
    case LA_OP_LT: left = left < right; break;
    case LA_OP_LE: left = left <= right; break;
    case LA_OP_GT: left = left > right; break;
    case LA_OP_GE: left = left >= right; break;
    case LA_OP_ADD: left += right; break;
    case LA_OP_SUB: left -= right; break;
    case LA_OP_MUL: left *= right; break;
    case LA_OP_BOR: left = (la_i32)((la_u32)left | (la_u32)right); break;
    case LA_OP_BXOR: left = (la_i32)((la_u32)left ^ (la_u32)right); break;
    case LA_OP_BAND: left = (la_i32)((la_u32)left & (la_u32)right); break;
    case LA_OP_SHL:
    case LA_OP_SHR:
        if (right < 0 || right > 31) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_slice("shift count 0..31", 17),
                           la_slice("", 0), right, 31);
        }
        left = op == LA_OP_SHL ?
            (la_i32)((la_u32)left << right) :
            (la_i32)((la_u32)left >> right);
        break;
    case LA_OP_DIV:
        if (right == 0) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_slice("division by zero", 16),
                           la_slice("", 0), 0, 0);
        }
        left /= right;
        break;
    case LA_OP_MOD:
        if (right == 0) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_slice("modulo by zero", 14),
                           la_slice("", 0), 0, 0);
        }
        left %= right;
        break;
    default:
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("operator", 8), la_slice("", 0), op, 0);
    }
    ctx->values[*value_count - 1].value = left;
    ctx->values[*value_count - 1].family = op_family;
    return LA_OK;
}

static LaDiagnosticCode la_property_value(LaContext *ctx,
                                          const char *text, la_u16 length,
                                          la_u16 line, la_i32 *value)
{
    const char *last_dot;
    const char *first_dot;
    const char *cursor;
    la_u16 sid;
    la_u16 pool_index;
    la_u16 enum_index;
    la_u16 constant_index;
    la_u16 scope;
    la_u16 source_id;
    constant_index = LA_INVALID_HANDLE;
    source_id = la_source_id_at_line(ctx, line);
    if (memchr(text, '.', length) != 0) {
        la_u16 index;
        for (index = 0; index < ctx->constant_count; ++index) {
            LaSlice name;
            name = la_name_slice(
                ctx, ctx->constants[index].name);
            if (name.length == length &&
                memcmp(name.data, text, length) == 0) {
                constant_index = index;
                break;
            }
        }
    } else {
        scope = la_namespace_at_line(ctx, line);
        while (scope != LA_INVALID_HANDLE &&
               constant_index == LA_INVALID_HANDLE) {
            LaSlice owner;
            la_u16 total;
            la_u16 index;
            owner = la_name_slice(
                ctx, ctx->namespaces[scope].name);
            total = (la_u16)(owner.length + 1 + length);
            if ((la_u32)total + 1 <= ctx->limits->max_line_bytes) {
                memcpy(ctx->path_buffer, owner.data, owner.length);
                ctx->path_buffer[owner.length] = '.';
                memcpy(ctx->path_buffer + owner.length + 1,
                       text, length);
                for (index = 0; index < ctx->constant_count; ++index) {
                    LaSlice name;
                    name = la_name_slice(
                        ctx, ctx->constants[index].name);
                    if (name.length == total &&
                        memcmp(name.data, ctx->path_buffer, total) == 0) {
                        constant_index = index;
                        break;
                    }
                }
            }
            scope = ctx->namespaces[scope].parent;
        }
    }
    if (constant_index != LA_INVALID_HANDLE &&
        constant_index < ctx->constant_count) {
        LaConstantRec *constant;
        constant = &ctx->constants[constant_index];
        if (constant->source_id != source_id &&
            !la_name_is_exported(ctx, constant->name)) {
            return la_fail(ctx, LA_ERR_PRIVATE_NAME, line, 1, length,
                           la_name_slice(ctx, constant->name),
                           la_slice("export", 6), 0, 0);
        }
        if (!constant->resolved) {
            return la_fail(ctx, LA_ERR_UNKNOWN_CONSTANT, line, 1, length,
                           la_name_slice(ctx, constant->name),
                           la_slice("unresolved or forward constant", 30),
                           0, 0);
        }
        *value = constant->value;
        return LA_OK;
    }
    last_dot = 0;
    first_dot = 0;
    for (cursor = text; cursor < text + length; ++cursor) {
        if (*cursor == '.') {
            if (first_dot == 0) first_dot = cursor;
            last_dot = cursor;
        }
    }
    if (first_dot == 0 || last_dot == 0) {
        return la_fail(ctx, LA_ERR_BAD_PROPERTY, line, 1, length,
                       la_slice(text, length), la_slice("", 0), 0, 0);
    }
    enum_index = la_find_enum_text(ctx, text,
                                   (la_u16)(first_dot - text));
    if (enum_index != LA_INVALID_HANDLE && first_dot == last_dot) {
        LaEnumRec *enumeration;
        const char *member_text;
        la_u16 member_length;
        la_u16 member_index;
        enumeration = &ctx->enums[enum_index];
        member_text = first_dot + 1;
        member_length =
            (la_u16)(text + length - member_text);
        if (la_equal_text(member_text, member_length, "size")) {
            *value = enumeration->size;
            return LA_OK;
        }
        if (la_equal_text(member_text, member_length, "align")) {
            *value = 1;
            return LA_OK;
        }
        for (member_index = enumeration->first_member;
             member_index < enumeration->first_member +
                            enumeration->member_count;
             ++member_index) {
            LaEnumMemberRec *member;
            LaSlice member_name;
            member = &ctx->enum_members[member_index];
            member_name = la_name_slice(ctx, member->name);
            if (member_name.length == member_length &&
                memcmp(member_name.data, member_text, member_length) == 0) {
                if (!member->resolved) {
                    return la_fail(
                        ctx, LA_ERR_ENUM_VALUE, line, 1, length,
                        la_slice(text, length),
                        la_slice("unresolved or forward enum member", 33),
                        0, 0);
                }
                *value = member->value;
                return LA_OK;
            }
        }
        return la_fail(ctx, LA_ERR_ENUM_VALUE, line, 1, length,
                       la_slice(text, length),
                       la_name_slice(ctx, enumeration->name), 0, 0);
    }
    pool_index = la_find_pool_text(ctx, text,
                                   (la_u16)(first_dot - text));
    if (pool_index != LA_INVALID_HANDLE && first_dot == last_dot) {
        LaSlice property;
        property = la_slice(first_dot + 1,
                            (la_u16)(text + length - first_dot - 1));
        if (la_equal_text(property.data, property.length, "size")) {
            *value = ctx->pools[pool_index].size;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "count")) {
            *value = ctx->pools[pool_index].count;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "stride")) {
            *value = ctx->pools[pool_index].stride;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "align")) {
            *value = ctx->pools[pool_index].alignment;
            return LA_OK;
        }
        return la_fail(ctx, LA_ERR_BAD_PROPERTY, line, 1, property.length,
                       property, la_name_slice(ctx,
                                               ctx->pools[pool_index].name),
                       0, 0);
    }
    sid = la_find_struct_text(ctx, text, (la_u16)(first_dot - text));
    if (sid == LA_INVALID_HANDLE) {
        return la_fail(ctx, LA_ERR_UNKNOWN_TYPE, line, 1,
                       (la_u16)(first_dot - text),
                       la_slice(text, (la_u16)(first_dot - text)),
                       la_slice("", 0), 0, 0);
    }
    if (first_dot == last_dot) {
        LaSlice property;
        property = la_slice(first_dot + 1,
                            (la_u16)(text + length - first_dot - 1));
        if (la_equal_text(property.data, property.length, "size")) {
            *value = ctx->structs[sid].size;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "align")) {
            *value = ctx->structs[sid].alignment;
            return LA_OK;
        }
        return la_fail(ctx, LA_ERR_BAD_PROPERTY, line, 1, property.length,
                       property, la_name_slice(ctx, ctx->structs[sid].name),
                       0, 0);
    } else {
        la_u16 field_index;
        la_u16 offset;
        LaSlice property;
        property = la_slice(last_dot + 1,
                            (la_u16)(text + length - last_dot - 1));
        if (la_resolve_path(ctx, text, (la_u16)(first_dot - text),
                            first_dot + 1,
                            (la_u16)(last_dot - first_dot - 1), line,
                            &field_index, &offset) != LA_OK) {
            return ctx->error;
        }
        if (la_equal_text(property.data, property.length, "offset")) {
            *value = offset;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "size")) {
            *value = ctx->fields[field_index].size;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "align")) {
            *value = la_field_alignment(ctx, field_index);
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "count")) {
            if (ctx->fields[field_index].count == 1) {
                return la_fail(ctx, LA_ERR_BAD_PROPERTY, line, 1,
                               property.length, property,
                               la_slice("scalar field", 12), 0, 0);
            }
            *value = ctx->fields[field_index].count;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "stride")) {
            if (ctx->fields[field_index].count == 1) {
                return la_fail(ctx, LA_ERR_BAD_PROPERTY, line, 1,
                               property.length, property,
                               la_slice("scalar field", 12), 0, 0);
            }
            *value = ctx->fields[field_index].size /
                     ctx->fields[field_index].count;
            return LA_OK;
        }
        return la_fail(ctx, LA_ERR_BAD_PROPERTY, line, 1, property.length,
                       property, la_slice("field property", 14), 0, 0);
    }
}

static LaDiagnosticCode la_eval_expression(LaContext *ctx,
                                           const char *text, const char *end,
                                           la_u16 line, la_i32 *result)
{
    const char *cursor;
    la_u16 value_count;
    la_u16 op_count;
    int expect_value;
    cursor = text;
    value_count = 0;
    op_count = 0;
    expect_value = 1;
    while (1) {
        la_u8 op;
        cursor = la_trim_left(cursor, end);
        if (cursor == end) break;
        if (expect_value) {
            la_i32 value;
            if (*cursor == '(') {
                if (op_count >= ctx->limits->max_expression_nodes ||
                    op_count >= ctx->limits->max_nesting) {
                    return la_fail(ctx, LA_ERR_NESTING_CAPACITY, line,
                                   (la_u16)(cursor - text + 1), 1,
                                   la_slice("expression nesting", 18),
                                   la_slice("", 0), op_count + 1,
                                   ctx->limits->max_nesting);
                }
                ctx->operators[op_count++].op = LA_OP_LPAREN;
                if (op_count > ctx->stats->nesting) {
                    ctx->stats->nesting = op_count;
                }
                ++cursor;
                continue;
            }
            if (*cursor == '!' || *cursor == '-' || *cursor == '~') {
                op = *cursor == '!' ? LA_OP_NOT :
                     *cursor == '~' ? LA_OP_BNOT : LA_OP_NEG;
                if (op_count >= ctx->limits->max_expression_nodes) {
                    return la_fail(ctx, LA_ERR_EXPRESSION_CAPACITY, line,
                                   (la_u16)(cursor - text + 1), 1,
                                   la_slice("operators", 9), la_slice("", 0),
                                   op_count + 1,
                                   ctx->limits->max_expression_nodes);
                }
                ctx->operators[op_count++].op = op;
                ++cursor;
                continue;
            }
            if (*cursor == '$') {
                int digits;
                value = 0;
                digits = 0;
                ++cursor;
                while (cursor < end) {
                    int digit;
                    if (*cursor >= '0' && *cursor <= '9') {
                        digit = *cursor - '0';
                    } else if (*cursor >= 'a' && *cursor <= 'f') {
                        digit = *cursor - 'a' + 10;
                    } else if (*cursor >= 'A' && *cursor <= 'F') {
                        digit = *cursor - 'A' + 10;
                    } else {
                        break;
                    }
                    value = value * 16 + digit;
                    ++cursor;
                    ++digits;
                }
                if (digits == 0) {
                    return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                                   la_slice("hexadecimal value", 17),
                                   la_slice("", 0), 0, 0);
                }
            } else if (*cursor >= '0' && *cursor <= '9') {
                value = 0;
                while (cursor < end && *cursor >= '0' && *cursor <= '9') {
                    value = value * 10 + (*cursor - '0');
                    ++cursor;
                }
            } else if (la_is_ident_start(*cursor)) {
                const char *start;
                const char *suffix;
                const char *path_start;
                la_u16 token_length;
                la_u16 suffix_length;
                start = cursor;
                while (cursor < end &&
                       (la_is_ident(*cursor) || *cursor == '.')) {
                    ++cursor;
                }
                token_length = (la_u16)(cursor - start);
                if (la_layout_query_suffix(
                        start, token_length, &suffix, &suffix_length)) {
                    la_u16 path_length;
                    la_u16 total;
                    cursor = la_trim_left(cursor, end);
                    path_start = cursor;
                    while (cursor < end &&
                           (la_is_ident(*cursor) || *cursor == '.')) {
                        ++cursor;
                    }
                    path_length = (la_u16)(cursor - path_start);
                    total = (la_u16)(
                        path_length + 1 + suffix_length);
                    if (path_length == 0 ||
                        (la_u32)total + 1 >
                            ctx->limits->max_line_bytes) {
                        return la_fail(
                            ctx, LA_ERR_SYNTAX, line, 1, token_length,
                            la_slice("layout query path", 17),
                            la_slice(start, token_length), total + 1,
                            ctx->limits->max_line_bytes);
                    }
                    memcpy(ctx->path_buffer, path_start, path_length);
                    ctx->path_buffer[path_length] = '.';
                    memcpy(ctx->path_buffer + path_length + 1,
                           suffix, suffix_length);
                    if (la_property_value(
                            ctx, ctx->path_buffer, total, line,
                            &value) != LA_OK) {
                        return ctx->error;
                    }
                } else if (la_property_value(
                               ctx, start, token_length, line,
                               &value) != LA_OK) {
                    return ctx->error;
                }
            } else {
                return la_fail(ctx, LA_ERR_SYNTAX, line,
                               (la_u16)(cursor - text + 1), 1,
                               la_slice("expression value", 16),
                               la_slice(cursor, 1), 0, 0);
            }
            if (value_count >= ctx->limits->max_expression_nodes) {
                return la_fail(ctx, LA_ERR_EXPRESSION_CAPACITY, line,
                               (la_u16)(cursor - text + 1), 1,
                               la_slice("values", 6), la_slice("", 0),
                               value_count + 1,
                               ctx->limits->max_expression_nodes);
            }
            ctx->values[value_count].family = LA_EXPR_NEUTRAL;
            ctx->values[value_count++].value = value;
            if (value_count + op_count > ctx->stats->expression_nodes) {
                ctx->stats->expression_nodes =
                    (la_u16)(value_count + op_count);
            }
            while (op_count > 0 &&
                   (ctx->operators[op_count - 1].op == LA_OP_NOT ||
                    ctx->operators[op_count - 1].op == LA_OP_NEG ||
                    ctx->operators[op_count - 1].op == LA_OP_BNOT)) {
                op = ctx->operators[--op_count].op;
                if (la_apply_operator(ctx, op, &value_count, line) != LA_OK) {
                    return ctx->error;
                }
            }
            expect_value = 0;
        } else if (*cursor == ')') {
            while (op_count > 0 &&
                   ctx->operators[op_count - 1].op != LA_OP_LPAREN) {
                op = ctx->operators[--op_count].op;
                if (la_apply_operator(ctx, op, &value_count, line) != LA_OK) {
                    return ctx->error;
                }
            }
            if (op_count == 0) {
                return la_fail(ctx, LA_ERR_SYNTAX, line,
                               (la_u16)(cursor - text + 1), 1,
                               la_slice("matching (", 10), la_slice("", 0),
                               0, 0);
            }
            --op_count;
            /* A parenthesized result returns to the neutral family. */
            if (value_count > 0) {
                ctx->values[value_count - 1].family = LA_EXPR_NEUTRAL;
            }
            ++cursor;
        } else {
            la_u8 next_op;
            next_op = LA_OP_NONE;
            if ((la_u16)(end - cursor) >= 2) {
                if (cursor[0] == '|' && cursor[1] == '|') next_op = LA_OP_OR;
                else if (cursor[0] == '&' && cursor[1] == '&') next_op = LA_OP_AND;
                else if (cursor[0] == '=' && cursor[1] == '=') next_op = LA_OP_EQ;
                else if (cursor[0] == '!' && cursor[1] == '=') next_op = LA_OP_NE;
                else if (cursor[0] == '<' && cursor[1] == '=') next_op = LA_OP_LE;
                else if (cursor[0] == '>' && cursor[1] == '=') next_op = LA_OP_GE;
                else if (cursor[0] == '<' && cursor[1] == '<') next_op = LA_OP_SHL;
                else if (cursor[0] == '>' && cursor[1] == '>') next_op = LA_OP_SHR;
                if (next_op != LA_OP_NONE) cursor += 2;
            }
            if (next_op == LA_OP_NONE) {
                if (*cursor == '<') next_op = LA_OP_LT;
                else if (*cursor == '>') next_op = LA_OP_GT;
                else if (*cursor == '+') next_op = LA_OP_ADD;
                else if (*cursor == '-') next_op = LA_OP_SUB;
                else if (*cursor == '*') next_op = LA_OP_MUL;
                else if (*cursor == '/') next_op = LA_OP_DIV;
                else if (*cursor == '%') next_op = LA_OP_MOD;
                else if (*cursor == '&') next_op = LA_OP_BAND;
                else if (*cursor == '^') next_op = LA_OP_BXOR;
                else if (*cursor == '|') next_op = LA_OP_BOR;
                if (next_op != LA_OP_NONE) ++cursor;
            }
            if (next_op == LA_OP_NONE) {
                return la_fail(ctx, LA_ERR_SYNTAX, line,
                               (la_u16)(cursor - text + 1), 1,
                               la_slice("expression operator", 19),
                               la_slice(cursor, 1), 0, 0);
            }
            while (op_count > 0 &&
                   ctx->operators[op_count - 1].op != LA_OP_LPAREN &&
                   la_precedence(ctx->operators[op_count - 1].op) >=
                   la_precedence(next_op)) {
                op = ctx->operators[--op_count].op;
                if (la_apply_operator(ctx, op, &value_count, line) != LA_OK) {
                    return ctx->error;
                }
            }
            if (op_count >= ctx->limits->max_expression_nodes) {
                return la_fail(ctx, LA_ERR_EXPRESSION_CAPACITY, line, 1, 1,
                               la_slice("operators", 9), la_slice("", 0),
                               op_count + 1,
                               ctx->limits->max_expression_nodes);
            }
            ctx->operators[op_count++].op = next_op;
            expect_value = 1;
        }
    }
    if (expect_value || value_count == 0) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("complete expression", 19),
                       la_slice("", 0), 0, 0);
    }
    while (op_count > 0) {
        la_u8 op;
        op = ctx->operators[--op_count].op;
        if (op == LA_OP_LPAREN) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_slice("matching )", 10), la_slice("", 0),
                           0, 0);
        }
        if (la_apply_operator(ctx, op, &value_count, line) != LA_OK) {
            return ctx->error;
        }
    }
    if (value_count != 1) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_slice("single expression result", 24),
                       la_slice("", 0), value_count, 1);
    }
    *result = ctx->values[0].value;
    ctx->expression_family = ctx->values[0].family;
    return LA_OK;
}

static LaDiagnosticCode la_check_assertions(LaContext *ctx)
{
    const char *cursor;
    la_u16 line;
    la_reset_lines(ctx);
    line = 0;
    while (1) {
        const char *line_end;
        const char *content_end;
        const char *trimmed;
        if (la_next_line(ctx, &cursor, &line_end, &line) <= 0) break;
        content_end = la_code_end(cursor, line_end);
        trimmed = la_trim_left(cursor, content_end);
        if (la_line_keyword(trimmed, content_end, "static_assert")) {
            la_i32 value;
            const char *expression;
            expression = trimmed + 13;
            expression = la_trim_left(expression, content_end);
            if (la_eval_expression(ctx, expression, content_end,
                                   line, &value) != LA_OK) {
                return ctx->error;
            }
            if (!value) {
                return la_fail(ctx, LA_ERR_ASSERTION, line,
                               (la_u16)(expression - cursor + 1),
                               (la_u16)(content_end - expression),
                               la_slice(expression,
                                        (la_u16)(content_end - expression)),
                               la_slice("", 0), value, 1);
            }
        }
    }
    return LA_OK;
}

static LaDiagnosticCode la_resolve_constants(LaContext *ctx)
{
    la_u16 index;
    for (index = 0; index < ctx->constant_count; ++index) {
        LaConstantRec *constant;
        la_i32 value;
        constant = &ctx->constants[index];
        ctx->active_source_id = constant->source_id;
        if (la_eval_expression(
                ctx, constant->value_source,
                constant->value_source + constant->value_length,
                constant->line, &value) != LA_OK) {
            return ctx->error;
        }
        constant->value = value;
        constant->resolved = 1;
    }
    return LA_OK;
}

static int la_write_event(LaContext *ctx, LaEvent *event)
{
    if (ctx->events == 0 || ctx->events->write == 0) return 1;
    if (!ctx->events->write(ctx->events->context, event)) {
        la_fail(ctx, LA_ERR_IO, event->span.line, event->span.column,
                event->span.length, la_slice("event sink", 10),
                la_slice("", 0), 0, 0);
        return 0;
    }
    return 1;
}

static void la_init_event(LaContext *ctx, LaEvent *event, LaEventKind kind,
                          la_u16 line, la_u16 length)
{
    memset(event, 0, sizeof(*event));
    event->kind = kind;
    la_set_span(ctx, &event->span, line, 1, length);
}

static int la_emit_property(LaContext *ctx, la_u16 line,
                            LaSlice owner, LaSlice path,
                            LaPropertyKind kind, la_u16 value)
{
    LaEvent event;
    la_u16 aggregate;
    la_init_event(ctx, &event, LA_EVENT_PROPERTY, line, 1);
    event.owner = owner;
    event.path = path;
    event.property = kind;
    event.value = value;
    aggregate = la_find_struct_text(ctx, owner.data, owner.length);
    if (aggregate != LA_INVALID_HANDLE) {
        event.aggregate_kind =
            (LaAggregateKind)ctx->structs[aggregate].kind;
        event.layout_policy =
            (LaLayoutPolicy)ctx->structs[aggregate].policy;
    }
    return la_write_event(ctx, &event);
}

static int la_emit_field_offset(LaContext *ctx, LaFieldRec *field,
                                LaSlice owner, LaSlice path, la_u16 value)
{
    LaEvent event;
    la_u16 aggregate;
    la_init_event(ctx, &event, LA_EVENT_PROPERTY, field->line, 1);
    event.owner = owner;
    event.path = path;
    event.property = LA_PROPERTY_FIELD_OFFSET;
    event.value = value;
    event.explicit_offset = field->has_explicit_offset;
    aggregate = la_find_struct_text(ctx, owner.data, owner.length);
    if (aggregate != LA_INVALID_HANDLE) {
        event.aggregate_kind =
            (LaAggregateKind)ctx->structs[aggregate].kind;
        event.layout_policy =
            (LaLayoutPolicy)ctx->structs[aggregate].policy;
    }
    return la_write_event(ctx, &event);
}

static int la_append_path(LaContext *ctx, la_u16 *path_length,
                          LaSlice component)
{
    la_u16 needed;
    needed = component.length + (*path_length != 0 ? 1 : 0);
    if ((la_u32)*path_length + needed + 1 >
        ctx->limits->max_line_bytes) {
        la_fail(ctx, LA_ERR_NESTING_CAPACITY, 1, 1, 1,
                la_slice("field path bytes", 16), la_slice("", 0),
                *path_length + needed + 1,
                ctx->limits->max_line_bytes);
        return 0;
    }
    if (*path_length != 0) ctx->path_buffer[(*path_length)++] = '.';
    memcpy(ctx->path_buffer + *path_length, component.data, component.length);
    *path_length = (la_u16)(*path_length + component.length);
    ctx->path_buffer[*path_length] = 0;
    return 1;
}

static int la_emit_struct_properties(LaContext *ctx, la_u16 root_sid)
{
    LaSlice owner;
    la_u16 depth;
    la_u16 path_length;
    owner = la_name_slice(ctx, ctx->structs[root_sid].name);
    if (!la_emit_property(ctx, ctx->structs[root_sid].line, owner,
                          la_slice("", 0), LA_PROPERTY_STRUCT_SIZE,
                          ctx->structs[root_sid].size)) return 0;
    if (!la_emit_property(ctx, ctx->structs[root_sid].line, owner,
                          la_slice("", 0), LA_PROPERTY_STRUCT_ALIGN,
                          ctx->structs[root_sid].alignment)) {
        return 0;
    }
    depth = 0;
    path_length = 0;
    ctx->frames[0].sid = root_sid;
    ctx->frames[0].next_field = ctx->structs[root_sid].first_field;
    ctx->frames[0].base = 0;
    ctx->frames[0].path_length = 0;
    while (1) {
        LaPropertyFrame *frame;
        LaStructRec *record;
        frame = &ctx->frames[depth];
        record = &ctx->structs[frame->sid];
        if (frame->next_field >=
            record->first_field + record->field_count) {
            if (depth == 0) break;
            path_length = frame->path_length;
            ctx->path_buffer[path_length] = 0;
            --depth;
            continue;
        } else {
            la_u16 field_index;
            LaFieldRec *field;
            LaSlice field_name;
            la_u16 nested_sid;
            la_u16 saved_path;
            field_index = frame->next_field++;
            field = &ctx->fields[field_index];
            field_name = la_name_slice(ctx, field->name);
            saved_path = path_length;
            if (!la_append_path(ctx, &path_length, field_name)) return 0;
            if (!la_emit_field_offset(
                    ctx, field, owner,
                    la_slice(ctx->path_buffer, path_length),
                    (la_u16)(frame->base + field->offset))) {
                return 0;
            }
            if (!la_emit_property(ctx, field->line, owner,
                                  la_slice(ctx->path_buffer, path_length),
                                  LA_PROPERTY_FIELD_SIZE, field->size)) {
                return 0;
            }
            if (field->count != 1) {
                la_u16 stride;
                stride = (la_u16)(field->size / field->count);
                if (!la_emit_property(ctx, field->line, owner,
                                      la_slice(ctx->path_buffer, path_length),
                                      LA_PROPERTY_FIELD_COUNT, field->count) ||
                    !la_emit_property(ctx, field->line, owner,
                                      la_slice(ctx->path_buffer, path_length),
                                      LA_PROPERTY_FIELD_STRIDE, stride)) {
                    return 0;
                }
            }
            nested_sid = field->is_pointer ? LA_INVALID_HANDLE :
                la_find_struct_handle(ctx, field->type_name);
            if (nested_sid != LA_INVALID_HANDLE && field->count == 1) {
                if (depth + 1 >= ctx->limits->max_nesting) {
                    la_fail(ctx, LA_ERR_NESTING_CAPACITY, field->line, 1, 1,
                            la_slice("layout nesting", 14), owner,
                            depth + 2, ctx->limits->max_nesting);
                    return 0;
                }
                ++depth;
                if (depth + 1 > ctx->stats->nesting) {
                    ctx->stats->nesting = (la_u16)(depth + 1);
                }
                ctx->frames[depth].sid = nested_sid;
                ctx->frames[depth].next_field =
                    ctx->structs[nested_sid].first_field;
                ctx->frames[depth].base =
                    (la_u16)(frame->base + field->offset);
                ctx->frames[depth].path_length = saved_path;
            } else {
                path_length = saved_path;
                ctx->path_buffer[path_length] = 0;
            }
        }
    }
    return 1;
}

static la_u16 la_procedure_at_line(LaContext *ctx, la_u16 line)
{
    la_u16 index;
    for (index = 0; index < ctx->procedure_count; ++index) {
        if (ctx->procedures[index].source_id == ctx->active_source_id &&
            line > ctx->procedures[index].begin_line &&
            line < ctx->procedures[index].end_line) return index;
    }
    return LA_INVALID_HANDLE;
}

static int la_parse_typed_operation(LaContext *ctx,
                                    const char *start, const char *end,
                                    la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *bracket;
    const char *close;
    const char *base_start;
    const char *base_end;
    const char *root_start;
    const char *first_dot;
    const char *path_start;
    la_u16 location_index;
    la_u16 overlay_index;
    la_u16 root_length;
    la_u16 field_index;
    la_u16 offset;
    la_u16 procedure;
    la_u16 stride;
    la_u16 count;
    la_u16 leaf_size;
    LaSlice index;
    LaSlice base_type;
    int indexed;
    int is_overlay;
    LaTargetOperationKind operation;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) >= 4 && memcmp(cursor, "lda ", 4) == 0) {
        operation = LA_TARGET_OP_LOAD8_PTR_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "sta ", 4) == 0) {
        operation = LA_TARGET_OP_STORE8_PTR_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "cmp ", 4) == 0) {
        operation = LA_TARGET_OP_CMP8_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "stx ", 4) == 0) {
        operation = LA_TARGET_OP_STOREX_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "sty ", 4) == 0) {
        operation = LA_TARGET_OP_STOREY_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "and ", 4) == 0) {
        operation = LA_TARGET_OP_AND8A_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "ora ", 4) == 0) {
        operation = LA_TARGET_OP_ORA8A_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "ldx ", 4) == 0) {
        operation = LA_TARGET_OP_LOADX_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "ldy ", 4) == 0) {
        operation = LA_TARGET_OP_LOADY_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "add ", 4) == 0) {
        operation = LA_TARGET_OP_ADD8A_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "sub ", 4) == 0) {
        operation = LA_TARGET_OP_SUB8A_OVERLAY_DISP;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "adc ", 4) == 0) {
        operation = LA_TARGET_OP_ADC8_OVERLAY_INDEXED;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "sbc ", 4) == 0) {
        operation = LA_TARGET_OP_SBC8_OVERLAY_INDEXED;
    } else {
        return 0;
    }
    bracket = cursor + 3;
    bracket = la_trim_left(bracket, end);
    if (bracket >= end || *bracket != '[') return 0;
    close = end;
    while (close > bracket && la_is_space(close[-1])) --close;
    if (close <= bracket || close[-1] != ']') return 0;
    --close;
    base_start = la_trim_left(bracket + 1, close);
    base_end = base_start;
    while (base_end < close && la_is_ident(*base_end)) ++base_end;
    if (base_end == base_start) return 0;
    cursor = la_trim_left(base_end, close);
    if (cursor >= close || (*cursor != '+' && *cursor != '.')) return 0;
    procedure = la_procedure_at_line(ctx, line);
    overlay_index = LA_INVALID_HANDLE;
    is_overlay = 0;
    /* The base may be namespace-qualified (e.g. Machine.object): swallow
       dotted components until the accumulated name resolves to a location or
       overlay, so the remaining .field path belongs to that base's type. */
    for (;;) {
        location_index = la_find_location_text_at(
            ctx, base_start, (la_u16)(base_end - base_start), procedure);
        if (location_index != LA_INVALID_HANDLE) break;
        overlay_index = la_find_overlay_text(
            ctx, base_start, (la_u16)(base_end - base_start));
        if (overlay_index != LA_INVALID_HANDLE) {
            is_overlay = 1;
            break;
        }
        if (base_end < close && *base_end == '.' &&
            base_end + 1 < close && la_is_ident_start(base_end[1])) {
            const char *scan;
            scan = base_end + 1;
            while (scan < close && la_is_ident(*scan)) ++scan;
            base_end = scan;
            continue;
        }
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line,
                (la_u16)(base_start - start + 1),
                (la_u16)(base_end - base_start),
                la_slice(base_start, (la_u16)(base_end - base_start)),
                la_slice("typed location or overlay", 25), 0, 0);
        return -1;
    }
    cursor = la_trim_left(base_end, close);
    if (is_overlay) {
        base_type = la_name_slice(ctx, ctx->overlays[overlay_index].type_name);
    } else {
        base_type = la_name_slice(ctx, ctx->locations[location_index].type_name);
    }
    if (*cursor == '.') {
        /* Shorthand [base.field]: the field's struct type is the base's own
           declared type, so it need not be restated. */
        root_start = base_type.data;
        root_length = base_type.length;
        path_start = cursor + 1;
    } else {
        /* Explicit [base + Type.field]: the restated type is cross-checked
           against the base's declared type. */
        ++cursor;
        root_start = la_trim_left(cursor, close);
        first_dot = root_start;
        while (first_dot < close && *first_dot != '.') ++first_dot;
        if (first_dot == close) return 0;
        root_length = (la_u16)(first_dot - root_start);
        path_start = first_dot + 1;
        if (base_type.length != root_length ||
            memcmp(base_type.data, root_start, root_length) != 0) {
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line,
                    (la_u16)(root_start - start + 1), root_length,
                    base_type, la_slice(root_start, root_length), 0, 0);
            return -1;
        }
    }
    indexed = memchr(path_start, '[', (size_t)(close - path_start)) != 0;
    index.data = 0;
    index.length = 0;
    stride = 0;
    count = 0;
    if (indexed) {
        if (la_resolve_indexed_path(
                ctx, root_start, root_length, path_start,
                (la_u16)(close - path_start), line, &field_index, &offset,
                &index, &stride, &count) != LA_OK) return -1;
        if (!is_overlay) {
            if (!la_equal_text(index.data, index.length, "x")) {
                la_fail(ctx, LA_ERR_INDEX_LOCATION, line, 1, index.length,
                        index, la_slice("x", 1), 0, 0);
                return -1;
            }
        } else if (!la_equal_text(index.data, index.length, "x") &&
                   !la_equal_text(index.data, index.length, "y")) {
            /* Absolute indexed addressing accepts either physical index. */
            la_fail(ctx, LA_ERR_INDEX_LOCATION, line, 1, index.length,
                    index, la_slice("x or y", 6), 0, 0);
            return -1;
        }
        if ((!is_overlay &&
             stride != 1 && stride != 2 && stride != 4 && stride != 8) ||
            (is_overlay && stride != 1)) {
            la_fail(ctx, LA_ERR_INDEX_STRIDE, line, 1, index.length,
                    index, la_slice(is_overlay ? "1" : "1, 2, 4, or 8",
                                    is_overlay ? 1 : 13),
                    stride, is_overlay ? 1 : 8);
            return -1;
        }
        if (is_overlay) {
            /* Absolute indexed access (ADDR + field, Y): the field offset is
               part of the 16-bit base address, so only the index range must
               fit the 8-bit physical register. This lets page views past the
               first 256 bytes be reached without hidden scratch. */
            if ((la_u32)(count - 1) * stride > 255) {
                la_fail(ctx, LA_ERR_DISPLACEMENT, line, 1, index.length,
                        index, la_slice("index register range", 20),
                        (la_i32)((la_u32)(count - 1) * stride), 255);
                return -1;
            }
        } else if ((la_u32)offset + (la_u32)(count - 1) * stride >
                   ctx->target->max_displacement) {
            la_fail(ctx, LA_ERR_DISPLACEMENT, line, 1, index.length,
                    index, la_slice("indexed displacement", 20),
                    (la_i32)((la_u32)offset +
                             (la_u32)(count - 1) * stride),
                    ctx->target->max_displacement);
            return -1;
        }
    } else if (la_resolve_path(ctx, root_start, root_length, path_start,
                               (la_u16)(close - path_start), line,
                               &field_index, &offset) != LA_OK) {
        return -1;
    }
    leaf_size = ctx->fields[field_index].count == 1 ?
        ctx->fields[field_index].size :
        (la_u16)(ctx->fields[field_index].size /
                 ctx->fields[field_index].count);
    if (leaf_size != 1 ||
        (!indexed && ctx->fields[field_index].count != 1)) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line,
                (la_u16)(path_start - start + 1),
                (la_u16)(close - path_start),
                la_name_slice(ctx, ctx->fields[field_index].name),
                la_slice("byte", 4), leaf_size, 1);
        return -1;
    }
    /* A fixed overlay field is reached by absolute addressing, so its offset
       is part of the 16-bit address and is not bound by the pointer
       displacement window. */
    if (!is_overlay && offset > ctx->target->max_displacement) {
        la_fail(ctx, LA_ERR_DISPLACEMENT, line,
                (la_u16)(path_start - start + 1),
                (la_u16)(close - path_start),
                la_slice(path_start, (la_u16)(close - path_start)),
                la_slice("", 0), offset, ctx->target->max_displacement);
        return -1;
    }
    if (ctx->operation_count >= ctx->limits->max_operations) {
        la_fail(ctx, LA_ERR_OPERATION_CAPACITY, line, 1, 1,
                la_slice("target operations", 17), la_slice("", 0),
                ctx->operation_count + 1, ctx->limits->max_operations);
        return -1;
    }
    ++ctx->operation_count;
    ctx->stats->operations = ctx->operation_count;
    event->kind = LA_EVENT_TARGET_OPERATION;
    la_set_span(ctx, &event->span, line, 1, (la_u16)(end - start));
    event->text = la_slice("", 0);
    event->owner = la_slice(root_start, root_length);
    event->path = la_slice(path_start, (la_u16)(close - path_start));
    if (is_overlay) {
        event->base =
            la_name_slice(ctx, ctx->overlays[overlay_index].base);
    } else {
        event->base =
            la_name_slice(ctx, ctx->locations[location_index].physical);
    }
    event->index = index;
    event->aux = la_slice("", 0);
    event->aux2 = la_slice("", 0);
    event->property = (LaPropertyKind)0;
    if (operation == LA_TARGET_OP_ADC8_OVERLAY_INDEXED ||
        operation == LA_TARGET_OP_SBC8_OVERLAY_INDEXED) {
        /* Carry-chain arithmetic through an indexed fixed-overlay array (the
           effects structure-of-arrays); the accumulator and carry are live. */
        if (!is_overlay || !indexed) {
            la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                    (la_u16)(end - start),
                    la_slice(start, (la_u16)(end - start)),
                    la_slice("indexed fixed-overlay carry arithmetic", 38),
                    0, 0);
            return -1;
        }
        if (!ctx->target->overlay_byte_operations ||
            !ctx->target->indexed_overlay_byte_operations) {
            la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                    (la_u16)(end - start),
                    la_slice(start, (la_u16)(end - start)),
                    la_slice("indexed overlay byte access", 27), 0, 0);
            return -1;
        }
        event->operation = operation;
        event->access_width = 1;
        event->clobbers = la_slice("a,flags", 7);
        event->volatility = ctx->overlays[overlay_index].volatile_access ?
            LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    } else if (operation == LA_TARGET_OP_CMP8_OVERLAY_DISP ||
        operation == LA_TARGET_OP_STOREX_OVERLAY_DISP ||
        operation == LA_TARGET_OP_STOREY_OVERLAY_DISP ||
        operation == LA_TARGET_OP_AND8A_OVERLAY_DISP ||
        operation == LA_TARGET_OP_ORA8A_OVERLAY_DISP ||
        operation == LA_TARGET_OP_LOADX_OVERLAY_DISP ||
        operation == LA_TARGET_OP_LOADY_OVERLAY_DISP ||
        operation == LA_TARGET_OP_ADD8A_OVERLAY_DISP ||
        operation == LA_TARGET_OP_SUB8A_OVERLAY_DISP) {
        /* Accumulator compare/logic and physical-register loads/stores are
           registered only against a non-indexed fixed overlay field; the
           pointer-indirect and indexed variants stay raw and reviewed. */
        int sets_flags;
        if (!is_overlay || indexed) {
            la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                    (la_u16)(end - start),
                    la_slice(start, (la_u16)(end - start)),
                    la_slice("fixed-overlay accumulator or register op", 40),
                    0, 0);
            return -1;
        }
        if (!ctx->target->overlay_byte_operations) {
            la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                    (la_u16)(end - start),
                    la_slice(start, (la_u16)(end - start)),
                    la_slice("static overlay byte access", 26), 0, 0);
            return -1;
        }
        /* stx/sty leave the flags untouched; the rest update N and Z. */
        sets_flags = operation != LA_TARGET_OP_STOREX_OVERLAY_DISP &&
                     operation != LA_TARGET_OP_STOREY_OVERLAY_DISP;
        event->operation = operation;
        event->access_width = 1;
        event->scratch = la_slice("", 0);
        if (sets_flags) {
            event->clobbers = la_slice("flags", 5);
        } else {
            event->clobbers = la_slice("", 0);
        }
        event->volatility = ctx->overlays[overlay_index].volatile_access ?
            LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    } else if (is_overlay) {
        if (!ctx->target->overlay_byte_operations) {
            la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                    (la_u16)(end - start),
                    la_slice(start, (la_u16)(end - start)),
                    la_slice("static overlay byte access", 26), 0, 0);
            return -1;
        }
        if (indexed && !ctx->target->indexed_overlay_byte_operations) {
            la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                    (la_u16)(end - start),
                    la_slice(start, (la_u16)(end - start)),
                    la_slice("indexed overlay byte access", 27), 0, 0);
            return -1;
        }
        event->operation = indexed ?
            (operation == LA_TARGET_OP_LOAD8_PTR_DISP ?
                LA_TARGET_OP_LOAD8_OVERLAY_INDEXED :
                LA_TARGET_OP_STORE8_OVERLAY_INDEXED) :
            (operation == LA_TARGET_OP_LOAD8_PTR_DISP ?
                LA_TARGET_OP_LOAD8_OVERLAY_DISP :
                LA_TARGET_OP_STORE8_OVERLAY_DISP);
        event->volatility = ctx->overlays[overlay_index].volatile_access ?
            LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    } else {
        event->operation = indexed ?
        (operation == LA_TARGET_OP_LOAD8_PTR_DISP ?
            LA_TARGET_OP_LOAD8_PTR_INDEXED :
            LA_TARGET_OP_STORE8_PTR_INDEXED) : operation;
    }
    event->value = offset;
    event->stride = stride;
    event->count = count;
    if (!is_overlay) event->volatility = LA_ACCESS_NONVOLATILE;
    return 1;
}

static int la_resolve_field_tail(LaContext *ctx, const char *start,
                                 const char *cursor, const char *close,
                                 la_u16 line, LaSlice base_type,
                                 const char **root_start,
                                 la_u16 *root_length,
                                 const char **path_start);

static int la_parse_typed_word_operation(LaContext *ctx,
                                         const char *start,
                                         const char *end,
                                         la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *word_start;
    const char *word_end;
    const char *bracket;
    const char *close;
    const char *base_start;
    const char *base_end;
    const char *root_start;
    const char *path_start;
    la_u16 word_location;
    la_u16 pointer_location;
    la_u16 root_length;
    la_u16 field_index;
    la_u16 field_offset;
    la_u16 field_size;
    la_u16 word_size;
    la_u16 procedure;
    int store;
    int immediate_store;
    la_i32 immediate_value;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) >= 4 && memcmp(cursor, "ldw ", 4) == 0) {
        store = 0;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "stw ", 4) == 0) {
        store = 1;
    } else {
        return 0;
    }
    if (!ctx->target->pointer_word_operations) {
        la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                (la_u16)(end - start),
                la_slice(start, (la_u16)(end - start)),
                la_slice("typed pointer word transfer", 27), 0, 0);
        return -1;
    }
    cursor = la_trim_left(cursor + 3, end);
    if (store) {
        bracket = cursor;
    } else {
        word_start = cursor;
        while (cursor < end && la_is_ident(*cursor)) ++cursor;
        word_end = cursor;
        cursor = la_trim_left(cursor, end);
        if (word_end == word_start || cursor >= end || *cursor++ != ',') {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("ldw WORD, [pointer + Type.field]", 34),
                    la_slice("", 0), 0, 0);
            return -1;
        }
        bracket = la_trim_left(cursor, end);
    }
    if (bracket >= end || *bracket != '[') {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("[pointer + Type.field]", 22),
                la_slice("", 0), 0, 0);
        return -1;
    }
    close = bracket + 1;
    while (close < end && *close != ']') ++close;
    if (close == end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("]", 1), la_slice("", 0), 0, 0);
        return -1;
    }
    base_start = la_trim_left(bracket + 1, close);
    base_end = base_start;
    while (base_end < close && la_is_ident(*base_end)) ++base_end;
    la_extend_qualified_base(ctx, base_start, &base_end, close,
                             la_procedure_at_line(ctx, line));
    cursor = la_trim_left(base_end, close);
    if (base_end == base_start || cursor >= close ||
        (*cursor != '.' && *cursor != '+')) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("[pointer.field]", 15),
                la_slice("", 0), 0, 0);
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    pointer_location = la_find_location_text_at(
        ctx, base_start, (la_u16)(base_end - base_start), procedure);
    if (pointer_location == LA_INVALID_HANDLE ||
        !ctx->locations[pointer_location].is_pointer) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                (la_u16)(base_end - base_start),
                la_slice(base_start, (la_u16)(base_end - base_start)),
                la_slice("typed pointer", 13), 0, 0);
        return -1;
    }
    {
        int tail;
        tail = la_resolve_field_tail(
            ctx, start, cursor, close, line,
            la_name_slice(ctx, ctx->locations[pointer_location].type_name),
            &root_start, &root_length, &path_start);
        if (tail == 0) return 0;
        if (tail < 0) return -1;
    }
    cursor = la_trim_left(close + 1, end);
    immediate_store = 0;
    immediate_value = 0;
    if (store) {
        if (cursor >= end || *cursor++ != ',') {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("stw [pointer + Type.field], WORD", 34),
                    la_slice("", 0), 0, 0);
            return -1;
        }
        cursor = la_trim_left(cursor, end);
        if (cursor < end && *cursor == '#') {
            /* stw [pointer + Type.field], #expr16 */
            ++cursor;
            if (la_eval_expression(ctx, cursor, end, line,
                                   &immediate_value) != LA_OK) return -1;
            if (ctx->expression_family == LA_EXPR_BITWISE) {
                immediate_value =
                    (la_i32)((la_u32)immediate_value & 0xffff);
            }
            if (immediate_value < -32768 || immediate_value > 65535) {
                la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                        (la_u16)(end - cursor),
                        la_slice(cursor, (la_u16)(end - cursor)),
                        la_slice("16-bit immediate", 16),
                        immediate_value, 65535);
                return -1;
            }
            immediate_store = 1;
            word_start = cursor;
            word_end = end;
            cursor = end;
        } else {
            word_start = cursor;
            while (cursor < end && la_is_ident(*cursor)) ++cursor;
            word_end = cursor;
        }
    }
    if (word_end == word_start || la_trim_left(cursor, end) != end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice(store ? "stw [pointer + Type.field], WORD" :
                                 "ldw WORD, [pointer + Type.field]",
                         34),
                la_slice("", 0), 0, 0);
        return -1;
    }
    word_location = LA_INVALID_HANDLE;
    if (!immediate_store) {
        word_location = la_find_location_text_at(
            ctx, word_start, (la_u16)(word_end - word_start), procedure);
        if (word_location == LA_INVALID_HANDLE ||
            ctx->locations[word_location].is_pointer ||
            !la_scalar_size(ctx, ctx->locations[word_location].type_name,
                            &word_size) ||
            word_size != 2) {
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                    (la_u16)(word_end - word_start),
                    la_slice(word_start, (la_u16)(word_end - word_start)),
                    la_slice("physical two-unit word", 22), 0, 0);
            return -1;
        }
    }
    if (la_resolve_path(ctx, root_start, root_length, path_start,
                        (la_u16)(close - path_start), line,
                        &field_index, &field_offset) != LA_OK) {
        return -1;
    }
    field_size = ctx->fields[field_index].count == 1 ?
        ctx->fields[field_index].size :
        (la_u16)(ctx->fields[field_index].size /
                 ctx->fields[field_index].count);
    if (ctx->fields[field_index].count != 1 || field_size != 2) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                (la_u16)(close - path_start),
                la_name_slice(ctx, ctx->fields[field_index].name),
                la_slice("two-unit word", 13), field_size, 2);
        return -1;
    }
    if ((la_u32)field_offset + 1 > ctx->target->max_displacement) {
        la_fail(ctx, LA_ERR_DISPLACEMENT, line, 1,
                (la_u16)(close - path_start),
                la_slice(path_start, (la_u16)(close - path_start)),
                la_slice("word displacement", 17),
                (la_i32)((la_u32)field_offset + 1),
                ctx->target->max_displacement);
        return -1;
    }
    if (ctx->operation_count >= ctx->limits->max_operations) {
        la_fail(ctx, LA_ERR_OPERATION_CAPACITY, line, 1, 1,
                la_slice("target operations", 17), la_slice("", 0),
                ctx->operation_count + 1, ctx->limits->max_operations);
        return -1;
    }
    ++ctx->operation_count;
    ctx->stats->operations = ctx->operation_count;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->operation = immediate_store ? LA_TARGET_OP_STORE16_IMM_PTR_DISP :
                       store ? LA_TARGET_OP_STORE16_PTR_DISP :
                               LA_TARGET_OP_LOAD16_PTR_DISP;
    event->owner = la_slice(root_start, root_length);
    event->path = la_slice(path_start, (la_u16)(close - path_start));
    event->base =
        la_name_slice(ctx, ctx->locations[pointer_location].physical);
    if (immediate_store) {
        event->signed_value = immediate_value;
    } else {
        event->aux =
            la_name_slice(ctx, ctx->locations[word_location].physical);
    }
    event->scratch = la_slice("a", 1);
    event->clobbers = la_slice("a,flags", 7);
    event->value = field_offset;
    event->access_width = 2;
    event->byte_order = ctx->target->byte_order;
    event->volatility = LA_ACCESS_NONVOLATILE;
    return 1;
}

static int la_parse_physical_word_arithmetic(LaContext *ctx,
                                             const char *start,
                                             const char *end,
                                             la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *left_start;
    const char *left_end;
    const char *right_start;
    const char *right_end;
    la_u16 right_location;
    la_u16 right_size;
    la_u16 procedure;
    LaTargetOperationKind operation;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) >= 5 && memcmp(cursor, "addw ", 5) == 0) {
        operation = LA_TARGET_OP_ADD16_PHYSICAL;
    } else if ((la_u16)(end - cursor) >= 5 &&
               memcmp(cursor, "subw ", 5) == 0) {
        operation = LA_TARGET_OP_SUB16_PHYSICAL;
    } else if ((la_u16)(end - cursor) >= 5 &&
               memcmp(cursor, "cmpw ", 5) == 0) {
        operation = LA_TARGET_OP_CMP16_PHYSICAL;
    } else {
        return 0;
    }
    cursor = la_trim_left(cursor + 4, end);
    left_start = cursor;
    while (cursor < end && la_is_ident(*cursor)) ++cursor;
    left_end = cursor;
    cursor = la_trim_left(cursor, end);
    if (left_end == left_start || cursor >= end || *cursor++ != ',') {
        return 0;
    }
    if (!ctx->target->physical_word_arithmetic ||
        ctx->target->word_accumulator == 0) {
        la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                (la_u16)(end - start),
                la_slice(start, (la_u16)(end - start)),
                la_slice("physical word arithmetic", 24), 0, 0);
        return -1;
    }
    if (!la_equal_text(left_start, (la_u16)(left_end - left_start),
                       ctx->target->word_accumulator)) {
        la_fail(ctx, LA_ERR_MEMBER_PLACEMENT, line, 1,
                (la_u16)(left_end - left_start),
                la_slice(left_start, (la_u16)(left_end - left_start)),
                la_slice(ctx->target->word_accumulator,
                         (la_u16)strlen(ctx->target->word_accumulator)),
                0, 0);
        return -1;
    }
    cursor = la_trim_left(cursor, end);
    right_start = cursor;
    while (cursor < end && la_is_ident(*cursor)) ++cursor;
    right_end = cursor;
    if (right_end == right_start || la_trim_left(cursor, end) != end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("OP ab, WORD", 11), la_slice("", 0), 0, 0);
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    right_location = la_find_location_text_at(
        ctx, right_start, (la_u16)(right_end - right_start), procedure);
    if (right_location == LA_INVALID_HANDLE ||
        ctx->locations[right_location].is_pointer ||
        !la_scalar_size(ctx, ctx->locations[right_location].type_name,
                        &right_size) ||
        right_size != 2) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                (la_u16)(right_end - right_start),
                la_slice(right_start, (la_u16)(right_end - right_start)),
                la_slice("physical two-unit word", 22), 0, 0);
        return -1;
    }
    if (ctx->operation_count >= ctx->limits->max_operations) {
        la_fail(ctx, LA_ERR_OPERATION_CAPACITY, line, 1, 1,
                la_slice("target operations", 17), la_slice("", 0),
                ctx->operation_count + 1, ctx->limits->max_operations);
        return -1;
    }
    ++ctx->operation_count;
    ctx->stats->operations = ctx->operation_count;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->operation = operation;
    event->base = la_slice(
        ctx->target->word_accumulator,
        (la_u16)strlen(ctx->target->word_accumulator));
    event->aux =
        la_name_slice(ctx, ctx->locations[right_location].physical);
    event->access_width = 2;
    event->byte_order = ctx->target->byte_order;
    if (operation == LA_TARGET_OP_CMP16_PHYSICAL) {
        event->clobbers = la_slice("n,z,c", 5);
    } else {
        event->clobbers = la_slice("ab,n,v,z,c", 10);
    }
    return 1;
}

/* Resolve the field tail of a bracketed operand after the base identifier:
   either `.field` (shorthand: the field's struct type is the base's own
   declared type, `base_type`, so it need not be restated) or `+ Type.field`
   (explicit: the restated type is cross-checked against `base_type`).
   Returns 1 on success, 0 to decline (not a field tail), -1 on a
   type-mismatch error. The root_start and root_length outputs give the
   struct-type text; path_start gives the field path. `cursor` points at the
   character after the base identifier; `close` is the ']'. */
static int la_resolve_field_tail(LaContext *ctx, const char *start,
                                 const char *cursor, const char *close,
                                 la_u16 line, LaSlice base_type,
                                 const char **root_start, la_u16 *root_length,
                                 const char **path_start)
{
    const char *first_dot;
    if (cursor >= close) return 0;
    if (*cursor == '.') {
        *root_start = base_type.data;
        *root_length = base_type.length;
        *path_start = cursor + 1;
        return 1;
    }
    if (*cursor != '+') return 0;
    cursor = la_trim_left(cursor + 1, close);
    first_dot = cursor;
    while (first_dot < close && *first_dot != '.') ++first_dot;
    if (first_dot == close) return 0;
    *root_start = cursor;
    *root_length = (la_u16)(first_dot - cursor);
    *path_start = first_dot + 1;
    if (base_type.length != *root_length ||
        memcmp(base_type.data, *root_start, *root_length) != 0) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line,
                (la_u16)(*root_start - start + 1), *root_length,
                base_type, la_slice(*root_start, *root_length), 0, 0);
        return -1;
    }
    return 1;
}

static int la_parse_typed_byte_rmw(LaContext *ctx,
                                   const char *start, const char *end,
                                   la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *bracket;
    const char *close;
    const char *base_start;
    const char *base_end;
    const char *root_start;
    const char *path_start;
    const char *immediate_start;
    la_u16 pointer_location;
    la_u16 overlay_base;
    la_u16 root_length;
    la_u16 field_index;
    la_u16 field_offset;
    la_u16 field_size;
    la_u16 procedure;
    la_i32 immediate;
    LaTargetOperationKind operation;
    int needs_immediate;
    int rmw_is_overlay;
    cursor = la_trim_left(start, end);
    needs_immediate = 0;
    if ((la_u16)(end - cursor) >= 4 && memcmp(cursor, "inc ", 4) == 0) {
        operation = LA_TARGET_OP_INC8_PTR_DISP;
        cursor += 3;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "dec ", 4) == 0) {
        operation = LA_TARGET_OP_DEC8_PTR_DISP;
        cursor += 3;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "and ", 4) == 0) {
        operation = LA_TARGET_OP_AND8_PTR_DISP;
        cursor += 3;
        needs_immediate = 1;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "ora ", 4) == 0) {
        operation = LA_TARGET_OP_OR8_PTR_DISP;
        cursor += 3;
        needs_immediate = 1;
    } else {
        return 0;
    }
    bracket = la_trim_left(cursor, end);
    if (bracket >= end || *bracket != '[') return 0;
    if (!ctx->target->pointer_byte_rmw_operations) {
        la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                (la_u16)(end - start),
                la_slice(start, (la_u16)(end - start)),
                la_slice("typed pointer byte update", 25), 0, 0);
        return -1;
    }
    close = bracket + 1;
    while (close < end && *close != ']') ++close;
    if (close == end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("]", 1), la_slice("", 0), 0, 0);
        return -1;
    }
    base_start = la_trim_left(bracket + 1, close);
    base_end = base_start;
    while (base_end < close && la_is_ident(*base_end)) ++base_end;
    la_extend_qualified_base(ctx, base_start, &base_end, close,
                             la_procedure_at_line(ctx, line));
    cursor = la_trim_left(base_end, close);
    if (base_end == base_start || cursor >= close ||
        (*cursor != '.' && *cursor != '+')) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("[base.field]", 12),
                la_slice("", 0), 0, 0);
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    pointer_location = la_find_location_text_at(
        ctx, base_start, (la_u16)(base_end - base_start), procedure);
    overlay_base = LA_INVALID_HANDLE;
    rmw_is_overlay = 0;
    if (pointer_location == LA_INVALID_HANDLE) {
        /* A fixed overlay base updates an absolute address in place. */
        overlay_base = la_find_overlay_text(
            ctx, base_start, (la_u16)(base_end - base_start));
        if (overlay_base == LA_INVALID_HANDLE) {
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                    (la_u16)(base_end - base_start),
                    la_slice(base_start, (la_u16)(base_end - base_start)),
                    la_slice("typed pointer or overlay", 24), 0, 0);
            return -1;
        }
        rmw_is_overlay = 1;
    }
    {
        LaSlice base_type;
        int tail;
        if (rmw_is_overlay) {
            base_type =
                la_name_slice(ctx, ctx->overlays[overlay_base].type_name);
        } else {
            base_type =
                la_name_slice(ctx, ctx->locations[pointer_location].type_name);
        }
        tail = la_resolve_field_tail(ctx, start, cursor, close, line, base_type,
                                     &root_start, &root_length, &path_start);
        if (tail == 0) return 0;
        if (tail < 0) return -1;
    }
    cursor = la_trim_left(close + 1, end);
    immediate = 0;
    if (needs_immediate) {
        if (cursor >= end || *cursor != ',') {
            /* No immediate operand: this is an accumulator logic read
               (and/ora [base.field]), not a mask read-modify-write. Let the
               byte operand parser handle it. */
            return 0;
        }
        ++cursor;
        cursor = la_trim_left(cursor, end);
        if (cursor >= end || *cursor++ != '#') {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("#VALUE", 6), la_slice("", 0), 0, 0);
            return -1;
        }
        immediate_start = cursor;
        if (la_eval_expression(ctx, immediate_start, end, line,
                               &immediate) != LA_OK) return -1;
        /* A bitwise result is masked to the operand width; other values
           keep the strict range check. */
        if (ctx->expression_family == LA_EXPR_BITWISE) {
            immediate = (la_i32)((la_u32)immediate & 0xff);
        }
        if (immediate < 0 || immediate > 255) {
            la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                    (la_u16)(end - immediate_start),
                    la_slice(immediate_start,
                             (la_u16)(end - immediate_start)),
                    la_slice("byte immediate", 14), immediate, 255);
            return -1;
        }
    } else if (cursor != end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1,
                (la_u16)(end - cursor),
                la_slice("end of byte update", 18),
                la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
        return -1;
    }
    if (la_resolve_path(ctx, root_start, root_length, path_start,
                        (la_u16)(close - path_start), line,
                        &field_index, &field_offset) != LA_OK) return -1;
    field_size = ctx->fields[field_index].count == 1 ?
        ctx->fields[field_index].size :
        (la_u16)(ctx->fields[field_index].size /
                 ctx->fields[field_index].count);
    if (ctx->fields[field_index].count != 1 || field_size != 1) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                (la_u16)(close - path_start),
                la_name_slice(ctx, ctx->fields[field_index].name),
                la_slice("byte", 4), field_size, 1);
        return -1;
    }
    /* A fixed overlay names an absolute address, so the field displacement is
       not bounded by the target's pointer displacement window. */
    if (!rmw_is_overlay && field_offset > ctx->target->max_displacement) {
        la_fail(ctx, LA_ERR_DISPLACEMENT, line, 1,
                (la_u16)(close - path_start),
                la_slice(path_start, (la_u16)(close - path_start)),
                la_slice("", 0), field_offset,
                ctx->target->max_displacement);
        return -1;
    }
    if (ctx->operation_count >= ctx->limits->max_operations) {
        la_fail(ctx, LA_ERR_OPERATION_CAPACITY, line, 1, 1,
                la_slice("target operations", 17), la_slice("", 0),
                ctx->operation_count + 1, ctx->limits->max_operations);
        return -1;
    }
    ++ctx->operation_count;
    ctx->stats->operations = ctx->operation_count;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->owner = la_slice(root_start, root_length);
    event->path = la_slice(path_start, (la_u16)(close - path_start));
    event->value = field_offset;
    event->offset = (la_u16)immediate;
    event->access_width = 1;
    if (rmw_is_overlay) {
        /* inc/dec lower to a native read-modify-write that clobbers no
           register; and/ora still need the accumulator. */
        int is_mask;
        is_mask = (operation == LA_TARGET_OP_AND8_PTR_DISP ||
                   operation == LA_TARGET_OP_OR8_PTR_DISP);
        event->operation =
            operation == LA_TARGET_OP_INC8_PTR_DISP ?
                LA_TARGET_OP_INC8_OVERLAY_ABS :
            operation == LA_TARGET_OP_DEC8_PTR_DISP ?
                LA_TARGET_OP_DEC8_OVERLAY_ABS :
            operation == LA_TARGET_OP_AND8_PTR_DISP ?
                LA_TARGET_OP_AND8_OVERLAY_ABS :
                LA_TARGET_OP_OR8_OVERLAY_ABS;
        event->base = la_name_slice(ctx, ctx->overlays[overlay_base].base);
        if (is_mask) {
            event->scratch = la_slice("a", 1);
            event->clobbers = la_slice("a,flags", 7);
        } else {
            event->scratch = la_slice("", 0);
            event->clobbers = la_slice("flags", 5);
        }
        event->volatility = ctx->overlays[overlay_base].volatile_access ?
            LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    } else {
        event->operation = operation;
        event->base =
            la_name_slice(ctx, ctx->locations[pointer_location].physical);
        event->scratch = la_slice("a", 1);
        event->clobbers = la_slice("a,flags", 7);
        event->volatility = LA_ACCESS_NONVOLATILE;
    }
    return 1;
}

static int la_count_operation(LaContext *ctx, la_u16 line);
static int la_process_operation_line(LaContext *ctx, const char *cursor,
                                     const char *content_end,
                                     const char *line_end, la_u16 line);
static int la_capture_inline_line(LaContext *ctx, la_u16 procedure,
                                  const char *start, const char *end,
                                  la_u16 line);
static int la_expand_inline_body(LaContext *ctx, la_u16 callee,
                                 la_u16 caller, la_u16 line);

/* decz [pointer + Type.field], label - branch to label when the byte field
   is zero, otherwise decrement it and fall through with A holding the
   post-decrement value. tstw [pointer + Type.field] / tstw WORD - Z from
   low|high of a two-unit field or declared word location; N is meaningless.
   Fixed overlays are deliberately excluded from both. */
static int la_parse_observation_operation(LaContext *ctx,
                                          const char *start, const char *end,
                                          la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *bracket;
    const char *close;
    const char *base_start;
    const char *base_end;
    const char *root_start;
    const char *path_start;
    const char *label_start;
    la_u16 pointer_location;
    la_u16 root_length;
    la_u16 field_index;
    la_u16 field_offset;
    la_u16 field_size;
    la_u16 procedure;
    la_u16 required_size;
    int is_decz;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) >= 5 && memcmp(cursor, "decz ", 5) == 0) {
        is_decz = 1;
        cursor += 4;
    } else if ((la_u16)(end - cursor) >= 5 &&
               memcmp(cursor, "tstw ", 5) == 0) {
        is_decz = 0;
        cursor += 4;
    } else {
        return 0;
    }
    if (!ctx->target->pointer_byte_rmw_operations) {
        la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                (la_u16)(end - start),
                la_slice(start, (la_u16)(end - start)),
                la_slice("typed observation operation", 27), 0, 0);
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    bracket = la_trim_left(cursor, end);
    if (!is_decz && (bracket >= end || *bracket != '[')) {
        /* tstw WORD: a declared two-unit physical word location. */
        const char *word_start;
        const char *word_end;
        la_u16 word_location;
        la_u16 word_size;
        word_start = bracket;
        word_end = word_start;
        while (word_end < end && la_is_ident(*word_end)) ++word_end;
        la_extend_qualified_base(ctx, word_start, &word_end, end, procedure);
        if (word_end == word_start ||
            la_trim_left(word_end, end) != end) {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("tstw WORD", 9), la_slice("", 0), 0, 0);
            return -1;
        }
        word_location = la_find_location_text_at(
            ctx, word_start, (la_u16)(word_end - word_start), procedure);
        if (word_location == LA_INVALID_HANDLE ||
            ctx->locations[word_location].is_pointer ||
            !la_scalar_size(ctx, ctx->locations[word_location].type_name,
                            &word_size) ||
            word_size != 2) {
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                    (la_u16)(word_end - word_start),
                    la_slice(word_start, (la_u16)(word_end - word_start)),
                    la_slice("physical two-unit word", 22), 0, 0);
            return -1;
        }
        if (!la_count_operation(ctx, line)) return -1;
        la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                      (la_u16)(end - start));
        event->operation = LA_TARGET_OP_TSTW_LOCATION;
        event->base =
            la_name_slice(ctx, ctx->locations[word_location].physical);
        event->owner = la_name_slice(ctx, ctx->locations[word_location].name);
        event->scratch = la_slice("a", 1);
        event->clobbers = la_slice("a,flags", 7);
        event->access_width = 2;
        event->volatility = LA_ACCESS_NONVOLATILE;
        return 1;
    }
    if (bracket >= end || *bracket != '[') {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("[pointer + Type.field]", 22),
                la_slice("", 0), 0, 0);
        return -1;
    }
    close = bracket + 1;
    while (close < end && *close != ']') ++close;
    if (close == end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("]", 1), la_slice("", 0), 0, 0);
        return -1;
    }
    base_start = la_trim_left(bracket + 1, close);
    base_end = base_start;
    while (base_end < close && la_is_ident(*base_end)) ++base_end;
    la_extend_qualified_base(ctx, base_start, &base_end, close, procedure);
    cursor = la_trim_left(base_end, close);
    if (base_end == base_start || cursor >= close ||
        (*cursor != '.' && *cursor != '+')) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("[pointer.field]", 15),
                la_slice("", 0), 0, 0);
        return -1;
    }
    pointer_location = la_find_location_text_at(
        ctx, base_start, (la_u16)(base_end - base_start), procedure);
    if (pointer_location == LA_INVALID_HANDLE ||
        !ctx->locations[pointer_location].is_pointer) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                (la_u16)(base_end - base_start),
                la_slice(base_start, (la_u16)(base_end - base_start)),
                la_slice("typed pointer", 13), 0, 0);
        return -1;
    }
    {
        int tail;
        tail = la_resolve_field_tail(
            ctx, start, cursor, close, line,
            la_name_slice(ctx, ctx->locations[pointer_location].type_name),
            &root_start, &root_length, &path_start);
        if (tail == 0) return 0;
        if (tail < 0) return -1;
    }
    cursor = la_trim_left(close + 1, end);
    label_start = 0;
    if (is_decz) {
        if (cursor >= end || *cursor++ != ',') {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("decz [pointer + Type.field], label", 34),
                    la_slice("", 0), 0, 0);
            return -1;
        }
        cursor = la_trim_left(cursor, end);
        label_start = cursor;
        while (cursor < end &&
               (la_is_ident(*cursor) || *cursor == '.')) ++cursor;
        if (cursor == label_start || la_trim_left(cursor, end) != end) {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("branch label", 12), la_slice("", 0), 0, 0);
            return -1;
        }
    } else if (cursor != end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1,
                (la_u16)(end - cursor),
                la_slice("end of word test", 16),
                la_slice(cursor, (la_u16)(end - cursor)), 0, 0);
        return -1;
    }
    if (la_resolve_path(ctx, root_start, root_length, path_start,
                        (la_u16)(close - path_start), line,
                        &field_index, &field_offset) != LA_OK) return -1;
    field_size = ctx->fields[field_index].count == 1 ?
        ctx->fields[field_index].size :
        (la_u16)(ctx->fields[field_index].size /
                 ctx->fields[field_index].count);
    required_size = is_decz ? 1 : 2;
    if (ctx->fields[field_index].count != 1 ||
        field_size != required_size) {
        LaSlice width_name;
        if (is_decz) {
            width_name = la_slice("byte", 4);
        } else {
            width_name = la_slice("two-unit word", 13);
        }
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                (la_u16)(close - path_start),
                la_name_slice(ctx, ctx->fields[field_index].name),
                width_name, field_size, required_size);
        return -1;
    }
    if ((la_u32)field_offset + (required_size - 1) >
        ctx->target->max_displacement) {
        la_fail(ctx, LA_ERR_DISPLACEMENT, line, 1,
                (la_u16)(close - path_start),
                la_slice(path_start, (la_u16)(close - path_start)),
                la_slice("", 0),
                (la_i32)((la_u32)field_offset + (required_size - 1)),
                ctx->target->max_displacement);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->operation = is_decz ? LA_TARGET_OP_DECZ8_PTR_DISP :
                                 LA_TARGET_OP_TSTW_PTR_DISP;
    event->owner = la_slice(root_start, root_length);
    event->path = la_slice(path_start, (la_u16)(close - path_start));
    event->base =
        la_name_slice(ctx, ctx->locations[pointer_location].physical);
    if (is_decz) {
        event->aux = la_slice(label_start,
                              (la_u16)(cursor - label_start));
        event->scratch = la_slice("a", 1);
        event->clobbers = la_slice("a,flags", 7);
    } else {
        /* The pointer word test reads the high unit through (base),y. */
        event->scratch = la_slice("a,y", 3);
        event->clobbers = la_slice("a,y,flags", 9);
    }
    event->value = field_offset;
    event->access_width = (la_u16)required_size;
    event->volatility = LA_ACCESS_NONVOLATILE;
    return 1;
}

/* movw WORD, #expr16 / movw WORD, WORD - immediate or location-to-location
   word transfer through A. Destination and source must be declared two-unit
   physical word locations. Clobbers A and flags. */
static int la_parse_word_move(LaContext *ctx,
                              const char *start, const char *end,
                              la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *dest_start;
    const char *dest_end;
    const char *source_start;
    const char *source_end;
    la_u16 dest_location;
    la_u16 source_location;
    la_u16 word_size;
    la_u16 procedure;
    la_i32 immediate;
    int is_immediate;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) < 5 || memcmp(cursor, "movw ", 5) != 0) {
        return 0;
    }
    cursor = la_trim_left(cursor + 4, end);
    procedure = la_procedure_at_line(ctx, line);
    dest_start = cursor;
    dest_end = dest_start;
    while (dest_end < end && la_is_ident(*dest_end)) ++dest_end;
    la_extend_qualified_base(ctx, dest_start, &dest_end, end, procedure);
    cursor = la_trim_left(dest_end, end);
    if (dest_end == dest_start || cursor >= end || *cursor++ != ',') {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("movw WORD, #expr16 or WORD", 26),
                la_slice("", 0), 0, 0);
        return -1;
    }
    dest_location = la_find_location_text_at(
        ctx, dest_start, (la_u16)(dest_end - dest_start), procedure);
    if (dest_location == LA_INVALID_HANDLE ||
        ctx->locations[dest_location].is_pointer ||
        !la_scalar_size(ctx, ctx->locations[dest_location].type_name,
                        &word_size) ||
        word_size != 2) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                (la_u16)(dest_end - dest_start),
                la_slice(dest_start, (la_u16)(dest_end - dest_start)),
                la_slice("physical two-unit word", 22), 0, 0);
        return -1;
    }
    cursor = la_trim_left(cursor, end);
    is_immediate = 0;
    immediate = 0;
    source_location = LA_INVALID_HANDLE;
    if (cursor < end && *cursor == '#') {
        ++cursor;
        if (la_eval_expression(ctx, cursor, end, line,
                               &immediate) != LA_OK) return -1;
        if (ctx->expression_family == LA_EXPR_BITWISE) {
            immediate = (la_i32)((la_u32)immediate & 0xffff);
        }
        if (immediate < -32768 || immediate > 65535) {
            la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                    (la_u16)(end - cursor),
                    la_slice(cursor, (la_u16)(end - cursor)),
                    la_slice("16-bit immediate", 16), immediate, 65535);
            return -1;
        }
        is_immediate = 1;
    } else {
        source_start = cursor;
        source_end = source_start;
        while (source_end < end && la_is_ident(*source_end)) ++source_end;
        la_extend_qualified_base(ctx, source_start, &source_end, end,
                                 procedure);
        if (source_end == source_start ||
            la_trim_left(source_end, end) != end) {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("movw WORD, #expr16 or WORD", 26),
                    la_slice("", 0), 0, 0);
            return -1;
        }
        source_location = la_find_location_text_at(
            ctx, source_start, (la_u16)(source_end - source_start),
            procedure);
        if (source_location == LA_INVALID_HANDLE ||
            ctx->locations[source_location].is_pointer ||
            !la_scalar_size(ctx,
                            ctx->locations[source_location].type_name,
                            &word_size) ||
            word_size != 2) {
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                    (la_u16)(source_end - source_start),
                    la_slice(source_start,
                             (la_u16)(source_end - source_start)),
                    la_slice("physical two-unit word", 22), 0, 0);
            return -1;
        }
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->operation = is_immediate ? LA_TARGET_OP_MOVW_IMM :
                                      LA_TARGET_OP_MOVW_LOCATION;
    event->base = la_name_slice(ctx, ctx->locations[dest_location].physical);
    event->owner = la_name_slice(ctx, ctx->locations[dest_location].name);
    if (is_immediate) {
        event->signed_value = immediate;
    } else {
        event->aux =
            la_name_slice(ctx, ctx->locations[source_location].physical);
    }
    event->scratch = la_slice("a", 1);
    event->clobbers = la_slice("a,flags", 7);
    event->access_width = 2;
    event->byte_order = ctx->target->byte_order;
    event->volatility = LA_ACCESS_NONVOLATILE;
    return 1;
}

static int la_has_explicit_typed_operand(const char *start, const char *end)
{
    const char *open;
    const char *plus;
    const char *close;
    open = start;
    while (open < end && *open != '[') ++open;
    if (open == end) return 0;
    close = open + 1;
    while (close < end && *close != ']') ++close;
    if (close == end) return 0;
    plus = open + 1;
    while (plus < close && *plus != '+') ++plus;
    return plus < close;
}

static int la_count_operation(LaContext *ctx, la_u16 line)
{
    if (ctx->operation_count >= ctx->limits->max_operations) {
        la_fail(ctx, LA_ERR_OPERATION_CAPACITY, line, 1, 1,
                la_slice("target operations", 17), la_slice("", 0),
                ctx->operation_count + 1, ctx->limits->max_operations);
        return 0;
    }
    ++ctx->operation_count;
    ctx->stats->operations = ctx->operation_count;
    return 1;
}

/* Compare/test-and-branch pseudo-ops against a fixed overlay field:
   `MNEM [overlay + Type.field], REST` or `MNEM [overlay.field], REST`. The tail
   (immediate and target label) is passed through verbatim; the pseudo-op still
   expands to the same bytes as the legacy raw zero-page form. */
static int la_parse_overlay_branch(LaContext *ctx,
                                   const char *start, const char *end,
                                   la_u16 line, LaEvent *event)
{
    static const char *const mnemonics[] = {
        "cbeq", "cbne", "cblt", "cble", "cbgt", "cbge", "tbz", "tbnz"
    };
    const char *cursor;
    const char *mnem_start;
    const char *mnem_end;
    const char *bracket;
    const char *close;
    const char *base_start;
    const char *base_end;
    const char *root_start;
    const char *path_start;
    const char *rest_start;
    la_u16 mnem_length;
    la_u16 overlay_index;
    la_u16 root_length;
    la_u16 field_index;
    la_u16 field_offset;
    la_u16 field_size;
    int matched;
    unsigned i;
    cursor = la_trim_left(start, end);
    mnem_start = cursor;
    while (cursor < end && la_is_ident(*cursor)) ++cursor;
    mnem_end = cursor;
    mnem_length = (la_u16)(mnem_end - mnem_start);
    matched = 0;
    for (i = 0; i < sizeof(mnemonics) / sizeof(mnemonics[0]); ++i) {
        if (la_equal_text(mnem_start, mnem_length, mnemonics[i])) {
            matched = 1;
            break;
        }
    }
    if (!matched) return 0;
    bracket = la_trim_left(mnem_end, end);
    if (bracket >= end || *bracket != '[') return 0;
    close = bracket + 1;
    while (close < end && *close != ']') ++close;
    if (close == end) return 0;
    base_start = la_trim_left(bracket + 1, close);
    base_end = base_start;
    while (base_end < close && la_is_ident(*base_end)) ++base_end;
    la_extend_qualified_base(ctx, base_start, &base_end, close,
                             la_procedure_at_line(ctx, line));
    cursor = la_trim_left(base_end, close);
    if (base_end == base_start || cursor >= close ||
        (*cursor != '.' && *cursor != '+')) return 0;
    rest_start = la_trim_left(close + 1, end);
    if (rest_start >= end || *rest_start != ',') return 0;
    rest_start = la_trim_left(rest_start + 1, end);
    if (rest_start == end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("MNEM [overlay.field], #VALUE, TARGET", 36),
                la_slice("", 0), 0, 0);
        return -1;
    }
    overlay_index = la_find_overlay_text(
        ctx, base_start, (la_u16)(base_end - base_start));
    if (overlay_index == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                (la_u16)(base_end - base_start),
                la_slice(base_start, (la_u16)(base_end - base_start)),
                la_slice("overlay", 7), 0, 0);
        return -1;
    }
    {
        int tail;
        tail = la_resolve_field_tail(
            ctx, start, cursor, close, line,
            la_name_slice(ctx, ctx->overlays[overlay_index].type_name),
            &root_start, &root_length, &path_start);
        if (tail == 0) return 0;
        if (tail < 0) return -1;
    }
    if (la_resolve_path(ctx, root_start, root_length, path_start,
                        (la_u16)(close - path_start), line,
                        &field_index, &field_offset) != LA_OK) return -1;
    field_size = ctx->fields[field_index].count == 1 ?
        ctx->fields[field_index].size :
        (la_u16)(ctx->fields[field_index].size /
                 ctx->fields[field_index].count);
    if (ctx->fields[field_index].count != 1 || field_size != 1) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                (la_u16)(close - path_start),
                la_name_slice(ctx, ctx->fields[field_index].name),
                la_slice("byte", 4), field_size, 1);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->operation = LA_TARGET_OP_BRANCH_OVERLAY_DISP;
    event->owner = la_slice(root_start, root_length);
    event->path = la_slice(path_start, (la_u16)(close - path_start));
    event->base = la_name_slice(ctx, ctx->overlays[overlay_index].base);
    event->scratch = la_slice(mnem_start, mnem_length);
    event->text = la_slice(rest_start, (la_u16)(end - rest_start));
    event->value = field_offset;
    event->access_width = 1;
    event->volatility = ctx->overlays[overlay_index].volatile_access ?
        LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    return 1;
}

/* mov [overlay + Type.field], #EXPR — store an immediate into a fixed overlay
   field. The immediate is passed through verbatim so target-side constants stay
   resolvable and the emitted bytes match the legacy raw form exactly. */
static int la_parse_overlay_store_immediate(LaContext *ctx,
                                            const char *start, const char *end,
                                            la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *bracket;
    const char *close;
    const char *base_start;
    const char *base_end;
    const char *root_start;
    const char *path_start;
    const char *imm_start;
    la_u16 overlay_index;
    la_u16 root_length;
    la_u16 field_index;
    la_u16 field_offset;
    la_u16 field_size;
    int tail;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) < 4 || memcmp(cursor, "mov ", 4) != 0) return 0;
    bracket = la_trim_left(cursor + 3, end);
    if (bracket >= end || *bracket != '[') return 0;
    close = bracket + 1;
    while (close < end && *close != ']') ++close;
    if (close == end) return 0;
    base_start = la_trim_left(bracket + 1, close);
    base_end = base_start;
    while (base_end < close && la_is_ident(*base_end)) ++base_end;
    la_extend_qualified_base(ctx, base_start, &base_end, close,
                             la_procedure_at_line(ctx, line));
    cursor = la_trim_left(base_end, close);
    if (base_end == base_start) return 0;
    /* Only a field operand [base.field] / [base + Type.field] is a store to a
       fixed overlay; a bare [base] is a frame-pointer move handled elsewhere. */
    if (cursor >= close || (*cursor != '.' && *cursor != '+')) return 0;
    imm_start = la_trim_left(close + 1, end);
    if (imm_start >= end || *imm_start != ',') return 0;
    imm_start = la_trim_left(imm_start + 1, end);
    if (imm_start < end && *imm_start == '[') {
        /* A second typed memory operand would be a memory-to-memory move the
           target does not define; keep it explicit and rejected. */
        la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                (la_u16)(end - start),
                la_slice(start, (la_u16)(end - start)),
                la_slice("fixed-overlay memory-to-memory mov", 34), 0, 0);
        return -1;
    }
    if (imm_start == end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("mov [overlay.field], SOURCE", 27),
                la_slice("", 0), 0, 0);
        return -1;
    }
    overlay_index = la_find_overlay_text(
        ctx, base_start, (la_u16)(base_end - base_start));
    if (overlay_index == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                (la_u16)(base_end - base_start),
                la_slice(base_start, (la_u16)(base_end - base_start)),
                la_slice("overlay", 7), 0, 0);
        return -1;
    }
    tail = la_resolve_field_tail(
        ctx, start, cursor, close, line,
        la_name_slice(ctx, ctx->overlays[overlay_index].type_name),
        &root_start, &root_length, &path_start);
    if (tail == 0) return 0;
    if (tail < 0) return -1;
    if (la_resolve_path(ctx, root_start, root_length, path_start,
                        (la_u16)(close - path_start), line,
                        &field_index, &field_offset) != LA_OK) return -1;
    field_size = ctx->fields[field_index].count == 1 ?
        ctx->fields[field_index].size :
        (la_u16)(ctx->fields[field_index].size /
                 ctx->fields[field_index].count);
    if (ctx->fields[field_index].count != 1 || field_size != 1) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                (la_u16)(close - path_start),
                la_name_slice(ctx, ctx->fields[field_index].name),
                la_slice("byte", 4), field_size, 1);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->operation = LA_TARGET_OP_STORE_IMM_OVERLAY_ABS;
    event->owner = la_slice(root_start, root_length);
    event->path = la_slice(path_start, (la_u16)(close - path_start));
    event->base = la_name_slice(ctx, ctx->overlays[overlay_index].base);
    event->text = la_slice(imm_start, (la_u16)(end - imm_start));
    event->value = field_offset;
    event->access_width = 1;
    event->volatility = ctx->overlays[overlay_index].volatile_access ?
        LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    return 1;
}

static int la_parse_overlay_address(LaContext *ctx,
                                    const char *start, const char *end,
                                    la_u16 line, LaEvent *event,
                                    const char *dest_start, la_u16 dest_length,
                                    const char *name_start, la_u16 name_length,
                                    const char *dot)
{
    const char *path_start;
    const char *path_end;
    la_u16 procedure;
    la_u16 location;
    la_u16 overlay_index;
    la_u16 field_index;
    la_u16 offset;
    LaSlice type_text;
    path_start = dot + 1;
    path_end = path_start;
    while (path_end < end &&
           (la_is_ident(*path_end) || *path_end == '.')) ++path_end;
    if (path_end == path_start || la_trim_left(path_end, end) != end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("address DEST, OVERLAY.field", 27),
                la_slice("", 0), 0, 0);
        return -1;
    }
    /* The destination must be a pointer-width, non-code location: a whole
       address is materialized, never a byte or a callable code pointer. */
    procedure = la_procedure_at_line(ctx, line);
    location = la_find_location_text_at(ctx, dest_start, dest_length,
                                        procedure);
    if (location == LA_INVALID_HANDLE ||
        ctx->locations[location].storage_width != 2 ||
        la_is_code_pointer_type(ctx, ctx->locations[location].type_name)) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1, dest_length,
                la_slice(dest_start, dest_length),
                la_slice("address pointer destination", 27), 0, 0);
        return -1;
    }
    overlay_index = la_find_overlay_text(ctx, name_start, name_length);
    if (overlay_index == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1, name_length,
                la_slice(name_start, name_length),
                la_slice("overlay", 7), 0, 0);
        return -1;
    }
    type_text = la_name_slice(ctx, ctx->overlays[overlay_index].type_name);
    if (la_resolve_path(ctx, type_text.data, type_text.length,
                        path_start, (la_u16)(path_end - path_start),
                        line, &field_index, &offset) != LA_OK) {
        return -1;
    }
    (void)field_index;
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->operation = LA_TARGET_OP_ADDRESS_OVERLAY_FIELD;
    event->base = la_name_slice(ctx, ctx->locations[location].physical);
    event->aux = la_name_slice(ctx, ctx->overlays[overlay_index].base);
    event->owner = la_slice(name_start, name_length);
    event->path = la_slice(path_start, (la_u16)(path_end - path_start));
    event->value = offset;
    event->access_width = 2;
    event->byte_order = ctx->target->byte_order;
    return 1;
}

static int la_parse_pool_address(LaContext *ctx,
                                 const char *start, const char *end,
                                 la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *destination_start;
    const char *pool_start;
    const char *index_start;
    la_u16 destination_length;
    la_u16 pool_length;
    la_u16 index_length;
    la_u16 procedure;
    la_u16 location;
    la_u16 pool_index;
    LaPoolRec *pool;
    cursor = la_trim_left(start, end);
    if (!la_line_keyword(cursor, end, "address")) return 0;
    cursor += 7;
    if (!la_read_qualified_identifier(&cursor, end, &destination_start,
                                      &destination_length)) return -1;
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ',' ||
        !la_read_identifier(&cursor, end, &pool_start, &pool_length)) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("address DEST, POOL[INDEX]", 25),
                la_slice("", 0), 0, 0);
        return -1;
    }
    cursor = la_trim_left(cursor, end);
    /* A dotted second operand is a fixed-overlay field address, not a pool. */
    if (cursor < end && *cursor == '.') {
        return la_parse_overlay_address(
            ctx, start, end, line, event,
            destination_start, destination_length,
            pool_start, pool_length, cursor);
    }
    if (cursor >= end || *cursor++ != '[' ||
        !la_read_identifier(&cursor, end, &index_start, &index_length) ||
        cursor >= end || *cursor++ != ']' ||
        la_trim_left(cursor, end) != end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("address DEST, POOL[INDEX]", 25),
                la_slice("", 0), 0, 0);
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    location = la_find_location_text_at(
        ctx, destination_start, destination_length, procedure);
    if (location == LA_INVALID_HANDLE ||
        !ctx->locations[location].is_pointer) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1, destination_length,
                la_slice(destination_start, destination_length),
                la_slice("pointer destination", 19), 0, 0);
        return -1;
    }
    pool_index = la_find_pool_text(ctx, pool_start, pool_length);
    if (pool_index == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_UNKNOWN_POOL, line, 1, pool_length,
                la_slice(pool_start, pool_length), la_slice("", 0), 0, 0);
        return -1;
    }
    pool = &ctx->pools[pool_index];
    if (ctx->locations[location].type_name != pool->type_name) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1, destination_length,
                la_name_slice(ctx, ctx->locations[location].type_name),
                la_name_slice(ctx, pool->type_name), 0, 0);
        return -1;
    }
    if (!la_equal_text(index_start, index_length, "a")) {
        la_fail(ctx, LA_ERR_INDEX_LOCATION, line, 1, index_length,
                la_slice(index_start, index_length), la_slice("a", 1), 0, 0);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->owner = la_name_slice(ctx, pool->name);
    event->path = la_name_slice(ctx, pool->base);
    event->base = la_name_slice(ctx, ctx->locations[location].physical);
    event->index = la_slice(index_start, index_length);
    event->aux = la_name_slice(ctx, pool->table_low);
    event->aux2 = la_name_slice(ctx, pool->table_high);
    event->operation = LA_TARGET_OP_ADDRESS_POOL_TABLE;
    event->stride = pool->stride;
    event->count = pool->count;
    return 1;
}

static int la_parse_local_operation(LaContext *ctx,
                                    const char *start, const char *end,
                                    la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *name_start;
    la_u16 name_length;
    la_u16 procedure;
    la_u16 local_index;
    la_u16 field_offset;
    LaProcedureRec *record;
    LaLocalRec *local;
    LaTargetOperationKind operation;
    int qualified;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) >= 4 && memcmp(cursor, "lda ", 4) == 0) {
        operation = LA_TARGET_OP_LOAD8_FRAME_LOCAL;
    } else if ((la_u16)(end - cursor) >= 4 &&
               memcmp(cursor, "sta ", 4) == 0) {
        operation = LA_TARGET_OP_STORE8_FRAME_LOCAL;
    } else {
        return 0;
    }
    cursor = la_trim_left(cursor + 3, end);
    if (cursor >= end || *cursor++ != '[') return 0;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        la_fail(ctx, LA_ERR_FRAME_LOCAL, line, 1, 1,
                la_slice("local name", 10), la_slice("", 0), 0, 0);
        return -1;
    }
    field_offset = 0;
    qualified = 0;
    cursor = la_trim_left(cursor, end);
    if (cursor < end && *cursor == '+') {
        const char *root_start;
        const char *path_start;
        const char *close;
        la_u16 root_length;
        la_u16 field_index;
        ++cursor;
        qualified = 1;
        if (!la_read_identifier(&cursor, end, &root_start, &root_length)) {
            la_fail(ctx, LA_ERR_FRAME_LOCAL, line, 1, 1,
                    la_slice("TYPE.field", 10), la_slice("", 0), 0, 0);
            return -1;
        }
        if (cursor >= end || *cursor++ != '.') {
            la_fail(ctx, LA_ERR_FRAME_LOCAL, line, 1, 1,
                    la_slice("TYPE.field", 10), la_slice("", 0), 0, 0);
            return -1;
        }
        path_start = cursor;
        close = cursor;
        while (close < end && *close != ']') ++close;
        procedure = la_procedure_at_line(ctx, line);
        local_index = la_find_local_text(ctx, procedure,
                                         name_start, name_length);
        if (local_index == LA_INVALID_HANDLE) {
            return 0;
        }
        local = &ctx->locals[local_index];
        if (local->is_pointer ||
            !la_equal_text(root_start, root_length,
                           la_name_slice(ctx, local->type_name).data)) {
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1, root_length,
                    la_slice(root_start, root_length),
                    la_name_slice(ctx, local->type_name), 0, 0);
            return -1;
        }
        if (la_resolve_path(ctx, root_start, root_length, path_start,
                            (la_u16)(close - path_start), line,
                            &field_index, &field_offset) != LA_OK) return -1;
        if (ctx->fields[field_index].size != 1 ||
            ctx->fields[field_index].count != 1) {
            la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                    (la_u16)(close - path_start),
                    la_slice(path_start, (la_u16)(close - path_start)),
                    la_slice("byte", 4), ctx->fields[field_index].size, 1);
            return -1;
        }
        cursor = close;
    }
    cursor = la_trim_left(cursor, end);
    /* A dotted field path is the typed-operand shorthand [base.field], handled
       by la_parse_typed_operation, not a frame-local form. */
    if (cursor < end && *cursor == '.') return 0;
    if (cursor >= end || *cursor++ != ']' ||
        la_trim_left(cursor, end) != end) {
        la_fail(ctx, LA_ERR_FRAME_LOCAL, line, 1, 1,
                la_slice("[NAME] or [NAME + TYPE.field]", 29),
                la_slice("", 0), 0, 0);
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    if (procedure == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_PROCEDURE_SCOPE, line, 1, name_length,
                la_slice(name_start, name_length),
                la_slice("procedure", 9), 0, 0);
        return -1;
    }
    local_index = la_find_local_text(ctx, procedure, name_start, name_length);
    if (local_index == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_FRAME_LOCAL, line, 1, name_length,
                la_slice(name_start, name_length),
                la_slice("declared local", 14), 0, 0);
        return -1;
    }
    local = &ctx->locals[local_index];
    record = &ctx->procedures[procedure];
    if (!qualified && local->size != 1) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1, name_length,
                la_slice(name_start, name_length), la_slice("byte", 4),
                local->size, 1);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->owner = la_name_slice(ctx, record->name);
    event->path = la_name_slice(ctx, local->name);
    event->operation = operation;
    event->value =
        (la_u16)(record->frame_size - (local->offset + field_offset));
    event->count = record->frame_size;
    return 1;
}

static int la_parse_frame_pointer_move(LaContext *ctx,
                                       const char *start, const char *end,
                                       la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *left_start;
    const char *right_start;
    la_u16 left_length;
    la_u16 right_length;
    la_u16 procedure;
    la_u16 local_index;
    la_u16 location_index;
    int store;
    cursor = la_trim_left(start, end);
    if ((la_u16)(end - cursor) < 4 || memcmp(cursor, "mov ", 4) != 0) {
        return 0;
    }
    cursor += 4;
    cursor = la_trim_left(cursor, end);
    store = cursor < end && *cursor == '[';
    if (store) {
        ++cursor;
        if (!la_read_identifier(&cursor, end, &left_start, &left_length) ||
            cursor >= end || *cursor++ != ']') return 0;
    } else if (!la_read_identifier(&cursor, end, &left_start, &left_length)) {
        return 0;
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ',') return 0;
    cursor = la_trim_left(cursor, end);
    if (store) {
        if (!la_read_identifier(&cursor, end, &right_start, &right_length) ||
            la_trim_left(cursor, end) != end) return 0;
    } else {
        if (cursor >= end || *cursor++ != '[' ||
            !la_read_identifier(&cursor, end, &right_start, &right_length) ||
            cursor >= end || *cursor++ != ']' ||
            la_trim_left(cursor, end) != end) return 0;
    }
    procedure = la_procedure_at_line(ctx, line);
    if (procedure == LA_INVALID_HANDLE) return 0;
    local_index = la_find_local_text(
        ctx, procedure, store ? left_start : right_start,
        store ? left_length : right_length);
    location_index = la_find_location_text_at(
        ctx, store ? right_start : left_start,
        store ? right_length : left_length, procedure);
    if (local_index == LA_INVALID_HANDLE ||
        location_index == LA_INVALID_HANDLE) return 0;
    if (!ctx->locals[local_index].is_pointer ||
        !ctx->locations[location_index].is_pointer ||
        ctx->locals[local_index].type_name !=
            ctx->locations[location_index].type_name) {
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1, 1,
                la_slice(store ? left_start : right_start,
                         store ? left_length : right_length),
                la_slice("matching pointer locations", 26), 0, 0);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->owner =
        la_name_slice(ctx, ctx->procedures[procedure].name);
    event->path = la_name_slice(ctx, ctx->locals[local_index].name);
    event->base =
        la_name_slice(ctx, ctx->locations[location_index].physical);
    event->aux2 = la_slice("a", 1);
    event->operation = store ? LA_TARGET_OP_STORE_PTR_FRAME :
                               LA_TARGET_OP_LOAD_PTR_FRAME;
    event->value = (la_u16)(
        ctx->procedures[procedure].frame_size -
        ctx->locals[local_index].offset);
    event->stride = ctx->target->pointer_units;
    event->count = ctx->procedures[procedure].frame_size;
    return 1;
}

static int la_emit_invoke_operation(LaContext *ctx, la_u16 line,
                                    LaTargetOperationKind operation,
                                    LaSlice owner, LaSlice path,
                                    LaSlice base, LaSlice aux, LaSlice aux2,
                                    la_u16 value, la_u16 stride,
                                    la_u16 count)
{
    LaEvent event;
    if (!la_count_operation(ctx, line)) return 0;
    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
    event.owner = owner;
    event.path = path;
    event.base = base;
    event.aux = aux;
    event.aux2 = aux2;
    event.operation = operation;
    event.value = value;
    event.stride = stride;
    event.count = count;
    return la_write_event(ctx, &event);
}

static int la_slice_is_register(LaSlice slice)
{
    return slice.length == 1 &&
           (slice.data[0] == 'a' || slice.data[0] == 'x' ||
            slice.data[0] == 'y');
}

static la_u16 la_find_invoke_member(LaContext *ctx,
                                    const LaProcedureRec *procedure,
                                    const char *name, la_u16 length)
{
    la_u16 scan;
    for (scan = procedure->first_parameter;
         scan < procedure->first_parameter + procedure->parameter_count;
         ++scan) {
        LaSlice member_name;
        member_name = la_name_slice(ctx, ctx->locations[scan].name);
        if (ctx->locations[scan].role == LA_MEMBER_INPUT &&
            member_name.length == length &&
            memcmp(member_name.data, name, length) == 0) {
            return scan;
        }
    }
    return LA_INVALID_HANDLE;
}

static int la_invoke_has_binding(LaContext *ctx, la_u16 count,
                                 la_u16 member)
{
    la_u16 scan;
    for (scan = 0; scan < count; ++scan) {
        if (ctx->bindings[scan].name == member) return 1;
    }
    return 0;
}

static int la_parse_invoke_source(LaContext *ctx, const char **cursor,
                                  const char *end, la_u16 line,
                                  la_u16 caller, la_u16 member_index,
                                  LaInvokeBindingRec *binding)
{
    const char *source_start;
    la_u16 source_length;
    la_u16 source_location;
    la_u16 member_width;
    member_width = la_location_storage_units(ctx, member_index);
    if (*cursor < end && (**cursor == '#' ||
                          (**cursor >= '0' && **cursor <= '9'))) {
        /* Immediate: a compile-time expression running to the next
           top-level comma. Byte members keep the byte range; two-unit
           scalar members accept the 16-bit range and lower through the
           word-immediate move. */
        const char *expr_start;
        const char *expr_end;
        int depth;
        la_i32 value;
        if (**cursor == '#') ++*cursor;
        expr_start = *cursor;
        expr_end = expr_start;
        depth = 0;
        while (expr_end < end) {
            if (*expr_end == '(') ++depth;
            else if (*expr_end == ')') --depth;
            else if (*expr_end == ',' && depth == 0) break;
            ++expr_end;
        }
        if (la_eval_expression(ctx, expr_start, expr_end, line,
                               &value) != LA_OK) return 0;
        *cursor = expr_end;
        if (ctx->locations[member_index].is_pointer ||
            la_is_code_pointer_type(
                ctx, ctx->locations[member_index].type_name)) {
            la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                    la_slice("immediate", 9),
                    la_name_slice(
                        ctx, ctx->locations[member_index].type_name),
                    value, 0);
            return 0;
        }
        if (member_width == 2) {
            if (ctx->expression_family == LA_EXPR_BITWISE) {
                value = (la_i32)((la_u32)value & 0xffff);
            }
            if (value < -32768 || value > 65535) {
                la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                        la_slice("16-bit immediate", 16),
                        la_name_slice(
                            ctx, ctx->locations[member_index].type_name),
                        value, 65535);
                return 0;
            }
            binding->source_kind = LA_SOURCE_IMMEDIATE;
            binding->is_word_immediate = 1;
            binding->immediate = value;
            return 1;
        }
        if (ctx->expression_family == LA_EXPR_BITWISE) {
            value = (la_i32)((la_u32)value & 0xff);
        }
        if (value < -128 || value > 255) {
            la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                    la_slice("byte immediate", 14),
                    la_name_slice(
                        ctx, ctx->locations[member_index].type_name),
                    value, 255);
            return 0;
        }
        binding->source_kind = LA_SOURCE_IMMEDIATE;
        binding->immediate = (la_i32)((la_u32)value & 0xff);
        return 1;
    }
    if (*cursor < end && **cursor == '[') {
        /* Typed-field source: [pointer + Type.field] with an optional
           constant value addend for byte leaves. */
        const char *bracket;
        const char *close;
        const char *base_start;
        const char *base_end;
        const char *root_start;
        const char *path_start;
        const char *field_cursor;
        la_u16 pointer_location;
        la_u16 root_length;
        la_u16 field_index;
        la_u16 field_offset;
        la_u16 field_size;
        la_i32 addend;
        bracket = *cursor;
        close = bracket + 1;
        while (close < end && *close != ']') ++close;
        if (close == end) {
            la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                    la_slice("]", 1), la_slice("", 0), 0, 0);
            return 0;
        }
        base_start = la_trim_left(bracket + 1, close);
        base_end = base_start;
        while (base_end < close && la_is_ident(*base_end)) ++base_end;
        la_extend_qualified_base(ctx, base_start, &base_end, close, caller);
        field_cursor = la_trim_left(base_end, close);
        if (base_end == base_start || field_cursor >= close ||
            (*field_cursor != '.' && *field_cursor != '+')) {
            la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                    la_slice("[pointer.field]", 15), la_slice("", 0), 0, 0);
            return 0;
        }
        pointer_location = la_find_location_text_at(
            ctx, base_start, (la_u16)(base_end - base_start), caller);
        if (pointer_location == LA_INVALID_HANDLE ||
            !ctx->locations[pointer_location].is_pointer) {
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line, 1,
                    (la_u16)(base_end - base_start),
                    la_slice(base_start, (la_u16)(base_end - base_start)),
                    la_slice("typed pointer", 13), 0, 0);
            return 0;
        }
        {
            int tail;
            tail = la_resolve_field_tail(
                ctx, bracket, field_cursor, close, line,
                la_name_slice(ctx,
                              ctx->locations[pointer_location].type_name),
                &root_start, &root_length, &path_start);
            if (tail <= 0) return 0;
        }
        if (la_resolve_path(ctx, root_start, root_length, path_start,
                            (la_u16)(close - path_start), line,
                            &field_index, &field_offset) != LA_OK) return 0;
        field_size = ctx->fields[field_index].count == 1 ?
            ctx->fields[field_index].size :
            (la_u16)(ctx->fields[field_index].size /
                     ctx->fields[field_index].count);
        if (ctx->fields[field_index].count != 1 ||
            ctx->locations[member_index].is_pointer ||
            la_is_code_pointer_type(
                ctx, ctx->locations[member_index].type_name) ||
            field_size != member_width) {
            la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                    (la_u16)(close - path_start),
                    la_name_slice(ctx, ctx->fields[field_index].name),
                    la_name_slice(
                        ctx, ctx->locations[member_index].type_name),
                    field_size, member_width);
            return 0;
        }
        if ((la_u32)field_offset + (field_size - 1) >
            ctx->target->max_displacement) {
            la_fail(ctx, LA_ERR_DISPLACEMENT, line, 1,
                    (la_u16)(close - path_start),
                    la_slice(path_start, (la_u16)(close - path_start)),
                    la_slice("", 0),
                    (la_i32)((la_u32)field_offset + (field_size - 1)),
                    ctx->target->max_displacement);
            return 0;
        }
        *cursor = close + 1;
        addend = 0;
        {
            const char *after;
            after = la_trim_left(*cursor, end);
            if (after < end && *after == '+') {
                const char *addend_start;
                const char *addend_end;
                int depth;
                if (field_size != 1) {
                    la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                            la_slice("byte field addend", 17),
                            la_slice("", 0), 0, 0);
                    return 0;
                }
                addend_start = after + 1;
                addend_end = addend_start;
                depth = 0;
                while (addend_end < end) {
                    if (*addend_end == '(') ++depth;
                    else if (*addend_end == ')') --depth;
                    else if (*addend_end == ',' && depth == 0) break;
                    ++addend_end;
                }
                if (la_eval_expression(ctx, addend_start, addend_end, line,
                                       &addend) != LA_OK) return 0;
                if (addend < -128 || addend > 255) {
                    la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                            la_slice("byte field addend", 17),
                            la_slice("", 0), addend, 255);
                    return 0;
                }
                *cursor = addend_end;
            }
        }
        binding->source_kind = LA_SOURCE_PHYSICAL;
        binding->is_field = 1;
        binding->field_width = (la_u8)field_size;
        binding->field_base = pointer_location;
        binding->field_disp = field_offset;
        binding->field_add = addend;
        return 1;
    }
    if (!la_read_qualified_identifier(cursor, end, &source_start,
                                      &source_length)) {
        la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                la_slice("value", 5), la_slice("", 0), 0, 0);
        return 0;
    }
    source_location = la_find_location_text_at(
        ctx, source_start, source_length, caller);
    if (source_location != LA_INVALID_HANDLE) {
        if (ctx->locations[source_location].is_pointer !=
                ctx->locations[member_index].is_pointer ||
            (ctx->locations[source_location].is_pointer &&
             ctx->locations[source_location].type_name !=
                ctx->locations[member_index].type_name) ||
            (la_is_code_pointer_type(
                 ctx, ctx->locations[source_location].type_name) !=
             la_is_code_pointer_type(
                 ctx, ctx->locations[member_index].type_name))) {
            la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, source_length,
                    la_slice(source_start, source_length),
                    la_name_slice(
                        ctx, ctx->locations[member_index].type_name),
                    0, 0);
            return 0;
        }
        binding->source = ctx->locations[source_location].physical;
    } else {
        LaSlice source;
        source = la_slice(source_start, source_length);
        if (ctx->locations[member_index].is_pointer ||
            la_is_code_pointer_type(
                ctx, ctx->locations[member_index].type_name) ||
            !la_slice_is_register(source)) {
            la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, source_length,
                    source, la_slice("typed source or a/x/y", 21), 0, 0);
            return 0;
        }
        binding->source =
            la_intern(ctx, source_start, source_length, line, 1);
        if (binding->source == LA_INVALID_HANDLE) return 0;
    }
    binding->source_kind = LA_SOURCE_PHYSICAL;
    return 1;
}

static int la_parse_invoke_binding(LaContext *ctx, const char **cursor,
                                   const char *end, la_u16 line,
                                   la_u16 caller,
                                   const LaProcedureRec *procedure,
                                   la_u16 *binding_count)
{
    const char *name_start;
    la_u16 name_length;
    la_u16 member_index;
    LaInvokeBindingRec *binding;
    if (*(*cursor)++ != ',') {
        la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                la_slice(",", 1), la_slice("", 0), 0, 0);
        return 0;
    }
    if (!la_read_identifier(cursor, end, &name_start, &name_length)) {
        la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                la_slice("binding name", 12), la_slice("", 0), 0, 0);
        return 0;
    }
    *cursor = la_trim_left(*cursor, end);
    if (*cursor >= end || *(*cursor)++ != '=') {
        la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                la_slice("=", 1), la_slice("", 0), 0, 0);
        return 0;
    }
    *cursor = la_trim_left(*cursor, end);
    if (*binding_count >= ctx->limits->max_invoke_bindings) {
        la_fail(ctx, LA_ERR_INVOKE_CAPACITY, line, 1, name_length,
                la_slice(name_start, name_length),
                la_slice("invoke bindings", 15), *binding_count + 1,
                ctx->limits->max_invoke_bindings);
        return 0;
    }
    member_index = la_find_invoke_member(
        ctx, procedure, name_start, name_length);
    if (member_index == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, name_length,
                la_slice(name_start, name_length),
                la_slice("callee input", 12), 0, 0);
        return 0;
    }
    if (la_invoke_has_binding(ctx, *binding_count, member_index)) {
        la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, name_length,
                la_slice(name_start, name_length),
                la_slice("unique binding", 14), 0, 0);
        return 0;
    }
    binding = &ctx->bindings[(*binding_count)++];
    memset(binding, 0, sizeof(*binding));
    binding->name = member_index;
    if (!la_parse_invoke_source(
            ctx, cursor, end, line, caller, member_index, binding)) {
        return 0;
    }
    *cursor = la_trim_left(*cursor, end);
    return 1;
}

static int la_validate_invoke_inputs(LaContext *ctx,
                                     const LaProcedureRec *procedure,
                                     la_u16 binding_count, la_u16 line)
{
    la_u16 scan;
    for (scan = procedure->first_parameter;
         scan < procedure->first_parameter + procedure->parameter_count;
         ++scan) {
        if (ctx->locations[scan].role != LA_MEMBER_INPUT) continue;
        if (!la_invoke_has_binding(ctx, binding_count, scan)) {
            la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                    la_name_slice(ctx, ctx->locations[scan].name),
                    la_slice("required input", 14), 0, 0);
            return 0;
        }
    }
    return 1;
}

static int la_slices_equal(LaSlice left, LaSlice right)
{
    return left.length == right.length &&
           memcmp(left.data, right.data, left.length) == 0;
}

/* Plan the marshalling order: identity bindings elide entirely; register
   sources snapshot (field reads pass through A); location sources snapshot
   only when another binding's destination overlaps them; field sources read
   directly into memory destinations unless an early write would disturb a
   later field base or an unsnapshotted location source. */
static int la_reserve_invoke_scratch(LaContext *ctx, la_u16 binding_count,
                                     la_u16 line, LaSlice scratch_name,
                                     la_u16 *scratch)
{
    la_u16 bind;
    la_u16 other;
    *scratch = 0;
    /* Identity elision. */
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        binding = &ctx->bindings[bind];
        if (binding->source_kind == LA_SOURCE_PHYSICAL &&
            !binding->is_field &&
            la_slices_equal(
                la_name_slice(ctx, binding->source),
                la_name_slice(ctx,
                              ctx->locations[binding->name].physical))) {
            binding->elided = 1;
        }
    }
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        LaSlice source;
        int conflicted;
        binding = &ctx->bindings[bind];
        binding->needs_scratch = 0;
        if (binding->elided ||
            binding->source_kind != LA_SOURCE_PHYSICAL) continue;
        if (binding->is_field) continue;
        source = la_name_slice(ctx, binding->source);
        if (la_slice_is_register(source)) {
            binding->needs_scratch = 1;
            continue;
        }
        conflicted = 0;
        for (other = 0; other < binding_count; ++other) {
            if (other == bind || ctx->bindings[other].elided) continue;
            if (la_slices_equal(
                    source,
                    la_name_slice(
                        ctx,
                        ctx->locations[ctx->bindings[other].name]
                            .physical))) {
                conflicted = 1;
                break;
            }
        }
        binding->needs_scratch = (la_u8)conflicted;
    }
    /* Field placement: direct into a memory destination only when the
       early write cannot disturb a later field base or an unsnapshotted
       location source, and the destination is not a register. */
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        LaSlice dest;
        int to_scratch;
        binding = &ctx->bindings[bind];
        if (!binding->is_field || binding->elided) continue;
        binding->field_direct_register = 0;
        dest = la_name_slice(ctx, ctx->locations[binding->name].physical);
        to_scratch = la_slice_is_register(dest);
        if (to_scratch) {
            /* Register destinations read after all assignments (Y, X,
               then A), through A - direct unless another binding assigns
               A in the assignment phase. */
            int a_assigned;
            a_assigned = 0;
            for (other = 0; other < binding_count; ++other) {
                LaInvokeBindingRec *peer;
                LaSlice peer_dest;
                peer = &ctx->bindings[other];
                if (peer->elided || peer->is_field) continue;
                peer_dest = la_name_slice(
                    ctx, ctx->locations[peer->name].physical);
                if (peer_dest.length == 1 && peer_dest.data[0] == 'a') {
                    a_assigned = 1;
                    break;
                }
            }
            if (!a_assigned) {
                binding->field_direct_register = 1;
                binding->field_to_scratch = 0;
                binding->needs_scratch = 0;
                continue;
            }
        }
        for (other = 0; other < binding_count && !to_scratch; ++other) {
            LaInvokeBindingRec *peer;
            peer = &ctx->bindings[other];
            if (peer->elided) continue;
            if (peer->is_field && other != bind &&
                la_slices_equal(
                    dest,
                    la_name_slice(
                        ctx,
                        ctx->locations[peer->field_base].physical))) {
                to_scratch = 1;
            }
            if (peer->is_field &&
                la_slices_equal(
                    dest,
                    la_name_slice(
                        ctx,
                        ctx->locations[binding->field_base].physical))) {
                /* Destination overlaps this read's own base. */
                if (other == bind) to_scratch = 1;
            }
            if (!peer->is_field && peer->source_kind == LA_SOURCE_PHYSICAL &&
                !peer->needs_scratch && other != bind &&
                la_slices_equal(dest,
                                la_name_slice(ctx, peer->source))) {
                to_scratch = 1;
            }
        }
        binding->field_to_scratch = (la_u8)to_scratch;
        binding->needs_scratch = (la_u8)to_scratch;
    }
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        la_u16 width;
        binding = &ctx->bindings[bind];
        if (!binding->needs_scratch) continue;
        width = binding->is_field ? binding->field_width :
                la_location_storage_units(ctx, binding->name);
        if (*scratch + width > ctx->target->invoke_scratch_units) {
            la_fail(ctx, LA_ERR_INVOKE_SCRATCH, line, 1, 1,
                    scratch_name, la_slice("invoke snapshot", 15),
                    *scratch + width, ctx->target->invoke_scratch_units);
            return 0;
        }
        binding->scratch = (la_u8)*scratch;
        *scratch = (la_u16)(*scratch + width);
    }
    return 1;
}

static int la_emit_invoke_saves(LaContext *ctx,
                                const LaProcedureRec *procedure,
                                la_u16 binding_count, la_u16 line,
                                LaSlice scratch_name, int registers)
{
    la_u16 bind;
    LaSlice owner;
    owner = la_name_slice(ctx, procedure->name);
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        LaSlice source;
        la_u16 width;
        binding = &ctx->bindings[bind];
        if (binding->source_kind != LA_SOURCE_PHYSICAL ||
            binding->elided || binding->is_field ||
            !binding->needs_scratch) continue;
        source = la_name_slice(ctx, binding->source);
        if (la_slice_is_register(source) != registers) continue;
        width = la_location_storage_units(ctx, binding->name);
        if (!la_emit_invoke_operation(
                ctx, line, LA_TARGET_OP_INVOKE_SAVE, owner,
                la_name_slice(ctx, ctx->locations[binding->name].name),
                la_slice("", 0), source, scratch_name,
                binding->scratch, width, LA_SOURCE_PHYSICAL)) {
            return 0;
        }
    }
    return 1;
}

/* Field reads happen after register saves and before destination writes,
   so every base pointer is still intact when it is dereferenced. */
static int la_emit_invoke_field_reads(LaContext *ctx,
                                      const LaProcedureRec *procedure,
                                      la_u16 binding_count, la_u16 line,
                                      LaSlice scratch_name)
{
    la_u16 bind;
    LaSlice owner;
    owner = la_name_slice(ctx, procedure->name);
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        LaEvent event;
        binding = &ctx->bindings[bind];
        if (!binding->is_field || binding->elided ||
            binding->field_direct_register) continue;
        if (!la_count_operation(ctx, line)) return 0;
        la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
        event.operation = LA_TARGET_OP_INVOKE_FIELD;
        event.owner = owner;
        event.path = la_name_slice(ctx, ctx->locations[binding->name].name);
        event.base = la_name_slice(
            ctx, ctx->locations[binding->field_base].physical);
        event.value = binding->field_disp;
        event.signed_value = binding->field_add;
        event.stride = binding->field_width;
        if (binding->field_to_scratch) {
            event.aux2 = scratch_name;
            event.offset = binding->scratch;
            event.count = 1;
        } else {
            event.aux = la_name_slice(
                ctx, ctx->locations[binding->name].physical);
            event.count = 0;
        }
        if (!la_write_event(ctx, &event)) return 0;
    }
    return 1;
}

/* Register-destination field reads run after every assignment: each read
   passes through A, so A-destination reads go last and nothing may write
   A afterwards. */
static int la_emit_invoke_register_fields(LaContext *ctx,
                                          const LaProcedureRec *procedure,
                                          la_u16 binding_count, la_u16 line)
{
    static const char order[3] = { 'y', 'x', 'a' };
    la_u16 pass;
    la_u16 bind;
    LaSlice owner;
    owner = la_name_slice(ctx, procedure->name);
    for (pass = 0; pass < 3; ++pass) {
        for (bind = 0; bind < binding_count; ++bind) {
            LaInvokeBindingRec *binding;
            LaSlice dest;
            LaEvent event;
            binding = &ctx->bindings[bind];
            if (!binding->is_field || binding->elided ||
                !binding->field_direct_register) continue;
            dest = la_name_slice(ctx,
                                 ctx->locations[binding->name].physical);
            if (dest.data[0] != order[pass]) continue;
            if (!la_count_operation(ctx, line)) return 0;
            la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
            event.operation = LA_TARGET_OP_INVOKE_FIELD;
            event.owner = owner;
            event.path = la_name_slice(ctx,
                                       ctx->locations[binding->name].name);
            event.base = la_name_slice(
                ctx, ctx->locations[binding->field_base].physical);
            event.value = binding->field_disp;
            event.signed_value = binding->field_add;
            event.stride = binding->field_width;
            event.aux = dest;
            event.count = 2;
            if (!la_write_event(ctx, &event)) return 0;
        }
    }
    return 1;
}

static int la_emit_invoke_assignments(LaContext *ctx,
                                      const LaProcedureRec *procedure,
                                      la_u16 binding_count, la_u16 line,
                                      LaSlice scratch_name)
{
    la_u16 bind;
    LaSlice owner;
    owner = la_name_slice(ctx, procedure->name);
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        la_u16 width;
        LaSlice source;
        binding = &ctx->bindings[bind];
        if (binding->elided) continue;
        if (binding->is_field && !binding->field_to_scratch) continue;
        width = la_location_storage_units(ctx, binding->name);
        if (binding->is_word_immediate) {
            LaEvent event;
            if (!la_count_operation(ctx, line)) return 0;
            la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
            event.operation = LA_TARGET_OP_MOVW_IMM;
            event.owner = la_name_slice(ctx,
                                        ctx->locations[binding->name].name);
            event.base = la_name_slice(
                ctx, ctx->locations[binding->name].physical);
            event.signed_value = binding->immediate;
            event.access_width = 2;
            if (!la_write_event(ctx, &event)) return 0;
            continue;
        }
        if (binding->is_field) {
            /* Copy the snapshotted field value out of scratch. */
            if (!la_emit_invoke_operation(
                    ctx, line, LA_TARGET_OP_INVOKE_ASSIGN, owner,
                    la_name_slice(ctx, ctx->locations[binding->name].name),
                    la_name_slice(ctx,
                                  ctx->locations[binding->name].physical),
                    la_slice("", 0), scratch_name,
                    binding->scratch, binding->field_width,
                    LA_SOURCE_PHYSICAL)) {
                return 0;
            }
            continue;
        }
        if (binding->source_kind == LA_SOURCE_PHYSICAL) {
            source = la_name_slice(ctx, binding->source);
        } else {
            source = la_slice("", 0);
        }
        if (binding->source_kind == LA_SOURCE_PHYSICAL &&
            !binding->needs_scratch) {
            /* Unconflicted location source: read it directly. */
            if (!la_emit_invoke_operation(
                    ctx, line, LA_TARGET_OP_INVOKE_ASSIGN, owner,
                    la_name_slice(ctx, ctx->locations[binding->name].name),
                    la_name_slice(ctx,
                                  ctx->locations[binding->name].physical),
                    source, scratch_name, 0, width, 3)) {
                return 0;
            }
            continue;
        }
        if (!la_emit_invoke_operation(
                ctx, line, LA_TARGET_OP_INVOKE_ASSIGN, owner,
                la_name_slice(ctx, ctx->locations[binding->name].name),
                la_name_slice(ctx, ctx->locations[binding->name].physical),
                source, scratch_name,
                binding->source_kind == LA_SOURCE_PHYSICAL ?
                    binding->scratch : (la_u16)binding->immediate,
                width, binding->source_kind)) {
            return 0;
        }
    }
    return 1;
}

static int la_parse_invoke(LaContext *ctx,
                           const char *start, const char *end,
                           la_u16 line, la_u16 caller)
{
    const char *cursor;
    const char *callee_start;
    la_u16 callee_length;
    la_u16 callee;
    la_u16 binding_count;
    la_u16 scratch;
    int is_private;
    int is_tail;
    LaProcedureRec *procedure;
    LaSlice owner;
    LaSlice scratch_name;
    cursor = la_trim_left(start, end);
    if (!la_line_keyword(cursor, end, "invoke")) return 0;
    cursor += 6;
    cursor = la_trim_left(cursor, end);
    is_tail = 0;
    if (la_line_keyword(cursor, end, "tail")) {
        is_tail = 1;
        cursor += 4;
        cursor = la_trim_left(cursor, end);
    }
    if (!la_read_qualified_identifier(
            &cursor, end, &callee_start, &callee_length)) {
        la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                la_slice("callee", 6), la_slice("", 0), 0, 0);
        return -1;
    }
    callee = la_find_procedure_scoped(
        ctx, callee_start, callee_length,
        ctx->procedures[caller].namespace_handle,
        ctx->procedures[caller].source_id, &is_private);
    if (callee == LA_INVALID_HANDLE) {
        la_fail(ctx, LA_ERR_UNKNOWN_PROCEDURE, line, 1, callee_length,
                la_slice(callee_start, callee_length), la_slice("", 0), 0, 0);
        return -1;
    }
    if (is_private) {
        la_fail(ctx, LA_ERR_PRIVATE_NAME, line, 1, callee_length,
                la_name_slice(ctx, ctx->procedures[callee].name),
                la_slice("export", 6), 0, 0);
        return -1;
    }
    procedure = &ctx->procedures[callee];
    binding_count = 0;
    cursor = la_trim_left(cursor, end);
    while (cursor < end) {
        if (!la_parse_invoke_binding(
                ctx, &cursor, end, line, caller, procedure,
                &binding_count)) return -1;
    }
    if (!la_validate_invoke_inputs(
            ctx, procedure, binding_count, line)) return -1;
    if (binding_count > ctx->invoke_binding_highwater) {
        ctx->invoke_binding_highwater = binding_count;
        ctx->stats->invoke_bindings = binding_count;
    }
    scratch_name = la_slice(
        ctx->target->invoke_scratch_prefix,
        (la_u16)strlen(ctx->target->invoke_scratch_prefix));
    if (!la_reserve_invoke_scratch(
            ctx, binding_count, line, scratch_name, &scratch)) return -1;
    /*
     * Save registers first. Other snapshots may use A as their load register
     * and must not destroy an unsaved A value.
     */
    if (!la_emit_invoke_saves(
            ctx, procedure, binding_count, line, scratch_name, 1) ||
        !la_emit_invoke_saves(
            ctx, procedure, binding_count, line, scratch_name, 0) ||
        !la_emit_invoke_field_reads(
            ctx, procedure, binding_count, line, scratch_name) ||
        !la_emit_invoke_assignments(
            ctx, procedure, binding_count, line, scratch_name) ||
        !la_emit_invoke_register_fields(
            ctx, procedure, binding_count, line)) {
        return -1;
    }
    owner = la_name_slice(ctx, procedure->name);
    if (procedure->is_inline) {
        if (is_tail) {
            la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, callee_length,
                    owner, la_slice("inline has no tail form", 23), 0, 0);
            return -1;
        }
        if (la_expand_inline_body(ctx, callee, caller, line) < 0) return -1;
        return 1;
    }
    if (is_tail && ctx->procedures[caller].frame_size != 0) {
        la_fail(ctx, LA_ERR_FRAME_STACK_MUTATION, line, 1, callee_length,
                owner, la_slice("tail with live frame", 20), 0, 0);
        return -1;
    }
    if (!la_emit_invoke_operation(
            ctx, line,
            is_tail ? LA_TARGET_OP_INVOKE_TAIL : LA_TARGET_OP_INVOKE_CALL,
            owner, la_slice("", 0),
            la_slice("", 0), la_slice("", 0),
            scratch_name,
            scratch, binding_count, 0)) {
        return -1;
    }
    return 1;
}

static int la_parse_procedure_data(LaContext *ctx,
                                   const char *start, const char *end,
                                   la_u16 line, int emit)
{
    const char *cursor;
    const char *type_start;
    la_u16 type_length;
    la_u16 namespace_handle;
    la_u16 source_id;
    int is_code_pointer;
    cursor = la_trim_left(start, end);
    if (!la_line_keyword(cursor, end, "data")) return 0;
    cursor += 4;
    if (!la_read_identifier(
            &cursor, end, &type_start, &type_length) ||
        !(la_equal_text(type_start, type_length, "u8") ||
          la_equal_text(type_start, type_length, "u16") ||
          la_equal_text(type_start, type_length, "codeptr"))) return 0;
    is_code_pointer =
        la_equal_text(type_start, type_length, "codeptr");
    namespace_handle = la_namespace_at_line(ctx, line);
    source_id = la_source_id_at_line(ctx, line);
    cursor = la_trim_left(cursor, end);
    if (cursor == end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("procedure address", 17), la_slice("", 0), 0, 0);
        return -1;
    }
    while (cursor < end) {
        const char *part_start;
        const char *name_start;
        la_u16 part_length;
        la_u16 name_length;
        la_u16 procedure;
        LaTargetOperationKind operation;
        int is_private;
        if (is_code_pointer) {
            operation = LA_TARGET_OP_DATA_CODEPTR;
            if (!la_read_qualified_identifier(
                    &cursor, end, &name_start, &name_length)) {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_slice("procedure", 9), la_slice("", 0), 0, 0);
                return -1;
            }
            part_start = type_start;
            part_length = type_length;
        } else {
            if (!la_read_identifier(
                    &cursor, end, &part_start, &part_length)) {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_slice("low, high, addr, or full", 24),
                        la_slice("", 0), 0, 0);
                return -1;
            }
            if (la_equal_text(part_start, part_length, "low")) {
                operation = LA_TARGET_OP_DATA_PROC_LOW;
            } else if (la_equal_text(part_start, part_length, "high")) {
                operation = LA_TARGET_OP_DATA_PROC_HIGH;
            } else if (la_equal_text(part_start, part_length, "addr") ||
                       la_equal_text(part_start, part_length, "full")) {
                operation = LA_TARGET_OP_DATA_PROC_FULL;
            } else {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, part_length,
                        la_slice(part_start, part_length),
                        la_slice("low, high, addr, or full", 24), 0, 0);
                return -1;
            }
            cursor = la_trim_left(cursor, end);
            if (cursor >= end || *cursor++ != '(' ||
                !la_read_qualified_identifier(
                    &cursor, end, &name_start, &name_length)) {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_slice("part(PROCEDURE)", 15),
                        la_slice("", 0), 0, 0);
                return -1;
            }
            cursor = la_trim_left(cursor, end);
            if (cursor >= end || *cursor++ != ')') {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_slice(")", 1), la_slice("", 0), 0, 0);
                return -1;
            }
        }
        if ((!is_code_pointer && type_length == 2 &&
             operation == LA_TARGET_OP_DATA_PROC_FULL) ||
            (!is_code_pointer && type_length == 3 &&
             operation != LA_TARGET_OP_DATA_PROC_FULL)) {
            la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1, part_length,
                    la_slice(type_start, type_length),
                    la_slice(part_start, part_length), 0, 0);
            return -1;
        }
        procedure = la_find_procedure_scoped(
            ctx, name_start, name_length, namespace_handle,
            source_id, &is_private);
        if (procedure == LA_INVALID_HANDLE) {
            la_fail(ctx, LA_ERR_UNKNOWN_PROCEDURE, line, 1, name_length,
                    la_slice(name_start, name_length),
                    la_slice("", 0), 0, 0);
            return -1;
        }
        if (is_private) {
            la_fail(ctx, LA_ERR_PRIVATE_NAME, line, 1, name_length,
                    la_name_slice(ctx, ctx->procedures[procedure].name),
                    la_slice("export", 6), 0, 0);
            return -1;
        }
        if (ctx->procedures[procedure].is_inline) {
            /* An inline procedure has no emitted body and no address. */
            la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, name_length,
                    la_name_slice(ctx, ctx->procedures[procedure].name),
                    la_slice("inline has no address", 21), 0, 0);
            return -1;
        }
        if (emit) {
            LaEvent event;
            if (!la_count_operation(ctx, line)) return -1;
            la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION,
                          line, 1);
            event.owner =
                la_name_slice(ctx, ctx->procedures[procedure].name);
            event.operation = operation;
            event.access_width =
                operation == LA_TARGET_OP_DATA_CODEPTR ?
                    ctx->target->code_pointer_units :
                operation == LA_TARGET_OP_DATA_PROC_FULL ?
                    2 : 1;
            event.byte_order = is_code_pointer ?
                ctx->target->code_pointer_byte_order :
                ctx->target->byte_order;
            if (!la_write_event(ctx, &event)) return -1;
        }
        cursor = la_trim_left(cursor, end);
        if (cursor == end) break;
        if (*cursor++ != ',') {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice(",", 1), la_slice("", 0), 0, 0);
            return -1;
        }
        cursor = la_trim_left(cursor, end);
    }
    return 1;
}

static int la_parse_offset_materialization(LaContext *ctx,
                                           const char *start,
                                           const char *end,
                                           la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *physical_start;
    const char *path_start;
    const char *path_end;
    const char *first_dot;
    la_u16 physical_length;
    la_u16 field_index;
    la_u16 offset;
    la_i32 addend;
    cursor = la_trim_left(start, end);
    if (la_line_keyword(cursor, end, "offset")) {
        la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1, 6,
                la_slice(cursor, 6),
                la_slice("mov DEST, offset TYPE.FIELD", 27), 0, 0);
        return -1;
    }
    if (!la_line_keyword(cursor, end, "mov")) return 0;
    cursor += 3;
    if (!la_read_identifier(
            &cursor, end, &physical_start, &physical_length)) {
        return 0;
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ',') {
        return 0;
    }
    cursor = la_trim_left(cursor, end);
    if (!la_take_word(&cursor, end, "offset")) return 0;
    if (!(la_equal_text(physical_start, physical_length, "a") ||
          la_equal_text(physical_start, physical_length, "x") ||
          la_equal_text(physical_start, physical_length, "y"))) {
        la_fail(ctx, LA_ERR_MEMBER_PLACEMENT, line, 1, physical_length,
                la_slice(physical_start, physical_length),
                la_slice("a, x, or y", 10), 0, 0);
        return -1;
    }
    path_start = la_trim_left(cursor, end);
    cursor = path_start;
    while (cursor < end &&
           (la_is_ident(*cursor) || *cursor == '.')) ++cursor;
    path_end = cursor;
    addend = 0;
    cursor = la_trim_left(cursor, end);
    if (cursor < end && (*cursor == '+' || *cursor == '-')) {
        int negative;
        negative = *cursor++ == '-';
        cursor = la_trim_left(cursor, end);
        if (cursor == end || *cursor < '0' || *cursor > '9') {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_slice("constant byte addend", 20),
                    la_slice("", 0), 0, 0);
            return -1;
        }
        while (cursor < end && *cursor >= '0' && *cursor <= '9') {
            addend = addend * 10 + (*cursor++ - '0');
        }
        if (negative) addend = -addend;
        cursor = la_trim_left(cursor, end);
    }
    if (path_end == path_start || cursor != end) {
        la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                la_slice("TYPE.FIELD", 10), la_slice("", 0), 0, 0);
        return -1;
    }
    first_dot = path_start;
    while (first_dot < path_end && *first_dot != '.') ++first_dot;
    if (first_dot == path_end || first_dot + 1 == path_end ||
        la_resolve_path(ctx, path_start,
                        (la_u16)(first_dot - path_start),
                        first_dot + 1,
                        (la_u16)(path_end - first_dot - 1), line,
                        &field_index, &offset) != LA_OK) {
        if (ctx->error == LA_OK) {
            la_fail(ctx, LA_ERR_UNKNOWN_FIELD, line, 1,
                    (la_u16)(path_end - path_start),
                    la_slice(path_start,
                             (la_u16)(path_end - path_start)),
                    la_slice("", 0), 0, 0);
        }
        return -1;
    }
    if ((la_i32)offset + addend < 0 ||
        (la_i32)offset + addend > ctx->target->max_displacement) {
        la_fail(ctx, LA_ERR_DISPLACEMENT, line, 1,
                (la_u16)(path_end - path_start),
                la_slice(path_start, (la_u16)(path_end - path_start)),
                la_slice(physical_start, physical_length),
                (la_i32)offset + addend,
                ctx->target->max_displacement);
        return -1;
    }
    offset = (la_u16)((la_i32)offset + addend);
    (void)field_index;
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line, 1);
    event->operation = LA_TARGET_OP_MATERIALIZE_FIELD_OFFSET;
    event->base = la_slice(physical_start, physical_length);
    event->value = offset;
    event->owner = la_slice(
        path_start, (la_u16)(first_dot - path_start));
    event->path = la_slice(
        first_dot + 1, (la_u16)(path_end - first_dot - 1));
    return 1;
}

static int la_parse_qualified_immediate(LaContext *ctx,
                                        const char *start,
                                        const char *end,
                                        la_u16 line, LaEvent *event)
{
    const char *cursor;
    const char *destination_start;
    const char *expression_start;
    const char *identifier_end;
    la_u16 destination_length;
    LaTargetOperationKind operation;
    la_i32 value;
    int layout_query;
    cursor = la_trim_left(start, end);
    destination_start = 0;
    destination_length = 0;
    if (la_line_keyword(cursor, end, "mov")) {
        operation = LA_TARGET_OP_VALUE_MOV;
        cursor += 3;
        if (!la_read_qualified_identifier(
                &cursor, end, &destination_start,
                &destination_length)) return 0;
        cursor = la_trim_left(cursor, end);
        if (cursor >= end || *cursor++ != ',') return 0;
    } else if (la_line_keyword(cursor, end, "cmp")) {
        operation = LA_TARGET_OP_VALUE_CMP;
        cursor += 3;
    } else {
        return 0;
    }
    cursor = la_trim_left(cursor, end);
    layout_query = 0;
    if (cursor < end && *cursor == '#') {
        ++cursor;
        expression_start = la_trim_left(cursor, end);
        /* Byte-select operators (#<, #>) are a target spelling the semantic
           evaluator does not model; let the scoped-raw path emit them. */
        if (expression_start < end &&
            (*expression_start == '<' || *expression_start == '>')) {
            return 0;
        }
    } else {
        const char *query_end;
        const char *suffix;
        la_u16 suffix_length;
        query_end = cursor;
        while (query_end < end && la_is_ident(*query_end)) ++query_end;
        layout_query = la_layout_query_suffix(
            cursor, (la_u16)(query_end - cursor),
            &suffix, &suffix_length);
        (void)suffix;
        (void)suffix_length;
        if (!layout_query) return 0;
        expression_start = cursor;
    }
    if (expression_start == end) return 0;
    if (!layout_query &&
        memchr(expression_start, '.',
               (size_t)(end - expression_start)) == 0) {
        la_u16 scope;
        int found;
        identifier_end = expression_start;
        while (identifier_end < end &&
               la_is_ident(*identifier_end)) ++identifier_end;
        found = 0;
        scope = la_namespace_at_line(ctx, line);
        while (scope != LA_INVALID_HANDLE && !found) {
            la_u16 constant_index;
            LaSlice owner;
            owner = la_name_slice(
                ctx, ctx->namespaces[scope].name);
            for (constant_index = 0;
                 constant_index < ctx->constant_count; ++constant_index) {
                LaSlice name;
                name = la_name_slice(
                    ctx, ctx->constants[constant_index].name);
                if (name.length ==
                        owner.length + 1 +
                        (la_u16)(identifier_end - expression_start) &&
                    memcmp(name.data, owner.data, owner.length) == 0 &&
                    name.data[owner.length] == '.' &&
                    memcmp(name.data + owner.length + 1,
                           expression_start,
                           (size_t)(identifier_end -
                                    expression_start)) == 0) {
                    found = 1;
                    break;
                }
            }
            scope = ctx->namespaces[scope].parent;
        }
        if (!found) return 0;
    }
    if (la_eval_expression(
            ctx, expression_start, end, line, &value) != LA_OK) {
        return -1;
    }
    /* A bitwise result is masked to the operand width; other values keep
       the strict range check. */
    if (ctx->expression_family == LA_EXPR_BITWISE) {
        value = (la_i32)((la_u32)value & 0xff);
    }
    if (value < -128 || value > 255) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, 1,
                (la_u16)(end - expression_start),
                la_slice(expression_start,
                         (la_u16)(end - expression_start)),
                la_slice("8-bit immediate", 15), value, 255);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line, 1);
    event->operation = operation;
    event->base =
        la_slice(destination_start, destination_length);
    event->signed_value = value;
    return 1;
}

static LaDiagnosticCode la_validate_procedure_data(LaContext *ctx)
{
    const char *cursor;
    la_u16 line;
    la_reset_lines(ctx);
    line = 0;
    while (1) {
        const char *line_end;
        const char *content_end;
        int parsed;
        if (la_next_line(ctx, &cursor, &line_end, &line) <= 0) break;
        content_end = la_code_end(cursor, line_end);
        parsed = la_parse_procedure_data(
            ctx, cursor, content_end, line, 0);
        if (parsed < 0) return ctx->error;
    }
    return LA_OK;
}

static int la_emit_procedure_event(LaContext *ctx, la_u16 procedure,
                                   la_u16 line,
                                   LaTargetOperationKind operation)
{
    LaEvent event;
    LaProcedureRec *record;
    record = &ctx->procedures[procedure];
    if (!la_count_operation(ctx, line)) return 0;
    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
    event.owner = la_name_slice(ctx, record->name);
    event.operation = operation;
    event.value = record->frame_size;
    event.count = record->local_count;
    return la_write_event(ctx, &event);
}

static int la_emit_member_events(LaContext *ctx, la_u16 procedure)
{
    LaProcedureRec *record;
    la_u16 index;
    record = &ctx->procedures[procedure];
    for (index = record->first_parameter;
         index < record->first_parameter + record->parameter_count; ++index) {
        LaLocationRec *member;
        LaEvent event;
        member = &ctx->locations[index];
        la_init_event(ctx, &event, LA_EVENT_PROCEDURE_MEMBER,
                      member->line, 1);
        event.owner = la_name_slice(ctx, record->name);
        event.path = la_name_slice(ctx, member->name);
        event.base = la_name_slice(ctx, member->physical);
        event.aux = la_name_slice(ctx, member->type_name);
        event.value = member->role;
        event.stride = member->is_pointer ?
            ctx->target->pointer_units : 1;
        event.count = LA_PLACEMENT_PHYSICAL;
        if (!la_write_event(ctx, &event)) return 0;
    }
    for (index = record->first_local;
         index < record->first_local + record->local_count; ++index) {
        LaLocalRec *local;
        LaEvent event;
        local = &ctx->locals[index];
        la_init_event(ctx, &event, LA_EVENT_PROCEDURE_MEMBER,
                      local->line, 1);
        event.owner = la_name_slice(ctx, record->name);
        event.path = la_name_slice(ctx, local->name);
        event.aux = la_name_slice(ctx, local->type_name);
        event.value = LA_MEMBER_FRAME;
        event.offset = local->offset;
        event.stride = local->size;
        event.count = LA_PLACEMENT_FRAME;
        if (!la_write_event(ctx, &event)) return 0;
    }
    return 1;
}

/* True when some top-level (non-procedure) label, constant, procedure or
   location carries exactly this fully-qualified name. */
static int la_symbol_named(LaContext *ctx, const char *text, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < ctx->label_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->labels[index].name);
        if (name.length == length &&
            memcmp(name.data, text, length) == 0) return 1;
    }
    for (index = 0; index < ctx->constant_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->constants[index].name);
        if (name.length == length &&
            memcmp(name.data, text, length) == 0) return 1;
    }
    for (index = 0; index < ctx->procedure_count; ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->procedures[index].name);
        if (name.length == length &&
            memcmp(name.data, text, length) == 0) return 1;
    }
    for (index = 0; index < ctx->location_count; ++index) {
        LaSlice name;
        if (ctx->locations[index].procedure != LA_INVALID_HANDLE) continue;
        name = la_name_slice(ctx, ctx->locations[index].name);
        if (name.length == length &&
            memcmp(name.data, text, length) == 0) return 1;
    }
    return 0;
}

/* Resolve a bare identifier against the enclosing namespace chain (innermost
   outward). If some enclosing namespace owns a matching symbol, build its
   qualified spelling into path_buffer and return 1; a global/unknown name is
   left to the caller (return 0). Sibling namespaces are never searched. */
/* Physical registers are reserved spellings that always win over any symbol,
   so a namespace member named `x`/`y`/`a` must be referenced explicitly. */
static int la_is_target_register(LaContext *ctx, const char *text,
                                 la_u16 length)
{
    la_u16 c;
    la_u16 i;
    if (ctx->target->word_accumulator != 0 &&
        la_equal_text(text, length, ctx->target->word_accumulator)) return 1;
    for (c = 0; c < ctx->target->convention_count; ++c) {
        const LaConvention *convention;
        convention = &ctx->target->conventions[c];
        for (i = 0; i < convention->scalar_input_count; ++i) {
            if (la_equal_text(text, length, convention->scalar_inputs[i])) {
                return 1;
            }
        }
        if (convention->scalar_return != 0 &&
            la_equal_text(text, length, convention->scalar_return)) return 1;
    }
    return 0;
}

static int la_resolve_bare_identifier(LaContext *ctx, la_u16 namespace_handle,
                                      const char *ident, la_u16 ident_length,
                                      la_u16 *qualified_length)
{
    la_u16 ns;
    if (la_is_target_register(ctx, ident, ident_length)) return 0;
    ns = namespace_handle;
    while (ns != LA_INVALID_HANDLE) {
        LaSlice ns_name;
        la_u32 total;
        ns_name = la_name_slice(ctx, ctx->namespaces[ns].name);
        total = (la_u32)ns_name.length + 1 + ident_length;
        if (total <= ctx->limits->max_line_bytes) {
            memcpy(ctx->path_buffer, ns_name.data, ns_name.length);
            ctx->path_buffer[ns_name.length] = '.';
            memcpy(ctx->path_buffer + ns_name.length + 1, ident,
                   ident_length);
            if (la_symbol_named(ctx, ctx->path_buffer, (la_u16)total)) {
                *qualified_length = (la_u16)total;
                return 1;
            }
        }
        ns = ctx->namespaces[ns].parent;
    }
    return 0;
}

/* Rewrite a raw line, qualifying every bare identifier that resolves to an
   enclosing-namespace symbol into resolve_buffer. Returns 1 (and sets *length)
   when at least one identifier was qualified, 0 when the line is unchanged, or
   -1 on overflow. Qualified names, local labels, strings and comments pass
   through untouched so byte output is identical to the explicit spelling. */
static int la_qualify_scoped_line(LaContext *ctx, const char *start,
                                  const char *end, la_u16 line,
                                  la_u16 *length)
{
    la_u16 namespace_handle;
    char *out;
    char *out_end;
    const char *cursor;
    int changed;
    int quote;
    int escaped;
    namespace_handle = la_namespace_at_line(ctx, line);
    if (namespace_handle == LA_INVALID_HANDLE) return 0;
    out = ctx->resolve_buffer;
    out_end = ctx->resolve_buffer + ctx->limits->max_line_bytes;
    cursor = start;
    changed = 0;
    quote = 0;
    escaped = 0;
    while (cursor < end) {
        char value;
        value = *cursor;
        if (out >= out_end) return -1;
        if (quote != 0) {
            *out++ = value;
            if (escaped) escaped = 0;
            else if (value == '\\') escaped = 1;
            else if (value == quote) quote = 0;
            ++cursor;
            continue;
        }
        if (value == ';') {
            while (cursor < end) {
                if (out >= out_end) return -1;
                *out++ = *cursor++;
            }
            break;
        }
        if (value == '"' || value == '\'') {
            quote = value;
            *out++ = value;
            ++cursor;
            continue;
        }
        if (value == '.') {
            /* A local label or member access: copy the dot and any following
               identifier verbatim so it is never treated as bare. */
            *out++ = value;
            ++cursor;
            while (cursor < end && la_is_ident(*cursor)) {
                if (out >= out_end) return -1;
                *out++ = *cursor++;
            }
            continue;
        }
        if (la_is_ident_start(value)) {
            const char *ident_start;
            const char *scan;
            la_u16 ident_length;
            ident_start = cursor++;
            while (cursor < end && la_is_ident(*cursor)) ++cursor;
            ident_length = (la_u16)(cursor - ident_start);
            if (cursor < end && *cursor == '.' && cursor + 1 < end &&
                la_is_ident_start(cursor[1])) {
                /* Already qualified: copy the whole dotted chain verbatim. */
                scan = cursor;
                while (scan < end && *scan == '.' && scan + 1 < end &&
                       la_is_ident_start(scan[1])) {
                    ++scan;
                    while (scan < end && la_is_ident(*scan)) ++scan;
                }
                while (ident_start < scan) {
                    if (out >= out_end) return -1;
                    *out++ = *ident_start++;
                }
                cursor = scan;
                continue;
            }
            {
                la_u16 qualified_length;
                if (la_resolve_bare_identifier(ctx, namespace_handle,
                                               ident_start, ident_length,
                                               &qualified_length)) {
                    if (out + qualified_length > out_end) return -1;
                    memcpy(out, ctx->path_buffer, qualified_length);
                    out += qualified_length;
                    changed = 1;
                } else {
                    if (out + ident_length > out_end) return -1;
                    memcpy(out, ident_start, ident_length);
                    out += ident_length;
                }
            }
            continue;
        }
        *out++ = value;
        ++cursor;
    }
    if (!changed) return 0;
    *length = (la_u16)(out - ctx->resolve_buffer);
    return 1;
}

static int la_validate_scoped_raw(LaContext *ctx, const char *start,
                                  const char *end, la_u16 line)
{
    const char *cursor;
    la_u16 source_id;
    int found_any;
    int quote;
    int escaped;
    cursor = start;
    source_id = la_source_id_at_line(ctx, line);
    found_any = 0;
    quote = 0;
    escaped = 0;
    while (cursor < end) {
        const char *name_start;
        const char *name_end;
        const char *part;
        la_u16 length;
        la_u16 index;
        la_u16 symbol_name;
        la_u16 symbol_source;
        int found;
        char value;
        value = *cursor;
        if (quote != 0) {
            if (escaped) {
                escaped = 0;
            } else if (value == '\\') {
                escaped = 1;
            } else if (value == quote) {
                quote = 0;
            }
            ++cursor;
            continue;
        }
        if (value == '"' || value == '\'') {
            quote = value;
            ++cursor;
            continue;
        }
        if (!la_is_ident_start(value)) {
            ++cursor;
            continue;
        }
        name_start = cursor++;
        while (cursor < end && la_is_ident(*cursor)) ++cursor;
        if (cursor >= end || *cursor != '.') continue;
        name_end = cursor;
        part = cursor;
        while (part < end && *part == '.') {
            ++part;
            if (part >= end || !la_is_ident_start(*part)) break;
            ++part;
            while (part < end && la_is_ident(*part)) ++part;
            name_end = part;
        }
        if (name_end == cursor) continue;
        cursor = name_end;
        length = (la_u16)(name_end - name_start);
        found = 0;
        symbol_name = LA_INVALID_HANDLE;
        symbol_source = 0;
        for (index = 0; index < ctx->label_count; ++index) {
            LaSlice name;
            name = la_name_slice(ctx, ctx->labels[index].name);
            if (name.length == length &&
                memcmp(name.data, name_start, length) == 0) {
                found = 1;
                symbol_name = ctx->labels[index].name;
                symbol_source = ctx->labels[index].source_id;
                break;
            }
        }
        for (index = 0; !found && index < ctx->constant_count; ++index) {
            LaSlice name;
            name = la_name_slice(ctx, ctx->constants[index].name);
            if (name.length == length &&
                memcmp(name.data, name_start, length) == 0) {
                found = 1;
                symbol_name = ctx->constants[index].name;
                symbol_source = ctx->constants[index].source_id;
            }
        }
        for (index = 0; !found && index < ctx->procedure_count; ++index) {
            LaSlice name;
            name = la_name_slice(ctx, ctx->procedures[index].name);
            if (name.length == length &&
                memcmp(name.data, name_start, length) == 0) {
                found = 1;
                symbol_name = ctx->procedures[index].name;
                symbol_source = ctx->procedures[index].source_id;
            }
        }
        for (index = 0; !found && index < ctx->location_count; ++index) {
            LaSlice name;
            if (ctx->locations[index].procedure != LA_INVALID_HANDLE) {
                continue;
            }
            name = la_name_slice(ctx, ctx->locations[index].name);
            if (name.length == length &&
                memcmp(name.data, name_start, length) == 0) {
                found = 1;
                symbol_name = ctx->locations[index].name;
                symbol_source = ctx->locations[index].source_id;
            }
        }
        if (!found) {
            int namespace_prefix;
            namespace_prefix = 0;
            for (index = 0; index < ctx->namespace_count; ++index) {
                LaSlice namespace_name;
                namespace_name =
                    la_name_slice(ctx, ctx->namespaces[index].name);
                if (namespace_name.length < length &&
                    name_start[namespace_name.length] == '.' &&
                    memcmp(namespace_name.data, name_start,
                           namespace_name.length) == 0) {
                    namespace_prefix = 1;
                    break;
                }
            }
            if (namespace_prefix) {
                la_fail(ctx, LA_ERR_UNKNOWN_SYMBOL, line,
                        (la_u16)(name_start - start + 1), length,
                        la_slice(name_start, length),
                        la_slice("", 0), 0, 0);
                return -1;
            }
            continue;
        }
        if (symbol_source != source_id &&
            !la_name_is_exported(ctx, symbol_name)) {
            la_fail(ctx, LA_ERR_PRIVATE_NAME, line,
                    (la_u16)(name_start - start + 1), length,
                    la_slice(name_start, length),
                    la_slice("export", 6), 0, 0);
            return -1;
        }
        found_any = 1;
    }
    return found_any;
}

static LaDiagnosticCode la_emit_all(LaContext *ctx)
{
    LaEvent event;
    const char *cursor;
    la_u16 line;
    la_u16 sid;
    la_u16 namespace_depth;
    int in_struct;
    la_u16 active_procedure;
    ctx->active_source_id = ctx->input->source_id;
    la_init_event(ctx, &event, LA_EVENT_HEADER, 1, 1);
    event.owner = la_slice(ctx->target->name,
                           (la_u16)strlen(ctx->target->name));
    event.value = LA_FORMAT_VERSION;
    if (!la_write_event(ctx, &event)) return ctx->error;
    for (sid = 0; sid < ctx->location_count; ++sid) {
        if (ctx->locations[sid].procedure != LA_INVALID_HANDLE ||
            !ctx->locations[sid].has_numeric_physical) continue;
        ctx->active_source_id = ctx->locations[sid].source_id;
        la_init_event(ctx, &event, LA_EVENT_LOCATION,
                      ctx->locations[sid].line, 1);
        event.owner = la_name_slice(ctx, ctx->locations[sid].name);
        event.aux = la_name_slice(ctx, ctx->locations[sid].type_name);
        event.signed_value = ctx->locations[sid].numeric_physical;
        event.access_width = ctx->locations[sid].storage_width;
        if (!la_write_event(ctx, &event)) return ctx->error;
    }
    for (sid = 0; sid < ctx->constant_count; ++sid) {
        ctx->active_source_id = ctx->constants[sid].source_id;
        la_init_event(ctx, &event, LA_EVENT_CONSTANT,
                      ctx->constants[sid].line, 1);
        event.owner =
            la_name_slice(ctx, ctx->constants[sid].name);
        event.signed_value = ctx->constants[sid].value;
        if (!la_write_event(ctx, &event)) return ctx->error;
    }
    for (sid = 0; sid < ctx->enum_count; ++sid) {
        LaSlice owner;
        ctx->active_source_id = ctx->enums[sid].source_id;
        owner = la_name_slice(ctx, ctx->enums[sid].name);
        if (!la_emit_property(ctx, ctx->enums[sid].line, owner,
                              la_slice("", 0), LA_PROPERTY_STRUCT_SIZE,
                              ctx->enums[sid].size) ||
            !la_emit_property(ctx, ctx->enums[sid].line, owner,
                              la_slice("", 0), LA_PROPERTY_STRUCT_ALIGN,
                              1)) return ctx->error;
    }
    for (sid = 0; sid < ctx->enum_member_count; ++sid) {
        LaEnumMemberRec *member;
        LaEnumRec *enumeration;
        member = &ctx->enum_members[sid];
        enumeration = &ctx->enums[member->owner];
        ctx->active_source_id = enumeration->source_id;
        la_init_event(ctx, &event, LA_EVENT_ENUM_MEMBER,
                      member->line, 1);
        event.owner = la_name_slice(ctx, enumeration->name);
        event.path = la_name_slice(ctx, member->name);
        if (enumeration->is_signed) {
            if (enumeration->size == 1) {
                event.aux = la_slice("i8", 2);
            } else {
                event.aux = la_slice("i16", 3);
            }
        } else {
            if (enumeration->size == 1) {
                event.aux = la_slice("u8", 2);
            } else {
                event.aux = la_slice("u16", 3);
            }
        }
        event.signed_value = member->value;
        event.offset = enumeration->size;
        event.count = enumeration->is_signed;
        if (!la_write_event(ctx, &event)) return ctx->error;
    }
    for (sid = 0; sid < ctx->struct_count; ++sid) {
        ctx->active_source_id = ctx->structs[sid].source_id;
        if (!la_emit_struct_properties(ctx, sid)) return ctx->error;
    }
    for (sid = 0; sid < ctx->overlay_count; ++sid) {
        LaOverlayRec *overlay;
        la_u16 aggregate;
        overlay = &ctx->overlays[sid];
        ctx->active_source_id = overlay->source_id;
        aggregate = la_find_struct_handle(ctx, overlay->type_name);
        la_init_event(ctx, &event, LA_EVENT_OVERLAY, overlay->line, 1);
        event.owner = la_name_slice(ctx, overlay->name);
        event.aux = la_name_slice(ctx, overlay->type_name);
        event.base = la_name_slice(ctx, overlay->base);
        event.value = ctx->structs[aggregate].size;
        event.offset = ctx->structs[aggregate].alignment;
        event.aggregate_kind =
            (LaAggregateKind)ctx->structs[aggregate].kind;
        event.layout_policy =
            (LaLayoutPolicy)ctx->structs[aggregate].policy;
        if (!la_write_event(ctx, &event)) return ctx->error;
    }
    for (sid = 0; sid < ctx->pool_count; ++sid) {
        LaSlice owner;
        ctx->active_source_id = ctx->pools[sid].source_id;
        owner = la_name_slice(ctx, ctx->pools[sid].name);
        if (!la_emit_property(ctx, ctx->pools[sid].line, owner,
                              la_slice("", 0), LA_PROPERTY_FIELD_COUNT,
                              ctx->pools[sid].count) ||
            !la_emit_property(ctx, ctx->pools[sid].line, owner,
                              la_slice("", 0), LA_PROPERTY_FIELD_STRIDE,
                              ctx->pools[sid].stride) ||
            !la_emit_property(ctx, ctx->pools[sid].line, owner,
                              la_slice("", 0), LA_PROPERTY_FIELD_SIZE,
                              ctx->pools[sid].size) ||
            !la_emit_property(ctx, ctx->pools[sid].line, owner,
                              la_slice("", 0), LA_PROPERTY_STRUCT_ALIGN,
                              ctx->pools[sid].alignment)) return ctx->error;
    }
    la_reset_lines(ctx);
    line = 0;
    in_struct = 0;
    namespace_depth = 0;
    active_procedure = LA_INVALID_HANDLE;
    while (1) {
        const char *line_end;
        const char *content_end;
        const char *trimmed;
        int typed;
        int semantic_constant;
        la_u16 semantic_label;
        if (la_next_line(ctx, &cursor, &line_end, &line) <= 0) break;
        content_end = la_code_end(cursor, line_end);
        trimmed = la_trim_left(cursor, content_end);
        semantic_constant = 0;
        semantic_label = LA_INVALID_HANDLE;
        for (sid = 0; sid < ctx->constant_count; ++sid) {
            if (ctx->constants[sid].source_id == ctx->active_source_id &&
                ctx->constants[sid].line == line) {
                semantic_constant = 1;
                break;
            }
        }
        for (sid = 0; sid < ctx->label_count; ++sid) {
            if (ctx->labels[sid].source_id == ctx->active_source_id &&
                ctx->labels[sid].line == line) {
                semantic_label = sid;
                break;
            }
        }
        if (active_procedure != LA_INVALID_HANDLE &&
            ctx->procedures[active_procedure].is_inline &&
            line > ctx->procedures[active_procedure].begin_line &&
            line < ctx->procedures[active_procedure].end_line) {
            if (la_capture_inline_line(ctx, active_procedure, trimmed,
                                       content_end, line) < 0) {
                return ctx->error;
            }
        } else if (semantic_constant) {
            /* Compile-time constants were emitted semantically above. */
        } else if (semantic_label != LA_INVALID_HANDLE) {
            la_init_event(ctx, &event, LA_EVENT_LABEL, line, 1);
            event.owner =
                la_name_slice(ctx, ctx->labels[semantic_label].name);
            if (!la_write_event(ctx, &event)) return ctx->error;
        } else if (in_struct) {
            if (la_line_keyword(trimmed, content_end, "end")) in_struct = 0;
        } else if (la_line_keyword(trimmed, content_end, "namespace")) {
            ++namespace_depth;
        } else if (la_line_keyword(trimmed, content_end, "export")) {
            /* Namespace visibility declarations are semantic-only. */
        } else if (active_procedure == LA_INVALID_HANDLE &&
                   namespace_depth != 0 &&
                   la_line_keyword(trimmed, content_end, "end")) {
            --namespace_depth;
        } else if (la_line_keyword(trimmed, content_end, "struct") ||
                   la_line_keyword(trimmed, content_end, "union") ||
                   la_line_keyword(trimmed, content_end, "enum")) {
            in_struct = 1;
        } else if (active_procedure != LA_INVALID_HANDLE &&
                   line <= ctx->procedures[active_procedure].begin_line) {
            /* Procedure header, parameters, locals and begin are semantic. */
        } else if (active_procedure != LA_INVALID_HANDLE &&
                   line == ctx->procedures[active_procedure].end_line) {
            active_procedure = LA_INVALID_HANDLE;
        } else if (la_line_keyword(trimmed, content_end, "proc")) {
            la_u16 procedure;
            procedure = LA_INVALID_HANDLE;
            for (sid = 0; sid < ctx->procedure_count; ++sid) {
                if (ctx->procedures[sid].source_id ==
                        ctx->active_source_id &&
                    ctx->procedures[sid].line == line) {
                    procedure = sid;
                    break;
                }
            }
            if (procedure == LA_INVALID_HANDLE) return LA_ERR_PROCEDURE_SCOPE;
            active_procedure = procedure;
            if (ctx->procedures[procedure].is_inline) {
                ctx->procedures[procedure].body_first_lineidx =
                    ctx->inline_line_count;
                ctx->procedures[procedure].body_line_count = 0;
            } else {
                if (!la_emit_member_events(ctx, procedure)) return ctx->error;
                if (!la_emit_procedure_event(
                        ctx, procedure, line,
                        ctx->procedures[procedure].naked ?
                            LA_TARGET_OP_PROC_NAKED :
                            LA_TARGET_OP_PROC_FRAME)) return ctx->error;
            }
        } else if (la_line_keyword(trimmed, content_end, "pool") ||
                   la_line_keyword(trimmed, content_end, "overlay")) {
            /* Storage declarations are semantic-only. */
        } else if (la_line_keyword(trimmed, content_end, "location") ||
                   la_line_keyword(trimmed, content_end, "static_assert")) {
            /* semantic-only */
        } else if (active_procedure != LA_INVALID_HANDLE &&
                   la_line_keyword(trimmed, content_end, "ret")) {
            if (!la_equal_text(trimmed, (la_u16)(content_end - trimmed),
                               "ret")) {
                return la_fail(ctx, LA_ERR_SYNTAX, line, 1,
                               (la_u16)(content_end - trimmed),
                               la_slice("ret", 3),
                               la_slice(trimmed,
                                        (la_u16)(content_end - trimmed)),
                               0, 0);
            }
            if (!la_emit_procedure_event(ctx, active_procedure, line,
                                         LA_TARGET_OP_PROC_RETURN)) {
                return ctx->error;
            }
        } else if (active_procedure != LA_INVALID_HANDLE &&
                   la_line_keyword(trimmed, content_end, "invoke")) {
            la_u16 length;
            la_u16 invoke_source_id;
            const char *logical_end;
            length = (la_u16)(content_end - trimmed);
            invoke_source_id = ctx->active_source_id;
            if (length > ctx->limits->max_line_bytes) {
                return la_fail(ctx, LA_ERR_INVOKE_CAPACITY, line, 1, length,
                               la_slice("invoke line", 11),
                               la_slice("", 0), length,
                               ctx->limits->max_line_bytes);
            }
            memcpy(ctx->line_buffer, trimmed, length);
            logical_end = content_end;
            while (length != 0 && ctx->line_buffer[length - 1] == ',') {
                const char *next_start;
                const char *next_end;
                const char *next_code_end;
                const char *next_trimmed;
                la_u16 continuation_line;
                if (la_next_line(ctx, &next_start, &next_end,
                                 &continuation_line) <= 0) {
                    return la_fail(ctx, LA_ERR_INVOKE_BINDING, line, 1, 1,
                                   la_slice("continued binding", 17),
                                   la_slice("", 0), 0, 0);
                }
                next_code_end = la_code_end(next_start, next_end);
                next_trimmed = la_trim_left(next_start, next_code_end);
                if ((la_u32)length + 1 +
                    (la_u16)(next_code_end - next_trimmed) >
                    ctx->limits->max_line_bytes) {
                    return la_fail(ctx, LA_ERR_INVOKE_CAPACITY, line, 1, 1,
                                   la_slice("logical invoke", 14),
                                   la_slice("", 0), length + 1 +
                                   (la_u16)(next_code_end - next_trimmed),
                                   ctx->limits->max_line_bytes);
                }
                ctx->line_buffer[length++] = ' ';
                memcpy(ctx->line_buffer + length, next_trimmed,
                       (size_t)(next_code_end - next_trimmed));
                length = (la_u16)(length +
                                  (next_code_end - next_trimmed));
                logical_end = next_code_end;
            }
            (void)logical_end;
            ctx->line_buffer[length] = 0;
            ctx->active_source_id = invoke_source_id;
            typed = la_parse_invoke(
                ctx, ctx->line_buffer, ctx->line_buffer + length,
                line, active_procedure);
            if (typed < 0) return ctx->error;
        } else {
            if (la_process_operation_line(ctx, cursor, content_end,
                                          line_end, line) < 0) {
                return ctx->error;
            }
        }
    }
    return LA_OK;
}

/* One operation-position line: the typed parser chain, then the raw escape
   hatch. Shared by the main pass and inline expansion replay. Returns 0 on
   success and -1 with ctx->error set on failure. */
static int la_process_operation_line(LaContext *ctx, const char *cursor,
                                     const char *content_end,
                                     const char *line_end, la_u16 line)
{
    LaEvent event;
    int typed;
    int data_emitted;
    const char *save_cursor;
    const char *save_content;
    la_u16 resolved_length;
    int resolved;
    data_emitted = 0;
    /* Parsers fill only the fields they own; start from a zeroed event so
       unset fields are deterministic. */
    memset(&event, 0, sizeof(event));
    /* Resolve bare enclosing-namespace names once, up front, so every
       typed parser (placements, mov/word operands, brackets) sees the
       same qualified spelling the scoped-raw path already resolves. */
    save_cursor = cursor;
    save_content = content_end;
    resolved_length = 0;
    resolved = la_qualify_scoped_line(
        ctx, cursor, content_end, line, &resolved_length);
    if (resolved < 0) {
        la_fail(ctx, LA_ERR_NAME_CAPACITY, line, 1,
                (la_u16)(content_end - cursor),
                la_slice("resolved line", 13),
                la_slice("", 0),
                (la_i32)(content_end - cursor),
                ctx->limits->max_line_bytes);
        return -1;
    }
    if (resolved > 0) {
        cursor = ctx->resolve_buffer;
        content_end = ctx->resolve_buffer + resolved_length;
    }
    typed = la_parse_procedure_data(
        ctx, cursor, content_end, line, 1);
    if (typed > 0) data_emitted = 1;
    if (typed == 0) {
        typed = la_parse_offset_materialization(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_qualified_immediate(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_overlay_store_immediate(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_overlay_branch(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_frame_pointer_move(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_local_operation(ctx, cursor, content_end,
                                         line, &event);
    }
    if (typed == 0) {
        typed = la_parse_pool_address(ctx, cursor, content_end,
                                      line, &event);
    }
    if (typed == 0) {
        typed = la_parse_typed_word_operation(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_physical_word_arithmetic(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_typed_byte_rmw(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_observation_operation(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_word_move(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0) {
        typed = la_parse_typed_operation(ctx, cursor, content_end,
                                         line, &event);
    }
    if (typed < 0) return -1;
    if (typed == 0) {
        /* No typed parser matched; the raw path re-resolves from the
           original slice so the trailing comment is preserved. */
        cursor = save_cursor;
        content_end = save_content;
    }
    if (typed > 0) {
        if (!data_emitted &&
            !la_write_event(ctx, &event)) return -1;
    } else if (la_has_explicit_typed_operand(cursor, content_end)) {
        la_fail(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, 1,
                (la_u16)(content_end - cursor),
                la_slice(cursor,
                         (la_u16)(content_end - cursor)),
                la_slice("raw assembly escape hatch", 24),
                0, 0);
        return -1;
    } else {
        int scoped_raw;
        int qualified;
        la_u16 qualified_length;
        scoped_raw = la_validate_scoped_raw(
            ctx, cursor, content_end, line);
        if (scoped_raw < 0) return -1;
        qualified_length = 0;
        qualified = la_qualify_scoped_line(
            ctx, cursor, line_end, line, &qualified_length);
        if (qualified < 0) {
            la_fail(ctx, LA_ERR_NAME_CAPACITY, line, 1,
                    (la_u16)(line_end - cursor),
                    la_slice("resolved line", 13),
                    la_slice("", 0),
                    (la_i32)(line_end - cursor),
                    ctx->limits->max_line_bytes);
            return -1;
        }
        if (qualified > 0) {
            /* Enclosing-namespace names were qualified in place; the
               result must go through the scoped-raw mangler. */
            la_init_event(ctx, &event, LA_EVENT_SCOPED_RAW, line,
                          qualified_length);
            event.text = la_slice(ctx->resolve_buffer,
                                  qualified_length);
        } else {
            la_init_event(ctx, &event,
                          scoped_raw ? LA_EVENT_SCOPED_RAW :
                                       LA_EVENT_RAW,
                          line,
                          (la_u16)(line_end - cursor));
            event.text = la_slice(cursor,
                                  (la_u16)(line_end - cursor));
        }
        if (!la_write_event(ctx, &event)) return -1;
    }
    return 0;
}

/* Capture one inline-procedure body line. The module expander has already
   removed comments and blank lines. Rejected here: ret, non-local labels,
   nested declarations, and invoke continuation commas. */
static int la_capture_inline_line(LaContext *ctx, la_u16 procedure,
                                  const char *start, const char *end,
                                  la_u16 line)
{
    LaProcedureRec *record;
    LaInlineLineRec *entry;
    la_u16 length;
    const char *scan;
    record = &ctx->procedures[procedure];
    length = (la_u16)(end - start);
    if (length == 0) return 0;
    if (la_equal_text(start, length, "ret") ||
        la_line_keyword(start, end, "proc") ||
        la_line_keyword(start, end, "namespace") ||
        la_line_keyword(start, end, "struct") ||
        la_line_keyword(start, end, "union") ||
        la_line_keyword(start, end, "enum") ||
        la_line_keyword(start, end, "include")) {
        la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, length,
                la_slice(start, length),
                la_slice("no ret or declarations in inline body", 37),
                0, 0);
        return -1;
    }
    if (la_line_keyword(start, end, "invoke") && end[-1] == ',') {
        la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, length,
                la_slice(start, length),
                la_slice("single-line invoke only", 23), 0, 0);
        return -1;
    }
    if (la_is_ident_start(*start)) {
        scan = start;
        while (scan < end && la_is_ident(*scan)) ++scan;
        if (scan < end && *scan == ':') {
            la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, length,
                    la_slice(start, length),
                    la_slice("only .local labels in inline body", 33),
                    0, 0);
            return -1;
        }
    }
    if (la_line_keyword(start, end, "jmp")) {
        scan = la_trim_left(start + 3, end);
        if (scan < end && *scan != '.') record->has_nonlocal_jmp = 1;
    }
    if (ctx->inline_line_count >= ctx->limits->max_inline_body_lines) {
        la_fail(ctx, LA_ERR_INLINE_CAPACITY, line, 1, 1,
                la_slice("inline body lines", 17), la_slice("", 0),
                ctx->inline_line_count + 1,
                ctx->limits->max_inline_body_lines);
        return -1;
    }
    if ((la_u32)ctx->inline_body_used + length + 1 >
        (la_u32)ctx->limits->max_inline_body_bytes) {
        la_fail(ctx, LA_ERR_INLINE_CAPACITY, line, 1, 1,
                la_slice("inline body bytes", 17), la_slice("", 0),
                (la_i32)ctx->inline_body_used + length + 1,
                ctx->limits->max_inline_body_bytes);
        return -1;
    }
    memcpy(ctx->inline_bodies + ctx->inline_body_used, start, length);
    ctx->inline_bodies[ctx->inline_body_used + length] = 0;
    entry = &ctx->inline_lines[ctx->inline_line_count];
    entry->offset = ctx->inline_body_used;
    entry->length = length;
    entry->source_id = la_source_id_at_line(ctx, line);
    entry->line = line;
    ctx->inline_body_used = (la_u16)(ctx->inline_body_used + length + 1);
    ++ctx->inline_line_count;
    ++record->body_line_count;
    return 0;
}

/* Expand a previously captured inline body at an invoke site. Local labels
   are freshened per expansion as dot-local names, so no new target label
   scope opens at the call site. */
static int la_expand_inline_body(LaContext *ctx, la_u16 callee,
                                 la_u16 caller, la_u16 line)
{
    LaProcedureRec *record;
    char *buffer;
    la_u16 index;
    la_u16 serial;
    la_u16 saved_source_id;
    record = &ctx->procedures[callee];
    if (ctx->inline_depth >= 8) {
        la_fail(ctx, LA_ERR_INLINE_DEPTH, line, 1, 1,
                la_name_slice(ctx, record->name), la_slice("", 0),
                ctx->inline_depth + 1, 8);
        return -1;
    }
    if (record->has_nonlocal_jmp &&
        ctx->procedures[caller].frame_size != 0) {
        la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, 1,
                la_name_slice(ctx, record->name),
                la_slice("tail jmp with live caller frame", 31), 0, 0);
        return -1;
    }
    if (ctx->inline_serial >= ctx->limits->max_inline_expansions) {
        la_fail(ctx, LA_ERR_INLINE_CAPACITY, line, 1, 1,
                la_slice("inline expansions", 17), la_slice("", 0),
                ctx->inline_serial + 1,
                ctx->limits->max_inline_expansions);
        return -1;
    }
    serial = ++ctx->inline_serial;
    ctx->stats->inline_expansions = ctx->inline_serial;
    buffer = ctx->inline_line_buffers +
             (size_t)ctx->inline_depth *
             ((size_t)ctx->limits->max_line_bytes + 1);
    ++ctx->inline_depth;
    saved_source_id = ctx->active_source_id;
    for (index = 0; index < record->body_line_count; ++index) {
        LaInlineLineRec *entry;
        const char *src;
        const char *scan;
        char *out;
        char *out_end;
        int in_quotes;
        int result;
        entry = &ctx->inline_lines[record->body_first_lineidx + index];
        src = ctx->inline_bodies + entry->offset;
        out = buffer;
        out_end = buffer + ctx->limits->max_line_bytes;
        in_quotes = 0;
        for (scan = src; scan < src + entry->length; ++scan) {
            if (*scan == '"') in_quotes = !in_quotes;
            if (!in_quotes && *scan == '.' &&
                (scan == src || !la_is_ident(scan[-1])) &&
                scan + 1 < src + entry->length &&
                la_is_ident_start(scan[1])) {
                char prefix[24];
                char digits[8];
                int written;
                int digit_count;
                unsigned value;
                memcpy(prefix, ".__la_i", 7);
                written = 7;
                value = (unsigned)serial;
                digit_count = 0;
                do {
                    digits[digit_count++] = (char)('0' + value % 10);
                    value /= 10;
                } while (value != 0);
                while (digit_count > 0) {
                    prefix[written++] = digits[--digit_count];
                }
                prefix[written++] = '_';
                if (out + written >= out_end) {
                    --ctx->inline_depth;
                    la_fail(ctx, LA_ERR_INLINE_CAPACITY, entry->line, 1, 1,
                            la_slice("freshened line", 14),
                            la_slice("", 0), 0,
                            ctx->limits->max_line_bytes);
                    return -1;
                }
                memcpy(out, prefix, (size_t)written);
                out += written;
                continue;
            }
            if (out >= out_end) {
                --ctx->inline_depth;
                la_fail(ctx, LA_ERR_INLINE_CAPACITY, entry->line, 1, 1,
                        la_slice("freshened line", 14),
                        la_slice("", 0), 0, ctx->limits->max_line_bytes);
                return -1;
            }
            *out++ = *scan;
        }
        *out = 0;
        ctx->active_source_id = entry->source_id;
        if (la_line_keyword(buffer, out, "invoke")) {
            result = la_parse_invoke(ctx, buffer, out, entry->line, callee);
            if (result <= 0) {
                --ctx->inline_depth;
                return -1;
            }
        } else if (la_process_operation_line(ctx, buffer, out, out,
                                             entry->line) < 0) {
            --ctx->inline_depth;
            return -1;
        }
    }
    --ctx->inline_depth;
    ctx->active_source_id = saved_source_id;
    return 0;
}

static LaDiagnosticCode la_load_source(LaContext *ctx)
{
    int amount;
    la_u16 remaining;
    remaining = ctx->limits->max_source_bytes;
    ctx->source_length = 0;
    while (1) {
        if (remaining == 0) {
            char extra;
            amount = ctx->input->read(ctx->input->context, &extra, 1);
            if (amount > 0) {
                return la_fail(ctx, LA_ERR_SOURCE_CAPACITY, 1, 1, 1,
                               la_slice("source", 6), la_slice("", 0),
                               ctx->source_length + 1,
                               ctx->limits->max_source_bytes);
            }
            break;
        }
        amount = ctx->input->read(ctx->input->context,
                                  ctx->source + ctx->source_length, remaining);
        if (amount < 0) {
            return la_fail(ctx, LA_ERR_IO, 1, 1, 1,
                           la_slice("input", 5), la_slice("", 0), amount, 0);
        }
        if (amount == 0) break;
        if ((la_u16)amount > remaining) {
            return la_fail(ctx, LA_ERR_IO, 1, 1, 1,
                           la_slice("input overflow", 14),
                           la_slice("", 0), amount, remaining);
        }
        ctx->source_length = (la_u16)(ctx->source_length + amount);
        remaining = (la_u16)(remaining - amount);
    }
    ctx->source[ctx->source_length] = 0;
    ctx->stats->source_bytes = ctx->source_length;
    return LA_OK;
}

LaDiagnosticCode la_compile(const LaInput *input,
                            const LaEventSink *events,
                            const LaDiagnosticSink *diagnostics,
                            const LaTarget *target,
                            const LaLimits *limits,
                            LaWorkspace workspace,
                            LaStats *stats)
{
    LaContext ctx;
    char *cursor;
    la_u32 remaining;
    la_u32 required;
    memset(&ctx, 0, sizeof(ctx));
    memset(stats, 0, sizeof(*stats));
    ctx.input = input;
    ctx.events = events;
    ctx.diagnostics = diagnostics;
    ctx.target = target;
    ctx.limits = limits;
    ctx.stats = stats;
    ctx.current_struct = LA_INVALID_HANDLE;
    ctx.current_enum = LA_INVALID_HANDLE;
    ctx.current_procedure = LA_INVALID_HANDLE;
    ctx.current_namespace = LA_INVALID_HANDLE;
    ctx.error = LA_OK;
    required = la_workspace_required(limits);
    if (workspace.data == 0 || workspace.size < required) {
        ctx.error = LA_ERR_WORKSPACE;
        if (diagnostics != 0 && diagnostics->write != 0) {
            LaDiagnostic diagnostic;
            memset(&diagnostic, 0, sizeof(diagnostic));
            diagnostic.code = LA_ERR_WORKSPACE;
            diagnostic.value = (la_i32)required;
            diagnostic.limit = (la_i32)workspace.size;
            diagnostics->write(diagnostics->context, &diagnostic);
        }
        return ctx.error;
    }
    cursor = (char *)workspace.data;
    remaining = workspace.size;
    ctx.source = (char *)la_take(&cursor, &remaining,
                                 (la_u32)limits->max_source_bytes + 1);
    ctx.names = (char *)la_take(&cursor, &remaining,
                                (la_u32)limits->max_name_bytes + 1);
    ctx.line_buffer = (char *)la_take(&cursor, &remaining,
                                      (la_u32)limits->max_line_bytes + 1);
    ctx.path_buffer = (char *)la_take(&cursor, &remaining,
                                      (la_u32)limits->max_line_bytes + 1);
    ctx.resolve_buffer = (char *)la_take(&cursor, &remaining,
                                         (la_u32)limits->max_line_bytes + 1);
    ctx.structs = (LaStructRec *)la_take(
        &cursor, &remaining,
        ((la_u32)limits->max_structs + limits->max_unions) *
        sizeof(LaStructRec));
    ctx.fields = (LaFieldRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_fields * sizeof(LaFieldRec));
    ctx.enums = (LaEnumRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_enums * sizeof(LaEnumRec));
    ctx.enum_members = (LaEnumMemberRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_enum_members * sizeof(LaEnumMemberRec));
    ctx.overlays = (LaOverlayRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_overlays * sizeof(LaOverlayRec));
    ctx.namespaces = (LaNamespaceRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_namespaces * sizeof(LaNamespaceRec));
    ctx.exports = (LaExportRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_exports * sizeof(LaExportRec));
    ctx.constants = (LaConstantRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_constants * sizeof(LaConstantRec));
    ctx.labels = (LaLabelRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_labels * sizeof(LaLabelRec));
    ctx.namespace_stack = (la_u16 *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_nesting * sizeof(la_u16));
    ctx.locations = (LaLocationRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_locations * sizeof(LaLocationRec));
    ctx.pools = (LaPoolRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_pools * sizeof(LaPoolRec));
    ctx.procedures = (LaProcedureRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_procedures * sizeof(LaProcedureRec));
    ctx.locals = (LaLocalRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_locals * sizeof(LaLocalRec));
    ctx.bindings = (LaInvokeBindingRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_invoke_bindings * sizeof(LaInvokeBindingRec));
    ctx.inline_bodies = (char *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_inline_body_bytes + 1);
    ctx.inline_lines = (LaInlineLineRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_inline_body_lines * sizeof(LaInlineLineRec));
    ctx.inline_line_buffers = (char *)la_take(
        &cursor, &remaining,
        8u * ((la_u32)limits->max_line_bytes + 1));
    ctx.values = (LaValueRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_expression_nodes * sizeof(LaValueRec));
    ctx.operators = (LaOperatorRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_expression_nodes * sizeof(LaOperatorRec));
    ctx.frames = (LaPropertyFrame *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_nesting * sizeof(LaPropertyFrame));
    if (ctx.enums == 0 || ctx.enum_members == 0 || ctx.overlays == 0 ||
        ctx.namespaces == 0 || ctx.exports == 0 || ctx.constants == 0 ||
        ctx.labels == 0 ||
        ctx.namespace_stack == 0 || ctx.bindings == 0 || ctx.frames == 0) {
        return LA_ERR_WORKSPACE;
    }
    stats->workspace_used = required;
    ctx.names[0] = 0;
    if (input->next_line == 0) {
        if (la_load_source(&ctx) != LA_OK) return ctx.error;
    } else {
        ctx.source_length = 0;
        ctx.source[0] = 0;
    }
    if (la_first_pass(&ctx) != LA_OK) return ctx.error;
    if (la_validate_labels(&ctx) != LA_OK) return ctx.error;
    if (la_validate_exports(&ctx) != LA_OK) return ctx.error;
    if (la_resolve_type_references(&ctx) != LA_OK) return ctx.error;
    if (la_resolve_enums(&ctx) != LA_OK) return ctx.error;
    if (la_resolve_layouts(&ctx) != LA_OK) return ctx.error;
    if (la_resolve_constants(&ctx) != LA_OK) return ctx.error;
    if (la_check_assertions(&ctx) != LA_OK) return ctx.error;
    if (la_validate_procedure_data(&ctx) != LA_OK) return ctx.error;
    if (la_emit_all(&ctx) != LA_OK) return ctx.error;
    return LA_OK;
}

const char *la_diagnostic_name(LaDiagnosticCode code)
{
    static const char *names[] = {
        "ok", "workspace-capacity", "source-capacity", "token-capacity",
        "name-capacity", "structure-capacity", "field-capacity",
        "location-capacity", "expression-capacity", "nesting-capacity",
        "operation-capacity", "syntax", "duplicate-structure",
        "duplicate-field", "unknown-type", "layout-cycle", "unknown-field",
        "bad-property", "assertion-failed", "duplicate-location",
        "location-type", "unsupported-operation", "access-width",
        "displacement", "reserved-symbol", "deferred-feature",
        "native-output-deferred", "io", "module-workspace",
        "module-capacity", "module-source-capacity",
        "module-line-capacity", "module-depth", "module-not-found",
        "module-cycle", "module-duplicate", "module-syntax",
        "pool-capacity", "procedure-capacity", "parameter-capacity",
        "local-capacity", "duplicate-pool", "duplicate-procedure",
        "duplicate-parameter", "duplicate-local", "indexed-field",
        "index-location", "index-stride", "unknown-pool", "pool-strategy",
        "procedure-scope", "frame-local", "frame-stack-mutation",
        "member-role", "member-placement", "calling-convention",
        "invoke-capacity", "unknown-procedure", "invoke-binding",
        "invoke-scratch", "local-syntax-migration",
        "enum-capacity", "enum-member-capacity", "union-capacity",
        "overlay-capacity", "duplicate-enum", "duplicate-enum-member",
        "duplicate-union", "duplicate-overlay", "enum-underlying",
        "enum-empty", "enum-value", "aggregate-empty", "layout-policy",
        "layout-alignment", "field-offset", "union-offset",
        "overlay-type", "overlay-base", "overlay-alignment",
        "namespace-capacity", "export-capacity", "namespace-depth",
        "duplicate-namespace", "duplicate-export", "private-name",
        "unknown-export", "constant-capacity", "duplicate-constant",
        "unknown-constant", "label-capacity", "duplicate-label",
        "unknown-symbol", "inline-body", "inline-depth",
        "inline-capacity"
    };
    if ((la_u16)code >= (la_u16)(sizeof(names) / sizeof(names[0]))) {
        return "unknown-diagnostic";
    }
    return names[code];
}
