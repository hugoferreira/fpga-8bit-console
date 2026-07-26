#include "laasm.h"

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
    limits.max_include_depth = 1;
    expect_module_error("include \"child\"\n", "x\n", limits,
                        LA_ERR_MODULE_DEPTH, "depth rejects one past");

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

int main(void)
{
    test_nested_and_origins();
    test_failures_and_boundaries();
    if (failures != 0) {
        fprintf(stderr, "%d module test(s) failed\n", failures);
        return 1;
    }
    puts("laasm module tests passed");
    return 0;
}
