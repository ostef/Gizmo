CalculateDimFactor :: inline (center : Vec3f, axis : Vec3f) -> float
{
    C := GetContext();

    camera_position := TranslationVector(GetContext().camera_transform);
    center_to_camera := normalize(camera_position - center);

    return clamp((1 - abs(dot(axis, center_to_camera))) * 30 - 0.1, 0, 1);
}

CalculateWidgetSize :: inline (position : Vec3f) -> float
{
    C := GetContext();

    widget_size := distance(position, TranslationVector(C.camera_transform));
    widget_size /= 1 / C.style.global_size * 12.5;

    return widget_size;
}

GizmoTranslation :: (id : string, translation : *Vec3f, flags : GizmoFlags = 0) -> InteractionState
{
    C := GetContext();

    if flags & .No_Translation
        return 0;

    gizmo_id := GetID(id);
    kb_state := KeyboardBehavior(gizmo_id, .Translate, translation.*);

    if kb_state & .Cancelled
        translation.* = C.drag_start_translation;
    if kb_state & .Started
        C.drag_start_translation = translation.*;

    result_state : InteractionState;

    result := translation.*;
    defer translation.* = result;

    PushID(id);
    defer PopID();

    model_matrix := GetGizmoMatrix();
    model_rotation := RotationMatrix(model_matrix);

    camera_forward := ForwardVector (C.camera_transform);
    camera_right := RightVector(C.camera_transform);
    camera_up := UpVector(C.camera_transform);
    widget_size := CalculateWidgetSize(translation.*);

    style := C.style;

    axes_ids := u32.[
        GetID("translate_x"),
        GetID("translate_y"),
        GetID("translate_z"),
    ];
    planes_ids := u32.[
        GetID("translate_xy"),
        GetID("translate_yz"),
        GetID("translate_zx"),
    ];
    axes_vectors := Vec3f.[
        .{1,0,0},
        .{0,1,0},
        .{0,0,1},
    ];

    if !(flags & .Global_Space)
    {
        for * axes_vectors
            it.* = transform_vector(model_rotation, it.*);
    }

    axes_colors := Vec4f.[
        style.colors[StyleColor.X_Axis],
        style.colors[StyleColor.Y_Axis],
        style.colors[StyleColor.Z_Axis],
    ];
    axes_active_colors := Vec4f.[
        style.colors[StyleColor.X_Axis_Active],
        style.colors[StyleColor.Y_Axis_Active],
        style.colors[StyleColor.Z_Axis_Active],
    ];
    axes_guide_colors := Vec4f.[
        style.colors[StyleColor.X_Axis_Guide],
        style.colors[StyleColor.Y_Axis_Guide],
        style.colors[StyleColor.Z_Axis_Guide],
    ];
    ignore_axes := bool.[
        flags & .No_X_Axis != 0,
        flags & .No_Y_Axis != 0,
        flags & .No_Z_Axis != 0,
    ];

    view_id := GetID("translate_view");

    if C.active_id != view_id && !array_find(axes_ids, C.active_id)
    {
        DrawOrigin(translation.*);
    }

    ignore_view := flags & .No_View_Axis != 0;
    ignore_view ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != 0;
    ignore_view ||= C.active_id != view_id && array_find(axes_ids, C.active_id);

    if !ignore_view
    {
        drag_state : InteractionState;
        if !kb_state
        {
            hovered := IsCircleFilledHovered(
                translation.*,
                -camera_forward,
                widget_size * C.style.translation_view_circle_size
            );

            drag_state = DraggingBehavior(view_id, hovered, .Translation_Plane, translation.*);
        }
        else if C.keyboard_interaction_flags == 0
        {
            drag_state = kb_state;
        }

        if drag_state
            result_state = drag_state;

        if drag_state & .Cancelled
            result = C.drag_start_translation;

        if drag_state & .Interacting
        {
            C.active_interaction = .Translation_Plane;

            if drag_state & .Started
                C.drag_start_translation = translation.*;

            origin := C.drag_start_translation;
            ray_origin, ray_dir := RayFromMouse();
            intersects, point := RayIntersectsPlane(ray_origin, ray_dir, origin, -camera_forward);

            if intersects
            {
                if drag_state & .Started
                    C.drag_start_translation_offset = translation.* - point;

                proj_point : Vec2f;
                _, proj_point.x = ProjectPointOnInfiniteLine(point, origin, origin + camera_right);
                _, proj_point.y = ProjectPointOnInfiniteLine(point, origin, origin + camera_up);

                if IsKeyDown(.Snap)
                {
                    proj_point.x = Snap(proj_point.x, C.style.translation_snap_grid_size);
                    proj_point.y = Snap(proj_point.y, C.style.translation_snap_grid_size);
                }

                point = origin + proj_point.x * camera_right + proj_point.y * camera_up;

                result = point + C.drag_start_translation_offset;
            }

            _, proj_center := WorldToScreen(C.drag_start_translation);
            DrawText(
                tprint("X: % Y: % Z: %", result.x, result.y, result.z),
                proj_center + .{10, 10},
                C.style.colors[StyleColor.Text],
                C.style.colors[StyleColor.Text_Shadow]
            );
        }

        color := ifx C.hovered_id == view_id || C.active_id == view_id
            then C.style.colors[StyleColor.View_Axis_Active]
            else C.style.colors[StyleColor.View_Axis];

        DrawCircle(
            translation.*,
            widget_size * C.style.translation_view_circle_size,
            color,
            C.style.translation_view_circle_thickness,
            RightVector(C.camera_transform),
            UpVector(C.camera_transform)
        );
    }

    for #v2 < i : 0..2
    {
        id := axes_ids[i];
        ignore_axis := ignore_axes[i];
        ignore_axis ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != xx (1 << i);
        ignore_axis ||= C.active_id != id && array_find(axes_ids, C.active_id);

        if ignore_axis
            continue;

        start := translation.* + widget_size * axes_vectors[i] * C.style.translation_view_circle_size;
        end := translation.* + widget_size * axes_vectors[i];
        dim := CalculateDimFactor(translation.*, axes_vectors[i]);

        drag_state : InteractionState;
        if !kb_state
        {
            hovered := dim > 0.1 && IsLineHovered(
                start, end,
                C.style.translation_handle_thickness + C.style.line_interaction_threshold
            );

            drag_state = DraggingBehavior(id, hovered, .Translation_Axis, translation.*);
        }
        else if C.keyboard_interaction_flags == xx (1 << i)
        {
            drag_state = kb_state;
        }

        if drag_state
            result_state = drag_state;

        if drag_state & .Cancelled
            result = C.drag_start_translation;

        if drag_state & .Interacting
        {
            C.active_interaction = .Translation_Axis;

            if drag_state & .Started
                C.drag_start_translation = translation.*;

            center_behind, proj_center := WorldToScreen(C.drag_start_translation);
            axis_behind, proj_axis := WorldToScreen(C.drag_start_translation + axes_vectors[i]);
            if !center_behind && !axis_behind
            {
                mouse_offset := C.mouse_pos - C.mouse_drag_start;
                proj_axis = normalize(proj_axis - proj_center);
                mouse_dir := normalize(C.mouse_pos - C.mouse_drag_start);
                dist := distance(C.mouse_drag_start, C.mouse_pos);
                dist *= dot(proj_axis, mouse_dir);
                dist *= C.style.translation_drag_sensitivity;

                if IsKeyDown(.Slow)
                    dist *= C.style.sensitivity_slow_factor;

                if IsKeyDown(.Snap)
                    dist = Snap(dist, C.style.translation_snap_grid_size);

                result = C.drag_start_translation + axes_vectors[i] * dist;

                DrawText(
                    tprint("X: % Y: % Z: %", result.x, result.y, result.z),
                    proj_center + .{10, 10},
                    C.style.colors[StyleColor.Text],
                    C.style.colors[StyleColor.Text_Shadow]
                );
            }
        }

        color := ifx C.hovered_id == id || C.active_id == id
            then axes_active_colors[i] else axes_colors[i] * .{1,1,1,dim};

        if drag_state & .Interacting
        {
            DrawLine(
                translation.* - axes_vectors[i] * 500,
                translation.* + axes_vectors[i] * 500,
                axes_guide_colors[i],
                style.guide_line_thickness
            );

            start = translation.*;
            DrawCircleFilled(
                start,
                widget_size * C.style.origin_circle_size,
                color,
                camera_right, camera_up
            );
        }

        DrawArrow(
            start, end,
            color,
            style.translation_handle_thickness,
            style.translation_arrow_size,
            style.translation_arrow_aspect_ratio
        );
    }

    return result_state;
}

