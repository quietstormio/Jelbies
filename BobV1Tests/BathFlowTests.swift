//
//  BathFlowTests.swift
//  The Clean flow (de-lint -> soap -> rinse -> shine) end to end on the headless sim, through the REAL GameCare + BathFlow, plus the
//  BathLook math and the grime (lint) model. Fake touches go through `BathFlow.touch` exactly as the stage feeds it.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SilentSound: BathSound {
    var peels = 0
    func peel(kind: LintKind) { peels += 1 }
}

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

    init(lint: Int = 3) {
        rig = MotionRig(game: true, settle: 1.0)
        rig.sim.arenaCenter = GameCamera.arenaCenter
        rig.sim.arenaRadius = GameCamera.arenaRadius
        rig.brain.autonomy = false
        care.bath.sound = sound
        care.bath.haptic = { [unowned self] _, _ in self.hapticTicks += 1 }
        care.bath.success = { [unowned self] in self.successes += 1 }
        for _ in 0..<lint { care.bath.grime.addBit() }
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

    /// Fake finger for the current tool: sweeps the front of the body (the roller goes to the next bit).
    func scrub() {
        guard bath.acceptsTouch else { return }
        let c = sim.centroid()
        let a = t * 3.1, b = t * 1.3
        let az = sinf(a) * 1.3, polar = 1.5 + 0.9 * sinf(b)
        var dir = SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az))
        if bath.phase == .delint, let bit = bath.grime.bits.first(where: { $0.peel == 0 }) { dir = bit.dir }
        let l = dir * 0.62
        bath.touch(contact: true, hitLocal: l, world: c + l, speed: 2.5, dt: sim.stepDt)
    }

    func run(_ seconds: Float, scrubbing: Bool = true, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            if scrubbing { scrub() }
            tick()
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
        for k in 0..<400 {
            let t = Float(k) * 0.05
            let az = sinf(t * 3.1) * 1.3, polar = 1.5 + 0.9 * sinf(t * 1.3)
            s.paint(local: SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az)) * 0.62, radius: 0.18, amount: 0.4)
        }
        XCTAssertGreaterThan(s.coverage, BathTuning.soapDone, "scrubbing what he shows the camera gets to the soap threshold")
    }

    // MARK: grime

    func testLintAccumulatesByDistanceAndNotWhileIdle() {
        let g = BlobGrime(persists: false)
        for _ in 0..<600 { g.step(dt: 1, travelled: 0) }
        XCTAssertTrue(g.bits.isEmpty, "no lint while he stands still")
        g.step(dt: 0.1, travelled: g.unitsPerBit * 0.4)
        XCTAssertTrue(g.bits.isEmpty)
        g.step(dt: 0.1, travelled: g.unitsPerBit * 0.7)
        XCTAssertEqual(g.bits.count, 1, "one bit per unitsPerBit walked")
        for _ in 0..<40 { g.step(dt: 0.1, travelled: g.unitsPerBit) }
        XCTAssertEqual(g.bits.count, GrimeTuning.maxBits, "capped at 10")
        XCTAssertTrue(g.bits.contains { $0.kind == .drop }, "some bits are dropped Jelly Drops")
        var rng: UInt32 = 5
        for _ in 0..<500 {
            rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
            var s2 = rng
            let d = BlobGrime.spot(rand: { s2 ^= s2 << 13; s2 ^= s2 >> 17; s2 ^= s2 << 5; return Float(s2 >> 8) / Float(1 << 24) })
            XCTAssertLessThan(d.y, 0.85 + 0.15); XCTAssertGreaterThan(d.y, -0.7, "not the feet")
            XCTAssertFalse(d.z > 0.35 && d.y > -0.2 && d.y < 0.55 && abs(d.x) < 0.8, "not the face")
        }
    }

    func testLintComesFromWalkingInTheRoom() {
        let r = CleanRun(lint: 0)
        r.care.bath.grime.unitsPerBit = 1.5
        r.run(2, scrubbing: false)
        XCTAssertTrue(r.care.bath.grime.bits.isEmpty, "standing still: no lint")
        r.brain.request(.goTo(SIMD2(-2, -1.5)))
        r.run(10, scrubbing: false)
        r.brain.request(.goTo(SIMD2(2, 1.5)))
        r.run(10, scrubbing: false)
        XCTAssertGreaterThan(r.care.bath.grime.bits.count, 0, "walking adds lint")
        XCTAssertEqual(r.care.bath.look.lint, r.care.bath.grime.bits, "the look carries the lint in the room too")
    }

    func testPeelRemovesBitsAndAwardsADrop() {
        let g = BlobGrime(persists: false)
        let wallet = DropsWallet(persists: false)
        _ = g.addBit(); _ = g.addBit()
        for _ in 0..<8 { _ = g.addBit() }
        XCTAssertEqual(g.bits.filter { $0.kind == .drop }.count, 1)
        let bit = g.bits.first { $0.kind == .drop }!
        let hit = bit.dir * 0.62 + BathLook.centre * 0
        let n = g.startPeel(hit: hit, radius: 0.2)
        XCTAssertTrue(n.contains { g.bits[$0].kind == .drop })
        XCTAssertTrue(g.bits.filter { $0.peel > 0 }.allSatisfy { $0.peel < 1 })
        var gone: [LintBit] = []
        for _ in 0..<40 { gone += g.advancePeel(dt: 1.0 / 60) }
        for b in gone where b.kind == .drop { wallet.add() }
        XCTAssertEqual(wallet.count, 1, "peeling the dropped Jelly Drop pays one Drop")
        XCTAssertEqual(g.bits.count, 10 - gone.count)
    }

    func testRoomSparkleFadesAndNewLintKnocksItDown() {
        let g = BlobGrime(persists: false)
        g.sparkle = 1
        g.step(dt: GrimeTuning.sparkleSeconds / 2, travelled: 0)
        XCTAssertEqual(g.sparkle, 0.5, accuracy: 0.01, "fades slowly on its own")
        g.step(dt: 1, travelled: g.unitsPerBit)
        XCTAssertLessThan(g.sparkle, 0.5 - GrimeTuning.sparkleKnock + 0.01, "a new bit knocks it down")
        g.step(dt: GrimeTuning.sparkleSeconds, travelled: 0)
        XCTAssertEqual(g.sparkle, 0)
    }

    func testSoundGeneratorIsAValidWAV() {
        let d = PeelSound.makeWAV()
        XCTAssertEqual(String(decoding: d.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertGreaterThan(d.count, 3000)
    }

    // MARK: flow

    func testHappyPathPhaseOrderAndSparkle() {
        let r = CleanRun(lint: 3)
        Self.keep.append(r)
        r.care.clean()
        XCTAssertEqual(r.bath.phase, .exit)
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        let order = r.phases.filter { $0 != .exit }
        XCTAssertEqual(order, [.fade, .delint, .soap, .rinse, .shine, .finish, .fade, .off], "phases: \(r.phases)")
        XCTAssertGreaterThan(r.sound.peels, 0, "peeling plays the thwip")
        XCTAssertGreaterThan(r.hapticTicks, 0)
        XCTAssertEqual(r.successes, 1)
        XCTAssertTrue(r.care.bath.grime.bits.isEmpty, "all lint peeled")
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

    func testNoSparkleBeforeShine() {
        let r = CleanRun(lint: 2)
        Self.keep.append(r)
        r.care.bath.grime.sparkle = 0.9
        r.care.clean()
        var worst: Float = 0
        r.run(40, until: {
            if r.bath.phase == .delint || r.bath.phase == .soap || r.bath.phase == .rinse { worst = max(worst, r.bath.look.sparkle) }
            return r.bath.phase == .shine
        })
        XCTAssertEqual(r.bath.phase, .shine)
        XCTAssertEqual(worst, 0, "no sparkle during delint / soap / rinse (the old shine goes when he is washed)")
    }

    func testNoLintSkipsStraightToSoap() {
        let r = CleanRun(lint: 0)
        Self.keep.append(r)
        r.care.clean()
        r.run(30, until: { r.bath.phase == .soap })
        XCTAssertFalse(r.phases.contains(.delint))
        XCTAssertEqual(r.bath.phase, .soap)
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
        let firstTools = r.fenceByPhase.firstIndex { $0.0 == .delint || $0.0 == .soap }!
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
            ("delint", { $0.bath.phase == .delint }),
            ("soap", { $0.bath.phase == .soap && $0.bath.look.coverage > 0.2 }),
            ("rinse", { $0.bath.phase == .rinse }),
            ("shine", { $0.bath.phase == .shine }),
            ("finish", { $0.bath.phase == .finish }),
        ]
        for (name, cond) in stops {
            let r = CleanRun(lint: 2)
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
            if name == "soap" || name == "rinse" { XCTAssertGreaterThan(r.care.bath.grime.bits.count + 1, 0) }
        }
    }

    func testCancelKeepsRemainingLint() {
        let r = CleanRun(lint: 4)
        Self.keep.append(r)
        r.care.clean()
        r.run(30, scrubbing: false, until: { r.bath.phase == .delint })
        r.care.cancelClean()
        r.run(10, scrubbing: false, until: { r.bath.phase == .off })
        XCTAssertEqual(r.care.bath.grime.bits.count, 4, "nothing was peeled, nothing is lost")
        XCTAssertEqual(r.bath.look.lint.count, 4)
    }

    func testMenuRowIsDisabledDuringAMealAndABath() {
        let r = CleanRun(lint: 0)
        Self.keep.append(r)
        XCTAssertTrue(r.care.canClean)
        r.care.feed("berries")
        r.run(0.2, scrubbing: false)
        XCTAssertTrue(r.care.trayOut)
        XCTAssertFalse(r.care.canClean, "no clean-up while a tray is out")
        r.care.clean()
        XCTAssertEqual(r.bath.phase, .off, "ignored")
        // a bath blocks the other actions
        let b = CleanRun(lint: 0)
        Self.keep.append(b)
        b.care.clean()
        b.run(0.2, scrubbing: false)
        XCTAssertFalse(b.care.canClean)
        b.care.feed("berries"); b.care.comeHere(); b.care.wave()
        b.run(0.2, scrubbing: false)
        XCTAssertFalse(b.care.trayOut, "no tray during a clean-up")
        XCTAssertFalse(b.care.focus.isActive, "no come-here during a clean-up")
        // come-here focus disables it too
        let f = CleanRun(lint: 0)
        Self.keep.append(f)
        f.care.focus.force(.focused)
        XCTAssertFalse(f.care.canClean)
    }

    func testRoomSparkleFadesAfterTheCleanUp() {
        let r = CleanRun(lint: 0)
        Self.keep.append(r)
        r.care.clean()
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        XCTAssertEqual(r.bath.look.sparkle, 1, accuracy: 0.01)
        XCTAssertGreaterThan(r.wetSeen, 0.5)
        r.run(4, scrubbing: false)
        XCTAssertEqual(r.bath.look.wet, 0, accuracy: 0.001, "wet dries off in the room")
        let s0 = r.bath.look.sparkle
        r.care.bath.grime.step(dt: GrimeTuning.sparkleSeconds * 0.5, travelled: 0)
        r.run(0.1, scrubbing: false)
        XCTAssertLessThan(r.bath.look.sparkle, s0 - 0.3, "the room sparkle fades")
    }

    func testFeetAttachedAndArmsCappedThroughTheCleanUp() {
        let r = CleanRun(lint: 3)
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
