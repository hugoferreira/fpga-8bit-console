#include "inlay.h"

#include <string.h>

typedef struct {
    la_u16 source_id;
    la_u16 line;
} LaOriginRec;

typedef struct {
    LaSourceView view;
    la_u8 state;
} LaModuleRec;

typedef struct {
    la_u16 module;
    la_u16 offset;
    la_u16 line;
} LaModuleFrame;

typedef struct {
    const char *data;
    const LaOriginRec *origins;
    la_u16 length;
    la_u16 offset;
    la_u16 line_count;
} LaExpandedState;

typedef struct {
    char *output;
    LaOriginRec *origins;
    LaModuleRec *modules;
    LaModuleSource *sources;
    LaModuleFrame *frames;
    LaExpandedState *state;
} LaModuleStorage;

static la_u32 module_align(la_u32 value)
{
    la_u32 alignment;
    alignment = (la_u32)sizeof(void *);
    return (value + alignment - 1) & ~(alignment - 1);
}

static void *module_take(char **cursor, la_u32 *remaining, la_u32 amount)
{
    la_u32 aligned;
    void *result;
    aligned = module_align(amount);
    if (*remaining < aligned) return 0;
    result = *cursor;
    *cursor += aligned;
    *remaining -= aligned;
    return result;
}

LaModuleLimits la_default_module_limits(void)
{
    LaModuleLimits limits;
    limits.max_modules = 64;
    limits.max_source_bytes = 32767;
    limits.max_source_lines = 4096;
    limits.max_include_depth = 32;
    return limits;
}

la_u32 la_module_workspace_required(const LaModuleLimits *limits)
{
    la_u32 total;
    total = module_align((la_u32)limits->max_source_bytes + 1);
    total += module_align((la_u32)limits->max_source_lines *
                          sizeof(LaOriginRec));
    total += module_align((la_u32)limits->max_modules *
                          sizeof(LaModuleRec));
    total += module_align((la_u32)limits->max_modules *
                          sizeof(LaModuleSource));
    total += module_align((la_u32)limits->max_include_depth *
                          sizeof(LaModuleFrame));
    total += module_align(sizeof(LaExpandedState));
    return total;
}

static LaDiagnosticCode module_fail(const LaDiagnosticSink *sink,
                                    LaDiagnosticCode code,
                                    la_u16 source_id, la_u16 line,
                                    const char *arg_data, la_u16 arg_length,
                                    la_i32 value,
                                    la_i32 limit)
{
    LaDiagnostic diagnostic;
    memset(&diagnostic, 0, sizeof(diagnostic));
    diagnostic.code = code;
    diagnostic.span.source_id = source_id;
    diagnostic.span.line = line;
    diagnostic.span.column = 1;
    diagnostic.span.length = arg_length;
    diagnostic.arg0.data = arg_data;
    diagnostic.arg0.length = arg_length;
    diagnostic.value = value;
    diagnostic.limit = limit;
    if (sink != 0 && sink->write != 0) {
        sink->write(sink->context, &diagnostic);
    }
    return code;
}

static void copy_slice(LaSlice *destination, const LaSlice *source)
{
    destination->data = source->data;
    destination->length = source->length;
}

static void copy_source_view(LaSourceView *destination,
                             const LaSourceView *source)
{
    destination->data = source->data;
    destination->length = source->length;
    destination->source_id = source->source_id;
    copy_slice(&destination->name, &source->name);
}

static const char *module_code_end(const char *start, const char *end)
{
    const char *cursor;
    const char *code_end;
    int quoted;
    int escaped;
    quoted = 0;
    escaped = 0;
    code_end = end;
    for (cursor = start; cursor < end; ++cursor) {
        if (quoted) {
            if (escaped) {
                escaped = 0;
            } else if (*cursor == '\\') {
                escaped = 1;
            } else if (*cursor == '"') {
                quoted = 0;
            }
        } else if (*cursor == '"') {
            quoted = 1;
        } else if (*cursor == ';') {
            code_end = cursor;
            break;
        }
    }
    while (code_end > start &&
           (code_end[-1] == ' ' || code_end[-1] == '\t')) {
        --code_end;
    }
    return code_end;
}

static int module_storage_init(LaWorkspace workspace,
                               const LaModuleLimits *limits,
                               LaModuleStorage *storage)
{
    char *cursor;
    la_u32 remaining;
    cursor = (char *)workspace.data;
    remaining = workspace.size;
    storage->output = (char *)module_take(
        &cursor, &remaining, (la_u32)limits->max_source_bytes + 1);
    storage->origins = (LaOriginRec *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_source_lines * sizeof(LaOriginRec));
    storage->modules = (LaModuleRec *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_modules * sizeof(LaModuleRec));
    storage->sources = (LaModuleSource *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_modules * sizeof(LaModuleSource));
    storage->frames = (LaModuleFrame *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_include_depth * sizeof(LaModuleFrame));
    storage->state = (LaExpandedState *)module_take(
        &cursor, &remaining, sizeof(LaExpandedState));
    return storage->output != 0 && storage->origins != 0 &&
           storage->modules != 0 && storage->sources != 0 &&
           storage->frames != 0 && storage->state != 0;
}

