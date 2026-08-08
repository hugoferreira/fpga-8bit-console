/* The console6502 target description: every target-specific fact
   the frontend consumes, and nothing else. */

#include "inlay_internal.h"

/* BEGIN TARGET DESCRIPTION console6502
   Everything between these markers is the console6502 description: the
   only place in this file where a register name, an operation spelling
   or emitted instruction text may appear. Conformance enforces that. */

static const LaConvention la_console6502_conventions[] = {
    {"console6502", {"a", "x", "y", 0}, 3, "a"}
};

static const LaRegisterDesc la_console6502_registers[] = {
    {"a", LA_REGISTER_ACCUMULATOR, 0},
    {"x", LA_REGISTER_INDEX,
     LA_REGISTER_POINTER_INDEX | LA_REGISTER_ABSOLUTE_INDEX},
    {"y", LA_REGISTER_INDEX, LA_REGISTER_ABSOLUTE_INDEX}
};

static const LaSpellingDesc la_console6502_spellings[] = {
    {"mov",  LA_SPELL_OFFSET_MATERIALIZE,
     LA_TARGET_OP_MATERIALIZE_FIELD_OFFSET},
    {"mov",  LA_SPELL_QUALIFIED_IMMEDIATE, LA_TARGET_OP_VALUE_MOV},
    {"mov",  LA_SPELL_OVERLAY_STORE_IMM, LA_TARGET_OP_STORE_IMM_OVERLAY_ABS},
    {"mov",  LA_SPELL_FRAME_POINTER_MOVE, LA_TARGET_OP_STORE_PTR_FRAME},
    {"offset", LA_SPELL_OFFSET_KEYWORD, 0},
    {"cmp",  LA_SPELL_VALUE_COMPARE, LA_TARGET_OP_VALUE_CMP},
    {"cmp",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_CMP8_OVERLAY_DISP},
    {"lda",  LA_SPELL_LOCAL_OPERATION, LA_TARGET_OP_LOAD8_FRAME_LOCAL},
    {"lda",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_LOAD8_PTR_DISP},
    {"sta",  LA_SPELL_LOCAL_OPERATION, LA_TARGET_OP_STORE8_FRAME_LOCAL},
    {"sta",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_STORE8_PTR_DISP},
    {"stx",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_STOREX_OVERLAY_DISP},
    {"sty",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_STOREY_OVERLAY_DISP},
    {"ldx",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_LOADX_OVERLAY_DISP},
    {"ldy",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_LOADY_OVERLAY_DISP},
    {"add",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_ADD8A_OVERLAY_DISP},
    {"sub",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_SUB8A_OVERLAY_DISP},
    {"adc",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_ADC8_OVERLAY_INDEXED},
    {"sbc",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_SBC8_OVERLAY_INDEXED},
    {"and",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_AND8A_OVERLAY_DISP},
    {"and",  LA_SPELL_BYTE_RMW, LA_TARGET_OP_AND8_PTR_DISP},
    {"ora",  LA_SPELL_TYPED_OPERATION, LA_TARGET_OP_ORA8A_OVERLAY_DISP},
    {"ora",  LA_SPELL_BYTE_RMW, LA_TARGET_OP_OR8_PTR_DISP},
    {"inc",  LA_SPELL_BYTE_RMW, LA_TARGET_OP_INC8_PTR_DISP},
    {"dec",  LA_SPELL_BYTE_RMW, LA_TARGET_OP_DEC8_PTR_DISP},
    {"ldw",  LA_SPELL_WORD_TRANSFER, LA_TARGET_OP_LOAD16_PTR_DISP},
    {"stw",  LA_SPELL_WORD_TRANSFER, LA_TARGET_OP_STORE16_PTR_DISP},
    {"addw", LA_SPELL_WORD_ARITHMETIC, LA_TARGET_OP_ADD16_PHYSICAL},
    {"subw", LA_SPELL_WORD_ARITHMETIC, LA_TARGET_OP_SUB16_PHYSICAL},
    {"cmpw", LA_SPELL_WORD_ARITHMETIC, LA_TARGET_OP_CMP16_PHYSICAL},
    {"decz", LA_SPELL_OBSERVATION, LA_TARGET_OP_DECZ8_PTR_DISP},
    {"tstw", LA_SPELL_OBSERVATION, LA_TARGET_OP_TSTW_PTR_DISP},
    {"movw", LA_SPELL_WORD_MOVE, LA_TARGET_OP_MOVW_LOCATION},
    {"cbeq", LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP},
    {"cbne", LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP},
    {"cblt", LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP},
    {"cble", LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP},
    {"cbgt", LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP},
    {"cbge", LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP},
    {"tbz",  LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP},
    {"tbnz", LA_SPELL_OVERLAY_BRANCH, LA_TARGET_OP_BRANCH_OVERLAY_DISP}
};

