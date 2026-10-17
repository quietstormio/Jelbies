//
//  GfxSavingsTests.swift
//  Pure state machines of the render-cost savers (room cache invalidation, footprint, idle rest) and the exact pixel identity of the
//  room cache against the old path on the offscreen renderer.
//

import XCTest
import simd
@testable import BobV1

final class RoomCacheStateTests: XCTestCase {
    private func key(_ mutate: (inout RoomCacheKey) -> Void = { _ in }) -> RoomCacheKey {
        var k = RoomCacheKey(); k.width = 1320; k.height = 2868; k.propsVersion = 1
        k.keyDir = SIMD3(-0.5, 0.8, 0.55); k.keyIntensity = 1.6; k.fog = SIMD3(14, 32, 0.3)
        mutate(&k); return k
    }

    func testBuildsOnlyAfterSettleThenHits() {
        var s = RoomCacheState()
        let k = key()
        XCTAssertEqual(s.frame(key: k, footprint: 0.3, enabled: true), .bypass(.settling))
        XCTAssertEqual(s.frame(key: k, footprint: 0.3, enabled: true), .bypass(.settling))
        XCTAssertEqual(s.frame(key: k, footprint: 0.3, enabled: true), .bypass(.settling))
        XCTAssertEqual(s.frame(key: k, footprint: 0.3, enabled: true), .build)
        for _ in 0..<10 { XCTAssertEqual(s.frame(key: k, footprint: 0.3, enabled: true), .use) }
        XCTAssertEqual(s.builds, 1)
        XCTAssertGreaterThan(s.hitRate, 0.6)
    }

    func testEveryKeyFieldInvalidatesWithItsReason() {
        let cases: [(String, (inout RoomCacheKey) -> Void, RoomCacheMiss)] = [
            ("camera", { $0.viewProj.columns.3.x += 0.01 }, .camera),
            ("camPos", { $0.camPos.y += 1 }, .camera),
            ("width", { $0.width += 2 }, .size),
            ("height", { $0.height += 2 }, .size),
            ("theme", { $0.themeTint.x += 0.1 }, .theme),
            ("props", { $0.propsVersion += 1 }, .props),
            ("keyDir", { $0.keyDir.x += 0.1 }, .light),
            ("intensity", { $0.keyIntensity += 0.1 }, .light),
            ("fog", { $0.fog.y += 1 }, .light),
        ]
        for (name, mut, reason) in cases {
            var s = RoomCacheState()
            let k = key()
            for _ in 0..<8 { _ = s.frame(key: k, footprint: 0.3, enabled: true) }
            XCTAssertEqual(s.frame(key: k, footprint: 0.3, enabled: true), .use, name)
            XCTAssertEqual(s.frame(key: key(mut), footprint: 0.3, enabled: true), .bypass(reason), name)
            XCTAssertEqual(s.misses[reason], 1, name)
            // and it rebuilds once stable again
            var last = RoomCacheAction.use
            for _ in 0..<5 { last = s.frame(key: key(mut), footprint: 0.3, enabled: true) }
            XCTAssertEqual(last, .use, name)
            XCTAssertEqual(s.builds, 2, name)
        }
    }

    func testMovingCameraNeverBuilds() {
        var s = RoomCacheState()
        for i in 0..<60 {                       // focus blend: a new camera every frame
            let a = s.frame(key: key { $0.viewProj.columns.3.x = Float(i) * 0.01 }, footprint: 0.3, enabled: true)
            XCTAssertEqual(a, i == 0 ? .bypass(.settling) : .bypass(.camera))
        }
        XCTAssertEqual(s.builds, 0)
    }

    func testLargeFootprintBypassesButKeepsCache() {
        var s = RoomCacheState()
        let k = key()
        for _ in 0..<6 { _ = s.frame(key: k, footprint: 0.3, enabled: true) }
        XCTAssertEqual(s.frame(key: k, footprint: 0.9, enabled: true), .bypass(.footprint))
        XCTAssertEqual(s.frame(key: k, footprint: 0.3, enabled: true), .use, "no rebuild: the cache stayed valid")
        XCTAssertEqual(s.builds, 1)
        var fresh = RoomCacheState()
        for _ in 0..<10 { XCTAssertEqual(fresh.frame(key: k, footprint: 0.9, enabled: true), fresh.frames == 1 ? .bypass(.settling) : .bypass(.footprint)) }
        XCTAssertEqual(fresh.builds, 0, "never builds a cache it would not use")
    }

    func testDisabledAndInvalidate() {
        var s = RoomCacheState()
        XCTAssertEqual(s.frame(key: key(), footprint: 0.3, enabled: false), .bypass(.disabled))
        for _ in 0..<6 { _ = s.frame(key: key(), footprint: 0.3, enabled: true) }
        s.invalidate()
        XCTAssertEqual(s.frame(key: key(), footprint: 0.3, enabled: true), .bypass(.settling))
        XCTAssertTrue(s.summary.contains("hit"))
    }
}

final class RoomFootprintTests: XCTestCase {
    private var vp: simd_float4x4 { GameCamera.camera(aspect: 440.0 / 956.0).viewProj }

