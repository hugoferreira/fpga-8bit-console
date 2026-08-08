/* Inlay core: Invocation: binding parse, scratch reservation, and the
   dependency scheduler that orders marshalling. */

#include "inlay_internal.h"

static int la_emit_invoke_operation(LaContext *ctx, la_u16 line,
                                    LaTargetOperationKind operation,
                                    LaSlice owner, LaSlice path,
                                    LaSlice base, LaSlice aux, LaSlice aux2,
                                    la_u16 value, la_u16 stride,
                                    la_u16 count);
static la_u16 la_find_invoke_member(LaContext *ctx,
                                    const LaProcedureRec *procedure,
                                    const char *name, la_u16 length);
static int la_invoke_has_binding(LaContext *ctx, la_u16 count,
                                 la_u16 member);
static int la_parse_invoke_source(LaContext *ctx, const char **cursor,
                                  const char *end, la_u16 line,
                                  la_u16 caller, la_u16 member_index,
                                  LaInvokeBindingRec *binding);
static int la_parse_invoke_binding(LaContext *ctx, const char **cursor,
                                   const char *end, la_u16 line,
                                   la_u16 caller,
                                   const LaProcedureRec *procedure,
                                   la_u16 *binding_count);
static int la_validate_invoke_inputs(LaContext *ctx,
                                     const LaProcedureRec *procedure,
                                     la_u16 binding_count, la_u16 line);
static int la_slices_equal(LaSlice left, LaSlice right);
static int la_reserve_invoke_scratch(LaContext *ctx, la_u16 binding_count,
                                     la_u16 line, LaSlice scratch_name,
                                     la_u16 *scratch);
static int la_emit_invoke_save_item(LaContext *ctx,
                                    const LaProcedureRec *procedure,
                                    la_u16 bind, la_u16 line,
                                    LaSlice scratch_name);
static int la_emit_invoke_field_item(LaContext *ctx,
                                     const LaProcedureRec *procedure,
                                     la_u16 bind, la_u16 line,
                                     LaSlice scratch_name);
static int la_emit_invoke_regfield_item(LaContext *ctx,
                                        const LaProcedureRec *procedure,
                                        la_u16 bind, la_u16 line);
static int la_emit_invoke_assign_item(LaContext *ctx,
                                      const LaProcedureRec *procedure,
                                      la_u16 bind, la_u16 line,
                                      LaSlice scratch_name);
static int la_invoke_item_must_precede(LaContext *ctx, int accumulator,
                                       const LaInvokeItemRec *first,
                                       const LaInvokeItemRec *second);
