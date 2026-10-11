#version 440
// Окраска белой маски в цвет tint: так MorphShape меняет цвет без перестройки геометрии
// (CurveRenderer пересчитывает фигуру при каждой смене fillColor — дорого при перекраске темы).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float a = texture(source, qt_TexCoord0).a * qt_Opacity * tint.a;
    fragColor = vec4(tint.rgb * a, a);
}
