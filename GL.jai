#import "Basic";
#import "GL";
Gizmo :: #import "Gizmo";

RendererData :: struct
{
    vbo_size : s64;
    vao, vbo : GLuint;
    shader : GLuint;
    proj_location : GLint;
}

Vertex_Shader :: #string GLSL
#version 330 core

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec4 in_color;

uniform mat4 u_projection_matrix;

out vec4 color;

void main()
{
    color = in_color;
    gl_Position = u_projection_matrix * vec4(in_position, 1);
}
GLSL

Fragment_Shader :: #string GLSL
#version 330 core

in vec4 color;

out vec4 frag_color;

void main()
{
    frag_color = color;
}
GLSL

CreateShader :: () -> GLuint #must
{
    status, log_length : GLint;

    vertex_shader := glCreateShader(GL_VERTEX_SHADER);
    defer glDeleteShader(vertex_shader);

    vertex_source := Vertex_Shader;
    glShaderSource(vertex_shader, 1, *vertex_source.data, null);
    glCompileShader(vertex_shader);

    glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, *status);
    if !status
    {
        glGetShaderiv(vertex_shader, GL_INFO_LOG_LENGTH, *log_length);

        buffer := alloc(log_length + 1 ,, temp);
        glGetShaderInfoLog(vertex_shader, xx log_length, null, buffer);

        message := string.{log_length, buffer};

        assert(false, "Could not compile Gizmo vertex shader:\n%", message);
    }

    fragment_shader := glCreateShader(GL_FRAGMENT_SHADER);
    defer glDeleteShader(fragment_shader);

    fragment_source := Fragment_Shader;
    glShaderSource(fragment_shader, 1, *fragment_source.data, null);
    glCompileShader(fragment_shader);

    glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, *status);
    if !status
    {
        glGetShaderiv(fragment_shader, GL_INFO_LOG_LENGTH, *log_length);

        buffer := alloc(log_length + 1 ,, temp);
        glGetShaderInfoLog(fragment_shader, xx log_length, null, buffer);

        message := string.{log_length, buffer};

        assert(false, "Could not compile Gizmo fragment shader:\n%", message);
    }

    program := glCreateProgram();

    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);

    glGetProgramiv(program, GL_LINK_STATUS, *status);
    if !status
    {
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, *log_length);

        buffer := alloc(log_length + 1 ,, temp);
        glGetProgramInfoLog(program, xx log_length, null, buffer);

        message := string.{log_length, buffer};

        assert(false, "Could not compile Gizmo fragment shader:\n%", message);
    }

    return program;
}

RenderDrawData :: ()
{
    C := Gizmo.GetContext();
    if !C.renderer
    {
        R := New(RendererData);
        C.renderer = R;

        glGenVertexArrays(1, *R.vao);
        glGenBuffers(1, *R.vbo);

        glBindVertexArray(R.vao);
        glBindBuffer(GL_ARRAY_BUFFER, R.vbo);

        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Gizmo.DrawVertex), cast(*void) 0);

        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, size_of(Gizmo.DrawVertex), cast(*void) size_of(Gizmo.Vec3f));

        R.shader = CreateShader();
        R.proj_location = glGetUniformLocation(R.shader, "u_projection_matrix");
    }

    R := cast(*RendererData) C.renderer;

    defer C.draw_vertices.count = 0;

    glBindVertexArray(R.vao);
    defer glBindVertexArray(0);

    glBindBuffer(GL_ARRAY_BUFFER, R.vbo);
    defer glBindBuffer(GL_ARRAY_BUFFER, 0);

    if R.vbo_size < C.draw_vertices.count * size_of(Gizmo.DrawVertex)
    {
        glBufferData(
            GL_ARRAY_BUFFER,
            size_of(Gizmo.DrawVertex) * C.draw_vertices.count,
            C.draw_vertices.data,
            GL_DYNAMIC_DRAW
        );

        R.vbo_size = C.draw_vertices.count * size_of(Gizmo.DrawVertex);
    }
    else
    {
        glBufferSubData(
            GL_ARRAY_BUFFER,
            0,
            size_of(Gizmo.DrawVertex) * C.draw_vertices.count,
            C.draw_vertices.data
        );
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    glViewport(0, 0, xx C.framebuffer_size.x, xx C.framebuffer_size.y);

    glUseProgram(R.shader);

    glDisable(GL_CULL_FACE);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUniformMatrix4fv(R.proj_location, 1, GL_TRUE, xx *C.ortho_projection);

    glDrawArrays(GL_TRIANGLES, 0, xx C.draw_vertices.count);

    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

Cleanup :: ()
{
    C := Gizmo.GetContext();
    assert(C != null, "Gizmo context not created or already destroyed");

    R := cast(*RendererData) C.renderer;
    if !R
        return;

    glDeleteVertexArrays(1, *R.vao);
    glDeleteBuffers(1, *R.vbo);
    R.vbo_size = 0;
}
