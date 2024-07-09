CalculateDimFactor :: inline (center : Vec3f, axis : Vec3f) -> float #must
{
    C := GetContext ();

    camera_position := TranslationVector (GetContext ().camera_transform);
    center_to_camera := normalize (camera_position - center);

    return clamp ((1 - abs (dot (axis, center_to_camera))) * 30 - 0.1, 0, 1);
}

CalculateWidgetSize :: inline (position : Vec3f) -> float #must
{
    C := GetContext ();

    widget_size := distance (position, TranslationVector (C.camera_transform));
    widget_size /= 1 / C.style.global_size * 12.5;

    return widget_size;
}

GizmoTranslation :: (id : string, translation : *Vec3f, flags : GizmoFlags = 0) -> bool
{
    C := GetContext ();

    if flags & .No_Translation
        return false;

    gizmo_id := GetID (id);
    kb_drag_start, kb_dragging, kb_drag_cancel, kb_drag_reset
        := KeyboardBehavior (gizmo_id, .Translate, translation.*);
    kb_interact := kb_dragging || kb_drag_cancel;

    if kb_drag_start
        C.drag_start_translation = translation.*;
    if kb_drag_reset
        translation.* = C.drag_start_translation;

    PushID (id);
    defer PopID ();

    model_matrix := GetGizmoMatrix ();
    model_rotation := RotationMatrix (model_matrix);

    result := translation.*;
    defer translation.* = result;

    camera_forward := ForwardVector (C.camera_transform);
    camera_right := RightVector (C.camera_transform);
    camera_up := UpVector (C.camera_transform);
    widget_size := CalculateWidgetSize (translation.*);

    style := C.style;

    axes_ids := u32.[
        GetID ("translate_x"),
        GetID ("translate_y"),
        GetID ("translate_z"),
    ];
    planes_ids := u32.[
        GetID ("translate_xy"),
        GetID ("translate_yz"),
        GetID ("translate_zx"),
    ];
    axes_vectors := Vec3f.[
        .{1,0,0},
        .{0,1,0},
        .{0,0,1},
    ];
    for * axes_vectors
        it.* = transform_vector (model_rotation, it.*);

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

    view_id := GetID ("translate_view");

    if C.active_id != view_id && !array_find (axes_ids, C.active_id)
    {
        DrawOrigin (translation.*);
    }

    ignore_view := flags & .No_View_Axis != 0;
    ignore_view ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != 0;
    ignore_view ||= C.active_id != view_id && array_find (axes_ids, C.active_id);

    if !ignore_view
    {
        hovered := IsCircleFilledHovered (
            translation.*,
            -camera_forward,
            widget_size * C.style.translation_view_circle_size
        );

        drag_start, dragging, cancelled_dragging, drag_reset : bool;
        if !kb_interact
        {
            drag_start, dragging, cancelled_dragging
                = DraggingBehavior (view_id, hovered, .Translation_Plane, translation.*);
        }
        else if C.keyboard_interaction_flags == 0
        {
            drag_start = kb_drag_start;
            dragging = kb_dragging;
            cancelled_dragging = kb_drag_cancel;
            drag_reset = kb_drag_reset;
        }

        if cancelled_dragging
            result = C.drag_start_translation;

        if dragging
        {
            C.active_interaction = .Translation_Plane;

            if drag_start
                C.drag_start_translation = translation.*;

            origin := C.drag_start_translation;
            ray_origin, ray_dir := RayFromMouse ();
            intersects, point := RayIntersectsPlane (ray_origin, ray_dir, origin, -camera_forward);

            if drag_start || drag_reset
                C.drag_start_translation_offset = translation.* - point;

            if intersects
                result = point + C.drag_start_translation_offset;
        }

        color := ifx C.hovered_id == view_id || C.active_id == view_id
            then C.style.colors[StyleColor.View_Axis_Active]
            else C.style.colors[StyleColor.View_Axis];

        DrawCircle (
            translation.*,
            widget_size * C.style.translation_view_circle_size,
            color,
            C.style.translation_view_circle_thickness,
            RightVector (C.camera_transform),
            UpVector (C.camera_transform)
        );
    }

    for < i : 2..0
    {
        id := axes_ids[i];
        ignore_axis := ignore_axes[i];
        ignore_axis ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != xx (1 << i);
        ignore_axis ||= C.active_id != id && array_find (axes_ids, C.active_id);

        if ignore_axis
            continue;

        start := translation.* + widget_size * axes_vectors[i] * C.style.translation_view_circle_size;
        end := translation.* + widget_size * axes_vectors[i];
        dim := CalculateDimFactor (translation.*, axes_vectors[i]);

        drag_start, dragging, cancelled_dragging, drag_reset : bool;
        if !kb_interact
        {
            hovered := dim > 0.1 && IsLineHovered (
                start, end,
                C.style.translation_handle_thickness + C.line_interaction_threshold
            );

            drag_start, dragging, cancelled_dragging
                = DraggingBehavior (id, hovered, .Translation_Axis, translation.*);
        }
        else if C.keyboard_interaction_flags == xx (1 << i)
        {
            drag_start = kb_drag_start;
            dragging = kb_dragging;
            cancelled_dragging = kb_drag_cancel;
            drag_reset = kb_drag_reset;
        }

        if cancelled_dragging
            result = C.drag_start_translation;

        if dragging
        {
            C.active_interaction = .Translation_Axis;

            if drag_start
            {
                C.drag_start_translation = translation.*;
            }

            origin := C.drag_start_translation;
            ray_origin, ray_dir := RayFromMouse ();
            _, point := NearestPointOnRayAndLine (ray_origin, ray_dir, origin, axes_vectors[i]);

            if drag_start || drag_reset
            {
                C.drag_start_translation_offset = translation.* - point;
            }

            result = point + C.drag_start_translation_offset;
        }

        color := ifx C.hovered_id == id || C.active_id == id
            then axes_active_colors[i] else axes_colors[i] * .{1,1,1,dim};

        if dragging
        {
            DrawLine (
                translation.* - axes_vectors[i] * 500,
                translation.* + axes_vectors[i] * 500,
                axes_guide_colors[i],
                style.guide_line_thickness
            );

            start = translation.*;
            DrawCircleFilled (
                start,
                widget_size * C.style.origin_circle_size,
                color,
                camera_right, camera_up
            );
        }

        DrawArrow (
            start, end,
            color,
            style.translation_handle_thickness,
            style.translation_arrow_size,
            style.translation_arrow_aspect_ratio
        );
    }

    return translation.* != result;
}

