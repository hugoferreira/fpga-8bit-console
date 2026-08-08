/* Inlay core: Layout resolution: field offsets and alignment, path and
   indexed-path resolution, and the property events they emit. */

#include "inlay_internal.h"

static la_u16 la_round_up(la_u16 value, la_u16 alignment);
static la_u16 la_find_field(LaContext *ctx, la_u16 sid,
                            const char *name, la_u16 length);
static int la_emit_field_offset(LaContext *ctx, LaFieldRec *field,
                                LaSlice owner, LaSlice path, la_u16 value);
static int la_append_path(LaContext *ctx, la_u16 *path_length,
                          LaSlice component);

LaDiagnosticCode la_resolve_enums(LaContext *ctx)
{
    la_u16 index;
    for (index = 0; index < ctx->enum_member_count; ++index) {
        LaEnumMemberRec *member;
        LaEnumRec *owner;
        la_i32 value;
        la_i32 minimum;
        la_i32 maximum;
        member = &ctx->enum_members[index];
        owner = &ctx->enums[member->owner];
        ctx->active_source_id = owner->source_id;
        if (la_eval_expression(
                ctx, member->value_source,
                member->value_source + member->value_length,
                member->line, &value) != LA_OK) return ctx->error;
        if (owner->is_signed) {
            minimum = owner->size == 1 ? -128 : -32768;
            maximum = owner->size == 1 ? 127 : 32767;
        } else {
            minimum = 0;
            maximum = owner->size == 1 ? 255 : 65535;
        }
        if (value < minimum || value > maximum) {
            return la_bound(ctx, LA_ERR_ENUM_VALUE, member->line, 1,
                            la_name_slice(ctx, member->name),
                            la_name_slice(ctx, owner->name), value, maximum);
        }
        member->value = value;
        member->resolved = 1;
    }
    return LA_OK;
}

static la_u16 la_round_up(la_u16 value, la_u16 alignment)
{
    la_u32 result;
    result = ((la_u32)value + alignment - 1) &
             ~((la_u32)alignment - 1);
    return result > 65535 ? LA_INVALID_HANDLE : (la_u16)result;
}

