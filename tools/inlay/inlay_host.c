#define _XOPEN_SOURCE 700

#include "inlay.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define HOST_MAX_MODULES 64

typedef struct {
    char *path;
    char *logical_name;
    char *data;
    LaSourceView view;
} HostModule;

typedef struct {
    char root_dir[PATH_MAX];
    HostModule modules[HOST_MAX_MODULES];
    la_u16 count;
} HostModules;

typedef struct {
    unsigned line;
    unsigned source_id;
} HostSourceLocation;

typedef struct {
    FILE *assembly;
    FILE *map;
    const HostModules *modules;
    const char *input_path;
    unsigned generated_line;
    unsigned map_entries;
    HostSourceLocation *source_locations;
    unsigned source_capacity;
    int failed;
} HostOutput;

typedef struct {
    const char *input_path;
    const HostModules *modules;
} HostDiagnostics;

typedef struct {
    const char *target_name;
    const char *output_path;
    const char *map_path;
    const char *input_path;
    int print_stats;
    int check_customasm;
} HostOptions;

typedef struct {
    FILE *assembly;
    FILE *map;
    char assembly_path[PATH_MAX];
    char map_path[PATH_MAX];
} HostArtifacts;

static void json_string(FILE *file, const char *text)
{
    const unsigned char *cursor;
    fputc('"', file);
    cursor = (const unsigned char *)text;
    while (*cursor != 0) {
        if (*cursor == '"' || *cursor == '\\') {
            fputc('\\', file);
            fputc(*cursor, file);
        } else if (*cursor == '\n') {
            fputs("\\n", file);
        } else if (*cursor < 0x20) {
            fprintf(file, "\\u%04x", (unsigned)*cursor);
        } else {
            fputc(*cursor, file);
        }
        ++cursor;
    }
    fputc('"', file);
}

static const char *path_basename(const char *path)
{
    const char *cursor;
    const char *base;
    base = path;
    cursor = path;
    while (*cursor != 0) {
        if (*cursor == '/' || *cursor == '\\') base = cursor + 1;
        ++cursor;
    }
    return base;
}

static int path_is_within(const char *root, const char *path)
{
    size_t length;
    length = strlen(root);
    return strncmp(root, path, length) == 0 &&
           (path[length] == 0 || path[length] == '/');
}

static int same_existing_file(const char *left, const char *right)
{
    struct stat left_status;
    struct stat right_status;
    return stat(left, &left_status) == 0 &&
           stat(right, &right_status) == 0 &&
           left_status.st_dev == right_status.st_dev &&
           left_status.st_ino == right_status.st_ino;
}

static int existing_directory(const char *path)
{
    struct stat status;
    return stat(path, &status) == 0 && S_ISDIR(status.st_mode);
}

static int read_source_file(const char *path, char **data, la_u16 *length)
{
    FILE *file;
    long size;
    char *buffer;
    file = fopen(path, "rb");
    if (file == 0) return 0;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    size = ftell(file);
    if (size < 0 || size > 65534L || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        errno = EFBIG;
        return 0;
    }
    buffer = (char *)malloc((size_t)size + 1);
    if (buffer == 0) {
        fclose(file);
        return 0;
    }
    if (size != 0 && fread(buffer, 1, (size_t)size, file) != (size_t)size) {
        free(buffer);
        fclose(file);
        return 0;
    }
    buffer[size] = 0;
    fclose(file);
    *data = buffer;
    *length = (la_u16)size;
    return 1;
}

static const HostModule *host_module_by_id(const HostModules *modules,
                                           la_u16 source_id)
{
    la_u16 index;
    for (index = 0; index < modules->count; ++index) {
        if (modules->modules[index].view.source_id == source_id) {
            return &modules->modules[index];
        }
    }
    return 0;
}

static int add_host_module(HostModules *modules, const char *path,
                           const char *logical_name, LaSourceView *view)
{
    HostModule *module;
    la_u16 length;
    if (modules->count >= HOST_MAX_MODULES) return 0;
    module = &modules->modules[modules->count];
    memset(module, 0, sizeof(*module));
    module->path = strdup(path);
    module->logical_name = strdup(logical_name);
    if (module->path == 0 || module->logical_name == 0 ||
        !read_source_file(path, &module->data, &length)) {
        free(module->path);
        free(module->logical_name);
        memset(module, 0, sizeof(*module));
        return 0;
    }
    module->view.data = module->data;
    module->view.length = length;
    module->view.source_id = (la_u16)(modules->count + 1);
    module->view.name.data = module->logical_name;
    module->view.name.length = (la_u16)strlen(module->logical_name);
    *view = module->view;
    ++modules->count;
    return 1;
}

