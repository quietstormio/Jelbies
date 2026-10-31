//
//  TeddyBean.swift
//  Teddy's two bear ears and the puffy pom tail, grown out of the BODY render mesh exactly like Pip's tail (TailBean): one block of body vertices appended after
//  the tail block (still in the body index range, so the body skin shader draws it: the same palette, fuzz, crinkle and lighting, no seam, no feature
//  pipeline). The block is collapsed onto each part's pole (zero-area, invisible) for every Jelly but Teddy and while a part is tucked (hat rule); for Teddy
//  each part rides the head / back rigidly on the frame of three landmark egg vertices (Skinner.applyTeddy), and the egg's own vertices around its root are
//  pushed out along the egg normal onto a true rolling-ball smooth-union fillet (TeddyBean.swell, the same `blend` maths as the shipped Pip back), so the head
//  flows up into the ear as one surface: no crease, no colour or shading step.
//
//  EAR (rest units; head top ~ y 1.35): a flattish "D" plate, wider than tall, with a fully rounded rim, a shallow inner hollow that runs OUT at the root (so the
//  raised rim is an arch over the top and sides, never a ring), a smooth convex back, the lower half buried in the head. Its face looks forward and a little out.
//  The hollow is the belly's cream (`cream`), the body fur (`fur`), or the old feature-pipeline lobes are drawn instead (`old`): TEDDYEARS env / DEBUG -TeddyEars.
//  POM: a round ball (an icosphere-free cube sphere: no pole to pinch) filleted into the lower back.
//

import Foundation
import simd

/// Which Teddy ears are drawn. Default `cream`; the TEDDYEARS environment variable (tests) or, in DEBUG builds, the `-TeddyEars cream|fur|old` launch argument picks another.
/// Tests may assign `active` between renders (a new Renderer picks the mask up; the Skinner / FeatureSet read it every tick).
nonisolated enum TeddyEarsVariant: String {
    case cream, fur, old
    nonisolated(unsafe) static var active: TeddyEarsVariant = launchValue
    static let launchValue: TeddyEarsVariant = {
        if let s = ProcessInfo.processInfo.environment["TEDDYEARS"], let v = TeddyEarsVariant(rawValue: s.lowercased()) { return v }
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "TeddyEars"), let v = TeddyEarsVariant(rawValue: s.lowercased()) { return v }
        #endif
        return .cream
    }()
    /// The pom's colour: the belly's cream (`true`, the default: it reads as a pom; the fur one is just a bulge) or the body fur. TEDDYPOM=cream|fur (tests); tests may assign it too.
    nonisolated(unsafe) static var pomCream: Bool = {
        if let s = ProcessInfo.processInfo.environment["TEDDYPOM"] { return s.lowercased() != "fur" }
        return true
    }()
    /// The ears and pom are body vertices (all variants but `old`).
    var inBody: Bool { self != .old }
}

