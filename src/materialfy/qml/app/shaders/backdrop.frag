#version 440
// Фон из обложки. Размытие — не свёртка, а увеличение крошечной копии обложки (её делает загрузчик
// картинок): кубический B-сплайн почти совпадает с гауссом и даёт гладкий результат без сетки,
// линейная интерполяция (cubic = 0) — прежние «пятна». Сила размытия — размер копии.
// «Плавание»: картинка на месте, плавное поле смещений (сумма синусов) двигает точку выборки.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float amp;          // сила смещения, доля размера
    float inset;        // запас по краям под смещение
    float cubic;        // 1 — B-сплайн, 0 — линейная интерполяция
    float saturation;   // 1 — как есть
    float grain;        // зерно «матового стекла»
    vec2 texSize;       // размер копии обложки, тексели
    vec2 crop;          // видимая доля обложки по осям (обрезка под пропорции элемента)
};
layout(binding = 1) uniform sampler2D source;

// Четыре линейные выборки вместо шестнадцати: пары соседних весов сплайна сливаются в одну
vec3 bspline(vec2 uv) {
    vec2 st = uv * texSize - 0.5;
    vec2 i = floor(st);
    vec2 f = st - i;
    vec2 f2 = f * f, f3 = f2 * f;
    vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
    vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
    vec2 w3 = f3 / 6.0;
    vec2 g0 = w0 + w1;
    vec2 g1 = 1.0 - g0;
    vec2 p0 = (i + w1 / g0 - 0.5) / texSize;
    vec2 p1 = (i + w3 / g1 + 1.5) / texSize;
    return g0.y * (g0.x * texture(source, p0).rgb + g1.x * texture(source, vec2(p1.x, p0.y)).rgb)
         + g1.y * (g0.x * texture(source, vec2(p0.x, p1.y)).rgb + g1.x * texture(source, p1).rgb);
}

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float t = time;
    vec2 off = vec2(
        sin(uv.y * 4.1 + t * 0.83) + 0.6 * sin(uv.x * 6.3 - t * 0.57 + 1.7) + 0.35 * sin((uv.x + uv.y) * 9.0 + t * 1.1),
        cos(uv.x * 3.7 - t * 0.71) + 0.6 * sin(uv.y * 5.9 + t * 0.49 + 0.6) + 0.35 * cos((uv.x - uv.y) * 8.0 - t * 0.9)
    ) / 1.95;
    vec2 p = inset + uv * (1.0 - 2.0 * inset) + amp * off;
    p = 0.5 + (p - 0.5) * crop;

    vec3 c = cubic > 0.5 ? bspline(p) : texture(source, p).rgb;
    c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, saturation);
    // Треугольный шум: зерно стекла и заодно дизеринг. Поверх фона лежит вуаль, она ослабляет шум
    // втрое — поэтому 3/255: после вуали остаётся около одного уровня, и плавные тёмные переходы
    // не распадаются на полосы
    float n = hash(gl_FragCoord.xy) + hash(gl_FragCoord.xy + 71.7) - 1.0;
    c += n * (grain + 3.0 / 255.0);
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0) * qt_Opacity;
}
