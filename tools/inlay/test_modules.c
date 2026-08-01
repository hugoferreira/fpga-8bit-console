#include "inlay.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    LaSourceView views[8];
    la_u16 count;
} Fixture;

typedef struct {
    LaDiagnostic last;
    int seen;
} Capture;

typedef struct {
    la_u16 raw_source;
    la_u16 raw_line;
    int saw_raw_include;
    int saw_operation;
} Events;

static int failures;

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        ++failures;
    }
}

static LaSlice slice(const char *text)
{
    LaSlice result;
    result.data = text;
    result.length = (la_u16)strlen(text);
    return result;
}

static LaSourceView view(const char *name, const char *data, la_u16 source_id)
{
    LaSourceView result;
    result.data = data;
    result.length = (la_u16)strlen(data);
    result.source_id = source_id;
    result.name = slice(name);
    return result;
}

static int same_slice(LaSlice left, LaSlice right)
{
    return left.length == right.length &&
           memcmp(left.data, right.data, left.length) == 0;
}

static int resolve(void *context, la_u16 including_source_id,
                   LaSlice requested, LaSourceView *source)
{
    Fixture *fixture;
    la_u16 index;
    (void)including_source_id;
    fixture = (Fixture *)context;
    for (index = 0; index < fixture->count; ++index) {
        if (same_slice(fixture->views[index].name, requested)) {
            *source = fixture->views[index];
            return 1;
        }
    }
    return 0;
}

static void diagnostic(void *context, const LaDiagnostic *value)
{
    Capture *capture;
    capture = (Capture *)context;
    capture->last = *value;
    capture->seen = 1;
}

static int event(void *context, const LaEvent *value)
{
    Events *events;
    events = (Events *)context;
    if (value->kind == LA_EVENT_RAW) {
        events->raw_source = value->span.source_id;
        events->raw_line = value->span.line;
        if (value->text.length >= 8 &&
            memcmp(value->text.data, "#include", 8) == 0) {
            events->saw_raw_include = 1;
        }
    } else if (value->kind == LA_EVENT_TARGET_OPERATION) {
        events->saw_operation = 1;
        check(value->span.source_id == 3,
              "operation retains nested module source id");
        check(value->span.line == 2,
              "operation retains nested module line");
    }
    return 1;
}

static int quiet_event(void *context, const LaEvent *value)
{
    (void)context;
    (void)value;
    return 1;
}

static int hash_event(void *context, const LaEvent *value)
{
    unsigned long *hash;
    la_u16 index;
    hash = (unsigned long *)context;
    *hash ^= (unsigned long)value->kind;
    *hash *= 16777619UL;
    for (index = 0; index < value->text.length; ++index) {
        *hash ^= (unsigned char)value->text.data[index];
        *hash *= 16777619UL;
    }
    return 1;
}

static LaDiagnosticCode expand(Fixture *fixture, LaModuleLimits limits,
                               LaWorkspace workspace,
                               LaExpandedInput *expanded, Capture *capture)
{
    LaModuleResolver resolver;
    LaDiagnosticSink sink;
    resolver.resolve = resolve;
    resolver.context = fixture;
    sink.write = diagnostic;
    sink.context = capture;
    memset(capture, 0, sizeof(*capture));
    return la_expand_modules(&fixture->views[0], &resolver, &sink,
                             &limits, workspace, expanded);
}

static void expect_module_error(const char *root_text, const char *child_text,
                                LaModuleLimits limits,
                                LaDiagnosticCode expected,
                                const char *message);

static la_u16 read_expanded(LaExpandedInput *expanded, char *output,
                            la_u16 capacity)
{
    la_u16 used;
    int amount;
    used = 0;
    while (used < capacity) {
        amount = expanded->input.read(
            expanded->input.context, output + used,
            (la_u16)(capacity - used));
        if (amount <= 0) break;
        used = (la_u16)(used + amount);
    }
    return used;
}

