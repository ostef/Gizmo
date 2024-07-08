// @Todo: use indices to reduce memory usage

DrawVertex :: struct
{
    position : Vec3f;
    color : Vec4f;
}

DrawOrigin :: (center : Vec3f)
{
    C := GetContext ();

    if C.style.origin_circle_size <= 0
        return;

    camera_right := RightVector (C.camera_transform);
    camera_up := UpVector (C.camera_transform);
    widget_size := CalculateWidgetSize (center);

    DrawCircleFilled (
        center,
        widget_size * C.style.origin_circle_size,
        C.style.colors[StyleColor.Origin_Outline],
        camera_right, camera_up
    );

    DrawCircleFilled (
        center,
        widget_size * C.style.origin_circle_size * 0.7,
        C.style.colors[StyleColor.Origin],
        camera_right, camera_up
    );
}

DrawTriangle :: (p0 : Vec3f, p1 : Vec3f, p2 : Vec3f, color : Vec4f)
{
    C := GetContext ();

    is_behind, proj_p0 := WorldToScreen (p0);
    if is_behind
        return;

    is_behind=, proj_p1 := WorldToScreen (p1);
    if is_behind
        return;

    is_behind=, proj_p2 := WorldToScreen (p2);
    if is_behind
        return;

    DrawTriangle2D (proj_p0, proj_p1, proj_p2, color);
}

DrawTriangle2D :: (p0 : Vec2f, p1 : Vec2f, p2 : Vec2f, color : Vec4f)
{
    C := GetContext ();

    array_add (*C.draw_vertices, .{.{xy=p0}, color});
    array_add (*C.draw_vertices, .{.{xy=p1}, color});
    array_add (*C.draw_vertices, .{.{xy=p2}, color});
}

DrawArrow2D :: (start : Vec2f, end : Vec2f, color : Vec4f, thickness : float, size : float, head_aspect_ratio := 1.0)
{
    if thickness <= 0 || color.w <= 0
        return;

    line_dir := end - start;
    if !IsFinite (line_dir)
        return;

    normalize (*line_dir);

    offset := Vec2f.{-line_dir.y, line_dir.x};
    line_offset := offset * thickness * 0.5;

    DrawTriangle2D (
        start - line_offset,
        start + line_offset,
        end + line_offset,
        color
    );

    DrawTriangle2D (
        start - line_offset,
        end + line_offset,
        end - line_offset,
        color
    );

    if size > 0 && head_aspect_ratio > 0
    {
        head_p0 := end - offset * size * 0.5 * head_aspect_ratio;
        head_p1 := end + offset * size * 0.5 * head_aspect_ratio;
        head_p2 := end + line_dir * size;
        DrawTriangle2D (head_p0, head_p1, head_p2, color);
    }
}

DrawSquareArrow2D :: (start : Vec2f, end : Vec2f, color : Vec4f, thickness : float, size : float)
{
    if thickness <= 0 || color.w <= 0
        return;

    line_dir := end - start;
    if !IsFinite (line_dir)
        return;

    normalize (*line_dir);
    offset := Vec2f.{-line_dir.y, line_dir.x};
    line_offset := offset * thickness * 0.5;

    DrawTriangle2D (
        start - line_offset,
        start + line_offset,
        end + line_offset,
        color
    );

    DrawTriangle2D (
        start - line_offset,
        end + line_offset,
        end - line_offset,
        color
    );

    if size > 0
    {
        head_p0 := end + Vec2f.{-1,-1} * size * 0.5;
        head_p1 := end + Vec2f.{1,-1} * size * 0.5;
        head_p2 := end + Vec2f.{1,1} * size * 0.5;
        head_p3 := end + Vec2f.{-1,1} * size * 0.5;
        DrawTriangle2D (head_p0, head_p1, head_p2, color);
        DrawTriangle2D (head_p0, head_p3, head_p2, color);
    }
}

DrawLine2D :: (start : Vec2f, end : Vec2f, color : Vec4f, thickness : float)
{
    DrawArrow2D (start, end, color, thickness, 0);
}

DrawDashedLine2D :: (start : Vec2f, end : Vec2f, line_len : float, spacing : float, color : Vec4f, thickness : float)
{
    if thickness <= 0 || line_len <= 0 || color.w <= 0
        return;

    spacing = max (spacing, 0);

    dir := end - start;
    if !IsFinite (dir)
        return;

    len := normalize (*dir);

    i := 0.0;
    while i < len
    {
        i2 := min (i + line_len, len);
        DrawLine2D (start + dir * i, start + dir * i2, color, thickness);

        i += line_len + spacing;
    }
}