static int la_emit_invoke_scheduled(LaContext *ctx,
                                    const LaProcedureRec *procedure,
                                    la_u16 binding_count, la_u16 line,
                                    LaSlice scratch_name);

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
            la_bound(ctx, LA_ERR_INVOKE_BINDING, line, 1, la_text("immediate"),
                     la_name_slice( ctx,
                     ctx->locations[member_index].type_name), value, 0);
            return 0;
        }
        if (member_width == 2) {
            if (ctx->expression_family == LA_EXPR_BITWISE) {
                value = (la_i32)((la_u32)value & 0xffff);
            }
            if (value < -32768 || value > 65535) {
                la_bound(ctx, LA_ERR_INVOKE_BINDING, line, 1,
                         la_text("16-bit immediate"), la_name_slice( ctx,
                         ctx->locations[member_index].type_name), value,
                         65535);
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
            la_bound(ctx, LA_ERR_INVOKE_BINDING, line, 1,
                     la_text("byte immediate"), la_name_slice( ctx,
                     ctx->locations[member_index].type_name), value, 255);
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
            la_reject(ctx, LA_ERR_INVOKE_BINDING, line, la_text("]"));
            return 0;
        }
        base_start = la_trim_left(bracket + 1, close);
        base_end = base_start;
        while (base_end < close && la_is_ident(*base_end)) ++base_end;
        la_extend_qualified_base(ctx, base_start, &base_end, close, caller);
        field_cursor = la_trim_left(base_end, close);
        if (base_end == base_start || field_cursor >= close ||
            (*field_cursor != '.' && *field_cursor != '+')) {
            la_reject(ctx, LA_ERR_INVOKE_BINDING, line,
                      la_text("[pointer.field]"));
            return 0;
        }
        pointer_location = la_find_location_text_at(
            ctx, base_start, (la_u16)(base_end - base_start), caller);
        if (pointer_location == LA_INVALID_HANDLE ||
            !ctx->locations[pointer_location].is_pointer) {
            la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(base_end -
                         base_start), la_slice(base_start, (la_u16)(base_end -
                         base_start)), la_text("typed pointer"));
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
        field_size = la_field_leaf_size(ctx, field_index);
        if (ctx->fields[field_index].count != 1 ||
            ctx->locations[member_index].is_pointer ||
            la_is_code_pointer_type(
                ctx, ctx->locations[member_index].type_name) ||
            field_size != member_width) {
            la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(close -
                     path_start), la_name_slice(ctx,
                     ctx->fields[field_index].name), la_name_slice( ctx,
                     ctx->locations[member_index].type_name), field_size,
                     member_width);
            return 0;
        }
        if ((la_u32)field_offset + (field_size - 1) >
            ctx->target->max_displacement) {
            la_bound(ctx, LA_ERR_DISPLACEMENT, line, (la_u16)(close -
                     path_start), la_slice(path_start, (la_u16)(close -
                     path_start)), la_text(""), (la_i32)((la_u32)field_offset +
                     (field_size - 1)), ctx->target->max_displacement);
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
                    la_reject(ctx, LA_ERR_INVOKE_BINDING, line,
                              la_text("byte field addend"));
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
                    la_bound(ctx, LA_ERR_INVOKE_BINDING, line, 1,
                             la_text("byte field addend"), la_text(""), addend,
                             255);
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
        la_reject(ctx, LA_ERR_INVOKE_BINDING, line, la_text("value"));
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
            la_reject_at(ctx, LA_ERR_INVOKE_BINDING, line, source_length,
                         la_slice(source_start, source_length), la_name_slice(
                         ctx, ctx->locations[member_index].type_name));
            return 0;
        }
        binding->source = ctx->locations[source_location].physical;
    } else {
        LaSlice source;
        source = la_slice(source_start, source_length);
        if (ctx->locations[member_index].is_pointer ||
            la_is_code_pointer_type(
                ctx, ctx->locations[member_index].type_name) ||
            !la_slice_is_register(ctx, source)) {
            la_reject_at(ctx, LA_ERR_INVOKE_BINDING, line, source_length,
                         source, la_text("typed source or register"));
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
        la_reject(ctx, LA_ERR_INVOKE_BINDING, line, la_text(","));
        return 0;
    }
    if (!la_read_identifier(cursor, end, &name_start, &name_length)) {
        la_reject(ctx, LA_ERR_INVOKE_BINDING, line, la_text("binding name"));
        return 0;
    }
    *cursor = la_trim_left(*cursor, end);
    if (*cursor >= end || *(*cursor)++ != '=') {
        la_reject(ctx, LA_ERR_INVOKE_BINDING, line, la_text("="));
        return 0;
    }
    *cursor = la_trim_left(*cursor, end);
    if (*binding_count >= ctx->limits->max_invoke_bindings) {
        la_bound(ctx, LA_ERR_INVOKE_CAPACITY, line, name_length,
                 la_slice(name_start, name_length), la_text("invoke bindings"),
                 *binding_count + 1, ctx->limits->max_invoke_bindings);
        return 0;
    }
    member_index = la_find_invoke_member(
        ctx, procedure, name_start, name_length);
    if (member_index == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_INVOKE_BINDING, line, name_length,
                     la_slice(name_start, name_length),
                     la_text("callee input"));
        return 0;
    }
    if (la_invoke_has_binding(ctx, *binding_count, member_index)) {
        la_reject_at(ctx, LA_ERR_INVOKE_BINDING, line, name_length,
                     la_slice(name_start, name_length),
                     la_text("unique binding"));
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
            la_expected(ctx, LA_ERR_INVOKE_BINDING, line, la_name_slice(ctx,
                        ctx->locations[scan].name), la_text("required input"));
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
        if (la_slice_is_register(ctx, source)) {
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
        to_scratch = la_slice_is_register(ctx, dest);
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
                if (la_slice_is_accumulator(ctx, peer_dest)) {
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
            la_bound(ctx, LA_ERR_INVOKE_SCRATCH, line, 1, scratch_name,
                     la_text("invoke snapshot"), *scratch + width,
                     ctx->target->invoke_scratch_units);
            return 0;
        }
        binding->scratch = (la_u8)*scratch;
        *scratch = (la_u16)(*scratch + width);
    }
    return 1;
}