static int host_resolve(void *context, la_u16 including_source_id,
                        LaSlice requested, LaSourceView *source)
{
    HostModules *modules;
    const HostModule *parent;
    char request[PATH_MAX];
    char joined[PATH_MAX];
    char canonical[PATH_MAX];
    char directory[PATH_MAX];
    char *slash;
    const char *logical;
    size_t request_length;
    la_u16 index;
    modules = (HostModules *)context;
    parent = host_module_by_id(modules, including_source_id);
    request_length = requested.length;
    if (parent == 0 || request_length == 0 ||
        request_length >= sizeof(request)) return 0;
    memcpy(request, requested.data, request_length);
    request[request_length] = 0;
    if (request[0] == '/') return 0;
    if (strlen(parent->path) >= sizeof(directory)) return 0;
    strcpy(directory, parent->path);
    slash = strrchr(directory, '/');
    if (slash == 0) return 0;
    *slash = 0;
    if (snprintf(joined, sizeof(joined), "%s/%s", directory, request) >=
        (int)sizeof(joined)) return 0;
    if (realpath(joined, canonical) == 0 ||
        !path_is_within(modules->root_dir, canonical)) return 0;
    for (index = 0; index < modules->count; ++index) {
        if (strcmp(modules->modules[index].path, canonical) == 0) {
            *source = modules->modules[index].view;
            return 1;
        }
    }
    logical = canonical + strlen(modules->root_dir);
    if (*logical == '/') ++logical;
    return add_host_module(modules, canonical, logical, source);
}

static void free_host_modules(HostModules *modules)
{
    la_u16 index;
    for (index = 0; index < modules->count; ++index) {
        free(modules->modules[index].path);
        free(modules->modules[index].logical_name);
        free(modules->modules[index].data);
    }
    modules->count = 0;
}

static int ensure_source_map(HostOutput *output, unsigned line)
{
    unsigned next;
    HostSourceLocation *grown;
    if (line < output->source_capacity) return 1;
    next = output->source_capacity == 0 ? 256 : output->source_capacity;
    while (next <= line) next *= 2;
    grown = (HostSourceLocation *)calloc(next, sizeof(*grown));
    if (grown == 0) return 0;
    if (output->source_capacity != 0) {
        memcpy(grown, output->source_locations,
               output->source_capacity * sizeof(*grown));
    }
    free(output->source_locations);
    output->source_locations = grown;
    output->source_capacity = next;
    return 1;
}

static void free_host_output(HostOutput *output)
{
    free(output->source_locations);
    output->source_locations = 0;
    output->source_capacity = 0;
}

static void write_map_entry(HostOutput *output, LaSpan span,
                            const char *kind)
{
    if (output->map == 0) return;
    if (output->map_entries != 0) fputs(",\n", output->map);
    fprintf(output->map,
            "    {\"generatedLine\":%u,\"sourceLine\":%u,"
            "\"sourceColumn\":%u,\"sourceId\":%u,\"kind\":",
            output->generated_line, (unsigned)span.line,
            (unsigned)span.column, (unsigned)span.source_id);
    json_string(output->map, kind);
    fputc('}', output->map);
    ++output->map_entries;
}

static int begin_line(HostOutput *output, LaSpan span, const char *kind)
{
    ++output->generated_line;
    if (!ensure_source_map(output, output->generated_line)) {
        output->failed = 1;
        return 0;
    }
    output->source_locations[output->generated_line].line = span.line;
    output->source_locations[output->generated_line].source_id =
        span.source_id;
    write_map_entry(output, span, kind);
    return 1;
}

static void mangle_component(FILE *file, LaSlice component)
{
    fprintf(file, "%u_", (unsigned)component.length);
    if (component.length != 0) {
        fwrite(component.data, 1, component.length, file);
    }
}

static void mangle_path(FILE *file, LaSlice owner, LaSlice path)
{
    const char *cursor;
    const char *end;
    fputs("__la_", file);
    mangle_component(file, owner);
    cursor = path.data;
    end = path.data + path.length;
    while (cursor < end) {
        const char *dot;
        LaSlice component;
        dot = cursor;
        while (dot < end && *dot != '.') ++dot;
        fputs("__", file);
        component.data = cursor;
        component.length = (la_u16)(dot - cursor);
        mangle_component(file, component);
        cursor = dot < end ? dot + 1 : end;
    }
}

static const char *property_suffix(LaPropertyKind property)
{
    switch (property) {
    case LA_PROPERTY_STRUCT_SIZE: return "size";
    case LA_PROPERTY_STRUCT_ALIGN: return "align";
    case LA_PROPERTY_FIELD_OFFSET: return "offset";
    case LA_PROPERTY_FIELD_SIZE: return "size";
    case LA_PROPERTY_FIELD_COUNT: return "count";
    case LA_PROPERTY_FIELD_STRIDE: return "stride";
    default: return "unknown";
    }
}

static int slice_is_register(LaSlice slice)
{
    return slice.length == 1 &&
           (slice.data[0] == 'a' || slice.data[0] == 'x' ||
            slice.data[0] == 'y');
}

static int emit_pointer_displacement(HostOutput *output,
                                     const LaEvent *event)
{
    if (!begin_line(output, event->span, "target-operation")) return 0;
    fprintf(output->assembly, "    %s (%.*s), #",
            event->operation == LA_TARGET_OP_LOAD8_PTR_DISP ? "lda" : "sta",
            (int)event->base.length, event->base.data);
    mangle_path(output->assembly, event->owner, event->path);
    fprintf(output->assembly, "__offset ; inlay %.*s.%.*s\n",
            (int)event->owner.length, event->owner.data,
            (int)event->path.length, event->path.data);
    return 1;
}