static void test_comment_compaction(void)
{
    static const char source[] =
        "    alpha   ; trailing comment\n"
        "  ; comment only\n"
        "#include \"semi;colon.asm\" ; include comment\n"
        "raw \"escaped \\\"; still quoted\" ; tail\n";
    static const char expected[] =
        "alpha\n"
        "#include \"semi;colon.asm\"\n"
        "raw \"escaped \\\"; still quoted\"\n";
    Fixture fixture;
    LaModuleLimits limits;
    LaWorkspace workspace;
    LaExpandedInput expanded;
    Capture capture;
    LaSpan origin;
    char output[256];
    la_u16 used;
    fixture.count = 1;
    fixture.views[0] = view("root", source, 7);
    limits = la_default_module_limits();
    workspace.size = la_module_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    check(workspace.data != 0, "comment workspace allocated");
    if (workspace.data == 0) return;
    check(expand(&fixture, limits, workspace, &expanded, &capture) == LA_OK,
          "commented source expands");
    used = read_expanded(&expanded, output, (la_u16)sizeof(output));
    check(used == strlen(expected) &&
          memcmp(output, expected, used) == 0,
          "comments and indentation compact outside quoted strings");
    memset(&origin, 0, sizeof(origin));
    expanded.input.origin(expanded.input.context, 2, &origin);
    check(origin.source_id == 7 && origin.line == 3,
          "compacted line retains original source line");
    free(workspace.data);

    limits = la_default_module_limits();
    limits.max_source_bytes = (la_u16)strlen(source);
    workspace.size = la_module_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    check(workspace.data != 0, "comment boundary workspace allocated");
    if (workspace.data == 0) return;
    check(expand(&fixture, limits, workspace, &expanded, &capture) == LA_OK,
          "immutable module bytes fit exact per-module capacity");
    free(workspace.data);
    limits.max_source_bytes = (la_u16)(strlen(source) - 1);
    expect_module_error(source, 0, limits, LA_ERR_MODULE_SOURCE_CAPACITY,
                        "per-module bytes reject one past");
}

static void test_nested_and_origins(void)
{
    static const char root_source[] =
        "include \"layout\"\n"
        "#include \"isa.asm\"\n"
        "include \"body\"\n";
    static const char layout_source[] =
        "struct Item packed\n"
        "    value : u8\n"
        "end\n"
        "location p : ptr Item\n";
    static const char body_source[] =
        "; body\n"
        "    lda [p + Item.value]\n";
    Fixture fixture;
    LaModuleLimits module_limits;
    LaWorkspace module_workspace;
    LaExpandedInput expanded;
    Capture capture;
    LaLimits limits;
    LaWorkspace workspace;
    LaEventSink event_sink;
    LaDiagnosticSink diagnostic_sink;
    LaStats stats;
    Events events;
    LaDiagnosticCode result;
    fixture.count = 3;
    fixture.views[0] = view("root", root_source, 1);
    fixture.views[1] = view("layout", layout_source, 2);
    fixture.views[2] = view("body", body_source, 3);
    module_limits = la_default_module_limits();
    module_workspace.size = la_module_workspace_required(&module_limits);
    module_workspace.data = malloc((size_t)module_workspace.size);
    check(module_workspace.data != 0, "module workspace allocated");
    if (module_workspace.data == 0) return;
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "nested modules expand");
    check(expanded.source_count == 3, "source table includes all modules");
    check(expanded.max_depth == 2, "depth is measured including root");
    limits = la_default_limits();
    workspace.size = la_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    check(workspace.data != 0, "compile workspace allocated");
    if (workspace.data != 0) {
        memset(&events, 0, sizeof(events));
        event_sink.write = event;
        event_sink.context = &events;
        diagnostic_sink.write = diagnostic;
        diagnostic_sink.context = &capture;
        result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                            &la_target_console6502, &limits, workspace, &stats);
        check(result == LA_OK, "expanded modules compile");
        check(events.saw_raw_include, "raw #include remains frontend output");
        check(events.saw_operation, "nested module can use prior declaration");
        free(workspace.data);
    }
    free(module_workspace.data);
}

