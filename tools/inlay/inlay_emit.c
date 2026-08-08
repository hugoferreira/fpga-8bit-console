/* Inlay core: The emission pass: scoped-raw resolution, inline expansion, the
   operation-line dispatch chain, and la_compile. */

#include "inlay_internal.h"

static int la_symbol_named(LaContext *ctx, const char *text, la_u16 length);
static int la_resolve_bare_identifier(LaContext *ctx, la_u16 namespace_handle,
                                      const char *ident, la_u16 ident_length,
                                      la_u16 *qualified_length);
static int la_qualify_scoped_line(LaContext *ctx, const char *start,
                                  const char *end, la_u16 line,
                                  la_u16 *length);
static int la_validate_scoped_raw(LaContext *ctx, const char *start,
                                  const char *end, la_u16 line);
static LaDiagnosticCode la_emit_all(LaContext *ctx);
static int la_process_operation_line(LaContext *ctx, const char *cursor,
                                     const char *content_end,
                                     const char *line_end, la_u16 line);
static int la_capture_inline_line(LaContext *ctx, la_u16 procedure,
                                  const char *start, const char *end,
                                  la_u16 line);

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
                la_fail(ctx, LA_ERR_UNKNOWN_SYMBOL, line, (la_u16)(name_start -
                        start + 1), length, la_slice(name_start, length),
                        la_text(""), 0, 0);
                return -1;
            }
            continue;
        }
        if (symbol_source != source_id &&
            !la_name_is_exported(ctx, symbol_name)) {
            la_fail(ctx, LA_ERR_PRIVATE_NAME, line, (la_u16)(name_start - start
                    + 1), length, la_slice(name_start, length),
                    la_text("export"), 0, 0);
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
    la_u16 active_method_table;
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
                              la_text(""), LA_PROPERTY_STRUCT_SIZE,
                              ctx->enums[sid].size) ||
            !la_emit_property(ctx, ctx->enums[sid].line, owner,
                              la_text(""), LA_PROPERTY_STRUCT_ALIGN,
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
                event.aux = la_text("i8");
            } else {
                event.aux = la_text("i16");
            }
        } else {
            if (enumeration->size == 1) {
                event.aux = la_text("u8");
            } else {
                event.aux = la_text("u16");
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
                              la_text(""), LA_PROPERTY_FIELD_COUNT,
                              ctx->pools[sid].count) ||
            !la_emit_property(ctx, ctx->pools[sid].line, owner,
                              la_text(""), LA_PROPERTY_FIELD_STRIDE,
                              ctx->pools[sid].stride) ||
            !la_emit_property(ctx, ctx->pools[sid].line, owner,
                              la_text(""), LA_PROPERTY_FIELD_SIZE,
                              ctx->pools[sid].size) ||
            !la_emit_property(ctx, ctx->pools[sid].line, owner,
                              la_text(""), LA_PROPERTY_STRUCT_ALIGN,
                              ctx->pools[sid].alignment)) return ctx->error;
    }
    la_reset_lines(ctx);
    line = 0;
    in_struct = 0;
    namespace_depth = 0;
    active_procedure = LA_INVALID_HANDLE;
    active_method_table = LA_INVALID_HANDLE;
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
        if (active_method_table != LA_INVALID_HANDLE) {
            if (line ==
                ctx->method_tables[active_method_table].end_line) {
                if (!la_emit_method_table(
                        ctx, &ctx->method_tables[active_method_table],
                        line)) {
                    return ctx->error;
                }
                active_method_table = LA_INVALID_HANDLE;
            }
            /* Header, column and row lines are semantic-only. */
        } else if (la_line_keyword(trimmed, content_end, "method_table")) {
            for (sid = 0; sid < ctx->method_table_count; ++sid) {
                if (ctx->method_tables[sid].line == line &&
                    la_source_id_at_line(ctx, line) ==
                        la_source_id_at_line(
                            ctx, ctx->method_tables[sid].line)) {
                    active_method_table = sid;
                    break;
                }
            }
            if (active_method_table == LA_INVALID_HANDLE) {
                return LA_ERR_SYNTAX;
            }
        } else if (active_procedure != LA_INVALID_HANDLE &&
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
        } else if (la_line_keyword(trimmed, content_end, "pool")) {
            int emitted;
            emitted = la_emit_pool_tables(ctx, trimmed, content_end, line);
            if (emitted < 0) return ctx->error;
            /* Pool declarations themselves are semantic-only. */
        } else if (la_line_keyword(trimmed, content_end, "overlay")) {
            /* Storage declarations are semantic-only. */
        } else if (la_line_keyword(trimmed, content_end, "location") ||
                   la_line_keyword(trimmed, content_end, "static_assert")) {
            /* semantic-only */
        } else if (active_procedure != LA_INVALID_HANDLE &&
                   la_line_keyword(trimmed, content_end, "ret")) {
            if (!la_equal_text(trimmed, (la_u16)(content_end - trimmed),
                               "ret")) {
                return la_reject_at(ctx, LA_ERR_SYNTAX, line,
                                    (la_u16)(content_end - trimmed),
                                    la_text("ret"), la_slice(trimmed,
                                    (la_u16)(content_end - trimmed)));
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
                return la_bound(ctx, LA_ERR_INVOKE_CAPACITY, line, length,
                                la_text("invoke line"), la_text(""), length,
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
                    return la_reject(ctx, LA_ERR_INVOKE_BINDING, line,
                                     la_text("continued binding"));
                }
                next_code_end = la_code_end(next_start, next_end);
                next_trimmed = la_trim_left(next_start, next_code_end);
                if ((la_u32)length + 1 +
                    (la_u16)(next_code_end - next_trimmed) >
                    ctx->limits->max_line_bytes) {
                    return la_bound(ctx, LA_ERR_INVOKE_CAPACITY, line, 1,
                                    la_text("logical invoke"), la_text(""),
                                    length + 1 + (la_u16)(next_code_end -
                                    next_trimmed),
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
    la_u16 families;
    data_emitted = 0;
    /* Parsers fill only the fields they own; start from a zeroed event so
       unset fields are deterministic. */
    memset(&event, 0, sizeof(event));
    /* The operation position expects an opcode: the first token lexes
       greedily through dots and selects the parser families the target
       description claims for that spelling. A first token followed by
       '=' is an equate, not an opcode; an unclaimed spelling skips every
       typed family and falls through to raw. */
    families = 0;
    {
        const char *token_start;
        const char *token_end;
        const char *after;
        token_start = la_trim_left(cursor, content_end);
        token_end = token_start;
        if (token_end < content_end && la_is_ident_start(*token_end)) {
            while (token_end < content_end &&
                   (la_is_ident(*token_end) || *token_end == '.')) {
                ++token_end;
            }
            after = la_trim_left(token_end, content_end);
            if (!(after < content_end && *after == '=')) {
                la_u16 index;
                for (index = 0; index < ctx->target->spelling_count;
                     ++index) {
                    const char *spelling;
                    spelling = ctx->target->spellings[index].spelling;
                    if (la_equal_text(token_start,
                                      (la_u16)(token_end - token_start),
                                      spelling)) {
                        families = (la_u16)(
                            families |
                            ctx->target->spellings[index].family);
                    }
                }
            }
        }
    }
    /* Resolve bare enclosing-namespace names once, up front, so every
       typed parser (placements, mov/word operands, brackets) sees the
       same qualified spelling the scoped-raw path already resolves. */
    save_cursor = cursor;
    save_content = content_end;
    resolved_length = 0;
    resolved = la_qualify_scoped_line(
        ctx, cursor, content_end, line, &resolved_length);
    if (resolved < 0) {
        la_bound(ctx, LA_ERR_NAME_CAPACITY, line, (la_u16)(content_end -
                 cursor), la_text("resolved line"), la_text(""),
                 (la_i32)(content_end - cursor), ctx->limits->max_line_bytes);
        return -1;
    }
    if (resolved > 0) {
        cursor = ctx->resolve_buffer;
        content_end = ctx->resolve_buffer + resolved_length;
    }
    typed = la_parse_procedure_data(
        ctx, cursor, content_end, line, 1);
    if (typed > 0) data_emitted = 1;
    if (typed == 0 && (families & (LA_SPELL_OFFSET_MATERIALIZE |
                                   LA_SPELL_OFFSET_KEYWORD))) {
        typed = la_parse_offset_materialization(
            ctx, cursor, content_end, line, families, &event);
    }
    if (typed == 0 && (families & (LA_SPELL_QUALIFIED_IMMEDIATE |
                                   LA_SPELL_VALUE_COMPARE))) {
        typed = la_parse_qualified_immediate(
            ctx, cursor, content_end, line, families, &event);
    }
    if (typed == 0 && (families & LA_SPELL_OVERLAY_STORE_IMM)) {
        typed = la_parse_overlay_store_immediate(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_OVERLAY_BRANCH)) {
        typed = la_parse_overlay_branch(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_FRAME_POINTER_MOVE)) {
        typed = la_parse_frame_pointer_move(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_LOCAL_OPERATION)) {
        typed = la_parse_local_operation(ctx, cursor, content_end,
                                         line, &event);
    }
    if (typed == 0) {
        typed = la_parse_pool_address(ctx, cursor, content_end,
                                      line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_WORD_TRANSFER)) {
        typed = la_parse_typed_word_operation(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_WORD_ARITHMETIC)) {
        typed = la_parse_physical_word_arithmetic(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_BYTE_RMW)) {
        typed = la_parse_typed_byte_rmw(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_OBSERVATION)) {
        typed = la_parse_observation_operation(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_WORD_MOVE)) {
        typed = la_parse_word_move(
            ctx, cursor, content_end, line, &event);
    }
    if (typed == 0 && (families & LA_SPELL_TYPED_OPERATION)) {
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
        la_reject_at(ctx, LA_ERR_UNSUPPORTED_OPERATION, line,
                     (la_u16)(content_end - cursor), la_slice(cursor,
                     (la_u16)(content_end - cursor)),
                     la_text("raw assembly escape hatch"));
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
            la_bound(ctx, LA_ERR_NAME_CAPACITY, line, (la_u16)(line_end -
                     cursor), la_text("resolved line"), la_text(""),
                     (la_i32)(line_end - cursor), ctx->limits->max_line_bytes);
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
        la_reject_at(ctx, LA_ERR_INLINE_BODY, line, length, la_slice(start,
                     length),
                     la_text("no ret or declarations in inline body"));
        return -1;
    }
    if (la_line_keyword(start, end, "invoke") && end[-1] == ',') {
        la_reject_at(ctx, LA_ERR_INLINE_BODY, line, length, la_slice(start,
                     length), la_text("single-line invoke only"));
        return -1;
    }
    if (la_is_ident_start(*start)) {
        scan = start;
        while (scan < end && la_is_ident(*scan)) ++scan;
        if (scan < end && *scan == ':') {
            la_reject_at(ctx, LA_ERR_INLINE_BODY, line, length, la_slice(start,
                         length),
                         la_text("only .local labels in inline body"));
            return -1;
        }
    }
    {
        const char *const *transfers;
        la_u16 index;
        transfers = ctx->target->nonlocal_transfers;
        for (index = 0; transfers[index] != 0; ++index) {
            if (!la_line_keyword(start, end, transfers[index])) continue;
            scan = la_trim_left(start + strlen(transfers[index]), end);
            if (scan < end && *scan != '.') record->has_nonlocal_jmp = 1;
        }
    }
    if (ctx->inline_line_count >= ctx->limits->max_inline_body_lines) {
        la_bound(ctx, LA_ERR_INLINE_CAPACITY, line, 1,
                 la_text("inline body lines"), la_text(""),
                 ctx->inline_line_count + 1,
                 ctx->limits->max_inline_body_lines);
        return -1;
    }
    if ((la_u32)ctx->inline_body_used + length + 1 >
        (la_u32)ctx->limits->max_inline_body_bytes) {
        la_bound(ctx, LA_ERR_INLINE_CAPACITY, line, 1,
                 la_text("inline body bytes"), la_text(""),
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
int la_expand_inline_body(LaContext *ctx, la_u16 callee,
                                 la_u16 caller, la_u16 line)
{
    LaProcedureRec *record;
    char *buffer;
    la_u16 index;
    la_u16 serial;
    la_u16 saved_source_id;
    record = &ctx->procedures[callee];
    if (ctx->inline_depth >= 8) {
        la_bound(ctx, LA_ERR_INLINE_DEPTH, line, 1, la_name_slice(ctx,
                 record->name), la_text(""), ctx->inline_depth + 1, 8);
        return -1;
    }
    if (record->has_nonlocal_jmp &&
        ctx->procedures[caller].frame_size != 0) {
        la_expected(ctx, LA_ERR_INLINE_BODY, line, la_name_slice(ctx,
                    record->name), la_text("tail jmp with live caller frame"));
        return -1;
    }
    if (ctx->inline_serial >= ctx->limits->max_inline_expansions) {
        la_bound(ctx, LA_ERR_INLINE_CAPACITY, line, 1,
                 la_text("inline expansions"), la_text(""), ctx->inline_serial
                 + 1, ctx->limits->max_inline_expansions);
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
                    la_bound(ctx, LA_ERR_INLINE_CAPACITY, entry->line, 1,
                             la_text("freshened line"), la_text(""), 0,
                             ctx->limits->max_line_bytes);
                    return -1;
                }
                memcpy(out, prefix, (size_t)written);
                out += written;
                continue;
            }
            if (out >= out_end) {
                --ctx->inline_depth;
                la_bound(ctx, LA_ERR_INLINE_CAPACITY, entry->line, 1,
                         la_text("freshened line"), la_text(""), 0,
                         ctx->limits->max_line_bytes);
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
    ctx.invoke_items = (LaInvokeItemRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_invoke_bindings * 2u *
        sizeof(LaInvokeItemRec));
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
    ctx.method_tables = (LaMethodTableRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_method_tables * sizeof(LaMethodTableRec));
    ctx.method_columns = (LaMethodColumnRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_method_columns * sizeof(LaMethodColumnRec));
    ctx.method_rows = (LaMethodRowRec *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_method_rows * sizeof(LaMethodRowRec));
    ctx.method_values = (la_u16 *)la_take(
        &cursor, &remaining,
        (la_u32)limits->max_method_values * sizeof(la_u16));
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