static int la_emit_invoke_save_item(LaContext *ctx,
                                    const LaProcedureRec *procedure,
                                    la_u16 bind, la_u16 line,
                                    LaSlice scratch_name)
{
    LaInvokeBindingRec *binding;
    la_u16 width;
    binding = &ctx->bindings[bind];
    width = la_location_storage_units(ctx, binding->name);
    return la_emit_invoke_operation(
        ctx, line, LA_TARGET_OP_INVOKE_SAVE,
        la_name_slice(ctx, procedure->name),
        la_name_slice(ctx, ctx->locations[binding->name].name),
        la_text(""), la_name_slice(ctx, binding->source), scratch_name,
        binding->scratch, width, LA_SOURCE_PHYSICAL);
}

static int la_emit_invoke_field_item(LaContext *ctx,
                                     const LaProcedureRec *procedure,
                                     la_u16 bind, la_u16 line,
                                     LaSlice scratch_name)
{
    LaInvokeBindingRec *binding;
    LaEvent event;
    binding = &ctx->bindings[bind];
    if (!la_count_operation(ctx, line)) return 0;
    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
    event.operation = LA_TARGET_OP_INVOKE_FIELD;
    event.owner = la_name_slice(ctx, procedure->name);
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
    return la_write_event(ctx, &event);
}

static int la_emit_invoke_regfield_item(LaContext *ctx,
                                        const LaProcedureRec *procedure,
                                        la_u16 bind, la_u16 line)
{
    LaInvokeBindingRec *binding;
    LaEvent event;
    binding = &ctx->bindings[bind];
    if (!la_count_operation(ctx, line)) return 0;
    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
    event.operation = LA_TARGET_OP_INVOKE_FIELD;
    event.owner = la_name_slice(ctx, procedure->name);
    event.path = la_name_slice(ctx, ctx->locations[binding->name].name);
    event.base = la_name_slice(
        ctx, ctx->locations[binding->field_base].physical);
    event.value = binding->field_disp;
    event.signed_value = binding->field_add;
    event.stride = binding->field_width;
    event.aux = la_name_slice(ctx, ctx->locations[binding->name].physical);
    event.count = 2;
    return la_write_event(ctx, &event);
}

static int la_emit_invoke_assign_item(LaContext *ctx,
                                      const LaProcedureRec *procedure,
                                      la_u16 bind, la_u16 line,
                                      LaSlice scratch_name)
{
    LaInvokeBindingRec *binding;
    la_u16 width;
    LaSlice owner;
    LaSlice source;
    owner = la_name_slice(ctx, procedure->name);
    binding = &ctx->bindings[bind];
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
        return la_write_event(ctx, &event);
    }
    if (binding->is_field) {
        /* Copy the snapshotted field value out of scratch. */
        return la_emit_invoke_operation(
            ctx, line, LA_TARGET_OP_INVOKE_ASSIGN, owner,
            la_name_slice(ctx, ctx->locations[binding->name].name),
            la_name_slice(ctx, ctx->locations[binding->name].physical),
            la_text(""), scratch_name,
            binding->scratch, binding->field_width, LA_SOURCE_PHYSICAL);
    }
    if (binding->source_kind == LA_SOURCE_PHYSICAL) {
        source = la_name_slice(ctx, binding->source);
    } else {
        source = la_text("");
    }
    if (binding->source_kind == LA_SOURCE_PHYSICAL &&
        !binding->needs_scratch) {
        /* Unconflicted location source: read it directly. */
        return la_emit_invoke_operation(
            ctx, line, LA_TARGET_OP_INVOKE_ASSIGN, owner,
            la_name_slice(ctx, ctx->locations[binding->name].name),
            la_name_slice(ctx, ctx->locations[binding->name].physical),
            source, scratch_name, 0, width, 3);
    }
    return la_emit_invoke_operation(
        ctx, line, LA_TARGET_OP_INVOKE_ASSIGN, owner,
        la_name_slice(ctx, ctx->locations[binding->name].name),
        la_name_slice(ctx, ctx->locations[binding->name].physical),
        source, scratch_name,
        binding->source_kind == LA_SOURCE_PHYSICAL ?
            binding->scratch : (la_u16)binding->immediate,
        width, binding->source_kind);
}

/* Marshalling order derives from the items' declared reads, writes and
   accumulator clobbers: an item that still needs a resource runs before
   the item that overwrites it, everything that reads the accumulator
   role runs before anything that passes through it, and the item whose
   destination is the accumulator runs after every clobber. The legacy
   class rank only breaks ties between independent items. */
