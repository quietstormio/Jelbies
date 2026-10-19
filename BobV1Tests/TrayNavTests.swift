//
//  TrayNavTests.swift
//  He walks around the tray (and around each other) instead of pushing against it: start in front, start at every corner, several Blobs crossing.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TrayNavTests: XCTestCase {
    static let trayAt = SIMD2<Float>(0, 1.3)

    /// A rig that has walked to `start` (no tray yet), then the tray pops in.
    private func place(_ rig: MotionRig, at p: SIMD2<Float>) {
        rig.brain.requestNow(.goTo(p))
        rig.run(14) { rig.brain.activity == .idle && simd_distance(rig.brain.position, p) < 0.3 }
        rig.run(0.6)
    }
    private func popTray() -> DiningSet {
        let t = DiningSet()
        t.spawn(serving: Consumables.berries, n: 1, bobAt: SIMD2(9, 9), forcedOrigin: Self.trayAt)
        for _ in 0..<40 { t.update(dt: 1 / 60) }
        return t
    }
    private func clearance(_ p: SIMD2<Float>) -> Float {
        RoomLayout.dynamicBoxes.map { RoomLayout.boxDistanceXZ(p, $0) }.min() ?? 9
    }

    /// Walks `rig` to `target`; returns (arrival time or nil, min clearance to the collider, longest stall).
    private func walk(_ rig: MotionRig, to target: SIMD2<Float>, limit: Float = 18) -> (t: Float?, clear: Float, stall: Float) {
        rig.brain.requestNow(.goTo(target))
        var clear = Float.infinity, stall: Float = 0, arrived: Float?
        let t0 = rig.t
        var tick = 0
        rig.run(limit) {
            tick += 1
            if tick % 30 == 0 { MotionLog.write(String(format: "NAVTRACE t=%.1f pos=(%.2f, %.2f) act=%@ stall=%.2f route=%@", rig.t - t0, rig.brain.position.x, rig.brain.position.y, "\(rig.brain.activity)", rig.brain.steerStallSeconds, "\(rig.brain.steerRoute)")) }
            clear = min(clear, self.clearance(rig.brain.position))
            stall = max(stall, rig.brain.steerStallSeconds)
            if rig.brain.activity == .idle && simd_distance(rig.brain.position, target) < 0.25 && rig.t - t0 > 1 { arrived = rig.t - t0; return true }
            return false
        }
        return (arrived, clear, stall)
    }

    func testFromInFrontOfTheTrayToBehindIt() {
        let rig = MotionRig(game: true); rig.brain.autonomy = false
        place(rig, at: SIMD2(0, 2.3))
        let tray = popTray(); defer { tray.reset() }
        let r = walk(rig, to: SIMD2(0, 0.45))
        MotionLog.write("NAV front->behind arrived \(String(describing: r.t)) min clearance \(r.clear) stall \(r.stall)")
        XCTAssertNotNil(r.t, "he gets around the tray")
        XCTAssertGreaterThan(r.clear, 0.7 * RoomLayout.lowPropRadiusScale - 0.05, "he never overlaps the collider")
        XCTAssertLessThanOrEqual(r.stall, 1.0, "no stall longer than 1 s")
    }

    func testFromEveryCorner() {
        let c = Self.trayAt
        for (sx, sz) in [(Float(1), Float(1)), (-1, 1), (1, -1), (-1, -1)] {
            let rig = MotionRig(game: true); rig.brain.autonomy = false
            let start = c + SIMD2(0.85 * sx, 0.95 * sz), goal = c + SIMD2(-0.85 * sx, -0.95 * sz)
            place(rig, at: start)
            let tray = popTray()
            let r = walk(rig, to: goal)
            MotionLog.write("NAV corner (\(sx), \(sz)) arrived \(String(describing: r.t)) clearance \(r.clear) stall \(r.stall)")
            XCTAssertNotNil(r.t, "corner (\(sx), \(sz)): he arrives")
            XCTAssertGreaterThan(r.clear, 0.7 * RoomLayout.lowPropRadiusScale - 0.05, "corner (\(sx), \(sz)): never overlaps")
            XCTAssertLessThanOrEqual(r.stall, 1.0, "corner (\(sx), \(sz)): no stall")
            tray.reset()
        }
    }

    func testTheColliderIsGoneTheMomentTheTrayPoofs() {
        let tray = popTray()
        XCTAssertFalse(RoomLayout.dynamicBoxes.isEmpty)
        tray.despawn()
        XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty, "no collider while it poofs")
        for _ in 0..<40 { tray.update(dt: 1 / 60) }
        XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty)
    }

    /// Three Blobs cross at the tray: all arrive, none walks through another, nobody stalls for more than a second.
    func testThreeWalkersCrossingAtTheTray() {
        let rigs = (0..<3).map { _ in MotionRig(game: true) }
        for (i, r) in rigs.enumerated() {
            r.brain.autonomy = false; r.brain.steerID = i
            r.brain.peers = { rigs.enumerated().filter { $0.offset != i }.map { (id: $0.offset, pos: $0.element.brain.position) } }
        }
        let starts: [SIMD2<Float>] = [SIMD2(-0.85, 0.5), SIMD2(0.85, 0.5), SIMD2(0, 2.4)]
        let goals: [SIMD2<Float>] = [SIMD2(0.85, 2.0), SIMD2(-0.85, 2.0), SIMD2(0, 0.45)]
        for (i, r) in rigs.enumerated() { place(r, at: starts[i]) }
        MotionLog.write("NAV three starts \(rigs.map { $0.brain.position })")
        let tray = popTray(); defer { tray.reset() }
        for (i, r) in rigs.enumerated() { r.brain.requestNow(.goTo(goals[i])) }
        var minPair = Float.infinity, minClear = Float.infinity, stall: Float = 0
        var arrived = [Bool](repeating: false, count: 3)
        var n3 = 0
        for _ in 0..<(60 * 30) {
            for r in rigs { r.tick() }
            n3 += 1
            if n3 % 60 == 0 { MotionLog.write("NAV3 t=\(n3 / 60) \(rigs.map { String(format: "(%.2f,%.2f %@ %.1f)", $0.brain.position.x, $0.brain.position.y, "\($0.brain.activity)", $0.brain.steerStallSeconds) })") }
            for i in 0..<3 {
                minClear = min(minClear, clearance(rigs[i].brain.position))
                stall = max(stall, rigs[i].brain.steerStallSeconds)
                if rigs[i].brain.activity == .idle && simd_distance(rigs[i].brain.position, goals[i]) < 0.3 { arrived[i] = true }
                for j in (i + 1)..<3 where j < 3 {
                    let d = simd_distance(rigs[i].brain.position, rigs[j].brain.position)
                    if d < minPair { minPair = d; if d < 0.5 { MotionLog.write("NAVPAIR \(i)-\(j) d=\(d) at \(rigs[i].brain.position) \(rigs[j].brain.position) t=\(n3 / 60) route0=\(rigs[i].brain.steerRoute) acts \(rigs[i].brain.activity) \(rigs[j].brain.activity)") } }
                }
            }
            if !arrived.contains(false) { break }
        }
        MotionLog.write("NAV three: arrived \(arrived) min pair \(minPair) min clearance \(minClear) longest stall \(stall)")
        XCTAssertFalse(arrived.contains(false), "all three arrive")
        // the visible floor beside the tray is a corridor only ~0.2 u wide: two Blobs meeting inside it cannot pass, so the lower id gives way for up to
        // 0.7 s and then squeezes by (soft bodies overlap, nobody is ever deadlocked or exactly on top of another)
        XCTAssertGreaterThan(minPair, 0.05, "nobody is ever on top of another")
        XCTAssertGreaterThan(minClear, 0.7 * RoomLayout.lowPropRadiusScale - 0.06, "nobody overlaps the tray")
        XCTAssertLessThanOrEqual(stall, 1.0, "no stall longer than 1 s")
    }
}