static int emit_indexed_operation(HostOutput *output, const LaEvent *event)
{
    unsigned shifts;
    unsigned step;
    int store;
    store = event->operation == LA_TARGET_OP_STORE8_PTR_INDEXED;
    if (store) {
        if (!begin_line(output, event->span, "indexed-store")) return 0;
        fputs("    pha\n", output->assembly);
    }
    if (!begin_line(output, event->span, "indexed-address")) return 0;
    fputs("    txa\n", output->assembly);
    shifts = event->stride == 8 ? 3 :
             event->stride == 4 ? 2 :
             event->stride == 2 ? 1 : 0;
    for (step = 0; step < shifts; ++step) {
        if (!begin_line(output, event->span, "indexed-address")) return 0;
        fputs("    asl\n", output->assembly);
    }
    if (event->value != 0) {
        if (!begin_line(output, event->span, "indexed-address")) return 0;
        fprintf(output->assembly, "    add #%u\n", (unsigned)event->value);
    }
    if (!begin_line(output, event->span, "indexed-address")) return 0;
    fputs("    tay\n", output->assembly);
    if (store) {
        if (!begin_line(output, event->span, "indexed-store")) return 0;
        fputs("    pla\n", output->assembly);
    }
    if (!begin_line(output, event->span, "indexed-operation")) return 0;
    fprintf(output->assembly, "    %s (%.*s), y ; inlay %.*s.%.*s\n",
            store ? "sta" : "lda",
            (int)event->base.length, event->base.data,
            (int)event->owner.length, event->owner.data,
            (int)event->path.length, event->path.data);
    return 1;
}

static int emit_pool_address(HostOutput *output, const LaEvent *event)
{
    if (!begin_line(output, event->span, "pool-address")) return 0;
    fputs("    tax\n", output->assembly);
    if (!begin_line(output, event->span, "pool-address")) return 0;
    fprintf(output->assembly, "    mov %.*s, %.*s + x\n",
            (int)event->base.length, event->base.data,
            (int)event->aux.length, event->aux.data);
    if (!begin_line(output, event->span, "pool-address")) return 0;
    fprintf(output->assembly, "    lda %.*s, x\n",
            (int)event->aux2.length, event->aux2.data);
    if (!begin_line(output, event->span, "pool-address")) return 0;
    fprintf(output->assembly, "    sta %.*s+1\n",
            (int)event->base.length, event->base.data);
    return 1;
}

static int emit_procedure_start(HostOutput *output, const LaEvent *event)
{
    unsigned step;
    if (!begin_line(output, event->span, "procedure")) return 0;
    fprintf(output->assembly, "%.*s:\n",
            (int)event->owner.length, event->owner.data);
    if (event->operation == LA_TARGET_OP_PROC_FRAME) {
        for (step = 0; step < event->value; ++step) {
            if (!begin_line(output, event->span, "frame-prologue")) return 0;
            fputs("    pha\n", output->assembly);
        }
    }
    return 1;
}

static int emit_procedure_return(HostOutput *output, const LaEvent *event)
{
    unsigned step;
    if (event->value != 0) {
        if (!begin_line(output, event->span, "frame-epilogue")) return 0;
        fputs("    tsx\n", output->assembly);
        for (step = 0; step < event->value; ++step) {
            if (!begin_line(output, event->span, "frame-epilogue")) return 0;
            fputs("    inx\n", output->assembly);
        }
        if (!begin_line(output, event->span, "frame-epilogue")) return 0;
        fputs("    txs\n", output->assembly);
    }
    if (!begin_line(output, event->span, "procedure-return")) return 0;
    fputs("    rts\n", output->assembly);
    return 1;
}

static int emit_frame_local(HostOutput *output, const LaEvent *event)
{
    if (!begin_line(output, event->span, "frame-local")) return 0;
    fputs("    tsx\n", output->assembly);
    if (!begin_line(output, event->span, "frame-local")) return 0;
    fprintf(output->assembly, "    %s $%04x, x ; inlay local %.*s\n",
            event->operation == LA_TARGET_OP_LOAD8_FRAME_LOCAL ? "lda" : "sta",
            0x0100u + (unsigned)event->value,
            (int)event->path.length, event->path.data);
    return 1;
}

static int emit_frame_pointer(HostOutput *output, const LaEvent *event)
{
    unsigned step;
    int store;
    store = event->operation == LA_TARGET_OP_STORE_PTR_FRAME;
    if (!begin_line(output, event->span, "frame-pointer")) return 0;
    fputs("    tsx\n", output->assembly);
    for (step = 0; step < event->stride; ++step) {
        unsigned address;
        address = 0x0100u + (unsigned)event->value - step;
        if (!begin_line(output, event->span, "frame-pointer")) return 0;
        if (store) {
            fprintf(output->assembly, "    lda %.*s%s\n",
                    (int)event->base.length, event->base.data,
                    step == 0 ? "" : "+1");
            if (!begin_line(output, event->span, "frame-pointer")) return 0;
            fprintf(output->assembly, "    sta $%04x, x\n", address);
        } else {
            fprintf(output->assembly, "    lda $%04x, x\n", address);
            if (!begin_line(output, event->span, "frame-pointer")) return 0;
            fprintf(output->assembly, "    sta %.*s%s\n",
                    (int)event->base.length, event->base.data,
                    step == 0 ? "" : "+1");
        }
    }
    return 1;
}

