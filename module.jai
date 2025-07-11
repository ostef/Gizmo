// @Todo: fix trackball rotation gizmo not working correctly at certain camera angles
// @Todo: handle flags in KeyboardBehavior

#import "Basic";
#import "Math";
#import "Hash";

#load "draw.jai";
#load "math.jai";
#load "gizmo.jai";

Vec2f :: Vector2;
Vec3f :: Vector3;
Vec4f :: Vector4;
Mat3f :: Matrix3;
Mat4f :: Matrix4;
Quatf :: Quaternion;

Key :: enum
{
    X_Axis;
    Y_Axis;
    Z_Axis;

    Exclude; // example: press Translate then Exclude + X_Axis means translate on Y and Z

    Translate;
    Rotate;
    Scale;

    Slow;
    Snap;

    Interact;
    Submit;
    Cancel;

    Count;
}

GizmoInteractionType :: enum
{
    None;
    Translation_Axis;
    Translation_Plane;
    Scale_Axis;
    Scale_Plane;
    Scale_All;
    Rotation_Axis;
    Rotation_Trackball;
}

KeyboardInteractionType :: enum
{
    None;
    Translate;
    Scale;
    Rotate;
}

KeyboardInteractionFlags :: enum_flags
{
    X_Axis;
    Y_Axis;
    Z_Axis;
}

GizmoContext :: struct
{
    display_size : Vec2f;
    framebuffer_size : Vec2f;
    mouse_pos : Vec2f;
    prev_key_states : [Key.Count]bool;
    key_states : [Key.Count]bool;

    persp_projection : Mat4f;
    ortho_projection : Mat4f;
    view_persp_projection : Mat4f;
    inv_persp_projection : Mat4f;
    inv_ortho_projection : Mat4f;
    camera_view : Mat4f;
    camera_transform : Mat4f;
    camera_near, camera_far : float;

    wants_to_hide_cursor : bool;

    hovered_id, active_id, next_active_id : u32;
    active_interaction : GizmoInteractionType;
    active_translation : Vec3f;

    keyboard_interaction : KeyboardInteractionType;
    keyboard_interaction_flags : KeyboardInteractionFlags;

    keyboard_focus_id, next_keyboard_focus_id : u32;

    id_stack : [..]u32;
    matrix_stack : [..]Mat4f;

    mouse_drag_start : Vec2f;

    drag_start_translation : Vec3f;
    drag_start_translation_offset : Vec3f;

    drag_start_scale : Vec3f;
    drag_start_scale_axis : Vec3f;
    drag_start_scale_offset : Vec3f;

    drag_start_rotation : Quatf;
    drag_start_rotation_axis : Vec3f;
    drag_start_rotation_point : Vec3f;

    draw_vertices : [..]DrawVertex;
    text_buffer : [..]u8;
    texts_to_draw : [..]TextToDraw;

    renderer : *void;

    style : Style;
}

StyleColor :: enum
{
    Origin;
    Origin_Outline;

    X_Axis;
    Y_Axis;
    Z_Axis;
    View_Axis;
    Rotation_Trackball;

    X_Axis_Active;
    Y_Axis_Active;
    Z_Axis_Active;
    View_Axis_Active;
    Rotation_Trackball_Active;

    X_Axis_Guide;
    Y_Axis_Guide;
    Z_Axis_Guide;
    View_Axis_Guide;

    Text;
    Text_Shadow;
    Ghost_Gizmo;
    Cursor;

    Count;
}

Style :: struct
{
    global_size := 1.0;

    line_interaction_threshold := 7.0;
    sensitivity_slow_factor := 0.1;

    translation_snap_grid_size := 1.0;
    translation_drag_sensitivity := 0.01;
    translation_handle_thickness := 3.0;
    translation_arrow_size := 20.0;
    translation_arrow_aspect_ratio := 0.5;
    translation_view_circle_size := 0.2;
    translation_view_circle_thickness := 3.5;
    scale_handle_thickness := 3.5;

    scale_snap_grid_size := 0.1;
    scale_tip_size := 10.0;
    scale_all_inner_circle_size := 0.2;
    scale_all_outer_circle_size := 1.23;
    scale_all_handle_thickness := 3.5;

    rotation_snap_grid_size := 5.0 * PI / 180.0;
    rotation_handle_thickness := 4.5;
    rotation_view_axis_size := 1.23;
    rotation_view_axis_thickness := 3.5;

    guide_line_thickness := 1.0;

    cursor_line_thickness := 1.5;
    cursor_line_dash_length := 4.0;
    cursor_line_dash_spacing := 3.0;
    cursor_indicator_size := 17.0;

    origin_circle_size := 0.065;

    colors : [StyleColor.Count]Vec4f = ---;
}