static LaDiagnosticCode append_source_line(
    const LaDiagnosticSink *diagnostics, const LaModuleLimits *limits,
    const LaModuleRec *module, const LaModuleFrame *frame,
    const char *line_start, const char *line_end, LaModuleStorage *storage,
    la_u16 *output_length, la_u16 *output_lines)
{
    la_u16 line_length;
    line_end = module_code_end(line_start, line_end);
    line_length = (la_u16)(line_end - line_start);
    if ((la_u32)*output_length + line_length + 1 >
        limits->max_source_bytes) {
        return module_fail(diagnostics, LA_ERR_MODULE_SOURCE_CAPACITY,
                           module->view.source_id, frame->line,
                           module->view.name.data, module->view.name.length,
                           *output_length + line_length + 1,
                           limits->max_source_bytes);
    }
    if (*output_lines >= limits->max_source_lines) {
        return module_fail(diagnostics, LA_ERR_MODULE_LINE_CAPACITY,
                           module->view.source_id, frame->line,
                           module->view.name.data, module->view.name.length,
                           *output_lines + 1, limits->max_source_lines);
    }
    memcpy(storage->output + *output_length, line_start, line_length);
    *output_length = (la_u16)(*output_length + line_length);
    storage->output[(*output_length)++] = '\n';
    storage->origins[*output_lines].source_id = module->view.source_id;
    storage->origins[*output_lines].line = frame->line;
    ++*output_lines;
    return LA_OK;
}

static int expanded_read(void *context, char *destination, la_u16 capacity)
{
    LaExpandedState *state;
    la_u16 amount;
    state = (LaExpandedState *)context;
    if (state->offset >= state->length) return 0;
    amount = (la_u16)(state->length - state->offset);
    if (amount > capacity) amount = capacity;
    memcpy(destination, state->data + state->offset, amount);
    state->offset = (la_u16)(state->offset + amount);
    return amount;
}

static void expanded_origin(void *context, la_u16 expanded_line,
                            LaSpan *origin)
{
    LaExpandedState *state;
    state = (LaExpandedState *)context;
    if (expanded_line == 0 || expanded_line > state->line_count) return;
    origin->source_id = state->origins[expanded_line - 1].source_id;
    origin->line = state->origins[expanded_line - 1].line;
}

static int include_line(const char *start, const char *end,
                        LaSlice *requested)
{
    const char *cursor;
    const char *name;
    while (start < end &&
           (*start == ' ' || *start == '\t' || *start == '\r')) ++start;
    if ((la_u16)(end - start) < 7 ||
        memcmp(start, "include", 7) != 0 ||
        (start + 7 < end && start[7] != ' ' && start[7] != '\t')) {
        return 0;
    }
    cursor = start + 7;
    while (cursor < end && (*cursor == ' ' || *cursor == '\t')) ++cursor;
    if (cursor == end || *cursor != '"') return -1;
    ++cursor;
    name = cursor;
    while (cursor < end && *cursor != '"') ++cursor;
    if (cursor == end || cursor == name) return -1;
    requested->data = name;
    requested->length = (la_u16)(cursor - name);
    ++cursor;
    while (cursor < end && (*cursor == ' ' || *cursor == '\t' ||
                            *cursor == '\r')) ++cursor;
    if (cursor < end && *cursor == ';') return 1;
    return cursor == end ? 1 : -1;
}

static la_u16 find_module(LaModuleRec *modules, la_u16 count,
                          la_u16 source_id)
{
    la_u16 index;
    for (index = 0; index < count; ++index) {
        if (modules[index].view.source_id == source_id) return index;
    }
    return LA_INVALID_HANDLE;
}

