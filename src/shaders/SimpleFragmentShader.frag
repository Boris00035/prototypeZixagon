#version 410 core

// Color input from the vertex shader.
in vec4 v_Color;

// Fragment shaders must return an output.
out vec4 f_Color;

void main() {
    f_Color = v_Color;
}