GizmoScale :: (id : string, scale : *Vec3f, flags : GizmoFlags = 0) -> InteractionState
{
    ThreeAxes :: struct
    {
        x, y, z : Vec3f;

        #place x;
        axes : [3]Vec3f;
    }

    operator * :: (axes : ThreeAxes, vec : Vec3f) -> ThreeAxes
    {
        return .{axes.x * vec.x, axes.y * vec.y, axes.z * vec.z};
    }

    GetScaleOnAxis :: (scale : ThreeAxes, axis : Vec3f) -> float
    {
        return abs(dot(scale.x, axis)) + abs(dot(scale.y, axis)) + abs(dot(scale.z, axis));
    }

    ProjectScale :: (scale : ThreeAxes, onto : ThreeAxes) -> Vec3f
    {
        return .{
            GetScaleOnAxis(scale, onto.x),
            GetScaleOnAxis(scale, onto.y),
            GetScaleOnAxis(scale, onto.z),
        };
    }

    C := GetContext();

    if flags & .No_Scale
        return 0;

    model_matrix := GetGizmoMatrix();
    translation := TranslationVector(model_matrix);
    model_matrix = RotationMatrix(model_matrix);

    gizmo_id := GetID(id);
    kb_state := KeyboardBehavior(gizmo_id, .Scale, translation);

    if kb_state & .Cancelled
        scale.* = C.drag_start_scale;
    if kb_state & .Started
        C.drag_start_scale = scale.*;

    result_state : InteractionState;

    result := scale.*;
    defer scale.* = result;

    PushID(id);
    defer PopID();

    camera_forward := ForwardVector (C.camera_transform);
    camera_right := RightVector(C.camera_transform);
    camera_up := UpVector(C.camera_transform);
    widget_size := CalculateWidgetSize(translation);

    style := C.style;

    all_id := GetID("scale_all");
    axes_ids := u32.[
        GetID("scale_x"),
        GetID("scale_y"),
        GetID("scale_z"),
        all_id,
    ];

    axes_vectors := Vec3f.[
        .{1,0,0},
        .{0,1,0},
        .{0,0,1},
    ];
    local_axes_vectors := Vec3f.[
        .{1,0,0},
        .{0,1,0},
        .{0,0,1},
    ];

    if !(flags & .Global_Space)
    {
        for * axes_vectors
            it.* = transform_vector(model_matrix, it.*);
    }

    for * local_axes_vectors
        it.* = transform_vector(model_matrix, it.*);

    axes_colors := Vec4f.[
        style.colors[StyleColor.X_Axis],
        style.colors[StyleColor.Y_Axis],
        style.colors[StyleColor.Z_Axis],
    ];
    axes_active_colors := Vec4f.[
        style.colors[StyleColor.X_Axis_Active],
        style.colors[StyleColor.Y_Axis_Active],
        style.colors[StyleColor.Z_Axis_Active],
    ];
    axes_guide_colors := Vec4f.[
        style.colors[StyleColor.X_Axis_Guide],
        style.colors[StyleColor.Y_Axis_Guide],
        style.colors[StyleColor.Z_Axis_Guide],
    ];
    ignore_axes := bool.[
        flags & .No_X_Axis != 0,
        flags & .No_Y_Axis != 0,
        flags & .No_Z_Axis != 0,
    ];

    if !array_find(axes_ids, C.active_id)
        DrawOrigin(translation);

    for #v2 < i : 0..2
    {
        id := axes_ids[i];
        ignore_axis := ignore_axes[i];
        ignore_axis ||= C.active_id != id && array_find(axes_ids, C.active_id);
        ignore_axis ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != xx (1 << i);
        if ignore_axis
            continue;

        start := translation + widget_size * axes_vectors[i] * C.style.scale_all_inner_circle_size;
        end := translation + widget_size * axes_vectors[i];
        dim := CalculateDimFactor(translation, axes_vectors[i]);

        drag_state : InteractionState;
        if !kb_state
        {
            hovered := dim > 0.1 && IsLineHovered(
                start, end,
                C.style.scale_handle_thickness + C.style.line_interaction_threshold
            );

            drag_state = DraggingBehavior(id, hovered, .Scale_Axis, translation);
        }
        else if C.keyboard_interaction_flags == xx (1 << i)
        {
            drag_state = kb_state;
        }

        if drag_state
            result_state = drag_state;

        if drag_state & .Cancelled
            result = C.drag_start_scale;

        if drag_state & .Interacting
        {
            if drag_state & .Started
            {
                C.drag_start_scale = ProjectScale(ThreeAxes.{axes=local_axes_vectors} * scale.*, .{axes=axes_vectors});
                C.drag_start_scale_axis = axes_vectors[i];
            }

            end = translation + widget_size * C.drag_start_scale_axis;

            is_behind, proj_center := WorldToScreen(translation);
            if !is_behind
            {
                t1 := distance(proj_center, C.mouse_drag_start);
                t2 := distance(proj_center, C.mouse_pos);

                if IsKeyDown(.Slow)
                    t2 = t1 + (t2 - t1) * C.style.sensitivity_slow_factor;

                s := Sign(C.drag_start_scale.component[i]);
                center_to_start := normalize(C.mouse_drag_start - proj_center);
                center_to_curr := normalize(C.mouse_pos - proj_center);

                if dot(center_to_start, center_to_curr) < 0
                    s = -s;

                ratio := t2 / t1;
                additional_scale := s * abs(C.drag_start_scale.component[i]) * ratio - C.drag_start_scale.component[i];

                if IsKeyDown(.Snap)
                    additional_scale = Snap(additional_scale, C.style.scale_snap_grid_size);

                scale_axes := ThreeAxes.{
                    axes_vectors[0] * C.drag_start_scale.component[0],
                    axes_vectors[1] * C.drag_start_scale.component[1],
                    axes_vectors[2] * C.drag_start_scale.component[2],
                };
                scale_axes.axes[i] += axes_vectors[i] * additional_scale;
                scale_on_axis := C.drag_start_scale.component[i] + additional_scale;

                result = ProjectScale(scale_axes, .{axes=local_axes_vectors});

                end = translation + widget_size * C.drag_start_scale_axis * s * ratio;

                XYZ :: string.["X","Y","Z"];
                DrawText(
                    tprint("%: %", XYZ[i], scale_on_axis),
                    proj_center + .{10, 10},
                    C.style.colors[StyleColor.Text],
                    C.style.colors[StyleColor.Text_Shadow]
                );
            }
        }

        color := ifx C.hovered_id == id || C.active_id == id
            then axes_active_colors[i] else axes_colors[i] * .{1,1,1,dim};

        if drag_state & .Interacting
        {
            DrawLine(
                translation - axes_vectors[i] * 500,
                translation + axes_vectors[i] * 500,
                axes_guide_colors[i],
                style.guide_line_thickness
            );

            start = translation;

            DrawCircleFilled(
                start,
                widget_size * C.style.origin_circle_size,
                color,
                RightVector(C.camera_transform), UpVector(C.camera_transform)
            );
        }

        DrawSquareArrow(
            start, end,
            color,
            style.scale_handle_thickness,
            style.scale_tip_size
        );
    }

    ignore_all := flags & .No_View_Axis != 0;
    ignore_all ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != 0;
    ignore_all ||= C.active_id != all_id && array_find(axes_ids, C.active_id);

    if !ignore_all
    {
        drag_state : InteractionState;
        if !kb_state
        {
            hovered := IsCircleFilledHovered(
                translation,
                -camera_forward,
                widget_size * C.style.scale_all_outer_circle_size
            );

            drag_state = DraggingBehavior(all_id, hovered, .Scale_All, translation);
        }
        else if C.keyboard_interaction_flags == 0
        {
            drag_state = kb_state;
        }

        if drag_state
            result_state = drag_state;

        if drag_state & .Cancelled
            result = C.drag_start_scale;

        if drag_state & .Interacting
        {
            if drag_state & .Started
            {
                C.drag_start_scale = scale;
                C.drag_start_scale_axis = .{1,1,1};
            }

            is_behind, proj_center := WorldToScreen(translation);
            if !is_behind
            {
                t1 := distance(proj_center, C.mouse_drag_start);
                t2 := distance(proj_center, C.mouse_pos);

                if IsKeyDown(.Slow)
                    t2 = t1 + (t2 - t1) * C.style.sensitivity_slow_factor;

                s := Vec3f.{
                    Sign(C.drag_start_scale.x),
                    Sign(C.drag_start_scale.y),
                    Sign(C.drag_start_scale.z),
                };

                center_to_start := normalize(C.mouse_drag_start - proj_center);
                center_to_curr := normalize(C.mouse_pos - proj_center);

                if dot(center_to_start, center_to_curr) < 0
                    s = -s;

                widget_size *= t2 / t1;

                ratio := t2 / t1;
                additional_scale := s * abs(C.drag_start_scale) * ratio - C.drag_start_scale;

                if IsKeyDown(.Snap)
                {
                    additional_scale.x = Snap(additional_scale.x, C.style.scale_snap_grid_size);
                    additional_scale.y = Snap(additional_scale.y, C.style.scale_snap_grid_size);
                    additional_scale.z = Snap(additional_scale.z, C.style.scale_snap_grid_size);
                }

                result = C.drag_start_scale + additional_scale;

                if IsKeyDown(.Snap)
                {
                    result.x = Snap(result.x, C.style.scale_snap_grid_size);
                    result.y = Snap(result.y, C.style.scale_snap_grid_size);
                    result.z = Snap(result.z, C.style.scale_snap_grid_size);
                }

                DrawText(
                    tprint("X: % Y: % Z: %", result.x, result.y, result.z),
                    proj_center + .{10, 10},
                    C.style.colors[StyleColor.Text],
                    C.style.colors[StyleColor.Text_Shadow]
                );
            }
        }

        color := ifx C.hovered_id == all_id || C.active_id == all_id
            then C.style.colors[StyleColor.View_Axis_Active]
            else C.style.colors[StyleColor.View_Axis];

        DrawCircle(
            translation,
            widget_size * C.style.scale_all_inner_circle_size,
            color,
            C.style.scale_all_handle_thickness,
            RightVector(C.camera_transform),
            UpVector(C.camera_transform)
        );

        if C.active_id != gizmo_id && C.active_id != all_id
        {
            DrawCircle(
                translation,
                widget_size * C.style.scale_all_outer_circle_size,
                color,
                C.style.scale_all_handle_thickness,
                RightVector(C.camera_transform),
                UpVector(C.camera_transform)
            );
        }
    }

    return result_state;
}

