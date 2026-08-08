/* Inlay core: Declaration parsing and the first pass: namespaces, types,
   overlays, locations, pools, procedures and their members. */

#include "inlay_internal.h"

static LaDiagnosticCode la_parse_namespace(LaContext *ctx,
                                           const char *start,
                                           const char *end, la_u16 line);
static LaDiagnosticCode la_record_export(LaContext *ctx, la_u16 name,
                                         la_u16 line);
static LaDiagnosticCode la_parse_export(LaContext *ctx,
                                        const char *start,
                                        const char *end, la_u16 line);
static int la_parse_constant(LaContext *ctx, const char *start,
                             const char *end, la_u16 line);
static int la_parse_scoped_label(LaContext *ctx, const char *start,
                                 const char *end, la_u16 line);
static la_u16 la_checked_type_name(LaContext *ctx, la_u16 type_name,
                                   la_u16 source_id, la_u16 line);
static la_u16 la_resolve_type_name(LaContext *ctx, la_u16 type_name,
                                   la_u16 namespace_handle,
                                   la_u16 source_id, la_u16 line);
static LaDiagnosticCode la_parse_aggregate(LaContext *ctx,
                                           const char *start,
                                           const char *end, la_u16 line,
                                           LaAggregateKind kind);
static LaDiagnosticCode la_parse_field(LaContext *ctx,
                                       const char *start, const char *end,
                                       la_u16 line);
static LaDiagnosticCode la_parse_enum(LaContext *ctx,
                                      const char *start, const char *end,
                                      la_u16 line);
static LaDiagnosticCode la_parse_enum_member(LaContext *ctx,
                                             const char *start,
                                             const char *end, la_u16 line);
static LaDiagnosticCode la_parse_overlay(LaContext *ctx,
                                         const char *start,
                                         const char *end, la_u16 line);
static LaDiagnosticCode la_parse_location(LaContext *ctx,
                                          const char *start, const char *end,
                                          la_u16 line);
static la_u16 la_find_procedure_text(LaContext *ctx,
                                     const char *text, la_u16 length);
static LaDiagnosticCode la_parse_pool(LaContext *ctx,
                                      const char *start, const char *end,
                                      la_u16 line);
static LaDiagnosticCode la_parse_procedure(LaContext *ctx,
                                           const char *start,
                                           const char *end, la_u16 line);
static LaDiagnosticCode la_parse_member(LaContext *ctx,
                                        const char *start,
                                        const char *end, la_u16 line);

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
    la_u16 default_convention;
    cursor = la_trim_left(start, end) + 9;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("namespace name"));
    }
    cursor = la_trim_left(cursor, end);
    default_convention = LA_INVALID_HANDLE;
    if (la_take_word(&cursor, end, "using")) {
        const char *convention_start;
        la_u16 convention_length;
        cursor = la_trim_left(cursor, end);
        if (!la_read_identifier(&cursor, end, &convention_start,
                                &convention_length)) {
            return la_reject(ctx, LA_ERR_CONVENTION, line,
                             la_text("convention"));
        }
        for (index = 0; index < ctx->target->convention_count; ++index) {
            if (la_equal_text(convention_start, convention_length,
                              ctx->target->conventions[index].name)) {
                default_convention = index;
                break;
            }
        }
        if (default_convention == LA_INVALID_HANDLE) {
            return la_reject_at(ctx, LA_ERR_CONVENTION, line,
                                convention_length, la_slice(convention_start,
                                convention_length), la_slice(ctx->target->name,
                                (la_u16)strlen(ctx->target->name)));
        }
        cursor = la_trim_left(cursor, end);
    }
    if (cursor != end) {
        return la_reject_at(ctx, LA_ERR_SYNTAX, line, (la_u16)(end - cursor),
                            la_text("namespace NAME [using CONVENTION]"),
                            la_slice(cursor, (la_u16)(end - cursor)));
    }
    if (ctx->namespace_depth >= ctx->limits->max_nesting) {
        return la_bound(ctx, LA_ERR_NAMESPACE_DEPTH, line, name_length,
                        la_slice(name_start, name_length),
                        la_text("namespace depth"), ctx->namespace_depth + 1,
                        ctx->limits->max_nesting);
    }
    if (ctx->namespace_count >= ctx->limits->max_namespaces) {
        return la_bound(ctx, LA_ERR_NAMESPACE_CAPACITY, line, name_length,
                        la_slice(name_start, name_length),
                        la_text("namespaces"), ctx->namespace_count + 1,
                        ctx->limits->max_namespaces);
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    for (index = 0; index < ctx->namespace_count; ++index) {
        if (ctx->namespaces[index].name == name) {
            return la_reject_at(ctx, LA_ERR_DUPLICATE_NAMESPACE, line,
                                name_length, la_name_slice(ctx, name),
                                la_text(""));
        }
    }
    ctx->namespace_stack[ctx->namespace_depth++] = ctx->current_namespace;
    record = &ctx->namespaces[ctx->namespace_count];
    record->name = name;
    record->parent = ctx->current_namespace;
    record->source_id = la_source_id_at_line(ctx, line);
    record->line = line;
    record->end_line = 0;
    record->default_convention = default_convention;
    ctx->current_namespace = ctx->namespace_count++;
    ctx->stats->namespaces = ctx->namespace_count;
    if (ctx->namespace_depth > ctx->stats->nesting) {
        ctx->stats->nesting = ctx->namespace_depth;
    }
    return LA_OK;
}

