#version 440
// Rounded-rectangle clip for a layer: pixels outside the corner arcs become transparent, the edge is
// antialiased over one device pixel. Sizes are in device pixels.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 pixelSize;  // item size, device pixels
    float radius;    // corner radius, device pixels
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 half_size = pixelSize * 0.5;
    vec2 q = abs(qt_TexCoord0 * pixelSize - half_size) - (half_size - vec2(radius));
    float d = length(max(q, 0.0)) - radius;   // > 0 outside the shape
    float a = clamp(0.5 - d, 0.0, 1.0);
    fragColor = texture(source, qt_TexCoord0) * (a * qt_Opacity);
}