    func testRoamingFootprintIsSmallAndContainsBob() {
        let c = SIMD3<Float>(0, 0, 0.5)
        let r = RoomFootprint.rect(min: c + SIMD3(-0.9, 0, -0.9), max: c + SIMD3(0.9, 1.5, 0.9), shadowDir: GameCamera.shadowDir, viewProj: vp, width: 1320, height: 2868)
        let share = RoomFootprint.share(r, width: 1320, height: 2868)
        XCTAssertLessThan(share, 0.3)
        XCTAssertGreaterThan(share, 0.03)
        // Bob's own bbox corner projects inside
        let q = vp * SIMD4<Float>(0.9, 1.5, 0.9, 1)
        let sx = (q.x / q.w * 0.5 + 0.5) * 1320, sy = (0.5 - q.y / q.w * 0.5) * 2868
        XCTAssertTrue(sx >= Float(r.x) && sx <= Float(r.x + r.w) && sy >= Float(r.y) && sy <= Float(r.y + r.h))
    }

    func testFocusFootprintIsLarge() {
        let cam = GameCamera.camera(aspect: 440.0 / 956.0, focus: 1)
        let c = SIMD3<Float>(0, 0, 2.4)
        let r = RoomFootprint.rect(min: c + SIMD3(-0.9, 0, -0.9), max: c + SIMD3(0.9, 1.5, 0.9), shadowDir: GameCamera.shadowDir, viewProj: cam.viewProj, width: 1320, height: 2868)
        XCTAssertGreaterThan(RoomFootprint.share(r, width: 1320, height: 2868), RoomCacheState.maxFootprint)
    }

    func testBehindCameraOrNaNFallsBackToFullScreen() {
        let r = RoomFootprint.rect(min: SIMD3(-1, 0, 20), max: SIMD3(1, 1, 22), shadowDir: GameCamera.shadowDir, viewProj: vp, width: 100, height: 200)
        XCTAssertEqual(r, RoomFootprint.Rect(x: 0, y: 0, w: 100, h: 200))
        let n = RoomFootprint.rect(min: SIMD3(repeating: .nan), max: SIMD3(repeating: .nan), shadowDir: GameCamera.shadowDir, viewProj: vp, width: 100, height: 200)
        XCTAssertEqual(n, RoomFootprint.Rect(x: 0, y: 0, w: 100, h: 200))
    }
}

final class IdleRestGovernorTests: XCTestCase {
    func testRestsAfterTwoSecondsOfCalm() {
        var g = IdleRestGovernor()
        var flips = 0
        for _ in 0..<110 { if g.update(dt: 1.0 / 60, active: false, energy: 0) { flips += 1 } }
        XCTAssertFalse(g.resting, "1.83 s is not enough")
        for _ in 0..<20 { if g.update(dt: 1.0 / 60, active: false, energy: 0) { flips += 1 } }
        XCTAssertTrue(g.resting); XCTAssertEqual(flips, 1)
    }

    func testActivityEnergyAndUnknownKeepFullRate() {
        var g = IdleRestGovernor()
        for _ in 0..<200 { _ = g.update(dt: 1.0 / 60, active: true, energy: 0) }
        XCTAssertFalse(g.resting)
        for _ in 0..<200 { _ = g.update(dt: 1.0 / 60, active: false, energy: 1) }
        XCTAssertFalse(g.resting)
        for _ in 0..<200 { _ = g.update(dt: 1.0 / 60, active: false, energy: nil) }
        XCTAssertFalse(g.resting)
    }

    func testWakeIsInstantAndRestartsTheDwell() {
        var g = IdleRestGovernor()
        for _ in 0..<130 { _ = g.update(dt: 1.0 / 60, active: false, energy: 0) }
        XCTAssertTrue(g.resting)
        XCTAssertTrue(g.wake()); XCTAssertFalse(g.resting)
        XCTAssertFalse(g.wake())
        for _ in 0..<60 { _ = g.update(dt: 1.0 / 60, active: false, energy: 0) }
        XCTAssertFalse(g.resting, "needs another full 2 s")
    }
}

@MainActor
final class RoomCacheIdentityTests: XCTestCase {
    /// The room cache must reproduce the old path pixel for pixel: roaming, a throw frozen mid-air, the dining tray, and the focus close-up.
    func testCacheMatchesOldPath() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 402, height: 874))
        s.place(SIMD2(0.8, 0.6))
        func check(_ name: String, focus: Float = 0) {
            let old = s.render(focus: focus, cache: false)
            let old2 = s.render(focus: focus, cache: false)
            print("GFXIDENT \(name) self-diff old vs old: \(GfxDiff(old, old2).summary)")
            let new = s.render(focus: focus, cache: true, frames: 6)
            let d = GfxDiff(old, new)
            print("GFXIDENT \(name): \(d.summary); action \(s.ren.lastCacheAction), footprint \(s.ren.lastFootprintShare); rect \(String(describing: s.ren.lastFootprintRect)); at \(d.where_)")
            if let dir = ProcessInfo.processInfo.environment["GFX_OUT"] {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                old.png(to: URL(fileURLWithPath: dir).appendingPathComponent("dbg_\(name.replacingOccurrences(of: " ", with: "_"))_old.png"))
                new.png(to: URL(fileURLWithPath: dir).appendingPathComponent("dbg_\(name.replacingOccurrences(of: " ", with: "_"))_new.png"))
            }
            XCTAssertEqual(d.maxLevel, 0, "\(name): \(d.summary)")
        }
        check("roaming")
        XCTAssertEqual(s.ren.lastCacheAction, .use)
        s.shift(SIMD3(0.5, 1.6, -0.4)); check("throw mid-air"); s.shift(SIMD3(-0.5, -1.6, 0.4))
        s.spawnTray(); check("dining"); s.clearTray()
        s.place(GameCamera.callSpot); check("focus close-up", focus: 1)
    }
}
