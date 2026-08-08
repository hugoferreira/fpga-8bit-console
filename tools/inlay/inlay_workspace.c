/* Inlay core: Bounded workspace, slices, interning, source lines,
   diagnostics and the event sink. */

#include "inlay_internal.h"

static la_u32 la_align_size(la_u32 value);
static const char *la_trim_right(const char *text, const char *end);
static la_u16 la_name_hash(const char *text, la_u16 length);
static void la_cache_name(LaContext *ctx, la_u16 handle, la_u16 hash);
static void la_apply_contract(LaContext *ctx, LaEvent *event);

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
    limits.max_method_tables = 8;
    limits.max_method_columns = 32;
    limits.max_method_rows = 64;
    limits.max_method_values = 512;
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
    total += la_align_size((la_u32)limits->max_locations *
                           sizeof(LaLocationRec));
    total += la_align_size((la_u32)limits->max_pools * sizeof(LaPoolRec));
    total += la_align_size((la_u32)limits->max_procedures *
                           sizeof(LaProcedureRec));
    total += la_align_size((la_u32)limits->max_locals * sizeof(LaLocalRec));
    total += la_align_size((la_u32)limits->max_invoke_bindings *
                           sizeof(LaInvokeBindingRec));
    total += la_align_size((la_u32)limits->max_invoke_bindings * 2u *
                           sizeof(LaInvokeItemRec));
    total += la_align_size((la_u32)limits->max_expression_nodes *
                           sizeof(LaValueRec));
    total += la_align_size((la_u32)limits->max_expression_nodes *
                           sizeof(LaOperatorRec));
    total += la_align_size((la_u32)limits->max_inline_body_bytes + 1);
    total += la_align_size((la_u32)limits->max_inline_body_lines *
                           sizeof(LaInlineLineRec));
    total += la_align_size(8u * ((la_u32)limits->max_line_bytes + 1));
    total += la_align_size((la_u32)limits->max_method_tables *
                           sizeof(LaMethodTableRec));
    total += la_align_size((la_u32)limits->max_method_columns *
                           sizeof(LaMethodColumnRec));
    total += la_align_size((la_u32)limits->max_method_rows *
                           sizeof(LaMethodRowRec));
    total += la_align_size((la_u32)limits->max_method_values *
                           sizeof(la_u16));
    total += la_align_size((la_u32)limits->max_nesting *
                           sizeof(LaPropertyFrame));
    return total;
}

void *la_take(char **cursor, la_u32 *remaining, la_u32 amount)
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

LaSlice la_slice(const char *data, la_u16 length)
{
    LaSlice slice;
    slice.data = data;
    slice.length = length;
    return slice;
}

/* A slice over a C string literal: the length is the literal's, never a
   hand-counted one. */
LaSlice la_text(const char *literal)
{
    return la_slice(literal, (la_u16)strlen(literal));
}

