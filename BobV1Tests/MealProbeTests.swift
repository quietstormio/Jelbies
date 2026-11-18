//
//  MealProbeTests.swift
//  TEST-ONLY measuring probe (gate 9): when does the awake diner stand ready vs when does the tray pop (one awake + one asleep, n = 2).
//
import XCTest
import simd
@testable import BobV1

@MainActor
final class MealProbeTests: XCTestCase {
    private var savedHour: Double?
    private var savedAnywhere = SleepTuning.anywhere, savedGetUp = SleepTuning.getUpNew
    override func setUp() { savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12; RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset(); BlobBrain.softMealWake = true; savedAnywhere = SleepTuning.anywhere; savedGetUp = SleepTuning.getUpNew }
    override func tearDown() { SleepTuning.anywhere = savedAnywhere; SleepTuning.getUpNew = savedGetUp; DayClock.shared.forcedHour = savedHour; RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset() }
    private let dt: Float = 1.0 / 60

    private func night(n: Int, seed: UInt64) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: n, quiet: false, seed: seed)
        for r in lab.rigs {
            r.brain.sleepEnabled = true; r.brain.watching = true
            r.brain.idleNight = 1; r.brain.idleDeepNight = 1
            r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.5; r.brain.socialBook.cooldown = 1e6
        }
        for _ in 0..<120 { lab.tick(watching: false) }
        NightRestTuning.sendToBed(lab.rigs.map(\.brain))
        var t: Float = 0
        while t < 40, !lab.rigs.allSatisfy({ $0.brain.isNapping }) { lab.tick(watching: false); t += dt }
        for _ in 0..<60 { lab.tick(watching: false) }
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0; r.brain.autonomy = false }
        SleepOrder.reset()
        return lab
    }
    private func s(_ v: Float?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }

    struct Row { var ready: Float?, readyPos: Float?, pop: Float?, reason = "", bite: Float?, walk: Float = 0, path: Float = 0, sTray: Float = 0, sFront = false, origin = SIMD2<Float>.zero, f0 = SIMD2<Float>.zero, f1 = SIMD2<Float>.zero, places: [Int] = [], cross = "never" }

    private func runMeal(seed: UInt64, awake: [Int], fixed: Bool) -> Row {
        let savedPick = DiningSpot.pickOpen
        defer { DiningSpot.pickOpen = savedPick }
        if fixed { DiningSpot.pickOpen = { o in o.isEmpty ? nil : o[Int(seed) % o.count] } }
        let n = 2
        let lab = night(n: n, seed: seed)
        let brains = lab.rigs.map(\.brain)
        for i in awake { brains[i].sleepWake(groggy: false, fast: true) }
        var w: Float = 0
        while w < 10, awake.contains(where: { brains[$0].isSleeping }) { lab.tick(watching: false); w += dt }
        for _ in 0..<120 { lab.tick(watching: false) }
        SleepOrder.reset()
        let group = DiningGroup()
        group.start(Consumables.berries, brains: brains, floor: { lab.rigs[$0].brain.position })
        var r = Row()
        let stands = group.standsNow
        r.origin = group.originNow ?? .zero; r.places = group.placeOf
        r.f0 = brains[0].position; r.f1 = brains[1].position
        r.walk = simd_distance(r.f0, group.approachPoint(blob: 0))
        r.sTray = group.trayDistance(r.f1)
        r.sFront = r.f1.y > stands[group.placeOf[1]].y + GameCare.popTolerance
        var t: Float = 0, posT: Float = 0, last = r.f0
        func idle(_ b: BlobBrain) -> Bool { !b.mealWaking && (b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace) }
        while t < 30, r.bite == nil {
            lab.tick(watching: false); group.tick(dt: lab.rigs[0].sim.stepDt); t += dt
            let f = brains[0].position, ap = group.approachPoint(blob: 0), st = group.standsNow
            if r.pop == nil || r.ready == nil { r.path += simd_distance(f, last) }
            last = f
            let pos = !st.isEmpty && f.y <= st[group.placeOf[0]].y + GameCare.popTolerance && simd_distance(f, ap) < 0.5
            if pos, idle(brains[0]) {
                posT += dt
                if r.readyPos == nil { r.readyPos = t }
                let facing = abs(wrapAngle(brains[0].yaw - group.placeYaw(group.placeOf[0]))) < DiningGroup.calmFacing || posT >= DiningGroup.calmFacingWait
                if r.ready == nil, facing { r.ready = t }
            } else { posT = 0 }
            if r.pop == nil, group.dining.phase != .absent { r.pop = t }
            if brains[1].mealWaking, r.cross == "never", !st.isEmpty {
                let g = brains[1].position
                if g.y > st[group.placeOf[1]].y + GameCare.popTolerance { r.cross = "line@\(s(t))" }
                else if group.trayDistance(g) < DiningGroup.trayClearance { r.cross = "tray0.7@\(s(t))" }
            }
            if brains[0].activity == .eating || brains[0].activity == .drinking { r.bite = t }
        }
        r.reason = group.popReason
        group.cancel(); group.dining.reset()
        return r
    }

    func testProbe() {
        // measuring test only: does nothing unless TEST_RUNNER_MEALPROBE_CFG is set (r7, rowsleep, oldgetup, r7fixed, rowsleepfixed)
        guard let cfg = ProcessInfo.processInfo.environment["MEALPROBE_CFG"] else { return }
        let fixed = cfg.hasSuffix("fixed")
        switch cfg { case "rowsleep", "rowsleepfixed": SleepTuning.anywhere = false; case "oldgetup": SleepTuning.getUpNew = false; default: break }
        for seed in UInt64(1)...8 {
            let base = runMeal(seed: seed, awake: [0, 1], fixed: fixed)
            let m = runMeal(seed: seed, awake: [0], fixed: fixed)
            let pm = (m.pop != nil && m.ready != nil) ? m.pop! - m.ready! : nil
            let pmPos = (m.pop != nil && m.readyPos != nil) ? m.pop! - m.readyPos! : nil
            let diff = (m.bite != nil && base.bite != nil) ? m.bite! - base.bite! : nil
            let bm = (m.bite != nil && m.pop != nil) ? m.bite! - m.pop! : nil
            let line = "MEALPROBE cfg=\(cfg) seed=\(seed) ready=\(s(m.ready)) readyPosOnly=\(s(m.readyPos)) pop=\(s(m.pop)) reason=\(m.reason) popMinusReady=\(s(pm)) popMinusReadyPos=\(s(pmPos)) walk=\(s(m.walk)) path=\(s(m.path)) sleeperTrayDist=\(s(m.sTray)) sleeperInFront=\(m.sFront ? 1 : 0) sleeperCross=\(m.cross) bite=\(s(m.bite)) biteMinusPop=\(s(bm)) | baseTray=\(s(base.pop)) baseBite=\(s(base.bite)) diff=\(s(diff)) | origin=(\(s(m.origin.x)),\(s(m.origin.y))) baseOrigin=(\(s(base.origin.x)),\(s(base.origin.y))) awake0=(\(s(m.f0.x)),\(s(m.f0.y))) sleeper=(\(s(m.f1.x)),\(s(m.f1.y))) place=\(m.places)"
            print(line); MotionLog.write(line)
        }
    }
}
