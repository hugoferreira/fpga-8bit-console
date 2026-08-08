/* Inlay core: Declared tables: method tables, pool tables and procedure
   address data, emitted through the description's strategies. */

#include "inlay_internal.h"

static la_u16 la_find_enum_member_text(LaContext *ctx, la_u16 enum_handle,
                                       const char *text, la_u16 length);
static int la_emit_strategy_label(LaContext *ctx, la_u16 line,
                                  la_u8 strategy, la_u8 lane, LaSlice name);

/* method_table NAME : ENUM[LOW .. HIGH] - rows are keyed by enum member
   value over the declared inclusive domain; columns emit value tables or
   split low/high code-pointer tables at the declaration's position. */
static la_u16 la_find_enum_member_text(LaContext *ctx, la_u16 enum_handle,
                                       const char *text, la_u16 length)
{
    LaEnumRec *enumeration;
    la_u16 index;
    enumeration = &ctx->enums[enum_handle];
    for (index = enumeration->first_member;
         index < enumeration->first_member + enumeration->member_count;
         ++index) {
        LaSlice name;
        name = la_name_slice(ctx, ctx->enum_members[index].name);
        if (name.length == length &&
            memcmp(name.data, text, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

LaDiagnosticCode la_parse_method_table(LaContext *ctx,
                                              const char *start,
                                              const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *enum_start;
    const char *low_start;
    const char *high_start;
    la_u16 name_length;
    la_u16 enum_length;
    la_u16 low_length;
    la_u16 high_length;
    la_u16 enum_handle;
    la_u16 low_member;
    la_u16 high_member;
    LaMethodTableRec *record;
    if (ctx->method_table_count >= ctx->limits->max_method_tables) {
        return la_bound(ctx, LA_ERR_STRUCT_CAPACITY, line, 1,
                        la_text("method tables"), la_text(""),
                        ctx->method_table_count + 1,
                        ctx->limits->max_method_tables);
    }
    cursor = la_trim_left(start, end) + 12;
    cursor = la_trim_left(cursor, end);
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line,
                         la_text("method table name"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text(":"));
    }
    cursor = la_trim_left(cursor, end);
    if (!la_read_identifier(&cursor, end, &enum_start, &enum_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("enum name"));
    }
    enum_handle = la_find_enum_text(ctx, enum_start, enum_length);
    if (enum_handle == LA_INVALID_HANDLE) {
        return la_reject_at(ctx, LA_ERR_UNKNOWN_TYPE, line, enum_length,
                            la_slice(enum_start, enum_length),
                            la_text("declared enum"));
    }
    if (cursor >= end || *cursor++ != '[') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("[low .. high]"));
    }
    cursor = la_trim_left(cursor, end);
    if (!la_read_identifier(&cursor, end, &low_start, &low_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line,
                         la_text("domain low member"));
    }
    cursor = la_trim_left(cursor, end);
    if ((la_u16)(end - cursor) < 2 || cursor[0] != '.' || cursor[1] != '.') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text(".."));
    }
    cursor = la_trim_left(cursor + 2, end);
    if (!la_read_identifier(&cursor, end, &high_start, &high_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line,
                         la_text("domain high member"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ']' ||
        la_trim_left(cursor, end) != end) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("]"));
    }
    low_member = la_find_enum_member_text(ctx, enum_handle,
                                          low_start, low_length);
    high_member = la_find_enum_member_text(ctx, enum_handle,
                                           high_start, high_length);
    if (low_member == LA_INVALID_HANDLE ||
        high_member == LA_INVALID_HANDLE) {
        return la_reject(ctx, LA_ERR_ENUM_VALUE, line,
                         la_text("domain member"));
    }
    record = &ctx->method_tables[ctx->method_table_count];
    record->name = la_intern(ctx, name_start, name_length, line, 1);
    if (record->name == LA_INVALID_HANDLE) return ctx->error;
    record->enum_handle = enum_handle;
    record->low = (la_i32)low_member;
    record->high = (la_i32)high_member;
    record->first_column = ctx->method_column_count;
    record->column_count = 0;
    record->first_row = ctx->method_row_count;
    record->row_count = 0;
    record->line = line;
    record->end_line = 0;
    ++ctx->method_table_count;
    return LA_OK;
}

