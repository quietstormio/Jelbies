//
//  WristbandFitTests.swift
//  The wristband rides the DRAWN arm in every arm mode (rest nub, keyframed wave, held-up arms, walking / running / every scripted capsule move): a snug ring around the arm,
//  perpendicular to its axis, 60-70 % of the way from the root to the tip, its inner surface 0 ... 1.2 cm outside the arm's skin. The truth is read from the SKINNED
//  vertices of the arm (the revolve's tangent rings in the same skin buffer the renderer draws), not from the data the band is built from.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WristbandFitTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// The drawn arm of one side, fitted from its revolve rings in the skinned positions.
    struct Truth {
        var U: SIMD3<Double>, B: SIMD3<Double>, L: Double
        var s: [Double] = [], rho: [[Double]] = [], theta: [Double] = []
        var e1: SIMD3<Double>, e2: SIMD3<Double>
        func radius(at sAx: Double, theta th: Double) -> Double {
            var k = 0
            while k < s.count - 2 && s[k + 1] < sAx { k += 1 }
            let u = min(max((sAx - s[k]) / max(s[k + 1] - s[k], 1e-9), 0), 1)
            let n = theta.count
            var jf = th / (2 * .pi) * Double(n); jf -= floor(jf / Double(n)) * Double(n)          // theta0 = 0 at j = 0, ring order = increasing angle
            let j0 = Int(jf) % n, j1 = (j0 + 1) % n, w = jf - Double(Int(jf))
            func r(_ kk: Int) -> Double { rho[kk][j0] * (1 - w) + rho[kk][j1] * w }
            return r(k) * (1 - u) + r(k + 1) * u
        }
    }

    static func truth(_ d: [Float], first: Int, inflate: Double, modelR1: Float, modelR2: Float, modelLen: Float) -> Truth? {
        let n = ArmCapsule.around, K = ArmCapsule.ringCount, T = ArmCapsule.tipRings
        func P(_ v: Int) -> SIMD3<Double> { SIMD3(Double(d[6 * v]), Double(d[6 * v + 1]), Double(d[6 * v + 2])) }
        func idx(_ k: Int, _ j: Int) -> Int { first + 1 + n * k + j }
        var C = [SIMD3<Double>](repeating: .zero, count: K)
        for k in 0..<K { for j in 0..<n { C[k] += P(idx(k, j)) }; C[k] /= Double(n) }
        let tipPole = P(first), rootPole = P(first + ArmCapsule.vertexCount - 1)
        let U0 = rootPole - tipPole
        guard simd_length(U0) > 1e-6 else { return nil }
        let U = simd_normalize(U0)                                           // tip -> root (toward the shoulder)
        func meanRho(_ k: Int) -> Double { var m = 0.0; for j in 0..<n { let v = P(idx(k, j)) - C[k]; m += simd_length(v - U * simd_dot(v, U)) }; return m / Double(n) }
        let span = simd_length(U0), whole = Double(max(modelLen, 0)) + Double(max(modelR1 - Float(inflate), 0.001)) + Double(max(modelR2 - Float(inflate), 0.001))
        let B = tipPole + U * (span * Double(max(modelR2 - Float(inflate), 0.001)) / whole)
        let LL = span * Double(max(modelLen, 0)) / whole
        var t = Truth(U: U, B: B, L: LL, e1: .zero, e2: .zero)
        let v0 = P(idx(T - 1, 0)) - C[T - 1]
        t.e1 = simd_normalize(v0 - U * simd_dot(v0, U)); t.e2 = simd_cross(U, t.e1)
        t.theta = (0..<n).map { 2 * Double.pi * Double($0) / Double(n) }
        for k in 0..<K {
            t.s.append(simd_dot(C[k] - B, U))
            var row = [Double](repeating: 0, count: n)
            for j in 0..<n { let v = P(idx(k, j)) - C[k]; row[j] = simd_length(v - U * simd_dot(v, U)) + inflate }
            t.rho.append(row)
        }
        // the ring order must run with increasing angle about U (else flip e2 and the angle lookup)
        let a1 = P(idx(T - 1, n / 4)) - C[T - 1]
        if simd_dot(a1, t.e2) < 0 { t.e2 = -t.e2 }          // (e2 only names the direction the ring index runs)
        if t.s.first! > t.s.last! { return nil }
        return t
    }

    /// Smallest principal axis of a point cloud (a thin ring's axis).
    static func thinAxis(_ pts: [SIMD3<Double>]) -> SIMD3<Double> {
        let c = pts.reduce(SIMD3<Double>.zero, +) / Double(pts.count)
        var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
        for p in pts { let q = p - c; xx += q.x * q.x; xy += q.x * q.y; xz += q.x * q.z; yy += q.y * q.y; yz += q.y * q.z; zz += q.z * q.z }
        let tr = xx + yy + zz
        // power iteration on (tr I - C): its largest eigenvector is C's smallest
        var v = SIMD3<Double>(0.3, 0.5, 0.8)
        for _ in 0..<200 {
            let w = SIMD3(tr * v.x - (xx * v.x + xy * v.y + xz * v.z), tr * v.y - (xy * v.x + yy * v.y + yz * v.z), tr * v.z - (xz * v.x + yz * v.y + zz * v.z))
            v = simd_normalize(w)
        }
        return v
    }

    struct Worst {
        var samples = 0, skipped = 0, tucked = 0
        var centre = 0.0, angle = 0.0, minGap = 1.0, maxInner = -1.0, tLo = 9.0, tHi = -9.0
        var whereCentre = "", whereAngle = "", whereGap = "", whereInner = "", whereT = ""
    }

    func check(_ r: MotionRig, label: String, into w: inout Worst, p: WearPrepared, inflateFor: (Int) -> Double?) {
        r.render()
        let frames = GameCare.armFrames(brain: r.brain, sim: r.sim)
        var slot = WornSet.Slot()
        slot.arms = frames
        var m = RoomMesh()
        r.dyn.withUnsafeBufferPointer { WornSet.emitArms(p, into: &m, slot: slot, skin: $0.baseAddress, scale: 1) }          // (as the renderer calls it: with the skinned stream)
        XCTAssertEqual(m.vertices.count, 2 * p.rest.count, "\(label): frames \(frames.map { "a \($0.a) b \($0.b) first \($0.first) infl \($0.inflate) r \($0.r1) \($0.r2)" }) armG \(r.brain.armG)")
        guard m.vertices.count == 2 * p.rest.count, r.brain.armFirstIdx.count == 2 else { return }
        for side in 0..<2 {
            guard let infl = inflateFor(side) else { w.skipped += 1; continue }
            guard let tr = Self.truth(r.dyn, first: r.brain.armFirstIdx[side], inflate: infl, modelR1: frames[side].r1, modelR2: frames[side].r2, modelLen: simd_length(frames[side].a - frames[side].b)) else { w.skipped += 1; continue }
            let pts: [SIMD3<Double>] = (0..<p.rest.count).map { let v = m.vertices[side * p.rest.count + $0].pos; return SIMD3(Double(v.x), Double(v.y), Double(v.z)) }
            let c = pts.reduce(SIMD3<Double>.zero, +) / Double(pts.count)
            // a tucked arm (skin radius at the station collapsed): the band must have shrunk away with it
            let sSt = tr.L * 0.35
            let rSt = 0.5 * (tr.radius(at: sSt, theta: 0) + tr.radius(at: sSt, theta: .pi / 2))
            if rSt < 0.035 {
                var lo = 1.0, hi = -1.0
                for q in pts { let a = simd_dot(q - tr.B, tr.U); lo = min(lo, a); hi = max(hi, a) }
                XCTAssertLessThan(hi - lo, 0.012, "\(label): a tucked arm (radius \(rSt)) wears a band of no width")
                w.tucked += 1
                continue
            }
            let rel = c - tr.B
            let sc = simd_dot(rel, tr.U)
            let off = simd_length(rel - tr.U * sc)
            let tFrac = 1 - sc / tr.L
            let ax = Self.thinAxis(pts)
            let ang = acos(min(1, abs(simd_dot(ax, tr.U)))) * 180 / .pi
            var minGap = 1.0, worstAt = ""
            for q in pts {
                let v = q - tr.B, sAx = simd_dot(v, tr.U), perp = v - tr.U * sAx
                let th = atan2(simd_dot(perp, tr.e2), simd_dot(perp, tr.e1))
                let g = simd_length(perp) - tr.radius(at: sAx, theta: th)
                if g < minGap { minGap = g; worstAt = String(format: "s %.3f th %.2f rad %.3f skin %.3f", sAx, th, simd_length(perp), tr.radius(at: sAx, theta: th)) }
            }
            // the band's average inner clearance: the lowest quartile of the gaps (the wall's inner half), must sit within 1.2 cm of the skin
            var gaps: [Double] = []
            for q in pts {
                let v = q - tr.B, sAx = simd_dot(v, tr.U), perp = v - tr.U * sAx
                let th = atan2(simd_dot(perp, tr.e2), simd_dot(perp, tr.e1))
                gaps.append(simd_length(perp) - tr.radius(at: sAx, theta: th))
            }
            gaps.sort()
            let innerQ = gaps[gaps.count / 4]
            let tag = "\(label) side \(side) truthL \(tr.L) modelLen \(simd_length(frames[side].a - frames[side].b)) rSt \(rSt) sRange \(tr.s.first!)...\(tr.s.last!) minGapAt \(worstAt) armG \(r.brain.armG) c-off \(off) t \(tFrac) ang \(ang) minGap \(minGap) innerQ \(innerQ)"
            w.samples += 1
            if off > w.centre { w.centre = off; w.whereCentre = tag }
            if ang > w.angle { w.angle = ang; w.whereAngle = tag }
            if minGap < w.minGap { w.minGap = minGap; w.whereGap = tag }
            if innerQ > w.maxInner { w.maxInner = innerQ; w.whereInner = tag }
            if tr.L >= 0.04 {          // (a capsule shorter than that is a ball: no station to speak of)
                if tFrac < w.tLo { w.tLo = tFrac }
                if tFrac > w.tHi { w.tHi = tFrac; w.whereT = tag }
            }
        }
    }

    func assertWorst(_ w: Worst, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        MotionLog.write(String(format: "WRIST %@: %d samples (%d skipped, %d tucked), centre off axis max %.4f, axis angle max %.2f deg, min gap %.4f, inner quartile gap max %.4f, station %.2f ... %.2f", name, w.samples, w.skipped, w.tucked, w.centre, w.angle, w.minGap, w.maxInner, w.tLo, w.tHi))
        XCTAssertGreaterThan(w.samples, 10, "\(name): the arms were sampled", file: file, line: line)
        XCTAssertLessThanOrEqual(w.centre, 0.012, "\(name): band centre on the drawn arm's axis: \(w.whereCentre)", file: file, line: line)
        XCTAssertLessThanOrEqual(w.angle, 6, "\(name): band axis along the arm's axis: \(w.whereAngle)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(w.minGap, -0.006, "\(name): no band vertex under the arm's skin: \(w.whereGap)", file: file, line: line)
        XCTAssertLessThanOrEqual(w.maxInner, 0.012, "\(name): the inner surface hugs the arm (<= 1.2 cm outside the skin): \(w.whereInner)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(w.tLo, 0.52, "\(name): station on the arm: \(w.whereT)", file: file, line: line)
        XCTAssertLessThanOrEqual(w.tHi, 0.78, "\(name): station on the arm: \(w.whereT)", file: file, line: line)
    }

    /// The expected capsule inflate (the revolve is hidden / grown by it) so the truth ring is read as the arm's drawn skin.
    func inflate(_ r: MotionRig, side: Int) -> Double? {
        let b = r.brain
        if b.armG > 0.0001 { return b.armBlendNow >= 0.995 ? 0 : nil }          // (the capsule is out: its vertices ARE the drawn arm; skip the swap frames)
        let g = b.skinArmGeom(side: side) ?? ArmGeom.rest                       // (the arm under the revolve: the keyframed arm, else the rest nub; the revolve hides / grows by its capsuleInflate)
        return -g.capsuleInflate * g.flatten.squareRoot()
    }

    func prepared() -> WearPrepared {
        WearBody.install(MotionRig.renderMesh)
        return WearMeshes.prepare(.wristbandsSky, body: WearBody.shared)!
    }

    func testBandRidesTheRestNub() {
        let p = prepared()
        let r = MotionRig(game: true); Self.keep.append(r)
        r.brain.seed = 11; r.brain.amplitude = 1
        var w = Worst(), k = 0
        r.run(3) { k += 1; if k % 6 == 0, r.brain.armG == 0 { self.check(r, label: "rest", into: &w, p: p) { self.inflate(r, side: $0) } } }
        assertWorst(w, "rest nub")
    }

    func testBandRidesTheWave() {
        let p = prepared()
        for (name, blend, feature) in [("blue/panda blend", true, false), ("lavender wings", false, true), ("plain", false, false)] {
            for side in [-1, 1] {
                UserDefaults.standard.set(side, forKey: "BlobWaveSide")
                defer { UserDefaults.standard.removeObject(forKey: "BlobWaveSide") }
                let r = MotionRig(game: true); Self.keep.append(r)
                r.brain.armBlendSpecies = blend
                if feature { r.brain.feature = .wings }
                r.brain.request(.wave)
                var w = Worst(), k = 0, saw = false
                for _ in 0..<(60 * 6) {
                    r.tick(); k += 1
                    if r.brain.armActive { saw = true; if k % 3 == 0 { check(r, label: "wave \(name) \(side)", into: &w, p: p) { inflate(r, side: $0) } } }
                    else if saw { break }
                }
                assertWorst(w, "wave \(name) side \(side)")
            }
        }
    }

    func testBandRidesTheHeldUpArms() {
        let p = prepared()
        let r = MotionRig(game: true); Self.keep.append(r)
        var w = Worst()
        for i in 0..<240 {
            r.brain.driveExcited(sim: r.sim, skinner: r.skinner, dt: 1.0 / 60, level: 0.4 + 0.6 * Float(sin(Double(i) * 0.03)).magnitude, phase: Float(i) * 0.1)
            r.sim.step()
            if i % 8 == 0 { check(r, label: "held", into: &w, p: p) { inflate(r, side: $0) } }
        }
        r.brain.endExcited()
        assertWorst(w, "held up")
    }

    /// Every move of ArmCapTests' list that draws the walking capsule (plus the rest between them).
    func testBandRidesEveryArmMove() {
        defer { DecorField.shared.clear() }
        let p = prepared()
        func idle(_ k: IdleKind) -> (MotionRig) -> Void { { r in r.brain.idleForced = true; _ = r.brain.idleStart(k, r.sim) } }
        var moves: [(String, Float, (MotionRig) -> Void, Bool)] = [
            ("walk", 7, { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) }, false),
            ("run", 10, idle(.run), false), ("jacks", 14, idle(.jacks), false), ("zoomies", 12, idle(.zoomies), false), ("belly slide", 12, idle(.slide), false),
            ("hop-scoot", 8, idle(.scoot), false), ("stumble", 10, idle(.stumble), false), ("sit", 14, idle(.sit), false), ("look", 14, idle(.look), false),
            ("sleep roll", 20, { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sleep, r.sim); r.brain.sleep.hold = 2 }, false),
            ("sleep hand-hold", 20, { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sleep, r.sim); r.brain.sleep.hold = 5; r.brain.sleep.holdForce = true }, false),
            ("sleep hand-hold + cuddle", 20, { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sleep, r.sim); r.brain.sleep.hold = 5; r.brain.sleep.holdForce = true; r.brain.sleep.mode = .cuddle }, false),
            ("hop", 2, { $0.brain.startHopPlay(sim: $0.sim) }, false), ("name hop", 2, { $0.brain.startNameHop($0.sim, $0.skinner) }, false),
            ("flip clean", 4, { $0.brain.startFlip(sim: $0.sim) }, false), ("faceplant", 5, { $0.brain.startFlip(sim: $0.sim, fail: true) }, false),
        ]
        for (n, k) in [("skip-hop", IdleKind.skipHop), ("hopscotch", .hopscotch), ("mid-leg spin", .legSpin), ("bounce-trot", .trot), ("stop and look", .stopLook), ("jump for joy", .joy),
                       ("giggle", .giggle), ("startle hop", .startle), ("big sigh", .sigh), ("hmph puff", .hmph), ("shake", .shake), ("lie down", .lieDown), ("chirp", .chirp),
                       ("window walk", .window), ("tail spin", .tail), ("flop", .flop), ("bounce", .bounce), ("stretch", .stretch), ("peek", .peek), ("sway (show dance)", .sway)] {
            moves.append((n, 10, idle(k), false))
        }
        for (n, kind, move, at) in [("decor: beanbag", DecorKind.beanbag, IdleKind.decorSit, SIMD2<Float>(1.1, 0.9)), ("decor: cushion", .cushion, .decorSit, SIMD2(-1.1, 0.9)),
                                   ("decor: plant boop", .plant, .decorBoop, SIMD2(1.1, 0.9)), ("decor: kick ball", .ball, .decorKick, SIMD2(0.9, 0.9)),
                                   ("decor: mat hop", .bouncymat, .decorHop, SIMD2(-1.1, 0.9)), ("decor: toy box", .toybox, .decorPeek, SIMD2(1.1, 0.9))] {
            moves.append((n, 22, { FeetAttachTests.decorStart($0, kind, at, move) }, true))
        }
        var all = Worst()
        for (name, secs, start, field) in moves {
            let r = MotionRig(game: true); Self.keep.append(r)
            r.brain.seed = 11; r.brain.amplitude = 1
            start(r)
            var w = Worst(), k = 0
            r.run(secs, until: { r.brain.idleState.kind == nil && r.t > 1 && !name.hasPrefix("walk") && !name.hasPrefix("hop") && !name.hasPrefix("name") && !name.hasPrefix("flip") && !name.hasPrefix("faceplant") && !name.hasPrefix("window") && !name.hasPrefix("decor") }) {
                if field { DecorField.shared.tick(dt: 1.0 / 60) }
                k += 1
                if k % 5 == 0 { self.check(r, label: name, into: &w, p: p) { self.inflate(r, side: $0) } }
            }
            MotionLog.write(String(format: "WRIST move %@: %d samples, centre %.4f, angle %.2f, minGap %.4f, inner %.4f, station %.2f..%.2f", name, w.samples, w.centre, w.angle, w.minGap, w.maxInner, w.tLo, w.tHi))
            all.samples += w.samples; all.skipped += w.skipped; all.tucked += w.tucked
            if w.centre > all.centre { all.centre = w.centre; all.whereCentre = w.whereCentre }
            if w.angle > all.angle { all.angle = w.angle; all.whereAngle = w.whereAngle }
            if w.minGap < all.minGap { all.minGap = w.minGap; all.whereGap = w.whereGap }
            if w.maxInner > all.maxInner { all.maxInner = w.maxInner; all.whereInner = w.whereInner }
            all.tLo = min(all.tLo, w.tLo); if w.tHi > all.tHi { all.tHi = w.tHi; all.whereT = w.whereT }
        }
        assertWorst(all, "every arm move")
    }
}
