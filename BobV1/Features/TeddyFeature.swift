//
//  TeddyFeature.swift
//  Teddy (character 4, JellyFeature.ears): Bob's identical body in light brown with a lighter belly (the blue-belly shader patch, ported: BlueBelly.swift),
//  plus ONE signature feature made of two kinds of part: two round bear EARS near the top of the head (slightly back, outward; each a half-sunk
//  rounded lobe with a lighter inner cup) and a small round puffy POM tail on the lower back. Nothing here reshapes the base body: every part is its own
//  little mesh, bound to the rest egg surface like the daisy / spikes (FeatureMeshes: pivot = the surface point it grows from, so it follows the skin),
//  built in code (no .bin) and drawn through the same feature pipeline (FeatureSet / FeatureMeshes.emit).
//
//  HAT RULE (TeddyFit.solve, computed from the real wardrobe geometry, nothing hand-listed per hat except the ear headbands):
//    1. an ear that clears the worn hat stays where it is (perching and open pieces: bows, flower clips, visor, sweatband, headphones, party / witch / chef / top hats ...)
//    2. an ear the hat would clip SLIDES down the side of the head, rim-side, until it pokes out below the hat's edge (the usual "ears out from under the
//       beanie" look), if a clear spot within the sliding range exists
//    3. otherwise it tucks away (shrinks onto its base, as Pip's covered spikes do) and comes back when the hat comes off
//    4. the ear headbands (cat / frog / bunny ears) are ears themselves: the bear ears tuck
//  The pom tucks under any worn piece that covers the lower back (cape, backpack, tutu, vest, cardigan ...), measured the same way.
//
//  Colours are linear RGB for the vertex stream; the tones are the three light-brown options shown to the user (TeddyLook).
//

import simd
import Foundation

