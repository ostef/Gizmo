# Gizmo
Example (pseudo-code ish):

```
#import "Math";
Gizmo :: #import "Gizmo";
Gizmo_GL :: #import "Gizmo/GL";

main :: ()
{
    // Window and GL context creation

    Gizmo.CreateContext ();
    defer Gizmo.DestroyContext ();
    defer Gizmo_GL.Cleanup ();

    transform : Matrix4;
    translation : Vector3;
    while true
    {
        // Poll window events

        Gizmo.SetKeyState (.Interact, IsMouseButtonDown (.Left));
        Gizmo.SetKeyState (.Cancel, IsKeyDown (.Escape));

        Gizmo.NewFrame (
            display_size,
            mouse_position,
            perspective_projection,
            orthographic_projection,
            view_matrix,
            view_near,
            view_far
        );

        if Gizmo.GizmoTranslation ("translate", *translation)
        {
            transform = make_translation_matrix4 (translation);
        }

        Gizmo.EndFrame ();

        glViewport (0, 0, xx display_size.x, xx display_size.y);
        glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        Gizmo_GL.RenderDrawData ();

        // Swap buffers
    }
}
```