static const char *const la_c6502_decz[] = {
    "    lda (%b), #%d",
    "    beq %a",
    "    sub #1",
    "    sta (%b), #%d ; inlay decz %o.%p",
    0
};
static const char *const la_c6502_tstw_ptr[] = {
    "    ldy #%d",
    "    lda (%b), y",
    "    iny",
    "    ora (%b), y ; inlay tstw %o.%p",
    0
};
static const char *const la_c6502_tstw_loc[] = {
    "    lda %b",
    "    ora %b+1 ; inlay tstw %o",
    0
};
static const char *const la_c6502_movw_imm[] = {
    "    lda #%l",
    "    sta %b",
    "    lda #%h",
    "    sta %b+1 ; inlay movw %o",
    0
};
static const char *const la_c6502_movw_loc[] = {
    "    lda %a",
    "    sta %b",
    "    lda %a+1",
    "    sta %b+1 ; inlay movw %o",
    0
};
static const char *const la_c6502_stw_imm[] = {
    "    lda #%l",
    "    sta (%b), #%d",
    "    lda #%h",
    "    sta (%b), #%D ; inlay stw %o.%p",
    0
};
static const char *const la_c6502_inc8[] = {
    "    lda (%b), #%d",
    "    add #1",
    "    sta (%b), #%d ; inlay update %o.%p",
    0
};
static const char *const la_c6502_dec8[] = {
    "    lda (%b), #%d",
    "    sub #1",
    "    sta (%b), #%d ; inlay update %o.%p",
    0
};
static const char *const la_c6502_and8[] = {
    "    lda (%b), #%d",
    "    and #%i",
    "    sta (%b), #%d ; inlay update %o.%p",
    0
};
static const char *const la_c6502_or8[] = {
    "    lda (%b), #%d",
    "    ora #%i",
    "    sta (%b), #%d ; inlay update %o.%p",
    0
};

