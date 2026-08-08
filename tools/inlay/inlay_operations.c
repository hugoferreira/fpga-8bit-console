/* Inlay core: Typed operation parsing: one parser per operand shape, each
   keyed off the spelling its family claims. */

#include "inlay_internal.h"

/* The lexical shape of a bracketed operand: `[base` up to `]`, with the
   base identifier extended through any namespace qualification and the
   cursor left on the `.` or `+` that opens the field path. */
static int la_split_bracket(LaContext *ctx, const char *bracket,
                            const char *end, la_u16 line, LaSlice shape,
                            const char **close, const char **base_start,
                            const char **base_end, const char **cursor)
{
    const char *scan;
    scan = bracket + 1;
    while (scan < end && *scan != ']') ++scan;
    if (scan == end) {
        la_reject(ctx, LA_ERR_SYNTAX, line, la_text("]"));
        return 0;
    }
    *close = scan;
    *base_start = la_trim_left(bracket + 1, scan);
    *base_end = *base_start;
    while (*base_end < scan && la_is_ident(**base_end)) ++*base_end;
    la_extend_qualified_base(ctx, *base_start, base_end, scan,
                             la_procedure_at_line(ctx, line));
    *cursor = la_trim_left(*base_end, scan);
    if (*base_end == *base_start || *cursor >= scan ||
        (**cursor != '.' && **cursor != '+')) {
        la_reject(ctx, LA_ERR_SYNTAX, line, shape);
        return 0;
    }
    return 1;
}

/* Resolve a bracketed operand's field path and require a single scalar
   of `units` storage; `name` is what the width diagnostic calls it. */
static int la_resolve_scalar_field(LaContext *ctx, const char *root_start,
                                   la_u16 root_length,
                                   const char *path_start, const char *close,
                                   la_u16 line, la_u16 units, LaSlice name,
                                   la_u16 *field_index, la_u16 *offset,
                                   la_u16 *size)
{
    if (la_resolve_path(ctx, root_start, root_length, path_start,
                        (la_u16)(close - path_start), line,
                        field_index, offset) != LA_OK) return 0;
    *size = la_field_leaf_size(ctx, *field_index);
    if (ctx->fields[*field_index].count != 1 || *size != units) {
        la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(close - path_start),
                 la_name_slice(ctx, ctx->fields[*field_index].name), name,
                 *size, units);
        return 0;
    }
    return 1;
}

static int la_parse_overlay_address(LaContext *ctx,
                                    const char *start, const char *end,
                                    la_u16 line, LaEvent *event,
                                    const char *dest_start, la_u16 dest_length,
                                    const char *name_start, la_u16 name_length,
                                    const char *dot);

