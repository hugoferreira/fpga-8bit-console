#include "inlay.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *source;
    la_u16 length;
    la_u16 offset;
    la_u16 chunk;
} MemoryInput;

typedef struct {
    unsigned long hash;
    unsigned events;
    unsigned properties;
    unsigned members;
    unsigned enum_members;
    unsigned overlays;
    unsigned operations;
    unsigned raw;
    unsigned labels;
    unsigned scoped_raw;
    int saw_hitbox_w;
    int saw_hair;
    int saw_left_a;
    int saw_result_a;
    int saw_frame_offset;
    int saw_first_a;
    int saw_second_x;
    int saw_word_load;
    int saw_word_store;
    int saw_word_add;
    int saw_word_sub;
    int saw_word_compare;
    int saw_byte_increment;
    int saw_byte_decrement;
    int saw_byte_and;
    int saw_byte_or;
    int saw_overlay_indexed_load;
    int saw_overlay_indexed_store;
    int saw_code_pointer_data;
    int saw_overlay_address;
    int saw_overlay_increment;
    int saw_overlay_decrement;
    int saw_overlay_and;
    int saw_overlay_or;
    int saw_overlay_volatile_increment;
    int saw_overlay_compare;
    int saw_overlay_store_immediate;
    int saw_enclosing_resolution;
} TestEvents;

typedef struct {
    LaDiagnostic diagnostic;
    int seen;
} TestDiagnostic;

static int failures;

static LaDiagnosticCode compile_source_target(
    const char *source, la_u16 chunk, LaLimits limits, TestEvents *events,
    TestDiagnostic *diagnostic, LaStats *stats, const LaTarget *target);
static LaDiagnosticCode compile_source(const char *source, la_u16 chunk,
                                       LaLimits limits, TestEvents *events,
                                       TestDiagnostic *diagnostic,
                                       LaStats *stats);
static void expect_error(const char *source, LaLimits limits,
                         LaDiagnosticCode expected, const char *message);

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        ++failures;
    }
}

static int memory_read(void *context, char *destination, la_u16 capacity)
{
    MemoryInput *input;
    la_u16 amount;
    input = (MemoryInput *)context;
    if (input->offset >= input->length) return 0;
    amount = (la_u16)(input->length - input->offset);
    if (amount > capacity) amount = capacity;
    if (input->chunk != 0 && amount > input->chunk) amount = input->chunk;
    memcpy(destination, input->source + input->offset, amount);
    input->offset = (la_u16)(input->offset + amount);
    return amount;
}

static void hash_bytes(unsigned long *hash, const char *data, la_u16 length)
{
    la_u16 index;
    for (index = 0; index < length; ++index) {
        *hash ^= (unsigned char)data[index];
        *hash *= 16777619UL;
    }
}

static int test_event(void *context, const LaEvent *event)
{
    TestEvents *events;
    events = (TestEvents *)context;
    ++events->events;
    events->hash ^= (unsigned long)event->kind;
    events->hash *= 16777619UL;
    events->hash ^= event->value;
    events->hash *= 16777619UL;
    events->hash ^= (unsigned long)event->signed_value;
    events->hash *= 16777619UL;
    events->hash ^= (unsigned long)event->aggregate_kind;
    events->hash *= 16777619UL;
    events->hash ^= (unsigned long)event->layout_policy;
    events->hash *= 16777619UL;
    hash_bytes(&events->hash, event->text.data, event->text.length);
    hash_bytes(&events->hash, event->owner.data, event->owner.length);
    hash_bytes(&events->hash, event->path.data, event->path.length);
    hash_bytes(&events->hash, event->base.data, event->base.length);
    hash_bytes(&events->hash, event->index.data, event->index.length);
    hash_bytes(&events->hash, event->aux.data, event->aux.length);
    hash_bytes(&events->hash, event->aux2.data, event->aux2.length);
    hash_bytes(&events->hash, event->scratch.data, event->scratch.length);
    hash_bytes(&events->hash, event->clobbers.data, event->clobbers.length);
    events->hash ^= (unsigned long)event->byte_order;
    events->hash *= 16777619UL;
    events->hash ^= (unsigned long)event->volatility;
    events->hash *= 16777619UL;
    events->hash ^= event->offset;
    events->hash *= 16777619UL;
    events->hash ^= event->stride;
    events->hash *= 16777619UL;
    events->hash ^= event->count;
    events->hash *= 16777619UL;
    events->hash ^= event->access_width;
    events->hash *= 16777619UL;
    events->hash ^= event->explicit_offset;
    events->hash *= 16777619UL;
    if (event->kind == LA_EVENT_PROPERTY) {
        ++events->properties;
        if (event->owner.length == 13 &&
            memcmp(event->owner.data, "CelesteObject", 13) == 0 &&
            event->path.length == 8 &&
            memcmp(event->path.data, "hitbox.w", 8) == 0 &&
            event->property == LA_PROPERTY_FIELD_OFFSET &&
            event->value == 14) {
            events->saw_hitbox_w = 1;
        }
        if (event->path.length == 4 &&
            memcmp(event->path.data, "hair", 4) == 0 &&
            event->property == LA_PROPERTY_FIELD_OFFSET &&
            event->value == 37) {
            events->saw_hair = 1;
        }
    } else if (event->kind == LA_EVENT_PROCEDURE_MEMBER) {
        ++events->members;
        if (event->path.length == 4 &&
            memcmp(event->path.data, "left", 4) == 0 &&
            event->base.length == 1 && event->base.data[0] == 'a' &&
            event->value == LA_MEMBER_INPUT) {
            events->saw_left_a = 1;
        }
        if (event->path.length == 6 &&
            memcmp(event->path.data, "result", 6) == 0 &&
            event->base.length == 1 && event->base.data[0] == 'a' &&
            event->value == LA_MEMBER_RETURN) {
            events->saw_result_a = 1;
        }
        if (event->value == LA_MEMBER_FRAME &&
            event->count == LA_PLACEMENT_FRAME &&
            event->offset == 0) {
            events->saw_frame_offset = 1;
        }
        if (event->path.length == 5 &&
            memcmp(event->path.data, "first", 5) == 0 &&
            event->base.length == 1 && event->base.data[0] == 'a') {
            events->saw_first_a = 1;
        }
        if (event->path.length == 6 &&
            memcmp(event->path.data, "second", 6) == 0 &&
            event->base.length == 1 && event->base.data[0] == 'x') {
            events->saw_second_x = 1;
        }
    } else if (event->kind == LA_EVENT_TARGET_OPERATION) {
        ++events->operations;
        if (event->operation == LA_TARGET_OP_DATA_CODEPTR) {
            check(event->access_width == 2,
                  "code pointer reports target storage width");
            check(event->byte_order == LA_BYTE_ORDER_LITTLE,
                  "code pointer reports target byte order");
            events->saw_code_pointer_data = 1;
        } else if (event->operation == LA_TARGET_OP_LOAD16_PTR_DISP ||
            event->operation == LA_TARGET_OP_STORE16_PTR_DISP) {
            check(event->access_width == 2,
                  "word transfer reports two-unit width");
            check(event->byte_order == LA_BYTE_ORDER_LITTLE,
                  "word transfer reports target byte order");
            check(event->base.length == 4 &&
                  memcmp(event->base.data, "pObj", 4) == 0,
                  "word transfer reports physical pointer");
            check(event->aux.length == 2 &&
                  memcmp(event->aux.data, "w0", 2) == 0,
                  "word transfer reports physical word");
            check(event->scratch.length == 1 &&
                  event->scratch.data[0] == 'a',
                  "word transfer reports accumulator scratch");
            check(event->clobbers.length == 7 &&
                  memcmp(event->clobbers.data, "a,flags", 7) == 0,
                  "word transfer reports clobbers");
            if (event->operation == LA_TARGET_OP_LOAD16_PTR_DISP) {
                events->saw_word_load = 1;
            } else {
                events->saw_word_store = 1;
            }
        } else if (event->operation == LA_TARGET_OP_ADD16_PHYSICAL ||
                   event->operation == LA_TARGET_OP_SUB16_PHYSICAL ||
                   event->operation == LA_TARGET_OP_CMP16_PHYSICAL) {
            check(event->base.length == 2 &&
                  memcmp(event->base.data, "ab", 2) == 0,
                  "word arithmetic reports physical accumulator");
            check(event->aux.length == 2 &&
                  memcmp(event->aux.data, "w0", 2) == 0,
                  "word arithmetic reports physical operand");
            check(event->access_width == 2,
                  "word arithmetic reports two-unit width");
            if (event->operation == LA_TARGET_OP_ADD16_PHYSICAL) {
                events->saw_word_add = 1;
            } else if (event->operation == LA_TARGET_OP_SUB16_PHYSICAL) {
                events->saw_word_sub = 1;
            } else {
                events->saw_word_compare = 1;
            }
        } else if (event->operation == LA_TARGET_OP_INC8_PTR_DISP ||
                   event->operation == LA_TARGET_OP_DEC8_PTR_DISP ||
                   event->operation == LA_TARGET_OP_AND8_PTR_DISP ||
                   event->operation == LA_TARGET_OP_OR8_PTR_DISP) {
            check(event->access_width == 1,
                  "byte update reports one-unit width");
            check(event->volatility == LA_ACCESS_NONVOLATILE,
                  "pointer byte update reports nonvolatile access");
            check(event->scratch.length == 1 &&
                  event->scratch.data[0] == 'a',
                  "byte update reports accumulator scratch");
            if (event->operation == LA_TARGET_OP_INC8_PTR_DISP) {
                events->saw_byte_increment = 1;
            } else if (event->operation == LA_TARGET_OP_DEC8_PTR_DISP) {
                events->saw_byte_decrement = 1;
            } else if (event->operation == LA_TARGET_OP_AND8_PTR_DISP) {
                events->saw_byte_and = 1;
            } else {
                events->saw_byte_or = 1;
            }
        } else if (event->operation == LA_TARGET_OP_LOAD8_OVERLAY_INDEXED ||
                   event->operation == LA_TARGET_OP_STORE8_OVERLAY_INDEXED) {
            check(event->index.length == 1 &&
                  (event->index.data[0] == 'y' || event->index.data[0] == 'x'),
                  "indexed overlay reports a physical index");
            check(event->stride == 1,
                  "indexed overlay reports unit stride");
            check(event->volatility == LA_ACCESS_VOLATILE,
                  "indexed MMIO overlay reports volatile access");
            if (event->operation == LA_TARGET_OP_LOAD8_OVERLAY_INDEXED) {
                events->saw_overlay_indexed_load = 1;
            } else {
                events->saw_overlay_indexed_store = 1;
            }
        } else if (event->operation == LA_TARGET_OP_INC8_OVERLAY_ABS ||
                   event->operation == LA_TARGET_OP_DEC8_OVERLAY_ABS ||
                   event->operation == LA_TARGET_OP_AND8_OVERLAY_ABS ||
                   event->operation == LA_TARGET_OP_OR8_OVERLAY_ABS) {
            int mask;
            mask = event->operation == LA_TARGET_OP_AND8_OVERLAY_ABS ||
                   event->operation == LA_TARGET_OP_OR8_OVERLAY_ABS;
            check(event->access_width == 1,
                  "overlay update reports one-unit width");
            check(mask ?
                      (event->scratch.length == 1 &&
                       event->scratch.data[0] == 'a') :
                      event->scratch.length == 0,
                  "overlay update reports accumulator scratch only when masking");
            check(mask ?
                      (event->clobbers.length == 7 &&
                       memcmp(event->clobbers.data, "a,flags", 7) == 0) :
                      (event->clobbers.length == 5 &&
                       memcmp(event->clobbers.data, "flags", 5) == 0),
                  "overlay update reports its clobber contract");
            if (event->operation == LA_TARGET_OP_INC8_OVERLAY_ABS) {
                if (event->volatility == LA_ACCESS_VOLATILE) {
                    events->saw_overlay_volatile_increment = 1;
                } else {
                    events->saw_overlay_increment = 1;
                }
            } else if (event->operation == LA_TARGET_OP_DEC8_OVERLAY_ABS) {
                events->saw_overlay_decrement = 1;
            } else if (event->operation == LA_TARGET_OP_AND8_OVERLAY_ABS) {
                events->saw_overlay_and = 1;
            } else {
                events->saw_overlay_or = 1;
            }
        } else if (event->operation ==
                   LA_TARGET_OP_STORE_IMM_OVERLAY_ABS) {
            check(event->access_width == 1,
                  "overlay store-immediate reports one-unit width");
            if (event->text.length == 14 &&
                memcmp(event->text.data, "#PLAYFIELD_W-1", 14) == 0) {
                check(event->volatility == LA_ACCESS_VOLATILE,
                      "MMIO overlay store-immediate reports volatile access");
                check(event->value == 5,
                      "overlay store-immediate reports field displacement");
                events->saw_overlay_store_immediate = 1;
            }
        } else if (event->operation == LA_TARGET_OP_CMP8_OVERLAY_DISP) {
            check(event->access_width == 1,
                  "overlay compare reports one-unit width");
            check(event->volatility == LA_ACCESS_VOLATILE,
                  "MMIO overlay compare reports volatile access");
            check(event->value == 13,
                  "overlay compare reports field displacement");
            events->saw_overlay_compare = 1;
        } else if (event->operation ==
                   LA_TARGET_OP_ADDRESS_OVERLAY_FIELD) {
            check(event->access_width == 2,
                  "overlay address reports pointer width");
            check(event->byte_order == LA_BYTE_ORDER_LITTLE,
                  "overlay address reports target byte order");
            check(event->base.length == 3 &&
                  memcmp(event->base.data, "$1a", 3) == 0,
                  "overlay address reports physical destination");
            check(event->aux.length == 5 &&
                  memcmp(event->aux.data, "$f000", 5) == 0,
                  "overlay address reports overlay base");
            check(event->owner.length == 8 &&
                  memcmp(event->owner.data, "tile_map", 8) == 0,
                  "overlay address reports overlay name");
            if (event->path.length == 10 &&
                memcmp(event->path.data, "attributes", 10) == 0) {
                check(event->value == 512,
                      "overlay address reports field displacement");
                events->saw_overlay_address = 1;
            }
        }
    } else if (event->kind == LA_EVENT_ENUM_MEMBER) {
        ++events->enum_members;
    } else if (event->kind == LA_EVENT_OVERLAY) {
        ++events->overlays;
    } else if (event->kind == LA_EVENT_RAW) {
        ++events->raw;
        check(event->owner.length == 0 && event->path.length == 0 &&
              event->base.length == 0 && event->index.length == 0 &&
              event->aux.length == 0 && event->aux2.length == 0 &&
              event->scratch.length == 0 && event->clobbers.length == 0 &&
              event->property == 0 && event->operation == 0 &&
              event->aggregate_kind == 0 && event->layout_policy == 0 &&
              event->byte_order == 0 &&
              event->volatility == 0 &&
              event->signed_value == 0 &&
              event->value == 0 && event->offset == 0 &&
              event->stride == 0 && event->count == 0 &&
              event->access_width == 0 &&
              event->explicit_offset == 0,
              "raw events do not retain fields from prior events");
    } else if (event->kind == LA_EVENT_LABEL) {
        ++events->labels;
    } else if (event->kind == LA_EVENT_SCOPED_RAW) {
        ++events->scoped_raw;
        if (event->text.length >= 11) {
            la_u16 offset;
            for (offset = 0; offset + 11 <= event->text.length; ++offset) {
                if (memcmp(event->text.data + offset,
                           "Widget.tick", 11) == 0) {
                    events->saw_enclosing_resolution = 1;
                    break;
                }
            }
        }
    }
    return 1;
}