LaDiagnosticCode la_parse_method_column(LaContext *ctx,
                                               const char *start,
                                               const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    const char *kind_start;
    la_u16 name_length;
    la_u16 kind_length;
    LaMethodTableRec *record;
    LaMethodColumnRec *column;
    record = &ctx->method_tables[ctx->method_table_count - 1];
    if (record->row_count != 0) {
        return la_reject_at(ctx, LA_ERR_SYNTAX, line, 6,
                            la_text("slots before members"), la_text(""));
    }
    if (ctx->method_column_count >= ctx->limits->max_method_columns) {
        return la_bound(ctx, LA_ERR_STRUCT_CAPACITY, line, 1,
                        la_text("method table slots"), la_text(""),
                        ctx->method_column_count + 1,
                        ctx->limits->max_method_columns);
    }
    cursor = la_trim_left(start, end);
    if (!la_read_identifier(&cursor, end, &name_start, &name_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("slot name"));
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != ':') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text(":"));
    }
    cursor = la_trim_left(cursor, end);
    if (!la_read_identifier(&cursor, end, &kind_start, &kind_length) ||
        la_trim_left(cursor, end) != end ||
        (!la_equal_text(kind_start, kind_length, "u8") &&
         !la_equal_text(kind_start, kind_length, "code"))) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("u8 or code"));
    }
    column = &ctx->method_columns[ctx->method_column_count];
    column->label = la_intern(ctx, name_start, name_length, line, 1);
    if (column->label == LA_INVALID_HANDLE) return ctx->error;
    column->is_code = la_equal_text(kind_start, kind_length, "code");
    ++ctx->method_column_count;
    ++record->column_count;
    return LA_OK;
}

LaDiagnosticCode la_parse_method_row(LaContext *ctx,
                                            const char *start,
                                            const char *end, la_u16 line)
{
    const char *cursor;
    const char *member_start;
    la_u16 member_length;
    la_u16 member;
    la_u16 count;
    la_u16 scan;
    LaMethodTableRec *record;
    LaMethodRowRec *row;
    record = &ctx->method_tables[ctx->method_table_count - 1];
    if (record->column_count == 0) {
        return la_reject_at(ctx, LA_ERR_SYNTAX, line, 3,
                            la_text("slots before members"), la_text(""));
    }
    if (ctx->method_row_count >= ctx->limits->max_method_rows) {
        return la_bound(ctx, LA_ERR_STRUCT_CAPACITY, line, 1,
                        la_text("method rows"), la_text(""),
                        ctx->method_row_count + 1,
                        ctx->limits->max_method_rows);
    }
    cursor = la_trim_left(start, end);
    if (!la_read_identifier(&cursor, end, &member_start, &member_length)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("member name"));
    }
    member = la_find_enum_member_text(ctx, record->enum_handle,
                                      member_start, member_length);
    if (member == LA_INVALID_HANDLE) {
        return la_reject_at(ctx, LA_ERR_ENUM_VALUE, line, member_length,
                            la_slice(member_start, member_length),
                            la_name_slice( ctx,
                            ctx->enums[record->enum_handle].name));
    }
    for (scan = record->first_row;
         scan < record->first_row + record->row_count; ++scan) {
        if (ctx->method_rows[scan].member_value == (la_i32)member) {
            return la_reject_at(ctx, LA_ERR_DUPLICATE_FIELD, line,
                                member_length, la_slice(member_start,
                                member_length), la_text("method row"));
        }
    }
    cursor = la_trim_left(cursor, end);
    if (cursor >= end || *cursor++ != '=') {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("="));
    }
    row = &ctx->method_rows[ctx->method_row_count];
    row->member_value = (la_i32)member;
    row->first_value = ctx->method_value_count;
    row->line = line;
    count = 0;
    while (count < record->column_count) {
        const char *value_start;
        const char *value_end;
        cursor = la_trim_left(cursor, end);
        value_start = cursor;
        while (cursor < end && *cursor != ',') ++cursor;
        value_end = cursor;
        while (value_end > value_start &&
               la_is_space(value_end[-1])) --value_end;
        if (value_end == value_start) {
            return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("row value"));
        }
        if (ctx->method_value_count >= ctx->limits->max_method_values) {
            return la_bound(ctx, LA_ERR_STRUCT_CAPACITY, line, 1,
                            la_text("method values"), la_text(""),
                            ctx->method_value_count + 1,
                            ctx->limits->max_method_values);
        }
        ctx->method_values[ctx->method_value_count] =
            la_intern(ctx, value_start,
                      (la_u16)(value_end - value_start), line, 1);
        if (ctx->method_values[ctx->method_value_count] ==
            LA_INVALID_HANDLE) return ctx->error;
        ++ctx->method_value_count;
        ++count;
        if (cursor < end) ++cursor;
    }
    if (la_trim_left(cursor, end) != end) {
        return la_reject(ctx, LA_ERR_SYNTAX, line,
                         la_text("one value per slot"));
    }
    ++ctx->method_row_count;
    ++record->row_count;
    return LA_OK;
}