static int emit_invoke_save(HostOutput *output, const LaEvent *event)
{
    unsigned step;
    if (event->stride == 1 && slice_is_register(event->aux)) {
        if (!begin_line(output, event->span, "invoke-snapshot")) return 0;
        fprintf(output->assembly, "    st%c %.*s%u\n",
                event->aux.data[0],
                (int)event->aux2.length, event->aux2.data,
                (unsigned)event->value);
        return 1;
    }
    for (step = 0; step < event->stride; ++step) {
        if (!begin_line(output, event->span, "invoke-snapshot")) return 0;
        fprintf(output->assembly, "    lda %.*s%s\n",
                (int)event->aux.length, event->aux.data,
                step == 0 ? "" : "+1");
        if (!begin_line(output, event->span, "invoke-snapshot")) return 0;
        fprintf(output->assembly, "    sta %.*s%u\n",
                (int)event->aux2.length, event->aux2.data,
                (unsigned)event->value + step);
    }
    return 1;
}

static int emit_invoke_assign(HostOutput *output, const LaEvent *event)
{
    unsigned step;
    if (event->count == LA_SOURCE_IMMEDIATE) {
        if (!begin_line(output, event->span, "invoke-assign")) return 0;
        if (slice_is_register(event->base)) {
            fprintf(output->assembly, "    ld%c #%u\n",
                    event->base.data[0], (unsigned)event->value);
        } else {
            fprintf(output->assembly, "    mov %.*s, #%u\n",
                    (int)event->base.length, event->base.data,
                    (unsigned)event->value);
        }
        return 1;
    }
    for (step = 0; step < event->stride; ++step) {
        if (!begin_line(output, event->span, "invoke-assign")) return 0;
        if (event->stride == 1 && slice_is_register(event->base)) {
            fprintf(output->assembly, "    ld%c %.*s%u\n",
                    event->base.data[0],
                    (int)event->aux2.length, event->aux2.data,
                    (unsigned)event->value);
        } else {
            fprintf(output->assembly, "    lda %.*s%u\n",
                    (int)event->aux2.length, event->aux2.data,
                    (unsigned)event->value + step);
            if (!begin_line(output, event->span, "invoke-assign")) return 0;
            fprintf(output->assembly, "    sta %.*s%s\n",
                    (int)event->base.length, event->base.data,
                    step == 0 ? "" : "+1");
        }
    }
    return 1;
}

static int emit_target_operation(HostOutput *output, const LaEvent *event)
{
    switch (event->operation) {
    case LA_TARGET_OP_LOAD8_PTR_DISP:
    case LA_TARGET_OP_STORE8_PTR_DISP:
        return emit_pointer_displacement(output, event);
    case LA_TARGET_OP_LOAD8_PTR_INDEXED:
    case LA_TARGET_OP_STORE8_PTR_INDEXED:
        return emit_indexed_operation(output, event);
    case LA_TARGET_OP_ADDRESS_POOL_TABLE:
        return emit_pool_address(output, event);
    case LA_TARGET_OP_PROC_FRAME:
    case LA_TARGET_OP_PROC_NAKED:
        return emit_procedure_start(output, event);
    case LA_TARGET_OP_PROC_RETURN:
        return emit_procedure_return(output, event);
    case LA_TARGET_OP_LOAD8_FRAME_LOCAL:
    case LA_TARGET_OP_STORE8_FRAME_LOCAL:
        return emit_frame_local(output, event);
    case LA_TARGET_OP_STORE_PTR_FRAME:
    case LA_TARGET_OP_LOAD_PTR_FRAME:
        return emit_frame_pointer(output, event);
    case LA_TARGET_OP_INVOKE_SAVE:
        return emit_invoke_save(output, event);
    case LA_TARGET_OP_INVOKE_ASSIGN:
        return emit_invoke_assign(output, event);
    case LA_TARGET_OP_INVOKE_CALL:
        if (!begin_line(output, event->span, "invoke-call")) return 0;
        fprintf(output->assembly, "    jsr %.*s\n",
                (int)event->owner.length, event->owner.data);
        return 1;
    default:
        return 0;
    }
}

