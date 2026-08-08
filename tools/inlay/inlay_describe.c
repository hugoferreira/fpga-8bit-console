/* Inlay core: The core's view of the target description: registers and their
   roles, the spellings each family claims, the data strategies. */

#include "inlay_internal.h"

static int la_lane_claims(const char *selectors, const char *text,
                          la_u16 length);
static LaSlice la_operation_token(const char *start, const char *end);

/* Does a lane's selector list claim this spelling? */
static int la_lane_claims(const char *selectors, const char *text,
                          la_u16 length)
{
    const char *cursor;
    cursor = selectors;
    while (*cursor != 0) {
        const char *start;
        start = cursor;
        while (*cursor != 0 && *cursor != ' ') ++cursor;
        if ((la_u16)(cursor - start) == length && length != 0 &&
            memcmp(start, text, length) == 0) return 1;
        while (*cursor == ' ') ++cursor;
    }
    return 0;
}

/* The description's default strategy of a kind, or -1 when the target
   declares none - a table of that kind is then unsupported. */
int la_default_strategy(LaContext *ctx, la_u8 kind)
{
    la_u8 index;
    for (index = 0; index < ctx->target->strategy_count; ++index) {
        if (ctx->target->strategies[index].kind == kind &&
            ctx->target->strategies[index].is_default) return (int)index;
    }
    return -1;
}

/* The lane a declaration site selects by spelling, over every strategy
   of a kind. Returns -1 when no lane claims the spelling. */
int la_strategy_lane(LaContext *ctx, la_u8 kind, const char *text,
                            la_u16 length, la_u8 *strategy, la_u8 *lane)
{
    la_u8 index;
    for (index = 0; index < ctx->target->strategy_count; ++index) {
        const LaStrategyDesc *desc;
        la_u8 slot;
        desc = &ctx->target->strategies[index];
        if (desc->kind != kind) continue;
        for (slot = 0; slot < desc->lane_count; ++slot) {
            if (la_lane_claims(desc->lanes[slot].selectors, text, length)) {
                *strategy = index;
                *lane = slot;
                return 0;
            }
        }
    }
    return -1;
}

/* The spellings a kind's lanes claim, comma-separated, for the
   diagnostic that rejects an unclaimed one. */
LaSlice la_strategy_selectors(LaContext *ctx, la_u8 kind)
{
    la_u16 length;
    la_u8 index;
    length = 0;
    for (index = 0; index < ctx->target->strategy_count; ++index) {
        const LaStrategyDesc *desc;
        la_u8 slot;
        desc = &ctx->target->strategies[index];
        if (desc->kind != kind) continue;
        for (slot = 0; slot < desc->lane_count; ++slot) {
            const char *cursor;
            cursor = desc->lanes[slot].selectors;
            if (*cursor == 0) continue;
            while (*cursor != 0) {
                if (*cursor == ' ') {
                    ctx->path_buffer[length++] = ',';
                    ctx->path_buffer[length++] = ' ';
                } else {
                    ctx->path_buffer[length++] = *cursor;
                }
                ++cursor;
                if (length + 2 >= ctx->limits->max_line_bytes) break;
            }
            if (*cursor == 0 && length != 0 &&
                length + 2 < ctx->limits->max_line_bytes) {
                ctx->path_buffer[length++] = ',';
                ctx->path_buffer[length++] = ' ';
            }
        }
    }
    if (length >= 2) length = (la_u16)(length - 2);
    return la_slice(ctx->path_buffer, length);
}

/* Register names and roles come from the target description; the core
   names no register itself. */
int la_register_lookup(const LaContext *ctx, LaSlice slice)
{
    la_u8 index;
    for (index = 0; index < ctx->target->register_count; ++index) {
        const char *name;
        name = ctx->target->registers[index].name;
        if (slice.length == (la_u16)strlen(name) &&
            memcmp(slice.data, name, slice.length) == 0) {
            return (int)index;
        }
    }
    return -1;
}

int la_slice_is_register(const LaContext *ctx, LaSlice slice)
{
    return la_register_lookup(ctx, slice) >= 0;
}

/* Append to the diagnostic scratch buffer, bounded by the line limit;
   diagnostics whose text is composed from the description build here. */