LaDiagnosticCode la_resolve_layouts(LaContext *ctx)
{
    la_u16 unresolved;
    la_u16 index;
    int progress;
    for (index = 0; index < ctx->location_count; ++index) {
        if (ctx->locations[index].is_pointer) {
            if (la_find_struct_handle(ctx, ctx->locations[index].type_name) ==
                LA_INVALID_HANDLE) {
                return la_reject(ctx, LA_ERR_UNKNOWN_TYPE,
                                 ctx->locations[index].line, la_name_slice(ctx,
                                 ctx->locations[index].type_name));
            }
        } else {
            la_u16 size;
            if (!la_scalar_size(ctx, ctx->locations[index].type_name,
                                &size)) {
                return la_expected(ctx, LA_ERR_UNKNOWN_TYPE,
                                   ctx->locations[index].line,
                                   la_name_slice(ctx,
                                   ctx->locations[index].type_name),
                                   la_text("scalar parameter"));
            }
        }
    }
    unresolved = ctx->struct_count;
    do {
        progress = 0;
        for (index = 0; index < ctx->struct_count; ++index) {
            LaStructRec *record;
            la_u16 field_index;
            la_u16 offset;
            la_u16 extent;
            int ready;
            record = &ctx->structs[index];
            if (record->state != 0) {
                continue;
            }
            ready = 1;
            offset = 0;
            extent = 0;
            for (field_index = record->first_field;
                 field_index < record->first_field + record->field_count;
                 ++field_index) {
                LaFieldRec *field;
                la_u16 unit_size;
                la_u16 unit_alignment;
                la_u16 nested;
                la_u16 enumeration;
                la_u16 placement;
                field = &ctx->fields[field_index];
                nested = LA_INVALID_HANDLE;
                enumeration = LA_INVALID_HANDLE;
                if (field->is_pointer) {
                    nested = la_find_struct_handle(ctx, field->type_name);
                    if (nested == LA_INVALID_HANDLE) {
                        return la_expected(ctx, LA_ERR_UNKNOWN_TYPE,
                                           field->line, la_name_slice(ctx,
                                           field->type_name),
                                           la_name_slice(ctx, record->name));
                    }
                    unit_size = ctx->target->pointer_units;
                    unit_alignment = unit_size;
                } else if (!la_primitive_size(ctx, field->type_name,
                                              &unit_size)) {
                    enumeration =
                        la_find_enum_handle(ctx, field->type_name);
                    if (enumeration != LA_INVALID_HANDLE) {
                        unit_size = ctx->enums[enumeration].size;
                        unit_alignment = unit_size;
                    } else {
                    nested = la_find_struct_handle(ctx, field->type_name);
                    if (nested == LA_INVALID_HANDLE) {
                        return la_expected(ctx, LA_ERR_UNKNOWN_TYPE,
                                           field->line, la_name_slice(ctx,
                                           field->type_name),
                                           la_name_slice(ctx, record->name));
                    }
                    if (ctx->structs[nested].state == 0) {
                        ready = 0;
                        break;
                    }
                    unit_size = ctx->structs[nested].size;
                    unit_alignment = ctx->structs[nested].alignment;
                    }
                } else {
                    unit_alignment = unit_size;
                }
                if (record->policy == LA_LAYOUT_PACKED) {
                    unit_alignment = 1;
                } else if (unit_alignment > record->alignment) {
                    unit_alignment = record->alignment;
                }
                placement = record->kind == LA_AGGREGATE_UNION ? 0 : offset;
                if (record->kind == LA_AGGREGATE_STRUCT &&
                    field->has_explicit_offset) {
                    la_i32 requested;
                    ctx->active_source_id = record->source_id;
                    if (la_eval_expression(
                            ctx, field->offset_source,
                            field->offset_source + field->offset_length,
                            field->line, &requested) != LA_OK) {
                        return ctx->error;
                    }
                    if (requested < 0 || requested > 65535 ||
                        requested < offset) {
                        return la_bound(ctx, LA_ERR_FIELD_OFFSET, field->line,
                                        1, la_name_slice(ctx, field->name),
                                        la_name_slice(ctx, record->name),
                                        requested, offset);
                    }
                    if ((requested % unit_alignment) != 0) {
                        return la_bound(ctx, LA_ERR_FIELD_OFFSET, field->line,
                                        1, la_name_slice(ctx, field->name),
                                        la_text("effective alignment"),
                                        requested, unit_alignment);
                    }
                    placement = (la_u16)requested;
                } else if (record->kind == LA_AGGREGATE_STRUCT &&
                           record->policy == LA_LAYOUT_ALIGNED) {
                    placement = la_round_up(offset, unit_alignment);
                    if (placement == LA_INVALID_HANDLE) {
                        return la_bound(ctx, LA_ERR_FIELD_OFFSET, field->line,
                                        1, la_name_slice(ctx, field->name),
                                        la_text("layout overflow"), offset,
                                        65535);
                    }
                }
                if ((la_u32)unit_size * field->count + placement > 65535) {
                    return la_bound(ctx, LA_ERR_SYNTAX, field->line, 1,
                                    la_text("layout overflow"),
                                    la_name_slice(ctx, field->name), 0, 65535);
                }
                field->offset = placement;
                field->size = (la_u16)(unit_size * field->count);
                if (record->kind == LA_AGGREGATE_STRUCT) {
                    offset = (la_u16)(placement + field->size);
                    extent = offset;
                } else if (field->size > extent) {
                    extent = field->size;
                }
            }
            if (ready) {
                if (record->policy == LA_LAYOUT_ALIGNED) {
                    record->size = la_round_up(extent, record->alignment);
                    if (record->size == LA_INVALID_HANDLE) {
                        return la_bound(ctx, LA_ERR_LAYOUT_ALIGNMENT,
                                        record->line, 1, la_name_slice(ctx,
                                        record->name),
                                        la_text("layout overflow"), extent,
                                        65535);
                    }
                } else {
                    record->size = extent;
                }
                record->state = 1;
                --unresolved;
                progress = 1;
            }
        }
    } while (unresolved != 0 && progress);
    if (unresolved != 0) {
        for (index = 0; index < ctx->struct_count; ++index) {
            if (ctx->structs[index].state == 0) {
                return la_bound(ctx, LA_ERR_LAYOUT_CYCLE,
                                ctx->structs[index].line, 1, la_name_slice(ctx,
                                ctx->structs[index].name), la_text(""),
                                unresolved, 0);
            }
        }
    }
    for (index = 0; index < ctx->pool_count; ++index) {
        la_u16 sid;
        LaPoolRec *pool;
        pool = &ctx->pools[index];
        sid = la_find_struct_handle(ctx, pool->type_name);
        if (sid == LA_INVALID_HANDLE) {
            return la_expected(ctx, LA_ERR_UNKNOWN_TYPE, pool->line,
                               la_name_slice(ctx, pool->type_name),
                               la_name_slice(ctx, pool->name));
        }
        pool->stride = ctx->structs[sid].size;
        pool->alignment = ctx->structs[sid].alignment;
        if ((la_u32)pool->stride * pool->count > 65535) {
            return la_bound(ctx, LA_ERR_SYNTAX, pool->line, 1,
                            la_text("pool size overflow"), la_name_slice(ctx,
                            pool->name), (la_i32)((la_u32)pool->stride *
                            pool->count), 65535);
        }
        pool->size = (la_u16)(pool->stride * pool->count);
    }
    for (index = 0; index < ctx->overlay_count; ++index) {
        la_u16 sid;
        LaOverlayRec *overlay;
        overlay = &ctx->overlays[index];
        sid = la_find_struct_handle(ctx, overlay->type_name);
        if (sid == LA_INVALID_HANDLE) {
            return la_expected(ctx, LA_ERR_OVERLAY_TYPE, overlay->line,
                               la_name_slice(ctx, overlay->type_name),
                               la_name_slice(ctx, overlay->name));
        }
        if (overlay->has_numeric_base &&
            overlay->numeric_base % ctx->structs[sid].alignment != 0) {
            return la_bound(ctx, LA_ERR_OVERLAY_ALIGNMENT, overlay->line, 1,
                            la_name_slice(ctx, overlay->name),
                            la_name_slice(ctx, overlay->type_name),
                            overlay->numeric_base,
                            ctx->structs[sid].alignment);
        }
    }
    for (index = 0; index < ctx->procedure_count; ++index) {
        LaProcedureRec *procedure;
        const LaConvention *convention;
        la_u16 member_index;
        la_u16 local_index;
        la_u16 scalar_slot;
        procedure = &ctx->procedures[index];
        convention = procedure->convention == LA_INVALID_HANDLE ? 0 :
            &ctx->target->conventions[procedure->convention];
        scalar_slot = 0;
        for (member_index = procedure->first_parameter;
             member_index < procedure->first_parameter +
                            procedure->parameter_count;
             ++member_index) {
            LaLocationRec *member;
            member = &ctx->locations[member_index];
            member->storage_width =
                la_location_storage_units(ctx, member_index);
            if (member->physical != LA_INVALID_HANDLE) {
                LaSlice placement;
                la_u16 declared;
                placement = la_name_slice(ctx, member->physical);
                declared = la_find_location_text(
                    ctx, placement.data, placement.length);
                if (declared != LA_INVALID_HANDLE &&
                    ctx->locations[declared].procedure ==
                        LA_INVALID_HANDLE) {
                    if (member->storage_width !=
                        ctx->locations[declared].storage_width ||
                        member->is_pointer !=
                        ctx->locations[declared].is_pointer) {
                        return la_bound(ctx, LA_ERR_MEMBER_PLACEMENT,
                            member->line, placement.length, placement,
                            la_text("compatible typed location"),
                            member->storage_width,
                            ctx->locations[declared].storage_width);
                    }
                    member->physical = ctx->locations[declared].physical;
                    continue;
                }
                if (memchr(placement.data, '.', placement.length) != 0) {
                    return la_reject_at(ctx, LA_ERR_MEMBER_PLACEMENT,
                        member->line, placement.length, placement,
                        la_text("declared qualified location"));
                }
                continue;
            }
            if (procedure->convention == LA_INVALID_HANDLE) {
                return la_expected(ctx, LA_ERR_MEMBER_PLACEMENT, member->line,
                                   la_name_slice(ctx, member->name),
                                   la_text("using convention or in physical"));
            }
            if (member->is_pointer) {
                return la_expected(ctx, LA_ERR_MEMBER_PLACEMENT, member->line,
                                   la_name_slice(ctx, member->name),
                                   la_text("explicit pointer location"));
            }
            if (member->role == LA_MEMBER_RETURN) {
                member->physical = la_intern(
                    ctx, convention->scalar_return,
                    (la_u16)strlen(convention->scalar_return),
                    member->line, 1);
            } else {
                int assigned;
                assigned = 0;
                while (scalar_slot < convention->scalar_input_count &&
                       !assigned) {
                    la_u16 other_index;
                    int used;
                    used = 0;
                    for (other_index = procedure->first_parameter;
                         other_index < procedure->first_parameter +
                                       procedure->parameter_count;
                         ++other_index) {
                        LaLocationRec *other;
                        LaSlice physical;
                        other = &ctx->locations[other_index];
                        if (other == member ||
                            other->physical == LA_INVALID_HANDLE ||
                            other->role != LA_MEMBER_INPUT) continue;
                        physical = la_name_slice(ctx, other->physical);
                        if (la_equal_text(physical.data, physical.length,
                                          convention->
                                              scalar_inputs[scalar_slot])) {
                            used = 1;
                            break;
                        }
                    }
                    if (!used) {
                        member->physical = la_intern(
                            ctx, convention->scalar_inputs[scalar_slot],
                            (la_u16)strlen(
                                convention->scalar_inputs[scalar_slot]),
                            member->line, 1);
                        assigned = 1;
                    }
                    ++scalar_slot;
                }
                if (!assigned) {
                    return la_bound(ctx, LA_ERR_CONVENTION, member->line, 1,
                                    la_name_slice(ctx, member->name),
                                    la_text("scalar input locations"),
                                    convention->scalar_input_count + 1,
                                    convention->scalar_input_count);
                }
            }
            if (member->physical == LA_INVALID_HANDLE) return ctx->error;
        }
        procedure->frame_size = 0;
        for (local_index = procedure->first_local;
             local_index < procedure->first_local + procedure->local_count;
             ++local_index) {
            LaLocalRec *local;
            la_u16 size;
            local = &ctx->locals[local_index];
            if (local->is_pointer) {
                if (la_find_struct_handle(ctx, local->type_name) ==
                    LA_INVALID_HANDLE) {
                    return la_expected(ctx, LA_ERR_UNKNOWN_TYPE, local->line,
                                       la_name_slice(ctx, local->type_name),
                                       la_text("pointer local"));
                }
                size = ctx->target->pointer_units;
            } else if (!la_scalar_size(ctx, local->type_name, &size)) {
                la_u16 sid;
                sid = la_find_struct_handle(ctx, local->type_name);
                if (sid == LA_INVALID_HANDLE) {
                    return la_expected(ctx, LA_ERR_UNKNOWN_TYPE, local->line,
                                       la_name_slice(ctx, local->type_name),
                                       la_text("frame local"));
                }
                size = ctx->structs[sid].size;
                if (ctx->structs[sid].alignment >
                    ctx->target->max_frame_alignment) {
                    return la_bound(ctx, LA_ERR_LAYOUT_ALIGNMENT, local->line,
                                    1, la_name_slice(ctx, local->name),
                                    la_text("frame alignment"),
                                    ctx->structs[sid].alignment,
                                    ctx->target->max_frame_alignment);
                }
            }
            if ((la_u32)procedure->frame_size + size > 255) {
                return la_bound(ctx, LA_ERR_FRAME_LOCAL, local->line, 1,
                                la_name_slice(ctx, local->name),
                                la_text("frame bytes"), procedure->frame_size +
                                size, 255);
            }
            local->offset = procedure->frame_size;
            local->size = size;
            procedure->frame_size =
                (la_u16)(procedure->frame_size + size);
        }
    }
    return LA_OK;
}