static int host_event(void *context, const LaEvent *event)
{
    HostOutput *output;
    int emitted;
    output = (HostOutput *)context;
    if (output->failed) return 0;
    emitted = 1;
    switch (event->kind) {
    case LA_EVENT_HEADER:
        emitted = begin_line(output, event->span, "header");
        if (emitted) {
            fprintf(output->assembly,
                    "; generated by Inlay format %u, target %.*s/%u\n",
                    (unsigned)event->value, (int)event->owner.length,
                    event->owner.data, LA_TARGET_VERSION);
        }
        break;
    case LA_EVENT_PROPERTY:
        emitted = begin_line(output, event->span, "layout-property");
        if (emitted) {
            mangle_path(output->assembly, event->owner, event->path);
            fprintf(output->assembly, "__%s = %u\n",
                    property_suffix(event->property), (unsigned)event->value);
        }
        break;
    case LA_EVENT_PROCEDURE_MEMBER:
        emitted = begin_line(output, event->span, "procedure-member");
        if (!emitted) break;
        fprintf(output->assembly, "; inlay member %.*s.%.*s : %.*s ",
                (int)event->owner.length, event->owner.data,
                (int)event->path.length, event->path.data,
                (int)event->aux.length, event->aux.data);
        if (event->value == LA_MEMBER_FRAME) {
            fprintf(output->assembly, "in frame offset %u size %u\n",
                    (unsigned)event->offset, (unsigned)event->stride);
        } else {
            fprintf(output->assembly, "%s in %.*s\n",
                    event->value == LA_MEMBER_RETURN ? "return" : "input",
                    (int)event->base.length, event->base.data);
        }
        break;
    case LA_EVENT_RAW:
        emitted = begin_line(output, event->span, "raw");
        if (!emitted) break;
        if (event->text.length != 0) {
            fwrite(event->text.data, 1, event->text.length, output->assembly);
        }
        fputc('\n', output->assembly);
        break;
    case LA_EVENT_TARGET_OPERATION:
        emitted = emit_target_operation(output, event);
        break;
    default:
        emitted = 0;
        break;
    }
    if (!emitted || ferror(output->assembly) != 0) {
        output->failed = 1;
        return 0;
    }
    return 1;
}

static void print_slice(FILE *file, LaSlice slice)
{
    if (slice.length != 0) {
        fprintf(file, "%.*s", (int)slice.length, slice.data);
    }
}

static void host_diagnostic(void *context, const LaDiagnostic *diagnostic)
{
    HostDiagnostics *host;
    const HostModule *module;
    const char *name;
    host = (HostDiagnostics *)context;
    module = host_module_by_id(host->modules, diagnostic->span.source_id);
    name = module != 0 ? module->logical_name : host->input_path;
    if (diagnostic->span.line != 0) {
        fprintf(stderr, "%s:%u:%u: error[%s]",
                name, (unsigned)diagnostic->span.line,
                (unsigned)diagnostic->span.column,
                la_diagnostic_name(diagnostic->code));
    } else {
        fprintf(stderr, "inlay: error[%s]",
                la_diagnostic_name(diagnostic->code));
    }
    if (diagnostic->arg0.length != 0) {
        fputs(": ", stderr);
        print_slice(stderr, diagnostic->arg0);
    }
    if (diagnostic->arg1.length != 0) {
        fputs(" (", stderr);
        print_slice(stderr, diagnostic->arg1);
        fputc(')', stderr);
    }
    if (diagnostic->limit != 0 || diagnostic->value != 0) {
        fprintf(stderr, " [value=%ld limit=%ld]",
                (long)diagnostic->value, (long)diagnostic->limit);
    }
    fputc('\n', stderr);
}

static void usage(FILE *file)
{
    fputs(
        "Inlay Assembly — Structured assembly, close to the metal.\n"
        "\n"
        "usage: inlay --target console6502 --output FILE --map FILE "
        "[OPTIONS] INPUT.inlay.asm\n"
        "\n"
        "Compile Inlay Assembly to customasm source and a JSON map.\n"
        "\n"
        "Options:\n"
        "  -h, --help           show this help\n"
        "  --version            show frontend and format versions\n"
        "  --target TARGET      target backend (required; console6502)\n"
        "  -o, --output FILE    generated customasm destination (required)\n"
        "  --map FILE           generated JSON source map (required)\n"
        "  --stats              print compilation statistics as JSON\n"
        "  --check-customasm    validate generated source with customasm\n"
        "  --native             reserved; reports native output as deferred\n"
        "\n"
        "Example:\n"
        "  inlay --target console6502 --output game.asm "
        "--map game.map.json game.inlay.asm\n"
        "\n"
        "Exit status: 0 success, 1 source/validation error, 2 usage/host error.\n",
        file);
}

static void version(FILE *file)
{
    fprintf(file,
            "inlay 0.2 language-format=%u target-format=%u map-format=2\n",
            LA_FORMAT_VERSION, LA_TARGET_VERSION);
}

static int open_temporary(const char *destination, char *path,
                          size_t path_capacity, FILE **file)
{
    int descriptor;
    if (snprintf(path, path_capacity, "%s.tmp.XXXXXX", destination) >=
        (int)path_capacity) {
        errno = ENAMETOOLONG;
        return 0;
    }
    descriptor = mkstemp(path);
    if (descriptor < 0) return 0;
    *file = fdopen(descriptor, "wb");
    if (*file == 0) {
        int saved_errno;
        saved_errno = errno;
        close(descriptor);
        unlink(path);
        path[0] = 0;
        errno = saved_errno;
        return 0;
    }
    return 1;
}

static void discard_artifacts(HostArtifacts *artifacts)
{
    if (artifacts->assembly != 0) {
        fclose(artifacts->assembly);
        artifacts->assembly = 0;
    }
    if (artifacts->map != 0) {
        fclose(artifacts->map);
        artifacts->map = 0;
    }
    if (artifacts->assembly_path[0] != 0) {
        unlink(artifacts->assembly_path);
        artifacts->assembly_path[0] = 0;
    }
    if (artifacts->map_path[0] != 0) {
        unlink(artifacts->map_path);
        artifacts->map_path[0] = 0;
    }
}