nonisolated enum TeddyBean {
    // MARK: the design numbers

    /// The right ear's root on the egg: polar angle from straight up (deg) and azimuth from the front (deg).
    nonisolated(unsafe) static var earPolar = 40.0, earAzimuth = 78.0
    /// The plate: half width, half height above / below its centre, outline exponent (2 = ellipse, a bit more = slightly squarish), splay of the face outward (deg).
    nonisolated(unsafe) static var earA = 0.20, earTopB = 0.275, earLowB = 0.22, earN = 2.3, earSplay = 22.0, earPitch = 9.0
    /// How far the plate's centre is sunk below the head surface along the ear's up axis (covers the head's curve under the base corners).
    nonisolated(unsafe) static var earSink = 0.04
    /// Half thickness at the root and at the rim, and the rim's round radius.
    nonisolated(unsafe) static var earHalfRoot = 0.075, earHalfRim = 0.050, earRimR = 0.046
    /// The inner hollow: an ellipsoid (semi axes u, v, w) whose centre sits on the face line `earHollowV` above the surface line, `earHollowDepth` deep; blended with `earHollowK`.
    nonisolated(unsafe) static var earHollowDepth = 0.030, earHollowK = 0.022
    nonisolated(unsafe) static var earHollowAxes = SIMD3<Double>(0.162, 0.150, 0.075)
    nonisolated(unsafe) static var earHollowV = 0.045          // the hollow's centre, above the surface line (the plate centre is `earSink` below it)
    /// The fillets (rolling-ball radius, rest units).
    nonisolated(unsafe) static var earFilletR = 0.05, pomFilletR = 0.07
    /// The pom: the old feature's size and spot.
    static let pomRadius = Double(TeddyMesh.pomRadius), pomY = Double(TeddyMesh.pomY), pomEmbed = Double(TeddyMesh.pomEmbed)
    static let pomGrid = 6, earAround = 36
    /// Colatitudes (deg from the front axis) of the ear's rings: dense over the front face (the hollow's soft edge needs it), then the rim, a few over the back.
    static let earThetas: [Double] = [6, 14, 22, 30, 37, 43, 48, 53, 58, 64, 72, 81, 90, 99, 108, 117, 128, 140, 155]

    // MARK: parts

    struct Part {
        var name: String
        var isEar: Bool
        var o: SIMD3<Double>                 // plate / ball centre (inside the body): the anchor everything shrinks onto
        var u: SIMD3<Double>, v: SIMD3<Double>, f: SIMD3<Double>      // ear frame (width, up, face); unused for the pom
        var filletR: Double
        var reach: Double                    // farthest a fillet can matter from `o`
        var landmarkTargets: [SIMD3<Float>]
        var first = 0, count = 0             // in the block (local vertex indices); the first vertex is the pole at `o`
        /// Local coordinates of a rest point.
        func local(_ q: SIMD3<Double>) -> SIMD3<Double> { let d = q - o; return SIMD3(simd_dot(d, u), simd_dot(d, v), simd_dot(d, f)) }
        /// Signed distance to the part's solid (rest space).
        func sdf(_ q: SIMD3<Double>) -> Double {
            if isEar { return TeddyBean.earLocalSDF(local(q)) }
            return simd_length(q - o) - TeddyBean.pomRadius
        }
    }

    static func rot(_ v: SIMD3<Double>, about a: SIMD3<Double>, by ang: Double) -> SIMD3<Double> {
        let c = cos(ang), s = sin(ang)
        return v * c + simd_cross(a, v) * s + a * (simd_dot(a, v) * (1 - c))
    }

    /// The three parts: right ear (+x), left ear, pom.
    static func buildParts() -> [Part] {
        func d(_ p: SIMD3<Float>) -> SIMD3<Double> { SIMD3(Double(p.x), Double(p.y), Double(p.z)) }
        // right ear
        let pol = earPolar * .pi / 180, az = earAzimuth * .pi / 180
        let dir = simd_normalize(SIMD3<Float>(Float(sin(pol) * sin(az)), Float(cos(pol)), Float(sin(pol) * cos(az))))
        let (sp, sn) = TeddyMesh.surface(from: TeddyMesh.earCentreFrom, dir: dir)
        let p = d(sp), n = d(sn)
        let zf = SIMD3<Double>(0, 0, 1)
        let f0 = simd_normalize(zf - n * simd_dot(zf, n))                       // forward along the head surface
        var g = simd_normalize(simd_cross(n, f0)); if g.x < 0 { g = -g }        // outward along the head surface
        let sa = earSplay * .pi / 180
        let f = simd_normalize(f0 * cos(sa) + g * sin(sa))
        let v0 = simd_normalize(n - f * simd_dot(n, f))
        let u = simd_cross(v0, f)
        let pa = earPitch * .pi / 180                                            // the face tips up toward a camera that looks down on the room
        let f1 = simd_normalize(f * cos(pa) + v0 * sin(pa)), v = simd_normalize(v0 * cos(pa) - f * sin(pa))
        let o = p - v0 * earSink
        var right = Part(name: "ear_r", isEar: true, o: o, u: u, v: v, f: f1, filletR: earFilletR, reach: 0.55, landmarkTargets: [])
        func mir(_ a: SIMD3<Double>) -> SIMD3<Double> { SIMD3(-a.x, a.y, a.z) }
        let ov = mir(o), vv = mir(v), ff = mir(f1)
        var left = Part(name: "ear_l", isEar: true, o: ov, u: simd_cross(vv, ff), v: vv, f: ff, filletR: earFilletR, reach: 0.55, landmarkTargets: [])
        func targets(_ p: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> [SIMD3<Float>] {
            [p + a * 0.16, p - a * 0.16, p + b * 0.16].map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
        }
        right.landmarkTargets = targets(p, u, f)
        left.landmarkTargets = targets(mir(p), simd_cross(vv, ff), ff)
        // the pom
        let (pp, pn) = TeddyMesh.pomSpot()
        let pc = d(pp) + d(pn) * (pomEmbed * pomRadius)
        let pom = Part(name: "pom", isEar: false, o: pc, u: SIMD3(1, 0, 0), v: SIMD3(0, 1, 0), f: SIMD3(0, 0, 1), filletR: pomFilletR, reach: pomRadius + 0.3,
                       landmarkTargets: [d(pp) + SIMD3(0.16, 0, 0), d(pp) - SIMD3(0.16, 0, 0), d(pp) + SIMD3(0, 0.16, 0)].map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) })
        return [right, left, pom]
    }

    // MARK: the ear solid

    @inline(__always) static func smax(_ a: Double, _ b: Double, _ k: Double) -> Double { -BobForm.smin(-a, -b, k) }

    /// Signed distance (approximate, exact sign) to one ear in its local frame (u across, v up, w along the face normal; origin = the plate centre).
    static func earLocalSDF(_ l: SIMD3<Double>) -> Double {
        let a = earA, b = l.y >= 0 ? earTopB : earLowB, n = earN
        let x = abs(l.x) / a, y = abs(l.y) / b
        let rho = pow(pow(x, n) + pow(y, n), 1 / n)
        let r1 = max(rho, 1e-6)
        let gx = pow(r1, 1 - n) * pow(x, n - 1) / a, gy = pow(r1, 1 - n) * pow(y, n - 1) / b
        let d2 = (rho - 1) / max(hypot(gx, gy), 1e-6)                            // distance to the outline in the plate plane
        let rc = min(rho, 1)
        let hmid = earHalfRoot - (earHalfRoot - earHalfRim) * rc * rc          // half thickness: ~0.11 thick at the root, ~0.07 near the rim
        let hc = hmid - earRimR
        let dx = d2 + earRimR, dw = abs(l.z) - hc
        let plate = hypot(max(dx, 0), max(dw, 0)) + min(max(dx, dw), 0) - earRimR     // a rounded plate: the rim is a half circle of radius earRimR
        // the hollow: an ellipsoid carved out of the front face
        let ax = earHollowAxes
        let c = SIMD3<Double>(0, earHollowV + earSink, earHalfRoot + ax.z - earHollowDepth)
        let q = (l - c) / ax
        let dish = (simd_length(q) - 1) * min(ax.x, ax.y, ax.z)
        return smax(plate, -dish, earHollowK)
    }

    /// 0...1: how much of the inner-ear tint a point of the ear's front face gets (soft ~1.5 cm edge; fades out at the root so there is no colour step to the head).
    static func hollowMask(_ l: SIMD3<Double>) -> Double {
        if l.z < 0.01 { return 0 }
        let ax = earHollowAxes
        let c = SIMD3<Double>(0, earHollowV + earSink, earHalfRoot + ax.z - earHollowDepth)
        let s = simd_length((l - c) / ax)
        let edge = 1 - BobForm.smooth01((s - 0.97) / 0.17)
        let root = BobForm.smooth01((l.y - earSink + 0.005) / 0.05)
        return edge * root
    }

    // MARK: the mesh

    /// Cube-sphere directions (no poles): `n` x `n` cells on each of six faces, shared edge vertices merged. Returns the unit directions and the triangles.
    static func cubeSphere(_ n: Int) -> (dirs: [SIMD3<Double>], tri: [UInt32]) {
        var dirs: [SIMD3<Double>] = [], key: [String: Int] = [:], tri: [UInt32] = []
        func vert(_ p: SIMD3<Double>) -> Int {
            let d = simd_normalize(p)
            let k = String(format: "%.5f,%.5f,%.5f", d.x, d.y, d.z)
            if let i = key[k] { return i }
            dirs.append(d); key[k] = dirs.count - 1
            return dirs.count - 1
        }
        let axes: [(SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1)),
            (SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)), (SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(1, 0, 0), SIMD3(0, -1, 0)),
        ]
        for (c, a, b) in axes {
            var grid = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: n + 1)
            for i in 0...n { for j in 0...n {
                let s = tan((Double(i) / Double(n) * 2 - 1) * .pi / 4), t = tan((Double(j) / Double(n) * 2 - 1) * .pi / 4)
                grid[i][j] = vert(c + a * s + b * t)
            } }
            for i in 0..<n { for j in 0..<n {
                let p00 = UInt32(grid[i][j]), p10 = UInt32(grid[i + 1][j]), p01 = UInt32(grid[i][j + 1]), p11 = UInt32(grid[i + 1][j + 1])
                tri += [p00, p10, p11, p00, p11, p01]
            } }
        }
        return (dirs, tri)
    }

    struct Block { var pos: [SIMD3<Double>] = [], nrm: [SIMD3<Double>] = [], mat: [Float] = [], tri: [UInt32] = [] }

    /// Rest-space vertices / normals / mat of the whole block + the part table with first / count filled in (cached).
    static let built: (parts: [Part], block: Block) = {
        var parts = buildParts()
        var blk = Block()
        for pi in 0..<parts.count {
            var part = parts[pi]
            part.first = blk.pos.count
            let base = blk.pos.count
            // pole vertex at the centre (unreferenced by any triangle: the collapse target, always inside the body)
            blk.pos.append(part.o); blk.nrm.append(part.v); blk.mat.append(0)
            if part.isEar {
                // rings of `earAround` vertices about the face axis (colatitude from the table), a pole on each face: the hit point of a ray from the plate centre
                let D = SIMD3<Double>(earA, 0.22, earHalfRoot)
                func hit(_ dv: SIMD3<Double>) {
                    var lo = 0.0, hi = 4.0
                    for _ in 0..<46 { let m = (lo + hi) / 2; if earLocalSDF(dv * m) < 0 { lo = m } else { hi = m } }
                    let l = dv * ((lo + hi) / 2)
                    let e = 0.0008
                    let g = SIMD3(earLocalSDF(l + SIMD3(e, 0, 0)) - earLocalSDF(l - SIMD3(e, 0, 0)), earLocalSDF(l + SIMD3(0, e, 0)) - earLocalSDF(l - SIMD3(0, e, 0)),
                                  earLocalSDF(l + SIMD3(0, 0, e)) - earLocalSDF(l - SIMD3(0, 0, e)))
                    let nl = simd_length(g) > 1e-12 ? simd_normalize(g) : simd_normalize(dv)
                    blk.pos.append(part.o + part.u * l.x + part.v * l.y + part.f * l.z)
                    blk.nrm.append(simd_normalize(part.u * nl.x + part.v * nl.y + part.f * nl.z))
                    blk.mat.append(0)                                            // (the cream hollow is a per-pixel shader shape: teddyEarMask)
                }
                let thetas = earThetas.map { $0 * .pi / 180 }
                hit(SIMD3(0, 0, 1))                                              // the front pole (base + 1)
                for th in thetas { for j in 0..<earAround {
                    let ph = 2 * Double.pi * Double(j) / Double(earAround)
                    hit(SIMD3(D.x * sin(th) * cos(ph), D.y * sin(th) * sin(ph), D.z * cos(th)))
                } }
                hit(SIMD3(0, 0, -1))                                             // the back pole
                let f0 = base + 1, bottom = f0, top = blk.pos.count - 1
                func ring(_ r: Int, _ j: Int) -> UInt32 { UInt32(f0 + 1 + earAround * r + (j % earAround)) }
                for j in 0..<earAround { blk.tri += [UInt32(bottom), ring(0, j), ring(0, j + 1)] }
                for r in 0..<(thetas.count - 1) { for j in 0..<earAround {
                    blk.tri += [ring(r, j), ring(r + 1, j), ring(r, j + 1), ring(r, j + 1), ring(r + 1, j), ring(r + 1, j + 1)]
                } }
                for j in 0..<earAround { blk.tri += [UInt32(top), ring(thetas.count - 1, j + 1), ring(thetas.count - 1, j)] }
            } else {
                let cs = cubeSphere(pomGrid)
                for dir in cs.dirs { blk.pos.append(part.o + dir * pomRadius); blk.nrm.append(dir); blk.mat.append(-0.85) }          // (a cream mask that keeps some of the fur's shading, so the ball reads round; the Renderer drops it for the fur pom)
                blk.tri += cs.tri.map { $0 + UInt32(base + 1) }
            }
            part.count = blk.pos.count - base
            parts[pi] = part
        }
        return (parts, blk)
    }()

    static var parts: [Part] { built.parts }
    static var vertexCount: Int { built.block.pos.count }
    /// Where the block starts in the body mesh last built (Geometry), so a Skinner nobody configured still collapses it.
    nonisolated(unsafe) static var builtFirst = -1

    /// Triangles of the block (winding fixed by Geometry's pass against the normals), offset to `firstVertex`.
    static func triangles(firstVertex f: Int) -> [UInt32] { built.block.tri.map { $0 + UInt32(f) } }
    static let localF: [SIMD3<Float>] = built.block.pos.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }

    /// Rest-space points of the ears' visible part (above the head surface), both sides: what the hat rule tests.
    static func earVisiblePoints(minHeight: Double = 0.03) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for part in parts where part.isEar {
            for i in 1..<part.count where BobForm.sdf(built.block.pos[part.first + i]) > minHeight { out.append(localF[part.first + i]) }
        }
        return out
    }

    // MARK: the fillet (the egg's own vertices pushed onto the smooth union)

    /// The rest-space displacement of an egg rest point near a part's root: a true circular smooth-union fillet between the egg and the part's solid, found by
    /// pushing the point along the EGG NORMAL until it lies on the blended surface (the shipped Pip back's `blend` maths, TailBean.swellVector).
    static func swell(_ q: SIMD3<Float>, part: Part) -> SIMD3<Float> {
        let p = SIMD3<Double>(Double(q.x), Double(q.y), Double(q.z))
        if simd_distance(p, part.o) > part.reach { return .zero }
        let R = part.filletR, kk = R / (1 - 0.5.squareRoot())
        if part.sdf(p) >= kk { return .zero }
        let n = BobForm.normal(p)
        func smin(_ a: Double, _ b: Double) -> Double {
            let h = max(kk - abs(a - b), 0) / kk
            return min(a, b) - kk * 0.5 * (1 + h - (1 - h * (h - 2)).squareRoot())
        }
        func f(_ s: Double) -> Double { let x = p + n * s; return smin(BobForm.sdf(x), part.sdf(x)) }
        let cap = 0.5 * R
        var root = 0.0
        if f(0) < 0 {
            let top = 3 * cap
            if f(top) < 0 { root = top } else {
                var lo = 0.0, hi = top
                for _ in 0..<18 { let m = (lo + hi) / 2; if f(m) < 0 { lo = m } else { hi = m } }
                root = (lo + hi) / 2
            }
        }
        let s = cap * tanh(root / cap)
        let d = n * s
        return SIMD3(Float(d.x), Float(d.y), Float(d.z))
    }

    /// What a Skinner needs per mesh: the three landmark egg vertices of each part, and the egg vertices each part's fillet pushes (rest-space vectors).
    struct Rig {
        var landmarks: [[Int]]
        var landmarkRest: [[SIMD3<Float>]]
        var bumps: [[(Int, SIMD3<Float>)]]
    }
    private static let rigLock = NSLock()
    nonisolated(unsafe) private static var rigCache: [Int: Rig] = [:]
    static func rig(rest: [Float], eggLimit: Int) -> Rig {
        let key = rest.count &* 31 &+ eggLimit
        rigLock.lock(); let c = rigCache[key]; rigLock.unlock()
        if let c { return c }
        var r = Rig(landmarks: [], landmarkRest: [], bumps: [])
        let limit = min(eggLimit, rest.count / 3)
        for part in parts {
            let lm = part.landmarkTargets.map { t -> Int in
                var best = 0, bd = Float.infinity
                for v in 0..<limit {
                    let dd = simd_distance_squared(SIMD3(rest[3 * v], rest[3 * v + 1], rest[3 * v + 2]), t)
                    if dd < bd { bd = dd; best = v }
                }
                return best
            }
            r.landmarks.append(lm)
            r.landmarkRest.append(lm.map { SIMD3(rest[3 * $0], rest[3 * $0 + 1], rest[3 * $0 + 2]) })
            var bumps: [(Int, SIMD3<Float>)] = []
            for v in 0..<limit {
                let d = swell(SIMD3(rest[3 * v], rest[3 * v + 1], rest[3 * v + 2]), part: part)
                if simd_length(d) > 0.002 { bumps.append((v, d)) }
            }
            r.bumps.append(bumps)
        }
        rigLock.lock(); rigCache[key] = r; rigLock.unlock()
        return r
    }
}