static LaDiagnosticCode la_record_export(LaContext *ctx, la_u16 name,
                                         la_u16 line)
{
    la_u16 index;
    if (ctx->export_count >= ctx->limits->max_exports) {
        return la_bound(ctx, LA_ERR_EXPORT_CAPACITY, line, 1,
                        la_name_slice(ctx, name), la_text("exports"),
                        ctx->export_count + 1, ctx->limits->max_exports);
    }
    for (index = 0; index < ctx->export_count; ++index) {
        if (ctx->exports[index].name == name) {
            return la_reject(ctx, LA_ERR_DUPLICATE_EXPORT, line,
                             la_name_slice(ctx, name));
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
        return la_reject_at(ctx, LA_ERR_SYNTAX, line, 6,
                            la_text("export inside namespace"), la_text(""));
    }
    cursor = la_trim_left(start, end) + 6;
    cursor = la_trim_left(cursor, end);
    if (la_take_word(&cursor, end, "namespace")) {
        cursor = la_trim_left(cursor, end);
    }
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("export name"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor != end) {
        return la_reject_at(ctx, LA_ERR_SYNTAX, line, (la_u16)(end - cursor),
                            la_text("export NAME"), la_slice(cursor,
                            (la_u16)(end - cursor)));
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    (void)index;
    return la_record_export(ctx, name, line);
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
        la_reject(ctx, LA_ERR_SYNTAX, line, la_text("constant expression"));
        return -1;
    }
    if (ctx->constant_count >= ctx->limits->max_constants) {
        la_bound(ctx, LA_ERR_CONSTANT_CAPACITY, line, name_length,
                 la_slice(name_start, name_length), la_text("constants"),
                 ctx->constant_count + 1, ctx->limits->max_constants);
        return -1;
    }
    name = la_intern_qualified(
        ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return -1;
    for (index = 0; index < ctx->constant_count; ++index) {
        if (ctx->constants[index].name == name) {
            la_reject_at(ctx, LA_ERR_DUPLICATE_CONSTANT, line, name_length,
                         la_name_slice(ctx, name), la_text(""));
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
        la_bound(ctx, LA_ERR_LABEL_CAPACITY, line, name_length,
                 la_slice(name_start, name_length), la_text("labels"),
                 ctx->label_count + 1, ctx->limits->max_labels);
        return -1;
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return -1;
    for (index = 0; index < ctx->label_count; ++index) {
        if (ctx->labels[index].name == name) {
            la_reject_at(ctx, LA_ERR_DUPLICATE_LABEL, line, name_length,
                         la_name_slice(ctx, name), la_text(""));
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

la_u16 la_find_struct_handle(LaContext *ctx, la_u16 name)
{
    la_u16 index;
    for (index = 0; index < ctx->struct_count; ++index) {
        if (ctx->structs[index].name == name) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

la_u16 la_find_struct_text(LaContext *ctx,
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

la_u16 la_find_enum_handle(LaContext *ctx, la_u16 name)
{
    la_u16 index;
    for (index = 0; index < ctx->enum_count; ++index) {
        if (ctx->enums[index].name == name) return index;
    }
    return LA_INVALID_HANDLE;
}

la_u16 la_find_enum_text(LaContext *ctx,
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

la_u16 la_find_overlay_text(LaContext *ctx,
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

la_u16 la_find_location_text_at(LaContext *ctx,
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

la_u16 la_find_location_text(LaContext *ctx,
                                    const char *text, la_u16 length)
{
    return la_find_location_text_at(ctx, text, length, LA_INVALID_HANDLE);
}

/* Advance *base_end across dotted components while the accumulated name is not
   yet a known location or overlay, so a namespace-qualified operand base such
   as `Machine.object` is read whole. Stops at the shortest resolving prefix;
   if none resolves, *base_end is left unchanged so callers report the leading
   name. */
void la_extend_qualified_base(LaContext *ctx, const char *base_start,
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

int la_primitive_size(LaContext *ctx, la_u16 type_name,
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

int la_scalar_size(LaContext *ctx, la_u16 type_name, la_u16 *size)
{
    la_u16 enumeration;
    if (la_primitive_size(ctx, type_name, size)) return 1;
    enumeration = la_find_enum_handle(ctx, type_name);
    if (enumeration == LA_INVALID_HANDLE) return 0;
    *size = ctx->enums[enumeration].size;
    return 1;
}

int la_is_code_pointer_type(LaContext *ctx, la_u16 type_name)
{
    LaSlice type;
    type = la_name_slice(ctx, type_name);
    return la_equal_text(type.data, type.length, "codeptr");
}

la_u16 la_location_storage_units(LaContext *ctx,
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
        la_expected(ctx, LA_ERR_PRIVATE_NAME, line, la_name_slice(ctx,
                    type_name), la_text("export"));
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

LaDiagnosticCode la_resolve_type_references(LaContext *ctx)
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
        return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start + 1),
                       1, la_text("aggregate name"), la_text(""), 0, 0);
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
                return la_fail(ctx, LA_ERR_LAYOUT_POLICY, line, (la_u16)(cursor
                               - start + 1), (la_u16)(end - cursor),
                               la_slice(cursor, (la_u16)(end - cursor)),
                               la_text("aligned(power-of-two)"), 0, 0);
            }
            while (number < end - 1 && *number >= '0' && *number <= '9') {
                parsed = parsed * 10 + (la_u32)(*number++ - '0');
            }
            if (number != end - 1 || parsed == 0 || parsed > 255 ||
                (parsed & (parsed - 1)) != 0 ||
                parsed > ctx->target->max_aggregate_alignment) {
                return la_fail(ctx, LA_ERR_LAYOUT_ALIGNMENT, line,
                               (la_u16)(cursor - start + 1), (la_u16)(end -
                               cursor), la_slice(cursor, (la_u16)(end -
                               cursor)), la_text("target maximum"),
                               (la_i32)parsed,
                               ctx->target->max_aggregate_alignment);
            }
            policy = LA_LAYOUT_ALIGNED;
            alignment = (la_u16)parsed;
        } else {
            return la_fail(ctx, LA_ERR_LAYOUT_POLICY, line, (la_u16)(cursor -
                           start + 1), (la_u16)(end - cursor), la_slice(cursor,
                           (la_u16)(end - cursor)),
                           la_text("packed or aligned(N)"), 0, 0);
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
                       la_name_slice(ctx, name), la_text(""), 0, 0);
    }
    if ((kind == LA_AGGREGATE_STRUCT &&
         ctx->plain_struct_count >= ctx->limits->max_structs) ||
        (kind == LA_AGGREGATE_UNION &&
         ctx->union_count >= ctx->limits->max_unions)) {
        if (kind == LA_AGGREGATE_STRUCT) {
            return la_bound(ctx, LA_ERR_STRUCT_CAPACITY, line, name_length,
                            la_name_slice(ctx, name), la_text("structures"),
                            ctx->plain_struct_count + 1,
                            ctx->limits->max_structs);
        }
        return la_bound(ctx, LA_ERR_UNION_CAPACITY, line, name_length,
                        la_name_slice(ctx, name), la_text("unions"),
                        ctx->union_count + 1, ctx->limits->max_unions);
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
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("field name"));
    }
    while (cursor < end && la_is_ident(*cursor)) {
        ++cursor;
    }
    name_length = (la_u16)(cursor - name_start);
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor != ':') {
        return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start + 1),
                       1, la_text(":"), la_text(""), 0, 0);
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
        return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start + 1),
                       1, la_text("field type"), la_text(""), 0, 0);
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
            return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start +
                           1), 1, la_text("positive array count"), la_text(""),
                           0, 0);
        }
        while (cursor < end && *cursor >= '0' && *cursor <= '9') {
            parsed = parsed * 10 + (la_u32)(*cursor - '0');
            ++cursor;
        }
        if (cursor >= end || *cursor != ']' || parsed == 0 || parsed > 65535) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start +
                           1), 1, la_text("valid array count"), la_text(""),
                           (la_i32)parsed, 65535);
        }
        count = (la_u16)parsed;
        ++cursor;
        cursor = la_trim_left(cursor, end);
    }
    if (la_take_word(&cursor, end, "at")) {
        if (ctx->structs[ctx->current_struct].kind == LA_AGGREGATE_UNION) {
            return la_fail(ctx, LA_ERR_UNION_OFFSET, line, (la_u16)(cursor -
                           start + 1), 2, la_slice(name_start, name_length),
                           la_name_slice( ctx,
                           ctx->structs[ctx->current_struct].name), 0, 0);
        }
        offset_start = la_trim_left(cursor, end);
        if (offset_start == end) {
            return la_fail(ctx, LA_ERR_FIELD_OFFSET, line, (la_u16)(cursor -
                           start + 1), 1, la_text("constant expression"),
                           la_text(""), 0, 0);
        }
        has_explicit_offset = 1;
        cursor = end;
    }
    if (cursor != end) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start + 1),
                       (la_u16)(end - cursor), la_text("end of field"),
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
                           la_name_slice(ctx, name), la_name_slice(ctx,
                           ctx->structs[ctx->current_struct].name), 0, 0);
        }
    }
    if (ctx->field_count >= ctx->limits->max_fields) {
        return la_bound(ctx, LA_ERR_FIELD_CAPACITY, line, name_length,
                        la_name_slice(ctx, name), la_text("fields"),
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
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("enum name"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':' ||
        !la_read_qualified_identifier(
            &cursor, end, &type_start, &type_length) ||
        la_trim_left(cursor, end) != end) {
        return la_reject(ctx, LA_ERR_ENUM_UNDERLYING, line,
                         la_text("u8, i8, u16, or i16"));
    }
    if (!(la_equal_text(type_start, type_length, "u8") ||
          la_equal_text(type_start, type_length, "i8") ||
          la_equal_text(type_start, type_length, "u16") ||
          la_equal_text(type_start, type_length, "i16"))) {
        return la_reject_at(ctx, LA_ERR_ENUM_UNDERLYING, line, type_length,
                            la_slice(type_start, type_length),
                            la_text("u8, i8, u16, or i16"));
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    if (la_find_enum_handle(ctx, name) != LA_INVALID_HANDLE ||
        la_find_struct_handle(ctx, name) != LA_INVALID_HANDLE) {
        return la_reject_at(ctx, LA_ERR_DUPLICATE_ENUM, line, name_length,
                            la_name_slice(ctx, name), la_text(""));
    }
    if (ctx->enum_count >= ctx->limits->max_enums) {
        return la_bound(ctx, LA_ERR_ENUM_CAPACITY, line, name_length,
                        la_text("enums"), la_text(""), ctx->enum_count + 1,
                        ctx->limits->max_enums);
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
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("enum member"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != '=') {
        return la_reject(ctx, LA_ERR_ENUM_VALUE, line,
                         la_text("explicit enum value"));
    }
    value_start = la_trim_left(cursor, end);
    if (value_start == end) {
        return la_reject(ctx, LA_ERR_ENUM_VALUE, line,
                         la_text("enum value expression"));
    }
    owner = &ctx->enums[ctx->current_enum];
    name = la_intern(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    for (index = owner->first_member;
         index < owner->first_member + owner->member_count; ++index) {
        if (ctx->enum_members[index].name == name) {
            return la_reject_at(ctx, LA_ERR_DUPLICATE_ENUM_MEMBER, line,
                                name_length, la_name_slice(ctx, name),
                                la_name_slice(ctx, owner->name));
        }
    }
    if (ctx->enum_member_count >= ctx->limits->max_enum_members) {
        return la_bound(ctx, LA_ERR_ENUM_MEMBER_CAPACITY, line, name_length,
                        la_text("enum members"), la_text(""),
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
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("overlay name"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':' ||
        !la_read_identifier(&cursor, end, &type_start, &type_length) ||
        !la_take_word(&cursor, end, "at")) {
        return la_reject(ctx, LA_ERR_SYNTAX, line,
                         la_text("overlay NAME : TYPE at BASE"));
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
            return la_bound(ctx, LA_ERR_OVERLAY_BASE, line, (la_u16)(cursor -
                            base_start), la_slice(base_start, (la_u16)(cursor -
                            base_start)), la_text("16-bit fixed address"),
                            (la_i32)numeric, 65535);
        }
    } else if (!la_read_identifier(&cursor, end, &base_start, &base_length)) {
        return la_reject(ctx, LA_ERR_OVERLAY_BASE, line,
                         la_text("target symbol"));
    }
    cursor = la_trim_left(cursor, end);
    volatile_access = 0;
    if (la_take_word(&cursor, end, "volatile")) {
        volatile_access = 1;
        cursor = la_trim_left(cursor, end);
    }
    if (cursor != end) {
        return la_reject_at(ctx, LA_ERR_OVERLAY_BASE, line, (la_u16)(end -
                            cursor), la_slice(cursor, (la_u16)(end - cursor)),
                            la_text("single base"));
    }
    if (is_numeric) base_length = (la_u16)(base_end - base_start);
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    if (la_find_overlay_text(
            ctx, ctx->names + name,
            (la_u16)strlen(ctx->names + name)) != LA_INVALID_HANDLE) {
        return la_reject_at(ctx, LA_ERR_DUPLICATE_OVERLAY, line, name_length,
                            la_name_slice(ctx, name), la_text(""));
    }
    if (ctx->overlay_count >= ctx->limits->max_overlays) {
        return la_bound(ctx, LA_ERR_OVERLAY_CAPACITY, line, name_length,
                        la_text("overlays"), la_text(""), ctx->overlay_count +
                        1, ctx->limits->max_overlays);
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
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("location name"));
    }
    while (cursor < end && la_is_ident(*cursor)) {
        ++cursor;
    }
    name_length = (la_u16)(cursor - name_start);
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor != ':') {
        return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start + 1),
                       1, la_text(":"), la_text(""), 0, 0);
    }
    ++cursor;
    cursor = la_trim_left(cursor, end);
    is_pointer = la_take_word(&cursor, end, "ptr");
    if (!la_read_qualified_identifier(&cursor, end, &type_start,
                                      &type_length)) {
        return la_fail(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(cursor - start
                       + 1), 1, la_text("scalar, ptr T, or codeptr"),
                       la_text(""), 0, 0);
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
        return la_fail(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(type_start -
                       start + 1), type_length,
                       la_text("scalar, ptr T, or codeptr"),
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
            return la_bound(ctx, LA_ERR_LOCATION_TYPE, line, physical_length,
                            la_text("16-bit fixed address"),
                            la_slice(physical_start, physical_length),
                            (la_i32)numeric, 65535);
        }
        has_fixed_address = 1;
    }
    cursor = la_trim_left(cursor, end);
    if (cursor != end) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, (la_u16)(cursor - start + 1),
                       (la_u16)(end - cursor), la_text("end of location"),
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
        return la_reject_at(ctx, LA_ERR_DUPLICATE_LOCATION, line, name_length,
                            la_name_slice(ctx, name), la_text(""));
    }
    if (ctx->location_count >= ctx->limits->max_locations) {
        return la_bound(ctx, LA_ERR_LOCATION_CAPACITY, line, name_length,
                        la_name_slice(ctx, name), la_text("locations"),
                        ctx->location_count + 1, ctx->limits->max_locations);
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

la_u16 la_find_pool_text(LaContext *ctx,
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

int la_name_is_exported(LaContext *ctx, la_u16 name)
{
    la_u16 index;
    for (index = 0; index < ctx->export_count; ++index) {
        if (ctx->exports[index].name == name) return 1;
    }
    return 0;
}

la_u16 la_find_procedure_scoped(LaContext *ctx,
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

la_u16 la_find_local_text(LaContext *ctx, la_u16 procedure,
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
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("pool name"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text(":"));
    }
    if (!la_read_qualified_identifier(
            &cursor, end, &type_start, &type_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line,
                         la_text("pool element type"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != '[') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("[count]"));
    }
    count = 0;
    while (cursor < end && *cursor >= '0' && *cursor <= '9') {
        count = count * 10 + (la_u32)(*cursor++ - '0');
    }
    if (count == 0 || count > 65535 || cursor >= end || *cursor++ != ']') {
        return la_bound(ctx, LA_ERR_SYNTAX, line, 1,
                        la_text("positive pool count"), la_text(""),
                        (la_i32)count, 65535);
    }
    if (!la_take_word(&cursor, end, "at") ||
        !la_read_identifier(&cursor, end, &base_start, &base_length) ||
        !la_take_word(&cursor, end, "table") ||
        !la_read_identifier(&cursor, end, &low_start, &low_length)) {
        return la_reject(ctx, LA_ERR_POOL_STRATEGY, line,
                         la_text("at BASE table LOW, HIGH"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ',' ||
        !la_read_identifier(&cursor, end, &high_start, &high_length) ||
        la_trim_left(cursor, end) != end) {
        return la_reject(ctx, LA_ERR_POOL_STRATEGY, line,
                         la_text("at BASE table LOW, HIGH"));
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
            return la_reject_at(ctx, LA_ERR_DUPLICATE_POOL, line, name_length,
                                la_name_slice(ctx, qualified_name),
                                la_text(""));
        }
    }
    if (ctx->pool_count >= ctx->limits->max_pools) {
        return la_bound(ctx, LA_ERR_POOL_CAPACITY, line, name_length,
                        la_text("pools"), la_text(""), ctx->pool_count + 1,
                        ctx->limits->max_pools);
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
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("procedure name"));
    }
    while (cursor < end && *cursor == '.') {
        const char *component_start;
        la_u16 component_length;
        ++cursor;
        if (!la_read_identifier(&cursor, end, &component_start,
                                &component_length)) {
            return la_reject(ctx, LA_ERR_SYNTAX, line,
                             la_text("qualified procedure name"));
        }
        name_length = (la_u16)(cursor - name_start);
    }
    name = la_intern_qualified(ctx, name_start, name_length, line, 1);
    if (name == LA_INVALID_HANDLE) return ctx->error;
    for (index = 0; index < ctx->procedure_count; ++index) {
        LaSlice existing;
        existing = la_name_slice(ctx, ctx->procedures[index].name);
        if (ctx->procedures[index].name == name) {
            return la_reject_at(ctx, LA_ERR_DUPLICATE_PROCEDURE, line,
                                name_length, existing, la_text(""));
        }
    }
    if (ctx->procedure_count >= ctx->limits->max_procedures) {
        return la_bound(ctx, LA_ERR_PROCEDURE_CAPACITY, line, name_length,
                        la_text("procedures"), la_text(""),
                        ctx->procedure_count + 1, ctx->limits->max_procedures);
    }
    procedure = &ctx->procedures[ctx->procedure_count];
    memset(procedure, 0, sizeof(*procedure));
    procedure->name = name;
    procedure->namespace_handle = ctx->current_namespace;
    procedure->source_id = la_source_id_at_line(ctx, line);
    if (procedure->name == LA_INVALID_HANDLE) return ctx->error;
    procedure->convention = LA_INVALID_HANDLE;
    cursor = la_trim_left(cursor, end);
    if (la_take_word(&cursor, end, "export")) {
        if (la_record_export(ctx, name, line) != LA_OK) return ctx->error;
        cursor = la_trim_left(cursor, end);
    }
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
            return la_reject(ctx, LA_ERR_CONVENTION, line,
                             la_text("convention"));
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
            return la_reject_at(ctx, LA_ERR_CONVENTION, line,
                                convention_length, la_slice(convention_start,
                                convention_length), la_slice(ctx->target->name,
                                (la_u16)strlen(ctx->target->name)));
        }
        procedure->convention = convention_index;
    }
    if (procedure->convention == LA_INVALID_HANDLE) {
        la_u16 scope;
        scope = ctx->current_namespace;
        while (scope != LA_INVALID_HANDLE) {
            if (ctx->namespaces[scope].default_convention !=
                LA_INVALID_HANDLE) {
                procedure->convention =
                    ctx->namespaces[scope].default_convention;
                break;
            }
            scope = ctx->namespaces[scope].parent;
        }
    }
    cursor = la_trim_left(cursor, end);
    if (procedure->is_inline && cursor != end) {
        return la_reject_at(ctx, LA_ERR_INLINE_BODY, line, (la_u16)(end -
                            cursor), la_text("inline takes no frame mode"),
                            la_slice(cursor, (la_u16)(end - cursor)));
    }
    if (cursor != end) {
        if (la_equal_text(cursor, (la_u16)(end - cursor), "naked")) {
            procedure->naked = 1;
        } else if (!la_equal_text(cursor, (la_u16)(end - cursor), "frame")) {
            return la_reject_at(ctx, LA_ERR_SYNTAX, line, (la_u16)(end -
                                cursor),
                                la_text("[using CONVENTION] [frame|naked]"),
                                la_slice(cursor, (la_u16)(end - cursor)));
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
        return la_reject_at(ctx, LA_ERR_LOCAL_SYNTAX_MIGRATION, line, 5,
                            la_text("local"), la_text("NAME : TYPE in frame"));
    }
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("parameter"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text(":"));
    }
    cursor = la_trim_left(cursor, end);
    is_pointer = la_take_word(&cursor, end, "ptr");
    if (!la_read_qualified_identifier(
            &cursor, end, &type_start, &type_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("member type"));
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
                return la_reject(ctx, LA_ERR_MEMBER_ROLE, line,
                                 la_text("return [in PHYSICAL]"));
            }
            explicit_placement = 1;
            if (la_equal_text(physical_start, physical_length, "frame")) {
                return la_reject_at(ctx, LA_ERR_MEMBER_ROLE, line,
                                    physical_length,
                                    la_text("return cannot use frame"),
                                    la_text("NAME : TYPE in frame"));
            }
        }
    } else if (la_take_word(&cursor, end, "in")) {
        if (!la_read_qualified_identifier(&cursor, end, &physical_start,
                                          &physical_length) ||
            la_trim_left(cursor, end) != end) {
            return la_reject(ctx, LA_ERR_MEMBER_PLACEMENT, line,
                             la_text("in PHYSICAL"));
        }
        if (la_equal_text(physical_start, physical_length, "frame")) {
            is_local = 1;
        } else {
            explicit_placement = 1;
        }
    } else if (cursor != end) {
        return la_reject_at(ctx, LA_ERR_MEMBER_ROLE, line, (la_u16)(end -
                            cursor), la_text("in PLACE or return [in PLACE]"),
                            la_slice(cursor, (la_u16)(end - cursor)));
    }
    if (is_local) {
        LaLocalRec *local;
        if (procedure->is_inline) {
            return la_reject_at(ctx, LA_ERR_INLINE_BODY, line, name_length,
                                la_slice(name_start, name_length),
                                la_text("inline has no frame"));
        }
        if (procedure->naked) {
            return la_reject_at(ctx, LA_ERR_FRAME_LOCAL, line, name_length,
                                la_slice(name_start, name_length),
                                la_text("naked"));
        }
        if (la_find_local_text(ctx, ctx->current_procedure,
                               name_start, name_length) != LA_INVALID_HANDLE) {
            return la_reject_at(ctx, LA_ERR_DUPLICATE_LOCAL, line, name_length,
                                la_slice(name_start, name_length),
                                la_text(""));
        }
        for (index = 0; index < ctx->location_count; ++index) {
            LaSlice other;
            if (ctx->locations[index].procedure != ctx->current_procedure)
                continue;
            other = la_name_slice(ctx, ctx->locations[index].name);
            if (other.length == name_length &&
                memcmp(other.data, name_start, name_length) == 0) {
                return la_reject_at(ctx, LA_ERR_DUPLICATE_LOCAL, line,
                                    name_length, other, la_text(""));
            }
        }
        if (ctx->local_count >= ctx->limits->max_locals) {
            return la_bound(ctx, LA_ERR_LOCAL_CAPACITY, line, name_length,
                            la_text("locals"), la_text(""), ctx->local_count +
                            1, ctx->limits->max_locals);
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
        return la_reject_at(ctx, LA_ERR_DUPLICATE_PARAMETER, line, name_length,
                            la_slice(name_start, name_length),
                            la_text("procedure member"));
    }
    for (index = 0; index < ctx->location_count; ++index) {
        LaSlice name;
        if (ctx->locations[index].procedure != ctx->current_procedure)
            continue;
        name = la_name_slice(ctx, ctx->locations[index].name);
        if (name.length == name_length &&
            memcmp(name.data, name_start, name_length) == 0) {
            return la_reject_at(ctx, LA_ERR_DUPLICATE_PARAMETER, line,
                                name_length, name, la_text(""));
        }
    }
    if (ctx->parameter_count >= ctx->limits->max_parameters) {
        return la_bound(ctx, LA_ERR_PARAMETER_CAPACITY, line, name_length,
                        la_text("parameters"), la_text(""),
                        ctx->parameter_count + 1, ctx->limits->max_parameters);
    }
    if (ctx->location_count >= ctx->limits->max_locations) {
        return la_bound(ctx, LA_ERR_LOCATION_CAPACITY, line, name_length,
                        la_text("locations"), la_text(""), ctx->location_count
                        + 1, ctx->limits->max_locations);
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

LaDiagnosticCode la_first_pass(LaContext *ctx)
{
    const char *cursor;
    la_u16 line;
    int in_struct;
    int in_enum;
    int in_procedure;
    int in_body;
    int in_method_table;
    la_reset_lines(ctx);
    line = 0;
    in_struct = 0;
    in_enum = 0;
    in_procedure = 0;
    in_body = 0;
    in_method_table = 0;
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
            if (in_method_table) {
                const char *shape;
                shape = trimmed;
                while (shape < content_end && la_is_ident(*shape)) ++shape;
                shape = la_trim_left(shape, content_end);
                if (la_line_keyword(trimmed, content_end, "end")) {
                    ctx->method_tables[
                        ctx->method_table_count - 1].end_line = line;
                    in_method_table = 0;
                } else if (shape < content_end && *shape == ':') {
                    if (la_parse_method_column(
                            ctx, trimmed, content_end, line) != LA_OK) {
                        return ctx->error;
                    }
                } else if (shape < content_end && *shape == '=') {
                    if (la_parse_method_row(
                            ctx, trimmed, content_end, line) != LA_OK) {
                        return ctx->error;
                    }
                } else {
                    return la_reject_at(ctx, LA_ERR_SYNTAX, line,
                                        (la_u16)(content_end - trimmed),
                                        la_slice("NAME : u8|code, "
                                        "MEMBER = ... or end", 34),
                                        la_slice(trimmed, (la_u16)(content_end
                                        - trimmed)));
                }
            } else if (in_struct) {
                if (la_line_keyword(trimmed, content_end, "end")) {
                    if (ctx->structs[ctx->current_struct].kind ==
                            LA_AGGREGATE_UNION &&
                        ctx->structs[ctx->current_struct].field_count == 0) {
                        return la_bound(ctx, LA_ERR_AGGREGATE_EMPTY,
                            ctx->structs[ctx->current_struct].line, 1,
                            la_name_slice( ctx,
                            ctx->structs[ctx->current_struct].name),
                            la_text("union"), 0, 1);
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
                        return la_bound(ctx, LA_ERR_ENUM_EMPTY,
                                        ctx->enums[ctx->current_enum].line, 1,
                                        la_name_slice( ctx,
                                        ctx->enums[ctx->current_enum].name),
                                        la_text(""), 0, 1);
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
                            return la_reject(ctx, LA_ERR_SYNTAX, line,
                                             la_text("begin"));
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
                        return la_reject(ctx, LA_ERR_SYNTAX, line,
                                         la_text("end"));
                    }
                    procedure->end_line = line;
                    in_procedure = 0;
                    in_body = 0;
                    ctx->current_procedure = LA_INVALID_HANDLE;
                } else if (procedure->local_count != 0) {
                    const char *const *mutators;
                    la_u16 mutator;
                    mutators = ctx->target->stack_mutators;
                    for (mutator = 0; mutators[mutator] != 0; ++mutator) {
                        if (la_line_keyword(trimmed, content_end,
                                            mutators[mutator])) {
                            return la_reject_at(ctx,
                                LA_ERR_FRAME_STACK_MUTATION, line,
                                (la_u16)strlen(mutators[mutator]),
                                la_slice(mutators[mutator],
                                (la_u16)strlen(mutators[mutator])),
                                la_name_slice(ctx, procedure->name));
                        }
                    }
                    if (la_line_keyword(trimmed, content_end,
                                        ctx->target->raw_return)) {
                        return la_reject_at(ctx, LA_ERR_FRAME_STACK_MUTATION,
                            line, (la_u16)strlen(ctx->target->raw_return),
                            la_slice(ctx->target->raw_return, (la_u16)strlen(
                            ctx->target->raw_return)), la_text("use ret"));
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
                    return la_reject_at(ctx, LA_ERR_SYNTAX, line,
                                        (la_u16)(content_end - trimmed),
                                        la_text("namespace end"),
                                        la_slice(trimmed, (la_u16)(content_end
                                        - trimmed)));
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
            } else if (la_line_keyword(trimmed, content_end,
                                       "method_table")) {
                if (la_parse_method_table(
                        ctx, trimmed, content_end, line) != LA_OK) {
                    return ctx->error;
                }
                in_method_table = 1;
            } else if (la_line_keyword(trimmed, content_end, "overlay")) {
                if (la_parse_overlay(ctx, cursor, content_end, line) !=
                    LA_OK) return ctx->error;
            } else if (la_line_keyword(trimmed, content_end, "pool")) {
                const char *pool_cursor;
                pool_cursor = la_trim_left(trimmed, content_end) + 4;
                pool_cursor = la_trim_left(pool_cursor, content_end);
                if (!la_take_word(&pool_cursor, content_end, "tables")) {
                    if (la_parse_pool(ctx, cursor, content_end, line) !=
                        LA_OK) {
                        return ctx->error;
                    }
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
                                   deferred.length, deferred, la_text(""), 0,
                                   0);
                }
            } else if (la_deferred_keyword(trimmed, content_end, &deferred)) {
                return la_fail(ctx, LA_ERR_DEFERRED_FEATURE, line,
                               (la_u16)(trimmed - cursor + 1), deferred.length,
                               deferred, la_text(""), 0, 0);
            } else if ((la_u16)(content_end - trimmed) >= 5 &&
                       memcmp(trimmed, "__la_", 5) == 0) {
                return la_fail(ctx, LA_ERR_RESERVED_SYMBOL, line,
                               (la_u16)(trimmed - cursor + 1), 5,
                               la_slice(trimmed, 5), la_text("__la_"), 0, 0);
            }
        }
    }
    if (in_struct || in_enum || in_procedure || in_method_table ||
        ctx->namespace_depth != 0) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("end"));
    }
    return LA_OK;
}

