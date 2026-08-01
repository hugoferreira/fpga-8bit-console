#include "inlay.h"

#include <string.h>

typedef struct {
    LaSourceView view;
    la_u8 state;
} LaModuleRec;

typedef struct {
    la_u16 parent;
    la_u16 child;
    la_u16 line;
} LaModuleEdge;

typedef struct {
    la_u16 module;
    la_u16 offset;
    la_u16 line;
} LaModuleFrame;

typedef struct {
    LaModuleRec *modules;
    LaModuleSource *sources;
    LaModuleEdge *edges;
    LaModuleFrame *frames;
    la_u16 module_count;
    la_u16 edge_count;
    la_u16 frame_capacity;
    la_u16 depth;
    const char *pending;
    la_u16 pending_length;
    la_u16 pending_offset;
    int read_started;
} LaReplayState;

typedef struct {
    LaModuleRec *modules;
    LaModuleSource *sources;
    LaModuleEdge *edges;
    LaModuleFrame *frames;
    LaReplayState *state;
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
    limits.max_edges = 64;
    limits.max_source_bytes = 32767;
    limits.max_source_lines = 4096;
    limits.max_include_depth = 32;
    return limits;
}

la_u32 la_module_workspace_required(const LaModuleLimits *limits)
{
    la_u32 total;
    total = module_align((la_u32)limits->max_modules *
                         sizeof(LaModuleRec));
    total += module_align((la_u32)limits->max_modules *
                          sizeof(LaModuleSource));
    total += module_align((la_u32)limits->max_edges *
                          sizeof(LaModuleEdge));
    total += module_align((la_u32)limits->max_include_depth *
                          sizeof(LaModuleFrame));
    total += module_align(sizeof(LaReplayState));
    return total;
}

