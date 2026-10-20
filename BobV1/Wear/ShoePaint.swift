//
//  ShoePaint.swift
//  The artist's shoe paint specs (Resources/shoe_paint_spec.json, shoe_paint_spec_2.json) evaluated per vertex of the existing procedural shoe shell.
//  Geometry, thickness(u) and the (u, v, sx) coordinates are the shell's own (ShoeModel.style); this only decides each vertex's colour:
//    col = base; for each Tier A layer in order: col = mix(col, layer.colour, w(u) * w(v) * w(sx) * (bars | ellipse) * alpha)
//  with window w = rise(a - e, a + e, x) * (1 - rise(b - e, b + e, x)) (a or b nil = open). A layer colour "$body" is the Jelly's own body colour (the
//  foot shows through the ballet flats' opening). A `glow` layer also yields an emission weight for the light-up sneakers (the lamp material).
//  Tier B (laces, tongue, stitching, glitter dots) needs a denser shell and is NOT drawn: the twinkling diamonds of the glitter shoes stay.
//

import simd
import Foundation

nonisolated enum ShoePaint {
    struct Window {
        var a: Float?
        var b: Float?
        var e: Float
    }
    struct Bars { var v: [Float]; var hw: Float; var e: Float }
    struct Ell { var c: SIMD2<Float>; var r: SIMD2<Float>; var e: Float }
    struct Layer {
        var name = "", tier = "A"
        var colour: SIMD3<Float>? = nil            // linear; nil = "$body"
        var u: Window? = nil
        var v: Window? = nil
        var sx: Window? = nil
        var bars: Bars? = nil
        var ellipse: Ell? = nil
        var alpha: Float = 1
        var glow = false
        var speckle: (f1: Float, density: Float)? = nil
    }
    struct Style { var name = ""; var base = SIMD3<Float>.zero; var layers: [Layer] = [] }

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / max(b - a, 1e-6), 0), 1); return t * t * (3 - 2 * t) }
    private static func win(_ w: Window?, _ x: Float) -> Float {
        guard let w else { return 1 }
        var r: Float = 1
        if let a = w.a { r *= smooth(a - w.e, a + w.e, x) }
        if let b = w.b { r *= 1 - smooth(b - w.e, b + w.e, x) }
        return r
    }

    private static func parseWindow(_ any: Any?) -> Window? {
        guard let arr = any as? [Any], arr.count == 3 else { return nil }
        return Window(a: (arr[0] as? NSNumber)?.floatValue, b: (arr[1] as? NSNumber)?.floatValue, e: (arr[2] as? NSNumber)?.floatValue ?? 0.03)
    }
    private static func rgb(_ any: Any?) -> SIMD3<Float>? {
        guard let a = any as? [Double], a.count == 3 else { return nil }
        return OKLab.srgbToLinear(SIMD3(Float(a[0]), Float(a[1]), Float(a[2])))
    }

    /// Every style of both spec files by its spec key ("sneaker_mint", "hightop_red", ...).
    static let styles: [String: Style] = {
        var out: [String: Style] = [:]
        for file in ["shoe_paint_spec", "shoe_paint_spec_2"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "json") ?? Bundle(for: Token.self).url(forResource: file, withExtension: "json"),
                  let d = try? Data(contentsOf: url), let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let st = root["styles"] as? [String: Any] else { continue }
            for (key, any) in st {
                guard let s = any as? [String: Any], let base = rgb(s["base"]) else { continue }
                var style = Style(name: (s["name"] as? String) ?? key, base: base)
                for l in (s["layers"] as? [[String: Any]]) ?? [] {
                    var layer = Layer()
                    layer.name = (l["name"] as? String) ?? ""
                    layer.tier = (l["tier"] as? String) ?? "A"
                    layer.colour = (l["colour"] as? String) == "$body" ? nil : rgb(l["colour"])
                    layer.u = parseWindow(l["u"]); layer.v = parseWindow(l["v"]); layer.sx = parseWindow(l["sx"])
                    layer.alpha = (l["alpha"] as? NSNumber)?.floatValue ?? 1
                    layer.glow = (l["glow"] as? Bool) ?? false
                    if let sp = l["speckle"] as? [String: Any] { layer.speckle = (Float((sp["f1"] as? Double) ?? 157.3), Float((sp["density"] as? Double) ?? 0.14)) }
                    if let b = l["bars"] as? [String: Any], let vs = b["v"] as? [Double] {
                        layer.bars = Bars(v: vs.map { Float($0) }, hw: Float((b["hw"] as? Double) ?? 0.02), e: Float((b["e"] as? Double) ?? 0.015))
                    }
                    if let e = l["ellipse"] as? [String: Any], let c = e["c"] as? [Double], let r = e["r"] as? [Double] {
                        layer.ellipse = Ell(c: SIMD2(Float(c[0]), Float(c[1])), r: SIMD2(Float(r[0]), Float(r[1])), e: Float((e["e"] as? Double) ?? 0.3))
                    }
                    style.layers.append(layer)
                }
                out[key] = style
            }
        }
        return out
    }()
    private final class Token {}

    static func style(_ look: WearLook) -> Style? { styles[look.row.paintStyle] }

    /// Weight of one layer at (u, v, sx). `sharp` < 1 narrows every soft edge (the flat-shaded shell wants hard bands).
    static func weight(_ L: Layer, u: Float, v: Float, sx: Float, sharp: Float = 1) -> Float {
        func sw(_ x: Window?) -> Window? { x.map { Window(a: $0.a, b: $0.b, e: $0.e * sharp) } }
        var w = win(sw(L.u), u) * win(sw(L.v), v) * win(sw(L.sx), sx) * L.alpha
        if let b = L.bars {
            var m: Float = 0
            for c in b.v { m = max(m, 1 - smooth(b.hw - b.e, b.hw + b.e, abs(v - c))) }
            w *= m
        }
        if let e = L.ellipse {
            let dv = (v - e.c.x) / e.r.x, ds = (sx - e.c.y) / e.r.y
            w *= 1 - smooth(1 - e.e, 1, (dv * dv + ds * ds).squareRoot())
        }
        return w
    }

    /// Colour of every vertex of the subdivided shell (ShoeModel.sub: the bean vertices, then the edge midpoints), with hard-edged windows (Tier A and Tier B:
    /// laces, tongue, stitching, glitter dots): at twice the old resolution a band edge now crosses ONE small triangle, so it reads crisp and stays smooth-edged.
    static func paintVertices(_ look: WearLook, body: SIMD3<Float>) -> (col: [SIMD3<Float>], glow: [Float]) {
        let key = "V\(look.rawValue)-\(Int(body.x * 255))-\(Int(body.y * 255))-\(Int(body.z * 255))"
        lock.lock(); if let c = cache[key] { lock.unlock(); return c }; lock.unlock()
        let sb = ShoeModel.sub
        var col = [SIMD3<Float>](), glow = [Float]()
        let sty = style(look)
        for i in 0..<sb.vu.count {
            let u = sb.vu[i], v = sb.vv[i], sx = sb.vs[i]
            var c = sty?.base ?? SIMD3<Float>(0.7, 0.7, 0.7), g: Float = 0
            for var L in sty?.layers ?? [] {
                // the body hides most of the foot, so the toe is what shows: keep the toe cap a cap (a lighter rounded tip), not the whole visible foot
                if L.name.hasPrefix("toe_cap"), !L.name.contains("stitch"), let a = L.v?.a, a < 0.9 { L.v?.a = a + 0.07 }
                var w = weight(L, u: u, v: v, sx: sx, sharp: 0.5)
                if let sp = L.speckle {            // glitter dots: hashed, on the layer's window
                    let h = sinf(u * sp.f1 + v * 91.7 + sx * 37.1) * 43758.5453
                    w *= (h - floorf(h)) >= 1 - sp.density ? 1 : 0
                }
                w = w < 0.5 && L.alpha >= 0.99 ? 0 : (w > 0.5 && L.alpha >= 0.99 ? 1 : w)           // opaque layers: a hard edge
                guard w > 0 else { continue }
                c += ((L.colour ?? body) - c) * min(w, 1)
                if L.glow { g = max(g, w) } else { g *= 1 - min(w, 1) }
            }
            col.append(c); glow.append(g)
        }
        lock.lock(); cache[key] = (col, glow); lock.unlock()
        return (col, glow)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (col: [SIMD3<Float>], glow: [Float])] = [:]

    /// The colour of every shell vertex (418) and the glow weight of the glow layers, for a Jelly whose body colour is `body` (linear). Cached per look and body.
    static func paint(_ look: WearLook, body: SIMD3<Float>) -> (col: [SIMD3<Float>], glow: [Float]) {
        let key = "\(look.rawValue)-\(Int(body.x * 255))-\(Int(body.y * 255))-\(Int(body.z * 255))"
        lock.lock(); if let c = cache[key] { lock.unlock(); return c }; lock.unlock()
        let st = ShoeModel.style
        var col = [SIMD3<Float>](), glow = [Float]()
        let sty = style(look)
        for i in st.u.indices {
            var c = sty?.base ?? SIMD3<Float>(0.7, 0.7, 0.7), g: Float = 0
            for L in sty?.layers ?? [] where L.tier == "A" {
                let w = weight(L, u: st.u[i], v: st.v[i], sx: st.sx[i])
                guard w > 0 else { continue }
                c += ((L.colour ?? body) - c) * min(w, 1)
                if L.glow { g = max(g, w) } else { g *= 1 - min(w, 1) }
            }
            col.append(c); glow.append(g)
        }
        lock.lock(); cache[key] = (col, glow); lock.unlock()
        return (col, glow)
    }

    /// The named layer's colour (the shell palette the tests and thumbnails speak of).
    static func layerColour(_ look: WearLook, _ name: String) -> SIMD3<Float>? {
        style(look)?.layers.first { $0.name.hasPrefix(name) }?.colour
    }
}
