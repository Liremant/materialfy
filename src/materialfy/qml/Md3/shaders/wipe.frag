#version 440
// Смена темы: снимок окна со старыми цветами уходит, открывая новые. Четыре способа (mode):
//   0 — шторка: мягкий, чуть наклонный край; dir = +1 — слева направо, -1 — справа налево;
//   1 — волна: новое расходится от точки origin фигурой с волнистым краем (край вращается по dir);
//   2 — растворение: снимок равномерно тает;
//   3 — перетекание: снимок тает по плавному шуму и при этом «плывёт» — волна шума идёт по dir.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float dir;
    float edge;
    float skew;
    float shown;
    float mode;
    float aspect;   // ширина / высота
    float seed;
    vec2 origin;    // центр волны, доли размера
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    return (noise(p) + 0.5 * noise(p * 2.03 + 11.7) + 0.25 * noise(p * 4.01 + 5.3)) / 1.75;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 at = uv;       // откуда брать снимок
    float a;            // сколько осталось от старого
    if (mode < 0.5) {
        float x = dir > 0.0 ? uv.x : 1.0 - uv.x;
        float t = x + skew * (uv.y - 0.5);
        float front = progress * (1.0 + edge + skew) - edge - skew * 0.5;
        a = smoothstep(front, front + edge, t);
    } else if (mode < 1.5) {
        vec2 k = vec2(aspect, 1.0);
        vec2 d = (uv - origin) * k;
        float far = length(max(origin, 1.0 - origin) * k);
        float lobes = 1.0 + 0.07 * cos(9.0 * atan(d.y, d.x) + dir * (seed + progress * 2.6));
        float soft = 0.05;
        float front = progress * (far * 1.08 + soft);
        a = smoothstep(front - soft, front, length(d) / lobes);
    } else if (mode < 2.5) {
        a = 1.0 - progress;
    } else {
        vec2 q = uv * vec2(aspect, 1.0) + seed;
        float x = dir > 0.0 ? uv.x : 1.0 - uv.x;
        float v = mix(fbm(q * 2.4), x, 0.4);
        float soft = 0.22;
        float front = progress * (1.0 + soft) - soft;
        a = smoothstep(front, front + soft, v);
        at += (vec2(noise(q * 3.1 + 7.3), noise(q * 3.1 + 19.1)) - 0.5) * 0.05 * progress;
    }
    fragColor = texture(source, at) * a * shown * qt_Opacity;
}