static la_u16 la_find_field(LaContext *ctx, la_u16 sid,
                            const char *name, la_u16 length)
{
    la_u16 index;
    LaStructRec *record;
    record = &ctx->structs[sid];
    for (index = record->first_field;
         index < record->first_field + record->field_count; ++index) {
        LaSlice field_name;
        field_name = la_name_slice(ctx, ctx->fields[index].name);
        if (field_name.length == length &&
            memcmp(field_name.data, name, length) == 0) {
            return index;
        }
    }
    return LA_INVALID_HANDLE;
}

LaDiagnosticCode la_resolve_path(LaContext *ctx,
                                        const char *root, la_u16 root_length,
                                        const char *path, la_u16 path_length,
                                        la_u16 line, la_u16 *field_out,
                                        la_u16 *offset_out)
{
    la_u16 sid;
    la_u16 total;
    const char *cursor;
    const char *end;
    sid = la_find_struct_text(ctx, root, root_length);
    if (sid == LA_INVALID_HANDLE) {
        return la_reject_at(ctx, LA_ERR_UNKNOWN_TYPE, line, root_length,
                            la_slice(root, root_length), la_text(""));
    }
    total = 0;
    cursor = path;
    end = path + path_length;
    while (cursor < end) {
        const char *component_end;
        la_u16 field_index;
        component_end = cursor;
        while (component_end < end && *component_end != '.') {
            ++component_end;
        }
        field_index = la_find_field(ctx, sid, cursor,
                                    (la_u16)(component_end - cursor));
        if (field_index == LA_INVALID_HANDLE) {
            return la_reject_at(ctx, LA_ERR_UNKNOWN_FIELD, line,
                                (la_u16)(component_end - cursor),
                                la_slice(cursor, (la_u16)(component_end -
                                cursor)), la_name_slice(ctx,
                                ctx->structs[sid].name));
        }
        total = (la_u16)(total + ctx->fields[field_index].offset);
        if (component_end == end) {
            *field_out = field_index;
            *offset_out = total;
            return LA_OK;
        }
        if (ctx->fields[field_index].is_pointer) {
            sid = LA_INVALID_HANDLE;
        } else {
            sid = la_find_struct_handle(ctx,
                                        ctx->fields[field_index].type_name);
        }
        if (sid == LA_INVALID_HANDLE || ctx->fields[field_index].count != 1) {
            return la_reject_at(ctx, LA_ERR_UNKNOWN_FIELD, line,
                                (la_u16)(component_end - cursor),
                                la_slice(cursor, (la_u16)(component_end -
                                cursor)), la_text("non-structure"));
        }
        cursor = component_end + 1;
    }
    return la_reject_at(ctx, LA_ERR_UNKNOWN_FIELD, line, path_length,
                        la_slice(path, path_length), la_text(""));
}

