//
//  FurnitureFitTests.swift
//  Every piece a Jelly sits on, sleeps in, climbs or rocks, QA'd against the DRAWN furniture mesh (DecorModels.build: squashed, rocked, swayed):
//    - the body (rendered vertices, arms and foot beans included) does not sink into the mesh beyond a small seat-contact tolerance,
//    - he sits ON the seat (lowest point of the body within 0.03 of the seat surface), the feet are attached and not inside the piece,
//    - two on a loveseat / swing never touch (SDF body-to-body gap, the cuddle lean included),
//    - a worn hat does not sink into a backrest.
//  FurnCaptureTests.testCaptureFurnitureQA draws the same scenes (FURN_CAP_DIR).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FurnitureFitTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { DecorField.shared.clear(); Self.room() }
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    static func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    // MARK: tolerances
    /// How far a body vertex may be inside the furniture mesh (the seat's soft contact; the squash of the cushion).
    static let maxDepth: Float = 0.05
    /// Lowest point of the body over the seat surface.
    static let seatGap: Float = 0.03
    /// Two Jellies on one piece: the least SDF gap between the bodies.
    static let bodyGap: Float = 0.02

    // MARK: geometry
    /// Distance (negative inside) from `p` to the nearest triangle of `mesh`, by the triangle's averaged vertex normals.
    struct Solid {
        var v: [SIMD3<Float>] = [], n: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        init(_ m: RoomMesh) { v = m.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) }; n = m.vertices.map { SIMD3($0.normal.x, $0.normal.y, $0.normal.z) }; idx = m.indices }
        static func closest(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
            let ab = b - a, ac = c - a, ap = p - a
            let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
            if d1 <= 0 && d2 <= 0 { return a }
            let bp = p - b, d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
            if d3 >= 0 && d4 <= d3 { return b }
            let vc = d1 * d4 - d3 * d2
            if vc <= 0 && d1 >= 0 && d3 <= 0 { return a + ab * (d1 / (d1 - d3)) }
            let cp = p - c, d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
            if d6 >= 0 && d5 <= d6 { return c }
            let vb = d5 * d2 - d1 * d6
            if vb <= 0 && d2 >= 0 && d6 <= 0 { return a + ac * (d2 / (d2 - d6)) }
            let va = d3 * d6 - d5 * d4
            if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 { return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))) }
            let den = 1 / (va + vb + vc)
            return a + ab * (vb * den) + ac * (vc * den)
        }
        /// Penetration depth of `p` (0 when outside).
        func depth(_ p: SIMD3<Float>) -> Float {
            var best = Float.infinity, sgn: Float = 1
            var t = 0
            while t + 2 < idx.count {
                let a = v[Int(idx[t])], b = v[Int(idx[t + 1])], c = v[Int(idx[t + 2])]
                t += 3
                let lo = simd_min(a, simd_min(b, c)) - SIMD3(repeating: best), hi = simd_max(a, simd_max(b, c)) + SIMD3(repeating: best)
                if p.x < lo.x || p.y < lo.y || p.z < lo.z || p.x > hi.x || p.y > hi.y || p.z > hi.z { continue }
                let q = Self.closest(p, a, b, c)
                let d = simd_distance(p, q)
                if d < best {
                    best = d
                    let nn = n[Int(idx[t - 3])] + n[Int(idx[t - 2])] + n[Int(idx[t - 1])]
                    sgn = simd_dot(p - q, nn) < 0 ? -1 : 1
                }
            }
            guard sgn < 0, best.isFinite, parityInside(p) else { return 0 }
            return best
        }
        /// Odd number of crossings of a ray (both tests must agree: smooth vertex normals alone mislead near edges, an open mesh alone misleads in hollows).
        func parityInside(_ p: SIMD3<Float>) -> Bool {
            let d = simd_normalize(SIMD3<Float>(0.31, 0.9, 0.29))
            var hits = 0, t = 0
            while t + 2 < idx.count {
                let a = v[Int(idx[t])], e1 = v[Int(idx[t + 1])] - a, e2 = v[Int(idx[t + 2])] - a
                t += 3
                let h = simd_cross(d, e2), det = simd_dot(e1, h)
                if abs(det) < 1e-9 { continue }
                let f = 1 / det, s = p - a, u = f * simd_dot(s, h)
                if u < 0 || u > 1 { continue }
                let q = simd_cross(s, e1), w = f * simd_dot(d, q)
                if w < 0 || u + w > 1 { continue }
                if f * simd_dot(e2, q) > 1e-6 { hits += 1 }
            }
            return hits % 2 == 1
        }
    }

    /// The drawn furniture right now.
    static func solid(time: Float = 0.4) -> Solid { Solid(DecorModels.build(feet: DecorField.shared.feet, field: DecorField.shared, time: time)) }

    /// World positions of the rendered body (every `stride`th vertex).
    static func bodyPoints(_ r: MotionRig, stride s: Int = 5) -> [SIMD3<Float>] {
        r.render()
        var out: [SIMD3<Float>] = []
        var i = 0
        let n = r.dyn.count / 6
        while i < n { out.append(SIMD3(r.dyn[6 * i], r.dyn[6 * i + 1], r.dyn[6 * i + 2])); i += s }
        return out
    }
    /// SDF of Jelly `b` (rest-body SDF in its fitted pose) at world point p.
    static func sdf(_ b: MotionRig, _ p: SIMD3<Float>) -> Float {
        let pose = b.sim.bodyPose(iterations: 3)
        let l = pose.rotation.inverse.act(p - pose.centroid) + b.sim.restCentroid
        return Float(BobForm.sdf(SIMD3(Double(l.x), Double(l.y), Double(l.z))))
    }

    // MARK: probe
    struct Stats {
        var frames = 0
        var worstDepth: Float = 0, deepCount = 0
        var seatLo: Float = .infinity, seatHi: Float = -.infinity
        var footIn: Float = 0, footAway: Float = 0
        var bodyGap: Float = .infinity
        var maxAngle: Float = 0
        var offCentre: Float = 0
        var worstAt = SIMD3<Float>.zero
        /// Extra depth allowed: a soft body leaning into a backrest (the Jelly is 1.3 wide, the cushion gives).
        var extraTol: Float = 0
    }
    func observe(_ s: inout Stats, _ rigs: [MotionRig], solid: Solid, soft: Float = 0) {
        s.frames += 1
        for r in rigs {
            let pts = Self.bodyPoints(r)
            for p in pts {
                let d = solid.depth(p)
                if d > Self.maxDepth + soft + s.extraTol { s.deepCount += 1 }
                if d > s.worstDepth { s.worstDepth = d; s.worstAt = p - SIMD3(0, 0, 0) }
            }
            if let sw = DecorField.shared.seatWorld(7, seat: r.brain.idleState.seat), r.brain.idleState.kind == .decorSit {
                let c = r.sim.centroid()
                s.offCentre = max(s.offCentre, simd_distance(SIMD2(c.x, c.z), SIMD2(sw.x, sw.z)))
            }
            let low = pts.map(\.y).min() ?? 0
            s.seatLo = min(s.seatLo, low - r.sim.floorY); s.seatHi = max(s.seatHi, low - r.sim.floorY)
            for side in 0..<2 {
                let b = r.footBottom(side) - r.sim.floorY
                s.footIn = min(s.footIn, b)
                s.footAway = max(s.footAway, b)
            }
        }
        if rigs.count == 2 {
            let a = Self.bodyPoints(rigs[0], stride: 3), b = Self.bodyPoints(rigs[1], stride: 3)
            for p in a { s.bodyGap = min(s.bodyGap, Self.sdf(rigs[1], p)) }
            for p in b { s.bodyGap = min(s.bodyGap, Self.sdf(rigs[0], p)) }
        }
    }
    func log(_ tag: String, _ s: Stats) {
        MotionLog.write(String(format: "FIT %@: frames %d, worst depth %.3f (%d verts over %.2f), lowest body point over the seat %.3f...%.3f, feet %.3f...%.3f, body gap %.3f, angle %.3f, off-centre %.3f, worst at (%.2f %.2f %.2f)", tag, s.frames, s.worstDepth, s.deepCount, Self.maxDepth, s.seatLo, s.seatHi, s.footIn, s.footAway, s.bodyGap, s.maxAngle, s.offCentre, s.worstAt.x, s.worstAt.y, s.worstAt.z))
    }

    // MARK: scenes
    /// `n` Jellies sit on `kind` (placed at `c`); calls `each` every 6th settled frame. Returns the rigs.
    func sitScene(_ kind: DecorKind, n: Int, at c: SIMD2<Float>, seconds: Float = 40, wear: WearLook? = nil, each: (Solid, [MotionRig]) -> Void) -> [MotionRig] {
        DecorField.shared.clear()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: c.x, z: c.y)])
        let starts: [SIMD2<Float>] = [SIMD2(c.x - 1.6, c.y + 2.0), SIMD2(c.x + 1.6, c.y + 2.0)]
        let lab = SocialTests.Lab(n: n, positions: Array(starts.prefix(n)), quiet: true, seed: 7)
        Self.keep.append(lab)
        for r in lab.rigs { r.skinner.autoBlink = false; r.brain.idleForced = true; r.renderSamples = false }
        for r in lab.rigs { XCTAssertTrue(r.brain.idleStart(.decorSit, r.sim), "\(kind): sit starts") }
        func seated(_ r: MotionRig) -> Bool { r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 1.5 }
        var k = 0, settled = 0
        for _ in 0..<Int(seconds * 60) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            k += 1
            if lab.rigs.allSatisfy(seated) {
                settled += 1
                if settled % 6 == 0 { each(Self.solid(), lab.rigs) }
                if settled > 60 * 14 { break }
            }
        }
        XCTAssertGreaterThan(settled, 120, "\(kind) x\(n): everybody sat down")
        return lab.rigs
    }

    func check(_ tag: String, _ s: Stats, soft: Float = 0, twoSeat: Bool = false, line: UInt = #line) {
        log(tag, s)
        XCTAssertGreaterThan(s.frames, 10, "\(tag): observed", line: line)
        XCTAssertLessThanOrEqual(s.deepCount, 4 + Int(soft * 200), "\(tag): the body does not sink into the furniture (worst \(s.worstDepth))", line: line)
        XCTAssertLessThanOrEqual(s.seatLo, Self.seatGap + soft, "\(tag): not floating above the seat (\(s.seatLo))", line: line)
        XCTAssertGreaterThanOrEqual(s.seatHi, -Self.seatGap - soft - 0.15, "\(tag): not buried in the seat (\(s.seatHi))", line: line)
        XCTAssertGreaterThanOrEqual(s.footIn, -0.03 - soft, "\(tag): the feet are not inside the seat (\(s.footIn))", line: line)
        XCTAssertLessThan(s.footAway, 0.12 + soft * 3, "\(tag): the feet stay attached (\(s.footAway))", line: line)
        XCTAssertLessThan(s.offCentre, 0.4, "\(tag): he sits over the seat point, not beside the piece (\(s.offCentre))", line: line)
        if twoSeat { XCTAssertGreaterThanOrEqual(s.bodyGap, Self.bodyGap, "\(tag): two Jellies do not touch (\(s.bodyGap))", line: line) }
    }

    func testSingleSeatsFitTheJelly() {
        for kind in [DecorKind.pouf, .armchair, .rockingchair, .diningset, .loveseat, .swing] {
            var s = Stats()
            s.extraTol = [.armchair, .loveseat, .rockingchair].contains(kind) ? 0.06 : 0
            _ = sitScene(kind, n: 1, at: SIMD2(0, -0.8)) { solid, rigs in
                observe(&s, rigs, solid: solid)
                if let a = DecorField.shared.anim[7] { s.maxAngle = max(s.maxAngle, abs(kind == .swing ? DecorModels.swingAngle(a) : DecorModels.rockAngle(a))) }
            }
            check("\(kind) x1", s)
            if kind == .rockingchair { XCTAssertGreaterThan(s.maxAngle, 0.14 * 0.8, "rocked to the extremes") }
            if kind == .swing { XCTAssertGreaterThan(s.maxAngle, 0.22 * 0.8, "swayed to the extremes") }
        }
    }

    func testTwoOnTheLoveseatSwingAndStoolsDoNotOverlap() {
        for kind in [DecorKind.loveseat, .swing, .diningset] {
            var s = Stats()
            s.extraTol = kind == .loveseat ? 0.06 : 0
            _ = sitScene(kind, n: 2, at: SIMD2(0, -0.8)) { solid, rigs in
                observe(&s, rigs, solid: solid)
                if let a = DecorField.shared.anim[7] { s.maxAngle = max(s.maxAngle, abs(kind == .swing ? DecorModels.swingAngle(a) : 0)) }
            }
            check("\(kind) x2", s, twoSeat: kind != .diningset)
            if kind == .diningset { XCTAssertGreaterThanOrEqual(s.bodyGap, Self.bodyGap, "stools: apart") }
        }
    }

    func testBeanbagAndCushionSeatsAreSoftButNotFloating() {
        for kind in [DecorKind.beanbag] {
            var s = Stats()
            _ = sitScene(kind, n: 1, at: SIMD2(0, -0.8)) { solid, rigs in observe(&s, rigs, solid: solid, soft: 0.3) }
            log("\(kind) x1", s)
            XCTAssertGreaterThan(s.frames, 10)
            XCTAssertLessThanOrEqual(s.seatLo, Self.seatGap + 0.1, "\(kind): not floating above the seat (\(s.seatLo))")
        }
    }

    func testSleeperInThePetBedAndTheSlidePhases() {
        // pet bed
        do {
            DecorField.shared.clear()
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .petbed, x: 1.0, z: 0.4)])
            let r = MotionRig(game: true); Self.keep.append(r)
            r.renderSamples = false; r.skinner.autoBlink = false
            r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
            r.brain.abortScript(r.sim, r.skinner); r.sim.teleport(toXZ: SIMD2(-1.0, 1.4))
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim); r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 600
            var s = Stats(), k = 0, inside = true
            for _ in 0..<(60 * 40) {
                r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: 1.0 / 60)
                if r.brain.isNapping, r.brain.sleep.t > 1.5 {
                    k += 1
                    let c = r.sim.centroid(); let h = DecorKind.petbed.spec.half
                    if abs(c.x - 1.0) > h.x - 0.2 || abs(c.z - 0.4) > h.y - 0.2 { inside = false }
                    if k % 6 == 0 { observe(&s, [r], solid: Self.solid()) }
                    if k > 60 * 6 { break }
                }
            }
            check("petbed sleeper", s, soft: 0.1)
            XCTAssertTrue(inside, "the sleeper fits inside the rim")
        }
        // slide: every phase
        do {
            DecorField.shared.clear()
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .slide, x: 1.4, z: 0.3)])
            let r = MotionRig(game: true); Self.keep.append(r)
            r.renderSamples = false; r.skinner.autoBlink = false
            r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
            r.brain.abortScript(r.sim, r.skinner); r.sim.teleport(toXZ: SIMD2(-1.0, 1.0))
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim); r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(.decorSlide, r.sim))
            var per: [Int: Stats] = [:], k = 0
            for _ in 0..<(60 * 60) {
                r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: 1.0 / 60)
                k += 1
                let st = r.brain.idleState.slideStage
                if r.brain.idleState.kind == .decorSlide, st >= 1, k % 6 == 0 {
                    var s = per[st] ?? Stats()
                    s.extraTol = st == 1 ? 0.2 : 0
                    observe(&s, [r], solid: Self.solid())
                    per[st] = s
                }
                if r.brain.idleState.kind == nil, r.t > 5 { break }
            }
            for (st, s) in per.sorted(by: { $0.key < $1.key }) {
                log("slide stage \(st)", s)
                // (a hop between steps is in the air: only the body vs the mesh is judged there)
                XCTAssertLessThanOrEqual(s.deepCount, 6, "slide stage \(st): the body does not sink into the slide (\(s.worstDepth))")
                if st == 4 || st == 5 { XCTAssertLessThanOrEqual(s.seatLo, Self.seatGap + 0.02, "slide stage \(st): not floating above the chute (\(s.seatLo))") }
            }
            XCTAssertTrue(per.keys.contains(4) && per.keys.contains(5), "the slide ran through the platform and the ride")
        }
    }

    /// A tall hat on a Jelly leaning back in a backrest: the hat does not sink into it (it is visible from the front camera).
    func testHatsDoNotSinkIntoBackrests() {
        WearBody.install(MotionRig.renderMesh)
        for kind in [DecorKind.armchair, .loveseat, .rockingchair] {
            for look in [WearLook.tophat, .witchHat] {
                let set = WornSet(); set.body = WearBody.shared; set.soundOn = false
                Self.keep.append(set)
                var worst: Float = 0, deep = 0, frames = 0
                _ = sitScene(kind, n: 1, at: SIMD2(0, -0.8)) { solid, rigs in
                    let r = rigs[0]
                    for _ in 0..<2 { set.tick(id: 0, brain: r.brain, sim: r.sim, outfit: [.head: look], role: .none, hideAll: false, dt: 1.0 / 60) }
                    r.render()
                    let hat = r.dyn.withUnsafeBufferPointer { p in set.frame(theme: RoomTheme(), time: 0.4) { _ in p.baseAddress }.opaque }
                    guard !hat.vertices.isEmpty else { return }
                    frames += 1
                    for v in hat.vertices {
                        let d = solid.depth(SIMD3(v.pos.x, v.pos.y, v.pos.z))
                        worst = max(worst, d); if d > (look == .witchHat ? 0.14 : 0.08) { deep += 1 }          // (the pointed hat's brim leans into the top rail by up to ~0.12: soft felt, hidden behind the head)
                    }
                }
                MotionLog.write(String(format: "FIT hat %@ on %@: frames %d worst depth %.3f verts over 0.08: %d", "\(look)", "\(kind)", frames, worst, deep))
                XCTAssertGreaterThan(frames, 5, "\(look) on \(kind): the hat was worn")
                XCTAssertLessThanOrEqual(deep, 10, "\(look) on \(kind): the hat does not sink into the backrest (worst \(worst))")
            }
        }
    }
}
