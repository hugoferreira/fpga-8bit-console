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
    int saw_hitbox_w;
    int saw_hair;
    int saw_left_a;
    int saw_result_a;
    int saw_frame_offset;
    int saw_first_a;
    int saw_second_x;
} TestEvents;

typedef struct {
    LaDiagnostic diagnostic;
    int seen;
} TestDiagnostic;

static int failures;

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
    events->hash ^= event->offset;
    events->hash *= 16777619UL;
    events->hash ^= event->stride;
    events->hash *= 16777619UL;
    events->hash ^= event->count;
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
    } else if (event->kind == LA_EVENT_ENUM_MEMBER) {
        ++events->enum_members;
    } else if (event->kind == LA_EVENT_OVERLAY) {
        ++events->overlays;
    } else if (event->kind == LA_EVENT_RAW) {
        ++events->raw;
        check(event->owner.length == 0 && event->path.length == 0 &&
              event->base.length == 0 && event->index.length == 0 &&
              event->aux.length == 0 && event->aux2.length == 0 &&
              event->property == 0 && event->operation == 0 &&
              event->aggregate_kind == 0 && event->layout_policy == 0 &&
              event->signed_value == 0 &&
              event->value == 0 && event->offset == 0 &&
              event->stride == 0 && event->count == 0 &&
              event->explicit_offset == 0,
              "raw events do not retain fields from prior events");
    }
    return 1;
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
        "proc address_record\n"
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
                 "overlay v : A at RAM\nlda [v + A.x[x]]\n",
                 limits, LA_ERR_UNSUPPORTED_OPERATION,
                 "indexed overlay rejected");
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

int main(void)
{
    test_valid_layout();
    test_semantic_errors();
    test_comments_and_pointer_fields();
    test_indexed_pools_and_procedures();
    test_unified_members_and_invoke();
    test_layout_variants();
    test_capacities();
    test_workspace_error();
    if (failures != 0) {
        fprintf(stderr, "%d Inlay test(s) failed\n", failures);
        return 1;
    }
    puts("Inlay core: all tests passed");
    return 0;
}