GizmoRotation :: (id : string, rotation : *Quatf, flags : GizmoFlags = 0) -> InteractionState
{
    C := GetContext();

    if flags & .No_Rotation
        return 0;

    matrix := GetGizmoMatrix();
    translation := TranslationVector(matrix);

    gizmo_id := GetID(id);
    kb_state := KeyboardBehavior(gizmo_id, .Rotate, translation);

    if kb_state & .Cancelled
        rotation.* = C.drag_start_rotation;
    if kb_state & .Started
        C.drag_start_rotation = rotation.*;

    result_state : InteractionState;

    result := rotation.*;
    defer rotation.* = result;

    PushID(id);
    defer PopID();

    camera_forward := ForwardVector (C.camera_transform);
    camera_right := RightVector(C.camera_transform);
    camera_up := UpVector(C.camera_transform);
    widget_size := CalculateWidgetSize(translation);

    trackball_id := GetID("rotate_trackball");
    axes_ids := u32.[
        GetID("rotate_x"),
        GetID("rotate_y"),
        GetID("rotate_z"),
        GetID("rotate_view"),
        trackball_id,
    ];

    axes_vectors := Vec3f.[
        .{1,0,0},
        .{0,1,0},
        .{0,0,1},
        camera_forward,
    ];

    if !(flags & .Global_Space)
    {
        for i : 0..2
            axes_vectors[i] = rotate(axes_vectors[i], rotation.*);
    }

    axes_colors := Vec4f.[
        C.style.colors[StyleColor.X_Axis],
        C.style.colors[StyleColor.Y_Axis],
        C.style.colors[StyleColor.Z_Axis],
        C.style.colors[StyleColor.View_Axis],
    ];
    axes_active_colors := Vec4f.[
        C.style.colors[StyleColor.X_Axis_Active],
        C.style.colors[StyleColor.Y_Axis_Active],
        C.style.colors[StyleColor.Z_Axis_Active],
        C.style.colors[StyleColor.View_Axis_Active],
    ];
    axes_guide_colors := Vec4f.[
        C.style.colors[StyleColor.X_Axis_Guide],
        C.style.colors[StyleColor.Y_Axis_Guide],
        C.style.colors[StyleColor.Z_Axis_Guide],
        C.style.colors[StyleColor.View_Axis_Guide],
    ];
    ignore_axes := bool.[
        flags & .No_X_Axis != 0,
        flags & .No_Y_Axis != 0,
        flags & .No_Z_Axis != 0,
        flags & .No_View_Axis != 0,
    ];

    if C.active_id != gizmo_id && !array_find(axes_ids, C.active_id)
        DrawOrigin(translation);

    for #v2 < i : 0..3
    {
        keyboard_flags : KeyboardInteractionFlags;
        if i != 3
            keyboard_flags = xx (1 << i);

        id := axes_ids[i];
        ignore_axis := ignore_axes[i];
        ignore_axis ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != keyboard_flags;
        ignore_axis ||= C.active_id != id && array_find(axes_ids, C.active_id);

        if ignore_axis
            continue;

        axis := axes_vectors[i];
        tangent, bitangent : Vec3f;
        radius : float;
        thickness : float;
        if i == 3
        {
            tangent = RightVector(C.camera_transform);
            bitangent = UpVector(C.camera_transform);
            radius = widget_size * C.style.rotation_view_axis_size;
            thickness = C.style.rotation_view_axis_thickness;
        }
        else
        {
            tangent = axes_vectors[(i + 1) % 3];
            bitangent = axes_vectors[(i + 2) % 3];
            radius = widget_size;
            thickness = C.style.rotation_handle_thickness;
        }

        drag_state : InteractionState;
        if !kb_state
        {
            hovered := IsFacingCircleHovered(
                translation,
                radius,
                thickness + ifx i == 3 then C.style.line_interaction_threshold,
                tangent, bitangent
            );

            drag_state = DraggingBehavior(id, hovered, .Rotation_Axis, translation);
        }
        else if C.keyboard_interaction_flags == keyboard_flags
        {
            drag_state = kb_state;
        }

        if drag_state
            result_state = drag_state;

        if drag_state & .Cancelled
            result = C.drag_start_rotation;

        if drag_state & .Interacting
        {
            if drag_state & .Started
            {
                C.drag_start_rotation_axis = axes_vectors[i];
                C.drag_start_rotation = rotation.*;
            }

            origin := translation;
            ray_origin, ray_dir := RayFromMouse();
            intersects, point := RayIntersectsPlane(ray_origin, ray_dir, origin, C.drag_start_rotation_axis);
            if drag_state & .Started
            {
                C.drag_start_rotation_point = point;
            }

            is_behind, proj_center := WorldToScreen(translation);
            if !is_behind
            {
                begin := normalize(proj_center - C.mouse_drag_start);
                end := normalize(proj_center - C.mouse_pos);
                s := ifx dot(camera_forward, axis) < 0 then -1.0 else 1.0;
                angle := SignedAngle(Vec3f.{xy=begin,z=0}, Vec3f.{xy=end,z=0}, .{0,0,-s});

                if IsKeyDown(.Slow)
                    angle *= C.style.sensitivity_slow_factor;

                if IsKeyDown(.Snap)
                    angle = Snap(angle, C.style.rotation_snap_grid_size);

                rotated : Quatf;
                set_from_axis_and_angle(*rotated, C.drag_start_rotation_axis, angle);

                result = rotated * C.drag_start_rotation;
                normalize_or_identity(*result);

                rotation_start_dir := normalize(C.drag_start_rotation_point - translation);
                DrawSemiCircleFilled(
                    translation,
                    radius,
                    axes_guide_colors[i] * .{1,1,1,0.3},
                    tangent, bitangent,
                    SignedAngle(tangent, rotation_start_dir, C.drag_start_rotation_axis), -angle
                );

                DrawLine(
                    translation,
                    translation + rotation_start_dir * radius,
                    axes_active_colors[i],
                    C.style.guide_line_thickness
                );

                DrawLine(
                    translation,
                    translation + rotate(rotation_start_dir, rotated) * radius,
                    axes_active_colors[i],
                    thickness
                );

                _, angle_text_pos := WorldToScreen(translation + rotation_start_dir * radius * 1.2);
                DrawText(
                    tprint("% deg", angle * 180 / PI),
                    angle_text_pos,
                    C.style.colors[StyleColor.Text],
                    C.style.colors[StyleColor.Text_Shadow]
                );
            }
        }

        color := ifx C.hovered_id == id || C.active_id == id
            then axes_active_colors[i] else axes_colors[i];

        if drag_state & .Interacting
        {
            DrawCircle(
                translation,
                radius,
                color,
                thickness,
                tangent, bitangent
            );
        }
        else
        {
            DrawFacingCircle(
                translation,
                radius,
                color,
                thickness,
                tangent, bitangent
            );
        }
    }

    ignore_trackball := (flags & .No_Trackball) != 0;
    ignore_trackball ||= C.active_id == gizmo_id;
    ignore_trackball ||= C.active_id != trackball_id && array_find(axes_ids, C.active_id);

    if !ignore_trackball
    {
        hovered := IsCircleFilledHovered(translation, camera_forward, widget_size);
        drag_state := DraggingBehavior(trackball_id, hovered, .Rotation_Trackball, translation);
        if drag_state
            result_state = drag_state;

        if drag_state & .Cancelled
            result = C.drag_start_rotation;

        if drag_state & .Interacting
        {
            if drag_state & .Started
            {
                C.drag_start_rotation = rotation.*;
            }

            camera_rotation := get_rotation(C.camera_view);
            start_axis := Project2DPointOn3DSphere(C.mouse_drag_start, translation, widget_size);
            start_axis = normalize(start_axis);
            start_axis = rotate(start_axis, camera_rotation);

            curr_axis := Project2DPointOn3DSphere(C.mouse_pos, translation, widget_size);
            curr_axis = normalize(curr_axis);
            curr_axis = rotate(curr_axis, camera_rotation);

            result = C.drag_start_rotation * QuatfFromVectorToVector(start_axis, curr_axis);
        }

        trackball_color := ifx C.hovered_id == trackball_id || C.active_id == trackball_id
            then C.style.colors[StyleColor.Rotation_Trackball_Active]
            else C.style.colors[StyleColor.Rotation_Trackball];

        if !(drag_state & .Interacting)
        {
            DrawCircleFilled(
                translation,
                widget_size,
                trackball_color,
                RightVector(C.camera_transform), UpVector(C.camera_transform)
            );
        }
        else
        {
            DrawFacingCircle(
                translation,
                widget_size,
                C.style.colors[StyleColor.Z_Axis],
                C.style.rotation_handle_thickness,
                axes_vectors[0], axes_vectors[1]
            );
            DrawFacingCircle(
                translation,
                widget_size,
                C.style.colors[StyleColor.Y_Axis],
                C.style.rotation_handle_thickness,
                axes_vectors[2], axes_vectors[0]
            );
            DrawFacingCircle(
                translation,
                widget_size,
                C.style.colors[StyleColor.X_Axis],
                C.style.rotation_handle_thickness,
                axes_vectors[1], axes_vectors[2]
            );
        }
    }

    return result_state;
}