static int open_artifacts(const HostOptions *options,
                          HostArtifacts *artifacts)
{
    memset(artifacts, 0, sizeof(*artifacts));
    if (!open_temporary(options->output_path, artifacts->assembly_path,
                        sizeof(artifacts->assembly_path),
                        &artifacts->assembly)) {
        fprintf(stderr, "inlay: cannot create %s: %s\n",
                options->output_path, strerror(errno));
        return 0;
    }
    if (!open_temporary(options->map_path, artifacts->map_path,
                        sizeof(artifacts->map_path), &artifacts->map)) {
        fprintf(stderr, "inlay: cannot create %s: %s\n",
                options->map_path, strerror(errno));
        discard_artifacts(artifacts);
        return 0;
    }
    return 1;
}

static int close_artifacts(HostArtifacts *artifacts)
{
    int ok;
    ok = 1;
    if (artifacts->assembly != 0) {
        if (fclose(artifacts->assembly) != 0) ok = 0;
        artifacts->assembly = 0;
    }
    if (artifacts->map != 0) {
        if (fclose(artifacts->map) != 0) ok = 0;
        artifacts->map = 0;
    }
    return ok;
}

static int publish_artifacts(const HostOptions *options,
                             HostArtifacts *artifacts)
{
    if (rename(artifacts->map_path, options->map_path) != 0) {
        fprintf(stderr, "inlay: cannot publish %s: %s\n",
                options->map_path, strerror(errno));
        return 0;
    }
    artifacts->map_path[0] = 0;
    if (rename(artifacts->assembly_path, options->output_path) != 0) {
        fprintf(stderr, "inlay: cannot publish %s: %s\n",
                options->output_path, strerror(errno));
        return 0;
    }
    artifacts->assembly_path[0] = 0;
    return 1;
}

static int shell_quote(char *destination, size_t capacity, const char *source)
{
    size_t used;
    used = 0;
    if (capacity < 3) return 0;
    destination[used++] = '\'';
    while (*source != 0) {
        if (*source == '\'') {
            if (used + 4 >= capacity) return 0;
            memcpy(destination + used, "'\\''", 4);
            used += 4;
        } else {
            if (used + 1 >= capacity) return 0;
            destination[used++] = *source;
        }
        ++source;
    }
    destination[used++] = '\'';
    destination[used] = 0;
    return 1;
}

static int run_customasm(const char *output_path, HostOutput *output)
{
    char quoted_output[PATH_MAX * 4 + 3];
    char quoted_binary[PATH_MAX * 4 + 3];
    char command[PATH_MAX * 8 + 256];
    char line[4096];
    char binary_path[PATH_MAX];
    const char *temporary_directory;
    FILE *pipe;
    int descriptor;
    int status;
    temporary_directory = getenv("TMPDIR");
    if (temporary_directory == 0 || temporary_directory[0] == 0) {
        temporary_directory = "/tmp";
    }
    if (snprintf(binary_path, sizeof(binary_path),
                 "%s/inlay-check.XXXXXX", temporary_directory) >=
        (int)sizeof(binary_path)) {
        fputs("inlay: temporary directory path is too long\n", stderr);
        return 0;
    }
    descriptor = mkstemp(binary_path);
    if (descriptor < 0) {
        fprintf(stderr, "inlay: cannot create validation output: %s\n",
                strerror(errno));
        return 0;
    }
    close(descriptor);
    if (!shell_quote(quoted_output, sizeof(quoted_output), output_path) ||
        !shell_quote(quoted_binary, sizeof(quoted_binary), binary_path)) {
        fputs("inlay: generated path is too long for customasm wrapper\n",
              stderr);
        unlink(binary_path);
        return 0;
    }
    if (snprintf(command, sizeof(command),
                 "customasm %s -t 10 --color=off "
                 "-f binary -o %s 2>&1",
                 quoted_output, quoted_binary) >= (int)sizeof(command)) {
        fputs("inlay: customasm command is too long\n", stderr);
        unlink(binary_path);
        return 0;
    }
    pipe = popen(command, "r");
    if (pipe == 0) {
        fprintf(stderr, "inlay: cannot run customasm: %s\n", strerror(errno));
        unlink(binary_path);
        return 0;
    }
    while (fgets(line, sizeof(line), pipe) != 0) {
        char *match;
        match = strstr(line, output_path);
        if (match != 0) {
            char *number;
            unsigned generated;
            number = match + strlen(output_path);
            if (*number == ':') ++number;
            generated = (unsigned)strtoul(number, 0, 10);
            if (generated < output->source_capacity &&
                output->source_locations[generated].line != 0) {
                const HostModule *module;
                module = host_module_by_id(
                    output->modules,
                    (la_u16)output->source_locations[generated].source_id);
                fprintf(stderr, "%s:%u: customasm: %s",
                        module != 0 ? module->logical_name :
                                      output->input_path,
                        output->source_locations[generated].line, line);
                continue;
            }
        }
        fputs(line, stderr);
    }
    status = pclose(pipe);
    unlink(binary_path);
    return status == 0;
}

