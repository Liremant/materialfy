#version 440
// Vertical alpha fade: transparent at the top/bottom edges, opaque inside.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float fadeTop;     // fade height at the top, item-normalized
    float fadeBottom;  // fade height at the bottom, item-normalized
    float cut;         // empty band below the faded content, item-normalized (0: content reaches the bottom edge)
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float y = qt_TexCoord0.y;
    float a = smoothstep(0.0, max(fadeTop, 1e-4), y) * smoothstep(0.0, max(fadeBottom, 1e-4), 1.0 - cut - y);
    fragColor = texture(source, qt_TexCoord0) * a * qt_Opacity;
}