static void expect_module_error(const char *root_text, const char *child_text,
                                LaModuleLimits limits,
                                LaDiagnosticCode expected,
                                const char *message)
{
    Fixture fixture;
    LaWorkspace workspace;
    LaExpandedInput expanded;
    Capture capture;
    LaDiagnosticCode result;
    fixture.count = child_text == 0 ? 1 : 2;
    fixture.views[0] = view("root", root_text, 1);
    if (child_text != 0) fixture.views[1] = view("child", child_text, 2);
    workspace.size = la_module_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    check(workspace.data != 0, "error workspace allocated");
    if (workspace.data == 0) return;
    result = expand(&fixture, limits, workspace, &expanded, &capture);
    check(result == expected, message);
    check(capture.seen, "module error emits diagnostic");
    check(capture.last.span.source_id != 0,
          "module diagnostic is source-correlated");
    free(workspace.data);
}

static void test_failures_and_boundaries(void)
{
    LaModuleLimits limits;
    Fixture fixture;
    LaWorkspace workspace;
    LaExpandedInput expanded;
    Capture capture;
    LaDiagnosticCode result;
    limits = la_default_module_limits();
    expect_module_error("include \"missing\"\n", 0, limits,
                        LA_ERR_MODULE_NOT_FOUND, "missing module rejected");
    expect_module_error("include \"child\"\n",
                        "include \"root\"\n", limits,
                        LA_ERR_MODULE_CYCLE, "cycle rejected");
    expect_module_error("include \"child\"\ninclude \"child\"\n",
                        "x\n", limits,
                        LA_ERR_MODULE_DUPLICATE,
                        "duplicate completed module rejected");

    limits.max_modules = 2;
    limits.max_edges = 1;
    limits.max_include_depth = 2;
    fixture.count = 2;
    fixture.views[0] = view("root", "include \"child\"\n", 1);
    fixture.views[1] = view("child", "x\n", 2);
    workspace.size = la_module_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    result = expand(&fixture, limits, workspace, &expanded, &capture);
    check(result == LA_OK, "module and depth capacities permit exact limit");
    free(workspace.data);
    limits.max_modules = 1;
    expect_module_error("include \"child\"\n", "x\n", limits,
                        LA_ERR_MODULE_CAPACITY,
                        "module capacity rejects one past");
    limits.max_modules = 2;
    limits.max_edges = 1;
    limits.max_include_depth = 1;
    expect_module_error("include \"child\"\n", "x\n", limits,
                        LA_ERR_MODULE_DEPTH, "depth rejects one past");
    limits = la_default_module_limits();
    limits.max_edges = 0;
    expect_module_error("include \"child\"\n", "x\n", limits,
                        LA_ERR_MODULE_CAPACITY,
                        "dependency-edge capacity rejects one past");

    limits = la_default_module_limits();
    limits.max_source_bytes = 2;
    limits.max_source_lines = 1;
    fixture.count = 1;
    fixture.views[0] = view("root", "x\n", 1);
    workspace.size = la_module_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    result = expand(&fixture, limits, workspace, &expanded, &capture);
    check(result == LA_OK, "byte and line capacities permit exact limit");
    free(workspace.data);
    limits.max_source_bytes = 1;
    expect_module_error("x\n", 0, limits, LA_ERR_MODULE_SOURCE_CAPACITY,
                        "byte capacity rejects one past");
    limits.max_source_bytes = 2;
    limits.max_source_lines = 0;
    expect_module_error("x\n", 0, limits, LA_ERR_MODULE_LINE_CAPACITY,
                        "line capacity rejects one past");

    limits = la_default_module_limits();
    workspace.size = la_module_workspace_required(&limits);
    workspace.data = malloc((size_t)(workspace.size - 1));
    fixture.count = 1;
    fixture.views[0] = view("root", "", 1);
    workspace.size -= 1;
    result = expand(&fixture, limits, workspace, &expanded, &capture);
    check(result == LA_ERR_MODULE_WORKSPACE,
          "workspace rejects one byte below exact requirement");
    free(workspace.data);
}

