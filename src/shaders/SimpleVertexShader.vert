#version 410 core

// Width/height of the framebuffer (= the window).
uniform vec2 u_FramebufferSize;

// Angle of the object we're drawing, in radians.
uniform float u_Angle;

uniform float u_verplaatsen;

// Vertex position and color as defined in the mesh.
in vec4 a_Position;
in vec4 a_Color;

// Color result that will be passed to the fragment shader.
out vec4 v_Color;

void main() {
    // Account for the window's aspect ratio. We want a 1:1 width/height ratio.
    float scaleX = min(u_FramebufferSize.y / u_FramebufferSize.x, 1) / 2;
    float scaleY = min(u_FramebufferSize.x / u_FramebufferSize.y, 1) / 2;

    float s = sin(u_Angle);
    float c = cos(u_Angle);

    gl_Position = vec4(
        (a_Position.x * c + a_Position.y * -s + u_verplaatsen) * scaleX ,
        (a_Position.x * s + a_Position.y * c) * scaleY,
        a_Position.zw
    ) * vec4(0.875, 0.875, 1, 1); // Shrink the object slightly to fit the window.

    // Pass the vertex's color to the fragment shader.
    v_Color = a_Color;
}