LaDiagnosticCode la_resolve_indexed_path(
    LaContext *ctx, const char *root, la_u16 root_length,
    const char *path, la_u16 path_length, la_u16 line,
    la_u16 *field_out, la_u16 *offset_out, LaSlice *index_out,
    la_u16 *stride_out, la_u16 *count_out)
{
    la_u16 sid;
    la_u16 total;
    const char *cursor;
    const char *end;
    int saw_index;
    sid = la_find_struct_text(ctx, root, root_length);
    if (sid == LA_INVALID_HANDLE) {
        return la_reject_at(ctx, LA_ERR_UNKNOWN_TYPE, line, root_length,
                            la_slice(root, root_length), la_text(""));
    }
    total = 0;
    cursor = path;
    end = path + path_length;
    saw_index = 0;
    index_out->data = 0;
    index_out->length = 0;
    *stride_out = 0;
    *count_out = 0;
    while (cursor < end) {
        const char *name_end;
        const char *component_end;
        const char *index_start;
        const char *index_end;
        la_u16 field_index;
        int indexed;
        name_end = cursor;
        while (name_end < end && *name_end != '.' && *name_end != '[') {
            ++name_end;
        }
        component_end = name_end;
        indexed = 0;
        index_start = 0;
        index_end = 0;
        if (name_end < end && *name_end == '[') {
            indexed = 1;
            index_start = name_end + 1;
            index_end = index_start;
            while (index_end < end && *index_end != ']') ++index_end;
            if (index_end == end || index_end == index_start) {
                return la_reject_at(ctx, LA_ERR_INDEXED_FIELD, line,
                                    (la_u16)(end - name_end),
                                    la_slice(name_end, (la_u16)(end -
                                    name_end)),
                                    la_text("closed physical index"));
            }
            component_end = index_end + 1;
        }
        field_index = la_find_field(ctx, sid, cursor,
                                    (la_u16)(name_end - cursor));
        if (field_index == LA_INVALID_HANDLE) {
            return la_reject_at(ctx, LA_ERR_UNKNOWN_FIELD, line,
                                (la_u16)(name_end - cursor), la_slice(cursor,
                                (la_u16)(name_end - cursor)),
                                la_name_slice(ctx, ctx->structs[sid].name));
        }
        total = (la_u16)(total + ctx->fields[field_index].offset);
        if (indexed) {
            const char *check;
            LaSlice expected;
            if (saw_index || ctx->fields[field_index].count == 1) {
                if (saw_index) {
                    expected = la_text("one index");
                } else {
                    expected = la_text("array field");
                }
                return la_bound(ctx, LA_ERR_INDEXED_FIELD, line,
                                (la_u16)(component_end - cursor),
                                la_slice(cursor, (la_u16)(component_end -
                                cursor)), expected,
                                ctx->fields[field_index].count, 0);
            }
            check = index_start;
            if (!la_is_ident_start(*check)) {
                return la_reject_at(ctx, LA_ERR_INDEX_LOCATION, line,
                                    (la_u16)(index_end - index_start),
                                    la_slice(index_start, (la_u16)(index_end -
                                    index_start)), la_text("physical index"));
            }
            while (check < index_end && la_is_ident(*check)) ++check;
            if (check != index_end) {
                return la_reject_at(ctx, LA_ERR_INDEX_LOCATION, line,
                                    (la_u16)(index_end - index_start),
                                    la_slice(index_start, (la_u16)(index_end -
                                    index_start)), la_text("physical index"));
            }
            index_out->data = index_start;
            index_out->length = (la_u16)(index_end - index_start);
            *stride_out = (la_u16)(ctx->fields[field_index].size /
                                   ctx->fields[field_index].count);
            *count_out = ctx->fields[field_index].count;
            saw_index = 1;
        } else if (ctx->fields[field_index].count != 1) {
            return la_reject_at(ctx, LA_ERR_INDEXED_FIELD, line,
                                (la_u16)(name_end - cursor), la_slice(cursor,
                                (la_u16)(name_end - cursor)),
                                la_text("array index"));
        }
        if (component_end == end) {
            *field_out = field_index;
            *offset_out = total;
            if (!saw_index) {
                return la_reject_at(ctx, LA_ERR_INDEXED_FIELD, line,
                                    path_length, la_slice(path, path_length),
                                    la_text("indexed array"));
            }
            return LA_OK;
        }
        if (*component_end != '.') {
            return la_reject_at(ctx, LA_ERR_INDEXED_FIELD, line, (la_u16)(end -
                                component_end), la_slice(component_end,
                                (la_u16)(end - component_end)), la_text("."));
        }
        if (ctx->fields[field_index].is_pointer) {
            sid = LA_INVALID_HANDLE;
        } else {
            sid = la_find_struct_handle(ctx,
                                        ctx->fields[field_index].type_name);
        }
        if (sid == LA_INVALID_HANDLE) {
            return la_reject_at(ctx, LA_ERR_UNKNOWN_FIELD, line,
                                (la_u16)(name_end - cursor), la_slice(cursor,
                                (la_u16)(name_end - cursor)),
                                la_text("non-structure"));
        }
        cursor = component_end + 1;
    }
    return la_reject_at(ctx, LA_ERR_INDEXED_FIELD, line, path_length,
                        la_slice(path, path_length), la_text(""));
}