GizmoTransform :: (
    id : string,
    translation : *Vec3f,
    rotation : *Quatf,
    scale : *Vec3f,
    type : GizmoType,
    flags : GizmoFlags = 0
) -> InteractionState
{
    C := GetContext();

    parent := GetGizmoMatrix();
    inv_parent := inverse(parent);

    matrix := make_translation_matrix4(translation.*)
        * rotation_matrix(Mat4f, rotation.*)
        * make_scale_matrix4(scale.*);

    PushGizmoMatrix(matrix);
    defer PopGizmoMatrix();

    gizmo_id := GetID(id);
    if C.keyboard_focus_id == gizmo_id && C.active_id == 0
    {
        if IsKeyPressed(.Translate)
            type = .Translate;
        if IsKeyPressed(.Rotate)
            type = .Rotate;
        if IsKeyPressed(.Scale)
            type = .Scale;
    }

    if C.active_id == gizmo_id
    {
        if C.keyboard_interaction ==
        {
        case .Translate;
            type = .Translate;
        case .Rotate;
            type = .Rotate;
        case .Scale;
            type = .Scale;
        }
    }

    if #complete type ==
    {
    case .Translate;
        translation.* = transform_point(parent, translation.*);
        defer translation.* = transform_point(inv_parent, translation.*);

        return GizmoTranslation(id, translation, flags);

    case .Rotate;
        // Transform the quaternion to global space first
        // Transform back to local space afterwards
        q := QuatfFromMatrix(parent);
        inv_q := conjugate(q);
        rotation.* = q * rotation.*;
        defer rotation.* = inv_q * rotation.*;

        return GizmoRotation(id, rotation, flags);

    case .Scale;
        return GizmoScale(id, scale, flags);

    case .None;
        translation := TranslationVector(GetGizmoMatrix());
        DrawOrigin(translation);
    }

    return 0;
}
