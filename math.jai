IsFinite :: inline (val : float) -> bool #must
{
    nan, inf := is_nan_is_inf (val);

    return !nan && !inf;
}

IsFinite :: inline (val : Vec2f) -> bool #must
{
    return IsFinite (val.x) && IsFinite (val.y);
}

IsFinite :: inline (val : Vec3f) -> bool #must
{
    return IsFinite (val.x) && IsFinite (val.y) && IsFinite (val.z);
}

IsFinite :: inline (val : Vec4f) -> bool #must
{
    return IsFinite (val.x) && IsFinite (val.y) && IsFinite (val.z) && IsFinite (val.w);
}

Sign :: inline (val : $T) -> T #must
{
    if val < 0
        return -1;
    else if val > 0
        return 1;

    return 0;
}

Round :: inline (value : float) -> float #must
{
    return cast (float) (cast (int) (value + Sign (value) * 0.5));
}

Snap :: inline (value : float, grid_size : float) -> float #must
{
    return Round (value / grid_size) * grid_size;
}

ApproxZero :: inline (val : float, epsilon : float) -> bool #must
{
    return abs (val) <= epsilon;
}

ApproxEquals :: inline (left : float, right : float, epsilon : float) -> bool #must
{
    return abs (left - right) <= epsilon;
}

RightVector :: inline (q : Quatf) -> Vec3f #must
{
    return rotate (.{1,0,0}, q);
}

UpVector :: inline (q : Quatf) -> Vec3f #must
{
    return rotate (.{0,1,0}, q);
}

ForwardVector :: inline (q : Quatf) -> Vec3f #must
{
    return rotate (.{0,0,1}, q);
}

RightVector :: inline (mat : Mat4f) -> Vec3f #must
{
    return normalize (Vec3f.{mat._11, mat._21, mat._31});
}

UpVector :: inline (mat : Mat4f) -> Vec3f #must
{
    return normalize (Vec3f.{mat._12, mat._22, mat._32});
}

ForwardVector :: inline (mat : Mat4f) -> Vec3f #must
{
    return normalize (Vec3f.{mat._13, mat._23, mat._33});
}

TranslationVector :: inline (mat : Mat4f) -> Vec3f #must
{
    return .{mat._14, mat._24, mat._34};
}

RotationMatrix :: inline (mat : Mat4f) -> Mat4f #must
{
    return make_matrix_from_columns (
        RightVector (mat),
        UpVector (mat),
        ForwardVector (mat),
        Mat4f
    );
}

Angle :: inline (a : Vec2f, b : Vec2f) -> float #must
{
    denom := sqrt (dot (a, a) * dot (b, b));
    if ApproxZero (denom, 0.0001)
        return 0;

    d := clamp (dot (a, b) / denom, -1, 1);

    return acos (d);
}

SignedAngle :: inline (a : Vec2f, b : Vec2f) -> float #must
{
    s := Sign (a.x * b.y - a.y * b.y);

    return Angle (a, b) * s;
}

Angle :: inline (a : Vec3f, b : Vec3f) -> float #must
{
    denom := sqrt (dot (a, a) * dot (b, b));
    if ApproxZero (denom, 0.0001)
        return 0;

    d := clamp (dot (a, b) / denom, -1, 1);

    return acos (d);
}

SignedAngle :: inline (a : Vec3f, b : Vec3f, axis : Vec3f) -> float #must
{
    c := cross (a, b);
    s := Sign (dot (axis, c));

    return Angle (a, b) * s;
}

PerpendicularCW :: inline (vec : Vec2f) -> Vec2f #must
{
    return .{vec.y, -vec.x};
}

PerpendicularCCW :: inline (vec : Vec2f) -> Vec2f #must
{
    return .{-vec.y, vec.x};
}

QuatfFromVectorToVector :: (a : Vec3f, b : Vec3f) -> Quatf #must
{
    a_norm := normalize (a);
    b_norm := normalize (b);

    d := dot (a_norm, b_norm);

    // If a and b are parallel then there is no rotation
    if ApproxEquals (d, 1, 0.0001)
        return .{};

    // If a and b are opposite
    if ApproxEquals (d, -1, 0.0001)
    {
        q : Quatf;
        if abs (a_norm.x) > abs (a_norm.z)
            q = Quatf.{-a_norm.y, a_norm.x, 0, 0};
        else
            q = Quatf.{0, -a_norm.z, a_norm.y, 0};

        normalize_or_identity(*q);
        return q;
    }

    w := cross (a_norm, b_norm);

    q := Quatf.{xyz=w, w=d + 1};
    normalize_or_identity (*q);

    return q;
}