la_u16 la_field_alignment(LaContext *ctx, la_u16 field_index)
{
    LaFieldRec *field;
    la_u16 alignment;
    la_u16 owner;
    la_u16 nested;
    la_u16 enumeration;
    field = &ctx->fields[field_index];
    if (field->is_pointer) {
        alignment = ctx->target->pointer_units;
    } else if (la_primitive_size(ctx, field->type_name, &alignment)) {
        /* Primitive size is its native alignment. */
    } else {
        enumeration = la_find_enum_handle(ctx, field->type_name);
        if (enumeration != LA_INVALID_HANDLE) {
            alignment = ctx->enums[enumeration].size;
        } else {
            nested = la_find_struct_handle(ctx, field->type_name);
            if (nested == LA_INVALID_HANDLE) return 0;
            alignment = ctx->structs[nested].alignment;
        }
    }
    for (owner = 0; owner < ctx->struct_count; ++owner) {
        LaStructRec *record;
        record = &ctx->structs[owner];
        if (field_index >= record->first_field &&
            field_index < record->first_field + record->field_count) {
            if (record->policy == LA_LAYOUT_PACKED) return 1;
            if (alignment > record->alignment) {
                alignment = record->alignment;
            }
            break;
        }
    }
    return alignment;
}

int la_emit_property(LaContext *ctx, la_u16 line,
                            LaSlice owner, LaSlice path,
                            LaPropertyKind kind, la_u16 value)
{
    LaEvent event;
    la_u16 aggregate;
    la_init_event(ctx, &event, LA_EVENT_PROPERTY, line, 1);
    event.owner = owner;
    event.path = path;
    event.property = kind;
    event.value = value;
    aggregate = la_find_struct_text(ctx, owner.data, owner.length);
    if (aggregate != LA_INVALID_HANDLE) {
        event.aggregate_kind =
            (LaAggregateKind)ctx->structs[aggregate].kind;
        event.layout_policy =
            (LaLayoutPolicy)ctx->structs[aggregate].policy;
    }
    return la_write_event(ctx, &event);
}