void la_set_span(LaContext *ctx, LaSpan *span,
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

LaDiagnosticCode la_fail(LaContext *ctx, LaDiagnosticCode code,
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

/* la_fail shorthands for the shapes the core repeats. All start the
   span at the operand's line and column 1: `la_reject` reports what was
   found, `la_expected` adds what was wanted, `la_reject_at` spans the
   found text, and `la_bound` adds the value that missed a limit. */
LaDiagnosticCode la_reject(LaContext *ctx, LaDiagnosticCode code,
                                  la_u16 line, LaSlice found)
{
    return la_fail(ctx, code, line, 1, 1, found, la_text(""), 0, 0);
}

LaDiagnosticCode la_expected(LaContext *ctx, LaDiagnosticCode code,
                                    la_u16 line, LaSlice found,
                                    LaSlice wanted)
{
    return la_fail(ctx, code, line, 1, 1, found, wanted, 0, 0);
}

LaDiagnosticCode la_reject_at(LaContext *ctx, LaDiagnosticCode code,
                                     la_u16 line, la_u16 length,
                                     LaSlice found, LaSlice wanted)
{
    return la_fail(ctx, code, line, 1, length, found, wanted, 0, 0);
}

LaDiagnosticCode la_bound(LaContext *ctx, LaDiagnosticCode code,
                                 la_u16 line, la_u16 length, LaSlice found,
                                 LaSlice wanted, la_i32 value, la_i32 limit)
{
    return la_fail(ctx, code, line, 1, length, found, wanted, value, limit);
}

int la_is_space(char value)
{
    return value == ' ' || value == '\t' || value == '\r';
}

int la_is_ident_start(char value)
{
    return (value >= 'A' && value <= 'Z') ||
           (value >= 'a' && value <= 'z') || value == '_';
}

int la_is_ident(char value)
{
    return la_is_ident_start(value) || (value >= '0' && value <= '9');
}

const char *la_trim_left(const char *text, const char *end)
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

const char *la_code_end(const char *text, const char *end)
{
    const char *cursor;
    cursor = text;
    while (cursor < end && *cursor != ';') ++cursor;
    return la_trim_right(text, cursor);
}

int la_equal_text(const char *left, la_u16 left_length,
                         const char *right)
{
    la_u16 right_length;
    right_length = (la_u16)strlen(right);
    return left_length == right_length &&
           memcmp(left, right, left_length) == 0;
}

LaSlice la_name_slice(LaContext *ctx, la_u16 handle)
{
    const char *name;
    if (handle == LA_INVALID_HANDLE) {
        return la_text("");
    }
    name = ctx->names + handle;
    return la_slice(name, (la_u16)strlen(name));
}

LaDiagnosticCode la_token(LaContext *ctx, la_u16 line, la_u16 column)
{
    if (ctx->token_count >= ctx->limits->max_tokens) {
        return la_fail(ctx, LA_ERR_TOKEN_CAPACITY, line, column, 1,
                       la_text("tokens"), la_text(""), ctx->token_count + 1,
                       ctx->limits->max_tokens);
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

la_u16 la_intern(LaContext *ctx, const char *text, la_u16 length,
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
        la_fail(ctx, LA_ERR_NAME_CAPACITY, line, column, length, la_slice(text,
                length), la_text("names"), ctx->name_length + length + 1,
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

la_u16 la_source_id_at_line(LaContext *ctx, la_u16 line)
{
    LaSpan span;
    la_set_span(ctx, &span, line, 1, 1);
    return span.source_id;
}

la_u16 la_namespace_at_line(LaContext *ctx, la_u16 line)
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

void la_reset_lines(LaContext *ctx)
{
    ctx->active_source_id = ctx->input->source_id;
    ctx->active_line = 0;
    if (ctx->input->next_line != 0) {
        if (ctx->input->reset != 0) ctx->input->reset(ctx->input->context);
    } else {
        ctx->legacy_cursor = ctx->source;
    }
}

int la_next_line(LaContext *ctx, const char **start,
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

la_u16 la_intern_qualified(LaContext *ctx,
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
        la_fail(ctx, LA_ERR_NAME_CAPACITY, line, column, length, la_slice(text,
                length), la_text("qualified name"), total + 1,
                ctx->limits->max_line_bytes);
        return LA_INVALID_HANDLE;
    }
    memcpy(ctx->line_buffer, owner.data, owner.length);
    ctx->line_buffer[owner.length] = '.';
    memcpy(ctx->line_buffer + owner.length + 1, text, length);
    ctx->line_buffer[total] = 0;
    return la_intern(ctx, ctx->line_buffer, total, line, column);
}

int la_line_keyword(const char *start, const char *end,
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

int la_deferred_keyword(const char *start, const char *end,
                               LaSlice *found)
{
    static const char *keywords[] = {
        "callconv", "invoke", "object", "interface"
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

int la_read_identifier(const char **cursor, const char *end,
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

int la_read_qualified_identifier(const char **cursor,
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

int la_take_word(const char **cursor, const char *end,
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

/* The declared contract of an operation: what its lowering reads
   through and what it leaves undefined. Events carry it so consumers
   never infer a register from a mnemonic; a parser that already filled
   the field (the branch spelling rides in `scratch`) keeps its own. */
static void la_apply_contract(LaContext *ctx, LaEvent *event)
{
    la_u16 index;
    if (event->kind != LA_EVENT_TARGET_OPERATION) return;
    for (index = 0; index < ctx->target->lowering_count; ++index) {
        const LaLoweringDesc *entry;
        entry = &ctx->target->lowerings[index];
        if (entry->operation != (la_u8)event->operation) continue;
        if (event->scratch.length == 0 && entry->scratch != 0) {
            event->scratch = la_text(entry->scratch);
        }
        if (event->clobbers.length == 0 && entry->clobbers != 0) {
            event->clobbers = la_text(entry->clobbers);
        }
        return;
    }
}

int la_write_event(LaContext *ctx, LaEvent *event)
{
    la_apply_contract(ctx, event);
    if (ctx->events == 0 || ctx->events->write == 0) return 1;
    if (!ctx->events->write(ctx->events->context, event)) {
        la_fail(ctx, LA_ERR_IO, event->span.line, event->span.column,
                event->span.length, la_text("event sink"), la_text(""), 0, 0);
        return 0;
    }
    return 1;
}

void la_init_event(LaContext *ctx, LaEvent *event, LaEventKind kind,
                          la_u16 line, la_u16 length)
{
    memset(event, 0, sizeof(*event));
    event->kind = kind;
    la_set_span(ctx, &event->span, line, 1, length);
}

/* The operation this line spells is not one the target supports; the
   span is the whole line and `why` names the missing capability. */
int la_unsupported(LaContext *ctx, const char *start, const char *end,
                          la_u16 line, LaSlice why)
{
    la_reject_at(ctx, LA_ERR_UNSUPPORTED_OPERATION, line, (la_u16)(end -
                 start), la_slice(start, (la_u16)(end - start)), why);
    return -1;
}

int la_count_operation(LaContext *ctx, la_u16 line)
{
    if (ctx->operation_count >= ctx->limits->max_operations) {
        la_bound(ctx, LA_ERR_OPERATION_CAPACITY, line, 1,
                 la_text("target operations"), la_text(""),
                 ctx->operation_count + 1, ctx->limits->max_operations);
        return 0;
    }
    ++ctx->operation_count;
    ctx->stats->operations = ctx->operation_count;
    return 1;
}

LaDiagnosticCode la_load_source(LaContext *ctx)
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
                return la_bound(ctx, LA_ERR_SOURCE_CAPACITY, 1, 1,
                                la_text("source"), la_text(""),
                                ctx->source_length + 1,
                                ctx->limits->max_source_bytes);
            }
            break;
        }
        amount = ctx->input->read(ctx->input->context,
                                  ctx->source + ctx->source_length, remaining);
        if (amount < 0) {
            return la_bound(ctx, LA_ERR_IO, 1, 1, la_text("input"),
                            la_text(""), amount, 0);
        }
        if (amount == 0) break;
        if ((la_u16)amount > remaining) {
            return la_bound(ctx, LA_ERR_IO, 1, 1, la_text("input overflow"),
                            la_text(""), amount, remaining);
        }
        ctx->source_length = (la_u16)(ctx->source_length + amount);
        remaining = (la_u16)(remaining - amount);
    }
    ctx->source[ctx->source_length] = 0;
    ctx->stats->source_bytes = ctx->source_length;
    return LA_OK;
}

/* The semantic operation vocabulary, in enum order. Descriptions fill
   these in; they cannot add to the list. */
const char *la_operation_name(la_u8 operation)
{
    static const char *names[] = {
        "load8-ptr-disp", "store8-ptr-disp", "load8-ptr-indexed",
        "store8-ptr-indexed", "address-pool-table", "proc-frame",
        "proc-naked", "proc-return", "load8-frame-local",
        "store8-frame-local", "store-ptr-frame", "load-ptr-frame",
        "invoke-save", "invoke-assign", "invoke-call",
        "load8-overlay-disp", "store8-overlay-disp", "dispatch-entry",
        "table-row", "table-hole", "table-label", "data-codeptr",
        "materialize-field-offset", "value-mov", "value-cmp",
        "load16-ptr-disp", "store16-ptr-disp", "add16-physical",
        "sub16-physical", "cmp16-physical", "inc8-ptr-disp",
        "dec8-ptr-disp", "and8-ptr-disp", "or8-ptr-disp",
        "load8-overlay-indexed", "store8-overlay-indexed",
        "address-overlay-field", "inc8-overlay-abs", "dec8-overlay-abs",
        "and8-overlay-abs", "or8-overlay-abs", "cmp8-overlay-disp",
        "store-imm-overlay-abs", "storex-overlay-disp",
        "storey-overlay-disp", "and8a-overlay-disp", "ora8a-overlay-disp",
        "loadx-overlay-disp", "loady-overlay-disp", "add8a-overlay-disp",
        "sub8a-overlay-disp", "branch-overlay-disp",
        "adc8-overlay-indexed", "sbc8-overlay-indexed", "decz8-ptr-disp",
        "tstw-ptr-disp", "tstw-location", "movw-imm", "movw-location",
        "store16-imm-ptr-disp", "invoke-tail", "invoke-field"
    };
    if (operation == 0 ||
        (la_u16)operation > (la_u16)(sizeof(names) / sizeof(names[0]))) {
        return "unknown-operation";
    }
    return names[operation - 1];
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