int la_parse_typed_operation(LaContext *ctx,
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
    operation = (LaTargetOperationKind)la_claimed_operation(
        ctx, cursor, end, LA_SPELL_TYPED_OPERATION);
    if (operation == 0) return 0;
    bracket = la_trim_left(la_skip_spelling(cursor, end), end);
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
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(base_start - start +
                1), (la_u16)(base_end - base_start), la_slice(base_start,
                (la_u16)(base_end - base_start)),
                la_text("typed location or overlay"), 0, 0);
        return -1;
    }
    cursor = la_trim_left(base_end, close);
    if (is_overlay) {
        base_type = la_name_slice(ctx, ctx->overlays[overlay_index].type_name);
    } else {
        base_type = la_name_slice(ctx,
                                  ctx->locations[location_index].type_name);
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
            la_fail(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(root_start -
                    start + 1), root_length, base_type, la_slice(root_start,
                    root_length), 0, 0);
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
        {
            /* Pointer-indexed and absolute-indexed addressing admit the
               registers the description declares for each use. */
            la_u8 use;
            use = is_overlay ? LA_REGISTER_ABSOLUTE_INDEX :
                               LA_REGISTER_POINTER_INDEX;
            if (!la_register_allows(ctx, index, use)) {
                la_reject_at(ctx, LA_ERR_INDEX_LOCATION, line, index.length,
                             index, la_register_names(ctx, use));
                return -1;
            }
        }
        if ((!is_overlay &&
             stride != 1 && stride != 2 && stride != 4 && stride != 8) ||
            (is_overlay && stride != 1)) {
            la_bound(ctx, LA_ERR_INDEX_STRIDE, line, index.length, index,
                     la_slice(is_overlay ? "1" : "1, 2, 4, or 8", is_overlay ?
                     1 : 13), stride, is_overlay ? 1 : 8);
            return -1;
        }
        if (is_overlay) {
            /* Absolute indexed access (ADDR + field, Y): the field offset is
               part of the 16-bit base address, so only the index range must
               fit the 8-bit physical register. This lets page views past the
               first 256 bytes be reached without hidden scratch. */
            if ((la_u32)(count - 1) * stride > 255) {
                la_bound(ctx, LA_ERR_DISPLACEMENT, line, index.length, index,
                         la_text("index register range"),
                         (la_i32)((la_u32)(count - 1) * stride), 255);
                return -1;
            }
        } else if ((la_u32)offset + (la_u32)(count - 1) * stride >
                   ctx->target->max_displacement) {
            la_bound(ctx, LA_ERR_DISPLACEMENT, line, index.length, index,
                     la_text("indexed displacement"), (la_i32)((la_u32)offset +
                     (la_u32)(count - 1) * stride),
                     ctx->target->max_displacement);
            return -1;
        }
    } else if (la_resolve_path(ctx, root_start, root_length, path_start,
                               (la_u16)(close - path_start), line,
                               &field_index, &offset) != LA_OK) {
        return -1;
    }
    leaf_size = la_field_leaf_size(ctx, field_index);
    if (leaf_size != 1 ||
        (!indexed && ctx->fields[field_index].count != 1)) {
        la_fail(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(path_start - start +
                1), (la_u16)(close - path_start), la_name_slice(ctx,
                ctx->fields[field_index].name), la_text("byte"), leaf_size, 1);
        return -1;
    }
    /* A fixed overlay field is reached by absolute addressing, so its offset
       is part of the 16-bit address and is not bound by the pointer
       displacement window. */
    if (!is_overlay && offset > ctx->target->max_displacement) {
        la_fail(ctx, LA_ERR_DISPLACEMENT, line, (la_u16)(path_start - start +
                1), (la_u16)(close - path_start), la_slice(path_start,
                (la_u16)(close - path_start)), la_text(""), offset,
                ctx->target->max_displacement);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    event->kind = LA_EVENT_TARGET_OPERATION;
    la_set_span(ctx, &event->span, line, 1, (la_u16)(end - start));
    event->text = la_text("");
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
    event->aux = la_text("");
    event->aux2 = la_text("");
    event->property = (LaPropertyKind)0;
    if (operation == LA_TARGET_OP_ADC8_OVERLAY_INDEXED ||
        operation == LA_TARGET_OP_SBC8_OVERLAY_INDEXED) {
        /* Carry-chain arithmetic through an indexed fixed-overlay array (the
           effects structure-of-arrays); the accumulator and carry are live. */
        if (!is_overlay || !indexed) {
            return la_unsupported(ctx, start, end, line,
                la_text("indexed fixed-overlay carry arithmetic"));
        }
        if (!ctx->target->overlay_byte_operations ||
            !ctx->target->indexed_overlay_byte_operations) {
            return la_unsupported(ctx, start, end, line,
                                  la_text("indexed overlay byte access"));
        }
        event->operation = operation;
        event->access_width = 1;
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
        if (!is_overlay || indexed) {
            return la_unsupported(ctx, start, end, line,
                la_text("fixed-overlay accumulator or register op"));
        }
        if (!ctx->target->overlay_byte_operations) {
            return la_unsupported(ctx, start, end, line,
                                  la_text("static overlay byte access"));
        }
        event->operation = operation;
        event->access_width = 1;
        event->volatility = ctx->overlays[overlay_index].volatile_access ?
            LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    } else if (is_overlay) {
        if (!ctx->target->overlay_byte_operations) {
            return la_unsupported(ctx, start, end, line,
                                  la_text("static overlay byte access"));
        }
        if (indexed && !ctx->target->indexed_overlay_byte_operations) {
            return la_unsupported(ctx, start, end, line,
                                  la_text("indexed overlay byte access"));
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

int la_parse_typed_word_operation(LaContext *ctx,
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
    {
        la_u8 claimed;
        claimed = la_claimed_operation(ctx, cursor, end,
                                       LA_SPELL_WORD_TRANSFER);
        if (claimed == 0) return 0;
        store = claimed == LA_TARGET_OP_STORE16_PTR_DISP;
    }
    if (!ctx->target->pointer_word_operations) {
        return la_unsupported(ctx, start, end, line,
                              la_text("typed pointer word transfer"));
    }
    cursor = la_trim_left(la_skip_spelling(cursor, end), end);
    if (store) {
        bracket = cursor;
    } else {
        word_start = cursor;
        while (cursor < end && la_is_ident(*cursor)) ++cursor;
        word_end = cursor;
        cursor = la_trim_left(cursor, end);
        if (word_end == word_start || cursor >= end || *cursor++ != ',') {
            la_reject(ctx, LA_ERR_SYNTAX, line,
                      la_text("ldw WORD, [pointer + Type.field]"));
            return -1;
        }
        bracket = la_trim_left(cursor, end);
    }
    if (bracket >= end || *bracket != '[') {
        la_reject(ctx, LA_ERR_SYNTAX, line, la_text("[pointer + Type.field]"));
        return -1;
    }
    if (!la_split_bracket(ctx, bracket, end, line,
                          la_text("[pointer.field]"),
                          &close, &base_start, &base_end, &cursor)) {
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    pointer_location = la_find_location_text_at(
        ctx, base_start, (la_u16)(base_end - base_start), procedure);
    if (pointer_location == LA_INVALID_HANDLE ||
        !ctx->locations[pointer_location].is_pointer) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(base_end -
                     base_start), la_slice(base_start, (la_u16)(base_end -
                     base_start)), la_text("typed pointer"));
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
            la_reject(ctx, LA_ERR_SYNTAX, line,
                      la_text("stw [pointer + Type.field], WORD"));
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
                la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(end -
                         cursor), la_slice(cursor, (la_u16)(end - cursor)),
                         la_text("16-bit immediate"), immediate_value, 65535);
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
        la_reject(ctx, LA_ERR_SYNTAX, line, la_slice(store ?
                  "stw [pointer + Type.field], WORD" :
                  "ldw WORD, [pointer + Type.field]", 34));
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
            la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(word_end -
                         word_start), la_slice(word_start, (la_u16)(word_end -
                         word_start)), la_text("physical two-unit word"));
            return -1;
        }
    }
    if (!la_resolve_scalar_field(ctx, root_start, root_length,
                                path_start, close, line, 2, la_text("two-unit word"),
                                &field_index, &field_offset, &field_size)) {
        return -1;
    }
    if ((la_u32)field_offset + 1 > ctx->target->max_displacement) {
        la_bound(ctx, LA_ERR_DISPLACEMENT, line, (la_u16)(close - path_start),
                 la_slice(path_start, (la_u16)(close - path_start)),
                 la_text("word displacement"), (la_i32)((la_u32)field_offset +
                 1), ctx->target->max_displacement);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
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
    event->value = field_offset;
    event->access_width = 2;
    event->byte_order = ctx->target->byte_order;
    event->volatility = LA_ACCESS_NONVOLATILE;
    return 1;
}

