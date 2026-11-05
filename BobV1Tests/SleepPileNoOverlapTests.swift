//
//  SleepPileNoOverlapTests.swift
//  Night capture: three Jelbies asleep on the rug, two placed one in front of the other (along z), overlapped by half a body. A lying body is longer along
//  its lie axis than it is wide, so a circular pile spacing is not enough. Every pair of lying footprints (ellipses at the rendered position and heading)
//  must stay apart on every frame, in an open room and with the x row blocked by decor, through the toss-and-turn fidgets and drifts.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepPileNoOverlapTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let logPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/5a467ba3-0e07-4f0a-81a4-9f51bd9e9c14/scratchpad/sleeppile.log"
    static func log(_ s: String) {
        NSLog("SLEEPPILE %@", s)
        guard let d = (s + "\n").data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: URL(fileURLWithPath: logPath)) }
    }

    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        DayClock.shared.forcedHour = 23
    }
    override func tearDown() {
        DayClock.shared.forcedHour = 12
        DecorField.shared.clear()
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// The footprint the test holds every pair to: the DRAWN body's measured reach about its soft-body centroid in the heading frame (max over 3 seeds x 120 s with
    /// every fidget: 0.70 along the heading, 0.76 across), + 0.02 / 0.01. Independent of the constants the pile code uses.
    static let halfLen: Float = 0.72, halfWid: Float = 0.77

    /// One lying footprint at a frame: the body centre on the floor, the heading, and the measured extents of the soft body about it.
    struct Foot { var c: SIMD2<Float>, yaw: Float, fwdMax: Float, fwdMin: Float, rightMax: Float, rightMin: Float }

    /// Extents of the DRAWN (skinned) body about its soft-body centroid, in the heading frame.
    static func foot(_ a: JellyActor, _ b: BlobBrain, _ dyn: inout [Float]) -> Foot {
        let c = a.sim.centroid()
        let f = SIMD2<Float>(sinf(b.yaw), cosf(b.yaw)), r = SIMD2<Float>(cosf(b.yaw), -sinf(b.yaw))
        dyn.withUnsafeMutableBufferPointer { a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: $0.baseAddress!) }
        var fm: Float = -9, fn: Float = 9, rm: Float = -9, rn: Float = 9
        for i in 0..<MotionRig.renderMesh.vertexCount {
            let d = SIMD2(dyn[6 * i] - c.x, dyn[6 * i + 2] - c.z)
            let u = simd_dot(d, f), v = simd_dot(d, r)
            fm = max(fm, u); fn = min(fn, u); rm = max(rm, v); rn = min(rn, v)
        }
        return Foot(c: SIMD2(c.x, c.z), yaw: b.yaw, fwdMax: fm, fwdMin: fn, rightMax: rm, rightMin: rn)
    }

    /// Metric clearance between two footprint ellipses (semi-axes `hl` along the heading, `hw` across): smallest boundary-to-boundary distance in metres,
    /// negative when they intersect.
    static func metricGap(_ a: Foot, _ b: Foot, hl: Float, hw: Float) -> Float {
        let inter = gap(a, b, hl: hl, hw: hw) < 0
        func pts(_ e: Foot) -> [SIMD2<Float>] {
            (0..<120).map { k in
                let t = Float(k) * 2 * .pi / 120
                return e.c + SIMD2(cosf(e.yaw), -sinf(e.yaw)) * (hw * cosf(t)) + SIMD2(sinf(e.yaw), cosf(e.yaw)) * (hl * sinf(t))
            }
        }
        var m: Float = .infinity
        let pb = pts(b)
        for p in pts(a) { for q in pb { m = min(m, simd_distance(p, q)) } }
        return inter ? -m : m
    }

    /// Gap between two footprint ellipses (semi-axes `hl` along the heading, `hw` across), as a fraction of the ellipse size: > 0 apart, <= 0 intersecting.
    /// Boundary points of each are tested against the other's normalised radius.
    static func gap(_ a: Foot, _ b: Foot, hl: Float, hw: Float) -> Float {
        func local(_ e: Foot, _ p: SIMD2<Float>) -> SIMD2<Float> {
            let d = p - e.c
            return SIMD2(simd_dot(d, SIMD2(cosf(e.yaw), -sinf(e.yaw))) / hw, simd_dot(d, SIMD2(sinf(e.yaw), cosf(e.yaw))) / hl)
        }
        var m: Float = .infinity
        for (p, q) in [(a, b), (b, a)] {
            for k in 0..<180 {
                let t = Float(k) * 2 * .pi / 180
                let w = p.c + SIMD2(cosf(p.yaw), -sinf(p.yaw)) * (hw * cosf(t)) + SIMD2(sinf(p.yaw), cosf(p.yaw)) * (hl * sinf(t))
                m = min(m, simd_length(local(q, w)))          // < 1 = the boundary point of p is inside q
            }
        }
        return m - 1
    }

    struct Run { var worst: (Foot, Foot)?, maxOff: Float = 0, minGap: Float = .infinity, minAt = -1, pair = "", fwd: ClosedRange<Float> = 0...0, right: ClosedRange<Float> = 0...0, spots: [SIMD2<Float>] = [] }

    /// Three sleepers; `block` places solid decor at both ends of the first sleeper's x row once he lies down.
    private func run(seed: UInt64, block: Bool, secs: Float, hl: Float, hw: Float) -> Run? {
        let r = RaceTripTests.Room()
        Self.keep.append(r)
        let brains = r.actors.compactMap(\.brain)
        for a in r.actors {
            guard let b = a.brain else { continue }
            b.sleepEnabled = true; b.autonomy = true
            b.seed = seed &+ UInt64(a.id) &* 7919
            b.socialOthers = { [unowned r] in r.actors.compactMap(\.brain) }
        }
        func step() {
            for b in brains { b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
            r.step()
        }
        var out = Run()
        var dyn = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        var n = 0
        if block {          // jelly 0 lies down alone first, then decor closes both ends of his x row, then the others go to bed
            let b0 = brains[0]
            b0.idleForced = true
            guard b0.idleStart(.sleep, r.actors[0].sim) else { return nil }
            b0.sleep.hold = 600
            while !b0.isNapping && n < 40 * 60 { step(); n += 1 }
            let s = b0.sleep.spot
            DecorField.shared.set([PlacedDecor(uid: 91, kind: .plant, x: s.x - 2.0, z: s.y), PlacedDecor(uid: 92, kind: .plant, x: s.x + 2.0, z: s.y)])
        }
        r.care.bedtimeAll()
        n = 0
        while !brains.allSatisfy({ $0.isNapping }) && n < 90 * 60 {
            step(); n += 1
            if brains.allSatisfy({ $0.isLying }) { checkFrame(r, brains, hl, hw, &dyn, &out, n) }
        }
        guard brains.allSatisfy({ $0.isNapping }) else { return nil }
        var fMin: Float = 9, fMax: Float = -9, rMin: Float = 9, rMax: Float = -9
        for k in 0..<Int(secs * 60) {
            step()
            checkFrame(r, brains, hl, hw, &dyn, &out, 100000 + k)
            for (i, a) in r.actors.enumerated() {
                let ft = Self.foot(a, brains[i], &dyn)
                fMin = min(fMin, ft.fwdMin); fMax = max(fMax, ft.fwdMax); rMin = min(rMin, ft.rightMin); rMax = max(rMax, ft.rightMax)
            }
        }
        out.fwd = fMin...fMax; out.right = rMin...rMax
        out.spots = brains.map { $0.sleep.spot }
        return out
    }
    private func checkFrame(_ r: RaceTripTests.Room, _ brains: [BlobBrain], _ hl: Float, _ hw: Float, _ dyn: inout [Float], _ out: inout Run, _ n: Int) {
        let fs = r.actors.enumerated().map { Self.foot($1, brains[$0], &dyn) }
        for (i, f) in fs.enumerated() { out.maxOff = max(out.maxOff, simd_distance(f.c, brains[i].sleep.spot)) }
        for i in 0..<fs.count { for j in (i + 1)..<fs.count {
            let g = Self.gap(fs[i], fs[j], hl: hl, hw: hw)
            if g < out.minGap { out.worst = (fs[i], fs[j]); out.minGap = g; out.minAt = n; out.pair = "\(i)-\(j) st\(brains[i].sleep.stage)/\(brains[j].sleep.stage) d\(String(format: "%.2f", simd_distance(fs[i].c, fs[j].c)))" }
        } }
    }

    func testLyingFootprintsNeverIntersect() {
        let hl = Self.halfLen, hw = Self.halfWid
        for block in [false, true] {
            for seed in [1, 2, 3] as [UInt64] {
                guard let o = run(seed: seed, block: block, secs: 120, hl: hl, hw: hw) else { XCTFail("never all asleep"); continue }
                let mg = o.worst.map { Self.metricGap($0.0, $0.1, hl: hl, hw: hw) } ?? 0
                Self.log(String(format: "%@ seed %d: minGap %.3f (%.3f m) maxCentroidOffFromSpot %.2f at %d pair %@ | extents fwd %.2f...%.2f right %.2f...%.2f | spots %@", block ? "BLOCKED" : "OPEN", Int(seed), o.minGap, mg, o.maxOff, o.minAt, o.pair, o.fwd.lowerBound, o.fwd.upperBound, o.right.lowerBound, o.right.upperBound, o.spots.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) }.joined(separator: " ")))
                XCTAssertGreaterThanOrEqual(mg, 0, "\(block ? "blocked" : "open") seed \(seed): footprints intersect (pair \(o.pair), frame \(o.minAt))")
            }
        }
    }
}
