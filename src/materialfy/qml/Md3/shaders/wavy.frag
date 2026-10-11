#version 440
// Волнистый прогресс MD3 Expressive целиком на GPU: проигранная часть — синусоида толщины thickness
// со скруглёнными концами, остаток — прямой трек с зазором, в конце — stop-точка.
// Раньше это был Shape: сотни точек пересобирались на CPU каждый кадр бегущей волны.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // px
    float thickness;
    float amp;
    float k;            // 2π / длина волны
    float phase;
    float activeEnd;    // x конца проигранной части
    float x0;
    float x1;
    float trackStart;   // x начала остатка
    float showStop;     // 1 — рисовать stop-точку
    float showActive;   // 0 — значение 0, волны нет
    vec4 activeColor;
    vec4 trackColor;
    vec4 stopColor;
};

float waveY(float x, float cy) { return cy + amp * sin(k * x - phase); }

void main() {
    vec2 p = qt_TexCoord0 * size;
    float cy = size.y * 0.5;
    float r = thickness * 0.5;
    vec4 c = vec4(0.0);

    // остаток трека: капсула [trackStart, x1]
    if (trackStart < x1) {
        float tx = clamp(p.x, trackStart, x1);
        float d = length(p - vec2(tx, cy));
        float a = clamp(r - d + 0.5, 0.0, 1.0);
        c = trackColor * trackColor.a * a + c * (1.0 - trackColor.a * a);
    }
    // stop-точка
    if (showStop > 0.5) {
        float d = length(p - vec2(x1, cy));
        float a = clamp(r - d + 0.5, 0.0, 1.0);
        c = stopColor * stopColor.a * a + c * (1.0 - stopColor.a * a);
    }
    // волна: расстояние до кривой (первый порядок) + круглые концы
    if (showActive > 0.5) {
        float d;
        if (p.x < x0) {
            d = length(p - vec2(x0, waveY(x0, cy)));
        } else if (p.x > activeEnd) {
            d = length(p - vec2(activeEnd, waveY(activeEnd, cy)));
        } else {
            float slope = amp * k * cos(k * p.x - phase);
            d = abs(p.y - waveY(p.x, cy)) / sqrt(1.0 + slope * slope);
        }
        float a = clamp(r - d + 0.5, 0.0, 1.0);
        c = activeColor * activeColor.a * a + c * (1.0 - activeColor.a * a);
    }
    fragColor = vec4(c.rgb, c.a) * qt_Opacity;
}