static int la_emit_field_offset(LaContext *ctx, LaFieldRec *field,
                                LaSlice owner, LaSlice path, la_u16 value)
{
    LaEvent event;
    la_u16 aggregate;
    la_init_event(ctx, &event, LA_EVENT_PROPERTY, field->line, 1);
    event.owner = owner;
    event.path = path;
    event.property = LA_PROPERTY_FIELD_OFFSET;
    event.value = value;
    event.explicit_offset = field->has_explicit_offset;
    aggregate = la_find_struct_text(ctx, owner.data, owner.length);
    if (aggregate != LA_INVALID_HANDLE) {
        event.aggregate_kind =
            (LaAggregateKind)ctx->structs[aggregate].kind;
        event.layout_policy =
            (LaLayoutPolicy)ctx->structs[aggregate].policy;
    }
    return la_write_event(ctx, &event);
}

static int la_append_path(LaContext *ctx, la_u16 *path_length,
                          LaSlice component)
{
    la_u16 needed;
    needed = component.length + (*path_length != 0 ? 1 : 0);
    if ((la_u32)*path_length + needed + 1 >
        ctx->limits->max_line_bytes) {
        la_bound(ctx, LA_ERR_NESTING_CAPACITY, 1, 1,
                 la_text("field path bytes"), la_text(""), *path_length +
                 needed + 1, ctx->limits->max_line_bytes);
        return 0;
    }
    if (*path_length != 0) ctx->path_buffer[(*path_length)++] = '.';
    memcpy(ctx->path_buffer + *path_length, component.data, component.length);
    *path_length = (la_u16)(*path_length + component.length);
    ctx->path_buffer[*path_length] = 0;
    return 1;
}