DrawLine :: (start : Vec3f, end : Vec3f, color : Vec4f, thickness : float)
{
    DrawArrow (start, end, color, thickness, 0);
}

DrawArrow :: (start : Vec3f, end : Vec3f, color : Vec4f, thickness : float, size : float, head_aspect_ratio := 1.0)
{
    C := GetContext ();

    clip_start, clip_end := ClipLine (start, end);

    is_behind, proj_start := WorldToScreen (clip_start);
    if is_behind
        return;

    is_behind=, proj_end := WorldToScreen (clip_end);
    if is_behind
        return;

    DrawArrow2D (proj_start, proj_end, color, thickness, size, head_aspect_ratio);
}

DrawSquareArrow :: (start : Vec3f, end : Vec3f, color : Vec4f, thickness : float, size : float)
{
    C := GetContext ();

    clip_start, clip_end := ClipLine (start, end);

    is_behind, proj_start := WorldToScreen (clip_start);
    if is_behind
        return;

    is_behind=, proj_end := WorldToScreen (clip_end);
    if is_behind
        return;

    DrawSquareArrow2D (proj_start, proj_end, color, thickness, size);
}

DrawSemiCircleFilled :: (center : Vec3f, radius : float, color : Vec4f, tangent : Vec3f, bitangent : Vec3f, start_angle : float, angle : float, resolution := 100)
{
    C := GetContext ();

    if radius <= 0 || color.w <= 0
        return;

    theta := -angle / cast (float) resolution;
    tan_factor := tan (theta);
    rad_factor := cos (theta);
    p := Vec2f.{cos (start_angle), sin (start_angle)};

    for i : 0..resolution - 1
    {
        p1 := p;

        t := Vec2f.{-p.y, p.x};

        p += t * tan_factor;
        p *= rad_factor;

        p2 := p;

        start := center + (tangent * p1.x + bitangent * p1.y) * radius;
        end := center + (tangent * p2.x + bitangent * p2.y) * radius;

        DrawTriangle (center, start, end, color);
    }
}

DrawCircleFilled :: (center : Vec3f, radius : float, color : Vec4f, tangent : Vec3f, bitangent : Vec3f, resolution := 100)
{
    DrawSemiCircleFilled (center, radius, color, tangent, bitangent, 0, PI * 2, resolution);
}

DrawCircle :: (center : Vec3f, radius : float, color : Vec4f, thickness : float, tangent : Vec3f, bitangent : Vec3f, resolution := 200)
{
    C := GetContext ();

    if radius <= 0 || color.w <= 0
        return;

    theta := -PI * 2 / cast (float) resolution;
    tan_factor := tan (theta);
    rad_factor := cos (theta);
    p := Vec2f.{1,0};

    for i : 0..resolution - 1
    {
        p1 := p;

        t := Vec2f.{-p.y, p.x};

        p += t * tan_factor;
        p *= rad_factor;

        p2 := p;

        start := center + (tangent * p1.x + bitangent * p1.y) * radius;
        end := center + (tangent * p2.x + bitangent * p2.y) * radius;

        DrawLine (start, end, color, thickness);
    }
}

DrawFacingCircle :: (center : Vec3f, radius : float, color : Vec4f, thickness : float, tangent : Vec3f, bitangent : Vec3f, epsilon := 0.02, resolution := 200)
{
    C := GetContext ();

    if radius <= 0 || color.w <= 0
        return;

    view_dir := ForwardVector (C.camera_transform);

    theta := -PI * 2 / cast (float) resolution;
    tan_factor := tan (theta);
    rad_factor := cos (theta);
    p := Vec2f.{1,0};

    for i : 0..resolution - 1
    {
        p1 := p;

        t := Vec2f.{-p.y, p.x};

        p += t * tan_factor;
        p *= rad_factor;

        p2 := p;

        start := center + (tangent * p1.x + bitangent * p1.y) * radius;
        end := center + (tangent * p2.x + bitangent * p2.y) * radius;

        if dot (start - center, view_dir) > epsilon || dot (end - center, view_dir) > epsilon
            continue;

        DrawLine (start, end, color, thickness);
    }
}