GizmoScale :: (id : string, scale : *Vec3f, flags : GizmoFlags = 0) -> bool
{
    C := GetContext ();

    if flags & .No_Translation
        return false;

    model_matrix := GetGizmoMatrix ();
    translation := TranslationVector (model_matrix);
    model_matrix = RotationMatrix (model_matrix);

    gizmo_id := GetID (id);
    kb_drag_start, kb_dragging, kb_drag_cancel, kb_drag_reset
        := KeyboardBehavior (gizmo_id, .Scale, translation);
    kb_interact := kb_dragging || kb_drag_cancel;

    if kb_drag_start
        C.drag_start_scale = scale.*;
    if kb_drag_reset
        scale.* = C.drag_start_scale;

    PushID (id);
    defer PopID ();

    camera_forward := ForwardVector (C.camera_transform);
    camera_right := RightVector (C.camera_transform);
    camera_up := UpVector (C.camera_transform);
    widget_size := CalculateWidgetSize (translation);

    style := C.style;

    result := scale.*;
    defer scale.* = result;

    all_id := GetID ("scale_all");
    axes_ids := u32.[
        GetID ("scale_x"),
        GetID ("scale_y"),
        GetID ("scale_z"),
        all_id,
    ];

    axes_vectors := Vec3f.[
        .{1,0,0},
        .{0,1,0},
        .{0,0,1},
    ];
    for * axes_vectors
        it.* = transform_vector (model_matrix, it.*);

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

    if !array_find (axes_ids, C.active_id)
        DrawOrigin (translation);

    for < i : 2..0
    {
        id := axes_ids[i];
        ignore_axis := ignore_axes[i];
        ignore_axis ||= C.active_id != id && array_find (axes_ids, C.active_id);
        ignore_axis ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != xx (1 << i);
        if ignore_axis
            continue;

        start := translation + widget_size * axes_vectors[i] * C.style.scale_all_inner_circle_size;
        end := translation + widget_size * axes_vectors[i];
        dim := CalculateDimFactor (translation, axes_vectors[i]);

        drag_start, dragging, cancelled_dragging, drag_reset : bool;
        if !kb_interact
        {
            hovered := dim > 0.1 && IsLineHovered (
                start, end,
                C.style.scale_handle_thickness + C.line_interaction_threshold
            );

            drag_start, dragging, cancelled_dragging
                = DraggingBehavior (id, hovered, .Scale_Axis, translation);
        }
        else if C.keyboard_interaction_flags == xx (1 << i)
        {
            drag_start = kb_drag_start;
            dragging = kb_dragging;
            cancelled_dragging = kb_drag_cancel;
            drag_reset = kb_drag_reset;
        }

        if cancelled_dragging
            result = C.drag_start_scale;

        if dragging
        {
            if drag_start || drag_reset
            {
                C.drag_start_scale = scale;
                C.drag_start_scale_axis = axes_vectors[i];
            }

            end = translation + widget_size * C.drag_start_scale_axis;

            is_behind, proj_center := WorldToScreen (translation);
            if !is_behind
            {
                t1 := distance (proj_center, C.mouse_drag_start);
                t2 := distance (proj_center, C.mouse_pos);

                s := Sign (C.drag_start_scale.component[i]);
                center_to_start := normalize (C.mouse_drag_start - proj_center);
                center_to_curr := normalize (C.mouse_pos - proj_center);

                if dot (center_to_start, center_to_curr) < 0
                    s = -s;

                ratio := t2 / t1;
                result.component[i] = s * abs (C.drag_start_scale.component[i]) * ratio;

                end = translation + widget_size * C.drag_start_scale_axis * s * ratio;
            }
        }

        color := ifx C.hovered_id == id || C.active_id == id
            then axes_active_colors[i] else axes_colors[i] * .{1,1,1,dim};

        if dragging
        {
            DrawLine (
                translation - axes_vectors[i] * 500,
                translation + axes_vectors[i] * 500,
                axes_guide_colors[i],
                style.guide_line_thickness
            );

            start = translation;

            DrawCircleFilled (
                start,
                widget_size * C.style.origin_circle_size,
                color,
                RightVector (C.camera_transform), UpVector (C.camera_transform)
            );
        }

        DrawSquareArrow (
            start, end,
            color,
            style.scale_handle_thickness,
            style.scale_tip_size
        );
    }

    ignore_all := flags & .No_View_Axis != 0;
    ignore_all ||= C.active_id == gizmo_id && C.keyboard_interaction_flags != 0;
    ignore_all ||= C.active_id != all_id && array_find (axes_ids, C.active_id);

    if !ignore_all
    {
        drag_start, dragging, cancelled_dragging, drag_reset : bool;
        if !kb_interact
        {
            hovered := IsCircleFilledHovered (
                translation,
                -camera_forward,
                widget_size * C.style.scale_all_outer_circle_size
            );

            drag_start, dragging, cancelled_dragging
                = DraggingBehavior (all_id, hovered, .Scale_All, translation);
        }
        else if C.keyboard_interaction_flags == 0
        {
            drag_start = kb_drag_start;
            dragging = kb_dragging;
            cancelled_dragging = kb_drag_cancel;
            drag_reset = kb_drag_reset;
        }

        if cancelled_dragging
            result = C.drag_start_scale;

        if dragging
        {
            if drag_start || drag_reset
            {
                C.drag_start_scale = scale;
                C.drag_start_scale_axis = .{1,1,1};
            }

            is_behind, proj_center := WorldToScreen (translation);
            if !is_behind
            {
                t1 := distance (proj_center, C.mouse_drag_start);
                t2 := distance (proj_center, C.mouse_pos);

                s := Vec3f.{
                    Sign (C.drag_start_scale.x),
                    Sign (C.drag_start_scale.y),
                    Sign (C.drag_start_scale.z),
                };

                center_to_start := normalize (C.mouse_drag_start - proj_center);
                center_to_curr := normalize (C.mouse_pos - proj_center);

                if dot (center_to_start, center_to_curr) < 0
                    s = -s;

                result = abs (C.drag_start_scale) * abs (t2 / t1);
                result = result * s;
                widget_size *= t2 / t1;
            }
        }

        color := ifx C.hovered_id == all_id || C.active_id == all_id
            then C.style.colors[StyleColor.View_Axis_Active]
            else C.style.colors[StyleColor.View_Axis];

        DrawCircle (
            translation,
            widget_size * C.style.scale_all_inner_circle_size,
            color,
            C.style.scale_all_handle_thickness,
            RightVector (C.camera_transform),
            UpVector (C.camera_transform)
        );

        if !dragging
        {
            DrawCircle (
                translation,
                widget_size * C.style.scale_all_outer_circle_size,
                color,
                C.style.scale_all_handle_thickness,
                RightVector (C.camera_transform),
                UpVector (C.camera_transform)
            );
        }
    }

    return scale.* != result;
}

