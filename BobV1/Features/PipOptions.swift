//
//  PipOptions.swift
//  PROTOTYPE (debug / launch selector, off by default): four candidate signature features for Pip that never touch the top of his head, so hats never
//  conflict. `-PipFeature A|B|C|D` (or PipOptions.current in captures); unset = the current small spikes, nothing changes for players.
//    A  dino tail: short chubby rounded tail at the lower back + three rounded orange plates along it (original spike size)
//    B  back ridge: original-style spikes, full size, shoulder line -> lower back, none on the head
//    C  lightning tail: short rounded zig-zag tail, soft corners
//    D  cheek bolts: two soft orange bolt marks on the cheeks (outside the mouth keep-out) + a tiny tail nub
//  Built procedurally from rounded primitives (spheres + tapered cones) in the feature-layer FeaturePrepared shape: rigid parts on bound pivots.
//

import simd
import Foundation

nonisolated enum PipOptions {
    nonisolated(unsafe) static var current: Character? = {
        guard let s = UserDefaults.standard.string(forKey: "PipFeature")?.uppercased(), let c = s.first, "ABCD".contains(c) else { return nil }
        return c
    }()

    struct Mesh {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = [], idx: [UInt32] = []
        mutating func sphere(_ c: SIMD3<Float>, _ r: Float, _ color: SIMD3<Float>) {
            let lat = 8, lon = 12, base = UInt32(pos.count)
            for i in 0...lat {
                let th = Float.pi * Float(i) / Float(lat)
                for j in 0..<lon {
                    let ph = 2 * Float.pi * Float(j) / Float(lon)
                    let n = SIMD3(sinf(th) * cosf(ph), cosf(th), sinf(th) * sinf(ph))
                    pos.append(c + n * r); nrm.append(n); col.append(color); ao.append(1)
                }
            }
            for i in 0..<lat { for j in 0..<lon {
                let a = base + UInt32(i * lon + j), b = base + UInt32(i * lon + (j + 1) % lon)
                let c2 = base + UInt32((i + 1) * lon + j), d = base + UInt32((i + 1) * lon + (j + 1) % lon)
                idx += [a, c2, b, b, c2, d]
            } }
        }
        mutating func cone(_ a: SIMD3<Float>, _ ra: Float, _ b: SIMD3<Float>, _ rb: Float, _ color: SIMD3<Float>) {
            let ax = b - a, L = simd_length(ax)
            guard L > 1e-5 else { return }
            let w = ax / L
            let u = simd_normalize(simd_cross(w, abs(w.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0))), v = simd_cross(w, u)
            let s = (ra - rb) / L, cs = 1 / (1 + s * s).squareRoot()
            let seg = 12, base = UInt32(pos.count)
            for k in 0..<2 { for j in 0..<seg {
                let ph = 2 * Float.pi * Float(j) / Float(seg)
                let rad = u * cosf(ph) + v * sinf(ph)
                let n = simd_normalize(rad * cs + w * (s * cs))
                pos.append((k == 0 ? a : b) + rad * (k == 0 ? ra : rb)); nrm.append(n); col.append(color); ao.append(1)
            } }
            for j in 0..<seg {
                let a0 = base + UInt32(j), a1 = base + UInt32((j + 1) % seg), b0 = a0 + UInt32(seg), b1 = a1 + UInt32(seg)
                idx += [a0, b0, a1, a1, b0, b1]
            }
        }
        /// A smooth plush tube: rings along `path` (radius `r[i]`), smooth analytic normals, closed with a hemispherical round tip. Path lies in the y-z plane.
        mutating func sweep(_ path: [SIMD3<Float>], _ r: [Float], _ color: SIMD3<Float>, seg: Int = 24, capRings: Int = 8, xs: Float = 1) {
            let n = path.count, base = UInt32(pos.count)
            let side = SIMD3<Float>(1, 0, 0)
            var rings = 0
            func ring(_ c: SIMD3<Float>, _ t: SIMD3<Float>, _ rad: Float, _ alpha: Float, cap: Bool, capC: Float = 1, capS: Float = 0) {
                let v = simd_normalize(simd_cross(t, side))
                for j in 0..<seg {
                    let ph = 2 * Float.pi * Float(j) / Float(seg)
                    let radial = side * cosf(ph) * xs + v * sinf(ph)                       // elliptical section (xs narrows the sides)
                    let radialN = side * cosf(ph) / xs + v * sinf(ph)
                    let nn: SIMD3<Float>, pp: SIMD3<Float>
                    if cap { nn = simd_normalize(radialN) * capC + t * capS; pp = c + radial * rad * capC + t * rad * capS }
                    else { let ca = cosf(alpha), sa = sinf(alpha); nn = simd_normalize(radialN) * ca + t * sa; pp = c + radial * rad }
                    pos.append(pp); nrm.append(simd_normalize(nn)); col.append(color); ao.append(1)
                }
                rings += 1
            }
            for i in 0..<n {
                let a = path[max(i - 1, 0)], b = path[min(i + 1, n - 1)]
                let t = simd_normalize(b - a)
                let dr = (r[min(i + 1, n - 1)] - r[max(i - 1, 0)]) / max(simd_length(b - a), 1e-5)
                ring(path[i], t, r[i], atanf(-dr), cap: false)
            }
            let tEnd = simd_normalize(path[n - 1] - path[n - 2])
            for k in 1...capRings {
                let th = Float.pi / 2 * Float(k) / Float(capRings)
                ring(path[n - 1], tEnd, r[n - 1], 0, cap: true, capC: cosf(th), capS: sinf(th))
            }
            for i in 0..<(rings - 1) { for j in 0..<seg {
                let a = base + UInt32(i * seg + j), b = base + UInt32(i * seg + (j + 1) % seg)
                let c = base + UInt32((i + 1) * seg + j), d = base + UInt32((i + 1) * seg + (j + 1) % seg)
                idx += [a, c, b, b, c, d]
            } }
        }
        /// A rounded tube through `pts` (radius `r[i]` at each): spheres at the joints, cones between.
        mutating func tube(_ pts: [SIMD3<Float>], _ r: [Float], _ color: SIMD3<Float>) {
            for i in 0..<pts.count { sphere(pts[i], r[i], color) }
            for i in 0..<(pts.count - 1) { cone(pts[i], r[i], pts[i + 1], r[i + 1], color) }
        }
        mutating func flatten(from first: Int, about p: SIMD3<Float>, axis n: SIMD3<Float>, k: Float) {
            for i in first..<pos.count {
                let d = pos[i] - p, h = simd_dot(d, n)
                pos[i] = p + (d - n * h) + n * (h * k)
                let nn = nrm[i], hn = simd_dot(nn, n)
                nrm[i] = simd_normalize((nn - n * hn) + n * (hn / k))
            }
        }
        /// A template spike of the shipped Pip art, moved so its sunk base is at `base` pointing along `normal`, scaled `s` about the base.
        mutating func spike(_ part: String, base: SIMD3<Float>, normal: SIMD3<Float>, scale s: Float, spec: FeatureSpec) {
            guard let art = FeatureMeshes.art("pip_c_final"), let p = art.parts.first(where: { $0.name == part }),
                  let sp = spec.spines.first(where: { $0.part == part }) else { return }
            let crown = SIMD3<Float>(0, spec.top, 0)
            let b0 = sp.base.v3, n0 = simd_normalize(sp.normal.v3) , piv = crown + sp.pivot.v3
            let q = simd_quatf(from: n0, to: simd_normalize(normal))
            let first = pos.count, off = UInt32(first)
            for k in 0..<p.positions.count {
                let local = (crown + p.positions[k]) - piv
                pos.append(base + q.act(local) * s - simd_normalize(normal) * 0)       // pivot (sunk base) lands on `base`
                nrm.append(q.act(p.normals[k])); col.append(p.colors[k]); ao.append(p.ao[k])
            }
            _ = b0; _ = first
            idx += p.indices.map { $0 + off }
        }
    }

    static let orangeFallback = SIMD3<Float>(0.8, 0.28, 0.05)

    /// Surface point + normal on the centre line at height y (back: z < 0; front: z > 0).
    static func centre(_ body: WearBody, y: Float, back: Bool) -> (p: SIMD3<Float>, n: SIMD3<Float>) {
        var best = -1, bz: Float = back ? .infinity : -.infinity
        for i in 0..<body.eggVertexLimit {
            let q = body.pos[i]
            guard abs(q.x) < 0.05, abs(q.y - y) < 0.04, back ? q.z < 0 : q.z > 0 else { continue }
            if back ? q.z < bz : q.z > bz { bz = q.z; best = i }
        }
        guard best >= 0 else { return (SIMD3(0, y, back ? -0.45 : 0.45), SIMD3(0, 0, back ? -1 : 1)) }
        return (body.pos[best], simd_normalize(body.nrm[best]))
    }
    static func front(_ body: WearBody, x: Float, y: Float) -> (p: SIMD3<Float>, n: SIMD3<Float>) {
        var best = -1, bd = Float.infinity
        for i in 0..<body.eggVertexLimit {
            let q = body.pos[i]
            guard q.z > 0.1 else { continue }
            let d = (q.x - x) * (q.x - x) + (q.y - y) * (q.y - y)
            if d < bd { bd = d; best = i }
        }
        return (body.pos[best], simd_normalize(body.nrm[best]))
    }

    static func build(_ opt: Character, body: WearBody, spec: FeatureSpec) -> FeaturePrepared {
        let r = FeaturePrepared(art: "pip_opt_\(opt)", key: "opt")
        let pal = JellyRoster.palette(1)
        let flesh = (pal?.flesh ?? SIMD3(0.95, 0.8, 0.2)) * 0.97 + SIMD3<Float>(repeating: 0.02)
        var ymin = Float.infinity, ymax = -Float.infinity
        for i in 0..<body.eggVertexLimit { ymin = min(ymin, body.pos[i].y); ymax = max(ymax, body.pos[i].y) }
        var orange = orangeFallback
        if let a = FeatureMeshes.art("pip_c_final"), let p = a.parts.first {
            var best = Float.infinity
            for c in p.colors { let s = c.x + c.y + c.z; if s < best { best = s; orange = c } }     // the deeper of the two tones
        }
        let h = ymax - ymin
        var m = Mesh()
        var pivotPoint = SIMD3<Float>.zero
        switch opt {
        case "A":
            // a plump kawaii comma: a very wide base (about half his height tall, centred at 30%) melting into the lower back, tapering quickly into a short
            // round tip that curls UP; 28% of the body width out from the surface. Three original head spikes (full size) stand along the top ridge.
            var xmin = Float.infinity, xmax = -Float.infinity
            for i in 0..<body.eggVertexLimit { xmin = min(xmin, body.pos[i].x); xmax = max(xmax, body.pos[i].x) }
            let width = xmax - xmin
            let root = centre(body, y: ymin + 0.30 * h, back: true)
            let o = root.p
            let sink: Float = 0.16, tipR: Float = 0.095
            let vis: Float = 0.28 * width - tipR                                  // surface -> tip-cap start
            let N = 16
            var path: [SIMD3<Float>] = [], rad: [Float] = []
            var cur = o + SIMD3(0, 0, sink)
            let ds = (sink + vis) / Float(N - 1)
            for i in 0..<N {
                let u = max(0, (Float(i) * ds - sink) / vis)                       // 0 at the surface, 1 at the tip
                path.append(cur)
                let ang = (6 + 38 * powf(u, 1.2)) * Float.pi / 180                // flat at the base, curling up to ~54 deg
                cur += SIMD3(0, sinf(ang), -cosf(ang)) * ds
                let uu = (Float(i) * ds) / (sink + vis)
                rad.append(tipR + (0.315 - tipR) * powf(1 - uu, 1.15))
            }
            m.sweep(path, rad, flesh * 0.92, xs: 0.82)
            let tailCount = m.pos.count
            // the ORIGINAL head spikes, full size, largest at the base, along the top ridge
            for (k, u) in [Float(0.0), 0.5, 0.92].enumerated() {
                let f = (sink + u * vis) / ds, i0 = min(Int(f), N - 2), fr = f - Float(i0)
                let c = path[i0] * (1 - fr) + path[i0 + 1] * fr
                let rr = rad[i0] * (1 - fr) + rad[i0 + 1] * fr
                let tan = simd_normalize(path[i0 + 1] - path[i0])
                var up = SIMD3<Float>(0, 1, 0); up -= tan * simd_dot(up, tan); up = simd_normalize(up)
                m.spike(["spike_00", "spike_02", "spike_03"][k], base: c + up * rr * 0.86, normal: simd_normalize(up + tan * 0.12), scale: 1.0, spec: spec)
            }
            // shading: the tail is lit with (mostly) the body's own surface normal at the join, so it reads as the same skin with no lighter band
            for i in 0..<tailCount {
                let d = simd_length(m.pos[i] - o)
                let w = 1 - min(max((d - 0.05) / 0.2, 0), 1)
                let soft = simd_normalize(m.nrm[i] * 0.4 + SIMD3<Float>(0, 0.85, 0.2) * 0.6)
                m.nrm[i] = simd_normalize(soft * (1 - 0.5 * w) + SIMD3<Float>(0, 0.85, 0.2) * 0.5 * w)
            }
            pivotPoint = o
        case "B":
            let n = 7
            for k in 0..<n {
                let t = Float(k) / Float(n - 1)
                let yy = ymin + (0.80 - 0.45 * t) * h                     // shoulder line -> lower back
                let c = centre(body, y: yy, back: true)
                m.spike("spike_03", base: c.p - c.n * 0.03, normal: c.n, scale: 1.45 - 0.5 * t, spec: spec)
            }
            pivotPoint = centre(body, y: ymin + 0.55 * h, back: true).p
        case "C":
            let root = centre(body, y: ymin + 0.38 * h, back: true)
            let o = root.p
            let pts = [o - root.n * 0.06, o + SIMD3(0.02, -0.0, -0.0) + SIMD3(0, 0.04, -0.14), o + SIMD3(0, 0.17, -0.07), o + SIMD3(0, 0.16, -0.25), o + SIMD3(0, 0.33, -0.17)]
            m.tube(pts, [0.10, 0.09, 0.085, 0.085, 0.12], flesh)
            pivotPoint = o
        default:
            let root = centre(body, y: ymin + 0.38 * h, back: true)
            m.sphere(root.p - root.n * 0.02, 0.07, flesh)
            m.sphere(root.p + SIMD3(0, 0.01, -0.06), 0.06, flesh)
            pivotPoint = root.p
        }
        _ = pivotPoint
        // D's cheek bolts: tangent-plane zig-zag strokes, flattened onto the skin
        var parts: [(String, Int, Int, SIMD3<Float>)] = []
        parts.append(("main", 0, m.pos.count, pivotPoint))
        if opt == "D" {
            for side: Float in [-1, 1] {
                let f = front(body, x: 0.36 * side, y: 0.60)
                let n = f.n
                let u = simd_normalize(simd_cross(SIMD3(0, 1, 0), n)), v = simd_cross(n, u)
                let c = f.p + n * 0.004
                let pt: [(Float, Float)] = [(0.022, 0.058), (-0.018, 0.008), (0.020, 0.004), (-0.020, -0.056)]
                let first = m.pos.count
                m.tube(pt.map { c + u * ($0.0 * side) + v * $0.1 }, [0.017, 0.017, 0.017, 0.017], orange)
                m.flatten(from: first, about: c, axis: n, k: 0.35)
                parts.append(("cheek", first, m.pos.count - first, c))
            }
        }
        // tail / ridge colours: spikes keep their art colours; flesh parts as given
        for (pi, pp) in parts.enumerated() {
            var pr = FeaturePrepared.Part(name: pp.0)
            pr.first = r.rest.count; pr.count = pp.2; pr.pivot = pp.3
            pr.bind = body.bind(pp.3) ?? SurfaceBind(); pr.side = pi
            for k in pp.1..<(pp.1 + pp.2) {
                r.rest.append(m.pos[k]); r.off.append(m.pos[k] - pp.3); r.nrm.append(m.nrm[k]); r.col.append(m.col[k]); r.ao.append(m.ao[k]); r.partOfVertex.append(pi)
            }
            r.parts.append(pr)
        }
        r.anchor = pivotPoint
        var t = 0
        // (triangles are index-global in m; each part's are contiguous with its vertices, so rebase)
        var starts: [Int] = parts.map { $0.1 }
        starts.append(m.pos.count)
        while t + 2 < m.idx.count {
            let i0 = m.idx[t], i1 = m.idx[t + 1], i2 = m.idx[t + 2]
            let g = simd_cross(m.pos[Int(i1)] - m.pos[Int(i0)], m.pos[Int(i2)] - m.pos[Int(i0)])
            let nn = m.nrm[Int(i0)] + m.nrm[Int(i1)] + m.nrm[Int(i2)]
            let a = UInt32(i0), b = UInt32(i1), c = UInt32(i2)
            if simd_dot(g, nn) >= 0 { r.idx += [a, b, c] } else { r.idx += [a, c, b] }
            t += 3
        }
        return r
    }
}