static int option_value(int argc, char **argv, int *index,
                        const char *option, const char **destination)
{
    if (*index + 1 >= argc) {
        fprintf(stderr, "inlay: option %s requires a value\n", option);
        return 0;
    }
    *destination = argv[++*index];
    return 1;
}

static int parse_options(int argc, char **argv, HostOptions *options,
                         int *run)
{
    int native;
    int index;
    int positional_only;
    memset(options, 0, sizeof(*options));
    *run = 0;
    native = 0;
    positional_only = 0;
    for (index = 1; index < argc; ++index) {
        if (!positional_only &&
            (strcmp(argv[index], "--help") == 0 ||
             strcmp(argv[index], "-h") == 0)) {
            usage(stdout);
            return 0;
        } else if (!positional_only &&
                   strcmp(argv[index], "--version") == 0) {
            version(stdout);
            return 0;
        } else if (!positional_only &&
                   strcmp(argv[index], "--target") == 0) {
            if (!option_value(argc, argv, &index, "--target",
                              &options->target_name)) return 2;
        } else if (!positional_only &&
            (strcmp(argv[index], "--output") == 0 ||
                    strcmp(argv[index], "-o") == 0)) {
            if (!option_value(argc, argv, &index, "--output",
                              &options->output_path)) return 2;
        } else if (!positional_only &&
                   strcmp(argv[index], "--map") == 0) {
            if (!option_value(argc, argv, &index, "--map",
                              &options->map_path)) return 2;
        } else if (!positional_only &&
                   strcmp(argv[index], "--stats") == 0) {
            options->print_stats = 1;
        } else if (!positional_only &&
                   strcmp(argv[index], "--check-customasm") == 0) {
            options->check_customasm = 1;
        } else if (!positional_only &&
                   strcmp(argv[index], "--native") == 0) {
            native = 1;
        } else if (!positional_only && strcmp(argv[index], "--") == 0) {
            positional_only = 1;
        } else if (!positional_only && argv[index][0] == '-') {
            fprintf(stderr, "inlay: unknown option: %s\n", argv[index]);
            usage(stderr);
            return 2;
        } else if (options->input_path == 0) {
            options->input_path = argv[index];
        } else {
            fputs("inlay: only one input file is supported\n", stderr);
            return 2;
        }
    }
    if (native) {
        fputs("inlay: error[native-output-deferred]: direct machine-code "
              "emission is deferred\n", stderr);
        return 2;
    }
    if (options->target_name == 0 || options->output_path == 0 ||
        options->map_path == 0 || options->input_path == 0) {
        usage(stderr);
        return 2;
    }
    if (strcmp(options->target_name, la_target_console6502.name) != 0) {
        fprintf(stderr, "inlay: unknown target '%s'; available: %s\n",
                options->target_name, la_target_console6502.name);
        return 2;
    }
    if (strcmp(options->input_path, options->output_path) == 0 ||
        strcmp(options->input_path, options->map_path) == 0) {
        fputs("inlay: refusing to overwrite the input file\n", stderr);
        return 2;
    }
    if (strcmp(options->output_path, options->map_path) == 0) {
        fputs("inlay: output and map must be different files\n", stderr);
        return 2;
    }
    if (existing_directory(options->output_path) ||
        existing_directory(options->map_path)) {
        fputs("inlay: output and map destinations must be files\n", stderr);
        return 2;
    }
    if (same_existing_file(options->output_path, options->map_path)) {
        fputs("inlay: output and map must be different files\n", stderr);
        return 2;
    }
    *run = 1;
    return 0;
}

