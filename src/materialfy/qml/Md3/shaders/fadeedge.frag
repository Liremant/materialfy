#version 440
// Текст, который не влез, уходит в прозрачность к концевому краю вместо многоточия (Label.fade).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float fadeFrom;     // доля ширины, с которой начинается затухание
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float keep = 1.0 - smoothstep(fadeFrom, 1.0, qt_TexCoord0.x);
    fragColor = texture(source, qt_TexCoord0) * keep * qt_Opacity;
}