GizmoRotation :: (id : string, rotation : *Quatf, flags : GizmoFlags = 0) -> bool
{
    C := GetContext ();

    if flags & .No_Rotation
        return false;

    gizmo_id := GetID (id);
    if C.keyboard_focus_id == gizmo_id
        C.next_keyboard_focus_id = gizmo_id;

    PushID (id);
    defer PopID ();

    matrix := GetGizmoMatrix ();
    translation := TranslationVector (matrix);

    camera_forward := ForwardVector (C.camera_transform);
    camera_right := RightVector (C.camera_transform);
    camera_up := UpVector (C.camera_transform);
    widget_size := CalculateWidgetSize (translation);

    result := rotation.*;
    defer rotation.* = result;

    trackball_id := GetID ("rotate_trackball");
    axes_ids := u32.[
        GetID ("rotate_x"),
        GetID ("rotate_y"),
        GetID ("rotate_z"),
        GetID ("rotate_view"),
        trackball_id,
    ];
    axes_vectors := Vec3f.[
        RightVector (rotation.*),
        UpVector (rotation.*),
        ForwardVector (rotation.*),
        camera_forward,
    ];
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

    if !array_find (axes_ids, C.active_id)
        DrawOrigin (translation);

    for < i : 3..0
    {
        id := axes_ids[i];
        if ignore_axes[i] || id != C.active_id && array_find (axes_ids, C.active_id)
            continue;

        axis := axes_vectors[i];
        tangent, bitangent : Vec3f;
        radius : float;
        if i == 3
        {
            tangent = RightVector (C.camera_transform);
            bitangent = UpVector (C.camera_transform);
            radius = widget_size * C.style.rotation_view_axis_size;
        }
        else
        {
            tangent = axes_vectors[(i + 1) % 3];
            bitangent = axes_vectors[(i + 2) % 3];
            radius = widget_size;
        }

        hovered := IsFacingCircleHovered (
            translation,
            radius,
            C.style.rotation_handle_thickness + ifx i == 3 then C.line_interaction_threshold,
            tangent, bitangent
        );

        drag_start, dragging, cancelled_dragging
            := DraggingBehavior (id, hovered, .Rotation_Axis, translation);

        if cancelled_dragging
            result = C.drag_start_rotation;

        if dragging
        {
            if drag_start
            {
                C.drag_start_rotation_axis = axes_vectors[i];
                C.drag_start_rotation = rotation.*;
            }

            origin := translation;
            ray_origin, ray_dir := RayFromMouse ();
            intersects, point := RayIntersectsPlane (ray_origin, ray_dir, origin, C.drag_start_rotation_axis);
            if drag_start
            {
                C.drag_start_rotation_point = point;
            }

            if intersects
            {
                begin := normalize (C.drag_start_rotation_point - translation);
                end   := normalize (point - translation);
                angle := SignedAngle (begin, end, C.drag_start_rotation_axis);

                rotated : Quatf;
                set_from_axis_and_angle (*rotated, C.drag_start_rotation_axis, angle);

                result = rotated * C.drag_start_rotation;
                normalize_or_identity (*result);

                DrawSemiCircleFilled (
                    translation,
                    radius,
                    axes_guide_colors[i] * .{1,1,1,0.3},
                    tangent, bitangent,
                    SignedAngle (tangent, begin, C.drag_start_rotation_axis), -angle
                );

                DrawLine (
                    translation,
                    translation + begin * radius,
                    axes_active_colors[i],
                    C.style.guide_line_thickness
                );

                DrawLine (
                    translation,
                    translation + end * radius,
                    axes_active_colors[i],
                    C.style.rotation_handle_thickness
                );
            }
        }

        color := ifx C.hovered_id == id || C.active_id == id
            then axes_active_colors[i] else axes_colors[i];

        if dragging
        {
            DrawCircle (
                translation,
                radius,
                color,
                C.style.rotation_handle_thickness,
                tangent, bitangent
            );
        }
        else
        {
            DrawFacingCircle (
                translation,
                radius,
                color,
                C.style.rotation_handle_thickness,
                tangent, bitangent
            );
        }
    }

    if !(flags & .No_Trackball)
    {
        hovered := IsCircleFilledHovered (translation, camera_forward, widget_size);
        drag_start, dragging, cancelled_dragging
            := DraggingBehavior (trackball_id, hovered, .Rotation_Trackball, translation);

        if cancelled_dragging
            result = C.drag_start_rotation;

        if dragging
        {
            if drag_start
            {
                C.drag_start_rotation = rotation.*;
            }

            camera_rotation := get_rotation (C.camera_view);
            start_axis := Project2DPointOn3DSphere (C.mouse_drag_start, translation, widget_size);
            start_axis = normalize (start_axis);
            start_axis = rotate (start_axis, camera_rotation);

            curr_axis := Project2DPointOn3DSphere (C.mouse_pos, translation, widget_size);
            curr_axis = normalize (curr_axis);
            curr_axis = rotate (curr_axis, camera_rotation);

            result = C.drag_start_rotation * QuatfFromVectorToVector (start_axis, curr_axis);
        }

        trackball_color := ifx C.hovered_id == trackball_id || C.active_id == trackball_id
            then C.style.colors[StyleColor.Rotation_Trackball_Active]
            else C.style.colors[StyleColor.Rotation_Trackball];

        if !dragging
        {
            DrawCircleFilled (
                translation,
                widget_size,
                trackball_color,
                RightVector (C.camera_transform), UpVector (C.camera_transform)
            );
        }
        else
        {
            DrawFacingCircle (
                translation,
                widget_size,
                C.style.colors[StyleColor.Z_Axis],
                C.style.rotation_handle_thickness,
                axes_vectors[0], axes_vectors[1]
            );
            DrawFacingCircle (
                translation,
                widget_size,
                C.style.colors[StyleColor.Y_Axis],
                C.style.rotation_handle_thickness,
                axes_vectors[2], axes_vectors[0]
            );
            DrawFacingCircle (
                translation,
                widget_size,
                C.style.colors[StyleColor.X_Axis],
                C.style.rotation_handle_thickness,
                axes_vectors[1], axes_vectors[2]
            );
        }
    }

    return rotation.* != result;
}

GizmoTransform :: (
    id : string,
    translation : *Vec3f,
    rotation : *Quatf,
    scale : *Vec3f,
    type : GizmoType,
    flags : GizmoFlags = 0
) -> bool
{
    parent := GetGizmoMatrix ();
    inv_parent := inverse (parent);

    matrix := make_translation_matrix4 (translation.*)
        * rotation_matrix (Mat4f, rotation.*)
        * make_scale_matrix4 (scale.*);

    PushGizmoMatrix (matrix);
    defer PopGizmoMatrix ();

    if #complete type ==
    {
    case .Translate;
        translation.* = transform_point (parent, translation.*);
        defer translation.* = transform_point (inv_parent, translation.*);

        return GizmoTranslation (id, translation, flags);

    case .Rotate;
        // Transform the quaternion to global space first
        // Transform back to local space afterwards
        q := QuatfFromMatrix (parent);
        inv_q := conjugate (q);
        rotation.* = q * rotation.*;
        defer rotation.* = inv_q * rotation.*;

        return GizmoRotation (id, rotation, flags);

    case .Scale;
        return GizmoScale (id, scale, flags);

    case .None;
        return false;
    }

    return false;
}