ClipLine :: (start : Vec3f, end : Vec3f) -> Vec3f #must, Vec3f #must
{
    C := GetContext ();

    camera_position := TranslationVector (C.camera_transform);
    camera_forward := ForwardVector (C.camera_transform);

    near_plane := camera_position + camera_forward * C.camera_near;
    far_plane := camera_position + camera_forward * C.camera_far;

    clipped_start := start;
    clipped_end := end;

    start_is_behind := dot (camera_forward, start - near_plane) < 0;
    end_is_behind := dot (camera_forward, end - near_plane) < 0;

    intersects, clipped := LineIntersectsPlane (start, end, near_plane, camera_forward);
    if intersects
    {
        if end_is_behind
            clipped_end = clipped;
        else
            clipped_start = clipped;
    }

    start_is_behind = dot (-camera_forward, start - far_plane) < 0;
    end_is_behind = dot (-camera_forward, end - far_plane) < 0;

    intersects, clipped = LineIntersectsPlane (start, end, far_plane, -camera_forward);
    if intersects
    {
        if start_is_behind
            clipped_start = clipped;
        else
            clipped_end = clipped;
    }

    return clipped_start, clipped_end;
}

WorldToScreen :: (point : Vec3f) -> bool #must, Vec2f #must
{
    C := GetContext ();

    proj := C.view_persp_projection * Vec4f.{xyz=point,w=1};
    if proj.w < 0
        return true, .{};

    proj /= proj.w;
    proj = C.inv_ortho_projection * proj;

    return false, proj.xy;
}

ProjectSphereOnScreen :: (center : Vec3f, radius : float) -> bool #must, Vec2f #must, float #must
{
    C := GetContext ();

    camera_right := RightVector (C.camera_transform);
    is_behind, proj_center := WorldToScreen (center);
    if is_behind
        return true, .{}, 0;

    is_behind=, proj_radius := WorldToScreen (center + camera_right * radius);
    if is_behind
        return true, .{}, 0;

    return false, proj_center, distance (proj_center, proj_radius);
}

Project2DPointOn3DSphere :: (point : Vec2f, world_space_center : Vec3f, world_space_radius : float) -> Vec3f #must
{
    is_behind, screen_space_center, screen_space_radius
        := ProjectSphereOnScreen (world_space_center, world_space_radius);
    if is_behind
        return .{0,0,0};

    r := screen_space_radius;
    p := screen_space_center - point;
    p.y = -p.y;

    d := length_squared (p);
    z := ifx 2 * d <= r * r
        then sqrt (r * r - d)
        else r * r / (2 * sqrt (d));

    return normalize (Vec3f.{p.x,p.y,z} - world_space_center);
}

ProjectPointOnLine2D :: (point : Vec2f, start : Vec2f, end : Vec2f) -> Vec2f #must, t : float
{
    dir := end - start;
    if !IsFinite (dir)
        return start, 0;

    len := normalize (*dir);
    t := dot (point - start, dir) / dot (dir, dir);
    t = clamp (t, 0, len);

    return start + t * dir, t;
}

ProjectPointOnLine :: (point : Vec3f, start : Vec3f, end : Vec3f) -> Vec3f #must, t : float
{
    dir := end - start;
    if !IsFinite (dir)
        return start, 0;

    len := normalize (*dir);
    t := dot (point - start, dir) / dot (dir, dir);
    t = clamp (t, 0, len);

    return start + t * dir, t;
}

ProjectPointOnInfiniteLine :: (point : Vec3f, start : Vec3f, end : Vec3f) -> Vec3f #must, t : float
{
    dir := end - start;
    if !IsFinite (dir)
        return start, 0;

    len := normalize (*dir);
    t := dot (point - start, dir) / dot (dir, dir);

    return start + t * dir, t;
}

RayFromScreenPoint :: (point : Vec2f) -> origin : Vec3f #must, direction : Vec3f #must
{
    C := GetContext ();

    ndc := (C.ortho_projection * Vec4f.{point.x, point.y, 0, 1}).xy;

    view_space := C.inv_persp_projection * Vec4f.{xy=ndc,z=0,w=1};
    view_space.z = 1;
    view_space.w = 0;

    pos := TranslationVector (C.camera_transform);
    dir := normalize ((C.camera_transform * view_space).xyz);

    return pos, dir;
}