LaDiagnosticCode la_expand_modules(const LaSourceView *root,
                                   const LaModuleResolver *resolver,
                                   const LaDiagnosticSink *diagnostics,
                                   const LaModuleLimits *limits,
                                   LaWorkspace workspace,
                                   LaExpandedInput *expanded)
{
    la_u32 required;
    LaModuleStorage storage;
    la_u16 module_count;
    la_u16 depth;
    la_u16 output_length;
    la_u16 output_lines;
    required = la_module_workspace_required(limits);
    memset(expanded, 0, sizeof(*expanded));
    if (workspace.data == 0 || workspace.size < required) {
        return module_fail(diagnostics, LA_ERR_MODULE_WORKSPACE,
                           root->source_id, 0,
                           root->name.data, root->name.length,
                           (la_i32)required, (la_i32)workspace.size);
    }
    if (limits->max_modules == 0 || limits->max_include_depth == 0) {
        return module_fail(diagnostics, LA_ERR_MODULE_CAPACITY,
                           root->source_id, 1,
                           root->name.data, root->name.length, 1, 0);
    }
    if (!module_storage_init(workspace, limits, &storage)) {
        return module_fail(diagnostics, LA_ERR_MODULE_WORKSPACE,
                           root->source_id, 0,
                           root->name.data, root->name.length,
                           (la_i32)required, (la_i32)workspace.size);
    }
    module_count = 1;
    copy_source_view(&storage.modules[0].view, root);
    storage.modules[0].state = 1;
    storage.sources[0].source_id = root->source_id;
    copy_slice(&storage.sources[0].name, &root->name);
    depth = 1;
    storage.frames[0].module = 0;
    storage.frames[0].offset = 0;
    storage.frames[0].line = 1;
    output_length = 0;
    output_lines = 0;
    expanded->max_depth = 1;
    while (depth != 0) {
        LaModuleFrame *frame;
        LaModuleRec *module;
        const char *line_start;
        const char *line_end;
        const char *content_end;
        LaSlice requested;
        int include;
        frame = &storage.frames[depth - 1];
        module = &storage.modules[frame->module];
        if (frame->offset >= module->view.length) {
            module->state = 2;
            --depth;
            continue;
        }
        line_start = module->view.data + frame->offset;
        line_end = line_start;
        while ((la_u16)(line_end - module->view.data) <
               module->view.length && *line_end != '\n') ++line_end;
        content_end = line_end;
        if (content_end > line_start && content_end[-1] == '\r') {
            --content_end;
        }
        include = include_line(line_start, content_end, &requested);
        frame->offset = (la_u16)(line_end - module->view.data);
        if (frame->offset < module->view.length) ++frame->offset;
        if (include < 0) {
            return module_fail(diagnostics, LA_ERR_MODULE_SYNTAX,
                               module->view.source_id, frame->line,
                               module->view.name.data,
                               module->view.name.length, 0, 0);
        }
        if (include > 0) {
            LaSourceView child;
            la_u16 existing;
            la_u16 child_index;
            if (resolver == 0 || resolver->resolve == 0 ||
                !resolver->resolve(resolver->context,
                                   module->view.source_id,
                                   requested, &child)) {
                return module_fail(diagnostics, LA_ERR_MODULE_NOT_FOUND,
                                   module->view.source_id, frame->line,
                                   requested.data, requested.length, 0, 0);
            }
            existing = find_module(
                storage.modules, module_count, child.source_id);
            if (existing != LA_INVALID_HANDLE) {
                return module_fail(
                    diagnostics,
                    storage.modules[existing].state == 1 ?
                        LA_ERR_MODULE_CYCLE : LA_ERR_MODULE_DUPLICATE,
                    module->view.source_id, frame->line,
                    requested.data, requested.length, 0, 0);
            }
            if (module_count >= limits->max_modules) {
                return module_fail(diagnostics, LA_ERR_MODULE_CAPACITY,
                                   module->view.source_id, frame->line,
                                   requested.data, requested.length,
                                   module_count + 1,
                                   limits->max_modules);
            }
            if (depth >= limits->max_include_depth) {
                return module_fail(diagnostics, LA_ERR_MODULE_DEPTH,
                                   module->view.source_id, frame->line,
                                   requested.data, requested.length, depth + 1,
                                   limits->max_include_depth);
            }
            child_index = module_count++;
            copy_source_view(&storage.modules[child_index].view, &child);
            storage.modules[child_index].state = 1;
            storage.sources[child_index].source_id = child.source_id;
            copy_slice(&storage.sources[child_index].name, &child.name);
            storage.frames[depth].module = child_index;
            storage.frames[depth].offset = 0;
            storage.frames[depth].line = 1;
            ++depth;
            if (depth > expanded->max_depth) expanded->max_depth = depth;
        } else {
            LaDiagnosticCode append_result;
            append_result = append_source_line(
                diagnostics, limits, module, frame, line_start, line_end,
                &storage, &output_length, &output_lines);
            if (append_result != LA_OK) return append_result;
        }
        ++frame->line;
    }
    storage.output[output_length] = 0;
    storage.state->data = storage.output;
    storage.state->origins = storage.origins;
    storage.state->length = output_length;
    storage.state->offset = 0;
    storage.state->line_count = output_lines;
    expanded->input.read = expanded_read;
    expanded->input.context = storage.state;
    expanded->input.source_id = root->source_id;
    expanded->input.origin = expanded_origin;
    expanded->sources = storage.sources;
    expanded->source_count = module_count;
    expanded->expanded_bytes = output_length;
    expanded->expanded_lines = output_lines;
    return LA_OK;
}