int la_parse_physical_word_arithmetic(LaContext *ctx,
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
    operation = (LaTargetOperationKind)la_claimed_operation(
        ctx, cursor, end, LA_SPELL_WORD_ARITHMETIC);
    if (operation == 0) return 0;
    cursor = la_trim_left(la_skip_spelling(cursor, end), end);
    left_start = cursor;
    while (cursor < end && la_is_ident(*cursor)) ++cursor;
    left_end = cursor;
    cursor = la_trim_left(cursor, end);
    if (left_end == left_start || cursor >= end || *cursor++ != ',') {
        return 0;
    }
    if (!ctx->target->physical_word_arithmetic ||
        ctx->target->word_accumulator == 0) {
        return la_unsupported(ctx, start, end, line,
                              la_text("physical word arithmetic"));
    }
    if (!la_equal_text(left_start, (la_u16)(left_end - left_start),
                       ctx->target->word_accumulator)) {
        la_reject_at(ctx, LA_ERR_MEMBER_PLACEMENT, line, (la_u16)(left_end -
                     left_start), la_slice(left_start, (la_u16)(left_end -
                     left_start)), la_slice(ctx->target->word_accumulator,
                     (la_u16)strlen(ctx->target->word_accumulator)));
        return -1;
    }
    cursor = la_trim_left(cursor, end);
    right_start = cursor;
    while (cursor < end && la_is_ident(*cursor)) ++cursor;
    right_end = cursor;
    if (right_end == right_start || la_trim_left(cursor, end) != end) {
        la_reject(ctx, LA_ERR_SYNTAX, line, la_text("OP ab, WORD"));
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
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(right_end -
                     right_start), la_slice(right_start, (la_u16)(right_end -
                     right_start)), la_text("physical two-unit word"));
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
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
int la_resolve_field_tail(LaContext *ctx, const char *start,
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
        la_fail(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(*root_start - start +
                1), *root_length, base_type, la_slice(*root_start,
                *root_length), 0, 0);
        return -1;
    }
    return 1;
}

