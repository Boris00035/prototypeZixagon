#version 410 core

// Width/height of the framebuffer (= the window).
uniform vec2 u_FramebufferSize;
uniform vec2 u_hexagonPosition;
uniform float u_Angle; 

// Vertex position and color as defined in the mesh.
in vec4 a_Position;
in vec4 a_Color;

// Color result that will be passed to the fragment shader.
out vec4 v_Color;

void main() {
    // Account for the window's aspect ratio. We want a 1:1 width/height ratio.
    float scaleX = min(u_FramebufferSize.y / u_FramebufferSize.x, 1) / 2;
    float scaleY = min(u_FramebufferSize.x / u_FramebufferSize.y, 1) / 2;

    gl_Position = vec4(
        (a_Position.x * cos(u_Angle) - a_Position.y * sin(u_Angle) + u_hexagonPosition.x) * scaleX,
        (a_Position.x * sin(u_Angle) + a_Position.y * cos(u_Angle) + u_hexagonPosition.x) * scaleY,
        a_Position.zw);

    // Pass the vertex's color to the fragment shader.
    v_Color = a_Color;
}