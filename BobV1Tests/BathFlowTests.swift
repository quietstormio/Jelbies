//
//  BathFlowTests.swift
//  The Clean flow (soap -> rinse -> shine) end to end on the headless sim, through the REAL GameCare + BathFlow, plus the
//  BathLook math, the soot grid and the grime (dirt) model. Fake touches go through `BathFlow.touch` exactly as the stage feeds it.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SilentSound: BathSound {}

/// One clean-up on a game brain, ticked like the stage does (brain, care, sim step), with feet / arm probes every step.
@MainActor
final class CleanRun {
    let rig: MotionRig
    let sound = SilentSound()
    let care = GameCare()
    var bath: BathFlow { care.bath }
    var brain: BlobBrain { rig.brain }
    var sim: SoftBody { rig.sim }
    var t: Float = 0
    var phases: [BathPhase] = []
    var fenceByPhase: [(BathPhase, Bool, Float)] = []     // phase, fenceLifted, sim arena radius
    var feet = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
    var feetFrames = 0
    var arms = ArmCapTests.Stat()
    var maxZ: Float = 0
    var hapticTicks = 0, successes = 0
    var wetSeen: Float = 0
    var riseByPhase: [String: Float] = [:]
    var posLog: [String] = []

    init(dirt: Float = 0.5) {
        rig = MotionRig(game: true, settle: 1.0)
        rig.sim.arenaCenter = GameCamera.arenaCenter
        rig.sim.arenaRadius = GameCamera.arenaRadius
        rig.brain.autonomy = false
        care.bath.sound = sound
        care.bath.haptic = { [unowned self] _, _ in self.hapticTicks += 1 }
        care.bath.success = { [unowned self] in self.successes += 1 }
        care.bath.grime.dirt = dirt
        care.tick(brain: brain, renderer: nil, dt: sim.stepDt, sim: sim)
    }

    func tick(probe: Bool = true) {
        brain.tick(sim: sim, skinner: rig.skinner, dt: sim.stepDt, touched: false)
        care.tick(brain: brain, renderer: nil, dt: sim.stepDt, sim: sim)
        sim.step()
        care.refreshHeld(brain: brain, sim: sim, renderer: nil)
        t += sim.stepDt
        if phases.last != bath.phase { phases.append(bath.phase) }
        fenceByPhase.append((bath.phase, bath.fenceLifted, sim.arenaRadius))
        maxZ = max(maxZ, rig.root.y)
        if phases.contains(.finish), Int(t * 60) % 6 == 0 { posLog.append("\(bath.phase)/\(bath.fadeStage) w=\(bath.wipe) root=\(rig.root) brain=\(brain.position) \(brain.activity) \(brain.script) job=\(String(describing: brain.job)) pend=\(String(describing: brain.pending))") }
        wetSeen = max(wetSeen, bath.look.wet)
        if probe && bath.active && bath.wipe < 1 {          // the swap hides under the opaque white
            if let f = FeetAttachTests.footFrame(rig) { FeetAttachTests.accumulate(&feet, f); feetFrames += 1; let k = "\(bath.phase)/\(bath.fadeStage)"; riseByPhase[k] = max(riseByPhase[k] ?? 0, f.soleRise) }
            if brain.armG > 0.5 {
                for si in 0..<2 {
                    let g = brain.armLastGeom[si]
                    arms.add(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), rawB: SIMD3<Double>(brain.armLastRawTip[si]), r1: Double(g.r1), r2: Double(g.r2), led: brain.armShortW >= 0.95)
                }
            }
        }
    }

    /// Fake finger for the current tool: sweeps the front of the body.
    func scrub() {
        guard bath.acceptsTouch else { return }
        let c = sim.centroid()
        let a = t * 3.1, b = t * 1.3
        let az = sinf(a) * 1.3, polar = 1.5 + 0.9 * sinf(b)
        let dir = SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az))
        let l = dir * 0.62
        bath.touch(contact: true, hitLocal: l, world: c + l, speed: 2.5, dt: sim.stepDt)
    }

    /// Seconds spent in the finish card so far (autoNext presses Done after a beat).
    var finishAge: Float = 0
    /// `autoNext`: like a patient player, press Next when a stage is complete and Done on the finish card (the bath no longer advances by itself).
    func run(_ seconds: Float, scrubbing: Bool = true, autoNext: Bool = true, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            if scrubbing { scrub() }
            tick()
            if autoNext, bath.stageComplete { care.nextCleanStep() }
            if bath.phase == .finish { finishAge += sim.stepDt } else { finishAge = 0 }
            if autoNext, bath.phase == .finish, bath.wipe == 0, finishAge > 0.5 { care.finishClean() }
            if let until, until() { break }
        }
    }
}