int la_parse_typed_byte_rmw(LaContext *ctx,
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
    operation = (LaTargetOperationKind)la_claimed_operation(
        ctx, cursor, end, LA_SPELL_BYTE_RMW);
    if (operation == 0) return 0;
    /* The masking updates carry the mask as an immediate operand. */
    needs_immediate = operation == LA_TARGET_OP_AND8_PTR_DISP ||
                      operation == LA_TARGET_OP_OR8_PTR_DISP;
    cursor = la_skip_spelling(cursor, end);
    bracket = la_trim_left(cursor, end);
    if (bracket >= end || *bracket != '[') return 0;
    if (!ctx->target->pointer_byte_rmw_operations) {
        return la_unsupported(ctx, start, end, line,
                              la_text("typed pointer byte update"));
    }
    if (!la_split_bracket(ctx, bracket, end, line,
                          la_text("[base.field]"),
                          &close, &base_start, &base_end,
                          &cursor)) {
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
            la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(base_end -
                         base_start), la_slice(base_start, (la_u16)(base_end -
                         base_start)), la_text("typed pointer or overlay"));
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
        tail = la_resolve_field_tail(ctx, start, cursor, close, line,
                                     base_type,
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
            la_reject(ctx, LA_ERR_SYNTAX, line, la_text("#VALUE"));
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
            la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(end -
                     immediate_start), la_slice(immediate_start, (la_u16)(end -
                     immediate_start)), la_text("byte immediate"), immediate,
                     255);
            return -1;
        }
    } else if (cursor != end) {
        la_reject_at(ctx, LA_ERR_SYNTAX, line, (la_u16)(end - cursor),
                     la_text("end of byte update"), la_slice(cursor,
                     (la_u16)(end - cursor)));
        return -1;
    }
    if (!la_resolve_scalar_field(ctx, root_start, root_length,
                                path_start, close, line, 1, la_text("byte"),
                                &field_index, &field_offset, &field_size)) {
        return -1;
    }
    /* A fixed overlay names an absolute address, so the field displacement is
       not bounded by the target's pointer displacement window. */
    if (!rmw_is_overlay && field_offset > ctx->target->max_displacement) {
        la_bound(ctx, LA_ERR_DISPLACEMENT, line, (la_u16)(close - path_start),
                 la_slice(path_start, (la_u16)(close - path_start)),
                 la_text(""), field_offset, ctx->target->max_displacement);
        return -1;
    }
    if (!la_count_operation(ctx, line)) return -1;
    la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                  (la_u16)(end - start));
    event->owner = la_slice(root_start, root_length);
    event->path = la_slice(path_start, (la_u16)(close - path_start));
    event->value = field_offset;
    event->offset = (la_u16)immediate;
    event->access_width = 1;
    if (rmw_is_overlay) {
        /* inc/dec lower to a native read-modify-write that clobbers no
           register; and/ora still need the accumulator, which is why
           the description gives those two a different contract. */
        event->operation =
            operation == LA_TARGET_OP_INC8_PTR_DISP ?
                LA_TARGET_OP_INC8_OVERLAY_ABS :
            operation == LA_TARGET_OP_DEC8_PTR_DISP ?
                LA_TARGET_OP_DEC8_OVERLAY_ABS :
            operation == LA_TARGET_OP_AND8_PTR_DISP ?
                LA_TARGET_OP_AND8_OVERLAY_ABS :
                LA_TARGET_OP_OR8_OVERLAY_ABS;
        event->base = la_name_slice(ctx, ctx->overlays[overlay_base].base);
        event->volatility = ctx->overlays[overlay_base].volatile_access ?
            LA_ACCESS_VOLATILE : LA_ACCESS_NONVOLATILE;
    } else {
        event->operation = operation;
        event->base =
            la_name_slice(ctx, ctx->locations[pointer_location].physical);
        event->volatility = LA_ACCESS_NONVOLATILE;
    }
    return 1;
}

/* decz [pointer + Type.field], label - branch to label when the byte field
   is zero, otherwise decrement it and fall through with A holding the
   post-decrement value. tstw [pointer + Type.field] / tstw WORD - Z from
   low|high of a two-unit field or declared word location; N is meaningless.
   Fixed overlays are deliberately excluded from both. */
