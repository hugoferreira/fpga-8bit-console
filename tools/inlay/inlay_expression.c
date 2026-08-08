/* Inlay core: Constant expressions: the operator table, layout queries,
   evaluation, and the assertions and constants built on them. */

#include "inlay_internal.h"

static int la_precedence(la_u8 op);
static la_u8 la_op_family(la_u8 op);
static int la_family_conflict(la_u8 op_family, la_u8 operand_family);
static LaDiagnosticCode la_apply_operator(LaContext *ctx, la_u8 op,
                                          la_u16 *value_count,
                                          la_u16 line);
static LaDiagnosticCode la_property_value(LaContext *ctx,
                                          const char *text, la_u16 length,
                                          la_u16 line, la_i32 *value);

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

int la_layout_query_suffix(const char *text, la_u16 length,
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
            return la_reject(ctx, LA_ERR_SYNTAX, line,
                             la_text("expression operand"));
        }
        if (la_family_conflict(op_family,
                               ctx->values[*value_count - 1].family)) {
            return la_reject(ctx, LA_ERR_SYNTAX, line,
                             la_text("parenthesized bitwise mix"));
        }
        right = ctx->values[*value_count - 1].value;
        ctx->values[*value_count - 1].value =
            op == LA_OP_NOT ? !right :
            op == LA_OP_BNOT ? (la_i32)~(la_u32)right : -right;
        ctx->values[*value_count - 1].family = op_family;
        return LA_OK;
    }
    if (*value_count < 2) {
        return la_reject(ctx, LA_ERR_SYNTAX, line, la_text("binary operands"));
    }
    if (la_family_conflict(op_family,
                           ctx->values[*value_count - 1].family) ||
        la_family_conflict(op_family,
                           ctx->values[*value_count - 2].family)) {
        return la_reject(ctx, LA_ERR_SYNTAX, line,
                         la_text("parenthesized bitwise mix"));
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
            return la_bound(ctx, LA_ERR_SYNTAX, line, 1,
                            la_text("shift count 0..31"), la_text(""), right,
                            31);
        }
        left = op == LA_OP_SHL ?
            (la_i32)((la_u32)left << right) :
            (la_i32)((la_u32)left >> right);
        break;
    case LA_OP_DIV:
        if (right == 0) {
            return la_reject(ctx, LA_ERR_SYNTAX, line,
                             la_text("division by zero"));
        }
        left /= right;
        break;
    case LA_OP_MOD:
        if (right == 0) {
            return la_reject(ctx, LA_ERR_SYNTAX, line,
                             la_text("modulo by zero"));
        }
        left %= right;
        break;
    default:
        return la_bound(ctx, LA_ERR_SYNTAX, line, 1, la_text("operator"),
                        la_text(""), op, 0);
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
            return la_reject_at(ctx, LA_ERR_PRIVATE_NAME, line, length,
                                la_name_slice(ctx, constant->name),
                                la_text("export"));
        }
        if (!constant->resolved) {
            return la_reject_at(ctx, LA_ERR_UNKNOWN_CONSTANT, line, length,
                                la_name_slice(ctx, constant->name),
                                la_text("unresolved or forward constant"));
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
        return la_reject_at(ctx, LA_ERR_BAD_PROPERTY, line, length,
                            la_slice(text, length), la_text(""));
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
                    return la_reject_at(ctx, LA_ERR_ENUM_VALUE, line, length,
                        la_slice(text, length),
                        la_text("unresolved or forward enum member"));
                }
                *value = member->value;
                return LA_OK;
            }
        }
        return la_reject_at(ctx, LA_ERR_ENUM_VALUE, line, length,
                            la_slice(text, length), la_name_slice(ctx,
                            enumeration->name));
    }
    if (first_dot == last_dot) {
        la_u16 table_index;
        for (table_index = 0; table_index < ctx->method_table_count;
             ++table_index) {
            LaSlice table_name;
            table_name = la_name_slice(
                ctx, ctx->method_tables[table_index].name);
            if (table_name.length == (la_u16)(first_dot - text) &&
                memcmp(table_name.data, text, table_name.length) == 0) {
                if (la_equal_text(first_dot + 1,
                                  (la_u16)(text + length - first_dot - 1),
                                  "bias")) {
                    *value = ctx->enum_members[
                        ctx->method_tables[table_index].low].value;
                    return LA_OK;
                }
                return la_reject_at(ctx, LA_ERR_BAD_PROPERTY, line, length,
                                    la_slice(text, length), table_name);
            }
        }
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
        return la_reject_at(ctx, LA_ERR_BAD_PROPERTY, line, property.length,
                            property, la_name_slice(ctx,
                            ctx->pools[pool_index].name));
    }
    sid = la_find_struct_text(ctx, text, (la_u16)(first_dot - text));
    if (sid == LA_INVALID_HANDLE) {
        return la_reject_at(ctx, LA_ERR_UNKNOWN_TYPE, line, (la_u16)(first_dot
                            - text), la_slice(text, (la_u16)(first_dot -
                            text)), la_text(""));
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
        return la_reject_at(ctx, LA_ERR_BAD_PROPERTY, line, property.length,
                            property, la_name_slice(ctx,
                            ctx->structs[sid].name));
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
                return la_reject_at(ctx, LA_ERR_BAD_PROPERTY, line,
                                    property.length, property,
                                    la_text("scalar field"));
            }
            *value = ctx->fields[field_index].count;
            return LA_OK;
        }
        if (la_equal_text(property.data, property.length, "stride")) {
            if (ctx->fields[field_index].count == 1) {
                return la_reject_at(ctx, LA_ERR_BAD_PROPERTY, line,
                                    property.length, property,
                                    la_text("scalar field"));
            }
            *value = ctx->fields[field_index].size /
                     ctx->fields[field_index].count;
            return LA_OK;
        }
        return la_reject_at(ctx, LA_ERR_BAD_PROPERTY, line, property.length,
                            property, la_text("field property"));
    }
}