RayFromMouse :: inline () -> origin : Vec3f #must, direction : Vec3f #must
{
    C := GetContext ();
    origin, dir := RayFromScreenPoint (C.mouse_pos);

    return origin, dir;
}

NearestPointOnRayAndLine :: (ray_origin : Vec3f, ray_dir : Vec3f, line_origin : Vec3f, line_dir : Vec3f) -> point_on_ray : Vec3f, point_on_line : Vec3f, line_dist : float, ray_dist : float
{
    p := ray_origin - line_origin;
    q := dot (ray_dir, line_dir);
    s := dot (line_dir, p);

    ray_dist, line_dist : float;
    d := 1 - q * q;
    if ApproxZero (d, 0.00001)
    {
        ray_dist = 0;
        line_dist = s;
    }
    else
    {
        r := dot (ray_dir, p);
        ray_dist = (q * s - r) / d;
        line_dist = (s - q * r) / d;
    }

    return ray_origin + ray_dist * ray_dir, line_origin + line_dist * line_dir, ray_dist, line_dist;
}

RayIntersectsPlane :: (ray_origin : Vec3f, ray_dir : Vec3f, plane_origin : Vec3f, plane_normal : Vec3f) -> bool, point : Vec3f, distance : float
{
    denom := dot (plane_normal, ray_dir);

    if !ApproxZero (denom, 0.0001)
    {
        q := plane_origin - ray_origin;
        t := dot (q, plane_normal) / denom;

        if t >= 0
            return true, ray_origin + ray_dir * t, t;
    }

    return false, .{}, 0;
}

LineIntersectsPlane :: (line_start : Vec3f, line_end : Vec3f, plane_origin : Vec3f, plane_normal : Vec3f) -> bool #must, Vec3f #must
{
    line_dir := line_end - line_start;
    if !IsFinite (line_dir)
        return false, .{};

    line_len := normalize (*line_dir);
    line_plane := dot (plane_normal, line_dir);

    if !ApproxZero (line_plane, 0.0001)
    {
        q := plane_origin - line_start;
        t := dot (q, plane_normal) / line_plane;

        if t >= 0 && t < line_len
            return true, line_start + line_dir * t;
    }

    return false, .{};
}

IsLineHovered2D :: (start : Vec2f, end : Vec2f, threshold : float) -> bool #must
{
    C := GetContext ();

    line_dir := end - start;
    if !IsFinite (line_dir)
        return false;

    normalize (*line_dir);
    mouse_on_line := ProjectPointOnLine2D (C.mouse_pos, start, end);

    return distance (mouse_on_line, C.mouse_pos) < threshold;
}

IsLineHovered :: (start : Vec3f, end : Vec3f, threshold : float) -> bool #must
{
    C := GetContext ();

    is_behind, proj_start := WorldToScreen (start);
    if is_behind
        return false;

    is_behind=, proj_end := WorldToScreen (end);
    if is_behind
        return false;

    return IsLineHovered2D (proj_start, proj_end, threshold);
}

IsCircleFilledHovered2D :: (center : Vec2f, radius : float) -> bool #must
{
    C := GetContext ();

    return distance (C.mouse_pos, center) < radius;
}

IsCircleFilledHovered :: (center : Vec3f, normal : Vec3f, radius : float) -> bool #must
{
    C := GetContext ();

    origin, direction := RayFromMouse ();
    intersected, point := RayIntersectsPlane (origin, direction, center, normal);
    if intersected
        return distance (point, center) < radius;

    return false;
}

IsFacingCircleHovered :: (center : Vec3f, radius : float, thickness : float, tangent : Vec3f, bitangent : Vec3f, epsilon := 0.01, resolution := 200) -> bool #must
{
    C := GetContext ();

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

        start := tangent * p1.x + bitangent * p1.y;
        end := tangent * p2.x + bitangent * p2.y;

        if dot (start, view_dir) > epsilon || dot (end, view_dir) > epsilon
            continue;

        start = center + start * radius;
        end = center + end * radius;

        if IsLineHovered (start, end, thickness)
            return true;
    }

    return false;
}

