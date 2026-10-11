.pragma library

// Смешивание цветов в OKLab: перцептивно ровный переход без «грязных» середин (как бывает в sRGB).

function _toLinear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
function _toSrgb(c) {
    c = Math.max(0, Math.min(1, c))
    return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055
}

// color (QColor/Qt.rgba) → [L, a, b, alpha]
function toLab(color) {
    const r = _toLinear(color.r), g = _toLinear(color.g), b = _toLinear(color.b)
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return [
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
        color.a
    ]
}

function fromLab(L, A, B, alpha) {
    const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
    const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
    const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
    return Qt.rgba(
        _toSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        _toSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        _toSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
        alpha)
}

function mix(a, b, t) {
    if (t >= 1) return fromLab(b[0], b[1], b[2], b[3])
    return fromLab(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                   a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t)
}

// {роль: color} → {роль: lab}
function labMap(colors) {
    const out = {}
    for (const k in colors)
        out[k] = toLab(colors[k])
    return out
}