static void test_typed_word_transfers(void)
{
    static const char source[] =
        "struct Fixed8_8\n"
        "    fraction : u8\n"
        "    integer : i8\n"
        "end\n"
        "struct Object\n"
        "    pad : u8[4]\n"
        "    speed : Fixed8_8\n"
        "    timer : u8\n"
        "end\n"
        "proc transfer naked\n"
        "    self : ptr Object in pObj\n"
        "    value : u16 in w0\n"
        "begin\n"
        "    ldw value, [self + Object.speed]\n"
        "    stw [self + Object.speed], value\n"
        "    addw ab, value\n"
        "    subw ab, value\n"
        "    cmpw ab, value\n"
        "    inc [self + Object.timer]\n"
        "    dec [self + Object.timer]\n"
        "    and [self + Object.timer], #$fe\n"
        "    ora [self + Object.timer], #1\n"
        "    ret\n"
        "end\n";
    static const char overlay_source[] =
        "struct Registers\n"
        "    channels : u8[4]\n"
        "end\n"
        "overlay regs : Registers at REGS volatile\n"
        "lda [regs + Registers.channels[y]]\n"
        "sta [regs + Registers.channels[y]]\n";
    static const char address_source[] =
        "struct TileMap packed\n"
        "    patterns : u8[512]\n"
        "    attributes : u8[512]\n"
        "end\n"
        "location dest : u16 at $1a\n"
        "overlay tile_map : TileMap at $f000\n"
        "address dest, tile_map.patterns\n"
        "address dest, tile_map.attributes\n";
    static const char overlay_rmw_source[] =
        "struct GameState\n"
        "    frames : u8 at 0\n"
        "    flags : u8 at 9\n"
        "end\n"
        "overlay game : GameState at $0030\n"
        "overlay video : GameState at $4000 volatile\n"
        "inc [game + GameState.frames]\n"
        "dec [game + GameState.frames]\n"
        "and [game + GameState.flags], #$fe\n"
        "ora [game + GameState.flags], #1\n"
        "inc [video + GameState.frames]\n";
    static const char overlay_cmp_source[] =
        "struct V\n"
        "    frame : u8 at 13\n"
        "end\n"
        "overlay video : V at $4000 volatile\n"
        "cmp [video + V.frame]\n";
    LaLimits limits;
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    LaTarget target;
    limits = la_default_limits();
    result = compile_source(source, 0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "typed word transfers compile");
    check(!diagnostic.seen, "typed word transfers have no diagnostic");
    check(stats.operations == 11,
          "word transfers and procedure operations are counted");
    check(events.saw_word_load, "typed word load event emitted");
    check(events.saw_word_store, "typed word store event emitted");
    check(events.saw_word_add, "physical word add event emitted");
    check(events.saw_word_sub, "physical word subtract event emitted");
    check(events.saw_word_compare, "physical word compare event emitted");
    check(events.saw_byte_increment, "typed byte increment event emitted");
    check(events.saw_byte_decrement, "typed byte decrement event emitted");
    check(events.saw_byte_and, "typed byte mask event emitted");
    check(events.saw_byte_or, "typed byte update event emitted");
    result = compile_source(
        overlay_source, 0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "indexed overlay transfers compile");
    check(stats.operations == 2, "indexed overlay operations are counted");
    check(events.saw_overlay_indexed_load,
          "indexed overlay load event emitted");
    check(events.saw_overlay_indexed_store,
          "indexed overlay store event emitted");
    result = compile_source(
        address_source, 0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "overlay field address materialization compiles");
    check(stats.operations == 2, "overlay address operations are counted");
    check(events.saw_overlay_address, "overlay field address event emitted");
    result = compile_source(
        overlay_rmw_source, 0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "fixed-overlay byte updates compile");
    check(stats.operations == 5, "overlay update operations are counted");
    check(events.saw_overlay_increment,
          "nonvolatile overlay increment event emitted");
    check(events.saw_overlay_decrement,
          "overlay decrement event emitted");
    check(events.saw_overlay_and, "overlay mask-and event emitted");
    check(events.saw_overlay_or, "overlay mask-or event emitted");
    check(events.saw_overlay_volatile_increment,
          "volatile overlay increment event emitted");
    result = compile_source(
        overlay_cmp_source, 0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "fixed-overlay accumulator compare compiles");
    check(stats.operations == 1, "overlay compare operation is counted");
    check(events.saw_overlay_compare, "overlay compare event emitted");
    result = compile_source(
        "struct Pages packed\n"
        "    page0 : u8[256] at 0\n"
        "    page9 : u8[96] at 2304\n"
        "end\n"
        "overlay fb : Pages at $e000 volatile\n"
        "lda [fb + Pages.page0[y]]\n"
        "sta [fb + Pages.page9[y]]\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK,
          "indexed access into a page view past 256 bytes compiles");
    check(events.saw_overlay_indexed_load,
          "page-view indexed load event emitted");
    check(events.saw_overlay_indexed_store,
          "page-view indexed store event emitted");
    result = compile_source(
        "struct Fx packed\n"
        "    lo : u8[32] at 0\n"
        "    speed : u8[32] at 32\n"
        "end\n"
        "overlay effects : Fx at $5600\n"
        "adc [effects.speed[x]]\n"
        "sbc [effects.speed[x]]\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK,
          "indexed carry arithmetic through a fixed-overlay array compiles");
    expect_error(
        "struct Fx packed\n    v : u8 at 0\nend\n"
        "overlay effects : Fx at $5600\n"
        "adc [effects.v]\n",
        limits, LA_ERR_UNSUPPORTED_OPERATION,
        "non-indexed overlay carry arithmetic rejected");
    result = compile_source(
        "struct V\n"
        "    control : u8 at 5\n"
        "end\n"
        "overlay video : V at $4000 volatile\n"
        "mov [video + V.control], #PLAYFIELD_W-1\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "overlay store-immediate compiles");
    check(events.saw_overlay_store_immediate,
          "overlay store-immediate event emitted with verbatim expression");
    expect_error(
        "struct V\ncontrol : u8 at 5\nend\n"
        "mov [missing + V.control], #1\n",
        limits, LA_ERR_LOCATION_TYPE,
        "overlay store-immediate with unknown base rejected");
    result = compile_source(
        "struct GameState\n"
        "    frames : u8 at 0\n"
        "    shake_x : i8 at 7\n"
        "    level : u8 at 13\n"
        "    buttons : u8 at 16\n"
        "end\n"
        "overlay game : GameState at $0030\n"
        "table = $9000\n"
        "ldx [game + GameState.frames]\n"
        "ldy [game + GameState.frames]\n"
        "add [game + GameState.shake_x]\n"
        "sub [game + GameState.shake_x]\n"
        "mov [game + GameState.level], table + x\n"
        "cblt [game + GameState.frames], #30, target\n"
        "tbz [game + GameState.buttons], #16, target\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK,
          "game-state register, arithmetic, move and branch forms compile");
    check(stats.operations == 7,
          "game-state overlay operations are all counted");
    expect_error(
        "struct GameState\nlevel : u8 at 13\nother : u8 at 14\nend\n"
        "overlay game : GameState at $0030\n"
        "mov [game + GameState.level], [game + GameState.other]\n",
        limits, LA_ERR_UNSUPPORTED_OPERATION,
        "fixed-overlay memory-to-memory move rejected");
    expect_error(
        "struct GameState\nframes : u8 at 0\nend\n"
        "cblt [missing + GameState.frames], #1, target\n",
        limits, LA_ERR_LOCATION_TYPE,
        "overlay branch with unknown base rejected");
    /* Enclosing-namespace resolution: a bare same-namespace name is qualified;
       a physical register with the same name as a member is preserved; a
       sibling-namespace name is never reached. */
    result = compile_source(
        "namespace Other\n"
        "    export tick\n"
        "tick:\n"
        "    rts\n"
        "end\n"
        "namespace Widget\n"
        "    export tick\n"
        "    y = 3\n"
        "tick:\n"
        "    jsr tick\n"
        "    sta (p), y\n"
        "    rts\n"
        "end\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "enclosing-namespace resolution compiles");
    check(events.saw_enclosing_resolution,
          "bare same-namespace reference is qualified to the namespace symbol");
    expect_error(
        "struct Big packed\ncells : u8[300] at 0\nend\n"
        "overlay b : Big at $e000\n"
        "lda [b + Big.cells[y]]\n",
        limits, LA_ERR_DISPLACEMENT,
        "indexed overlay access beyond the 8-bit register range rejected");
    expect_error(
        "struct GameState\nframes : u8 at 0\nend\n"
        "inc [missing + GameState.frames]\n",
        limits, LA_ERR_LOCATION_TYPE,
        "overlay update with unknown base rejected");
    expect_error(
        "struct R packed\nx : u8\nend\nlocation p : ptr R\n"
        "proc go naked\nself : ptr R in p\nbegin\ncmp [self + R.x]\nret\nend\n",
        limits, LA_ERR_UNSUPPORTED_OPERATION,
        "pointer accumulator compare rejected");
    expect_error(
        "struct TileMap packed\npatterns : u8[512]\nend\n"
        "location byte_dest : u8 at $10\n"
        "overlay tile_map : TileMap at $f000\n"
        "address byte_dest, tile_map.patterns\n",
        limits, LA_ERR_LOCATION_TYPE,
        "byte overlay-address destination rejected");
    expect_error(
        "struct TileMap packed\npatterns : u8[512]\nend\n"
        "location code_dest : codeptr at $14\n"
        "overlay tile_map : TileMap at $f000\n"
        "address code_dest, tile_map.patterns\n",
        limits, LA_ERR_LOCATION_TYPE,
        "code-pointer overlay-address destination rejected");
    expect_error(
        "struct TileMap packed\npatterns : u8[512]\nend\n"
        "location dest : u16 at $1a\n"
        "address dest, tile_map.patterns\n",
        limits, LA_ERR_LOCATION_TYPE,
        "unknown overlay in address rejected");
    expect_error(
        "struct TileMap packed\npatterns : u8[512]\nend\n"
        "location dest : u16 at $1a\n"
        "overlay tile_map : TileMap at $f000\n"
        "address dest, tile_map.missing\n",
        limits, LA_ERR_UNKNOWN_FIELD,
        "unknown overlay field in address rejected");
    expect_error(
        "struct Object\nbyte : u8\nend\n"
        "proc bad naked\n"
        "self : ptr Object in pObj\n"
        "value : u16 in w0\n"
        "begin\nldw value, [self + Object.byte]\nret\nend\n",
        limits, LA_ERR_ACCESS_WIDTH,
        "byte field is rejected by typed word transfer");
    expect_error(
        "struct Object\nword : u16\nend\n"
        "proc bad naked\n"
        "self : ptr Object in pObj\n"
        "value : u8 in t0\n"
        "begin\nldw value, [self + Object.word]\nret\nend\n",
        limits, LA_ERR_LOCATION_TYPE,
        "byte physical location is rejected by typed word transfer");
    expect_error(
        "struct Object\npad : u8[255]\nword : u16\nend\n"
        "proc bad naked\n"
        "self : ptr Object in pObj\n"
        "value : u16 in w0\n"
        "begin\nldw value, [self + Object.word]\nret\nend\n",
        limits, LA_ERR_DISPLACEMENT,
        "word transfer validates both displacement units");
    target = la_target_console6502;
    target.pointer_word_operations = 0;
    result = compile_source_target(source, 0, limits, &events, &diagnostic,
                                   &stats, &target);
    check(result == LA_ERR_UNSUPPORTED_OPERATION,
          "target may reject typed pointer word transfers");
    expect_error(
        "proc bad naked\n"
        "value : u16 in w0\n"
        "begin\naddw w0, value\nret\nend\n",
        limits, LA_ERR_MEMBER_PLACEMENT,
        "word arithmetic requires the target accumulator");
    expect_error(
        "proc bad naked\n"
        "value : u8 in t0\n"
        "begin\naddw ab, value\nret\nend\n",
        limits, LA_ERR_LOCATION_TYPE,
        "word arithmetic rejects a byte physical operand");
    target = la_target_console6502;
    target.physical_word_arithmetic = 0;
    result = compile_source_target(
        "proc bad naked\n"
        "value : u16 in w0\n"
        "begin\naddw ab, value\nret\nend\n",
        0, limits, &events, &diagnostic, &stats, &target);
    check(result == LA_ERR_UNSUPPORTED_OPERATION,
          "target may reject physical word arithmetic");
    expect_error(
        "struct Object\nword : u16\nend\n"
        "proc bad naked\nself : ptr Object in pObj\n"
        "begin\ninc [self + Object.word]\nret\nend\n",
        limits, LA_ERR_ACCESS_WIDTH,
        "byte update rejects a word field");
    expect_error(
        "struct Object\nbyte : u8\nend\n"
        "proc bad naked\nself : ptr Object in pObj\n"
        "begin\nand [self + Object.byte], #256\nret\nend\n",
        limits, LA_ERR_ACCESS_WIDTH,
        "byte update rejects a wide immediate");
    target = la_target_console6502;
    target.pointer_byte_rmw_operations = 0;
    result = compile_source_target(
        "struct Object\nbyte : u8\nend\n"
        "proc bad naked\nself : ptr Object in pObj\n"
        "begin\ninc [self + Object.byte]\nret\nend\n",
        0, limits, &events, &diagnostic, &stats, &target);
    check(result == LA_ERR_UNSUPPORTED_OPERATION,
          "target may reject typed byte updates");
    /* Absolute indexed overlay access accepts either physical index. */
    result = compile_source(
        "struct Registers\nchannels : u8[4]\nend\n"
        "overlay regs : Registers at REGS volatile\n"
        "lda [regs + Registers.channels[x]]\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "indexed overlay accepts physical X");
    expect_error(
        "struct Registers\nchannels : u8[4]\nend\n"
        "overlay regs : Registers at REGS volatile\n"
        "lda [regs + Registers.channels[a]]\n",
        limits, LA_ERR_INDEX_LOCATION,
        "indexed overlay rejects a non-index register");
    expect_error(
        "struct Pair\nlo : u8\nhi : u8\nend\n"
        "struct Registers\nchannels : Pair[4]\nend\n"
        "overlay regs : Registers at REGS volatile\n"
        "lda [regs + Registers.channels[y].lo]\n",
        limits, LA_ERR_INDEX_STRIDE,
        "indexed overlay rejects non-unit stride");
    target = la_target_console6502;
    target.indexed_overlay_byte_operations = 0;
    result = compile_source_target(
        "struct Registers\nchannels : u8[4]\nend\n"
        "overlay regs : Registers at REGS volatile\n"
        "lda [regs + Registers.channels[y]]\n",
        0, limits, &events, &diagnostic, &stats, &target);
    check(result == LA_ERR_UNSUPPORTED_OPERATION,
          "target may reject indexed overlay access");
}

static void test_diagnostic(void *context, const LaDiagnostic *diagnostic)
{
    TestDiagnostic *capture;
    capture = (TestDiagnostic *)context;
    capture->diagnostic = *diagnostic;
    capture->seen = 1;
}

static LaDiagnosticCode compile_source_target(
    const char *source, la_u16 chunk, LaLimits limits, TestEvents *events,
    TestDiagnostic *diagnostic, LaStats *stats, const LaTarget *target)
{
    MemoryInput memory;
    LaInput input;
    LaEventSink event_sink;
    LaDiagnosticSink diagnostic_sink;
    LaWorkspace workspace;
    LaDiagnosticCode result;
    memory.source = source;
    memory.length = (la_u16)strlen(source);
    memory.offset = 0;
    memory.chunk = chunk;
    memset(&input, 0, sizeof(input));
    input.read = memory_read;
    input.context = &memory;
    input.source_id = 7;
    input.origin = 0;
    event_sink.write = test_event;
    event_sink.context = events;
    diagnostic_sink.write = test_diagnostic;
    diagnostic_sink.context = diagnostic;
    workspace.size = la_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    check(workspace.data != 0, "test workspace allocated");
    if (workspace.data == 0) return LA_ERR_WORKSPACE;
    memset(events, 0, sizeof(*events));
    events->hash = 2166136261UL;
    memset(diagnostic, 0, sizeof(*diagnostic));
    result = la_compile(&input, &event_sink, &diagnostic_sink,
                        target, &limits, workspace, stats);
    free(workspace.data);
    return result;
}

static LaDiagnosticCode compile_source(const char *source, la_u16 chunk,
                                       LaLimits limits, TestEvents *events,
                                       TestDiagnostic *diagnostic,
                                       LaStats *stats)
{
    return compile_source_target(
        source, chunk, limits, events, diagnostic, stats,
        &la_target_console6502);
}

static const char celeste_source_layout_a[] =
    "struct Fixed8_8 packed\n"
    "    fraction : u8\n"
    "    integer : i8\n"
    "end\n"
    "struct Hitbox packed\n"
    "    x : i8\n"
    "    y : i8\n"
    "    w : u8\n"
    "    h : u8\n"
    "end\n"
    "struct HairNode packed\n"
    "    x : Fixed8_8\n"
    "    y : Fixed8_8\n"
    "end\n";

static const char celeste_source_layout_b[] =
    "struct CelesteObject packed\n"
    "    kind : u8\n"
    "    sprite : u8\n"
    "    x : i8\n"
    "    y : i8\n"
    "    speed_x : Fixed8_8\n"
    "    speed_y : Fixed8_8\n"
    "    remainder_x : Fixed8_8\n"
    "    remainder_y : Fixed8_8\n"
    "    hitbox : Hitbox\n";

static const char celeste_source_layout_c[] =
    "    flip : u8\n"
    "    flags : u8\n"
    "    state : u8\n"
    "    delay : u8\n"
    "    dash_jumps : u8\n"
    "    grace : u8\n"
    "    jump_buffer : u8\n"
    "    dash_time : u8\n"
    "    dash_effect : u8\n"
    "    player_bits : u8\n"
    "    sprite_offset : u8\n"
    "    dash_target_x : Fixed8_8\n"
    "    dash_target_y : Fixed8_8\n"
    "    dash_accel_x : Fixed8_8\n"
    "    dash_accel_y : Fixed8_8\n"
    "    target_x : i8\n"
    "    target_y : i8\n";

static const char celeste_source_tail[] =
    "    hair : HairNode[5]\n"
    "    reserved : u8[7]\n"
    "end\n"
    "static_assert CelesteObject.size == 64\n"
    "static_assert CelesteObject.hitbox.w.offset == 14\n"
    "static_assert CelesteObject.hair.offset == 37\n"
    "static_assert CelesteObject.hair.count == 5\n"
    "static_assert CelesteObject.hair.stride == 4\n"
    "location pObj : ptr CelesteObject\n"
    "start:\n"
    "    lda [pObj + CelesteObject.y]\n"
    "    sta [pObj + CelesteObject.hitbox.w]\n";

static void test_valid_layout(void)
{
    LaLimits limits;
    TestEvents events_a;
    TestEvents events_b;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaStats stats_b;
    LaDiagnosticCode result;
    char *celeste_source;
    size_t source_length;
    source_length = strlen(celeste_source_layout_a) +
                    strlen(celeste_source_layout_b) +
                    strlen(celeste_source_layout_c) +
                    strlen(celeste_source_tail) + 1;
    celeste_source = (char *)malloc(source_length);
    check(celeste_source != 0, "Celeste source buffer allocated");
    if (celeste_source == 0) return;
    strcpy(celeste_source, celeste_source_layout_a);
    strcat(celeste_source, celeste_source_layout_b);
    strcat(celeste_source, celeste_source_layout_c);
    strcat(celeste_source, celeste_source_tail);
    limits = la_default_limits();
    result = compile_source(celeste_source, 0, limits, &events_a,
                            &diagnostic, &stats);
    check(result == LA_OK, "Celeste layout compiles");
    check(!diagnostic.seen, "valid layout has no diagnostic");
    check(stats.structures == 4, "four structures");
    check(stats.fields == 36, "all Celeste fixture fields");
    check(stats.locations == 1, "one typed location");
    check(stats.operations == 2, "two structured operations");
    check(events_a.saw_hitbox_w, "nested hitbox offset emitted");
    check(events_a.saw_hair, "hair offset emitted");
    check(events_a.operations == 2, "operation sink sees two operations");
    result = compile_source(celeste_source, 3, limits, &events_b,
                            &diagnostic, &stats_b);
    check(result == LA_OK, "chunked adapter compiles");
    check(events_a.hash == events_b.hash,
          "memory adapter chunking preserves semantic event stream");
    free(celeste_source);
}

static void expect_error(const char *source, LaLimits limits,
                         LaDiagnosticCode expected, const char *message)
{
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    result = compile_source(source, 2, limits, &events, &diagnostic, &stats);
    check(result == expected, message);
    check(diagnostic.seen, "error emits diagnostic");
    if (diagnostic.seen) {
        check(diagnostic.diagnostic.code == expected,
              "diagnostic code matches result");
    }
}

static void expect_ok(const char *source, LaLimits limits,
                      const char *message)
{
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    result = compile_source(source, 2, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, message);
    check(!diagnostic.seen, "valid source has no diagnostic");
}

static void test_bitwise_expressions(void)
{
    LaLimits limits;
    limits = la_default_limits();
    /* Precedence among the bitwise family and against arithmetic. */
    expect_ok(
        "static_assert (1 | 2 ^ 3 & 4) == (1 | (2 ^ (3 & 4)))\n",
        limits, "bitwise precedence | ^ &");
    expect_ok(
        "static_assert (1 << 4) == 16\n"
        "static_assert (256 >> 4) == 16\n"
        "static_assert (1 << 2 + 1) == 8\n",
        limits, "shifts bind looser than addition");
    expect_ok(
        "static_assert (~1 & 255) == 254\n"
        "static_assert (~0 & 65535) == 65535\n",
        limits, "bitwise complement truncates via mask");
    /* Enum members compose to plain integers. */
    expect_ok(
        "enum Input : u8\n"
        "    left = 32\n"
        "    right = 64\n"
        "end\n"
        "static_assert (Input.left | Input.right) == 96\n",
        limits, "enum members compose bitwise");
    /* Unparenthesized bitwise/comparison mixes are diagnostics. */
    expect_error(
        "static_assert 1 & 2 == 2\n",
        limits, LA_ERR_SYNTAX, "unparenthesized & against == rejected");
    expect_error(
        "static_assert 1 == 1 | 1\n",
        limits, LA_ERR_SYNTAX, "unparenthesized | against == rejected");
    expect_error(
        "static_assert (1 & 1) && 2 | 4\n",
        limits, LA_ERR_SYNTAX, "unparenthesized | against && rejected");
    expect_error(
        "static_assert !1 & 1\n",
        limits, LA_ERR_SYNTAX, "logical not under & rejected");
    expect_error(
        "static_assert ~1 == 1\n",
        limits, LA_ERR_SYNTAX, "unparenthesized complement against == rejected");
    expect_ok(
        "static_assert (~(1 == 1)) != 0\n" /* fully parenthesized: ~1 = -2 */
        "static_assert (~1) != 0\n",
        limits, "parenthesized complement mixes accepted");
    /* Parenthesized mixes are legal. */
    expect_ok(
        "static_assert (1 & 2) == 0\n"
        "static_assert (3 & 1) == 1 && (4 | 1) == 5\n",
        limits, "parenthesized mixes accepted");
    /* Shift count range. */
    expect_error(
        "static_assert (1 << 32) == 0\n",
        limits, LA_ERR_SYNTAX, "shift count above 31 rejected");
    /* Arithmetic continues to mix freely with comparisons. */
    expect_ok(
        "struct A packed\nx : u8\ny : u16\nend\n"
        "static_assert A.y.offset + 1 == A.size - 1\n",
        limits, "arithmetic comparison mixing unaffected");
    /* Masked bitwise byte-update immediate. */
    expect_ok(
        "struct F packed\nflags : u8\nend\n"
        "location p : ptr F\n"
        "namespace N\n"
        "    bit_jump = 1\n"
        "proc t naked\n"
        "    self : ptr F in p\n"
        "begin\n"
        "    and [self + F.flags], #~bit_jump\n"
        "    ora [self + F.flags], #(bit_jump | 2)\n"
        "    ret\n"
        "end\n"
        "end\n",
        limits, "bitwise mask operands in typed byte updates");
    /* Non-bitwise out-of-range immediates still reject. */
    expect_error(
        "struct F packed\nflags : u8\nend\n"
        "location p : ptr F\n"
        "proc t naked\n"
        "    self : ptr F in p\n"
        "begin\n"
        "    and [self + F.flags], #300\n"
        "    ret\n"
        "end\n",
        limits, LA_ERR_ACCESS_WIDTH, "non-bitwise immediate range kept");
}

static void test_semantic_errors(void)
{
    LaLimits limits;
    limits = la_default_limits();
    expect_error(
        "struct A packed\nx : u8\nx : u8\nend\n",
        limits, LA_ERR_DUPLICATE_FIELD, "duplicate field rejected");
    expect_error(
        "struct A packed\nend\nstruct A packed\nend\n",
        limits, LA_ERR_DUPLICATE_STRUCT, "duplicate structure rejected");
    expect_error(
        "struct A packed\nb : B\nend\nstruct B packed\na : A\nend\n",
        limits, LA_ERR_LAYOUT_CYCLE, "value layout cycle rejected");
    expect_error(
        "struct A packed\nx : Missing\nend\n",
        limits, LA_ERR_UNKNOWN_TYPE, "unknown type rejected");
    expect_error(
        "struct A packed\nx : u8\nend\nstatic_assert A.size == 2\n",
        limits, LA_ERR_ASSERTION, "failed assertion rejected");
    expect_error(
        "struct A packed\nx : u8\nend\n"
        "struct B packed\nx : u8\nend\n"
        "location p : ptr A\nsta [p + B.x]\n",
        limits, LA_ERR_LOCATION_TYPE, "typed base mismatch rejected");
    expect_error(
        "callconv A\n",
        limits, LA_ERR_DEFERRED_FEATURE, "deferred callconv rejected");
    expect_error(
        "__la_bad = 1\n",
        limits, LA_ERR_RESERVED_SYMBOL, "reserved namespace rejected");
    expect_error(
        "struct A packed\nx : u16\nend\n"
        "location p : ptr A\nlda [p + A.x]\n",
        limits, LA_ERR_ACCESS_WIDTH, "wide byte access rejected");
    expect_error(
        "struct A packed\npad : u8[256]\nx : u8\nend\n"
        "location p : ptr A\nlda [p + A.x]\n",
        limits, LA_ERR_DISPLACEMENT, "large displacement rejected");
    expect_error(
        "struct A packed\nx : u8[0]\nend\n",
        limits, LA_ERR_SYNTAX, "zero array rejected");
    expect_error(
        "struct A packed\nx : u8[-1]\nend\n",
        limits, LA_ERR_SYNTAX, "negative array rejected");
    expect_error(
        "struct A packed\nx : u8\nend\nstatic_assert A.x.count == 1\n",
        limits, LA_ERR_BAD_PROPERTY, "scalar count rejected");
    expect_error(
        "struct A packed\nx : u8\nend\n"
        "location p : ptr A\nlda [p + A.missing]\n",
        limits, LA_ERR_UNKNOWN_FIELD, "unknown nested field rejected");
    expect_error(
        "location p : ptr Missing\n",
        limits, LA_ERR_UNKNOWN_TYPE, "unknown location pointee rejected");
    expect_error(
        "struct A packed\nx : u8\nend\n"
        "location p : ptr A\nadc [p + A.x]\n",
        limits, LA_ERR_UNSUPPORTED_OPERATION,
        "unsupported typed operation rejected");
}

static void test_indexed_pools_and_procedures(void)
{
    static const char source_a[] =
        "struct BytePair packed\n"
        "    lo : u8\n"
        "    hi : u8\n"
        "end\n"
        "struct Record packed\n"
        "    values : u8[4]\n"
        "    pairs : BytePair[4]\n"
        "end\n"
        "location p : ptr Record\n"
        "pool records : Record[4] at RECORDS table rec_lo, rec_hi\n"
        "static_assert records.count == 4\n"
        "static_assert records.stride == 12\n"
        "static_assert records.size == 48\n"
        "proc indexed naked\n"
        "    self : ptr Record in p\n"
        "begin\n"
        "    lda [self + Record.pairs[x].hi]\n"
        "    ret\n"
        "end\n";
    static const char source_b[] =
        "proc Record.address\n"
        "    out : ptr Record in p\n"
        "    slot : u8 in a\n"
        "begin\n"
        "    address out, records[a]\n"
        "    ret\n"
        "end\n";
    static const char source_c[] =
        "proc framed\n"
        "    saved : u8 in frame\n"
        "begin\n"
        "    sta [saved]\n"
        "    lda [saved]\n"
        "    ret\n"
        "end\n";
    LaLimits limits;
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    char *source;
    source = (char *)malloc(
        strlen(source_a) + strlen(source_b) + strlen(source_c) + 1);
    check(source != 0, "structured source allocated");
    if (source == 0) return;
    strcpy(source, source_a);
    strcat(source, source_b);
    strcat(source, source_c);
    limits = la_default_limits();
    result = compile_source(source, 3, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "indexed, pool and procedures compile");
    check(!diagnostic.seen, "structured fixture has no diagnostic");
    check(stats.pools == 1, "one pool counted");
    check(stats.procedures == 3, "three procedures counted");
    check(stats.parameters == 3, "three parameters counted");
    check(stats.locals == 1, "one local counted");
    check(stats.operations == 10, "all structured operations counted");
    free(source);

    expect_error(
        "proc Player.update\nbegin\nend\n"
        "proc Player.update\nbegin\nend\n",
        limits, LA_ERR_DUPLICATE_PROCEDURE,
        "duplicate qualified procedure rejected");

    expect_error(
        "struct R packed\nx : u8\nend\nlocation p : ptr R\n"
        "lda [p + R.x[x]]\n",
        limits, LA_ERR_INDEXED_FIELD, "scalar index rejected");
    expect_error(
        "struct R packed\nx : u8[2]\nend\nlocation p : ptr R\n"
        "lda [p + R.x[y]]\n",
        limits, LA_ERR_INDEX_LOCATION, "unsupported physical index rejected");
    expect_error(
        "struct T packed\na : u8\nb : u8\nc : u8\nend\n"
        "struct R packed\nx : T[2]\nend\nlocation p : ptr R\n"
        "lda [p + R.x[x].a]\n",
        limits, LA_ERR_INDEX_STRIDE, "unsupported index stride rejected");
    expect_error(
        "struct T packed\nx : u8[2]\nend\n"
        "struct R packed\na : T[2]\nend\nlocation p : ptr R\n"
        "lda [p + R.a[x].x[x]]\n",
        limits, LA_ERR_INDEXED_FIELD, "second index rejected");
    expect_error(
        "struct R packed\nx : u16[2]\nend\nlocation p : ptr R\n"
        "lda [p + R.x[x]]\n",
        limits, LA_ERR_ACCESS_WIDTH, "indexed non-byte leaf rejected");
    expect_error(
        "struct R packed\nx : u8\nend\nlocation p : ptr R\n"
        "address p, missing[a]\n",
        limits, LA_ERR_UNKNOWN_POOL, "unknown pool rejected");
    expect_error(
        "struct R packed\nx : u8\nend\n"
        "pool records : R[2] at RECORDS\n",
        limits, LA_ERR_POOL_STRATEGY, "missing table strategy rejected");
    expect_error(
        "struct R packed\nx : u8\nend\n"
        "pool records : R[2] at RECORDS table RL, RH\n"
        "pool records : R[2] at RECORDS table RL, RH\n",
        limits, LA_ERR_DUPLICATE_POOL, "duplicate pool rejected");
    expect_error(
        "pool records : Missing[2] at RECORDS table RL, RH\n",
        limits, LA_ERR_UNKNOWN_TYPE, "unknown pool element type rejected");
    expect_error(
        "struct R packed\nx : u8\nend\n"
        "struct S packed\nx : u8\nend\n"
        "location p : ptr S\n"
        "pool records : R[2] at RECORDS table RL, RH\n"
        "address p, records[a]\n",
        limits, LA_ERR_LOCATION_TYPE, "pool destination type rejected");
    expect_error(
        "struct R packed\nx : u8\nend\nlocation p : ptr R\n"
        "pool records : R[2] at RECORDS table RL, RH\n"
        "address p, records[x]\n",
        limits, LA_ERR_INDEX_LOCATION, "pool physical source rejected");
    expect_error(
        "proc bad naked\nx : u8 in frame\nbegin\nret\nend\n",
        limits, LA_ERR_FRAME_LOCAL, "naked local rejected");
    expect_error(
        "proc bad\nx : u8 in frame\nbegin\npha\nret\nend\n",
        limits, LA_ERR_FRAME_STACK_MUTATION,
        "raw frame stack mutation rejected");
    expect_error(
        "proc bad\nx : u8 in frame\nbegin\nrts\nend\n",
        limits, LA_ERR_FRAME_STACK_MUTATION,
        "raw framed return rejected");
    expect_error(
        "proc bad\nx : u16 in frame\nbegin\nlda [x]\nret\nend\n",
        limits, LA_ERR_ACCESS_WIDTH, "wide frame-local access rejected");
    expect_error(
        "proc same naked\nbegin\nret\nend\n"
        "proc same naked\nbegin\nret\nend\n",
        limits, LA_ERR_DUPLICATE_PROCEDURE, "duplicate procedure rejected");
    expect_error(
        "proc bad naked\nx : u8 in a\nx : u8 in x\nbegin\nret\nend\n",
        limits, LA_ERR_DUPLICATE_PARAMETER, "duplicate parameter rejected");
    expect_error(
        "proc bad\nx : u8 in frame\nx : u8 in frame\nbegin\nret\nend\n",
        limits, LA_ERR_DUPLICATE_LOCAL, "duplicate local rejected");
    expect_error(
        "proc bad sideways\nbegin\nret\nend\n",
        limits, LA_ERR_SYNTAX, "unknown frame mode rejected");
    expect_error(
        "proc bad\nx : u8 in frame\n",
        limits, LA_ERR_SYNTAX, "unterminated procedure rejected");
    expect_error(
        "struct R packed\nx : u8\nend\n"
        "proc scoped naked\nself : ptr R in p\nbegin\nret\nend\n"
        "lda [self + R.x]\n",
        limits, LA_ERR_LOCATION_TYPE, "parameter alias is procedure scoped");
    /* A procedure may place a parameter and a return at qualified locations
       declared in a namespace (the return branch used to reject the dotted
       spelling). */
    result = compile_source(
        "namespace Fix\n"
        "    location slot : u16 at $08\n"
        "    location other : u16 at $0a\n"
        "proc op naked\n"
        "    value : u16 in Fix.other\n"
        "    result : u16 return in Fix.slot\n"
        "begin\n"
        "    ret\n"
        "end\n"
        "end\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK,
          "qualified parameter and return placement resolve");
    /* The [base.field] shorthand accepts a namespace-qualified base by
       swallowing dotted components until the name resolves to a location. */
    result = compile_source(
        "struct Core packed\n    x : i8\n    y : i8\nend\n"
        "struct Obj packed\n    core : Core\nend\n"
        "namespace Mac\n"
        "    export object\n"
        "    location object : ptr Obj at $10\n"
        "end\n"
        "lda [Mac.object.core.y]\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK,
          "qualified base resolves in the [base.field] shorthand");
    expect_error(
        "struct Obj packed\n    core : u8\nend\n"
        "namespace Mac\n    location object : ptr Obj at $10\nend\n"
        "lda [Mac.missing.core]\n",
        limits, LA_ERR_LOCATION_TYPE,
        "unknown qualified base rejected in shorthand");
    /* `mov` accepts a namespace-qualified destination so the immediate value
       (here an enum member) still resolves semantically. */
    result = compile_source(
        "enum Kind : u8\n    idle = 0\n    active = 3\nend\n"
        "namespace Own\n"
        "    location slot : u8 at $20\n"
        "mov Own.slot, #Kind.active\n"
        "end\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK,
          "qualified mov destination resolves the immediate");
    /* Enclosing-namespace resolution also reaches typed-operation operands: a
       bare same-namespace destination/placement resolves like a qualified one,
       while a bare register is never shadowed. */
    result = compile_source(
        "enum Kind : u8\n    idle = 0\n    busy = 2\nend\n"
        "namespace Own\n"
        "    location slot : u8 at $20\n"
        "proc op naked\n"
        "    value : u8 return in slot\n"
        "begin\n"
        "    mov slot, #Kind.busy\n"
        "    ret\n"
        "end\n"
        "end\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK,
          "bare same-namespace names resolve in typed operands and placements");
}

static void test_comments_and_pointer_fields(void)
{
    LaLimits limits;
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    limits = la_default_limits();
    result = compile_source(
        "; raw leading comment\n"
        "struct Node packed ; declaration comment\n"
        "    value : u8 ; field comment\n"
        "    next : ptr Node ; non-recursive pointer\n"
        "end ; structure comment\n"
        "static_assert Node.size == 3 ; assertion comment\n"
        "location p : ptr Node ; location comment\n"
        "lda [p + Node.value] ; operation comment\n"
        "label: ; raw trailing comment\n",
        1, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "comments and pointer fields compile");
    check(!diagnostic.seen, "comment fixture has no diagnostic");
    check(stats.structures == 1, "pointer fixture structure counted");
    check(stats.fields == 2, "pointer fixture fields counted");
    check(stats.operations == 1, "commented typed operation lowered");
    check(events.raw == 2, "raw comment and label lines preserved");
}

static void test_unified_members_and_invoke(void)
{
    LaLimits limits;
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    limits = la_default_limits();
    result = compile_source(
        "struct R packed\nx : u8\nend\n"
        "location p : ptr R\n"
        "proc callee using console6502 naked\n"
        "left : u8\nright : u8\nresult : u8 return\n"
        "begin\nret\nend\n"
        "proc caller naked\nself : ptr R in p\nbegin\n"
        "invoke callee,\nleft=x,\nright=a\nret\nend\n",
        2, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "unified members and continued invoke compile");
    check(!diagnostic.seen, "unified fixture has no diagnostic");
    check(stats.invoke_bindings == 2, "invoke binding high-water reported");
    check(events.saw_left_a, "convention-resolved input event published");
    check(events.saw_result_a, "convention-resolved return event published");

    result = compile_source(
        "proc overrides using console6502 naked\n"
        "reserved : u8 in y\nfirst : u8\nsecond : u8\n"
        "begin\nret\nend\n",
        2, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "explicit convention override compiles");
    check(events.saw_first_a && events.saw_second_x,
          "explicit override preserves convention assignment order");

    expect_error(
        "proc bad\nlocal x : u8\nbegin\nret\nend\n",
        limits, LA_ERR_LOCAL_SYNTAX_MIGRATION,
        "provisional local syntax rejected");
    expect_error(
        "proc bad\nx : u8 in a return\nbegin\nret\nend\n",
        limits, LA_ERR_MEMBER_PLACEMENT,
        "noncanonical return placement rejected");
    expect_error(
        "proc bad\nx : u8 return in frame\nbegin\nret\nend\n",
        limits, LA_ERR_MEMBER_ROLE,
        "return cannot use frame placement");
    expect_error(
        "proc bad\nx : u8\nbegin\nret\nend\n",
        limits, LA_ERR_MEMBER_PLACEMENT,
        "unplaced input without convention rejected");
    expect_error(
        "struct R packed\nx : u8\nend\n"
        "proc bad using console6502\np : ptr R\nbegin\nret\nend\n",
        limits, LA_ERR_MEMBER_PLACEMENT,
        "unplaced pointer under convention rejected");
    expect_error(
        "proc bad using console6502\n"
        "a0 : u8\na1 : u8\na2 : u8\na3 : u8\nbegin\nret\nend\n",
        limits, LA_ERR_CONVENTION,
        "exhausted scalar convention rejected");
    expect_error(
        "proc bad using missing\nx : u8\nbegin\nret\nend\n",
        limits, LA_ERR_CONVENTION, "unknown convention rejected");
    expect_error(
        "proc caller naked\nbegin\ninvoke missing\nret\nend\n",
        limits, LA_ERR_UNKNOWN_PROCEDURE, "unknown invoked procedure rejected");
    expect_error(
        "proc callee using console6502 naked\nx : u8\nbegin\nret\nend\n"
        "proc caller naked\nbegin\ninvoke callee\nret\nend\n",
        limits, LA_ERR_INVOKE_BINDING, "missing invoke input rejected");
    expect_error(
        "proc callee using console6502 naked\nx : u8\nbegin\nret\nend\n"
        "proc caller naked\nbegin\n"
        "invoke callee, x=a, x=x\nret\nend\n",
        limits, LA_ERR_INVOKE_BINDING, "duplicate invoke binding rejected");
    expect_error(
        "proc callee using console6502 naked\nx : u8\nbegin\nret\nend\n"
        "proc caller naked\nbegin\n"
        "invoke callee, missing=a\nret\nend\n",
        limits, LA_ERR_INVOKE_BINDING, "unknown invoke binding rejected");
    expect_error(
        "proc many naked\n"
        "v0 : u8 in d0\nv1 : u8 in d1\nv2 : u8 in d2\n"
        "v3 : u8 in d3\nv4 : u8 in d4\nv5 : u8 in d5\n"
        "v6 : u8 in d6\nv7 : u8 in d7\nv8 : u8 in d8\n"
        "begin\nret\nend\n"
        "proc caller naked\n"
        "s0 : u8 in s0\ns1 : u8 in s1\ns2 : u8 in s2\n"
        "s3 : u8 in s3\ns4 : u8 in s4\ns5 : u8 in s5\n"
        "s6 : u8 in s6\ns7 : u8 in s7\ns8 : u8 in s8\n"
        "begin\ninvoke many, v0=s0, v1=s1, v2=s2, v3=s3, "
        "v4=s4, v5=s5, v6=s6, v7=s7, v8=s8\nret\nend\n",
        limits, LA_ERR_INVOKE_SCRATCH,
        "naked invoke without sufficient target scratch rejected");

    limits.max_invoke_bindings = 1;
    result = compile_source(
        "proc callee using console6502 naked\nx : u8\nbegin\nret\nend\n"
        "proc caller naked\nbegin\ninvoke callee, x=a\nret\nend\n",
        1, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "invoke binding exact capacity succeeds");

    limits.max_invoke_bindings = 0;
    expect_error(
        "proc callee using console6502 naked\nx : u8\nbegin\nret\nend\n"
        "proc caller naked\nbegin\ninvoke callee, x=a\nret\nend\n",
        limits, LA_ERR_INVOKE_CAPACITY,
        "invoke binding capacity rejected");
}

static void test_layout_variants(void)
{
    static const char valid_a[] =
        "enum Kind : u8\n"
        "none = 0\nplayer = 1\nactor = Kind.player\nend\n"
        "enum Signed : i8\nminimum = -128\nmaximum = 127\nend\n"
        "struct Pair\nlo : u8\nhi : u8\nend\n"
        "struct ExplicitPair packed\nlo : u8\nhi : u8\nend\n"
        "struct Sparse\nkind : Kind at 0\nflags : u8 at 17\nend\n"
        "struct Aligned aligned(4)\na : u8\nb : u16\nc : u8\nend\n"
        "union Payload\nbyte : u8\npair : Pair\nkinds : Kind[2]\n"
        "next : ptr Object\nend\n"
        "struct Object\nkind : Kind\npayload : Payload\nend\n";
    static const char valid_layout_more[] =
        "struct PointerShape aligned(4)\n"
        "a : u8\np : ptr Pair\nend\n"
        "struct Wide aligned(8)\nx : u8\nend\n"
        "struct Outer aligned(4)\nprefix : u8\ninner : Wide\nend\n"
        "pool shapes : Aligned[2] at SHAPES table SL, SH\n";
    static const char valid_b[] =
        "overlay sparse : Sparse at RAM\n"
        "overlay object : Object at RAM\n"
        "static_assert Kind.actor == 1\n"
        "static_assert Signed.minimum == -128\n"
        "static_assert Pair.size == ExplicitPair.size\n"
        "static_assert Sparse.flags.offset == 17\n"
        "static_assert Sparse.size == 18\n";
    static const char valid_c[] =
        "static_assert Aligned.a.offset == 0\n"
        "static_assert Aligned.b.offset == 2\n"
        "static_assert Aligned.c.offset == 4\n"
        "static_assert Aligned.size == 8\n"
        "static_assert Aligned.align == 4\n"
        "static_assert PointerShape.p.offset == 2\n"
        "static_assert PointerShape.size == 4\n"
        "static_assert Outer.inner.offset == 4\n"
        "static_assert Outer.size == 12\n";
    static const char valid_d[] =
        "static_assert shapes.align == 4\n"
        "static_assert Payload.pair.hi.offset == 1\n"
        "static_assert Payload.kinds.count == 2\n"
        "static_assert Object.payload.pair.hi.offset == 2\n"
        "lda [sparse + Sparse.kind]\n"
        "sta [object + Object.payload.pair.hi]\n";
    char *valid;
    LaLimits limits;
    TestEvents events_a;
    TestEvents events_b;
    TestEvents packed_a;
    TestEvents packed_b;
    TestDiagnostic diagnostic;
    LaStats stats_a;
    LaStats stats_b;
    LaTarget target;
    LaDiagnosticCode result;
    valid = (char *)malloc(
        strlen(valid_a) + strlen(valid_layout_more) +
        strlen(valid_b) + strlen(valid_c) + strlen(valid_d) + 1);
    check(valid != 0, "layout variant source allocated");
    if (valid == 0) return;
    strcpy(valid, valid_a);
    strcat(valid, valid_layout_more);
    strcat(valid, valid_b);
    strcat(valid, valid_c);
    strcat(valid, valid_d);
    limits = la_default_limits();
    result = compile_source(valid, 1, limits, &events_a, &diagnostic,
                            &stats_a);
    check(result == LA_OK, "layout variants compile");
    check(!diagnostic.seen, "layout variants have no diagnostic");
    check(stats_a.enums == 2 && stats_a.enum_members == 5,
          "enum records counted");
    check(stats_a.structures == 8 && stats_a.unions == 1,
          "aggregate kinds counted independently");
    check(stats_a.overlays == 2, "overlays counted");
    check(events_a.enum_members == 5 && events_a.overlays == 2,
          "variant semantic events emitted");
    check(events_a.operations == 2, "overlay byte operations emitted");
    limits.max_structs = 8;
    limits.max_unions = 1;
    limits.max_fields = 20;
    limits.max_enums = 2;
    limits.max_enum_members = 5;
    limits.max_overlays = 2;
    result = compile_source(valid, 7, limits, &events_b, &diagnostic,
                            &stats_b);
    check(result == LA_OK,
          "variant fixture recompiles under a sufficient tight profile");
    check(events_a.hash == events_b.hash,
          "variant semantic events are deterministic");
    free(valid);
    limits = la_default_limits();
    result = compile_source("struct Pair\nlo : u8\nhi : u16\nend\n",
                            0, limits, &packed_a, &diagnostic, &stats_a);
    check(result == LA_OK, "implicit packed spelling compiles");
    result = compile_source(
        "struct Pair packed\nlo : u8\nhi : u16\nend\n",
        0, limits, &packed_b, &diagnostic, &stats_b);
    check(result == LA_OK, "explicit packed spelling compiles");
    check(packed_a.hash == packed_b.hash,
          "implicit and explicit packed semantic events are identical");
    result = compile_source(
        "enum U16 : u16\nmaximum = 65535\nend\n"
        "enum I16 : i16\nminimum = -32768\nmaximum = 32767\nend\n",
        0, limits, &events_a, &diagnostic, &stats_a);
    check(result == LA_OK, "16-bit enum range edges compile");
    result = compile_source(
        "enum E : u8\none = 1\nend\nlda #E.one\n",
        0, limits, &events_a, &diagnostic, &stats_a);
    check(result == LA_OK && events_a.raw == 1,
          "raw enum operand remains unrewritten target assembly");

    expect_error("enum Bad : u32\nx = 0\nend\n", limits,
                 LA_ERR_ENUM_UNDERLYING,
                 "invalid enum underlying type rejected");
    expect_error("enum Empty : u8\nend\n", limits, LA_ERR_ENUM_EMPTY,
                 "empty enum rejected");
    expect_error("enum E : u8\nx = 1\nx = 2\nend\n", limits,
                 LA_ERR_DUPLICATE_ENUM_MEMBER,
                 "duplicate enum member rejected");
    expect_error("enum E : u8\nx = 256\nend\n", limits,
                 LA_ERR_ENUM_VALUE, "unsigned enum overflow rejected");
    expect_error("enum E : i8\nx = -129\nend\n", limits,
                 LA_ERR_ENUM_VALUE, "signed enum underflow rejected");
    expect_error("enum E : u16\nx = 65536\nend\n", limits,
                 LA_ERR_ENUM_VALUE, "unsigned 16-bit enum overflow rejected");
    expect_error("enum E : i16\nx = 32768\nend\n", limits,
                 LA_ERR_ENUM_VALUE, "signed 16-bit enum overflow rejected");
    expect_error("enum E : u8\nx = E.y\ny = 1\nend\n", limits,
                 LA_ERR_ENUM_VALUE, "forward enum reference rejected");
    expect_error("enum E : u8\nx = E.x\nend\n", limits,
                 LA_ERR_ENUM_VALUE, "self enum reference rejected");
    expect_error("enum E : u8\nx = 1\nend\nenum E : u8\ny = 2\nend\n",
                 limits, LA_ERR_DUPLICATE_ENUM,
                 "duplicate enum rejected");

    expect_error("struct A aligned(3)\nx : u8\nend\n", limits,
                 LA_ERR_LAYOUT_ALIGNMENT,
                 "non-power-of-two alignment rejected");
    expect_error("struct A aligned(32)\nx : u8\nend\n", limits,
                 LA_ERR_LAYOUT_ALIGNMENT,
                 "target-excessive alignment rejected");
    expect_error("struct A packed aligned(2)\nx : u8\nend\n", limits,
                 LA_ERR_LAYOUT_POLICY,
                 "conflicting layout policies rejected");
    expect_error("struct A\nx : u8\ny : u8 at 0\nend\n", limits,
                 LA_ERR_FIELD_OFFSET, "backward explicit offset rejected");
    expect_error("struct A aligned(4)\nx : u8\ny : u16 at 3\nend\n",
                 limits, LA_ERR_FIELD_OFFSET,
                 "misaligned explicit offset rejected");
    expect_error("struct A\nx : u8 at -1\nend\n", limits,
                 LA_ERR_FIELD_OFFSET, "negative explicit offset rejected");
    expect_error("struct A\nx : u8 at 70000\nend\n", limits,
                 LA_ERR_FIELD_OFFSET, "overflowing explicit offset rejected");

    expect_error("union U\nend\n", limits, LA_ERR_AGGREGATE_EMPTY,
                 "empty union rejected");
    expect_error("union U\nx : u8 at 0\nend\n", limits,
                 LA_ERR_UNION_OFFSET,
                 "explicit union offset rejected");
    expect_error("struct A\nu : U\nend\nunion U\na : A\nend\n", limits,
                 LA_ERR_LAYOUT_CYCLE,
                 "mixed aggregate cycle rejected");
    expect_error("union U\nx : u8\nx : u16\nend\n", limits,
                 LA_ERR_DUPLICATE_FIELD,
                 "duplicate union member rejected");

    expect_error("overlay x : u8 at RAM\n", limits, LA_ERR_OVERLAY_TYPE,
                 "primitive overlay type rejected");
    expect_error("struct A\nx : u8\nend\n"
                 "overlay v : A at RAM\noverlay v : A at RAM\n",
                 limits, LA_ERR_DUPLICATE_OVERLAY,
                 "duplicate overlay rejected");
    expect_error("struct A aligned(4)\nx : u8\nend\n"
                 "overlay v : A at $8003\n",
                 limits, LA_ERR_OVERLAY_ALIGNMENT,
                 "misaligned numeric overlay rejected");
    expect_error("struct A\nx : u8[2]\nend\n"
                 "overlay v : A at RAM\nlda [v + A.x[a]]\n",
                 limits, LA_ERR_INDEX_LOCATION,
                 "indexed overlay rejects a non-index register");
    expect_error("struct A\nx : u16\nend\n"
                 "overlay v : A at RAM\nlda [v + A.x]\n",
                 limits, LA_ERR_ACCESS_WIDTH,
                 "wide overlay byte access rejected");
    expect_error("struct A aligned(2)\nx : u8\nend\n"
                 "proc p\ntemporary : A in frame\nbegin\nret\nend\n",
                 limits, LA_ERR_LAYOUT_ALIGNMENT,
                 "unsupported aligned frame local rejected");
    target = la_target_console6502;
    target.overlay_byte_operations = 0;
    result = compile_source_target(
        "struct A\nx : u8\nend\n"
        "overlay v : A at RAM\nlda [v + A.x]\n",
        0, limits, &events_a, &diagnostic, &stats_a, &target);
    check(result == LA_ERR_UNSUPPORTED_OPERATION,
          "target without overlay operation rejects access");
}

static void test_capacities(void)
{
    LaLimits limits;
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    limits = la_default_limits();
    limits.max_structs = 1;
    result = compile_source("struct A packed\nx : u8\nend\n", 0, limits,
                            &events, &diagnostic, &stats);
    check(result == LA_OK, "structure capacity exact limit succeeds");
    expect_error("struct A packed\nend\nstruct B packed\nend\n",
                 limits, LA_ERR_STRUCT_CAPACITY,
                 "structure capacity plus one rejected");

    limits = la_default_limits();
    limits.max_fields = 1;
    result = compile_source("struct A packed\nx : u8\nend\n", 0, limits,
                            &events, &diagnostic, &stats);
    check(result == LA_OK, "field capacity exact limit succeeds");
    expect_error("struct A packed\nx : u8\ny : u8\nend\n",
                 limits, LA_ERR_FIELD_CAPACITY,
                 "field capacity plus one rejected");

    limits = la_default_limits();
    limits.max_locations = 1;
    result = compile_source(
        "struct A packed\nx : u8\nend\nlocation p : ptr A\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "location capacity exact limit succeeds");
    expect_error(
        "struct A packed\nx : u8\nend\n"
        "location p : ptr A\nlocation q : ptr A\n",
        limits, LA_ERR_LOCATION_CAPACITY,
        "location capacity plus one rejected");

    limits = la_default_limits();
    limits.max_tokens = 3;
    result = compile_source("struct A packed\nx : u8\nend\n", 0, limits,
                            &events, &diagnostic, &stats);
    check(result == LA_OK, "token capacity exact limit succeeds");
    limits.max_tokens = 2;
    expect_error("struct A packed\nx : u8\nend\n",
                 limits, LA_ERR_TOKEN_CAPACITY,
                 "token capacity plus one rejected");

    limits = la_default_limits();
    limits.max_operations = 1;
    result = compile_source(
        "struct A packed\nx : u8\nend\nlocation p : ptr A\n"
        "lda [p + A.x]\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "operation capacity exact limit succeeds");
    expect_error(
        "struct A packed\nx : u8\nend\nlocation p : ptr A\n"
        "lda [p + A.x]\nsta [p + A.x]\n",
        limits, LA_ERR_OPERATION_CAPACITY,
        "operation capacity plus one rejected");

    limits = la_default_limits();
    limits.max_source_bytes = 8;
    expect_error("struct A packed\nend\n", limits, LA_ERR_SOURCE_CAPACITY,
                 "source capacity rejected");

    limits = la_default_limits();
    limits.max_name_bytes = 3;
    expect_error("struct LongName packed\nend\n",
                 limits, LA_ERR_NAME_CAPACITY,
                 "name capacity rejected");

    limits = la_default_limits();
    limits.max_expression_nodes = 1;
    expect_error(
        "struct A packed\nx : u8\nend\nstatic_assert 1 + 2 == 3\n",
        limits, LA_ERR_EXPRESSION_CAPACITY,
        "expression capacity rejected");

    limits = la_default_limits();
    limits.max_nesting = 1;
    expect_error(
        "struct A packed\nx : u8\nend\nstatic_assert ((1))\n",
        limits, LA_ERR_NESTING_CAPACITY,
                 "expression nesting capacity rejected");

    limits = la_default_limits();
    limits.max_pools = 1;
    result = compile_source(
        "struct R packed\nx : u8\nend\n"
        "pool a : R[1] at A table AL, AH\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "pool capacity exact limit succeeds");
    expect_error(
        "struct R packed\nx : u8\nend\n"
        "pool a : R[1] at A table AL, AH\n"
        "pool b : R[1] at B table BL, BH\n",
        limits, LA_ERR_POOL_CAPACITY, "pool capacity plus one rejected");

    limits = la_default_limits();
    limits.max_procedures = 1;
    result = compile_source("proc a naked\nbegin\nret\nend\n", 0, limits,
                            &events, &diagnostic, &stats);
    check(result == LA_OK, "procedure capacity exact limit succeeds");
    expect_error("proc a naked\nbegin\nret\nend\n"
                 "proc b naked\nbegin\nret\nend\n",
                 limits, LA_ERR_PROCEDURE_CAPACITY,
                 "procedure capacity plus one rejected");

    limits = la_default_limits();
    limits.max_parameters = 1;
    result = compile_source(
        "proc a naked\nx : u8 in a\nbegin\nret\nend\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "parameter capacity exact limit succeeds");
    expect_error(
        "proc a naked\nx : u8 in a\ny : u8 in x\nbegin\nret\nend\n",
        limits, LA_ERR_PARAMETER_CAPACITY,
        "parameter capacity plus one rejected");

    limits = la_default_limits();
    limits.max_locals = 1;
    result = compile_source(
        "proc a\nx : u8 in frame\nbegin\nret\nend\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "local capacity exact limit succeeds");
    expect_error(
        "proc a\nx : u8 in frame\ny : u8 in frame\nbegin\nret\nend\n",
        limits, LA_ERR_LOCAL_CAPACITY, "local capacity plus one rejected");

    limits = la_default_limits();
    limits.max_enums = 1;
    result = compile_source("enum A : u8\nx = 0\nend\n", 0, limits,
                            &events, &diagnostic, &stats);
    check(result == LA_OK, "enum capacity exact limit succeeds");
    expect_error("enum A : u8\nx = 0\nend\n"
                 "enum B : u8\ny = 1\nend\n",
                 limits, LA_ERR_ENUM_CAPACITY,
                 "enum capacity plus one rejected");

    limits = la_default_limits();
    limits.max_enum_members = 1;
    result = compile_source("enum A : u8\nx = 0\nend\n", 0, limits,
                            &events, &diagnostic, &stats);
    check(result == LA_OK, "enum-member capacity exact limit succeeds");
    expect_error("enum A : u8\nx = 0\ny = 1\nend\n",
                 limits, LA_ERR_ENUM_MEMBER_CAPACITY,
                 "enum-member capacity plus one rejected");

    limits = la_default_limits();
    limits.max_unions = 1;
    result = compile_source("union A\nx : u8\nend\n", 0, limits,
                            &events, &diagnostic, &stats);
    check(result == LA_OK, "union capacity exact limit succeeds");
    expect_error("union A\nx : u8\nend\nunion B\ny : u8\nend\n",
                 limits, LA_ERR_UNION_CAPACITY,
                 "union capacity plus one rejected");

    limits = la_default_limits();
    limits.max_overlays = 1;
    result = compile_source(
        "struct A\nx : u8\nend\noverlay a : A at RAM\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "overlay capacity exact limit succeeds");
    expect_error(
        "struct A\nx : u8\nend\n"
        "overlay a : A at RAM\noverlay b : A at RAM\n",
        limits, LA_ERR_OVERLAY_CAPACITY,
        "overlay capacity plus one rejected");
}

static void test_namespaces(void)
{
    static const char source[] =
        "proc helper naked\n"
        "begin\n"
        "ret\n"
        "end\n"
        "namespace Player\n"
        "export run\n"
        "export speed\n"
        "export palette\n"
        "speed = $0A\n"
        "twice = speed * 2\n"
        "palette:\n"
        "#d8 1, 2, 3\n"
        "proc helper naked\n"
        "begin\n"
        "ret\n"
        "end\n"
        "proc run naked\n"
        "begin\n"
        "mov a, #twice\n"
        "cmp #Player.speed\n"
        "invoke helper\n"
        "invoke Player.helper\n"
        "ret\n"
        "end\n"
        "namespace Hair\n"
        "proc draw naked\n"
        "begin\n"
        "ret\n"
        "end\n"
        "end\n"
        "end\n"
        "lda Player.palette,x\n"
        "data u8 low(Player.run), high(Player.run)\n"
        "data u16 addr(Player.run)\n";
    LaLimits limits;
    TestEvents events;
    TestDiagnostic diagnostic;
    LaStats stats;
    LaDiagnosticCode result;
    LaTarget target;
    limits = la_default_limits();
    result = compile_source(source, 0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "nested namespaces and lexical invokes compile");
    check(stats.namespaces == 2, "namespace records counted");
    check(stats.exports == 3, "export records counted");
    check(stats.constants == 2, "namespace constants counted");
    check(stats.labels == 1, "namespace labels counted");
    check(stats.procedures == 4, "namespaced procedures counted");
    check(events.labels == 1, "namespace label event emitted");
    check(events.scoped_raw == 1, "qualified raw operand event emitted");
    result = compile_source(
        "proc target naked\n"
        "begin\n"
        "ret\n"
        "end\n"
        "proc other naked\n"
        "begin\n"
        "ret\n"
        "end\n"
        "data codeptr target, other\n"
        "struct Handler\n"
        "target : codeptr\n"
        "end\n"
        "static_assert sizeof Handler.target == 2\n"
        "static_assert Handler.size == 2\n",
        0, la_default_limits(), &events, &diagnostic, &stats);
    check(result == LA_OK,
          "target-sized code pointer data and layout compile");
    check(events.saw_code_pointer_data,
          "target-sized code pointer event emitted");
    target = la_target_console6502;
    target.code_pointer_units = 3;
    result = compile_source_target(
        "struct Handler\n"
        "target : codeptr\n"
        "end\n"
        "static_assert sizeof Handler.target == 3\n"
        "static_assert Handler.size == 3\n",
        0, la_default_limits(), &events, &diagnostic, &stats, &target);
    check(result == LA_OK,
          "code pointer layout follows target storage width");
    result = compile_source(
        "proc accept naked\n"
        "handler : codeptr in pFn\n"
        "begin\n"
        "ret\n"
        "end\n"
        "proc caller naked\n"
        "handler : codeptr in pSource\n"
        "begin\n"
        "invoke accept, handler=handler\n"
        "ret\n"
        "end\n",
        0, la_default_limits(), &events, &diagnostic, &stats);
    check(result == LA_OK,
          "typed code pointer invocation preserves target width");
    expect_error(
        "proc accept naked\n"
        "handler : codeptr in pFn\n"
        "begin\n"
        "ret\n"
        "end\n"
        "proc caller naked\n"
        "value : u8 in x\n"
        "begin\n"
        "invoke accept, handler=value\n"
        "ret\n"
        "end\n",
        la_default_limits(), LA_ERR_INVOKE_BINDING,
        "byte location cannot bind a code pointer input");
    result = compile_source(
        "struct Object\n"
        "kind : u8\n"
        "end\n"
        "namespace Machine\n"
        "location byte : u8 at $00\n"
        "location word : u16 at $08\n"
        "location object : ptr Object at $10\n"
        "location function : codeptr at $14\n"
        "location object_view : ptr Object at $10\n"
        "proc inspect naked\n"
        "self : ptr Object in Machine.object\n"
        "begin\n"
        "lda [self + Object.kind]\n"
        "ret\n"
        "end\n"
        "end\n",
        0, la_default_limits(), &events, &diagnostic, &stats);
    check(result == LA_OK,
          "scalar, pointer, code-pointer, overlap and qualified locations compile");
    expect_error(
        "namespace Machine\n"
        "location byte : u8 at $00\n"
        "proc bad naked\n"
        "value : u16 in Machine.byte\n"
        "begin\n"
        "ret\n"
        "end\n"
        "end\n",
        la_default_limits(), LA_ERR_MEMBER_PLACEMENT,
        "qualified placement enforces typed storage width");

    limits = la_default_limits();
    limits.max_constants = 1;
    result = compile_source(
        "namespace A\none = 1\nend\n", 0, limits,
        &events, &diagnostic, &stats);
    check(result == LA_OK, "constant capacity exact limit succeeds");
    expect_error(
        "namespace A\none = 1\ntwo = 2\nend\n",
        limits, LA_ERR_CONSTANT_CAPACITY,
        "constant capacity plus one rejected");
    expect_error(
        "namespace A\none = 1\none = 2\nend\n",
        la_default_limits(), LA_ERR_DUPLICATE_CONSTANT,
        "duplicate namespace constant rejected");

    limits = la_default_limits();
    limits.max_labels = 1;
    result = compile_source(
        "namespace A\none:\n#d8 1\nend\n", 0, limits,
        &events, &diagnostic, &stats);
    check(result == LA_OK, "label capacity exact limit succeeds");
    expect_error(
        "namespace A\none:\ntwo:\nend\n",
        limits, LA_ERR_LABEL_CAPACITY,
        "label capacity plus one rejected");
    expect_error(
        "namespace A\none:\none:\nend\n",
        la_default_limits(), LA_ERR_DUPLICATE_LABEL,
        "duplicate namespace label rejected");
    expect_error(
        "namespace A\none = 1\none:\nend\n",
        la_default_limits(), LA_ERR_DUPLICATE_LABEL,
        "label and constant target-symbol collision rejected");
    expect_error(
        "namespace A\none:\nproc one naked\nbegin\nret\nend\nend\n",
        la_default_limits(), LA_ERR_DUPLICATE_LABEL,
        "label and procedure target-symbol collision rejected");
    expect_error(
        "namespace A\nend\nlda A.missing\n",
        la_default_limits(), LA_ERR_UNKNOWN_SYMBOL,
        "unknown namespace symbol rejected");

    limits = la_default_limits();
    limits.max_namespaces = 1;
    result = compile_source(
        "namespace A\nend\n", 0, limits,
        &events, &diagnostic, &stats);
    check(result == LA_OK, "namespace capacity exact limit succeeds");
    expect_error("namespace A\nend\nnamespace B\nend\n",
                 limits, LA_ERR_NAMESPACE_CAPACITY,
                 "namespace capacity plus one rejected");

    limits = la_default_limits();
    limits.max_exports = 1;
    result = compile_source(
        "namespace A\nexport one\nproc one naked\nbegin\nret\nend\nend\n",
        0, limits, &events, &diagnostic, &stats);
    check(result == LA_OK, "export capacity exact limit succeeds");
    expect_error(
        "namespace A\nexport one\nexport two\n"
        "proc one naked\nbegin\nret\nend\n"
        "proc two naked\nbegin\nret\nend\nend\n",
        limits, LA_ERR_EXPORT_CAPACITY,
        "export capacity plus one rejected");

    limits = la_default_limits();
    limits.max_nesting = 1;
    expect_error("namespace A\nnamespace B\nend\nend\n",
                 limits, LA_ERR_NAMESPACE_DEPTH,
                 "namespace depth plus one rejected");
    expect_error("namespace A\nend\nnamespace A\nend\n",
                 la_default_limits(), LA_ERR_DUPLICATE_NAMESPACE,
                 "duplicate namespace rejected");
    expect_error("data u8 low(Missing.run)\n",
                 la_default_limits(), LA_ERR_UNKNOWN_PROCEDURE,
                 "unknown procedure address rejected before emission");
    expect_error("data codeptr Missing.run\n",
                 la_default_limits(), LA_ERR_UNKNOWN_PROCEDURE,
                 "unknown code pointer rejected before emission");
    expect_error(
        "proc target naked\nbegin\nret\nend\n"
        "data u8 addr(target)\n",
        la_default_limits(), LA_ERR_ACCESS_WIDTH,
        "full procedure address requires word data");
    result = compile_source(
        "struct Item\n"
        "pad : u8[3]\n"
        "value : u8\n"
        "items : u8[4]\n"
        "end\n"
        "mov y, offset Item.value\n"
        "mov slot, sizeof Item.items\n"
        "mov slot, alignof Item.value\n"
        "mov slot, countof Item.items\n"
        "mov slot, strideof Item.items\n"
        "static_assert offset Item.value == 3\n"
        "static_assert sizeof Item.items == 4\n"
        "static_assert alignof Item.value == 1\n"
        "static_assert countof Item.items == 4\n"
        "static_assert strideof Item.items == 1\n",
        0, la_default_limits(), &events, &diagnostic, &stats);
    check(result == LA_OK, "prefix layout queries materialize");
    check(stats.operations == 5, "prefix query moves are counted");
    result = compile_source(
        "enum Kind : u8\n"
        "none = 0\n"
        "item = 7\n"
        "end\n"
        "struct Item\n"
        "pad : u8[3]\n"
        "value : u8\n"
        "end\n"
        "mov slot, #Kind.item\n"
        "mov y, #Item.size-1\n"
        "cmp #Kind.none\n",
        0, la_default_limits(), &events, &diagnostic, &stats);
    check(result == LA_OK,
          "qualified enum values and layout properties materialize");
    check(stats.operations == 3,
          "qualified immediate operations are counted");
    expect_error(
        "enum Kind : u8\nitem = 1\nend\n"
        "mov slot, #Kind.missing\n",
        la_default_limits(), LA_ERR_ENUM_VALUE,
        "unknown qualified enum member is rejected");
    expect_error(
        "struct Big\nvalue : u8 at 256\nend\n"
        "mov y, #Big.value.offset\n",
        la_default_limits(), LA_ERR_ACCESS_WIDTH,
        "qualified immediate beyond target range is rejected");
    expect_error(
        "struct Big\nvalue : u8 at 256\nend\n"
        "mov y, offset Big.value\n",
        la_default_limits(), LA_ERR_DISPLACEMENT,
        "field offset beyond target range is rejected");
    expect_error(
        "struct Item\nvalue : u8\nend\n"
        "mov t0, offset Item.value\n",
        la_default_limits(), LA_ERR_MEMBER_PLACEMENT,
        "field offset requires a supported physical destination");
    expect_error(
        "struct Item\nvalue : u8\nend\n"
        "mov count, countof Item.value\n",
        la_default_limits(), LA_ERR_BAD_PROPERTY,
        "countof rejects scalar fields");
    expect_error(
        "struct Item\nvalue : u8\nend\n"
        "offset y, Item.value\n",
        la_default_limits(), LA_ERR_UNSUPPORTED_OPERATION,
        "legacy offset statement is rejected");
}

static void test_workspace_error(void)
{
    static const char source[] = "struct A packed\nx : u8\nend\n";
    MemoryInput memory;
    LaInput input;
    TestEvents events;
    TestDiagnostic diagnostic;
    LaEventSink event_sink;
    LaDiagnosticSink diagnostic_sink;
    LaLimits limits;
    LaWorkspace workspace;
    LaStats stats;
    char one_byte[1];
    LaDiagnosticCode result;
    memory.source = source;
    memory.length = (la_u16)strlen(source);
    memory.offset = 0;
    memory.chunk = 0;
    memset(&input, 0, sizeof(input));
    input.read = memory_read;
    input.context = &memory;
    input.source_id = 1;
    input.origin = 0;
    memset(&events, 0, sizeof(events));
    memset(&diagnostic, 0, sizeof(diagnostic));
    event_sink.write = test_event;
    event_sink.context = &events;
    diagnostic_sink.write = test_diagnostic;
    diagnostic_sink.context = &diagnostic;
    limits = la_default_limits();
    workspace.data = one_byte;
    workspace.size = 1;
    result = la_compile(&input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_ERR_WORKSPACE, "small workspace rejected");
    check(diagnostic.seen, "workspace error emits diagnostic");
}

/* The [base.field] shorthand must be exactly equivalent to the explicit
   [base + Type.field] form across every field-operand parser: the base's own
   declared type supplies the field's struct type, so restating it is optional. */
static void test_field_operand_shorthand(void)
{
    static const char explicit_src[] =
        "struct S packed\n    a : u8\n    b : u8\n    r : u8[4]\nend\n"
        "overlay o : S at $4000 volatile\n"
        "lda [o + S.a]\n"
        "sta [o + S.b]\n"
        "inc [o + S.a]\n"
        "and [o + S.b], #$fe\n"
        "mov [o + S.a], #1\n"
        "cblt [o + S.a], #3, done\n"
        "lda [o + S.r[x]]\n"
        "done:\n";
    static const char shorthand_src[] =
        "struct S packed\n    a : u8\n    b : u8\n    r : u8[4]\nend\n"
        "overlay o : S at $4000 volatile\n"
        "lda [o.a]\n"
        "sta [o.b]\n"
        "inc [o.a]\n"
        "and [o.b], #$fe\n"
        "mov [o.a], #1\n"
        "cblt [o.a], #3, done\n"
        "lda [o.r[x]]\n"
        "done:\n";
    LaLimits limits;
    TestEvents explicit_events;
    TestEvents shorthand_events;
    TestDiagnostic explicit_diag;
    TestDiagnostic shorthand_diag;
    LaStats explicit_stats;
    LaStats shorthand_stats;
    limits = la_default_limits();
    compile_source(explicit_src, 0, limits, &explicit_events,
                   &explicit_diag, &explicit_stats);
    compile_source(shorthand_src, 0, limits, &shorthand_events,
                   &shorthand_diag, &shorthand_stats);
    check(!explicit_diag.seen, "explicit field operands compile");
    check(!shorthand_diag.seen, "shorthand field operands compile");
    check(explicit_events.hash == shorthand_events.hash,
          "[base.field] emits identical events to [base + Type.field]");
    check(explicit_stats.operations == shorthand_stats.operations,
          "field shorthand counts identical operations");
    /* A restated type that does not match the base is still rejected. */
    expect_error(
        "struct S packed\n    a : u8\nend\n"
        "struct T packed\n    a : u8\nend\n"
        "overlay o : S at $0030\n"
        "lda [o + T.a]\n",
        limits, LA_ERR_LOCATION_TYPE,
        "explicit type that mismatches the base is rejected");
}

int main(void)
{
    test_valid_layout();
    test_bitwise_expressions();
    test_semantic_errors();
    test_comments_and_pointer_fields();
    test_indexed_pools_and_procedures();
    test_unified_members_and_invoke();
    test_layout_variants();
    test_capacities();
    test_namespaces();
    test_typed_word_transfers();
    test_field_operand_shorthand();
    test_workspace_error();
    if (failures != 0) {
        fprintf(stderr, "%d Inlay test(s) failed\n", failures);
        return 1;
    }
    puts("Inlay core: all tests passed");
    return 0;
}