static LaDiagnosticCode module_fail(const LaDiagnosticSink *sink,
                                    LaDiagnosticCode code,
                                    la_u16 source_id, la_u16 line,
                                    const char *arg_data, la_u16 arg_length,
                                    la_i32 value, la_i32 limit)
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
           (code_end[-1] == ' ' || code_end[-1] == '\t' ||
            code_end[-1] == '\r')) {
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
    storage->modules = (LaModuleRec *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_modules * sizeof(LaModuleRec));
    storage->sources = (LaModuleSource *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_modules * sizeof(LaModuleSource));
    storage->edges = (LaModuleEdge *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_edges * sizeof(LaModuleEdge));
    storage->frames = (LaModuleFrame *)module_take(
        &cursor, &remaining,
        (la_u32)limits->max_include_depth * sizeof(LaModuleFrame));
    storage->state = (LaReplayState *)module_take(
        &cursor, &remaining, sizeof(LaReplayState));
    return storage->modules != 0 && storage->sources != 0 &&
           storage->edges != 0 && storage->frames != 0 &&
           storage->state != 0;
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

static void replay_reset(void *context)
{
    LaReplayState *state;
    state = (LaReplayState *)context;
    state->depth = 1;
    state->frames[0].module = 0;
    state->frames[0].offset = 0;
    state->frames[0].line = 1;
    state->pending = 0;
    state->pending_length = 0;
    state->pending_offset = 0;
}

static la_u16 replay_child(LaReplayState *state, la_u16 parent,
                           la_u16 line)
{
    la_u16 edge;
    for (edge = 0; edge < state->edge_count; ++edge) {
        if (state->edges[edge].parent == parent &&
            state->edges[edge].line == line) {
            return state->edges[edge].child;
        }
    }
    return LA_INVALID_HANDLE;
}

static int replay_next_line(void *context, LaSourceLine *result)
{
    LaReplayState *state;
    state = (LaReplayState *)context;
    while (state->depth != 0) {
        LaModuleFrame *frame;
        LaModuleRec *module;
        const char *start;
        const char *end;
        const char *code_end;
        LaSlice requested;
        int include;
        la_u16 original_line;
        frame = &state->frames[state->depth - 1];
        module = &state->modules[frame->module];
        if (frame->offset >= module->view.length) {
            --state->depth;
            continue;
        }
        start = module->view.data + frame->offset;
        end = start;
        while ((la_u16)(end - module->view.data) < module->view.length &&
               *end != '\n') ++end;
        original_line = frame->line++;
        frame->offset = (la_u16)(end - module->view.data);
        if (frame->offset < module->view.length) ++frame->offset;
        code_end = module_code_end(start, end);
        include = include_line(start, code_end, &requested);
        if (include > 0) {
            la_u16 child;
            child = replay_child(state, frame->module, original_line);
            if (child == LA_INVALID_HANDLE ||
                state->depth >= state->frame_capacity) return -1;
            state->frames[state->depth].module = child;
            state->frames[state->depth].offset = 0;
            state->frames[state->depth].line = 1;
            ++state->depth;
            continue;
        }
        while (start < code_end && (*start == ' ' || *start == '\t')) {
            ++start;
        }
        if (start == code_end) continue;
        result->data = start;
        result->length = (la_u16)(code_end - start);
        result->source_id = module->view.source_id;
        result->line = original_line;
        return 1;
    }
    return 0;
}

static int replay_read(void *context, char *destination, la_u16 capacity)
{
    LaReplayState *state;
    la_u16 written;
    state = (LaReplayState *)context;
    if (!state->read_started) {
        replay_reset(state);
        state->read_started = 1;
    }
    written = 0;
    while (written < capacity) {
        if (state->pending_offset < state->pending_length) {
            la_u16 amount;
            amount = (la_u16)(state->pending_length -
                              state->pending_offset);
            if (amount > capacity - written) {
                amount = (la_u16)(capacity - written);
            }
            memcpy(destination + written,
                   state->pending + state->pending_offset, amount);
            state->pending_offset =
                (la_u16)(state->pending_offset + amount);
            written = (la_u16)(written + amount);
            continue;
        }
        if (state->pending != 0 &&
            state->pending_offset == state->pending_length) {
            destination[written++] = '\n';
            state->pending = 0;
            if (written == capacity) break;
        } else {
            LaSourceLine line;
            int next;
            next = replay_next_line(state, &line);
            if (next <= 0) break;
            state->pending = line.data;
            state->pending_length = line.length;
            state->pending_offset = 0;
        }
    }
    return written;
}

static void replay_origin(void *context, la_u16 expanded_line,
                          LaSpan *origin)
{
    LaReplayState *state;
    LaSourceLine line;
    la_u16 current;
    state = (LaReplayState *)context;
    replay_reset(state);
    current = 0;
    while (current < expanded_line &&
           replay_next_line(state, &line) > 0) {
        ++current;
    }
    if (current == expanded_line) {
        origin->source_id = line.source_id;
        origin->line = line.line;
    }
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
    la_u16 edge_count;
    la_u16 depth;
    required = la_module_workspace_required(limits);
    memset(expanded, 0, sizeof(*expanded));
    if (workspace.data == 0 || workspace.size < required) {
        return module_fail(diagnostics, LA_ERR_MODULE_WORKSPACE,
                           root->source_id, 0, root->name.data,
                           root->name.length, (la_i32)required,
                           (la_i32)workspace.size);
    }
    if (limits->max_modules == 0 || limits->max_edges == 0 ||
        limits->max_include_depth == 0) {
        return module_fail(diagnostics, LA_ERR_MODULE_CAPACITY,
                           root->source_id, 1, root->name.data,
                           root->name.length, 1, 0);
    }
    if (!module_storage_init(workspace, limits, &storage)) {
        return module_fail(diagnostics, LA_ERR_MODULE_WORKSPACE,
                           root->source_id, 0, root->name.data,
                           root->name.length, (la_i32)required,
                           (la_i32)workspace.size);
    }
    if (root->length > limits->max_source_bytes) {
        return module_fail(diagnostics, LA_ERR_MODULE_SOURCE_CAPACITY,
                           root->source_id, 1, root->name.data,
                           root->name.length, root->length,
                           limits->max_source_bytes);
    }
    module_count = 1;
    edge_count = 0;
    copy_source_view(&storage.modules[0].view, root);
    storage.modules[0].state = 1;
    storage.sources[0].source_id = root->source_id;
    copy_slice(&storage.sources[0].name, &root->name);
    depth = 1;
    storage.frames[0].module = 0;
    storage.frames[0].offset = 0;
    storage.frames[0].line = 1;
    expanded->max_depth = 1;
    expanded->total_source_bytes = root->length;
    expanded->total_source_lines = 0;
    while (depth != 0) {
        LaModuleFrame *frame;
        LaModuleRec *module;
        const char *line_start;
        const char *line_end;
        const char *content_end;
        LaSlice requested;
        int include;
        la_u16 include_line_number;
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
        content_end = module_code_end(line_start, line_end);
        include_line_number = frame->line++;
        ++expanded->total_source_lines;
        if (include_line_number > limits->max_source_lines) {
            return module_fail(
                diagnostics, LA_ERR_MODULE_LINE_CAPACITY,
                module->view.source_id, include_line_number,
                module->view.name.data, module->view.name.length,
                include_line_number, limits->max_source_lines);
        }
        frame->offset = (la_u16)(line_end - module->view.data);
        if (frame->offset < module->view.length) ++frame->offset;
        include = include_line(line_start, content_end, &requested);
        if (include < 0) {
            return module_fail(diagnostics, LA_ERR_MODULE_SYNTAX,
                               module->view.source_id,
                               include_line_number, module->view.name.data,
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
                                   module->view.source_id,
                                   include_line_number, requested.data,
                                   requested.length, 0, 0);
            }
            existing = find_module(storage.modules, module_count,
                                   child.source_id);
            if (existing != LA_INVALID_HANDLE) {
                return module_fail(
                    diagnostics,
                    storage.modules[existing].state == 1 ?
                        LA_ERR_MODULE_CYCLE : LA_ERR_MODULE_DUPLICATE,
                    module->view.source_id, include_line_number,
                    requested.data, requested.length, 0, 0);
            }
            if (module_count >= limits->max_modules) {
                return module_fail(diagnostics, LA_ERR_MODULE_CAPACITY,
                                   module->view.source_id,
                                   include_line_number, requested.data,
                                   requested.length, module_count + 1,
                                   limits->max_modules);
            }
            if (edge_count >= limits->max_edges) {
                return module_fail(diagnostics, LA_ERR_MODULE_CAPACITY,
                                   module->view.source_id,
                                   include_line_number, requested.data,
                                   requested.length, edge_count + 1,
                                   limits->max_edges);
            }
            if (depth >= limits->max_include_depth) {
                return module_fail(diagnostics, LA_ERR_MODULE_DEPTH,
                                   module->view.source_id,
                                   include_line_number, requested.data,
                                   requested.length, depth + 1,
                                   limits->max_include_depth);
            }
            if (child.length > limits->max_source_bytes) {
                return module_fail(
                    diagnostics, LA_ERR_MODULE_SOURCE_CAPACITY,
                    child.source_id, 1, child.name.data, child.name.length,
                    child.length, limits->max_source_bytes);
            }
            child_index = module_count++;
            copy_source_view(&storage.modules[child_index].view, &child);
            storage.modules[child_index].state = 1;
            storage.sources[child_index].source_id = child.source_id;
            copy_slice(&storage.sources[child_index].name, &child.name);
            storage.edges[edge_count].parent = frame->module;
            storage.edges[edge_count].child = child_index;
            storage.edges[edge_count].line = include_line_number;
            ++edge_count;
            expanded->total_source_bytes += child.length;
            storage.frames[depth].module = child_index;
            storage.frames[depth].offset = 0;
            storage.frames[depth].line = 1;
            ++depth;
            if (depth > expanded->max_depth) expanded->max_depth = depth;
        }
    }
    memset(storage.state, 0, sizeof(*storage.state));
    storage.state->modules = storage.modules;
    storage.state->sources = storage.sources;
    storage.state->edges = storage.edges;
    storage.state->frames = storage.frames;
    storage.state->module_count = module_count;
    storage.state->edge_count = edge_count;
    storage.state->frame_capacity = limits->max_include_depth;
    replay_reset(storage.state);
    expanded->input.read = replay_read;
    expanded->input.context = storage.state;
    expanded->input.source_id = root->source_id;
    expanded->input.origin = replay_origin;
    expanded->input.reset = replay_reset;
    expanded->input.next_line = replay_next_line;
    expanded->sources = storage.sources;
    expanded->source_count = module_count;
    return LA_OK;
}