static void test_namespace_privacy(void)
{
    static const char root_source[] =
        "include \"child\"\n"
        "proc caller naked\n"
        "begin\n"
        "invoke Child.hidden\n"
        "ret\n"
        "end\n";
    static const char private_source[] =
        "namespace Child\n"
        "proc hidden naked\n"
        "begin\n"
        "ret\n"
        "end\n"
        "end\n";
    static const char public_source[] =
        "namespace Child\n"
        "export hidden\n"
        "proc hidden naked\n"
        "begin\n"
        "ret\n"
        "end\n"
        "end\n";
    static const char type_root_source[] =
        "include \"child\"\n"
        "location p : ptr Child.Hidden\n";
    static const char private_type_source[] =
        "namespace Child\n"
        "struct Hidden\n"
        "value : u8\n"
        "end\n"
        "end\n";
    static const char public_type_source[] =
        "namespace Child\n"
        "export Hidden\n"
        "struct Hidden\n"
        "value : u8\n"
        "end\n"
        "end\n";
    static const char constant_root_source[] =
        "include \"child\"\n"
        "mov a, #Child.secret\n";
    static const char private_constant_source[] =
        "namespace Child\n"
        "secret = $2A\n"
        "end\n";
    static const char public_constant_source[] =
        "namespace Child\n"
        "export secret\n"
        "secret = $2A\n"
        "end\n";
    static const char label_root_source[] =
        "include \"child\"\n"
        "lda Child.palette,x\n";
    static const char private_label_source[] =
        "namespace Child\n"
        "palette:\n"
        "#d8 1\n"
        "end\n";
    static const char public_label_source[] =
        "namespace Child\n"
        "export palette\n"
        "palette:\n"
        "#d8 1\n"
        "end\n";
    Fixture fixture;
    LaModuleLimits module_limits;
    LaLimits limits;
    LaWorkspace module_workspace;
    LaWorkspace workspace;
    LaExpandedInput expanded;
    Capture capture;
    LaEventSink event_sink;
    LaDiagnosticSink diagnostic_sink;
    LaStats stats;
    LaDiagnosticCode result;
    fixture.count = 2;
    fixture.views[0] = view("root", root_source, 1);
    fixture.views[1] = view("child", private_source, 2);
    module_limits = la_default_module_limits();
    module_workspace.size = la_module_workspace_required(&module_limits);
    module_workspace.data = malloc((size_t)module_workspace.size);
    limits = la_default_limits();
    workspace.size = la_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    check(module_workspace.data != 0 && workspace.data != 0,
          "namespace privacy workspaces allocated");
    if (module_workspace.data == 0 || workspace.data == 0) {
        free(module_workspace.data);
        free(workspace.data);
        return;
    }
    event_sink.write = quiet_event;
    event_sink.context = 0;
    diagnostic_sink.write = diagnostic;
    diagnostic_sink.context = &capture;
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "private namespace fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_ERR_PRIVATE_NAME,
          "cross-module private procedure is rejected");
    check(capture.seen && capture.last.span.source_id == 1,
          "privacy diagnostic points to consuming module");

    fixture.views[1] = view("child", public_source, 2);
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "exported namespace fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_OK, "export permits cross-module procedure use");

    fixture.views[0] = view("root", type_root_source, 1);
    fixture.views[1] = view("child", private_type_source, 2);
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "private type fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_ERR_PRIVATE_NAME,
          "cross-module private type is rejected");

    fixture.views[1] = view("child", public_type_source, 2);
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "exported type fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_OK, "export permits cross-module type use");

    fixture.views[0] = view("root", constant_root_source, 1);
    fixture.views[1] = view("child", private_constant_source, 2);
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "private constant fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_ERR_PRIVATE_NAME,
          "cross-module private constant is rejected");

    fixture.views[1] = view("child", public_constant_source, 2);
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "exported constant fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_OK, "export permits cross-module constant use");

    fixture.views[0] = view("root", label_root_source, 1);
    fixture.views[1] = view("child", private_label_source, 2);
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "private label fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_ERR_PRIVATE_NAME,
          "cross-module private label is rejected");

    fixture.views[1] = view("child", public_label_source, 2);
    result = expand(&fixture, module_limits, module_workspace,
                    &expanded, &capture);
    check(result == LA_OK, "exported label fixture expands");
    result = la_compile(&expanded.input, &event_sink, &diagnostic_sink,
                        &la_target_console6502, &limits, workspace, &stats);
    check(result == LA_OK, "export permits cross-module label use");
    free(workspace.data);
    free(module_workspace.data);
}