nonisolated enum TeddyLook {
    struct Tone: Sendable {
        let name: String
        /// The lit body tone (the palette's `flesh`, the same units as the other species' palettes).
        let flesh: SIMD3<Float>
        let deep: SIMD3<Float>
        /// The sRGB colour the matte body shader actually DRAWS for this flesh in the lit room (measured from the real render: it lifts the tone a lot);
        /// the ears and the pom are vertex-coloured, so they are painted from this to read as the same fur.
        var drawn: SIMD3<Float>
        init(name: String, flesh: SIMD3<Float>, deep: SIMD3<Float>, drawn: SIMD3<Float>? = nil) { self.name = name; self.flesh = flesh; self.deep = deep; self.drawn = drawn ?? flesh }
        var palette: Palette {
            let unused = SIMD3<Float>(0.5, 0.5, 0.5)
            return JellyPalettes.matte(Palette(name: "Teddy " + name, flesh: flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                               shadowTint: flesh * 0.62, uiFlesh: flesh))
        }
    }
    /// Three light browns, named by what the matte shader DRAWS in the lit room (measured; `flesh` is the palette value that produces it): the eyes (#3A2620) stay readable on all three.
    static let tones: [Tone] = [
        Tone(name: "Honey", flesh: SIMD3(0.68, 0.42, 0.20), deep: SIMD3(0.50, 0.31, 0.15), drawn: srgb(0xD6, 0xAC, 0x7B)),
        Tone(name: "Caramel", flesh: SIMD3(0.60, 0.34, 0.14), deep: SIMD3(0.44, 0.25, 0.10), drawn: srgb(0xCB, 0x9C, 0x60)),
        Tone(name: "Toffee", flesh: SIMD3(0.50, 0.26, 0.10), deep: SIMD3(0.37, 0.19, 0.07), drawn: srgb(0xBB, 0x8B, 0x58)),
    ]
    static func srgb(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> { SIMD3(Float(r), Float(g), Float(b)) / 255 }
    /// The tone in force (Honey by default; `-TeddyTone 0|1|2` for captures, any build).
    nonisolated(unsafe) static var current: Tone = launchValue
    static let launchValue: Tone = {
        let i = UserDefaults.standard.object(forKey: "TeddyTone") != nil ? UserDefaults.standard.integer(forKey: "TeddyTone") : 0
        return tones[min(max(i, 0), tones.count - 1)]
    }()
    /// Linear colours (vertex stream): the ear's outer lobe = the drawn body colour; the inner cup a touch deeper and warmer (as in the reference, where the cup is the
    /// deeper tone of the ear); the pom the belly's warm cream.
    /// The ears / pom are vertex-coloured and lit by the room's plain shader, the body by the matte fur shader: `earGain` (per channel, calibrated by
    /// TeddyCalibrateTests.testTeddyEarMatch against the body pixels next to the ear) makes the ear DRAW as the same colour as the body.
    nonisolated(unsafe) static var earGain = SIMD3<Float>(0.875, 0.92, 0.97)
    static func tuned(_ c: SIMD3<Float>) -> SIMD3<Float> { OKLab.srgbToLinear(simd_clamp(c * earGain, SIMD3(repeating: 0), SIMD3(repeating: 1))) }
    static func earOuter(_ t: Tone = current) -> SIMD3<Float> { tuned(t.drawn) }
    /// The cup: only a touch deeper than the body (a soft shallow dish).
    static func earInner(_ t: Tone = current) -> SIMD3<Float> { tuned(t.drawn * SIMD3(0.90, 0.85, 0.80)) }
    static func pomColor(_ t: Tone = current) -> SIMD3<Float> {
        let cream = SIMD3<Float>(1.0, 0.93, 0.78)
        return tuned(simd_clamp(t.drawn + (cream - t.drawn) * 0.35, SIMD3(repeating: 0), SIMD3(repeating: 1)) * 1.04)
    }
}

nonisolated enum TeddyMesh {
    // MARK: the design numbers (rest space: y up, +z = the face)

    /// The RIGHT (+x) ear, matched to the reference (revision 2): an upright round disc standing vertically and FACING FORWARD at the top corner of the head, its centre
    /// on the head's outline as seen from the front (so the head overlaps its lower inner third), slightly behind the centre plane. `earHome` = its centre (rest space);
    /// `earFace` = the direction the disc faces (the cup side); `earRoll` = the point the ears slide about (down the side of the head) under a hat.
    nonisolated(unsafe) static var earHome = SIMD3<Float>(0.391, 1.217, 0.02)
    nonisolated(unsafe) static var earFace = SIMD3<Float>(0.22, 0.12, 1.0)
    static let earRoll = SIMD2<Float>(0, 0.85)
    nonisolated(unsafe) static var earRadius: Float = 0.156
    nonisolated(unsafe) static var earThick: Float = 0.72, cupRadius: Float = 0.62, cupDepth: Float = 0.22
    /// The pom: a ball on the lower back centre line.
    static let pomRadius: Float = 0.118, pomY: Float = 0.50, pomEmbed: Float = 0.30, pomFluff: Float = 0.035

    static let plushWrap: Float = 0.45
    static let segments = 20, rings = 14, pomSegments = 20, pomRings = 12

    // MARK: surface helpers (BobForm.bodySDF, the egg)

    static func surface(from c: SIMD3<Float>, dir: SIMD3<Float>) -> (p: SIMD3<Float>, n: SIMD3<Float>) {
        let d = SIMD3<Double>(Double(dir.x), Double(dir.y), Double(dir.z)), o = SIMD3<Double>(Double(c.x), Double(c.y), Double(c.z))
        var lo = 0.05, hi = 2.5
        for _ in 0..<48 { let m = 0.5 * (lo + hi); if BobForm.bodySDF(o + d * m) < 0 { lo = m } else { hi = m } }
        let p = o + d * lo, e = 0.0015
        let g = SIMD3(BobForm.bodySDF(p + SIMD3(e, 0, 0)) - BobForm.bodySDF(p - SIMD3(e, 0, 0)),
                      BobForm.bodySDF(p + SIMD3(0, e, 0)) - BobForm.bodySDF(p - SIMD3(0, e, 0)),
                      BobForm.bodySDF(p + SIMD3(0, 0, e)) - BobForm.bodySDF(p - SIMD3(0, 0, e)))
        let n = simd_length(g) > 1e-12 ? g / simd_length(g) : SIMD3(0, 1, 0)
        return (SIMD3(Float(p.x), Float(p.y), Float(p.z)), SIMD3(Float(n.x), Float(n.y), Float(n.z)))
    }

    /// The right ear's centre and facing, `slide` degrees round the head's side (positive = down and out, negative = in and up) about `earRoll`.
    static func earSpot(slide: Float) -> (p: SIMD3<Float>, w: SIMD3<Float>) {
        let th = slide * .pi / 180
        func roll(_ x: Float, _ y: Float) -> (Float, Float) { (x * cosf(th) + y * sinf(th), -x * sinf(th) + y * cosf(th)) }
        let d = earHome - SIMD3(earRoll.x, earRoll.y, 0)
        let (x, y) = roll(d.x, d.y)
        return (SIMD3(earRoll.x + x, earRoll.y + y, earHome.z), simd_normalize(earFace))
    }
    static func pomSpot() -> (p: SIMD3<Float>, n: SIMD3<Float>) { surface(from: SIMD3(0, pomY, 0), dir: SIMD3(0, 0, -1)) }

    // MARK: one lobe (an ellipsoid of revolution about its facing axis, with an optional cup in its front)

    struct Lobe {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = [], idx: [UInt32] = []
    }

    /// Frame: `w` = the facing axis (the cup looks along it), centre, radius `r` across and `h` along w. `cup` = (radius fraction, depth fraction of h) or nil.
    static func lobe(centre: SIMD3<Float>, w: SIMD3<Float>, up: SIMD3<Float>, r: Float, h: Float, cup: (rho: Float, depth: Float)?, outer: SIMD3<Float>, inner: SIMD3<Float>,
                     segs: Int, rings nr: Int, aoBack: Float, fluff: Float = 0) -> Lobe {
        var L = Lobe()
        let e1 = simd_normalize(simd_cross(up, w)), e2 = simd_cross(w, e1)
        for i in 0...nr {
            let th = Float.pi * Float(i) / Float(nr)
            let st = sinf(th), ct = cosf(th)
            for j in 0..<segs {
                let ph = 2 * Float.pi * Float(j) / Float(segs)
                let cx = cosf(ph), cy = sinf(ph)
                // a soft puffy surface: low lumps (fluff) in the radius
                let fl = 1 + fluff * sinf(5 * th) * cosf(3 * ph + 1.1)
                var lw = h * ct * fl
                var tint: Float = 0
                var ao: Float = 1
                if let c = cup, ct > 0 {
                    // a bowl in the front: rho = distance from the facing axis (as a fraction of r); smooth lip, soft floor
                    let rho = st / c.rho
                    if rho < 1 { let b = (1 - rho * rho); lw -= h * c.depth * b * b }
                    tint = 1 - smoothstep(0.86, 1.06, rho)
                    ao = 1 - 0.14 * (1 - smoothstep(0, 1, rho))
                }
                if ct < 0 { ao = 1 - (1 - aoBack) * min(1, -ct * 1.6) }            // the half sunk into the head
                L.pos.append(centre + e1 * (r * fl * st * cx) + e2 * (r * fl * st * cy) + w * lw)
                L.nrm.append(w)         // replaced by the smoothed face normals below
                L.col.append(outer + (inner - outer) * tint)
                L.ao.append(ao)
            }
        }
        for i in 0..<nr {
            for j in 0..<segs {
                let a = UInt32(i * segs + j), b = UInt32(i * segs + (j + 1) % segs)
                let c = UInt32((i + 1) * segs + j), d = UInt32((i + 1) * segs + (j + 1) % segs)
                if i > 0 { L.idx += [a, c, b] }                     // winding is fixed up against the normals in the build
                if i < nr - 1 { L.idx += [b, c, d] }
            }
        }
        smoothNormals(&L, centre: centre)
        // the two poles are rings of coincident vertices with different face fans: give each the mean normal of the ring next to it (no pinched shading)
        for (pole, next) in [(0, 1), (nr, nr - 1)] {
            var m = SIMD3<Float>.zero
            for j in 0..<segs { m += L.nrm[next * segs + j] }
            let nn = simd_length(m) > 1e-9 ? simd_normalize(m) : w
            for j in 0..<segs { L.nrm[pole * segs + j] = nn }
        }
        // soft plush lighting: lean every normal toward a fixed "up and forward" so the back / underside of a lobe is not much darker than the matte body next to it
        for k in 0..<L.nrm.count { L.nrm[k] = simd_normalize(L.nrm[k] * (1 - plushWrap) + SIMD3<Float>(0, 0.6, 0.8) * plushWrap) }
        return L
    }
    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }

    /// Area-weighted vertex normals, facing away from `centre` overall (the triangle winding is made to agree).
    static func smoothNormals(_ L: inout Lobe, centre: SIMD3<Float>) {
        var acc = [SIMD3<Float>](repeating: .zero, count: L.pos.count)
        var t = 0
        while t + 2 < L.idx.count {
            let i0 = Int(L.idx[t]), i1 = Int(L.idx[t + 1]), i2 = Int(L.idx[t + 2])
            var g = simd_cross(L.pos[i1] - L.pos[i0], L.pos[i2] - L.pos[i0])
            let mid = (L.pos[i0] + L.pos[i1] + L.pos[i2]) / 3 - centre
            if simd_dot(g, mid) < 0 { g = -g; L.idx.swapAt(t + 1, t + 2) }
            for i in [i0, i1, i2] { acc[i] += g }
            t += 3
        }
        // the segment seam / poles: average with the vertices at the same place
        for k in 0..<acc.count { let l = simd_length(acc[k]); L.nrm[k] = l > 1e-12 ? acc[k] / l : simd_normalize(L.pos[k] - centre) }
    }

    // MARK: the whole feature

    static func ear(slide: Float, left: Bool, tone: TeddyLook.Tone) -> (lobe: Lobe, pivot: SIMD3<Float>) {
        var (c, w) = earSpot(slide: slide)
        if left { c.x = -c.x; w.x = -w.x }
        let L = lobe(centre: c, w: w, up: SIMD3(0, 1, 0), r: earRadius, h: earRadius * earThick, cup: (cupRadius, cupDepth), outer: TeddyLook.earOuter(tone), inner: TeddyLook.earInner(tone),
                     segs: segments, rings: rings, aoBack: 0.8, fluff: 0)
        return (L, c)
    }
    static func pom(tone: TeddyLook.Tone) -> (lobe: Lobe, pivot: SIMD3<Float>) {
        let (p, n) = pomSpot()
        let centre = p + n * (pomEmbed * pomRadius)
        let L = lobe(centre: centre, w: SIMD3(0, 0, -1), up: SIMD3(0, 1, 0), r: pomRadius, h: pomRadius, cup: nil, outer: TeddyLook.pomColor(tone), inner: TeddyLook.pomColor(tone),
                     segs: pomSegments, rings: pomRings, aoBack: 0.7, fluff: pomFluff)
        return (L, p)
    }

    static let partNames = ["ear_r", "ear_l", "pom"]

    nonisolated(unsafe) private static var cache: [String: FeaturePrepared] = [:]
    private static let lock = NSLock()
    static func clearCache() { lock.lock(); cache = [:]; lock.unlock() }

    /// The prepared feature (cached per slide and tone): parts ear_r (side 0), ear_l (side 1), pom, each pivoting on the egg surface point it grows from.
    static func prepare(slide: Float, body: WearBody, tone: TeddyLook.Tone = TeddyLook.current) -> FeaturePrepared {
        let key = String(format: "teddy|slide:%.1f|%@", slide, tone.name)
        lock.lock(); let c = cache[key]; lock.unlock()
        if let c { return c }
        let r = FeaturePrepared(art: "teddy", key: key)
        r.anchor = SIMD3(0, 1.0, 0)
        let built = [ear(slide: slide, left: false, tone: tone), ear(slide: slide, left: true, tone: tone), pom(tone: tone)]
        for (i, b) in built.enumerated() {
            var part = FeaturePrepared.Part(name: partNames[i])
            part.first = r.rest.count; part.count = b.lobe.pos.count
            part.pivot = b.pivot; part.bind = body.bind(b.pivot) ?? SurfaceBind(); part.side = i == 1 ? 1 : 0
            for k in 0..<b.lobe.pos.count {
                r.rest.append(b.lobe.pos[k]); r.off.append(b.lobe.pos[k] - b.pivot); r.nrm.append(b.lobe.nrm[k]); r.col.append(b.lobe.col[k]); r.ao.append(b.lobe.ao[k]); r.partOfVertex.append(i)
            }
            let base = UInt32(part.first)
            r.idx += b.lobe.idx.map { $0 + base }
            r.parts.append(part)
        }
        lock.lock(); cache[key] = r; lock.unlock()
        return r
    }
}

