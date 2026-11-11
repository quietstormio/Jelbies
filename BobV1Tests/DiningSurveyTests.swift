//
//  DiningSurveyTests.swift
//  (Copied from the other session's survey harness, plus TRAY_ROBUST=0 (old behaviour), the excused list and a 'dropped for all while somebody eats' flag.)
//  MEASURE ONLY, off by default, never asserts on the results. The tray wake with three sleepers over several seeds:
//  who eats and when, when the group gives up (and why, as far as the test can see), when the group is over,
//  and how long a diner who has finished eating stays held by the sitting.
//
//  Run (Release):
//    TEST_RUNNER_TRAY_SURVEY=1 TEST_RUNNER_TRAY_SEEDS=21-50 TEST_RUNNER_TRAY_ARM=applike \
//      xcodebuild test-without-building ... -parallel-testing-enabled NO -only-testing:BobV1Tests/DiningSurveyTests/testTraySurvey
//  Variables (xcodebuild forwards TEST_RUNNER_<NAME> to the test process as <NAME>):
//    TRAY_SURVEY=1            enables the test (otherwise XCTSkip)
//    TRAY_SEEDS=21-50 | 21,25,28   default 21-30
//    TRAY_ARM=plain | applike      default plain
//      plain:   Lab(quiet: false, seed:), nothing set on the group
//      applike: group.tierOf = { _ in .normal } before start (the group then sets idleBlocked itself, as in the app) and rig 2's start spot varied by seed
//    TRAY_STANDS=old          NOT available on this tree (see the commented block below)
//
//  DiningGroup members read: init(), start(_:brains:floor:), tick(dt:), cancel(), dining (.reset()), tierOf (applike only),
//  gaveUp, isActive, isHolding(_:), walkRetries, reserves.  BlobBrain members read: position, isNapping, sleepEnabled, watching, idleNight,
//  idleDeepNight, idleState, restTimer, socialBook.cooldown, autonomy, activity.  GameCare.mealTimeout.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DiningSurveyTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset() }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset() }

    private let dt: Float = 1.0 / 60
    private static let window: Float = 75
    private static let spots: [SIMD2<Float>] = [SIMD2(-1.0, 2.6), SIMD2(0.0, 2.0), SIMD2(1.0, 1.5), SIMD2(-1.2, 1.0), SIMD2(1.2, 2.4)]

    private struct Result {
        var ate: [Float?]; var gaveUp: Float?; var gaveReason: String; var over: Float?; var maxHeld: Float; var maxHeldRig: Int; var maxHeldOpen: Bool; var excused: Int; var droppedWhileEating: Bool
        var timeout: Bool { gaveReason == "timeout" }
    }

    private static func parseSeeds(_ s: String?) -> [UInt64] {
        guard let s, !s.isEmpty else { return Array(21...30) }
        if s.contains(","), !s.contains("-") { return s.split(separator: ",").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) } }
        let p = s.split(separator: "-").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        if p.count == 2, p[0] <= p[1] { return Array(p[0]...p[1]) }
        return s.split(separator: ",").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
    }
    private static func f(_ x: Float?) -> String { x.map { String(format: "%.1f", $0) } ?? "nil" }

    private func runSeed(_ seed: UInt64, arm: String) -> Result {
        SleepOrder.reset()
        var positions = Array(SocialTests.starts)
        var spot = SocialTests.starts[2]
        if arm == "applike" { spot = Self.spots[Int(((seed - 1) / 2) % 5)]; positions[2] = spot }
        let lab = SocialTests.Lab(positions: positions, quiet: false, seed: seed)
        for r in lab.rigs {
            r.brain.sleepEnabled = true; r.brain.watching = true
            r.brain.idleNight = 1; r.brain.idleDeepNight = 1
            r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.5; r.brain.socialBook.cooldown = 1e6
        }
        for _ in 0..<120 { lab.tick(watching: false) }
        NightRestTuning.sendToBed(lab.rigs.map(\.brain))
        var bed: Float = 0
        while bed < 40, !lab.rigs.allSatisfy({ $0.brain.isNapping }) { lab.tick(watching: false); bed += dt }
        for _ in 0..<60 { lab.tick(watching: false) }
        let allAsleep = lab.rigs.allSatisfy { $0.brain.isNapping }
        SleepOrder.reset()
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0; r.brain.autonomy = false }
        let brains = lab.rigs.map(\.brain)
        let group = DiningGroup()
        if arm == "applike" { group.tierOf = { _ in .normal } }
        group.start(Consumables.berries, brains: brains, floor: { lab.rigs[$0].brain.position })

        var ate = [Float?](repeating: nil, count: 3)
        var lastEating = [Float?](repeating: nil, count: 3)       // last tick each rig was eating / drinking
        var releasedAt = [Float?](repeating: nil, count: 3)       // first tick after he had eaten that the sitting no longer holds him
        var gaveUp: Float?, reason = "", dropEating = false
        var over: Float?
        var t: Float = 0
        while t < Self.window {
            lab.tick(watching: false); group.tick(dt: lab.rigs[0].sim.stepDt); t += dt
            for (i, b) in brains.enumerated() {
                if b.activity == .eating || b.activity == .drinking { if ate[i] == nil { ate[i] = t }; lastEating[i] = t }
                if releasedAt[i] == nil, ate[i] != nil, !group.isHolding(i) { releasedAt[i] = t }
            }
            if over == nil, !group.isActive { over = t }
            if gaveUp == nil, group.gaveUp {
                gaveUp = t
                if (0..<3).contains(where: { lastEating[$0].map { t - $0 < 1.0 } ?? false }) { dropEating = true }
                if abs(t - GameCare.mealTimeout) >= 0.2, ate.contains(where: { $0 != nil }) { dropEating = true }          // (dropped for all by a retry rule while somebody had eaten)
                if abs(t - GameCare.mealTimeout) < 0.2 { reason = "timeout" } else {
                    let notEating = (0..<3).filter { ate[$0] == nil }
                    let walk = (0..<3).filter { group.walkRetries.indices.contains($0) && group.walkRetries[$0] >= 3 && ate[$0] == nil }
                    if !walk.isEmpty { reason = "retries(walkRetries>=3 rig \(walk.map(String.init).joined(separator: ",")); reserves \(group.reserves))" }
                    else { reason = "retries?(mealRetries private; not eating rig \(notEating.map(String.init).joined(separator: ",")); reserves \(group.reserves))" }
                }
            }
            if over != nil, !ate.contains(where: { $0 == nil }) { break }
        }
        // held time after eating ended: from the last tick he was eating to the tick the sitting let him go
        var maxHeld: Float = 0, maxRig = -1, open = false
        for i in 0..<3 {
            guard let le = lastEating[i] else { continue }
            let (h, isOpen): (Float, Bool) = releasedAt[i].map { ($0 - le, false) } ?? (t - le, true)
            if isOpen, brains[i].activity == .eating || brains[i].activity == .drinking { continue }
            if h > maxHeld || maxRig < 0 { maxHeld = h; maxRig = i; open = isOpen }
        }
        let n40 = ate.compactMap { $0 }.filter { $0 <= 40 }.count
        let nAll = ate.compactMap { $0 }.count
        let heldStr = maxRig < 0 ? "none" : String(format: "%.1f%@ rig %d", maxHeld, open ? "+" : "", maxRig)
        print("TRAYSURVEY arm \(arm) seed \(seed) | all asleep \(allAsleep) | rig2 start (\(spot.x), \(spot.y)) | ate rig0 \(Self.f(ate[0])) rig1 \(Self.f(ate[1])) rig2 \(Self.f(ate[2])) | ate<=40s \(n40) | ate<=window \(nAll) | gaveUp \(Self.f(gaveUp)) \(reason) | over \(Self.f(over)) | max held after eating \(heldStr) | excused \(group.excused) | end \((0..<3).map { "\(brains[$0].activity)/\(String(format: "%.2f", simd_distance(brains[$0].position, group.approachPoint(blob: $0))))/wr\(group.walkRetries.indices.contains($0) ? group.walkRetries[$0] : -1)" }) | droppedWhileEating \(dropEating) | sim \(Self.f(t)) s")
        group.cancel(); group.dining.reset()
        return Result(ate: ate, gaveUp: gaveUp, gaveReason: reason, over: over, maxHeld: maxHeld, maxHeldRig: maxRig, maxHeldOpen: open, excused: group.excused.filter { $0 }.count, droppedWhileEating: dropEating)
    }

    func testTraySurvey() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["TRAY_SURVEY"] == "1", "tray survey is off (set TRAY_SURVEY=1)")
        let arm = env["TRAY_ARM"] ?? "plain"
        DiningGroup.robust = env["TRAY_ROBUST"] != "0" && env["DINING_OLD"] == nil
        defer { DiningGroup.robust = ProcessInfo.processInfo.environment["DINING_OLD"] == nil }
        XCTAssertTrue(arm == "plain" || arm == "applike", "TRAY_ARM must be plain or applike")
        if env["TRAY_STANDS"] == "old" { XCTFail("TRAY_STANDS=old needs the solo-hangout tuning vars; not on this tree"); return }
        // SOLO-ONLY-BEGIN (switch on on the branch where IdleTuning is `var` and restAfterSpecial exists; then handle TRAY_STANDS == "old" here instead of failing above)
        // let keep = (IdleTuning.restAfterLeg, IdleTuning.wanderPickWait, IdleTuning.restAfterSpecial)
        // IdleTuning.restAfterLeg = 1.5...3.5; IdleTuning.wanderPickWait = 3...6; IdleTuning.restAfterSpecial = 1.0...2.5
        // defer { IdleTuning.restAfterLeg = keep.0; IdleTuning.wanderPickWait = keep.1; IdleTuning.restAfterSpecial = keep.2 }
        // SOLO-ONLY-END
        let seeds = Self.parseSeeds(env["TRAY_SEEDS"])
        var res: [Result] = []
        for s in seeds { res.append(runSeed(s, arm: arm)) }
        let n40 = { (r: Result) in r.ate.compactMap { $0 }.filter { $0 <= 40 }.count }
        let overs = res.compactMap(\.over).sorted()
        let median: Float? = overs.isEmpty ? nil : (overs.count % 2 == 1 ? overs[overs.count / 2] : (overs[overs.count / 2 - 1] + overs[overs.count / 2]) / 2)
        let gave = res.filter { $0.gaveUp != nil }
        let worst = res.filter { $0.maxHeldRig >= 0 }.max { $0.maxHeld < $1.maxHeld }
        let worstStr = worst.map { String(format: "%.1f%@", $0.maxHeld, $0.maxHeldOpen ? "+" : "") } ?? "none"
        print("TRAYSURVEY TOTALS arm \(arm) robust \(DiningGroup.robust) | dropped-for-all-while-eating \(res.filter(\.droppedWhileEating).count) | excuses \(res.map(\.excused).reduce(0, +)) | over>45s or never \(res.filter { ($0.over ?? 999) > 45 }.count) | held>3s \(res.filter { $0.maxHeldRig >= 0 && $0.maxHeld > 3 }.count) | seeds \(res.count) | >=2 ate within 40 s \(res.filter { n40($0) >= 2 }.count) | all 3 within 40 s \(res.filter { n40($0) >= 3 }.count) | all 3 within window \(res.filter { $0.ate.allSatisfy { $0 != nil } }.count) | gave up \(gave.count) (timeout \(gave.filter(\.timeout).count), retries \(gave.filter { !$0.timeout }.count)) | median over \(Self.f(median)) | largest held \(worstStr)")
    }
}