static int la_invoke_item_must_precede(LaContext *ctx, int accumulator,
                                       const LaInvokeItemRec *first,
                                       const LaInvokeItemRec *second)
{
    if (first->binding == second->binding &&
        first->kind < second->kind &&
        second->kind == 2) {
        return 1;
    }
    if (second->write_name != LA_INVALID_HANDLE &&
        first->read_name != LA_INVALID_HANDLE &&
        la_slices_equal(la_name_slice(ctx, first->read_name),
                        la_name_slice(ctx, second->write_name))) {
        return 1;
    }
    if (second->write_register >= 0 &&
        first->read_register == second->write_register) {
        return 1;
    }
    if (second->via_accumulator && first->read_register == accumulator) {
        return 1;
    }
    if (second->write_register == accumulator &&
        first->via_accumulator && first != second) {
        return 1;
    }
    return 0;
}

static int la_emit_invoke_scheduled(LaContext *ctx,
                                    const LaProcedureRec *procedure,
                                    la_u16 binding_count, la_u16 line,
                                    LaSlice scratch_name)
{
    LaInvokeItemRec *items;
    la_u16 item_count;
    la_u16 bind;
    la_u16 emitted;
    int accumulator;
    la_u8 index_role_count;
    items = ctx->invoke_items;
    item_count = 0;
    accumulator = -1;
    index_role_count = 0;
    {
        la_u8 scan;
        for (scan = 0; scan < ctx->target->register_count; ++scan) {
            if (ctx->target->registers[scan].role ==
                LA_REGISTER_ACCUMULATOR) {
                accumulator = (int)scan;
            } else {
                ++index_role_count;
            }
        }
    }
    (void)index_role_count;
    for (bind = 0; bind < binding_count; ++bind) {
        LaInvokeBindingRec *binding;
        LaSlice dest;
        int dest_register;
        LaInvokeItemRec *item;
        binding = &ctx->bindings[bind];
        if (binding->elided) continue;
        dest = la_name_slice(ctx, ctx->locations[binding->name].physical);
        dest_register = la_register_lookup(ctx, dest);
        if (binding->is_field && binding->field_direct_register) {
            item = &items[item_count++];
            memset(item, 0, sizeof(*item));
            item->kind = 3;
            item->binding = bind;
            item->rank = 4;
            item->subrank = dest_register == accumulator ? 255 :
                (la_u8)(ctx->target->register_count - 1 - dest_register);
            item->read_name =
                ctx->locations[binding->field_base].physical;
            item->read_register = -1;
            item->write_name = LA_INVALID_HANDLE;
            item->write_register = dest_register;
            item->via_accumulator = 1;
            continue;
        }
        if (binding->is_field) {
            item = &items[item_count++];
            memset(item, 0, sizeof(*item));
            item->kind = 1;
            item->binding = bind;
            item->rank = 2;
            item->read_name =
                ctx->locations[binding->field_base].physical;
            item->read_register = -1;
            item->via_accumulator = 1;
            if (binding->field_to_scratch) {
                item->write_name = LA_INVALID_HANDLE;
                item->write_register = -1;
            } else {
                item->write_name =
                    ctx->locations[binding->name].physical;
                item->write_register = -1;
                continue; /* Direct field reads need no assignment. */
            }
        }
        if (binding->source_kind == LA_SOURCE_PHYSICAL &&
            !binding->is_field && binding->needs_scratch) {
            LaSlice source;
            source = la_name_slice(ctx, binding->source);
            item = &items[item_count++];
            memset(item, 0, sizeof(*item));
            item->kind = 0;
            item->binding = bind;
            item->read_register = la_register_lookup(ctx, source);
            if (item->read_register >= 0) {
                item->rank = 0;
                item->read_name = LA_INVALID_HANDLE;
                item->via_accumulator = 0;
            } else {
                item->rank = 1;
                item->read_name = binding->source;
                item->via_accumulator = 1;
            }
            item->write_name = LA_INVALID_HANDLE;
            item->write_register = -1;
        }
        item = &items[item_count++];
        memset(item, 0, sizeof(*item));
        item->kind = 2;
        item->binding = bind;
        item->rank = 3;
        item->read_register = -1;
        item->read_name = LA_INVALID_HANDLE;
        item->write_name = LA_INVALID_HANDLE;
        item->write_register = dest_register;
        if (dest_register < 0) {
            item->write_name = ctx->locations[binding->name].physical;
        }
        if (binding->is_word_immediate) {
            item->via_accumulator = 1;
        } else if (binding->is_field) {
            /* Scratch copy through the accumulator unless the
               destination is a register load. */
            item->via_accumulator = dest_register < 0;
        } else if (binding->source_kind == LA_SOURCE_PHYSICAL) {
            if (!binding->needs_scratch) {
                item->read_name = binding->source;
                item->via_accumulator = dest_register < 0;
            } else {
                item->via_accumulator = dest_register < 0;
            }
        } else {
            /* Byte immediates: register loads and the custom mov both
               leave the accumulator alone. */
            item->via_accumulator = 0;
        }
    }
    for (emitted = 0; emitted < item_count; ++emitted) {
        int best;
        la_u16 scan;
        best = -1;
        for (scan = 0; scan < item_count; ++scan) {
            la_u16 other;
            int ready;
            if (items[scan].emitted) continue;
            ready = 1;
            for (other = 0; other < item_count; ++other) {
                if (other == scan || items[other].emitted) continue;
                if (la_invoke_item_must_precede(
                        ctx, accumulator, &items[other], &items[scan])) {
                    ready = 0;
                    break;
                }
            }
            if (!ready) continue;
            if (best < 0 ||
                items[scan].rank < items[best].rank ||
                (items[scan].rank == items[best].rank &&
                 items[scan].subrank < items[best].subrank) ||
                (items[scan].rank == items[best].rank &&
                 items[scan].subrank == items[best].subrank &&
                 items[scan].binding < items[best].binding)) {
                best = (int)scan;
            }
        }
        if (best < 0) {
            la_reject(ctx, LA_ERR_INVOKE_BINDING, line,
                      la_text("no safe marshalling order"));
            return 0;
        }
        items[best].emitted = 1;
        switch (items[best].kind) {
        case 0:
            if (!la_emit_invoke_save_item(
                    ctx, procedure, items[best].binding, line,
                    scratch_name)) return 0;
            break;
        case 1:
            if (!la_emit_invoke_field_item(
                    ctx, procedure, items[best].binding, line,
                    scratch_name)) return 0;
            break;
        case 2:
            if (!la_emit_invoke_assign_item(
                    ctx, procedure, items[best].binding, line,
                    scratch_name)) return 0;
            break;
        default:
            if (!la_emit_invoke_regfield_item(
                    ctx, procedure, items[best].binding, line)) return 0;
            break;
        }
    }
    return 1;
}