LaDiagnosticCode la_eval_expression(LaContext *ctx,
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
                                   la_text("expression nesting"),
                                   la_text(""), op_count + 1,
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
                                   la_text("operators"), la_text(""),
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
                                   la_text("hexadecimal value"),
                                   la_text(""), 0, 0);
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
                            la_text("layout query path"),
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
                               la_text("expression value"),
                               la_slice(cursor, 1), 0, 0);
            }
            if (value_count >= ctx->limits->max_expression_nodes) {
                return la_fail(ctx, LA_ERR_EXPRESSION_CAPACITY, line,
                               (la_u16)(cursor - text + 1), 1,
                               la_text("values"), la_text(""),
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
                               la_text("matching ("), la_text(""),
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
                               la_text("expression operator"),
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
                               la_text("operators"), la_text(""),
                               op_count + 1,
                               ctx->limits->max_expression_nodes);
            }
            ctx->operators[op_count++].op = next_op;
            expect_value = 1;
        }
    }
    if (expect_value || value_count == 0) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_text("complete expression"),
                       la_text(""), 0, 0);
    }
    while (op_count > 0) {
        la_u8 op;
        op = ctx->operators[--op_count].op;
        if (op == LA_OP_LPAREN) {
            return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                           la_text("matching )"), la_text(""),
                           0, 0);
        }
        if (la_apply_operator(ctx, op, &value_count, line) != LA_OK) {
            return ctx->error;
        }
    }
    if (value_count != 1) {
        return la_fail(ctx, LA_ERR_SYNTAX, line, 1, 1,
                       la_text("single expression result"),
                       la_text(""), value_count, 1);
    }
    *result = ctx->values[0].value;
    ctx->expression_family = ctx->values[0].family;
    return LA_OK;
}

LaDiagnosticCode la_check_assertions(LaContext *ctx)
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
                return la_fail(ctx, LA_ERR_ASSERTION, line, (la_u16)(expression
                               - cursor + 1), (la_u16)(content_end -
                               expression), la_slice(expression,
                               (la_u16)(content_end - expression)),
                               la_text(""), value, 1);
            }
        }
    }
    return LA_OK;
}

LaDiagnosticCode la_resolve_constants(LaContext *ctx)
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