InitDefaultColors :: (using style : *Style)
{
    colors[StyleColor.Origin] = .{1,0.744,0.140,1};
    colors[StyleColor.Origin_Outline] = .{0.1,0.1,0.1,1};

    colors[StyleColor.X_Axis] = .{0.886, 0.323, 0.323, 1};
    colors[StyleColor.Y_Axis] = .{0.499,0.88,0.382,1};
    colors[StyleColor.Z_Axis] = .{0.312,0.418,0.819,1};
    colors[StyleColor.View_Axis] = .{0.873,0.873,0.873,1};
    colors[StyleColor.Rotation_Trackball] = .{0,0,0,0};

    colors[StyleColor.X_Axis_Active] = .{1,0,0,1};
    colors[StyleColor.Y_Axis_Active] = .{0,1,0.067,1};
    colors[StyleColor.Z_Axis_Active] = .{0.217,0.317,1,1};
    colors[StyleColor.View_Axis_Active] = .{1,1,1,1};
    colors[StyleColor.Rotation_Trackball_Active] = .{1,1,1,0.2};

    colors[StyleColor.X_Axis_Guide] = .{1,0,0,1};
    colors[StyleColor.Y_Axis_Guide] = .{0,1,0.067,1};
    colors[StyleColor.Z_Axis_Guide] = .{0.217,0.317,1,1};
    colors[StyleColor.View_Axis_Guide] = .{1,1,1,1};

    colors[StyleColor.Text] = .{1,1,1,1};
    colors[StyleColor.Text_Shadow] = .{0,0,0,0.6};
    colors[StyleColor.Ghost_Gizmo] = .{0.5,0.5,0.5,1};
    colors[StyleColor.Cursor] = .{0.117,0.117,0.117,1};
}

GizmoType :: enum
{
    None;
    Translate;
    Rotate;
    Scale;
}

GizmoFlags :: enum_flags
{
    No_X_Axis;
    No_Y_Axis;
    No_Z_Axis;
    No_View_Axis;
    No_Trackball;

    No_Keyboard;

    No_Translation;
    No_Scale;
    No_Rotation;

    Global_Space;
}

InteractionState :: enum_flags
{
    Started;
    Interacting;
    Cancelled;
    Submitted;
}

#scope_file

g_gizmo_context : *GizmoContext;

#scope_export

CreateContext :: ()
{
    g_gizmo_context = New(GizmoContext);
    InitDefaultColors(*g_gizmo_context.style);
}

DestroyContext :: ()
{
    assert(g_gizmo_context != null, "Gizmo context not created");

    array_reset(*g_gizmo_context.id_stack);
    array_reset(*g_gizmo_context.matrix_stack);
    array_reset(*g_gizmo_context.draw_vertices);
    array_reset(*g_gizmo_context.text_buffer);
    array_reset(*g_gizmo_context.texts_to_draw);
    g_gizmo_context = null;
}

GetStyle :: inline () -> *Style
{
    return *GetContext().style;
}

GetContext :: inline () -> *GizmoContext
{
    assert(g_gizmo_context != null, "Gizmo context not created");

    return g_gizmo_context;
}

ClearKeyStates :: inline ()
{
    C := GetContext();

    memset(C.key_states.data, 0, size_of(type_of(C.key_states)));
}

SetKeyState :: inline (key : Key, state : bool)
{
    C := GetContext();

    C.key_states[key] = state;
}

IsKeyDown :: inline (key : Key) -> bool
{
    C := GetContext();

    return C.key_states[key];
}

IsKeyPressed :: inline (key : Key) -> bool
{
    C := GetContext();

    return !C.prev_key_states[key] && C.key_states[key];
}

IsKeyReleased :: inline (key : Key) -> bool
{
    C := GetContext();

    return C.prev_key_states[key] && !C.key_states[key];
}

SetKeyboardFocus :: inline (id : string)
{
    SetKeyboardFocus(GetID(id));
}

SetKeyboardFocus :: inline (id : u32)
{
    C := GetContext();

    C.keyboard_focus_id = id;
    C.next_keyboard_focus_id = id;
}