/* A strategy's label, carrying the composed table name. */
static int la_emit_strategy_label(LaContext *ctx, la_u16 line,
                                  la_u8 strategy, la_u8 lane, LaSlice name)
{
    LaEvent event;
    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line,
                  name.length);
    event.operation = LA_TARGET_OP_TABLE_LABEL;
    event.strategy = strategy;
    event.lane = lane;
    event.base = name;
    return la_write_event(ctx, &event);
}

/* Emission runs in the main pass at the declaration's end line, once enum
   member values have resolved: rows are ordered by member value over the
   inclusive domain, coverage is total, and every row's text comes from
   the lane of the strategy its column selects. */
int la_emit_method_table(LaContext *ctx, LaMethodTableRec *record,
                                la_u16 line)
{
    la_i32 low_value;
    la_i32 high_value;
    la_i32 value;
    la_u16 column;
    la_u8 dispatch_strategy;
    la_u8 value_strategy;
    LaEvent event;
    {
        int dispatch;
        int values;
        dispatch = la_default_strategy(ctx, LA_STRATEGY_DISPATCH_TABLE);
        values = la_default_strategy(ctx, LA_STRATEGY_VALUE_TABLE);
        if (dispatch < 0 || values < 0) {
            la_expected(ctx, LA_ERR_UNSUPPORTED_OPERATION, record->line,
                        la_text("method table"),
                        la_text("no declared strategy"));
            return 0;
        }
        dispatch_strategy = (la_u8)dispatch;
        value_strategy = (la_u8)values;
    }
    low_value = ctx->enum_members[record->low].value;
    high_value = ctx->enum_members[record->high].value;
    if (high_value < low_value) {
        la_bound(ctx, LA_ERR_ENUM_VALUE, record->line, 1,
                 la_text("domain order"), la_text(""), high_value, low_value);
        return 0;
    }
    /* Aliased members inside the domain would generate duplicate rows. */
    {
        LaEnumRec *enumeration;
        la_u16 a;
        la_u16 b;
        enumeration = &ctx->enums[record->enum_handle];
        for (a = enumeration->first_member;
             a < enumeration->first_member + enumeration->member_count;
             ++a) {
            if (ctx->enum_members[a].value < low_value ||
                ctx->enum_members[a].value > high_value) continue;
            for (b = (la_u16)(a + 1);
                 b < enumeration->first_member + enumeration->member_count;
                 ++b) {
                if (ctx->enum_members[a].value ==
                    ctx->enum_members[b].value) {
                    la_expected(ctx, LA_ERR_DUPLICATE_ENUM_MEMBER,
                                record->line, la_name_slice(ctx,
                                ctx->enum_members[b].name),
                                la_text("aliased in domain"));
                    return 0;
                }
            }
        }
    }
    for (column = 0; column < record->column_count; ++column) {
        LaMethodColumnRec *col;
        const LaStrategyDesc *strategy;
        la_u8 strategy_index;
        la_u8 lane_index;
        col = &ctx->method_columns[record->first_column + column];
        strategy_index = col->is_code ? dispatch_strategy : value_strategy;
        strategy = &ctx->target->strategies[strategy_index];
        for (lane_index = 0; lane_index < strategy->lane_count;
             ++lane_index) {
            const LaStrategyLane *lane;
            LaSlice label;
            LaSlice table_name;
            la_u16 length;
            la_u16 suffix_length;
            lane = &strategy->lanes[lane_index];
            table_name = la_name_slice(ctx, record->name);
            label = la_name_slice(ctx, col->label);
            suffix_length = (la_u16)strlen(lane->suffix);
            memcpy(ctx->path_buffer, table_name.data, table_name.length);
            length = table_name.length;
            ctx->path_buffer[length++] = '_';
            memcpy(ctx->path_buffer + length, label.data, label.length);
            length = (la_u16)(length + label.length);
            memcpy(ctx->path_buffer + length, lane->suffix, suffix_length);
            length = (la_u16)(length + suffix_length);
            if (!la_emit_strategy_label(ctx, line, strategy_index,
                                        lane_index,
                                        la_slice(ctx->path_buffer, length))) {
                return 0;
            }
            for (value = low_value; value <= high_value; ++value) {
                la_u16 scan;
                la_u16 cell;
                LaSlice text;
                cell = LA_INVALID_HANDLE;
                for (scan = record->first_row;
                     scan < record->first_row + record->row_count;
                     ++scan) {
                    if (ctx->enum_members[
                            ctx->method_rows[scan].member_value].value ==
                        value) {
                        cell = (la_u16)(
                            ctx->method_rows[scan].first_value + column);
                        break;
                    }
                }
                if (cell == LA_INVALID_HANDLE) {
                    la_bound(ctx, LA_ERR_ENUM_VALUE, record->line, 1,
                             la_name_slice(ctx, record->name),
                             la_text("uncovered domain value"), value, 0);
                    return 0;
                }
                text = la_name_slice(ctx, ctx->method_values[cell]);
                if (la_equal_text(text.data, text.length, "absent")) {
                    /* A lane with no hole template cannot express an
                       absent entry. */
                    if (lane->hole == 0) {
                        la_reject(ctx, LA_ERR_SYNTAX, record->line,
                                  la_text("absent in value slot"));
                        return 0;
                    }
                    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION,
                                  line, 1);
                    event.operation = LA_TARGET_OP_TABLE_HOLE;
                    event.strategy = strategy_index;
                    event.lane = lane_index;
                    if (!la_write_event(ctx, &event)) return 0;
                    continue;
                }
                if (col->is_code) {
                    la_u16 procedure;
                    int is_private;
                    procedure = la_find_procedure_scoped(
                        ctx, text.data, text.length, LA_INVALID_HANDLE,
                        la_source_id_at_line(ctx, record->line),
                        &is_private);
                    if (procedure == LA_INVALID_HANDLE) {
                        la_reject_at(ctx, LA_ERR_UNKNOWN_PROCEDURE,
                                     record->line, text.length, text,
                                     la_text(""));
                        return 0;
                    }
                    if (ctx->procedures[procedure].is_inline) {
                        la_reject_at(ctx, LA_ERR_INLINE_BODY, record->line,
                                     text.length, la_name_slice( ctx,
                                     ctx->procedures[procedure].name),
                                     la_text("inline has no address"));
                        return 0;
                    }
                    if (!la_count_operation(ctx, line)) return 0;
                    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION,
                                  line, 1);
                    event.owner = la_name_slice(
                        ctx, ctx->procedures[procedure].name);
                    event.operation = LA_TARGET_OP_DISPATCH_ENTRY;
                    event.strategy = strategy_index;
                    event.lane = lane_index;
                    event.access_width = lane->units;
                    event.byte_order = ctx->target->byte_order;
                    if (!la_write_event(ctx, &event)) return 0;
                } else {
                    la_i32 cell_value;
                    la_i32 cell_limit;
                    if (la_eval_expression(
                            ctx, text.data, text.data + text.length,
                            record->line, &cell_value) != LA_OK) return 0;
                    cell_limit = (la_i32)
                        ((1UL << (lane->units * 8)) - 1UL);
                    if (cell_value < 0 || cell_value > cell_limit) {
                        la_bound(ctx, LA_ERR_ACCESS_WIDTH, record->line,
                                 text.length, text, la_text("table cell"),
                                 cell_value, cell_limit);
                        return 0;
                    }
                    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION,
                                  line, 1);
                    event.operation = LA_TARGET_OP_TABLE_ROW;
                    event.strategy = strategy_index;
                    event.lane = lane_index;
                    event.access_width = lane->units;
                    event.signed_value = cell_value;
                    if (!la_write_event(ctx, &event)) return 0;
                }
            }
        }
    }
    return 1;
}

