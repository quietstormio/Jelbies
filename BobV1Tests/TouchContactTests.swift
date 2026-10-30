//
//  TouchContactTests.swift
//  Touching Jelbies (2026-10-30): two soft bodies that press must flatten against each other, never pass through (ContactMetric measures the DRAWN skins), and
//  nobody goes through Pip's tail. Every touch social is run between Pip (the dino tail) and Moss, in both seats, and the deepest overlap and the deepest
//  tail intrusion are logged (MOTION_LOG) next to the bounds the touches must keep. TOUCH_ONLY=kind,kind limits the kinds; TOUCH_LOG_ONLY=1 logs without asserting
//  (the before / after numbers of the round).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchContactTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }
    override func tearDown() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }

    /// Every social where the bodies meet.
    static let touchKinds: [SocialKind] = [.boop, .bump, .nuzzle, .chestBump, .highFive, .hum, .cheekSquish, .noseBoop, .backToBack, .bellyBounce,
                                           .cuddleLean, .swayHug, .leapfrog, .sitTogether, .hopAlong, .peekaboo, .whisperGiggle, .mirrorDance]
    /// The deepest a drawn body may sink into the other (world units; a body is ~1.0 wide): a small squish, not a pass-through. Before the contact round the worst touches sank 0.2 (hugs), 0.47 (back to back) and 0.55 (leapfrog).
    /// Into Pip's tail tube: the settled part of a touch (after 5 s) and the whole run (the turn of a back to back, a landing next to him: the tail sweeps through the other for a few frames; before: 0.28).
    static let depthBound: Float = 0.10, tailLateBound: Float = 0.18, tailBound: Float = 0.26

    struct Result { var depthLate: Float = 0, tailLate: Float = 0, tailPart = "-", simGap: Float = .infinity, part = "-", depth: Float = 0, tail: Float = 0, depthAt: Float = 0, tailAt: Float = 0, seconds: Float = 0, done = false }

    /// Runs `kind` between rig 0 and rig 1 (pip: which seat Pip has) and measures every 3rd frame.
    func run(_ kind: SocialKind, pipSeat: Int, seed: UInt64 = 31, maxSeconds: Float = 40, flipped: Bool = false) -> Result {
        let lab = SocialTests.Lab(n: 2, positions: flipped ? [SIMD2(0.7, 0.9), SIMD2(-1.0, 0.6)] : [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9)], seed: seed)          // (flipped: the first one starts on the right, so the hops go the other way)
        let rm = MotionRig.renderMesh
        for (i, r) in lab.rigs.enumerated() {
            r.renderSamples = false
            r.brain.feature = i == pipSeat ? .spines : .daisy
            r.skinner.configureTail(rm); r.skinner.tailOn = i == pipSeat; r.brain.skinnerRef = r.skinner
        }
        let tailFirst = rm.armCapsule?.tailFirst ?? -1
        let skip = tailFirst >= 0 ? tailFirst..<(tailFirst + TailBean.vertexCount) : 0..<0
        let eggEnd = rm.armCapsule?.firstVertex.min() ?? rm.vertexCount
        var res = Result()
        _ = lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim)
        var f = 0
        while f < Int(maxSeconds * 60) {
            lab.tick(watching: false)
            f += 1
            if f % 3 == 0 {
                for r in lab.rigs { r.render() }
                let a = lab.rigs[0], b = lab.rigs[1]
                let (d, v) = a.dyn.withUnsafeBufferPointer { pa in b.dyn.withUnsafeBufferPointer { pb -> (Float, Int) in
                    let x = ContactMetric.deepest(of: pa.baseAddress!, into: pb.baseAddress!, vertices: rm.vertexCount, skip: skip, surface: eggEnd), y = ContactMetric.deepest(of: pb.baseAddress!, into: pa.baseAddress!, vertices: rm.vertexCount, skip: skip, surface: eggEnd)
                    return x.depth >= y.depth ? (x.depth, x.vertex) : (y.depth, y.vertex) } }
                let ca = a.sim.centroid(), cb = b.sim.centroid(), dd = cb - ca, dl = simd_length(dd)
                if dl > 0.01 { let u = dd / dl; res.simGap = min(res.simGap, dl - PeerContact.support(a.sim, ca, u) - PeerContact.support(b.sim, cb, -u)) }
                if f > 300 { res.depthLate = max(res.depthLate, d) }          // (after 5 s: the settled part of the touch, past the turns and the landings)
                if d > res.depth { res.depth = d; res.depthAt = Float(f) / 60; res.part = Self.part(v, rm) }
                if tailFirst >= 0 {
                    let p = lab.rigs[pipSeat], o = lab.rigs[1 - pipSeat]
                    let t = p.dyn.withUnsafeBufferPointer { pp in o.dyn.withUnsafeBufferPointer { po in ContactMetric.tailDeepest(tail: pp.baseAddress!, first: tailFirst, other: po.baseAddress!, vertices: rm.vertexCount, skip: skip) } }
                    if f > 300 { res.tailLate = max(res.tailLate, t.depth) }
                    if t.depth > res.tail { res.tail = t.depth; res.tailAt = Float(f) / 60; res.tailPart = Self.part(t.vertex, rm) }
                }
            }
            if !lab.anySocial && f > 10 { res.done = true; break }
        }
        res.seconds = Float(f) / 60
        return res
    }

    /// Which block of the render mesh a vertex belongs to.
    static func part(_ v: Int, _ rm: RenderMesh) -> String {
        guard let cap = rm.armCapsule, v >= 0 else { return "?" }
        if v < cap.firstVertex.min()! { return "egg" }
        for side in [-1, 1] {
            let f = cap.first(side: side)
            if v < f + ArmCapsule.vertexCount { return "arm" }
            if v < f + ArmCapsule.vertexCount + FootBean.vertexCount { return "foot" }
        }
        return "other"
    }

    func testEveryTouchSocial() {
        let env = ProcessInfo.processInfo.environment
        let only = env["TOUCH_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let logOnly = env["TOUCH_LOG_ONLY"] != nil
        PeerContact.enabled = env["TOUCH_OFF"] == nil          // TOUCH_OFF=1: the bodies as they were before the contact round (the baseline numbers)
        defer { PeerContact.enabled = true }
        for kind in Self.touchKinds where only?.contains(kind.rawValue) ?? true {
            for seat in 0..<2 {
              for flipped in [false, true] where !flipped || kind == .leapfrog || kind == .backToBack {
                let r = run(kind, pipSeat: seat, flipped: flipped)
                MotionLog.write(String(format: "TOUCH %@ pip=%d\(flipped ? "f" : ""): depth %.3f %@ (t %.1f) tail %.3f %@ (t %.1f) simGap %.3f late(>5s) depth %.3f tail %.3f done=%d in %.1f s", kind.rawValue, seat, r.depth, r.part, r.depthAt, r.tail, r.tailPart, r.tailAt, r.simGap, r.depthLate, r.tailLate, r.done ? 1 : 0, r.seconds))
                if !logOnly {
                    XCTAssertLessThanOrEqual(r.depth, Self.depthBound, "\(kind) pip=\(seat): bodies stay out of each other")
                    XCTAssertLessThanOrEqual(r.tail, Self.tailBound, "\(kind) pip=\(seat): nobody goes through the tail")
                    XCTAssertLessThanOrEqual(r.tailLate, Self.tailLateBound, "\(kind) pip=\(seat): and none after it has settled")
                }
              }
            }
        }
    }

    // MARK: sleep, settling and the cost of contact

    /// Two Jelbies standing close (a little inside each other to start): they press into a contact patch, settle, and then both sims are at rest (a stage skips their step)
    /// and the contact does not wake them again.
    func testTouchingStandersSettleAndStaySettled() {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-0.5, 0.8), SIMD2(0.5, 0.8)], seed: 5)
        for r in lab.rigs { r.renderSamples = false; r.brain.autonomy = false }
        for _ in 0..<(60 * 10) { lab.tick(watching: false) }
        let epochs = lab.rigs.map { $0.sim.epoch }
        for _ in 0..<(60 * 3) { lab.tick(watching: false) }
        for (i, r) in lab.rigs.enumerated() {
            XCTAssertTrue(r.sim.isSettled, "rig \(i) settled while pressed against his neighbour (peerDepth \(r.sim.peerDepth), planes \(r.sim.planeCount))")
            XCTAssertEqual(r.sim.epoch, epochs[i], "rig \(i): the contact does not keep waking him")
        }
        let ca = lab.rigs[0].sim.centroid(), cb = lab.rigs[1].sim.centroid()
        let gap = simd_length(cb - ca) - PeerContact.support(lab.rigs[0].sim, ca, simd_normalize(cb - ca)) - PeerContact.support(lab.rigs[1].sim, cb, -simd_normalize(cb - ca))
        MotionLog.write(String(format: "TOUCH settle: gap %.3f", gap))
        XCTAssertGreaterThan(gap, -0.03, "pressed, not inside")
    }

    /// Far apart, or close but not touching: no plane does any work, and nobody is woken.
    func testNoContactWorkWithoutOverlap() {
        let a = MotionRig(game: true), b = MotionRig(game: true)
        a.sim.teleport(toXZ: SIMD2(-2, 0)); b.sim.teleport(toXZ: SIMD2(2, 0))
        for _ in 0..<60 { a.sim.step(); b.sim.step() }
        let e = [a.sim.epoch, b.sim.epoch]
        PeerContact.prepare([a.sim, b.sim], skins: [nil, nil])
        XCTAssertEqual(a.sim.planeCount + b.sim.planeCount, 0, "4 m apart: nothing to do")
        // a small gap (inside the contact band): a plane (the arms stop at it) but no push and no wake
        b.sim.teleport(toXZ: SIMD2(-2 + 1.55, 0))
        for _ in 0..<60 { a.sim.step(); b.sim.step() }
        let ca = a.sim.centroid(), cb = b.sim.centroid()
        let gap = simd_length(cb - ca) - PeerContact.support(a.sim, ca, simd_normalize(cb - ca)) - PeerContact.support(b.sim, cb, -simd_normalize(cb - ca))
        XCTAssertGreaterThan(gap, 0, "set up: they are apart (gap \(gap))")
        let e2 = [a.sim.epoch, b.sim.epoch]
        PeerContact.prepare([a.sim, b.sim], skins: [nil, nil])
        XCTAssertEqual([a.sim.epoch, b.sim.epoch], e2, "a plane without overlap wakes nobody")
        XCTAssertEqual(e.count, 2)
    }

    /// A settled body that is pressed into wakes (epoch), is dented, and settles again once the presser is gone.
    func testAPressWakesASleeperAndHeSettlesAgain() {
        let a = MotionRig(game: true), b = MotionRig(game: true)
        a.sim.teleport(toXZ: SIMD2(-2, 0)); b.sim.teleport(toXZ: SIMD2(0, 0))
        for _ in 0..<300 { a.sim.step(); b.sim.step() }
        XCTAssertTrue(b.sim.isSettled, "the sleeper is settled")
        let e = b.sim.epoch
        // push A into him: a hop of the body along +x (a launch), contact prepared every step like the stage
        a.sim.teleport(toXZ: SIMD2(-1.2, 0))
        var woke = false
        for _ in 0..<60 {
            PeerContact.prepare([a.sim, b.sim], skins: [nil, nil])
            if b.sim.epoch != e { woke = true }
            a.sim.step(); b.sim.step()
        }
        XCTAssertTrue(woke, "pressed into: he wakes")
        // the presser leaves: contact is gone, and the dented body is soon at rest again (a stage skips his step)
        a.sim.teleport(toXZ: SIMD2(-3, 0))
        for _ in 0..<(60 * 8) { PeerContact.prepare([a.sim, b.sim], skins: [nil, nil]); a.sim.step(); b.sim.step() }
        XCTAssertEqual(b.sim.planeCount, 0, "nothing touches him now")
        XCTAssertTrue(b.sim.isSettled && a.sim.isSettled, "both settle again once the contact is gone (KE \(b.sim.kineticEnergy()), drift \(b.sim.peerDrift))")
    }

    /// The cost of contact: one fixed step of three Jelbies pressed together (planes on every pair, Pip's tail + swell spheres on the other two) against the same step with contact off.
    /// Each timed step starts from the same overlapping spots (teleported back, untimed), so the contact has real work to do every time.
    func testContactCostThreeTouching() throws {
        guard ProcessInfo.processInfo.environment["TOUCH_PERF"] != nil else { throw XCTSkip("TOUCH_PERF not set") }
        let rm = MotionRig.renderMesh
        let rigs = (0..<3).map { _ in MotionRig(game: true) }
        rigs[0].brain.feature = .spines; rigs[0].skinner.configureTail(rm); rigs[0].skinner.tailOn = true
        let spots: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.8, 0), SIMD2(0.4, 0.7)]
        let sims = rigs.map { $0.sim }, skins = rigs.map { Optional($0.skinner) }
        func run(_ on: Bool) -> (prep: Double, step: Double, planes: Int, spheres: Int, listed: Int) {
            PeerContact.enabled = on
            var prep = 0.0, step = 0.0, planes = 0, spheres = 0, listed = 0
            let n = 300
            for k in 0..<(n + 60) {
                for (i, r) in rigs.enumerated() { r.sim.teleport(toXZ: spots[i]) }
                rigs[0].render()
                let t0 = CACurrentMediaTime(); PeerContact.prepare(sims, skins: skins); let t1 = CACurrentMediaTime()
                for s in sims { s.step() }
                let t2 = CACurrentMediaTime()
                if k >= 60 { prep += t1 - t0; step += t2 - t1; planes += sims.reduce(0) { $0 + $1.planeCount }; spheres += sims.reduce(0) { $0 + $1.sphereTotal }; listed += sims.reduce(0) { $0 + $1.sphereListCount } }
            }
            return (prep / Double(n) * 1000, step / Double(n) * 1000, planes / n, spheres / n, listed / n)
        }
        let off = run(false), on = run(true)
        PeerContact.enabled = true
        MotionLog.write(String(format: "TOUCH PERF three pressed together: prepare %.4f ms (off %.4f); the 3 sim steps %.3f ms (off %.3f) per fixed step; per step %d planes, %d tail spheres, %d particles listed for them", on.prep, off.prep, on.step, off.step, on.planes, on.spheres, on.listed))
    }

    /// Diagnostic: a time series of one social between Pip (seat 0 or 1) and Moss (TOUCH_DIAG = kind, TOUCH_SEAT = Pip's seat).
    func testSeriesDiagnostic() throws {
        let env = ProcessInfo.processInfo.environment
        guard let kindName = env["TOUCH_DIAG"], let kind = SocialKind(rawValue: kindName) else { throw XCTSkip("TOUCH_DIAG not set") }
        let seat = Int(env["TOUCH_SEAT"] ?? "0") ?? 0
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9)], seed: 31)
        let rm = MotionRig.renderMesh
        let eggEnd = rm.armCapsule!.firstVertex.min()!, tf = rm.armCapsule!.tailFirst
        let skip = tf..<(tf + TailBean.vertexCount)
        for (i, r) in lab.rigs.enumerated() { r.renderSamples = false; r.brain.feature = i == seat ? .spines : .daisy; r.skinner.configureTail(rm); r.skinner.tailOn = i == seat; r.brain.skinnerRef = r.skinner }
        _ = lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim)
        for f in 1...(60 * 14) {
            lab.tick(watching: false)
            guard f % 6 == 0 else { continue }
            for r in lab.rigs { r.render() }
            let a = lab.rigs[0], b = lab.rigs[1]
            let ca = a.sim.centroid(), cb = b.sim.centroid()
            let d = a.dyn.withUnsafeBufferPointer { pa in b.dyn.withUnsafeBufferPointer { pb in ContactMetric.deepest(of: pa.baseAddress!, into: pb.baseAddress!, vertices: rm.vertexCount, skip: skip, surface: eggEnd) } }
            let e = b.dyn.withUnsafeBufferPointer { pb in a.dyn.withUnsafeBufferPointer { pa in ContactMetric.deepest(of: pb.baseAddress!, into: pa.baseAddress!, vertices: rm.vertexCount, skip: skip, surface: eggEnd) } }
            let p = lab.rigs[seat], o = lab.rigs[1 - seat]
            let t = p.dyn.withUnsafeBufferPointer { pp in o.dyn.withUnsafeBufferPointer { po in ContactMetric.tailDeepest(tail: pp.baseAddress!, first: tf, other: po.baseAddress!, vertices: rm.vertexCount, skip: skip) } }
            if f == (Int(env["TOUCH_DUMP_T"] ?? "") ?? 300) {
                for (x, y, tag) in [(a, b, "A->B"), (b, a, "B->A")] {
                    let dp = x.dyn.withUnsafeBufferPointer { px in y.dyn.withUnsafeBufferPointer { py in ContactMetric.deepest(of: px.baseAddress!, into: py.baseAddress!, vertices: rm.vertexCount, skip: skip, surface: eggEnd) } }
                    guard dp.vertex >= 0 else { continue }
                    let q = SIMD3(x.dyn[6 * dp.vertex], x.dyn[6 * dp.vertex + 1], x.dyn[6 * dp.vertex + 2])
                    var best = Float.infinity, bw = 0
                    for w in stride(from: 0, to: eggEnd, by: 2) { let r = SIMD3(y.dyn[6 * w], y.dyn[6 * w + 1], y.dyn[6 * w + 2]); let l = simd_length_squared(r - q); if l < best { best = l; bw = w } }
                    let r = SIMD3(y.dyn[6 * bw], y.dyn[6 * bw + 1], y.dyn[6 * bw + 2]), n = SIMD3(y.dyn[6 * bw + 3], y.dyn[6 * bw + 4], y.dyn[6 * bw + 5])
                    MotionLog.write(String(format: "DUMP %@ depth %.3f vertex %d rest (%.2f %.2f %.2f) at (%.2f %.2f %.2f); nearest other vertex %d rest (%.2f %.2f %.2f) at (%.2f %.2f %.2f) dist %.3f normal (%.2f %.2f %.2f)", tag, dp.depth, dp.vertex, rm.rest[3 * dp.vertex], rm.rest[3 * dp.vertex + 1], rm.rest[3 * dp.vertex + 2], q.x, q.y, q.z, bw, rm.rest[3 * bw], rm.rest[3 * bw + 1], rm.rest[3 * bw + 2], r.x, r.y, r.z, best.squareRoot(), n.x, n.y, n.z))
                }
            }
            if f == (Int(env["TOUCH_DUMP_T"] ?? "") ?? 300), t.vertex >= 0 {
                let v = SIMD3(o.dyn[6 * t.vertex], o.dyn[6 * t.vertex + 1], o.dyn[6 * t.vertex + 2])
                let rings = p.dyn.withUnsafeBufferPointer { ContactMetric.tailRings($0.baseAddress!, first: tf) }
                let near = rings.min { simd_distance(SIMD3($0.x, $0.y, $0.z), v) - $0.w < simd_distance(SIMD3($1.x, $1.y, $1.z), v) - $1.w }!
                let ps = o.skinner.peerSpheres.min { simd_distance(SIMD3($0.x, $0.y, $0.z), v) - $0.w < simd_distance(SIMD3($1.x, $1.y, $1.z), v) - $1.w }
                MotionLog.write(String(format: "TAILDUMP vertex %d (%@) at (%.2f %.2f %.2f) ring sphere c (%.2f %.2f %.2f) r %.3f dist %.3f | peerSpheres %d, nearest c %@ r %.3f", t.vertex, Self.part(t.vertex, rm), v.x, v.y, v.z, near.x, near.y, near.z, near.w, simd_distance(SIMD3(near.x, near.y, near.z), v), o.skinner.peerSpheres.count, ps.map { String(format: "(%.2f %.2f %.2f) dist %.3f", $0.x, $0.y, $0.z, simd_distance(SIMD3($0.x, $0.y, $0.z), v)) } ?? "none", ps?.w ?? 0))
            }
            func name(_ r: MotionRig) -> String { "\(r.brain.idleState.kind.map { "\($0)" } ?? (r.brain.activity == .walking ? "walk" : "-"))" }
            MotionLog.write(String(format: "SERIES t %.1f A(%@) (%.2f %.2f %.2f) B(%@) (%.2f %.2f %.2f) planes %d/%d depth A->B %.3f %@ B->A %.3f %@ tail %.3f %@ aside %.2f spheres %d->%d listed %d behind %@ act %@ yaw %.2f pos (%.2f %.2f) hasTail %d tailOn %d held %d skinPlanes %d/%d armFirst %d/%d", Float(f) / 60, name(a), ca.x, ca.y, ca.z, name(b), cb.x, cb.y, cb.z, a.sim.planeCount, b.sim.planeCount, d.depth, Self.part(d.vertex, rm), e.depth, Self.part(e.vertex, rm), t.depth, Self.part(t.vertex, rm), p.brain.tailPlay.aside, p.skinner.tailSpheres.count, o.sim.sphereTotal, o.sim.sphereListCount, "\(String(describing: p.brain.partnerBehind()))", "\(p.brain.activity)", p.brain.yaw, p.brain.position.x, p.brain.position.y, p.brain.hasTailToPlay ? 1 : 0, p.skinner.tailOn ? 1 : 0, p.brain.held ? 1 : 0, a.skinner.peerPlanes.count, b.skinner.peerPlanes.count, a.skinner.armFirst.min() ?? -1, b.skinner.armFirst.min() ?? -1))
        }
    }
}