int la_emit_struct_properties(LaContext *ctx, la_u16 root_sid)
{
    LaSlice owner;
    la_u16 depth;
    la_u16 path_length;
    owner = la_name_slice(ctx, ctx->structs[root_sid].name);
    if (!la_emit_property(ctx, ctx->structs[root_sid].line, owner,
                          la_text(""), LA_PROPERTY_STRUCT_SIZE,
                          ctx->structs[root_sid].size)) return 0;
    if (!la_emit_property(ctx, ctx->structs[root_sid].line, owner,
                          la_text(""), LA_PROPERTY_STRUCT_ALIGN,
                          ctx->structs[root_sid].alignment)) {
        return 0;
    }
    depth = 0;
    path_length = 0;
    ctx->frames[0].sid = root_sid;
    ctx->frames[0].next_field = ctx->structs[root_sid].first_field;
    ctx->frames[0].base = 0;
    ctx->frames[0].path_length = 0;
    while (1) {
        LaPropertyFrame *frame;
        LaStructRec *record;
        frame = &ctx->frames[depth];
        record = &ctx->structs[frame->sid];
        if (frame->next_field >=
            record->first_field + record->field_count) {
            if (depth == 0) break;
            path_length = frame->path_length;
            ctx->path_buffer[path_length] = 0;
            --depth;
            continue;
        } else {
            la_u16 field_index;
            LaFieldRec *field;
            LaSlice field_name;
            la_u16 nested_sid;
            la_u16 saved_path;
            field_index = frame->next_field++;
            field = &ctx->fields[field_index];
            field_name = la_name_slice(ctx, field->name);
            saved_path = path_length;
            if (!la_append_path(ctx, &path_length, field_name)) return 0;
            if (!la_emit_field_offset(
                    ctx, field, owner,
                    la_slice(ctx->path_buffer, path_length),
                    (la_u16)(frame->base + field->offset))) {
                return 0;
            }
            if (!la_emit_property(ctx, field->line, owner,
                                  la_slice(ctx->path_buffer, path_length),
                                  LA_PROPERTY_FIELD_SIZE, field->size)) {
                return 0;
            }
            if (field->count != 1) {
                la_u16 stride;
                stride = (la_u16)(field->size / field->count);
                if (!la_emit_property(ctx, field->line, owner,
                                      la_slice(ctx->path_buffer, path_length),
                                      LA_PROPERTY_FIELD_COUNT, field->count) ||
                    !la_emit_property(ctx, field->line, owner,
                                      la_slice(ctx->path_buffer, path_length),
                                      LA_PROPERTY_FIELD_STRIDE, stride)) {
                    return 0;
                }
            }
            nested_sid = field->is_pointer ? LA_INVALID_HANDLE :
                la_find_struct_handle(ctx, field->type_name);
            if (nested_sid != LA_INVALID_HANDLE && field->count == 1) {
                if (depth + 1 >= ctx->limits->max_nesting) {
                    la_bound(ctx, LA_ERR_NESTING_CAPACITY, field->line, 1,
                             la_text("layout nesting"), owner, depth + 2,
                             ctx->limits->max_nesting);
                    return 0;
                }
                ++depth;
                if (depth + 1 > ctx->stats->nesting) {
                    ctx->stats->nesting = (la_u16)(depth + 1);
                }
                ctx->frames[depth].sid = nested_sid;
                ctx->frames[depth].next_field =
                    ctx->structs[nested_sid].first_field;
                ctx->frames[depth].base =
                    (la_u16)(frame->base + field->offset);
                ctx->frames[depth].path_length = saved_path;
            } else {
                path_length = saved_path;
                ctx->path_buffer[path_length] = 0;
            }
        }
    }
    return 1;
}