int la_parse_observation_operation(LaContext *ctx,
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
    {
        la_u8 claimed;
        claimed = la_claimed_operation(ctx, cursor, end,
                                       LA_SPELL_OBSERVATION);
        if (claimed == 0) return 0;
        is_decz = claimed == LA_TARGET_OP_DECZ8_PTR_DISP;
        cursor = la_skip_spelling(cursor, end);
    }
    if (!ctx->target->pointer_byte_rmw_operations) {
        return la_unsupported(ctx, start, end, line,
                              la_text("typed observation operation"));
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
            la_reject(ctx, LA_ERR_SYNTAX, line, la_text("tstw WORD"));
            return -1;
        }
        word_location = la_find_location_text_at(
            ctx, word_start, (la_u16)(word_end - word_start), procedure);
        if (word_location == LA_INVALID_HANDLE ||
            ctx->locations[word_location].is_pointer ||
            !la_scalar_size(ctx, ctx->locations[word_location].type_name,
                            &word_size) ||
            word_size != 2) {
            la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(word_end -
                         word_start), la_slice(word_start, (la_u16)(word_end -
                         word_start)), la_text("physical two-unit word"));
            return -1;
        }
        if (!la_count_operation(ctx, line)) return -1;
        la_init_event(ctx, event, LA_EVENT_TARGET_OPERATION, line,
                      (la_u16)(end - start));
        event->operation = LA_TARGET_OP_TSTW_LOCATION;
        event->base =
            la_name_slice(ctx, ctx->locations[word_location].physical);
        event->owner = la_name_slice(ctx, ctx->locations[word_location].name);
        event->access_width = 2;
        event->volatility = LA_ACCESS_NONVOLATILE;
        return 1;
    }
    if (bracket >= end || *bracket != '[') {
        la_reject(ctx, LA_ERR_SYNTAX, line, la_text("[pointer + Type.field]"));
        return -1;
    }
    if (!la_split_bracket(ctx, bracket, end, line,
                          la_text("[pointer.field]"),
                          &close, &base_start, &base_end,
                          &cursor)) {
        return -1;
    }
    pointer_location = la_find_location_text_at(
        ctx, base_start, (la_u16)(base_end - base_start), procedure);
    if (pointer_location == LA_INVALID_HANDLE ||
        !ctx->locations[pointer_location].is_pointer) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(base_end -
                     base_start), la_slice(base_start, (la_u16)(base_end -
                     base_start)), la_text("typed pointer"));
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
            la_reject(ctx, LA_ERR_SYNTAX, line,
                      la_text("decz [pointer + Type.field], label"));
            return -1;
        }
        cursor = la_trim_left(cursor, end);
        label_start = cursor;
        while (cursor < end &&
               (la_is_ident(*cursor) || *cursor == '.')) ++cursor;
        if (cursor == label_start || la_trim_left(cursor, end) != end) {
            la_reject(ctx, LA_ERR_SYNTAX, line, la_text("branch label"));
            return -1;
        }
    } else if (cursor != end) {
        la_reject_at(ctx, LA_ERR_SYNTAX, line, (la_u16)(end - cursor),
                     la_text("end of word test"), la_slice(cursor, (la_u16)(end
                     - cursor)));
        return -1;
    }
    if (la_resolve_path(ctx, root_start, root_length, path_start,
                        (la_u16)(close - path_start), line,
                        &field_index, &field_offset) != LA_OK) return -1;
    field_size = la_field_leaf_size(ctx, field_index);
    required_size = is_decz ? 1 : 2;
    if (ctx->fields[field_index].count != 1 ||
        field_size != required_size) {
        LaSlice width_name;
        if (is_decz) {
            width_name = la_text("byte");
        } else {
            width_name = la_text("two-unit word");
        }
        la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(close - path_start),
                 la_name_slice(ctx, ctx->fields[field_index].name), width_name,
                 field_size, required_size);
        return -1;
    }
    if ((la_u32)field_offset + (required_size - 1) >
        ctx->target->max_displacement) {
        la_bound(ctx, LA_ERR_DISPLACEMENT, line, (la_u16)(close - path_start),
                 la_slice(path_start, (la_u16)(close - path_start)),
                 la_text(""), (la_i32)((la_u32)field_offset + (required_size -
                 1)), ctx->target->max_displacement);
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
        event->aux = la_slice(label_start, (la_u16)(cursor - label_start));
    }
    event->value = field_offset;
    event->access_width = (la_u16)required_size;
    event->volatility = LA_ACCESS_NONVOLATILE;
    return 1;
}

/* movw WORD, #expr16 / movw WORD, WORD - immediate or location-to-location
   word transfer through A. Destination and source must be declared two-unit
   physical word locations. Clobbers A and flags. */
int la_parse_word_move(LaContext *ctx,
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
    if (la_claimed_operation(ctx, cursor, end, LA_SPELL_WORD_MOVE) == 0) {
        return 0;
    }
    cursor = la_trim_left(la_skip_spelling(cursor, end), end);
    procedure = la_procedure_at_line(ctx, line);
    dest_start = cursor;
    dest_end = dest_start;
    while (dest_end < end && la_is_ident(*dest_end)) ++dest_end;
    la_extend_qualified_base(ctx, dest_start, &dest_end, end, procedure);
    cursor = la_trim_left(dest_end, end);
    if (dest_end == dest_start || cursor >= end || *cursor++ != ',') {
        la_reject(ctx, LA_ERR_SYNTAX, line,
                  la_text("movw WORD, #expr16 or WORD"));
        return -1;
    }
    dest_location = la_find_location_text_at(
        ctx, dest_start, (la_u16)(dest_end - dest_start), procedure);
    if (dest_location == LA_INVALID_HANDLE ||
        ctx->locations[dest_location].is_pointer ||
        !la_scalar_size(ctx, ctx->locations[dest_location].type_name,
                        &word_size) ||
        word_size != 2) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(dest_end -
                     dest_start), la_slice(dest_start, (la_u16)(dest_end -
                     dest_start)), la_text("physical two-unit word"));
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
            la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(end - cursor),
                     la_slice(cursor, (la_u16)(end - cursor)),
                     la_text("16-bit immediate"), immediate, 65535);
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
            la_reject(ctx, LA_ERR_SYNTAX, line,
                      la_text("movw WORD, #expr16 or WORD"));
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
            la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(source_end -
                         source_start), la_slice(source_start,
                         (la_u16)(source_end - source_start)),
                         la_text("physical two-unit word"));
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
    event->access_width = 2;
    event->byte_order = ctx->target->byte_order;
    event->volatility = LA_ACCESS_NONVOLATILE;
    return 1;
}

