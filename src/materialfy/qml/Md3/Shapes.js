.pragma library

// Полярные фигуры MD3 Expressive. Каждая фигура — функция радиуса r(θ) > 0.
// Морфинг = линейная интерполяция радиусов двух фигур в одних и тех же углах,
// поэтому любые две фигуры морфятся друг в друга без «перескоков» вершин.
//
// Описание фигуры: { kind, n, depth, p, rotation, blob }
//   circle                      — окружность
//   square  { p }               — суперэллипс (p≈5 — «скруглённый квадрат»)
//   cookie  { n, depth }        — синусоидальный зубчатый край (печенька)
//   flower  { n, depth, p }     — лепестки (|cos|^p заостряет впадины)
//   blob    { blob: [[k, amp, phase], ...] } — сумма гармоник, «живая» клякса
//   pill    { p, aspect }       — вытянутый суперэллипс

const TAU = Math.PI * 2

const presets = {
    circle: { kind: "circle" },
    square: { kind: "square", p: 5 },
    softSquare: { kind: "square", p: 3.2 },
    cookie4: { kind: "cookie", n: 4, depth: 0.12 },
    cookie6: { kind: "cookie", n: 6, depth: 0.1 },
    cookie7: { kind: "cookie", n: 7, depth: 0.09 },
    cookie9: { kind: "cookie", n: 9, depth: 0.075 },
    cookie12: { kind: "cookie", n: 12, depth: 0.055 },
    scallop: { kind: "cookie", n: 24, depth: 0.035 },
    clover4: { kind: "flower", n: 4, depth: 0.32, p: 0.7 },
    flower6: { kind: "flower", n: 6, depth: 0.28, p: 0.8 },
    flower8: { kind: "flower", n: 8, depth: 0.22, p: 0.9 },
    sunny: { kind: "flower", n: 8, depth: 0.12, p: 2.5 },
    blob: { kind: "blob", blob: [[2, 0.07, 0.3], [3, 0.06, 1.7], [5, 0.025, 4.1]] },
    puffy: { kind: "blob", blob: [[3, 0.05, 0.0], [5, 0.04, 2.0], [7, 0.02, 3.3]] }
}

function get(nameOrSpec) {
    if (typeof nameOrSpec === "string")
        return presets[nameOrSpec] || presets.circle
    return nameOrSpec || presets.circle
}

function radius(spec, theta, time) {
    const rot = spec.rotation || 0
    const t = theta - rot
    switch (spec.kind) {
    case "square": {
        const p = spec.p || 5
        const a = spec.aspect || 1
        const c = Math.pow(Math.abs(Math.cos(t)) / a, p)
        const s = Math.pow(Math.abs(Math.sin(t)), p)
        return Math.pow(c + s, -1 / p)
    }
    case "cookie": {
        const d = spec.depth || 0.08
        return 1 - d * (0.5 - 0.5 * Math.cos(spec.n * t))
    }
    case "flower": {
        const d = spec.depth || 0.25
        const p = spec.p || 1
        const w = Math.pow(Math.abs(Math.cos(spec.n * t / 2)), p)
        return 1 - d + d * w
    }
    case "blob": {
        let r = 1
        const harmonics = spec.blob || []
        for (let i = 0; i < harmonics.length; ++i) {
            const h = harmonics[i]
            r += h[1] * Math.cos(h[0] * t + h[2] + (time || 0) * (0.6 + 0.35 * i))
        }
        return r
    }
    default:
        return 1
    }
}

// Радиусы в N равномерных углах, нормированные так, чтобы фигура вписывалась в квадрат [-1, 1].
function sample(spec, n, time) {
    const out = new Array(n)
    let extent = 0
    for (let i = 0; i < n; ++i) {
        const th = TAU * i / n
        const r = radius(spec, th, time)
        out[i] = r
        extent = Math.max(extent, Math.abs(r * Math.cos(th)), Math.abs(r * Math.sin(th)))
    }
    for (let i = 0; i < n; ++i)
        out[i] /= extent
    return out
}

// Фигура может быть именем пресета, описанием или уже готовым массивом радиусов
// (так MorphShape «замораживает» промежуточную форму, если морф прервали посередине).
function radii(shape, n, time) {
    if (Array.isArray(shape) && shape.length === n)
        return shape
    return sample(get(shape), n, time)
}

function isLiving(shape) {
    return !Array.isArray(shape) && get(shape).kind === "blob"
}

function blend(a, b, t) {
    const out = new Array(a.length)
    for (let i = 0; i < a.length; ++i)
        out[i] = a[i] + (b[i] - a[i]) * t
    return out
}

// Точки контура для PathPolyline: морф from → to с прогрессом t, вращение rotation (рад).
// pulse (0..1) — «дыхание»: впадины углубляются, а сама фигура чуть расширяется (97 % → 100 %).
function outline(from, to, t, n, w, h, rotation, time, inset, pulse) {
    const a = radii(from, n, time)
    const b = t > 0 ? radii(to, n, time) : a
    const cx = w / 2, cy = h / 2
    const rx = w / 2 - (inset || 0), ry = h / 2 - (inset || 0)
    const pts = new Array(n + 1)
    for (let i = 0; i < n; ++i) {
        let r = a[i] + (b[i] - a[i]) * t
        if (pulse)
            r = (1 - (1 - r) * (1 + 2.2 * pulse)) * (0.97 + 0.03 * pulse)
        const th = TAU * i / n + (rotation || 0)
        pts[i] = Qt.point(cx + rx * r * Math.cos(th), cy + ry * r * Math.sin(th))
    }
    pts[n] = pts[0]
    return pts
}