/* pool tables NAME - emit the pool's address tables from its base,
   stride and count, at this statement's position. One table per lane of
   the declared pool strategy, labelled by the pool's own table names;
   the rows are the strategy's, so the base need only resolve for the
   downstream assembler. */
int la_emit_pool_tables(LaContext *ctx, const char *start,
                               const char *end, la_u16 line)
{
    const char *cursor;
    const char *name_start;
    la_u16 name_length;
    la_u16 pool_index;
    la_u8 lane_index;
    la_u8 strategy_index;
    const LaStrategyDesc *strategy;
    LaPoolRec *pool;
    LaEvent event;
    cursor = la_trim_left(start, end) + 4;
    cursor = la_trim_left(cursor, end);
    if (!la_take_word(&cursor, end, "tables")) return 0;
    cursor = la_trim_left(cursor, end);
    if (!la_read_identifier(&cursor, end, &name_start, &name_length) ||
        la_trim_left(cursor, end) != end) {
        la_reject(ctx, LA_ERR_SYNTAX, line, la_text("pool tables NAME"));
        return -1;
    }
    pool_index = la_find_pool_text(ctx, name_start, name_length);
    if (pool_index == LA_INVALID_HANDLE) {
        la_reject_at(ctx, LA_ERR_UNKNOWN_POOL, line, name_length,
                     la_slice(name_start, name_length), la_text(""));
        return -1;
    }
    pool = &ctx->pools[pool_index];
    {
        int selected;
        selected = la_default_strategy(ctx, LA_STRATEGY_POOL_TABLE);
        /* The declaration names one label per lane, so a strategy with a
           different lane count cannot emit this pool. */
        if (selected < 0 ||
            ctx->target->strategies[selected].lane_count != 2) {
            la_reject_at(ctx, LA_ERR_POOL_STRATEGY, line, name_length,
                         la_slice(name_start, name_length),
                         la_text("no declared strategy"));
            return -1;
        }
        strategy_index = (la_u8)selected;
        strategy = &ctx->target->strategies[strategy_index];
    }
    for (lane_index = 0; lane_index < strategy->lane_count; ++lane_index) {
        LaSlice base;
        la_u16 slot;
        base = la_name_slice(ctx, pool->base);
        if (!la_emit_strategy_label(
                ctx, line, strategy_index, lane_index,
                la_name_slice(ctx, lane_index == 0 ? pool->table_low :
                                                     pool->table_high))) {
            return -1;
        }
        for (slot = 0; slot < pool->count; ++slot) {
            la_u32 offset;
            offset = (la_u32)slot * (la_u32)pool->stride;
            if (offset > 65535UL) {
                la_bound(ctx, LA_ERR_POOL_STRATEGY, line, name_length,
                         la_slice(name_start, name_length),
                         la_text("pool table row"), (la_i32)offset, 65535);
                return -1;
            }
            la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
            event.operation = LA_TARGET_OP_TABLE_ROW;
            event.strategy = strategy_index;
            event.lane = lane_index;
            event.base = base;
            event.value = (la_u16)offset;
            event.access_width = strategy->lanes[lane_index].units;
            if (!la_write_event(ctx, &event)) return -1;
        }
    }
    return 1;
}