LaDiagnosticCode la_validate_exports(LaContext *ctx)
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
            return la_reject(ctx, LA_ERR_UNKNOWN_EXPORT,
                             ctx->exports[export_index].line,
                             la_name_slice(ctx, name));
        }
    }
    return LA_OK;
}

LaDiagnosticCode la_validate_labels(LaContext *ctx)
{
    la_u16 label_index;
    for (label_index = 0; label_index < ctx->label_count; ++label_index) {
        la_u16 index;
        LaLabelRec *label;
        label = &ctx->labels[label_index];
        for (index = 0; index < ctx->constant_count; ++index) {
            if (ctx->constants[index].name == label->name) {
                return la_expected(ctx, LA_ERR_DUPLICATE_LABEL, label->line,
                                   la_name_slice(ctx, label->name),
                                   la_text("constant"));
            }
        }
        for (index = 0; index < ctx->procedure_count; ++index) {
            if (ctx->procedures[index].name == label->name) {
                return la_expected(ctx, LA_ERR_DUPLICATE_LABEL, label->line,
                                   la_name_slice(ctx, label->name),
                                   la_text("procedure"));
            }
        }
    }
    return LA_OK;
}

la_u16 la_procedure_at_line(LaContext *ctx, la_u16 line)
{
    la_u16 index;
    for (index = 0; index < ctx->procedure_count; ++index) {
        if (ctx->procedures[index].source_id == ctx->active_source_id &&
            line > ctx->procedures[index].begin_line &&
            line < ctx->procedures[index].end_line) return index;
    }
    return LA_INVALID_HANDLE;
}
