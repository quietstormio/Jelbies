//
//  ComeHereSettleTests.swift
//  Owner 2026-11-19: "the come here is still buggy the purple was sleep and now he's in the back there. The come here action cannot miss."
//  The rule: after Come here EVERY called Jelmiko ends in his own spot of the front row (side by side, none behind another, skin gap >= 0, facing the player),
//  whatever he was doing when it was tapped (asleep, going to bed, getting up, mid-trick, walking, far at the back, behind the furniture, mid-hop).
//  One test per starting state, 20 seeds each, on the stage's own wiring (`FocusAnyRun(peers: true)`). The table prints per state: runs that broke the rule, the settle time.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ComeHereSettleTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    /// The real HUD button cut-outs in the roam floor (space-fix-r1): the measured window and safe insets of an iPhone 17 Pro Max.
    enum HUD { case portrait, landscape }
    /// Clamp snaps seen during the current run (a called body that `GameCamera.constrain` would move by more than 0.05).
    nonisolated(unsafe) static var snaps = 0
    static let seeds = 20

    private var savedHour: Double?
    private var savedAnywhere = true
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        SleepOrder.reset()
        savedHour = DayClock.shared.forcedHour
        DayClock.shared.forcedHour = 23          // (night: bedtime hours; the day-nap variants set their own)
        savedAnywhere = SleepTuning.anywhere
        HUDLayout.measuredSize = .zero; HUDLayout.measuredInsets = .zero
        FocusGroup.sleeperFix = ProcessInfo.processInfo.environment["COMEHERE_BASE"] == nil
        FocusGroup.twoCornerMin = Float(ProcessInfo.processInfo.environment["COMEHERE_TWO"] ?? "") ?? 1.3          // (COMEHERE_BASE=1: the earlier behaviour, for the before table)
    }
    override func tearDown() {
        HUDLayout.measuredSize = .zero; HUDLayout.measuredInsets = .zero; GameCamera.clearRoam()
        SleepTuning.anywhere = savedAnywhere; FocusGroup.sleeperFix = true
        DayClock.shared.forcedHour = savedHour
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset()
    }

    // MARK: measuring

    private static func rng(_ s: UInt64) -> () -> Float {
        var x = s &* 6364136223846793005 &+ 1442695040888963407
        return { x = x &* 6364136223846793005 &+ 1442695040888963407; return Float((x >> 40) & 0xFFFF) / 65535 }
    }
    /// A floor point clear of the front row, the bowls and the table.
    private static func spread(seed: UInt64, n: Int, backBias: Bool = false) -> [SIMD2<Float>] {
        let r = rng(seed &* 977 &+ 13)
        if backBias { return (0..<n).map { i in SIMD2<Float>(-2.0 + 2.0 * Float(i) + (r() - 0.5) * 0.5, -2.1 + 0.5 * r()) } }          // (three along the back wall)
        var pts: [SIMD2<Float>] = []
        var tries = 0
        while pts.count < n, tries < 20000 {
            tries += 1
            let p = SIMD2<Float>(-2.4 + 4.8 * r(), (backBias ? -1.9 : -1.9) + (backBias ? 1.2 : 3.4) * r())
            guard abs(p.x) <= 2.4, simd_distance(p, GameCamera.callSpot) > 1.6, simd_distance(p, RoomLayout.table.centre) > 1.3,
                  simd_distance(p, GameCamera.foodBowlSpot) > 1.2, simd_distance(p, GameCamera.waterBowlSpot) > 1.2 else { continue }
            if pts.allSatisfy({ simd_distance($0, p) >= (tries < 3000 ? 2.0 : 1.7) }) { pts.append(p) }
        }
        precondition(pts.count == n, "no layout for seed \(seed)")
        return pts
    }

    struct Result {
        var fails: [String] = []
        var settle: Float = .infinity
        var netAccepted = 0
        var minGap: Float = .infinity
    }

    private static func outline(_ a: JellyActor, _ dyn: inout [Float], _ rm: RenderMesh) -> [SIMD2<Float>] {
        dyn.withUnsafeMutableBufferPointer { a.skinner.update(x: a.sim.x, index: rm.index, into: $0.baseAddress!) }
        return stride(from: 0, to: rm.vertexCount, by: 3).map { SIMD2(dyn[6 * $0], dyn[6 * $0 + 2]) }
    }

    /// One run: `n` at home, `setup` puts them in their starting states, then Come here for `called` (nil = everyone); measured when the close-up is up and again 3 s later.
    private func run(seed: UInt64, n: Int = 3, called: [Int]? = nil, backBias: Bool = false, aspect: Float = 440 / 956, hud: HUD? = nil, setup: (FocusAnyRun, [SIMD2<Float>]) -> Void) -> Result {
        SleepOrder.reset(); _ = GameCamera.camera(aspect: aspect)
        Self.snaps = 0
        if let hud {
            HUDLayout.measuredSize = hud == .portrait ? CGSize(width: 440, height: 956) : CGSize(width: 956, height: 440)
            HUDLayout.measuredInsets = hud == .portrait ? UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0) : UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)
            _ = GameCamera.refreshRoam(aspect: aspect)
        }
        let r = FocusAnyRun(count: n, peers: true); Self.keep.append(r)
        for (i, a) in r.actors.enumerated() { a.brain!.seed = seed &* 31 &+ UInt64(i) }
        r.run(0.5)
        let pts = Self.spread(seed: seed, n: n, backBias: backBias)
        for (i, p) in pts.enumerated() { r.place(i, at: p) }
        setup(r, pts)
        let ids = called ?? Array(0..<n)
        let startFloors = (0..<n).map { GameCare.floorPos(r.actors[$0].brain!, r.actors[$0].sim) }
        if called == nil { r.care.comeHereEveryone() } else { r.care.beginFocus(ids: ids) }
        var res = Result()
        var t: Float = 0
        var ok = false
        var trace: [String] = []
        for tk in 0..<(30 * 60) {
            r.tick(); t += 1.0 / 60
            if tk % 6 == 0, hud != nil {
                for id in ids { let q = GameCare.floorPos(r.actors[id].brain!, r.actors[id].sim); let c = GameCamera.constrain(SIMD3(q.x, 0, q.y), radius: 0.7); if simd_distance(SIMD2(c.x, c.z), q) > 0.05 { Self.snaps += 1 } }
            }
            if tk % 30 == 0 {          // a trace of every called body twice a second (printed only for a failing run)
                let g0 = r.care.focusGroup
                for id in ids {
                    let b = r.actors[id].brain!, q = GameCare.floorPos(b, r.actors[id].sim), ap = g0.approach[id]
                    let near = g0.uncalled.map { simd_distance($0, q) }.min() ?? 99
                    trace.append(String(format: "t%.1f j%d (%.1f,%.1f) d_spot %.1f d_obst %.1f act %@ come %d walk %d via %@ stuck %.1f det %d req %d arr %d", Float(tk) / 60, id, q.x, q.y, simd_distance(q, g0.spot(of: id)), near, "\(b.activity)", b.isCome ? 1 : 0, b.isWalkScript ? 1 : 0, ap?.via.map { String(format: "(%.1f,%.1f)", $0.x, $0.y) } ?? "-", ap?.stuckT ?? 0, ap?.detours ?? 0, (ap?.requested ?? false) ? 1 : 0, g0.arrived.contains(id) ? 1 : 0))
                }
            }
            if r.care.focus.isFocused { ok = true; break }
        }
        res.settle = t
        if !ok { res.fails.append("never focused (phase \(r.care.focus.phase))") }
        r.run(3)
        res.netAccepted = r.care.focusGroup.netAccepted
        let rm = r.rm
        var dyn = [Float](repeating: 0, count: rm.vertexCount * 6)
        let outlines = ids.map { Self.outline(r.actors[$0], &dyn, rm) }
        let g = r.care.focusGroup
        for (k, id) in ids.enumerated() {
            let b = r.actors[id].brain!
            let spot = g.spot(of: id)
            let here = GameCare.floorPos(b, r.actors[id].sim)
            let d = simd_distance(here, spot)
            if d > 0.3 { res.fails.append("j\(id) \(String(format: "%.2f", d)) from his spot") }
            if b.isSleeping { res.fails.append("j\(id) still asleep") }
            let yaw = abs(atan2f(sinf(b.yaw), cosf(b.yaw)))
            if yaw > 0.6 { res.fails.append("j\(id) faces away \(String(format: "%.2f", yaw))") }
            for l in (k + 1)..<max(k + 1, ids.count) {
                let gap = SleepAnywhereTests.skinGap(outlines[k], outlines[l])
                res.minGap = min(res.minGap, gap)
                if gap < -0.01 { res.fails.append("j\(id)/j\(ids[l]) gap \(String(format: "%.3f", gap))") }
            }
        }
        // the uncalled ones, on the close-up's own screen: behind the called row is fine, even in the middle; never in front of / beside a called body covering more than 10% of its drawn box
        let uncalled = (0..<n).filter { !ids.contains($0) }
        if !uncalled.isEmpty {
            let cam = GameCamera.camera(aspect: aspect, focus: 1)
            func box(_ id: Int) -> (x0: Float, y0: Float, x1: Float, y1: Float) {
                var d = [Float](repeating: 0, count: rm.vertexCount * 6)
                d.withUnsafeMutableBufferPointer { r.actors[id].skinner.update(x: r.actors[id].sim.x, index: rm.index, into: $0.baseAddress!) }
                var b = (x0: Float.infinity, y0: Float.infinity, x1: -Float.infinity, y1: -Float.infinity)
                for i in stride(from: 0, to: rm.vertexCount, by: 3) {
                    let c = cam.viewProj * SIMD4<Float>(d[6 * i], d[6 * i + 1], d[6 * i + 2], 1)
                    let sx = c.x / c.w, sy = c.y / c.w
                    b = (min(b.x0, sx), min(b.y0, sy), max(b.x1, sx), max(b.y1, sy))
                }
                return b
            }
            for u in uncalled {
                let ub = box(u), uz = GameCare.floorPos(r.actors[u].brain!, r.actors[u].sim).y
                for id in ids {
                    let c = box(id), cz = GameCare.floorPos(r.actors[id].brain!, r.actors[id].sim).y
                    if uz < cz - 0.25 { continue }          // (behind the called one: allowed)
                    let ow = max(0, min(ub.x1, c.x1) - max(ub.x0, c.x0)), oh = max(0, min(ub.y1, c.y1) - max(ub.y0, c.y0))
                    let frac = ow * oh / max((c.x1 - c.x0) * (c.y1 - c.y0), 1e-6)
                    if frac > 0.10 { res.fails.append("uncalled j\(u) (z \(String(format: "%.1f", uz))) covers \(Int(frac * 100))% of j\(id) (z \(String(format: "%.1f", cz)))") }
                }
            }
        }
        if hud != nil, Self.snaps > 0 { res.fails.append("clamp snapped a called body \(Self.snaps) times") }
        if ids.count > 1 {
            let zs = ids.map { GameCare.floorPos(r.actors[$0].brain!, r.actors[$0].sim).y }
            if (zs.max()! - zs.min()!) > 0.7 { res.fails.append("not one row (z spread \(String(format: "%.2f", zs.max()! - zs.min()!)))") }
        }
        if !res.fails.isEmpty { for l in trace { print("COMEHERE-TRACE | seed \(seed) | \(l)") } }
        if !res.fails.isEmpty {
            let f: (SIMD2<Float>) -> String = { String(format: "(%.1f,%.1f)", $0.x, $0.y) }
            res.fails.append("[spots " + ids.map { f(g.spot(of: $0)) }.joined(separator: " ") + " | start " + startFloors.map(f).joined(separator: " ") + " | final " + (0..<n).map { f(GameCare.floorPos(r.actors[$0].brain!, r.actors[$0].sim)) }.joined(separator: " ") + "]")
        }
        return res
    }

    private func table(_ name: String, n: Int = 3, called: [Int]? = nil, backBias: Bool = false, aspect: Float = 440 / 956, hud: HUD? = nil, setup: (FocusAnyRun, [SIMD2<Float>], UInt64) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        var bad = 0, slowest: Float = 0, sum: Float = 0, nets = 0
        var firstFails: [String] = []
        var settles: [Float] = []
        for s in 0..<UInt64(Self.seeds) {
            let res = run(seed: s + 1, n: n, called: called, backBias: backBias, aspect: aspect, hud: hud) { setup($0, $1, s + 1) }
            if !res.fails.isEmpty { bad += 1; if firstFails.count < 3 { firstFails.append("seed\(s + 1): " + res.fails.joined(separator: "; ")) } }
            slowest = max(slowest, res.settle); sum += res.settle; nets += res.netAccepted; settles.append(res.settle)
        }
        print("COMEHERE-TABLE | \(name) | runs \(Self.seeds) | broke the rule \(bad) | settle median \(String(format: "%.1f", settles.sorted()[settles.count / 2])) s, mean \(String(format: "%.1f", sum / Float(Self.seeds))) s, slowest \(String(format: "%.1f", slowest)) s | net accepted \(nets)")
        for f in firstFails { print("COMEHERE-FAIL | \(name) | \(f)") }
        XCTAssertEqual(bad, 0, "\(name): \(bad) of \(Self.seeds) runs broke the rule. \(firstFails.joined(separator: " | "))", file: file, line: line)
    }

    /// Puts Jelmiko `id` near `p0` (jittered by the seed) and moves anyone who started within 1.9 of it to a free spot (so the test never starts with two bodies on top of each other).
    private func put(_ r: FocusAnyRun, _ id: Int, at p0: SIMD2<Float>, seed: UInt64 = 0) {
        let jr = Self.rng(seed &* 7919 &+ 5)
        let p = p0 + SIMD2((jr() - 0.5) * 0.8, (jr() - 0.5) * 0.8)          // (a little different per seed)
        let spots: [SIMD2<Float>] = [SIMD2(-2.1, -1.6), SIMD2(2.1, -1.6), SIMD2(-2.1, 2.0), SIMD2(2.1, 2.0), SIMD2(0, -2.0), SIMD2(-2.1, 0.2), SIMD2(2.1, 0.2)]
        r.place(id, at: p)
        var taken = [p]
        for o in 0..<r.actors.count where o != id {
            let here = GameCare.floorPos(r.actors[o].brain!, r.actors[o].sim)
            if simd_distance(here, p) < 1.9 || taken.contains(where: { simd_distance($0, here) < 1.8 }) {
                if let s = spots.first(where: { c in taken.allSatisfy { simd_distance($0, c) > 1.9 } }) { r.place(o, at: s); taken.append(s) }
            } else { taken.append(here) }
        }
    }

    private func sleepNow(_ r: FocusAnyRun, _ id: Int) {
        let a = r.actors[id], b = a.brain!
        b.sleepEnabled = true
        b.sleepInstant(a.sim, a.skinner)
        r.run(2)
        XCTAssertTrue(b.isNapping, "jelly \(id) is down")
    }

    // MARK: the starting states

    func testControlEveryoneAwakeStanding() { table("control: all awake, standing") { _, _, _ in } }
    func testSleeperLyingWhereHeStands() { SleepTuning.anywhere = true; table("one asleep, lying where he stands (night)") { r, _, _ in self.sleepNow(r, 1) } }
    func testSleeperLyingInTheOldLine() { SleepTuning.anywhere = false; table("one asleep, old sleep line") { r, _, _ in self.sleepNow(r, 1) } }
    func testSleeperByDayNap() { DayClock.shared.forcedHour = 14; table("one asleep, daytime nap") { r, _, _ in self.sleepNow(r, 1) } }
    func testBobAsleep() { table("Bob (0) asleep") { r, _, _ in self.sleepNow(r, 0) } }
    func testEveryoneAsleep() { table("all three asleep") { r, _, _ in for i in 0..<3 { self.sleepNow(r, i) } } }
    func testSleeperGoingToBed() {
        table("one walking / sitting down to bed") { r, _, _ in
            let b = r.actors[2].brain!; b.sleepEnabled = true; b.commandedGoodnight = true; r.run(0.8)
        }
    }
    func testSleeperGettingUp() {
        table("one rolling up (a wake already asked)") { r, _, _ in
            self.sleepNow(r, 1); r.actors[1].brain!.sleepWake(groggy: true); r.run(0.6)
        }
    }
    func testEmoteAlone() {
        table("one mid-trick, alone") { r, _, s in
            r.actors[1].brain!.commandedIdle = [.flop, .sit, .jacks, .sway, .bounce, .tail][Int(s % 6)]; r.run(1.0)
        }
    }
    func testMidWalk() {
        table("one mid-walk across the room") { r, _, s in
            r.actors[1].brain!.requestNow(.goTo(SIMD2(s % 2 == 0 ? -2.2 : 2.2, -2.0))); r.run(0.7)
        }
    }
    func testFarAtTheBack() {
        table("all three far at the back", backBias: true) { _, _, _ in }
    }
    func testBehindTheFurniture() {
        table("one behind the table") { r, _, s in
            r.place(1, at: RoomLayout.table.centre + SIMD2(s % 2 == 0 ? 0.9 : -0.9, -1.0))
        }
    }
    func testMidHop() {
        table("one mid-air in a hop") { r, _, _ in
            let a = r.actors[1]; a.brain!.startHopPlay(sim: a.sim, distance: 0.0001); r.run(0.3)
        }
    }
    func testCallTwoOfThreeWithOneAsleep() {
        table("call two (1, 2) of three, 1 asleep", called: [1, 2]) { r, _, _ in self.sleepNow(r, 1) }
    }
    func testCallTwoOfThreeWithTheThirdAsleep() {
        table("call two (0, 1) of three, 2 asleep (not called)", called: [0, 1]) { r, _, _ in self.sleepNow(r, 2) }
    }
    func testTwoAtHomeOneAsleep() {
        table("two at home, 1 asleep", n: 2) { r, _, _ in self.sleepNow(r, 1) }
    }
    func testOneAtHomeAsleep() {
        table("one at home, asleep", n: 1) { r, _, _ in self.sleepNow(r, 0) }
    }

    // MARK: the uncalled third (2026-11-20): never between or over the called ones on screen
    func testCallTwoThirdAsleepInTheMiddleOfTheRug() {
        table("call two (0,1), the third asleep at the rug centre", called: [0, 1]) { r, _, s in self.put(r, 2, at: SIMD2(0, 0), seed: s); self.sleepNow(r, 2) }
    }
    func testCallTwoThirdAsleepNearTheFront() {
        table("call two (0,1), the third asleep at the front middle", called: [0, 1]) { r, _, s in self.put(r, 2, at: SIMD2(0, 1.6), seed: s); self.sleepNow(r, 2) }
    }
    func testCallTwoThirdAsleepAtTheLeft() {
        table("call two (0,1), the third asleep at the left", called: [0, 1]) { r, _, s in self.put(r, 2, at: SIMD2(-2.0, 1.2), seed: s); self.sleepNow(r, 2) }
    }
    func testCallTwoThirdAsleepAtTheRight() {
        table("call two (0,1), the third asleep at the right", called: [0, 1]) { r, _, s in self.put(r, 2, at: SIMD2(2.0, 1.2), seed: s); self.sleepNow(r, 2) }
    }
    func testCallTwoBobAsleepInTheMiddle() {
        table("call two (1,2), Bob (0) asleep at the rug centre", called: [1, 2]) { r, _, s in self.put(r, 0, at: SIMD2(0, 0.4), seed: s); self.sleepNow(r, 0) }
    }
    func testCallOneOthersAsleepInTheMiddle() {
        table("call one (1), the other two asleep (middle + side)", called: [1]) { r, _, s in self.put(r, 0, at: SIMD2(0, 0.4), seed: s); self.sleepNow(r, 0); self.put(r, 2, at: SIMD2(-2.1, 2.0), seed: s); self.sleepNow(r, 2) }
    }
    func testCallTwoThirdAwakeStandingInTheMiddle() {
        table("call two (0,1), the third awake, standing at the rug centre", called: [0, 1]) { r, _, s in self.put(r, 2, at: SIMD2(0, 0.4), seed: s) }
    }

    // MARK: a phone on its side
    func testLandscapeEveryoneAsleep() {
        table("landscape: all three asleep", aspect: 956 / 440) { r, _, _ in for i in 0..<3 { self.sleepNow(r, i) } }
    }
    func testLandscapeCallTwoThirdAsleepOnTheRug() {
        table("landscape: call two (0,1), the third asleep at the rug centre", called: [0, 1], aspect: 956 / 440) { r, _, s in self.put(r, 2, at: SIMD2(0, 0), seed: s); self.sleepNow(r, 2) }
    }
    func testLandscapeCallTwoThirdAsleepAtTheLeft() {
        table("landscape: call two (0,1), the third asleep at the left", called: [0, 1], aspect: 956 / 440) { r, _, s in self.put(r, 2, at: SIMD2(-2.4, 1.2), seed: s); self.sleepNow(r, 2) }
    }

    // MARK: with the real HUD button cut-outs in the floor (space-fix-r1): no called body under a button, none snapped by the clamp
    func testHUDPortraitCallTwoThirdAsleepAtTheFrontMiddle() {
        table("HUD portrait: call two (0,1), the third asleep at the front middle", called: [0, 1], hud: .portrait) { r, _, s in self.put(r, 2, at: SIMD2(0, 1.8), seed: s); self.sleepNow(r, 2) }
    }
    func testHUDLandscapeCallTwoThirdAsleepAtTheFrontMiddle() {
        table("HUD landscape: call two (0,1), the third asleep at the front middle", called: [0, 1], aspect: 956 / 440, hud: .landscape) { r, _, s in self.put(r, 2, at: SIMD2(0, 1.8), seed: s); self.sleepNow(r, 2) }
    }
    func testHUDLandscapeCallTwoThirdAsleepNearTheLeftButtons() {
        table("HUD landscape: call two (0,1), the third asleep at the front, near the bottom-left button column", called: [0, 1], aspect: 956 / 440, hud: .landscape) { r, _, s in self.put(r, 2, at: SIMD2(-1.6, 2.0), seed: s); self.sleepNow(r, 2) }
    }
    func testHUDLandscapeCallTwoThirdAsleepAtTheRugCentre() {
        table("HUD landscape: call two (0,1), the third asleep at the rug centre", called: [0, 1], aspect: 956 / 440, hud: .landscape) { r, _, s in self.put(r, 2, at: SIMD2(0, 0), seed: s); self.sleepNow(r, 2) }
    }

    /// The five rows that still failed (r1): run alone while iterating.
    func testPinnedRowsOnly() {
        table("PIN call one (1), the other two asleep (middle + side)", called: [1]) { r, _, s in self.put(r, 0, at: SIMD2(0, 0.4), seed: s); self.sleepNow(r, 0); self.put(r, 2, at: SIMD2(-2.1, 2.0), seed: s); self.sleepNow(r, 2) }
        table("PIN call two (0,1), the third asleep at the front middle", called: [0, 1]) { r, _, s in self.put(r, 2, at: SIMD2(0, 1.6), seed: s); self.sleepNow(r, 2) }
        table("PIN call two (1,2), Bob (0) asleep at the rug centre", called: [1, 2]) { r, _, s in self.put(r, 0, at: SIMD2(0, 0.4), seed: s); self.sleepNow(r, 0) }
        table("PIN HUD portrait front middle", called: [0, 1], hud: .portrait) { r, _, s in self.put(r, 2, at: SIMD2(0, 1.8), seed: s); self.sleepNow(r, 2) }
        table("PIN HUD landscape front middle", called: [0, 1], aspect: 956 / 440, hud: .landscape) { r, _, s in self.put(r, 2, at: SIMD2(0, 1.8), seed: s); self.sleepNow(r, 2) }
    }
}