static const char *const la_c6502_load8_ptr[] = {
    "    lda (%b), #%m ; inlay %o.%p", 0
};
static const char *const la_c6502_store8_ptr[] = {
    "    sta (%b), #%m ; inlay %o.%p", 0
};
static const char *const la_c6502_load8_overlay[] = {
    "    lda %b + %m ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_store8_overlay[] = {
    "    sta %b + %m ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_load16_ptr[] = {
    "    lda (%b), #%d ; inlay %o.%p[0]",
    "    sta %a",
    "    lda (%b), #%D ; inlay %o.%p[1]",
    "    sta %a+1",
    0
};
static const char *const la_c6502_store16_ptr[] = {
    "    lda %a",
    "    sta (%b), #%d ; inlay %o.%p[0]",
    "    lda %a+1",
    "    sta (%b), #%D ; inlay %o.%p[1]",
    0
};
static const char *const la_c6502_addw[] = { "    addw %a", 0 };
static const char *const la_c6502_subw[] = { "    subw %a", 0 };
static const char *const la_c6502_cmpw[] = { "    cmpw %a", 0 };
static const char *const la_c6502_offset_mat[] = {
    "    ld%b #%d ; inlay offset %o.%p", 0
};
static const char *const la_c6502_load8_ovl_indexed[] = {
    "    lda %b + %d, %x ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_store8_ovl_indexed[] = {
    "    sta %b + %d, %x ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_adc8_ovl_indexed[] = {
    "    adc %b + %d, %x ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_sbc8_ovl_indexed[] = {
    "    sbc %b + %d, %x ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_pool_address[] = {
    "    tax",
    "    mov %b, %a + x",
    "    lda %c, x",
    "    sta %b+1",
    0
};
static const char *const la_c6502_invoke_call[] = { "    jsr %q", 0 };
static const char *const la_c6502_invoke_tail[] = { "    jmp %q", 0 };
static const char *const la_c6502_data_codeptr[] = {
    "    #d8 (%q)[7:0], (%q)[15:8]", 0
};
static const char *const la_c6502_value_cmp[] = { "    cmp #%v", 0 };
static const char *const la_c6502_overlay_branch[] = {
    "    %s %b + %d, %t ; inlay branch %o.%p", 0
};
static const char *const la_c6502_overlay_store_imm[] = {
    "    mov %b + %d, %t ; inlay store %o.%p", 0
};
static const char *const la_c6502_overlay_cmp[] = {
    "    cmp %b + %d ; inlay compare %o.%p", 0
};
static const char *const la_c6502_ovl_stx[] = {
    "    stx %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_sty[] = {
    "    sty %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_and[] = {
    "    and %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_ora[] = {
    "    ora %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_ldx[] = {
    "    ldx %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_ldy[] = {
    "    ldy %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_add[] = {
    "    add %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_sub[] = {
    "    sub %b + %d ; inlay overlay %o.%p", 0
};
static const char *const la_c6502_ovl_inc[] = {
    "    inc %b + %d ; inlay update %o.%p", 0
};
static const char *const la_c6502_ovl_dec[] = {
    "    dec %b + %d ; inlay update %o.%p", 0
};
static const char *const la_c6502_ovl_and_abs[] = {
    "    lda %b + %d",
    "    and #%i",
    "    sta %b + %d ; inlay update %o.%p",
    0
};
static const char *const la_c6502_ovl_or_abs[] = {
    "    lda %b + %d",
    "    ora #%i",
    "    sta %b + %d ; inlay update %o.%p",
    0
};
static const char *const la_c6502_overlay_address[] = {
    "    mov %b, #<(%a + %d)",
    "    mov %b+1, #>(%a + %d) ; inlay address %o.%p",
    0
};
static const char *const la_c6502_proc_naked[] = { "%q:", 0 };
static const char *const la_c6502_proc_frame[] = {
    "%q:",
    "*@frame-prologue@    pha",
    0
};
static const char *const la_c6502_proc_return[] = {
    "?    tsx",
    "*    inx",
    "?    txs",
    "@procedure-return@    rts",
    0
};
static const char *const la_c6502_frame_load[] = {
    "    tsx",
    "    lda %F, x ; inlay local %p",
    0
};
static const char *const la_c6502_frame_store[] = {
    "    tsx",
    "    sta %F, x ; inlay local %p",
    0
};
static const char *const la_c6502_frame_ptr_store[] = {
    "    tsx",
    "    lda %b",
    "    sta %F, x",
    "    lda %b+1",
    "    sta %G, x",
    0
};
static const char *const la_c6502_frame_ptr_load[] = {
    "    tsx",
    "    lda %F, x",
    "    sta %b",
    "    lda %G, x",
    "    sta %b+1",
    0
};