int la_parse_procedure_data(LaContext *ctx,
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
                la_text("procedure address"), la_text(""), 0, 0);
        return -1;
    }
    while (cursor < end) {
        const char *part_start;
        const char *name_start;
        la_u16 part_length;
        la_u16 name_length;
        la_u16 procedure;
        LaTargetOperationKind operation;
        la_u8 strategy;
        la_u8 lane;
        int is_private;
        strategy = 0;
        lane = 0;
        if (is_code_pointer) {
            operation = LA_TARGET_OP_DATA_CODEPTR;
            if (!la_read_qualified_identifier(
                    &cursor, end, &name_start, &name_length)) {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_text("procedure"), la_text(""), 0, 0);
                return -1;
            }
            part_start = type_start;
            part_length = type_length;
        } else {
            operation = LA_TARGET_OP_DISPATCH_ENTRY;
            if (!la_read_identifier(
                    &cursor, end, &part_start, &part_length)) {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_strategy_selectors(
                            ctx, LA_STRATEGY_DISPATCH_TABLE),
                        la_text(""), 0, 0);
                return -1;
            }
            /* The part spelling selects a dispatch lane; the description
               owns which spellings exist and what each one emits. */
            if (la_strategy_lane(ctx, LA_STRATEGY_DISPATCH_TABLE,
                                 part_start, part_length,
                                 &strategy, &lane) < 0) {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, part_length,
                        la_slice(part_start, part_length),
                        la_strategy_selectors(
                            ctx, LA_STRATEGY_DISPATCH_TABLE), 0, 0);
                return -1;
            }
            cursor = la_trim_left(cursor, end);
            if (cursor >= end || *cursor++ != '(' ||
                !la_read_qualified_identifier(
                    &cursor, end, &name_start, &name_length)) {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_text("part(PROCEDURE)"),
                        la_text(""), 0, 0);
                return -1;
            }
            cursor = la_trim_left(cursor, end);
            if (cursor >= end || *cursor++ != ')') {
                la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                        la_text(")"), la_text(""), 0, 0);
                return -1;
            }
        }
        /* The declared width must be the lane's row width: `data u8` is
           a one-unit lane, `data u16` a two-unit one. */
        if (!is_code_pointer &&
            ctx->target->strategies[strategy].lanes[lane].units !=
                (type_length == 2 ? 1 : 2)) {
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
                    la_text(""), 0, 0);
            return -1;
        }
        if (is_private) {
            la_fail(ctx, LA_ERR_PRIVATE_NAME, line, 1, name_length,
                    la_name_slice(ctx, ctx->procedures[procedure].name),
                    la_text("export"), 0, 0);
            return -1;
        }
        if (ctx->procedures[procedure].is_inline) {
            /* An inline procedure has no emitted body and no address. */
            la_fail(ctx, LA_ERR_INLINE_BODY, line, 1, name_length,
                    la_name_slice(ctx, ctx->procedures[procedure].name),
                    la_text("inline has no address"), 0, 0);
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
            event.strategy = strategy;
            event.lane = lane;
            event.access_width =
                is_code_pointer ?
                    ctx->target->code_pointer_units :
                    ctx->target->strategies[strategy].lanes[lane].units;
            event.byte_order = is_code_pointer ?
                ctx->target->code_pointer_byte_order :
                ctx->target->byte_order;
            if (!la_write_event(ctx, &event)) return -1;
        }
        cursor = la_trim_left(cursor, end);
        if (cursor == end) break;
        if (*cursor++ != ',') {
            la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                    la_text(","), la_text(""), 0, 0);
            return -1;
        }
        cursor = la_trim_left(cursor, end);
    }
    return 1;
}

LaDiagnosticCode la_validate_procedure_data(LaContext *ctx)
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