SetCamera :: (
    persp_projection : Mat4f,
    ortho_projection : Mat4f,
    view : Mat4f,
    near : float, far : float
)
{
    C := GetContext();
    C.persp_projection = persp_projection;
    C.inv_persp_projection = inverse(persp_projection);
    C.ortho_projection = ortho_projection;
    C.inv_ortho_projection = inverse(ortho_projection);
    C.view_persp_projection = persp_projection * view;
    C.camera_view = view;
    C.camera_transform = inverse(view);
    C.camera_near = near;
    C.camera_far = far;
}

NewFrame :: (
    display_size : Vec2f,
    scale_factor : float,
    mouse_pos : Vec2f
)
{
    C := GetContext();
    C.hovered_id = 0;
    C.active_id = C.next_active_id;
    C.next_active_id = 0;

    C.keyboard_focus_id = C.next_keyboard_focus_id;
    C.next_keyboard_focus_id = 0;

    if C.active_id == 0
    {
        C.active_interaction = .None;
        C.keyboard_interaction = .None;
        C.keyboard_interaction_flags = 0;
    }

    if C.keyboard_focus_id == 0
    {
        C.keyboard_interaction = .None;
        C.keyboard_interaction_flags = 0;
    }

    C.display_size = display_size;
    C.framebuffer_size = display_size * scale_factor;
    C.mouse_pos = mouse_pos;

    C.text_buffer.count = 0;
    C.texts_to_draw.count = 0;
}

EndFrame :: ()
{
    DrawCursorArrow :: (center : Vec2f, dir : Vec2f)
    {
        C := GetContext();

        size := C.style.cursor_indicator_size;

        DrawArrow2D(
            center + dir * size * 0.2,
            center + dir * size * 0.5,
            C.style.colors[StyleColor.Cursor],
            size * 0.2,
            size * 0.5
        );
    }

    C := GetContext();

    memcpy(C.prev_key_states.data, C.key_states.data, size_of(type_of(C.key_states)));

    // Draw cursor
    is_behind, active_center := WorldToScreen(C.active_translation);
    if is_behind
    {
        dir := normalize(C.mouse_pos - active_center);

        if C.active_interaction ==
        {
        case .Translation_Axis; #through;
        case .Translation_Plane;
            DrawCursorArrow(C.mouse_pos, .{1,0});
            DrawCursorArrow(C.mouse_pos, .{-1,0});
            DrawCursorArrow(C.mouse_pos, .{0,1});
            DrawCursorArrow(C.mouse_pos, .{0,-1});
            C.wants_to_hide_cursor = true;

        case .Scale_Axis; #through;
        case .Scale_Plane; #through;
        case .Scale_All;
            DrawDashedLine2D(
                active_center, C.mouse_pos,
                C.style.cursor_line_dash_length,
                C.style.cursor_line_dash_spacing,
                C.style.colors[StyleColor.Cursor],
                C.style.cursor_line_thickness
            );

            DrawCursorArrow(C.mouse_pos, -dir);
            DrawCursorArrow(C.mouse_pos, dir);
            C.wants_to_hide_cursor = true;

        case .Rotation_Axis;
            DrawDashedLine2D(
                active_center, C.mouse_pos,
                C.style.cursor_line_dash_length,
                C.style.cursor_line_dash_spacing,
                C.style.colors[StyleColor.Cursor],
                C.style.cursor_line_thickness
            );

            DrawCursorArrow(C.mouse_pos, PerpendicularCW(dir));
            DrawCursorArrow(C.mouse_pos, PerpendicularCCW(dir));
            C.wants_to_hide_cursor = true;

        case .Rotation_Trackball;
            DrawCursorArrow(C.mouse_pos, .{1,0});
            DrawCursorArrow(C.mouse_pos, .{-1,0});
            DrawCursorArrow(C.mouse_pos, .{0,1});
            DrawCursorArrow(C.mouse_pos, .{0,-1});
            C.wants_to_hide_cursor = true;

        case;
            C.wants_to_hide_cursor = false;
        }
    }
}

GetID :: (str : string, hash_with_id_stack := true) -> u32
{
    C := GetContext();
    id := get_hash(str);

    if hash_with_id_stack && C.id_stack.count > 0
        id = get_hash(id, C.id_stack[C.id_stack.count - 1]);

    return id;
}

PushID :: (str : string, hash_with_id_stack := true)
{
    PushID(GetID(str, false), hash_with_id_stack);
}

PushID :: (id : u32, hash_with_id_stack := true)
{
    C := GetContext();
    if hash_with_id_stack && C.id_stack.count > 0
        id = get_hash(id, C.id_stack[C.id_stack.count - 1]);

    array_add(*C.id_stack, id);
}