static void test_large_replay_graph(void)
{
    char *root_text;
    char *first_text;
    char *second_text;
    Fixture fixture;
    LaModuleLimits module_limits;
    LaWorkspace module_workspace;
    LaLimits limits;
    LaWorkspace workspace;
    LaExpandedInput expanded;
    Capture capture;
    LaEventSink event_sink;
    LaDiagnosticSink diagnostic_sink;
    LaStats stats;
    LaDiagnosticCode result;
    unsigned long first_hash;
    unsigned long second_hash;
    size_t size;
    size = 24000;
    root_text = (char *)malloc(size + 1);
    first_text = (char *)malloc(size + 1);
    second_text = (char *)malloc(size + 1);
    check(root_text != 0 && first_text != 0 && second_text != 0,
          "large replay sources allocated");
    if (root_text == 0 || first_text == 0 || second_text == 0) {
        free(root_text);
        free(first_text);
        free(second_text);
        return;
    }
    memset(root_text, 'x', size);
    memset(first_text, 'a', size);
    memset(second_text, 'b', size);
    root_text[0] = ';';
    first_text[0] = ';';
    second_text[0] = ';';
    memcpy(root_text + size - 34,
           "\ninclude \"first\"\ninclude \"second\"\n", 34);
    root_text[size] = 0;
    first_text[size] = 0;
    second_text[size] = 0;
    fixture.count = 3;
    fixture.views[0] = view("root", root_text, 1);
    fixture.views[1] = view("first", first_text, 2);
    fixture.views[2] = view("second", second_text, 3);
    module_limits = la_default_module_limits();
    module_limits.max_modules = 3;
    module_limits.max_edges = 2;
    module_limits.max_source_bytes = (la_u16)size;
    module_workspace.size = la_module_workspace_required(&module_limits);
    module_workspace.data = malloc((size_t)module_workspace.size);
    limits = la_default_limits();
    limits.max_source_bytes = 64;
    workspace.size = la_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    check(module_workspace.data != 0 && workspace.data != 0,
          "large replay workspaces allocated");
    if (module_workspace.data != 0 && workspace.data != 0) {
        result = expand(&fixture, module_limits, module_workspace,
                        &expanded, &capture);
        check(result == LA_OK,
              "graph over 65535 total bytes expands at exact capacities");
        if (result == LA_OK) {
            check(expanded.total_source_bytes > 65535UL,
                  "module total exceeds 16-bit byte count");
            event_sink.write = hash_event;
            first_hash = 2166136261UL;
            event_sink.context = &first_hash;
            diagnostic_sink.write = diagnostic;
            diagnostic_sink.context = &capture;
            result = la_compile(
                &expanded.input, &event_sink, &diagnostic_sink,
                &la_target_console6502, &limits, workspace, &stats);
            check(result == LA_OK,
                  "graph over 65535 bytes compiles with a 64-byte core buffer");
        }
        if (result == LA_OK) {
            result = expand(&fixture, module_limits, module_workspace,
                            &expanded, &capture);
            second_hash = 2166136261UL;
            event_sink.context = &second_hash;
        }
        if (result == LA_OK) {
            result = la_compile(
                &expanded.input, &event_sink, &diagnostic_sink,
                &la_target_console6502, &limits, workspace, &stats);
        }
        check(result == LA_OK && first_hash == second_hash,
              "replayed large graph is deterministic");
    }
    free(workspace.data);
    free(module_workspace.data);
    free(root_text);
    free(first_text);
    free(second_text);
}

int main(void)
{
    test_nested_and_origins();
    test_comment_compaction();
    test_failures_and_boundaries();
    test_namespace_privacy();
    test_large_replay_graph();
    if (failures != 0) {
        fprintf(stderr, "%d module test(s) failed\n", failures);
        return 1;
    }
    puts("Inlay module tests passed");
    return 0;
}
