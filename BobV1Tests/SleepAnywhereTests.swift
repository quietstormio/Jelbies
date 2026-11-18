//
//  SleepAnywhereTests.swift
//  Sleep anywhere (owner 2026-11-17: "they don't have to lineup, they can sleep where ever ... they get buggy and run into each other when trying to line up").
//  At bedtime each Jelmiko lies down where he stands; only when that spot is not fair does he walk, to the nearest fair one (under about 1 u). Measured on the
//  stage's own wiring (`SocialTests.Lab`: keepApart + peers), the Bedtime order (`NightRestTuning.sendToBed`), against the old row / rug pile (`SleepTuning.anywhere = false`).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepAnywhereTests: XCTestCase {
    private var savedHour: Double?
    private var savedAnywhere = true
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        SleepOrder.reset()
        savedHour = DayClock.shared.forcedHour
        DayClock.shared.forcedHour = 23
        savedAnywhere = SleepTuning.anywhere
    }
    override func tearDown() {
        SleepTuning.anywhere = savedAnywhere
        DayClock.shared.forcedHour = savedHour
        DecorField.shared.clear()
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset()
    }

    // MARK: scenarios

    /// kind 0 = spread (all fair), 1 = crowded (two stand too close to both lie), 2 = decor (one stands right beside a plant).
    struct Scene { var name: String; var starts: [SIMD2<Float>]; var decorAt: SIMD2<Float>? }

    private static func rng(_ s: UInt64) -> () -> Float {
        var x = s &* 6364136223846793005 &+ 1442695040888963407
        return { x = x &* 6364136223846793005 &+ 1442695040888963407; return Float((x >> 40) & 0xFFFF) / 65535 }
    }
    /// A floor point clear of the bowls, the call spot and the table (the test's own check, independent of the brain's).
    private static func floorOK(_ p: SIMD2<Float>) -> Bool {
        guard abs(p.x) <= 2.1, p.y >= -1.5, p.y <= 1.5 else { return false }
        for s in [GameCamera.foodBowlSpot, GameCamera.waterBowlSpot, GameCamera.callSpot, RoomLayout.table.centre] where simd_distance(p, s) < 1.8 { return false }
        return true
    }
    static func scene(seed: UInt64, kind: Int, n: Int) -> Scene {
        let r = rng(seed &* 977)
        var pts: [SIMD2<Float>] = []
        var tries = 0
        while pts.count < n, tries < 4000 {
            tries += 1
            let p = SIMD2<Float>(-2.1 + 4.2 * r(), -1.5 + 3.0 * r())
            guard floorOK(p) else { continue }
            if pts.isEmpty { pts.append(p); continue }
            if kind == 1, pts.count == 1 {          // the second stands about 1.7 from the first: standing skins clear, lying footprints (1.81 across, 2.07 along) not
                let a = r() * 2 * Float.pi
                let q = pts[0] + SIMD2(cosf(a), sinf(a)) * 1.7
                if floorOK(q) { pts.append(q) }
                continue
            }
            if pts.allSatisfy({ simd_distance($0, p) >= 2.5 }) { pts.append(p) }
        }
        precondition(pts.count == n, "scene seed \(seed) kind \(kind) n \(n): no layout")
        let decor: SIMD2<Float>? = kind == 2 ? pts[n - 1] + SIMD2(0.7, 0) : nil
        return Scene(name: "seed\(seed)/kind\(kind)/n\(n)", starts: pts, decorAt: decor)
    }

    // MARK: one run

    struct Run {
        var starts: [SIMD2<Float>] = [], finals: [SIMD2<Float>] = []
        var walk: Float = 0, perWalk: [Float] = []
        var allAsleepAt: Float = .infinity
        var minGap: Float = .infinity, minGapAt: Float = 0
        var crossings: [String] = []
        var fairStart: [Bool] = []
        var offScreen = 0
        var nap = false
    }

    private static func points(_ r: MotionRig, _ dyn: inout [Float]) -> [SIMD2<Float>] {
        dyn.withUnsafeMutableBufferPointer { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: $0.baseAddress!) }
        return stride(from: 0, to: MotionRig.renderMesh.vertexCount, by: 3).map { SIMD2(dyn[6 * $0], dyn[6 * $0 + 2]) }
    }
    private static func hull(_ p: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let s = p.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lo: [SIMD2<Float>] = [], up: [SIMD2<Float>] = []
        for q in s { while lo.count >= 2, cross(lo[lo.count - 2], lo[lo.count - 1], q) <= 0 { lo.removeLast() }; lo.append(q) }
        for q in s.reversed() { while up.count >= 2, cross(up[up.count - 2], up[up.count - 1], q) <= 0 { up.removeLast() }; up.append(q) }
        return Array(lo.dropLast() + up.dropLast())
    }
    private static func inside(_ q: SIMD2<Float>, _ h: [SIMD2<Float>]) -> Bool {
        guard h.count >= 3 else { return false }
        for i in 0..<h.count {
            let a = h[i], b = h[(i + 1) % h.count]
            if (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x) < 0 { return false }
        }
        return true
    }
    /// Gap between two drawn skins seen from above (metres; negative = overlapping): the smallest vertex-to-vertex distance, negated when one body's outline holds a vertex of the other.
    static func skinGap(_ a: [SIMD2<Float>], _ b: [SIMD2<Float>]) -> Float {
        var m = Float.infinity
        for p in a { for q in b { m = min(m, simd_distance(p, q)) } }
        let ha = hull(a), hb = hull(b)
        let over = a.contains { inside($0, hb) } || b.contains { inside($0, ha) }
        return over ? -m : m
    }

    /// Bedtime for `scene` (`anywhere` = the new rule, else the old pile).
    func run(_ scene: Scene, anywhere: Bool, seed: UInt64 = 11, nap: Bool = false) -> Run {
        SleepTuning.anywhere = anywhere
        SleepOrder.reset()
        let n = scene.starts.count
        let lab = SocialTests.Lab(n: n, positions: scene.starts, quiet: true, seed: seed)
        SocialTests.keep.append(lab)
        let brains = lab.rigs.map(\.brain)
        for b in brains {
            b.sleepEnabled = true; b.watching = true
            b.idleNight = 1; b.idleDeepNight = 1
            b.idleState.cooldown = 0; b.restTimer = 0.5; b.socialBook.cooldown = 1e6
        }
        if let d = scene.decorAt { DecorField.shared.set([PlacedDecor(uid: 71, kind: .plant, x: d.x, z: d.y)]) }
        for _ in 0..<120 { lab.tick(watching: false) }
        var out = Run()
        out.starts = brains.map { $0.position }
        out.fairStart = brains.map { $0.sleepFairAnywhere($0.position) }
        var dyn = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        var traj = [[SIMD2<Float>]](repeating: [], count: n)
        var last = out.starts
        out.perWalk = [Float](repeating: 0, count: n)
        NightRestTuning.sendToBed(brains)
        var f = 0
        while f < 70 * 60 {
            lab.tick(watching: false); f += 1
            for (i, b) in brains.enumerated() {
                if !b.isLying { let d = simd_distance(b.position, last[i]); out.perWalk[i] += d; out.walk += d }
                last[i] = b.position; traj[i].append(b.position)
            }
            if f % 3 == 0 {
                let sk = lab.rigs.map { Self.points($0, &dyn) }
                for i in 0..<n { for j in (i + 1)..<n {
                    let g = Self.skinGap(sk[i], sk[j])
                    if g < out.minGap { out.minGap = g; out.minGapAt = Float(f) / 60 }
                } }
            }
            if brains.allSatisfy({ $0.isNapping }) { out.allAsleepAt = Float(f) / 60; break }
        }
        for _ in 0..<60 { lab.tick(watching: false) }
        out.finals = brains.map { $0.position }
        // nobody's walk crosses another's lying spot (a mover that starts inside a stayer's footprint only has to walk away from it)
        let yaw = brains[0].faceCameraYaw()
        for i in 0..<n { for j in 0..<n where i != j {
            let startsInside = BlobBrain.lieClash(out.starts[i] - out.finals[j], yawA: yaw, yawB: yaw, margin: 0)
            var prev = simd_distance(out.starts[i], out.finals[j])
            for p in traj[i] {
                let d = simd_distance(p, out.finals[j])
                if BlobBrain.lieClash(p - out.finals[j], yawA: yaw, yawB: yaw, margin: 0), !startsInside || d < prev - 0.03 { out.crossings.append("\(i) over \(j)'s spot at \(p)"); break }
                prev = d
            }
        } }
        for (i, p) in out.finals.enumerated() where abs(p.x) > 3.4 || p.y > 3.2 || p.y < -2.8 { out.offScreen += 1; _ = i }
        return out
    }

    private func check(_ s: Scene, _ o: Run, line: UInt = #line) {
        for i in 0..<o.finals.count {
            let moved = simd_distance(o.finals[i], o.starts[i])
            if o.fairStart[i], moved >= 0.2 { XCTFail("\(s.name): #\(i) stood on a fair spot but moved \(moved)", line: line) }
            XCTAssertLessThanOrEqual(moved, 1.2, "\(s.name): #\(i) walked \(moved) (nearest fair spot, never across the room)", line: line)
        }
        XCTAssertGreaterThanOrEqual(o.minGap, 0, "\(s.name): two skins touched/overlapped at \(o.minGapAt) s", line: line)
        XCTAssertTrue(o.crossings.isEmpty, "\(s.name): a walk crossed another's spot: \(o.crossings)", line: line)
        XCTAssertLessThan(o.allAsleepAt, 70, "\(s.name): not everybody fell asleep", line: line)
        // the finished lying bodies keep the gap (footprint ellipses, margin 0.15)
        for i in 0..<o.finals.count { for j in (i + 1)..<o.finals.count {
            XCTAssertFalse(BlobBrain.lieClash(o.finals[i] - o.finals[j], yawA: 0, yawB: 0, margin: 0.14), "\(s.name): \(i)/\(j) lie closer than the gap (\(simd_distance(o.finals[i], o.finals[j])))", line: line)
        } }
    }

    // MARK: the table

    func testScatteredThreeSixSeeds() {
        for seed in 1...6 as ClosedRange<UInt64> {
            let kind = Int(seed % 3)
            let s = Self.scene(seed: seed, kind: kind, n: 3)
            let o = run(s, anywhere: true)
            MotionLog.write("SLEEPANY new \(s.name) walk \(o.walk) per \(o.perWalk) gap \(o.minGap) asleep \(o.allAsleepAt) fairStart \(o.fairStart) moved \(zip(o.finals, o.starts).map { simd_distance($0, $1) })")
            check(s, o)
            if kind == 0 {
                for i in 0..<3 { XCTAssertLessThan(simd_distance(o.finals[i], o.starts[i]), 0.2, "\(s.name): #\(i) lies where he stood") }
                XCTAssertLessThan(o.walk, 0.4, "\(s.name): nobody walks when every spot is fair")
            } else {
                XCTAssertTrue(zip(o.finals, o.starts).contains { simd_distance($0, $1) > 0.1 }, "\(s.name): somebody had to move")
                XCTAssertTrue(zip(o.finals, o.starts).contains { simd_distance($0, $1) < 0.2 }, "\(s.name): the other one stays")
            }
        }
    }

    func testOneTwoAndThreePlusAGuest() {
        for (n, kind) in [(1, 0), (2, 0), (2, 1), (4, 0), (4, 1)] {
            let s = Self.scene(seed: 40 + UInt64(n * 7 + kind), kind: kind, n: n)
            let o = run(s, anywhere: true)
            MotionLog.write("SLEEPANY new \(s.name) walk \(o.walk) gap \(o.minGap) asleep \(o.allAsleepAt)")
            check(s, o)
            if kind == 0 { for i in 0..<n { XCTAssertLessThan(simd_distance(o.finals[i], o.starts[i]), 0.2, "\(s.name): #\(i) lies where he stood") } }
        }
    }

    func testWalkingAndTimeAgainstTheOldPile() {
        var newWalk: Float = 0, oldWalk: Float = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            let s = Self.scene(seed: seed, kind: Int(seed % 3), n: 3)
            let nw = run(s, anywhere: true), od = run(s, anywhere: false)
            MotionLog.write("SLEEPANY vs \(s.name): walk new \(nw.walk) old \(od.walk); asleep new \(nw.allAsleepAt) old \(od.allAsleepAt); minGap new \(nw.minGap) old \(od.minGap)")
            XCTAssertLessThanOrEqual(nw.allAsleepAt, od.allAsleepAt + 0.05, "\(s.name): all asleep no later than before")
            newWalk += nw.walk; oldWalk += od.walk
        }
        MotionLog.write("SLEEPANY total walk new \(newWalk) old \(oldWalk) ratio \(newWalk / max(oldWalk, 1e-3))")
        XCTAssertGreaterThan(oldWalk, 6, "the old pile walks (the comparison is meaningful)")
        XCTAssertLessThan(newWalk, 0.15 * oldWalk, "bedtime walking is under 15% of the old behaviour")
    }

    /// The same scenes must break the rule on the old behaviour (the switch really is the difference).
    func testTheOldPileBreaksTheRule() {
        var broke = 0
        for seed in [2, 5] as [UInt64] {
            let s = Self.scene(seed: seed, kind: 0, n: 3)
            let od = run(s, anywhere: false)
            let moved = zip(od.finals, od.starts).filter { simd_distance($0, $1) >= 0.2 }.count
            MotionLog.write("SLEEPANY old \(s.name) moved \(moved) walk \(od.walk)")
            if moved > 0 { broke += 1 }
        }
        XCTAssertEqual(broke, 2, "on the old behaviour scattered, fair sleepers still walk to a row")
    }
}