ToMat3f :: (mat : Mat4f) -> Mat3f #must
{
    return .{
        mat._11, mat._12, mat._13,
        mat._21, mat._22, mat._23,
        mat._31, mat._32, mat._33,
    };
}

QuatfFromMatrix :: inline (mat : $T/interface AnyMatrix3) -> Quatf #must
{
    #if T == Mat4f
        ortho, _, det := polar_decomp (ToMat3f (mat));
    else #if T == Mat3f
        ortho, _, det := polar_decomp (mat);

    nan, inf := is_nan_is_inf (det);
    if det == 0 || nan || inf
        return Quatf.{0,0,0,1};

    return QuatfFromMatrixNoChecks (ortho * det);
}

// From Blender source code:
// https://github.com/blender/blender/blob/756538b4a117cb51a15e848fa6170143b6aafcd8/source/blender/blenlib/intern/math_rotation.c#L272
// This function will fail for matrices that are not ortho normalized and positive
QuatfFromMatrixNoChecks :: inline (mat : $T/interface AnyMatrix3) -> Quatf #must
{
    /* Caller must ensure matrices aren't negative for valid results, see: T24291, T94231. */
    // assert (determinant (mat) > 0);

    /* Method outlined by Mike Day, ref: https://math.stackexchange.com/a/3183435/220949
        * with an additional `sqrtf(..)` for higher precision result.
        * Removing the `sqrt` causes tests to fail unless the precision is set to 1e-6 or larger. */

    q : Quatf = ---;

    if mat._33 < 0
    {
        if mat._11 > mat._22
        {
            trace := 1 + mat._11 - mat._22 - mat._33;
            s := 2 * sqrt (trace);
            if mat._23 < mat._32
            {
                /* Ensure W is non-negative for a canonical result. */
                s = -s;
            }
            q.x = 0.25 * s;
            s = 1 / s;
            q.w = (mat._23 - mat._32) * s;
            q.y = (mat._12 + mat._21) * s;
            q.z = (mat._31 + mat._13) * s;
            if trace == 1 && q.w == 0 && q.y == 0 && q.z == 0
            {
                /* Avoids the need to normalize the degenerate case. */
                q.x = 1;
            }
        }
        else
        {
            trace := 1 - mat._11 + mat._22 - mat._33;
            s := 2 * sqrt (trace);
            if mat._31 < mat._13
            {
                /* Ensure W is non-negative for a canonical result. */
                s = -s;
            }
            q.y = 0.25 * s;
            s = 1 / s;
            q.w = (mat._31 - mat._13) * s;
            q.x = (mat._12 + mat._21) * s;
            q.z = (mat._23 + mat._32) * s;
            if trace == 1 && q.w == 0 && q.x == 0 && q.z == 0
            {
                /* Avoids the need to normalize the degenerate case. */
                q.y = 1;
            }
        }
    }
    else
    {
        if mat._11 < -mat._22
        {
            trace := 1 - mat._11 - mat._22 + mat._33;
            s := 2 * sqrt (trace);
            if mat._12 < mat._21
            {
                /* Ensure W is non-negative for a canonical result. */
                s = -s;
            }
            q.z = 0.25 * s;
            s = 1 / s;
            q.w = (mat._12 - mat._21) * s;
            q.x = (mat._31 + mat._13) * s;
            q.y = (mat._23 + mat._32) * s;
            if trace == 1 && q.w == 0 && q.x == 0 && q.y == 0
            {
                /* Avoids the need to normalize the degenerate case. */
                q.z = 1;
            }
        }
        else
        {
            /* NOTE(@campbellbarton): A zero matrix will fall through to this block,
                * needed so a zero scaled matrices to return a quaternion without rotation, see: T101848. */
            trace := 1 + mat._11 + mat._22 + mat._33;
            s := 2 * sqrt (trace);
            q.w = 0.25 * s;
            s = 1 / s;
            q.x = (mat._23 - mat._32) * s;
            q.y = (mat._31 - mat._13) * s;
            q.z = (mat._12 - mat._21) * s;
            if trace == 1 && q.x == 0 && q.y == 0 && q.z == 0
            {
                /* Avoids the need to normalize the degenerate case. */
                q.w = 1;
            }
        }
    }

    // Not sure why I need to return the conjugate, the original code returns
    // quaternions that go in the opposite direction
    return conjugate (q);
}