int la_parse_invoke(LaContext *ctx,
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
        la_reject(ctx, LA_ERR_INVOKE_BINDING, line, la_text("callee"));
        return -1;
    }
    callee = la_find_procedure_scoped(
        ctx, callee_start, callee_length,
        ctx->procedures[caller].namespace_handle,
        ctx->procedures[caller].source_id, &is_private);
    if (callee == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_UNKNOWN_PROCEDURE, line, callee_length,
                     la_slice(callee_start, callee_length), la_text(""));
        return -1;
    }
    if (is_private) {
        la_reject_at(ctx, LA_ERR_PRIVATE_NAME, line, callee_length,
                     la_name_slice(ctx, ctx->procedures[callee].name),
                     la_text("export"));
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
    if (!la_emit_invoke_scheduled(
            ctx, procedure, binding_count, line, scratch_name)) {
        return -1;
    }
    owner = la_name_slice(ctx, procedure->name);
    if (procedure->is_inline) {
        if (is_tail) {
            la_reject_at(ctx, LA_ERR_INLINE_BODY, line, callee_length, owner,
                         la_text("inline has no tail form"));
            return -1;
        }
        if (la_expand_inline_body(ctx, callee, caller, line) < 0) return -1;
        return 1;
    }
    if (is_tail && ctx->procedures[caller].frame_size != 0) {
        la_reject_at(ctx, LA_ERR_FRAME_STACK_MUTATION, line, callee_length,
                     owner, la_text("tail with live frame"));
        return -1;
    }
    if (!la_emit_invoke_operation(
            ctx, line,
            is_tail ? LA_TARGET_OP_INVOKE_TAIL : LA_TARGET_OP_INVOKE_CALL,
            owner, la_text(""),
            la_text(""), la_text(""),
            scratch_name,
            scratch, binding_count, 0)) {
        return -1;
    }
    return 1;
}