// MARK: - the hat rule

nonisolated struct TeddyFitResult: Equatable, Sendable {
    /// Degrees the ears slide down the side of the head (0 = home).
    var slide: Float = 0
    var earsHidden = false
    var pomHidden = false
}

nonisolated enum TeddyFit {
    /// Ear headbands: they ARE ears, so the bear ears tuck under them.
    static let earBands: Set<String> = ["cat_ears", "frog_ears", "bunny_ears"]
    /// How far an ear must stay from a hat's surface, and how far the hat may rise / widen at run time (CrownFit lifts it to the drawn skin).
    static let clearance: Float = 0.035
    /// Open pieces (bands, crowns, visors, bows) are carried rigidly while the skin wobbles under them (only enclosing hats are re-seated on the skin every frame): more room.
    static let bandClearance: Float = 0.070
    /// What CrownFit may do to a hat in motion (it follows the drawn skin): widen it about the body axis and lift it. The rule clears the hat in all four of those states.
    static let motionWiden: Float = 1.10, motionLift: Float = 0.05
    /// The slide search: the lowest the ear may go is 54 deg more than home (beyond that it meets the cheek / eye zone).
    /// Slides tried in order (the smallest move first): a little further round the head, or inward toward the crown (negative), up to the cheek line.
    static let slideOrder: [Float] = [6, -6, 12, -12, 18, -18, 24, 30, 36, 42, 48, 54]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: TeddyFitResult] = [:]
    static func clearCache() { lock.lock(); cache = [:]; lock.unlock() }

    /// Points on the surface of a worn piece (rest space), dense enough (about 2 cm) for a clearance test.
    static func surfacePoints(_ p: WearPrepared) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = p.rest
        var t = 0
        while t + 2 < p.idx.count {
            let a = p.rest[Int(p.idx[t])], b = p.rest[Int(p.idx[t + 1])], c = p.rest[Int(p.idx[t + 2])]
            let ext = max(simd_distance(a, b), simd_distance(b, c), simd_distance(a, c))
            let n = Int((ext / 0.02).rounded(.up))
            if n > 1 { for i in 0...n { for j in 0...(n - i) {
                let u = Float(i) / Float(n), v = Float(j) / Float(n)
                out.append(a * (1 - u - v) + b * u + c * v)
            } } }
            t += 3
        }
        return out
    }

    /// Does `pts` (a part's rest vertices) touch the piece: inside an enclosing crown, or within `clearance` of its surface?
    static func clips(_ pts: [SIMD3<Float>], piece: WearPrepared, cloud: [SIMD3<Float>], margin: Float = clearance) -> Bool {
        let m2 = margin * margin
        for q in pts {
            if piece.crownEnclosing, q.y > 0.55 {
                for k in [Float(1), motionWiden] { if let h = CrownFit.height(piece.crown, q.x / k, q.z / k), q.y < h + motionLift + margin * 0.5 { return true } }
            }
        }
        // the surface test, on only the cloud points near the ears' box (the clouds are big and this runs on the main thread when a hat goes on)
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for q in pts { lo = simd_min(lo, q); hi = simd_max(hi, q) }
        lo -= margin; hi += margin
        let near = cloud.filter { all($0 .>= lo) && all($0 .<= hi) }
        if near.isEmpty { return false }
        for q in pts { for c in near where simd_distance_squared(q, c) < m2 { return true } }
        return false
    }

    /// What the Teddy's ears and pom do under what he wears (`worn` = the shown art ids).
    static func solve(worn: [String], tone: TeddyLook.Tone = TeddyLook.current) -> TeddyFitResult {
        let key = worn.sorted().joined(separator: ",")
        lock.lock(); let c = cache[key]; lock.unlock()
        if let c { return c }
        var r = TeddyFitResult()
        let body = WearBody.shared
        var hats: [(WearPrepared, [SIMD3<Float>], Float)] = []
        var backLooks: [(WearLook, WearPrepared)] = []
        for w in worn {
            if earBands.contains(w) { r.earsHidden = true }
            guard let look = WearLook.pieces.first(where: { $0.art == w }), let piece = WearMeshes.prepare(look, body: body) else { continue }
            switch look.slot {
            case .head:
                let pts = surfacePoints(piece)
                var all = pts
                for (k, dy) in [(Float(1), motionLift), (motionWiden, Float(0)), (motionWiden, motionLift)] { all += pts.map { SIMD3($0.x * k, $0.y + dy, $0.z * k) } }
                hats.append((piece, all, piece.crownEnclosing ? clearance : bandClearance))
            case .neck, .body: backLooks.append((look, piece))
            default: break
            }
        }
        if !r.earsHidden && !hats.isEmpty {
            func earClips(_ slide: Float) -> Bool {
                let pts = (0..<2).flatMap { side in TeddyMesh.ear(slide: slide, left: side == 1, tone: tone).lobe.pos.enumerated().filter { $0.offset % 3 == 0 }.map(\.element) }
                return hats.contains { clips(pts, piece: $0.0, cloud: $0.1, margin: $0.2) }
            }
            if earClips(0) {
                var found: Float? = nil
                for s in Self.slideOrder { if !earClips(s) { found = s; break } }
                if let f = found { r.slide = f } else { r.earsHidden = true }
            }
        }
        // the pom: any worn piece with a back surface point within the pom's reach (centre + radius + a margin) tucks it
        let (pp, pn) = TeddyMesh.pomSpot()
        let pc = pp + pn * (TeddyMesh.pomEmbed * TeddyMesh.pomRadius), reach = TeddyMesh.pomRadius + 0.03
        for (look, piece) in backLooks {
            _ = look
            if surfacePoints(piece).contains(where: { simd_distance_squared($0, pc) < reach * reach }) { r.pomHidden = true; break }
        }
        lock.lock(); cache[key] = r; lock.unlock()
        return r
    }
}