// MARK: - the Skinner side

extension Skinner {
    /// Configure the Teddy block of `rm` (landmarks + fillet pushes; cached across Jelbies).
    func configureTeddy(_ rm: RenderMesh) {
        guard let cap = rm.armCapsule, cap.teddyFirst >= 0 else { return }
        teddyFirst = cap.teddyFirst
        teddyRig = TeddyBean.rig(rest: rm.rest, eggLimit: cap.firstVertex.min() ?? rm.vertexCount)
    }

    /// Place (or collapse) the three parts. Off (every Jelly but Teddy, a tucked part), a part sits collapsed on its pole inside the body.
    func applyTeddy(_ dyn: UnsafeMutablePointer<Float>) {
        let f = teddyFirst >= 0 ? teddyFirst : TeddyBean.builtFirst, n = TeddyBean.vertexCount
        guard f >= 0, f + n <= vertexCount else { return }
        let parts = TeddyBean.parts
        func P(_ i: Int) -> SIMD3<Float> { SIMD3(dyn[6 * (f + i)], dyn[6 * (f + i) + 1], dyn[6 * (f + i) + 2]) }
        func collapse(_ part: TeddyBean.Part) {
            let B = P(part.first)
            for i in 1..<part.count { let o = 6 * (f + part.first + i); dyn[o] = B.x; dyn[o + 1] = B.y; dyn[o + 2] = B.z }
        }
        guard let rig = teddyRig, teddyOn else { for part in parts { collapse(part) }; return }
        func frame(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> simd_float3x3 {
            let x = simd_normalize(b - a), z = simd_normalize(simd_cross(x, c - a)), y = simd_cross(z, x)
            return simd_float3x3(columns: (x, y, z))
        }
        var rots = [simd_float3x3](repeating: matrix_identity_float3x3, count: parts.count)
        var live = [Bool](repeating: false, count: parts.count)
        let sway = teddySway
        for (pi, part) in parts.enumerated() {
            let scale = pi < 2 ? teddyEarScale : teddyPomScale
            if scale <= 0.002 { collapse(part); continue }
            live[pi] = true
            let lm = rig.landmarks[pi]
            func at(_ k: Int) -> SIMD3<Float> { let o = 6 * lm[k]; return SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) }
            let rr = rig.landmarkRest[pi], ss = [at(0), at(1), at(2)]
            let Rot = frame(ss[0], ss[1], ss[2]) * frame(rr[0], rr[1], rr[2]).transpose
            let Cr = (rr[0] + rr[1] + rr[2]) / 3, Cs = (ss[0] + ss[1] + ss[2]) / 3
            rots[pi] = Rot
            let O = SIMD3<Float>(Float(part.o.x), Float(part.o.y), Float(part.o.z))
            let A = Cs + Rot * (O - Cr)                                                     // the plate centre, carried
            // the follow-through wobble about the root (rest frame): nod about x, side about z (mirrored ears), a pom wobbles a little more
            let k: Float = pi == 2 ? 1.5 : 1, sgn: Float = pi == 1 ? -1 : 1
            let qz = simd_quatf(angle: sgn * sway.y * k * .pi / 180, axis: SIMD3(0, 0, 1))
            let W = simd_float3x3((simd_quatf(angle: sway.x * k * .pi / 180, axis: SIMD3(1, 0, 0)) * qz))
            for i in 0..<part.count {
                let L = TeddyBean.localF[part.first + i]
                let rel = W * (L - O)
                let p = A + Rot * rel * scale
                let o = 6 * (f + part.first + i); dyn[o] = p.x; dyn[o + 1] = p.y; dyn[o + 2] = p.z
            }
        }
        for (pi, _) in parts.enumerated() where live[pi] {                                // the fillet pushes (after every frame is read)
            let s = pi < 2 ? teddyEarScale : teddyPomScale
            for (v, w) in rig.bumps[pi] {
                let o = 6 * v, d = rots[pi] * (w * s)
                dyn[o] += d.x; dyn[o + 1] += d.y; dyn[o + 2] += d.z
            }
        }
    }
}

extension TeddyBean {
    /// What the shaders' `teddyEarMask` needs (rest space, the right ear): frame, and (cream half width, U-cap centre, top, skin line) in ear-local v. TeddyBeanTests prints / checks them.
    static let creamHalfWidth = 0.13
    static var shaderConstants: (o: SIMD3<Double>, u: SIMD3<Double>, v: SIMD3<Double>, f: SIMD3<Double>, p: SIMD4<Double>) {
        let e = parts[0]
        let skin = earSink * cos(earPitch * .pi / 180)
        let top = earTopB
        let visH = top - skin
        return (e.o, e.u, e.v, e.f, SIMD4(creamHalfWidth, skin + 0.31 * visH, skin + 0.70 * visH, skin))
    }
}