@MainActor
final class BathFlowTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    // MARK: BathLook math

    func testCellMapping() {
        XCTAssertEqual(BathLook.cell(for: SIMD3(0, 1, 0)) / BathLook.cols, 0, "straight up is the top row")
        XCTAssertEqual(BathLook.cell(for: SIMD3(0, -1, 0)) / BathLook.cols, BathLook.rows - 1, "straight down is the bottom row")
        let front = BathLook.cell(for: SIMD3(0, 0, 1))
        XCTAssertTrue(front % BathLook.cols == 0 || front % BathLook.cols == BathLook.cols - 1, "+z is at column 0 (the seam)")
        let right = BathLook.cell(for: SIMD3(1, 0, 0.3)) % BathLook.cols
        XCTAssertTrue((0..<BathLook.cols / 4).contains(right), "+x side of the front is in the first quarter: azimuth increases toward +x")
        XCTAssertTrue((BathLook.cols * 3 / 4..<BathLook.cols).contains(BathLook.cell(for: SIMD3(-1, 0, 0.3)) % BathLook.cols), "-x side is the last quarter")
        XCTAssertEqual(BathLook.cell(for: SIMD3(0.05, 0, -1)) % BathLook.cols, BathLook.cols / 2 - 1, "the back is half way round")
        for i in 0..<(BathLook.rows * BathLook.cols) { XCTAssertEqual(BathLook.cell(for: BathLook.direction(ofCell: i)), i, "cell \(i) round trip") }
        XCTAssertEqual(BathLook.cell(for: SIMD3(0, 0, 0)), BathLook.cell(for: SIMD3(0, 0, 1)), "a zero vector falls back to the front")
    }

    func testPaintRinseClampAndFalloff() {
        var l = BathLook()
        let at = SIMD3<Float>(0, 0.064, 0.62)
        l.paint(local: at, radius: 0.18, amount: 0.4)
        let centre = l.foamAt(SIMD3(0, 0, 1)), far = l.foamAt(SIMD3(0, 0, -1))
        XCTAssertGreaterThan(centre, 0.05); XCTAssertEqual(far, 0, "far side untouched")
        l.paint(local: at, radius: 0.18, amount: 5)
        XCTAssertTrue(l.foam.allSatisfy { $0 >= 0 && $0 <= 1 }, "clamped 0...1")
        XCTAssertEqual(l.foam.max() ?? 0, 1, accuracy: 1e-6)
        l.rinse(local: at, radius: 0.18, amount: 1000)
        XCTAssertTrue(l.foam.allSatisfy { $0 == 0 }, "a strong rinse clears it and never goes below 0")
        // a wider brush covers more cells
        var a = BathLook(), b = BathLook()
        a.paint(local: at, radius: 0.1, amount: 1); b.paint(local: at, radius: 0.3, amount: 1)
        XCTAssertGreaterThan(b.foam.filter { $0 > 0 }.count, a.foam.filter { $0 > 0 }.count)
        XCTAssertEqual(BathLook.dry, BathLook())
    }

    func testCoverageDefinition() {
        var l = BathLook()
        XCTAssertEqual(l.coverage, 0)
        // the back and the base do not count
        for i in 0..<l.foam.count where BathLook.direction(ofCell: i).z < 0 || i / BathLook.cols >= BathLook.rows - 2 { l.foam[i] = 1 }
        XCTAssertEqual(l.coverage, 0, accuracy: 1e-6, "foam on the back / base is not coverage")
        l.foam = Array(repeating: 1, count: l.foam.count)
        XCTAssertEqual(l.coverage, 1, accuracy: 1e-5)
        // scrubbing the front reaches the soap threshold
        var s = BathLook()
        for k in 0..<1200 {
            let t = Float(k) * 0.05
            let az = sinf(t * 3.1) * 1.3, polar = 1.5 + 0.9 * sinf(t * 1.3)
            s.paint(local: SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az)) * 0.62, radius: 0.18, amount: 0.4)
        }
        XCTAssertGreaterThan(s.coverage, BathTuning.soapDone, "scrubbing what he shows the camera gets to the soap threshold")
    }

    // MARK: grime

    func testDirtAccumulatesByDistanceAndNotWhileIdle() {
        let g = BlobGrime(persists: false)
        for _ in 0..<600 { g.step(dt: 1, travelled: 0) }
        XCTAssertEqual(g.dirt, 0, "no dirt while he stands still")
        g.step(dt: 0.1, travelled: GrimeTuning.roamUnitsPer5Min)
        XCTAssertEqual(g.dirt, GrimeTuning.dirtPer5Min, accuracy: 1e-5, "0.02 per 5 min of normal roaming")
        for _ in 0..<400 { g.step(dt: 0.1, travelled: GrimeTuning.roamUnitsPer5Min) }
        XCTAssertEqual(g.dirt, 1, "capped at 1")
        XCTAssertEqual(g.coat, .filthy)
    }

    func testDirtComesFromWalkingInTheRoom() {
        let r = CleanRun(dirt: 0)
        r.care.bath.grime.dirtPerUnit = 0.05
        r.run(2, scrubbing: false)
        XCTAssertEqual(r.care.bath.grime.dirt, 0, "standing still: no dirt")
        r.brain.request(.goTo(SIMD2(-2, -1.5)))
        r.run(10, scrubbing: false)
        r.brain.request(.goTo(SIMD2(2, 1.5)))
        r.run(10, scrubbing: false)
        XCTAssertGreaterThan(r.care.bath.grime.dirt, 0, "walking adds dirt")
        XCTAssertEqual(r.care.bath.look.dirt, r.care.bath.grime.dirt, accuracy: 1e-6, "the look carries the dirt for the soot pass")
    }

    func testWalletCounts() {
        let w = DropsWallet(persists: false)
        w.add(); w.add(2)
        XCTAssertEqual(w.count, 3)
    }

    func testRoomSparkleFadesAndDirtEndsIt() {
        let g = BlobGrime(persists: false)
        g.sparkle = 1
        g.step(dt: GrimeTuning.sparkleFade / 2, travelled: 0)
        XCTAssertEqual(g.sparkle, 0.5, accuracy: 0.01, "fades slowly on its own")
        XCTAssertEqual(g.coat, .beautiful)
        g.step(dt: 1, travelled: GrimeTuning.roamUnitsPer5Min * 0.5)        // 0.01 dirt: still clean, still sparkling
        XCTAssertGreaterThan(g.sparkle, 0.4)
        g.step(dt: 1, travelled: GrimeTuning.roamUnitsPer5Min * 2.5)        // past the clean line
        XCTAssertEqual(g.sparkle, 0, "enough dirt ends the sparkle at once")
        XCTAssertEqual(g.coat, .normal)
        g.sparkle = 1
        g.step(dt: GrimeTuning.sparkleFade, travelled: 0)
        XCTAssertEqual(g.sparkle, 0)
    }

    func testSudBubblesOnlyInTheBath() {
        let r = CleanRun(dirt: 0.5)
        Self.keep.append(r)
        XCTAssertTrue(r.bath.look.bubbles.isEmpty)
        r.care.clean()
        var seenSoap = false
        r.run(60, until: {
            let ph = r.bath.phase
            if ph == .soap || ph == .rinse { seenSoap = seenSoap || !r.bath.look.bubbles.isEmpty }
            else if ph != .shine { XCTAssertTrue(r.bath.look.bubbles.isEmpty, "no bubbles in \(ph)") }
            return r.bath.phase == .off && r.phases.contains(.finish)
        })
        XCTAssertTrue(seenSoap)
        XCTAssertTrue(r.bath.look.bubbles.isEmpty)
        // cancelled mid-soap: cleared on the way back
        let c = CleanRun(dirt: 0)
        Self.keep.append(c)
        c.care.clean()
        c.run(30, until: { c.bath.phase == .soap && !c.bath.look.bubbles.isEmpty })
        XCTAssertFalse(c.bath.look.bubbles.isEmpty)
        c.bath.cancel(brain: c.brain, sim: c.sim)
        c.run(30, until: { c.bath.phase == .off })
        XCTAssertTrue(c.bath.look.bubbles.isEmpty)
    }

    // MARK: flow

    func testHappyPathPhaseOrderAndSparkle() {
        let r = CleanRun(dirt: 0.5)
        Self.keep.append(r)
        r.care.clean()
        XCTAssertEqual(r.bath.phase, .exit)
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        let order = r.phases.filter { $0 != .exit }
        XCTAssertEqual(order, [.fade, .soap, .rinse, .shine, .finish, .fade, .off], "phases: \(r.phases)")
        XCTAssertGreaterThan(r.hapticTicks, 0)
        XCTAssertEqual(r.successes, 1)
        XCTAssertEqual(r.care.bath.grime.dirt, 0, "the clean-up takes all the dirt")
        XCTAssertTrue(r.bath.look.soot.allSatisfy { $0 == 0 }, "and all the soot")
        XCTAssertGreaterThan(r.maxZ, GameCamera.walkMaxZ + 0.5, "he ran out past the normal floor")
        XCTAssertFalse(r.bath.fenceLifted)
        XCTAssertEqual(r.sim.arenaRadius, GameCamera.arenaRadius)
        XCTAssertEqual(r.bath.cameraBlend, 0)
        XCTAssertFalse(r.bath.look.visible)
        XCTAssertTrue(r.brain.autonomy == false, "autonomy is back to what it was (this rig had it off)")
        XCTAssertFalse(r.brain.hurry)
        XCTAssertEqual(r.bath.look.coverage, 0, accuracy: 0.001)
        XCTAssertEqual(r.bath.look.sparkle, 1, accuracy: 0.01, "he keeps sparkling in the room")
        XCTAssertGreaterThan(r.wetSeen, 0.5)
        let p = GameCamera.callSpot
        XCTAssertLessThan(simd_distance(r.rig.root, p), 0.8, "back at the front spot " + r.posLog.suffix(30).joined(separator: " | "))
    }

    // MARK: the player completes every stage

    private func reachSoapDone(_ r: CleanRun) {
        r.care.clean()
        r.run(60, autoNext: false, until: { r.bath.phase == .soap && r.bath.stageComplete })
    }

    func testSoapWaitsForNext() {
        let r = CleanRun(dirt: 0.5); Self.keep.append(r)
        reachSoapDone(r)
        XCTAssertEqual(r.bath.phase, .soap); XCTAssertTrue(r.bath.stageComplete); XCTAssertEqual(r.bath.progress, 1)
        r.run(40, autoNext: false)
        XCTAssertEqual(r.bath.phase, .soap, "40 more seconds of scrubbing: still soap"); XCTAssertEqual(r.bath.progress, 1)
        XCTAssertEqual(r.bath.prompt, "All soapy! Tap Next")
        r.care.nextCleanStep()
        XCTAssertEqual(r.bath.phase, .rinse); XCTAssertFalse(r.bath.stageComplete)
        XCTAssertEqual(r.bath.prompt, "Rinse all the suds off")
    }

    func testRinseAndShineWaitForNext() {
        let r = CleanRun(dirt: 0.5); Self.keep.append(r)
        reachSoapDone(r)
        r.care.nextCleanStep()
        r.run(60, autoNext: false, until: { r.bath.stageComplete })
        XCTAssertEqual(r.bath.phase, .rinse); XCTAssertTrue(r.bath.stageComplete)
        r.run(20, autoNext: false); XCTAssertEqual(r.bath.phase, .rinse, "rinse waits")
        XCTAssertEqual(r.bath.prompt, "Squeaky clean! Tap Next")
        r.care.nextCleanStep()
        XCTAssertEqual(r.bath.phase, .shine); XCTAssertFalse(r.bath.stageComplete)
        r.run(60, autoNext: false, until: { r.bath.stageComplete })
        XCTAssertEqual(r.bath.phase, .shine); XCTAssertTrue(r.bath.stageComplete)
        r.run(20, autoNext: false); XCTAssertEqual(r.bath.phase, .shine, "shine waits")
        r.care.nextCleanStep()
        XCTAssertEqual(r.bath.phase, .finish)
    }

    func testNextIsIgnoredBeforeTheStageIsDone() {
        let r = CleanRun(dirt: 0.5); Self.keep.append(r)
        r.care.clean()
        r.run(60, autoNext: false, until: { r.bath.phase == .soap && r.bath.look.coverage > 0.3 })
        XCTAssertFalse(r.bath.stageComplete)
        r.care.nextCleanStep()
        XCTAssertEqual(r.bath.phase, .soap, "Next does nothing while the soap is not done")
        r.bath.advance(); XCTAssertEqual(r.bath.phase, .soap)
    }

    func testFinishWaitsForDone() {
        let r = CleanRun(dirt: 0.5); Self.keep.append(r)
        r.care.clean()
        r.run(120, until: { r.bath.phase == .finish })
        XCTAssertEqual(r.bath.phase, .finish)
        r.run(10, scrubbing: false, autoNext: false)
        XCTAssertEqual(r.bath.phase, .finish, "the finish card waits"); XCTAssertEqual(r.bath.wipe, 0)
        r.care.finishClean()
        r.run(20, scrubbing: false, autoNext: false, until: { r.bath.phase == .off })
        XCTAssertEqual(r.bath.phase, .off)
    }

    func testNoDemoScrubsInNormalPlay() {
        let r = CleanRun(dirt: 0.5); Self.keep.append(r)
        XCTAssertFalse(r.bath.demo)
        r.care.clean()
        r.run(30, scrubbing: false, autoNext: false, until: { r.bath.phase == .soap })
        XCTAssertEqual(r.bath.phase, .soap)
        r.run(10, scrubbing: false, autoNext: false)
        XCTAssertEqual(r.bath.look.coverage, 0, accuracy: 1e-6); XCTAssertEqual(r.bath.progress, 0)
        XCTAssertEqual(r.bath.phase, .soap)
    }

    func testPromptsArePersistentPerStage() {
        let r = CleanRun(dirt: 0.5); Self.keep.append(r)
        r.care.clean()
        r.run(30, scrubbing: false, autoNext: false, until: { r.bath.phase == .soap })
        var seen = Set<String>()
        func sample(_ label: String) {
            for _ in 0..<12 {
                r.run(0.5, scrubbing: false, autoNext: false)
                XCTAssertNotNil(r.bath.prompt, "\(label): the prompt stays up"); seen.insert(r.bath.prompt ?? "")
            }
        }
        sample("soap")
        r.run(60, autoNext: false, until: { r.bath.stageComplete })
        XCTAssertNotEqual(r.bath.prompt, "Scrub on the jelly soap", "the prompt changes on completion")
        r.care.nextCleanStep()
        sample("rinse")
        XCTAssertTrue(seen.contains("Scrub on the jelly soap")); XCTAssertTrue(seen.contains("Rinse all the suds off"))
    }

    func testFeetAttachedWhileWaitingInTheTub() {
        let r = CleanRun(dirt: 0.5); Self.keep.append(r)
        reachSoapDone(r)
        r.run(20, scrubbing: false, autoNext: false)
        XCTAssertEqual(r.bath.phase, .soap)
        FeetAttachTests.check("waiting in the tub", r.feet, frames: r.feetFrames)
        XCTAssertGreaterThan(r.feetFrames, 100)
        XCTAssertLessThanOrEqual(r.arms.capMax, ArmCap.maximum * 1.02, "arms within the wave's maximum")
    }

    func testNoSparkleBeforeShine() {
        let r = CleanRun(dirt: 0.5)
        Self.keep.append(r)
        r.care.bath.grime.sparkle = 0.9
        r.care.clean()
        var worst: Float = 0
        r.run(120, until: {
            if r.bath.phase == .soap || r.bath.phase == .rinse { worst = max(worst, r.bath.look.sparkle) }
            return r.bath.phase == .shine
        })
        XCTAssertEqual(r.bath.phase, .shine)
        XCTAssertEqual(worst, 0, "no sparkle during soap / rinse (the old shine goes when he is washed)")
    }

    func testCleanStartsAtTheSoapAndHasThreeTools() {
        let r = CleanRun(dirt: 0.5)
        Self.keep.append(r)
        r.care.clean()
        r.run(30, until: { r.bath.phase == .soap })
        XCTAssertEqual(r.bath.phase, .soap)
        XCTAssertEqual(r.bath.currentTool, .soap)
        XCTAssertEqual(r.phases.filter { $0 == .soap || $0 == .rinse || $0 == .shine }.count, 1)
    }

    func testFenceIsLiftedOnlyInTheExit() {
        let r = CleanRun()
        Self.keep.append(r)
        XCTAssertFalse(r.bath.fenceLifted)
        r.care.clean()
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        // lifted for the exit run (the fade-out under which he keeps running to the cut counts as part of it), never once the bath is shown
        for (ph, lifted, radius) in r.fenceByPhase {
            if ph == .exit { XCTAssertTrue(lifted && radius.isInfinite, "lifted in exit") }
            else if ph != .fade { XCTAssertFalse(lifted, "fence flag off in \(ph)"); XCTAssertEqual(radius, GameCamera.arenaRadius, "fence back in \(ph)") }
            XCTAssertEqual(radius.isInfinite, lifted, "the sim fence follows the flag")
        }
        XCTAssertEqual(r.fenceByPhase.filter { $0.0 == .fade && $0.1 }.count > 0, true)
        let firstTools = r.fenceByPhase.firstIndex { $0.0 == .soap }!
        XCTAssertFalse(r.fenceByPhase[firstTools...].contains { $0.1 }, "never lifted again after the exit")
        XCTAssertTrue(r.fenceByPhase.contains { $0.0 == .exit && $0.1 })
    }

    func testTheWorldSwapsOnlyWhileTheWhiteIsOpaque() {
        let r = CleanRun()
        Self.keep.append(r)
        r.care.clean()
        var prevWipe: Float = 0
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        XCTAssertEqual(r.bath.swapLog.count, 2, "one swap into the bath, one back")
        for s in r.bath.swapLog { XCTAssertEqual(s.wipe, 1, "swapped while fully white") }
        XCTAssertEqual(r.bath.swapLog.map { $0.dest == .bath }, [true, false])
        // the camera and the set flip only inside the fade: check the first bath frame had a white overlay
        let r2 = CleanRun(); Self.keep.append(r2)
        r2.care.clean()
        var sawVisibleWhileClear = false
        for _ in 0..<(60 * 20) {
            r2.scrub(); r2.tick()
            if r2.bath.look.visible && r2.bath.wipe < 1 && r2.bath.fadeStage == .out { sawVisibleWhileClear = true }
            if r2.bath.acceptsTouch { break }
            prevWipe = r2.bath.wipe
        }
        _ = prevWipe
        XCTAssertFalse(sawVisibleWhileClear)
        XCTAssertEqual(r2.bath.cameraBlend, 1, "camera is on the bath close-up")
        XCTAssertTrue(r2.bath.look.visible)
        XCTAssertEqual(r2.bath.wipe, 0, accuracy: 1e-6, "the overlay is gone when the tools come up")
        let c = r2.sim.centroid()
        XCTAssertLessThan(abs(c.z - BathFlow.standPoint.z), 0.35, "he stands at the stand point")
        XCTAssertLessThan(abs(c.x), 0.35)
    }

    func testCancelFromEveryPhaseRestoresEverything() {
        let stops: [(String, (CleanRun) -> Bool)] = [
            ("exit", { $0.bath.phase == .exit && $0.maxZ > 3.4 }),
            ("exit (early)", { $0.bath.phase == .exit && $0.t > 0.5 }),
            ("fade", { $0.bath.phase == .fade && $0.bath.wipe > 0.5 }),
            ("soap", { $0.bath.phase == .soap && $0.bath.look.coverage > 0.2 }),
            ("rinse", { $0.bath.phase == .rinse }),
            ("shine", { $0.bath.phase == .shine }),
            ("finish", { $0.bath.phase == .finish }),
        ]
        for (name, cond) in stops {
            let r = CleanRun(dirt: 0.5)
            Self.keep.append(r)
            r.brain.autonomy = true
            r.care.clean()
            var reached = false
            r.run(60, until: { reached = cond(r); return reached })
            XCTAssertTrue(reached, "reached \(name)")
            r.care.cancelClean()
            r.run(25, scrubbing: false, until: { r.bath.phase == .off })
            XCTAssertEqual(r.bath.phase, .off, "\(name): cancel ends the clean-up")
            r.run(1, scrubbing: false)
            XCTAssertFalse(r.bath.fenceLifted, name)
            XCTAssertEqual(r.sim.arenaRadius, GameCamera.arenaRadius, "\(name): fence back")
            XCTAssertTrue(r.brain.autonomy, "\(name): autonomy back")
            XCTAssertFalse(r.brain.hurry, "\(name): hurry cleared")
            XCTAssertEqual(r.bath.cameraBlend, 0, "\(name): camera home")
            XCTAssertFalse(r.bath.look.visible, "\(name): bath set hidden")
            XCTAssertEqual(r.bath.look.coverage, 0, accuracy: 0.001, "\(name): foam cleared")
            XCTAssertNil(r.bath.look.spray); XCTAssertNil(r.bath.look.toolAt); XCTAssertTrue(r.bath.look.bubbles.isEmpty)
            XCTAssertEqual(r.bath.look.tool, .none)
            XCTAssertEqual(r.bath.wipe, 0, accuracy: 1e-6, "\(name): no white left")
            XCTAssertFalse(r.care.focus.isActive, "\(name): focus untouched")
            XCTAssertLessThanOrEqual(r.rig.root.y, GameCamera.walkMaxZ + 0.2, "\(name): back on the floor")
            XCTAssertTrue(r.care.canClean, "\(name): the menu row is back")
            XCTAssertEqual(r.care.bath.grime.dirt, name == "finish" ? 0 : 0.5, accuracy: 0.001, "\(name): a cancelled clean keeps his dirt (a finished one took it)")
        }
    }

    func testCancelKeepsTheSootAndTheRoomShowsIt() {
        let r = CleanRun(dirt: 0.5)
        Self.keep.append(r)
        let seed = BathLook.sootSeed(dirt: 0.5)
        r.run(0.3, scrubbing: false)
        XCTAssertEqual(r.bath.look.soot, seed, "the room shows the stable seed for his dirt")
        r.care.clean()
        r.run(30, scrubbing: true, until: { r.bath.phase == .rinse })
        XCTAssertEqual(r.bath.look.soot, seed, "soaping greys the suds but leaves the soot; rinsing is what lifts it")
        var before = BathLook(); before.soot = seed
        r.run(30, until: { r.bath.phase == .shine })
        XCTAssertLessThan(r.bath.look.sootMean, before.sootMean * 0.4, "rinsing the suds washed most of the soot he shows the camera")
        r.care.cancelClean()
        r.run(15, scrubbing: false, until: { r.bath.phase == .off })
        r.run(1, scrubbing: false)
        XCTAssertEqual(r.bath.look.soot, seed, "cancelled: he is as dirty as before, so the soot is back")
    }

    func testMenuRowIsDisabledDuringAMealAndABath() {
        let r = CleanRun(dirt: 0)
        Self.keep.append(r)
        XCTAssertTrue(r.care.canClean)
        r.care.feed("berries")
        r.run(0.2, scrubbing: false)
        XCTAssertTrue(r.care.trayOut)
        XCTAssertFalse(r.care.canClean, "no clean-up while a tray is out")
        r.care.clean()
        XCTAssertEqual(r.bath.phase, .off, "ignored")
        // a bath blocks the other actions
        let b = CleanRun(dirt: 0)
        Self.keep.append(b)
        b.care.clean()
        b.run(0.2, scrubbing: false)
        XCTAssertFalse(b.care.canClean)
        b.care.feed("berries"); b.care.comeHere(); b.care.wave()
        b.run(0.2, scrubbing: false)
        XCTAssertFalse(b.care.trayOut, "no tray during a clean-up")
        XCTAssertFalse(b.care.focus.isActive, "no come-here during a clean-up")
        // come-here focus disables it too
        let f = CleanRun(dirt: 0)
        Self.keep.append(f)
        f.care.focus.force(.focused)
        XCTAssertFalse(f.care.canClean)
    }

    func testRoomSparkleFadesAfterTheCleanUp() {
        let r = CleanRun(dirt: 0)
        Self.keep.append(r)
        r.care.clean()
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        XCTAssertEqual(r.bath.look.sparkle, 1, accuracy: 0.01)
        XCTAssertGreaterThan(r.wetSeen, 0.5)
        r.run(4, scrubbing: false)
        XCTAssertEqual(r.bath.look.wet, 0, accuracy: 0.001, "wet dries off in the room")
        let s0 = r.bath.look.sparkle
        r.care.bath.grime.step(dt: GrimeTuning.sparkleFade * 0.5, travelled: 0)
        r.run(0.1, scrubbing: false)
        XCTAssertLessThan(r.bath.look.sparkle, s0 - 0.3, "the room sparkle fades")
    }

    func testFeetAttachedAndArmsCappedThroughTheCleanUp() {
        let r = CleanRun(dirt: 0.5)
        Self.keep.append(r)
        r.care.clean()
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        FeetAttachTests.check("clean-up", r.feet, frames: r.feetFrames)
        XCTAssertGreaterThan(r.feetFrames, 100, "the beans were out for part of it")
        XCTAssertLessThanOrEqual(r.arms.capMax, ArmCap.maximum * 1.02, "arms within the wave's maximum")
        if r.arms.frames > 0 { XCTAssertGreaterThanOrEqual(r.arms.minDepth, 0.015, "arm bases stay buried") }
        for (n, led) in [("bath", r.arms.ledMax)] where r.arms.ledFrames > 0 { XCTAssertLessThanOrEqual(led, ArmCap.restNub * 1.10, n) }
    }

    func testTeleportLeavesNoVelocity() {
        let r = MotionRig(game: true, settle: 1)
        Self.keep.append(r)
        r.sim.teleport(toXZ: SIMD2(1.5, 2.0))
        r.brain.px = 1.5; r.brain.pz = 2.0
        let c = r.sim.centroid()
        XCTAssertEqual(c.x, 1.5, accuracy: 1e-3); XCTAssertEqual(c.z, 2.0, accuracy: 1e-3)
        XCTAssertLessThan(simd_length(r.sim.meanVelocity()), 1e-4)
        r.run(1)
        XCTAssertLessThan(abs(r.sim.centroid().x - 1.5), 0.05, "settles where it was put")
        XCTAssertLessThan(r.sim.kineticEnergy() / r.sim.totalMass, 0.05)
    }
}