int main(int argc, char **argv)
{
    HostOptions options;
    HostArtifacts artifacts;
    int run;
    int parse_status;
    char canonical_input[PATH_MAX];
    char root_copy[PATH_MAX];
    char *root_slash;
    HostModules host_modules;
    HostOutput host_output;
    HostDiagnostics host_diagnostics;
    LaEventSink events;
    LaDiagnosticSink diagnostics;
    LaLimits limits;
    LaModuleLimits module_limits;
    LaModuleResolver resolver;
    LaExpandedInput expanded;
    LaWorkspace workspace;
    LaWorkspace module_workspace;
    LaStats stats;
    LaDiagnosticCode result;
    la_u16 source_index;
    parse_status = parse_options(argc, argv, &options, &run);
    if (!run) return parse_status;
    if (realpath(options.input_path, canonical_input) == 0) {
        fprintf(stderr, "inlay: cannot open %s: %s\n",
                options.input_path, strerror(errno));
        return 2;
    }
    if (same_existing_file(options.input_path, options.output_path) ||
        same_existing_file(options.input_path, options.map_path)) {
        fputs("inlay: refusing to overwrite the input file\n", stderr);
        return 2;
    }
    memset(&host_modules, 0, sizeof(host_modules));
    strcpy(root_copy, canonical_input);
    root_slash = strrchr(root_copy, '/');
    if (root_slash == 0) {
        fputs("inlay: input path has no directory\n", stderr);
        return 2;
    }
    *root_slash = 0;
    strcpy(host_modules.root_dir, root_copy);
    if (!add_host_module(&host_modules, canonical_input,
                         path_basename(canonical_input),
                         &host_modules.modules[0].view)) {
        fprintf(stderr, "inlay: cannot load %s: %s\n",
                options.input_path, strerror(errno));
        return 2;
    }
    memset(&host_output, 0, sizeof(host_output));
    host_output.input_path = options.input_path;
    host_output.modules = &host_modules;
    host_diagnostics.input_path = options.input_path;
    host_diagnostics.modules = &host_modules;
    diagnostics.write = host_diagnostic;
    diagnostics.context = &host_diagnostics;
    resolver.resolve = host_resolve;
    resolver.context = &host_modules;
    module_limits = la_default_module_limits();
    module_limits.max_source_bytes = 65534;
    module_limits.max_source_lines = 12000;
    module_workspace.size = la_module_workspace_required(&module_limits);
    module_workspace.data = malloc((size_t)module_workspace.size);
    if (module_workspace.data == 0) {
        fputs("inlay: cannot allocate module workspace\n", stderr);
        free_host_modules(&host_modules);
        return 2;
    }
    result = la_expand_modules(&host_modules.modules[0].view, &resolver,
                               &diagnostics, &module_limits,
                               module_workspace, &expanded);
    if (result != LA_OK) {
        free(module_workspace.data);
        free_host_modules(&host_modules);
        return 1;
    }
    if (!open_artifacts(&options, &artifacts)) {
        free(module_workspace.data);
        free_host_modules(&host_modules);
        return 2;
    }
    host_output.assembly = artifacts.assembly;
    host_output.map = artifacts.map;
    fputs("{\n  \"format\":2,\n  \"sources\":[\n", artifacts.map);
    for (source_index = 0; source_index < expanded.source_count;
         ++source_index) {
        if (source_index != 0) fputs(",\n", artifacts.map);
        fprintf(artifacts.map, "    {\"id\":%u,\"name\":",
                (unsigned)expanded.sources[source_index].source_id);
        json_string(artifacts.map,
                    host_modules.modules[source_index].logical_name);
        fputc('}', artifacts.map);
    }
    fputs("\n  ],\n  \"generated\":", artifacts.map);
    json_string(artifacts.map, path_basename(options.output_path));
    fputs(",\n  \"mappings\":[\n", artifacts.map);
    events.write = host_event;
    events.context = &host_output;
    limits = la_default_limits();
    limits.max_source_bytes = 65534;
    workspace.size = la_workspace_required(&limits);
    workspace.data = malloc((size_t)workspace.size);
    if (workspace.data == 0) {
        fputs("inlay: cannot allocate host workspace\n", stderr);
        discard_artifacts(&artifacts);
        free(module_workspace.data);
        free_host_modules(&host_modules);
        return 2;
    }
    result = la_compile(&expanded.input, &events, &diagnostics,
                        &la_target_console6502, &limits, workspace, &stats);
    fputs("\n  ]\n}\n", artifacts.map);
    free(workspace.data);
    if (!close_artifacts(&artifacts)) host_output.failed = 1;
    if (result != LA_OK || host_output.failed) {
        discard_artifacts(&artifacts);
        free_host_output(&host_output);
        free(module_workspace.data);
        free_host_modules(&host_modules);
        return 1;
    }
    if (options.print_stats) {
        printf("{\"format\":1,"
               "\"sourceBytes\":%u,\"nameBytes\":%u,\"tokens\":%u,"
               "\"structures\":%u,\"fields\":%u,\"locations\":%u,"
               "\"pools\":%u,\"procedures\":%u,\"parameters\":%u,"
               "\"locals\":%u,\"invokeBindings\":%u,"
               "\"expressionNodes\":%u,\"nesting\":%u,"
               "\"operations\":%u,\"workspaceBytes\":%lu,"
               "\"moduleBytes\":%u,\"moduleLines\":%u,"
               "\"moduleDepth\":%u,\"moduleWorkspaceBytes\":%lu}\n",
               stats.source_bytes, stats.name_bytes, stats.tokens,
               stats.structures, stats.fields, stats.locations,
               stats.pools, stats.procedures, stats.parameters, stats.locals,
               stats.invoke_bindings,
               stats.expression_nodes, stats.nesting, stats.operations,
               (unsigned long)stats.workspace_used,
               expanded.expanded_bytes, expanded.expanded_lines,
               expanded.max_depth,
               (unsigned long)module_workspace.size);
    }
    if (options.check_customasm &&
        !run_customasm(artifacts.assembly_path, &host_output)) {
        discard_artifacts(&artifacts);
        free_host_output(&host_output);
        free(module_workspace.data);
        free_host_modules(&host_modules);
        return 1;
    }
    if (!publish_artifacts(&options, &artifacts)) {
        discard_artifacts(&artifacts);
        free_host_output(&host_output);
        free(module_workspace.data);
        free_host_modules(&host_modules);
        return 2;
    }
    free_host_output(&host_output);
    free(module_workspace.data);
    free_host_modules(&host_modules);
    return 0;
}