la_u16 la_append_text(LaContext *ctx, la_u16 length,
                             const char *text)
{
    la_u16 amount;
    amount = (la_u16)strlen(text);
    if (length + amount >= ctx->limits->max_line_bytes) return length;
    memcpy(ctx->path_buffer + length, text, amount);
    return (la_u16)(length + amount);
}

/* The accumulator role's name: the register memory reads pass through,
   which the marshalling events report as their scratch. */
LaSlice la_accumulator_slice(const LaContext *ctx)
{
    la_u8 index;
    for (index = 0; index < ctx->target->register_count; ++index) {
        if (ctx->target->registers[index].role == LA_REGISTER_ACCUMULATOR) {
            return la_slice(
                ctx->target->registers[index].name,
                (la_u16)strlen(ctx->target->registers[index].name));
        }
    }
    return la_text("");
}

/* Does this register declare the use a form requires? */
int la_register_allows(const LaContext *ctx, LaSlice slice,
                              la_u8 use)
{
    int index;
    index = la_register_lookup(ctx, slice);
    return index >= 0 &&
           (ctx->target->registers[index].uses & use) == use;
}

/* The declared register names carrying a use, comma-separated, for the
   diagnostics that reject a register no form admits. Use 0 for all. */
LaSlice la_register_names(LaContext *ctx, la_u8 use)
{
    la_u16 length;
    la_u8 index;
    length = 0;
    for (index = 0; index < ctx->target->register_count; ++index) {
        const char *name;
        la_u16 name_length;
        if ((ctx->target->registers[index].uses & use) != use) continue;
        name = ctx->target->registers[index].name;
        name_length = (la_u16)strlen(name);
        if (length + name_length + 2 >= ctx->limits->max_line_bytes) break;
        if (length != 0) {
            ctx->path_buffer[length++] = ',';
            ctx->path_buffer[length++] = ' ';
        }
        memcpy(ctx->path_buffer + length, name, name_length);
        length = (la_u16)(length + name_length);
    }
    return la_slice(ctx->path_buffer, length);
}

int la_slice_is_accumulator(const LaContext *ctx, LaSlice slice)
{
    int index;
    index = la_register_lookup(ctx, slice);
    return index >= 0 &&
           ctx->target->registers[index].role == LA_REGISTER_ACCUMULATOR;
}

/* The spelling a family claims, or 0 when the description declares
   none. A family with one claimant names a word the core reads but
   never emits. */
const char *la_family_spelling(LaContext *ctx, la_u16 family)
{
    la_u16 index;
    for (index = 0; index < ctx->target->spelling_count; ++index) {
        if (ctx->target->spellings[index].family == family) {
            return ctx->target->spellings[index].spelling;
        }
    }
    return 0;
}

/* Step over the operation-position token the dispatcher already matched
   against the description, lexed the same way. */
const char *la_skip_spelling(const char *start, const char *end)
{
    const char *cursor;
    cursor = la_trim_left(start, end);
    while (cursor < end && (la_is_ident(*cursor) || *cursor == '.')) {
        ++cursor;
    }
    return cursor;
}

/* The operation-position token, lexed as the dispatcher lexes it. */
static LaSlice la_operation_token(const char *start, const char *end)
{
    const char *first;
    first = la_trim_left(start, end);
    return la_slice(first, (la_u16)(la_skip_spelling(first, end) - first));
}

/* The operation this line's spelling names inside a family, or 0 when
   the description claims the spelling for no such family. */
la_u8 la_claimed_operation(LaContext *ctx, const char *start,
                                  const char *end, la_u16 family)
{
    LaSlice token;
    la_u16 index;
    token = la_operation_token(start, end);
    for (index = 0; index < ctx->target->spelling_count; ++index) {
        const LaSpellingDesc *entry;
        entry = &ctx->target->spellings[index];
        if (entry->family != family) continue;
        if (la_equal_text(token.data, token.length, entry->spelling)) {
            return entry->operation;
        }
    }
    return 0;
}

/* Physical registers are reserved spellings that always win over any symbol,
   so a namespace member named `x`/`y`/`a` must be referenced explicitly. */
int la_is_target_register(LaContext *ctx, const char *text,
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
