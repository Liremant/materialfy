#version 440
// Apple Music-style word sweep: left of `progress` is bright, right is dim,
// with a soft feathered edge in between.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;    // 0..1 fill edge, in item-normalized x
    float feather;     // half width of the soft edge, item-normalized
    float dimAlpha;    // alpha multiplier of not-yet-sung text
    float glow;        // 0..1 extra brightness for held notes
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    float f = 1.0 - smoothstep(progress - feather, progress + feather, qt_TexCoord0.x);
    float a = mix(dimAlpha, 1.0, f);
    vec4 c = tex * a;
    c.rgb += c.a * glow * f * 0.12;
    fragColor = c * qt_Opacity;
}