int la_has_explicit_typed_operand(const char *start, const char *end)
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

/* Compare/test-and-branch pseudo-ops against a fixed overlay field:
   `MNEM [overlay + Type.field], REST` or `MNEM [overlay.field], REST`. The
       tail
   (immediate and target label) is passed through verbatim; the pseudo-op still
   expands to the same bytes as the legacy raw zero-page form. */
int la_parse_overlay_branch(LaContext *ctx,
                                   const char *start, const char *end,
                                   la_u16 line, LaEvent *event)
{
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
    la_u16 i;
    cursor = la_trim_left(start, end);
    mnem_start = cursor;
    while (cursor < end && la_is_ident(*cursor)) ++cursor;
    mnem_end = cursor;
    mnem_length = (la_u16)(mnem_end - mnem_start);
    /* The branch spellings are the description's; the matched one is
       passed through to the lowering verbatim. */
    matched = 0;
    for (i = 0; i < ctx->target->spelling_count; ++i) {
        if (ctx->target->spellings[i].family !=
            LA_SPELL_OVERLAY_BRANCH) continue;
        if (la_equal_text(mnem_start, mnem_length,
                          ctx->target->spellings[i].spelling)) {
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
        la_reject(ctx, LA_ERR_SYNTAX, line,
                  la_text("MNEM [overlay.field], #VALUE, TARGET"));
        return -1;
    }
    overlay_index = la_find_overlay_text(
        ctx, base_start, (la_u16)(base_end - base_start));
    if (overlay_index == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(base_end -
                     base_start), la_slice(base_start, (la_u16)(base_end -
                     base_start)), la_text("overlay"));
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
    if (!la_resolve_scalar_field(ctx, root_start, root_length,
                                path_start, close, line, 1, la_text("byte"),
                                &field_index, &field_offset, &field_size)) {
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
   field. The immediate is passed through verbatim so target-side constants
       stay
   resolvable and the emitted bytes match the legacy raw form exactly. */
int la_parse_overlay_store_immediate(LaContext *ctx,
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
    if (la_claimed_operation(ctx, cursor, end,
                             LA_SPELL_OVERLAY_STORE_IMM) == 0) return 0;
    bracket = la_trim_left(la_skip_spelling(cursor, end), end);
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
       fixed overlay; a bare [base] is a frame-pointer move handled elsewhere.
           */
    if (cursor >= close || (*cursor != '.' && *cursor != '+')) return 0;
    imm_start = la_trim_left(close + 1, end);
    if (imm_start >= end || *imm_start != ',') return 0;
    imm_start = la_trim_left(imm_start + 1, end);
    if (imm_start < end && *imm_start == '[') {
        /* A second typed memory operand would be a memory-to-memory move the
           target does not define; keep it explicit and rejected. */
        return la_unsupported(ctx, start, end, line,
                              la_text("fixed-overlay memory-to-memory mov"));
    }
    if (imm_start == end) {
        la_reject(ctx, LA_ERR_SYNTAX, line,
                  la_text("mov [overlay.field], SOURCE"));
        return -1;
    }
    overlay_index = la_find_overlay_text(
        ctx, base_start, (la_u16)(base_end - base_start));
    if (overlay_index == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, (la_u16)(base_end -
                     base_start), la_slice(base_start, (la_u16)(base_end -
                     base_start)), la_text("overlay"));
        return -1;
    }
    tail = la_resolve_field_tail(
        ctx, start, cursor, close, line,
        la_name_slice(ctx, ctx->overlays[overlay_index].type_name),
        &root_start, &root_length, &path_start);
    if (tail == 0) return 0;
    if (tail < 0) return -1;
    if (!la_resolve_scalar_field(ctx, root_start, root_length,
                                path_start, close, line, 1, la_text("byte"),
                                &field_index, &field_offset, &field_size)) {
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
        la_reject(ctx, LA_ERR_SYNTAX, line,
                  la_text("address DEST, OVERLAY.field"));
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
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, dest_length,
                     la_slice(dest_start, dest_length),
                     la_text("address pointer destination"));
        return -1;
    }
    overlay_index = la_find_overlay_text(ctx, name_start, name_length);
    if (overlay_index == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, name_length,
                     la_slice(name_start, name_length), la_text("overlay"));
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

int la_parse_pool_address(LaContext *ctx,
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
        la_reject(ctx, LA_ERR_SYNTAX, line,
                  la_text("address DEST, POOL[INDEX]"));
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
        la_reject(ctx, LA_ERR_SYNTAX, line,
                  la_text("address DEST, POOL[INDEX]"));
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    location = la_find_location_text_at(
        ctx, destination_start, destination_length, procedure);
    if (location == LA_INVALID_HANDLE ||
        !ctx->locations[location].is_pointer) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, destination_length,
                     la_slice(destination_start, destination_length),
                     la_text("pointer destination"));
        return -1;
    }
    pool_index = la_find_pool_text(ctx, pool_start, pool_length);
    if (pool_index == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_UNKNOWN_POOL, line, pool_length,
                     la_slice(pool_start, pool_length), la_text(""));
        return -1;
    }
    pool = &ctx->pools[pool_index];
    if (ctx->locations[location].type_name != pool->type_name) {
        la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, destination_length,
                     la_name_slice(ctx, ctx->locations[location].type_name),
                     la_name_slice(ctx, pool->type_name));
        return -1;
    }
    if (!la_slice_is_accumulator(
            ctx, la_slice(index_start, index_length))) {
        la_reject_at(ctx, LA_ERR_INDEX_LOCATION, line, index_length,
                     la_slice(index_start, index_length),
                     la_accumulator_slice(ctx));
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

int la_parse_local_operation(LaContext *ctx,
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
    operation = (LaTargetOperationKind)la_claimed_operation(
        ctx, cursor, end, LA_SPELL_LOCAL_OPERATION);
    if (operation == 0) return 0;
    cursor = la_trim_left(la_skip_spelling(cursor, end), end);
    if (cursor >= end || *cursor++ != '[') return 0;
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        la_reject(ctx, LA_ERR_FRAME_LOCAL, line, la_text("local name"));
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
            la_reject(ctx, LA_ERR_FRAME_LOCAL, line, la_text("TYPE.field"));
            return -1;
        }
        if (cursor >= end || *cursor++ != '.') {
            la_reject(ctx, LA_ERR_FRAME_LOCAL, line, la_text("TYPE.field"));
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
            la_reject_at(ctx, LA_ERR_LOCATION_TYPE, line, root_length,
                         la_slice(root_start, root_length), la_name_slice(ctx,
                         local->type_name));
            return -1;
        }
        if (la_resolve_path(ctx, root_start, root_length, path_start,
                            (la_u16)(close - path_start), line,
                            &field_index, &field_offset) != LA_OK) return -1;
        if (ctx->fields[field_index].size != 1 ||
            ctx->fields[field_index].count != 1) {
            la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(close -
                     path_start), la_slice(path_start, (la_u16)(close -
                     path_start)), la_text("byte"),
                     ctx->fields[field_index].size, 1);
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
        la_reject(ctx, LA_ERR_FRAME_LOCAL, line,
                  la_text("[NAME] or [NAME + TYPE.field]"));
        return -1;
    }
    procedure = la_procedure_at_line(ctx, line);
    if (procedure == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_PROCEDURE_SCOPE, line, name_length,
                     la_slice(name_start, name_length), la_text("procedure"));
        return -1;
    }
    local_index = la_find_local_text(ctx, procedure, name_start, name_length);
    if (local_index == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_FRAME_LOCAL, line, name_length,
                     la_slice(name_start, name_length),
                     la_text("declared local"));
        return -1;
    }
    local = &ctx->locals[local_index];
    record = &ctx->procedures[procedure];
    if (!qualified && local->size != 1) {
        la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, name_length,
                 la_slice(name_start, name_length), la_text("byte"),
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

int la_parse_frame_pointer_move(LaContext *ctx,
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
    if (la_claimed_operation(ctx, cursor, end,
                             LA_SPELL_FRAME_POINTER_MOVE) == 0) return 0;
    cursor = la_trim_left(la_skip_spelling(cursor, end), end);
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
        la_expected(ctx, LA_ERR_LOCATION_TYPE, line, la_slice(store ?
                    left_start : right_start, store ? left_length :
                    right_length), la_text("matching pointer locations"));
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
    event->aux2 = la_accumulator_slice(ctx);
    event->operation = store ? LA_TARGET_OP_STORE_PTR_FRAME :
                               LA_TARGET_OP_LOAD_PTR_FRAME;
    event->value = (la_u16)(
        ctx->procedures[procedure].frame_size -
        ctx->locals[local_index].offset);
    event->stride = ctx->target->pointer_units;
    event->count = ctx->procedures[procedure].frame_size;
    return 1;
}

int la_parse_offset_materialization(LaContext *ctx,
                                           const char *start,
                                           const char *end,
                                           la_u16 line, la_u16 families,
                                           LaEvent *event)
{
    const char *cursor;
    const char *keyword;
    const char *physical_start;
    const char *path_start;
    const char *path_end;
    const char *first_dot;
    la_u16 physical_length;
    la_u16 field_index;
    la_u16 offset;
    la_i32 addend;
    cursor = la_trim_left(start, end);
    keyword = la_family_spelling(ctx, LA_SPELL_OFFSET_KEYWORD);
    if (keyword == 0) return 0;
    /* The keyword alone is the shape this operation is not: name the
       form the description does claim, in its own spellings. */
    if ((families & LA_SPELL_OFFSET_KEYWORD) != 0) {
        const char *move;
        la_u16 length;
        move = la_family_spelling(ctx, LA_SPELL_OFFSET_MATERIALIZE);
        if (move == 0) return 0;
        length = 0;
        length = la_append_text(ctx, length, move);
        length = la_append_text(ctx, length, " DEST, ");
        length = la_append_text(ctx, length, keyword);
        length = la_append_text(ctx, length, " TYPE.FIELD");
        la_reject_at(ctx, LA_ERR_UNSUPPORTED_OPERATION, line,
                     (la_u16)strlen(keyword), la_slice(cursor,
                     (la_u16)strlen(keyword)), la_slice(ctx->path_buffer,
                     length));
        return -1;
    }
    cursor = la_skip_spelling(cursor, end);
    if (!la_read_identifier(
            &cursor, end, &physical_start, &physical_length)) {
        return 0;
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ',') {
        return 0;
    }
    cursor = la_trim_left(cursor, end);
    if (!la_take_word(&cursor, end, keyword)) return 0;
    if (!la_slice_is_register(
            ctx, la_slice(physical_start, physical_length))) {
        la_reject_at(ctx, LA_ERR_MEMBER_PLACEMENT, line, physical_length,
                     la_slice(physical_start, physical_length),
                     la_register_names(ctx, 0));
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
            la_reject(ctx, LA_ERR_SYNTAX, line,
                      la_text("constant byte addend"));
            return -1;
        }
        while (cursor < end && *cursor >= '0' && *cursor <= '9') {
            addend = addend * 10 + (*cursor++ - '0');
        }
        if (negative) addend = -addend;
        cursor = la_trim_left(cursor, end);
    }
    if (path_end == path_start || cursor != end) {
        la_reject(ctx, LA_ERR_SYNTAX, line, la_text("TYPE.FIELD"));
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
            la_reject_at(ctx, LA_ERR_UNKNOWN_FIELD, line, (la_u16)(path_end -
                         path_start), la_slice(path_start, (la_u16)(path_end -
                         path_start)), la_text(""));
        }
        return -1;
    }
    if ((la_i32)offset + addend < 0 ||
        (la_i32)offset + addend > ctx->target->max_displacement) {
        la_bound(ctx, LA_ERR_DISPLACEMENT, line, (la_u16)(path_end -
                 path_start), la_slice(path_start, (la_u16)(path_end -
                 path_start)), la_slice(physical_start, physical_length),
                 (la_i32)offset + addend, ctx->target->max_displacement);
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

int la_parse_qualified_immediate(LaContext *ctx,
                                        const char *start,
                                        const char *end,
                                        la_u16 line, la_u16 families,
                                        LaEvent *event)
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
    /* The claiming family says which operation this spelling is: the
       compare reads the immediate alone, the move takes a destination
       first. */
    if ((families & LA_SPELL_VALUE_COMPARE) != 0) {
        operation = LA_TARGET_OP_VALUE_CMP;
        cursor = la_skip_spelling(cursor, end);
    } else {
        operation = LA_TARGET_OP_VALUE_MOV;
        cursor = la_skip_spelling(cursor, end);
        if (!la_read_qualified_identifier(
                &cursor, end, &destination_start,
                &destination_length)) return 0;
        cursor = la_trim_left(cursor, end);
        if (cursor >= end || *cursor++ != ',') return 0;
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
        la_bound(ctx, LA_ERR_ACCESS_WIDTH, line, (la_u16)(end -
                 expression_start), la_slice(expression_start, (la_u16)(end -
                 expression_start)), la_text("8-bit immediate"), value, 255);
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