static const LaLoweringDesc la_console6502_lowerings[] = {
    {LA_TARGET_OP_LOAD8_PTR_DISP, "target-operation",
     la_c6502_load8_ptr, 0, 0},
    {LA_TARGET_OP_STORE8_PTR_DISP, "target-operation",
     la_c6502_store8_ptr, 0, 0},
    {LA_TARGET_OP_LOAD8_OVERLAY_DISP, "overlay-operation",
     la_c6502_load8_overlay, 0, 0},
    {LA_TARGET_OP_STORE8_OVERLAY_DISP, "overlay-operation",
     la_c6502_store8_overlay, 0, 0},
    {LA_TARGET_OP_LOAD16_PTR_DISP, "word-field-load",
     la_c6502_load16_ptr, "a", "a,flags"},
    {LA_TARGET_OP_STORE16_PTR_DISP, "word-field-store",
     la_c6502_store16_ptr, "a", "a,flags"},
    {LA_TARGET_OP_ADD16_PHYSICAL, "physical-word-arithmetic",
     la_c6502_addw, 0, "ab,n,v,z,c"},
    {LA_TARGET_OP_SUB16_PHYSICAL, "physical-word-arithmetic",
     la_c6502_subw, 0, "ab,n,v,z,c"},
    {LA_TARGET_OP_CMP16_PHYSICAL, "physical-word-arithmetic",
     la_c6502_cmpw, 0, "n,z,c"},
    {LA_TARGET_OP_MATERIALIZE_FIELD_OFFSET, "field-offset",
     la_c6502_offset_mat, 0, 0},
    {LA_TARGET_OP_LOAD8_OVERLAY_INDEXED, "overlay-indexed-operation",
     la_c6502_load8_ovl_indexed, 0, 0},
    {LA_TARGET_OP_STORE8_OVERLAY_INDEXED, "overlay-indexed-operation",
     la_c6502_store8_ovl_indexed, 0, 0},
    {LA_TARGET_OP_ADC8_OVERLAY_INDEXED, "overlay-indexed-operation",
     la_c6502_adc8_ovl_indexed, 0, "a,flags"},
    {LA_TARGET_OP_SBC8_OVERLAY_INDEXED, "overlay-indexed-operation",
     la_c6502_sbc8_ovl_indexed, 0, "a,flags"},
    {LA_TARGET_OP_ADDRESS_POOL_TABLE, "pool-address",
     la_c6502_pool_address, 0, 0},
    {LA_TARGET_OP_INVOKE_CALL, "invoke-call", la_c6502_invoke_call, 0, 0},
    {LA_TARGET_OP_INVOKE_TAIL, "invoke-call", la_c6502_invoke_tail, 0, 0},
    {LA_TARGET_OP_DATA_CODEPTR, "procedure-address",
     la_c6502_data_codeptr, 0, 0},
    {LA_TARGET_OP_VALUE_CMP, "qualified-immediate", la_c6502_value_cmp, 0, 0},
    {LA_TARGET_OP_BRANCH_OVERLAY_DISP, "overlay-branch",
     la_c6502_overlay_branch, 0, 0},
    {LA_TARGET_OP_STORE_IMM_OVERLAY_ABS, "overlay-store-source",
     la_c6502_overlay_store_imm, 0, 0},
    {LA_TARGET_OP_CMP8_OVERLAY_DISP, "overlay-compare",
     la_c6502_overlay_cmp, "", "flags"},
    {LA_TARGET_OP_STOREX_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_stx, "", ""},
    {LA_TARGET_OP_STOREY_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_sty, "", ""},
    {LA_TARGET_OP_AND8A_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_and, "", "flags"},
    {LA_TARGET_OP_ORA8A_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_ora, "", "flags"},
    {LA_TARGET_OP_LOADX_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_ldx, "", "flags"},
    {LA_TARGET_OP_LOADY_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_ldy, "", "flags"},
    {LA_TARGET_OP_ADD8A_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_add, "", "flags"},
    {LA_TARGET_OP_SUB8A_OVERLAY_DISP, "overlay-operation",
     la_c6502_ovl_sub, "", "flags"},
    {LA_TARGET_OP_INC8_OVERLAY_ABS, "overlay-update",
     la_c6502_ovl_inc, "", "flags"},
    {LA_TARGET_OP_DEC8_OVERLAY_ABS, "overlay-update",
     la_c6502_ovl_dec, "", "flags"},
    {LA_TARGET_OP_AND8_OVERLAY_ABS, "overlay-update",
     la_c6502_ovl_and_abs, "a", "a,flags"},
    {LA_TARGET_OP_OR8_OVERLAY_ABS, "overlay-update",
     la_c6502_ovl_or_abs, "a", "a,flags"},
    {LA_TARGET_OP_ADDRESS_OVERLAY_FIELD, "overlay-address",
     la_c6502_overlay_address, 0, 0},
    {LA_TARGET_OP_PROC_NAKED, "procedure", la_c6502_proc_naked, 0, 0},
    {LA_TARGET_OP_PROC_FRAME, "procedure", la_c6502_proc_frame, 0, 0},
    {LA_TARGET_OP_PROC_RETURN, "frame-epilogue", la_c6502_proc_return, 0, 0},
    {LA_TARGET_OP_LOAD8_FRAME_LOCAL, "frame-local",
     la_c6502_frame_load, "a", "a,flags"},
    {LA_TARGET_OP_STORE8_FRAME_LOCAL, "frame-local",
     la_c6502_frame_store, "a", "a,flags"},
    {LA_TARGET_OP_STORE_PTR_FRAME, "frame-pointer",
     la_c6502_frame_ptr_store, 0, 0},
    {LA_TARGET_OP_LOAD_PTR_FRAME, "frame-pointer",
     la_c6502_frame_ptr_load, 0, 0},
    {LA_TARGET_OP_DECZ8_PTR_DISP, "byte-field-decz",
     la_c6502_decz, "a", "a,flags"},
    {LA_TARGET_OP_TSTW_PTR_DISP, "word-field-test",
     la_c6502_tstw_ptr, "a,y", "a,y,flags"},
    {LA_TARGET_OP_TSTW_LOCATION, "word-location-test",
     la_c6502_tstw_loc, "a", "a,flags"},
    {LA_TARGET_OP_MOVW_IMM, "word-move", la_c6502_movw_imm, 0, 0},
    {LA_TARGET_OP_MOVW_LOCATION, "word-move", la_c6502_movw_loc, 0, 0},
    {LA_TARGET_OP_STORE16_IMM_PTR_DISP, "word-field-immediate",
     la_c6502_stw_imm, "a", "a,flags"},
    {LA_TARGET_OP_INC8_PTR_DISP, "byte-field-update",
     la_c6502_inc8, "a", "a,flags"},
    {LA_TARGET_OP_DEC8_PTR_DISP, "byte-field-update",
     la_c6502_dec8, "a", "a,flags"},
    {LA_TARGET_OP_AND8_PTR_DISP, "byte-field-update",
     la_c6502_and8, "a", "a,flags"},
    {LA_TARGET_OP_OR8_PTR_DISP, "byte-field-update", la_c6502_or8,
     "a", "a,flags"}
};