PopID :: ()
{
    C := GetContext();
    pop(*C.id_stack);
}

GetGizmoMatrix :: (peek := 0) -> Mat4f
{
    C := GetContext();

    if peek < C.matrix_stack.count
        return C.matrix_stack[C.matrix_stack.count - 1 - peek];

    return Matrix4_Identity;
}

PushGizmoMatrix :: (mat : Mat4f, apply_previous_matrix := true)
{
    C := GetContext();

    m := mat;
    if C.matrix_stack.count > 0 && apply_previous_matrix
        m = C.matrix_stack[C.matrix_stack.count - 1] * mat;

    array_add(*C.matrix_stack, m);
}

PopGizmoMatrix :: ()
{
    C := GetContext();
    pop(*C.matrix_stack);
}

DraggingBehavior :: (id : u32, hovered : bool, interaction : GizmoInteractionType, translation : Vec3f) -> InteractionState
{
    C := GetContext();

    state : InteractionState;

    if C.active_id == 0 && C.hovered_id == 0 && hovered
        C.hovered_id = id;

    if C.hovered_id == id && IsKeyPressed(.Interact)
    {
        C.active_id = id;
        C.next_active_id = id;

        C.mouse_drag_start = C.mouse_pos;

        state |= .Started;
    }

    if C.active_id == id
    {
        if !(state & .Started) && IsKeyPressed(.Cancel)
        {
            C.active_id = 0;
            state |= .Cancelled;
        }
        else if IsKeyDown(.Interact)
        {
            state |= .Interacting;
            C.next_active_id = id;
            C.active_interaction = interaction;
            C.active_translation = translation;
        }
        else
        {
            state |= .Submitted;
            C.active_id = 0;
        }
    }

    return state;
}

KeyboardBehavior :: (id : u32, type : KeyboardInteractionType, translation : Vec3f) -> InteractionState
{
    C := GetContext();

    if C.keyboard_focus_id != id
        return 0;

    C.next_keyboard_focus_id = id;

    if C.active_id != 0 && C.active_id != id
        return 0;

    if C.keyboard_interaction == type && IsKeyPressed(.Submit)
    {
        C.next_active_id = 0;
        return .Submitted;
    }

    state : InteractionState;
    if C.keyboard_interaction != type
    {
        if type == .Translate && IsKeyPressed(.Translate)
        {
            C.keyboard_interaction = .Translate;
            C.mouse_drag_start = C.mouse_pos;
            state |= .Started;
        }

        if type == .Scale && IsKeyPressed(.Scale)
        {
            C.keyboard_interaction = .Scale;
            C.mouse_drag_start = C.mouse_pos;
            state |= .Started;
        }

        if type == .Rotate && IsKeyPressed(.Rotate)
        {
            C.keyboard_interaction = .Rotate;
            C.mouse_drag_start = C.mouse_pos;
            state |= .Started;
        }
    }

    if C.keyboard_interaction == type && !(state & .Started) && IsKeyPressed(.Cancel)
    {
        C.next_active_id = 0;
        return .Cancelled;
    }

    if C.keyboard_interaction == type
    {
        state |= .Interacting;

        C.active_id = id;
        C.next_active_id = id;
        C.active_translation = translation;

        exclude := IsKeyDown(.Exclude);
        if IsKeyPressed(.X_Axis)
        {
            if exclude
                C.keyboard_interaction_flags = .Y_Axis | .Z_Axis;
            else if C.keyboard_interaction_flags == .X_Axis
                C.keyboard_interaction_flags = 0;
            else
                C.keyboard_interaction_flags = .X_Axis;

            state |= .Started;
            state |= .Cancelled;
        }
        else if IsKeyPressed(.Y_Axis)
        {
            if exclude
                C.keyboard_interaction_flags = .X_Axis | .Z_Axis;
            else if C.keyboard_interaction_flags == .Y_Axis
                C.keyboard_interaction_flags = 0;
            else
                C.keyboard_interaction_flags = .Y_Axis;

            state |= .Started;
            state |= .Cancelled;
        }
        else if IsKeyPressed(.Z_Axis)
        {
            if exclude
                C.keyboard_interaction_flags = .X_Axis | .Y_Axis;
            else if C.keyboard_interaction_flags == .Z_Axis
                C.keyboard_interaction_flags = 0;
            else
                C.keyboard_interaction_flags = .Z_Axis;

            state |= .Started;
            state |= .Cancelled;
        }
    }

    return state;
}