/* One element of a field: its declared size, or the size of one member
   when the field is an array. */
la_u16 la_field_leaf_size(const LaContext *ctx, la_u16 field)
{
    if (ctx->fields[field].count == 1) return ctx->fields[field].size;
    return (la_u16)(ctx->fields[field].size / ctx->fields[field].count);
}

int la_emit_procedure_event(LaContext *ctx, la_u16 procedure,
                                   la_u16 line,
                                   LaTargetOperationKind operation)
{
    LaEvent event;
    LaProcedureRec *record;
    record = &ctx->procedures[procedure];
    if (!la_count_operation(ctx, line)) return 0;
    la_init_event(ctx, &event, LA_EVENT_TARGET_OPERATION, line, 1);
    event.owner = la_name_slice(ctx, record->name);
    event.operation = operation;
    event.value = record->frame_size;
    event.count = record->local_count;
    return la_write_event(ctx, &event);
}

int la_emit_member_events(LaContext *ctx, la_u16 procedure)
{
    LaProcedureRec *record;
    la_u16 index;
    record = &ctx->procedures[procedure];
    for (index = record->first_parameter;
         index < record->first_parameter + record->parameter_count; ++index) {
        LaLocationRec *member;
        LaEvent event;
        member = &ctx->locations[index];
        la_init_event(ctx, &event, LA_EVENT_PROCEDURE_MEMBER,
                      member->line, 1);
        event.owner = la_name_slice(ctx, record->name);
        event.path = la_name_slice(ctx, member->name);
        event.base = la_name_slice(ctx, member->physical);
        event.aux = la_name_slice(ctx, member->type_name);
        event.value = member->role;
        event.stride = member->is_pointer ?
            ctx->target->pointer_units : 1;
        event.count = LA_PLACEMENT_PHYSICAL;
        if (!la_write_event(ctx, &event)) return 0;
    }
    for (index = record->first_local;
         index < record->first_local + record->local_count; ++index) {
        LaLocalRec *local;
        LaEvent event;
        local = &ctx->locals[index];
        la_init_event(ctx, &event, LA_EVENT_PROCEDURE_MEMBER,
                      local->line, 1);
        event.owner = la_name_slice(ctx, record->name);
        event.path = la_name_slice(ctx, local->name);
        event.aux = la_name_slice(ctx, local->type_name);
        event.value = LA_MEMBER_FRAME;
        event.offset = local->offset;
        event.stride = local->size;
        event.count = LA_PLACEMENT_FRAME;
        if (!la_write_event(ctx, &event)) return 0;
    }
    return 1;
}