/* Strategy templates. A table label takes the composed name in %b; a
   dispatch row takes the procedure symbol in %q; a pool row takes the
   pool base in %b and the slot's byte offset in %d; a value row takes
   the cell in %v. */
static const char *const la_c6502_table_label[] = {
    "@table-label@%b:", 0
};
static const char *const la_c6502_dispatch_low[] = {
    "    #d8 (%q)[7:0]", 0
};
static const char *const la_c6502_dispatch_high[] = {
    "    #d8 (%q)[15:8]", 0
};
static const char *const la_c6502_dispatch_word[] = { "    #d16 %q", 0 };
static const char *const la_c6502_hole8[] = { "    #d8 0", 0 };
static const char *const la_c6502_hole16[] = { "    #d16 0", 0 };
static const char *const la_c6502_value_row[] = { "    #d8 %v", 0 };
static const char *const la_c6502_pool_low[] = {
    "    #d8 (%b+%d)[7:0]", 0
};
static const char *const la_c6502_pool_high[] = {
    "    #d8 (%b+%d)[15:8]", 0
};

static const LaStrategyLane la_c6502_split_lanes[] = {
    {"low", "_lo", 1, la_c6502_dispatch_low, la_c6502_hole8},
    {"high", "_hi", 1, la_c6502_dispatch_high, la_c6502_hole8}
};
static const LaStrategyLane la_c6502_word_lanes[] = {
    {"addr full", "", 2, la_c6502_dispatch_word, la_c6502_hole16}
};
static const LaStrategyLane la_c6502_value_lanes[] = {
    {"", "", 1, la_c6502_value_row, 0}
};
static const LaStrategyLane la_c6502_pool_lanes[] = {
    {"", "", 1, la_c6502_pool_low, 0},
    {"", "", 1, la_c6502_pool_high, 0}
};

/* Raw spellings the core recognizes but never emits: these move the
   stack pointer, so a procedure with frame locals cannot contain one. */
static const char *const la_c6502_stack_mutators[] = {
    "pha", "pla", "php", "plp", "txs", 0
};
/* A transfer out of an inline body, which cannot expand into a caller
   whose frame is live. */
static const char *const la_c6502_nonlocal_transfers[] = { "jmp", 0 };

static const LaStrategyDesc la_console6502_strategies[] = {
    {LA_STRATEGY_DISPATCH_TABLE, "split-low-high", "procedure-address",
     1, 2, la_c6502_split_lanes, la_c6502_table_label},
    {LA_STRATEGY_DISPATCH_TABLE, "word-per-entry", "procedure-address",
     0, 1, la_c6502_word_lanes, la_c6502_table_label},
    {LA_STRATEGY_VALUE_TABLE, "byte-rows", "table-value",
     1, 1, la_c6502_value_lanes, la_c6502_table_label},
    {LA_STRATEGY_POOL_TABLE, "symbolic-base-offset", "pool-address",
     1, 2, la_c6502_pool_lanes, la_c6502_table_label}
};

const LaTarget la_target_console6502 = {
    "console6502", 8, 2, 255, LA_TARGET_VERSION,
    la_console6502_conventions, 1,
    "t", 8, 0, 0, 16, 1, 1, 1, LA_BYTE_ORDER_LITTLE, "ab", 1, 1, 1,
    2, LA_BYTE_ORDER_LITTLE,
    la_console6502_registers, 3,
    la_console6502_spellings,
    (la_u16)(sizeof(la_console6502_spellings) /
             sizeof(la_console6502_spellings[0])),
    la_console6502_lowerings,
    (la_u16)(sizeof(la_console6502_lowerings) /
             sizeof(la_console6502_lowerings[0])),
    la_console6502_strategies,
    (la_u8)(sizeof(la_console6502_strategies) /
            sizeof(la_console6502_strategies[0])),
    la_c6502_stack_mutators, "rts", la_c6502_nonlocal_transfers
};

/* END TARGET DESCRIPTION console6502 */
