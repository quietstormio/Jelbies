//
//  DiningFlowTests.swift
//  The tray meal end to end on the headless sim, through the REAL care flow (GameCare + DiningSet + the brain's dining hooks):
//  tap -> tray pops in -> walk to his place -> stepped turn -> body-led lean -> grab -> straighten -> chomp x 3 -> happy -> tray poofs
//  -> back to rest. Finger food (berries), pizza (3 slices) and the sip (water, soda).
//

import XCTest
import simd
@testable import BobV1

/// One meal on a game brain, ticked like the stage does (brain, care, sim step).
@MainActor
final class MealRun {
    struct Frame {
        var t: Float
        var activity: BlobActivity
        var phase: String
        var mouth: Float
        var window: Bool
        var holding: Bool
        var forkHeld: Bool
        var capsuleOut: Bool
        var armPath: Bool
        var eyes: Float
        var heldDist: Float?                // |what he holds - the nub grip| after the sim step
        var mouthToStraw: Float?
        var fill: Float
        var forkVisible = false
        var armS: Float = 0
        var pre: Float?
        var flying = false
        var landed = false
        var landDist: Float?                // the landed bite to the mouth centre
        var arc: Float?                     // in flight: distance of the bite from the straight line launch -> mouth
        var flickSeconds: Float = 0
        var brow: SIMD2<Float>?             // apparent slant of the left / right brow (rad, inner end up), sampled
        var miss: Float = 0
        var trayPhase: DiningSet.Phase
    }

    let rig: MotionRig
    let care = GameCare()
    var frames: [Frame] = []
    var lastHold: SIMD3<Float>?
    var lastBite: SIMD3<Float>?
    var lastForkNub: SIMD3<Float>?
    var browLog: [(t: Float, slant: SIMD2<Float>)] = []
    static let browIdx = buildEyeRig(render: MotionRig.renderMesh, sim: MotionRig.simMesh).brow
    var wrapped = false
    var arrival: (dist: Float, yaw: Float)?
    var arrivalRoot = SIMD2<Float>(0, 0)
    var swapped = false
    var started: Float?
    var restTilt: Float = 0
    var restBrow = SIMD2<Float>(0, 0)
    var firstLeanFrame: Int?

    var tray: DiningSet { care.dining }
    var brain: BlobBrain { rig.brain }

    init(settle: Float = 1.0) {
        rig = MotionRig(game: true, settle: settle)
        rig.brain.autonomy = false
    }

    /// One fixed step: brain, care (tray), sim; records a frame.
    func tick() {
        lastHold = nil; lastBite = nil
        let b = rig.brain
        b.tick(sim: rig.sim, skinner: rig.skinner, dt: rig.sim.stepDt, touched: false)
        care.tick(brain: b, renderer: nil, dt: rig.sim.stepDt)
        if !wrapped, var h = b.dineHooks {                           // observe what the brain hands to the tray (the wiring itself is the game's)
            let hold = h.hold, holdFork = h.holdFork
            h.hold = { [unowned self] m in
                let g = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                self.lastHold = g; self.lastBite = g; hold(m)
            }
            h.holdFork = { [unowned self] m in
                let g = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                let y = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z), z = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
                // the fork's grip stays on the nub; the forkful sits on the tines until it is tossed
                self.lastHold = g
                if !self.brain.dineFlying { self.lastBite = g + z * DineGeometry.forkLength + y * DineGeometry.forkBiteLift }
                holdFork(m)
            }
            let holdBite = h.holdBite
            h.holdBite = { [unowned self] m in self.lastBite = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z); holdBite(m) }
            b.dineHooks = h; wrapped = true
        }
        let pre = lastHold.map { simd_distance($0, b.nubTipWorld(sim: rig.sim)) }       // as sent by the tick, before the step: the lag the refresh removes
        rig.sim.step()
        care.refreshHeld(brain: b, sim: rig.sim, renderer: nil)         // what the stage does after the frame's last step
        rig.t += rig.sim.stepDt
        let dining = b.activity == .eating || b.activity == .drinking
        var landDist: Float?, arc: Float?
        if dining, b.dineHolding, b.dineFlying, let bite = lastBite {
            let mc = b.mouthWorld(sim: rig.sim)
            if b.dineLanded { landDist = simd_distance(bite, mc) }
            else {
                let a0 = b.dineLaunchWorld, d = mc - a0
                let t = min(1, max(0, simd_dot(bite - a0, d) / max(simd_length_squared(d), 1e-6)))
                arc = simd_distance(bite, a0 + d * t)
            }
        }
        var brow: SIMD2<Float>?
        if dining {
            brow = browSlant()
        }
        var held: Float?
        if let h = lastHold { held = simd_distance(h, b.nubTipWorld(sim: rig.sim)) }
        var straw: Float?
        if dining, b.dineIsSipping, b.dinePhaseName == "chew", let tip = tray.strawTip(place: 0) { straw = simd_distance(b.mouthWorld(sim: rig.sim), tip) }
        if dining, arrival == nil, !tray.places.isEmpty {
            arrival = (simd_distance(b.position, tray.places[0].stand + SIMD2(0, 1) * (b.dineIsSipping ? GameCare.sipCloser : GameCare.eatCloser)), abs(wrapPi(b.heading - tray.places[0].yaw)))
            MotionLog.write("DINEFLOW arrival: brain root \(b.position) stand \(tray.places[0].stand) body centroid \(rig.root) heading \(b.heading) body yaw \(rig.poseYaw)")
            firstLeanFrame = frames.count
            arrivalRoot = b.position
        }
        frames.append(Frame(t: rig.t, activity: b.activity, phase: dining ? b.dinePhaseName : "-", mouth: b.mouthOpen, window: b.dineMouthWindow,
                            holding: b.dineHolding, forkHeld: b.dineForkHeld, capsuleOut: b.armCapsuleOut, armPath: b.armPathActive,
                            eyes: rig.skinner.openness.left, heldDist: held, mouthToStraw: straw, fill: tray.drinkFill, forkVisible: tray.forkVisible.first ?? false, armS: b.dineArmS, pre: pre, flying: b.dineFlying, landed: b.dineLanded, landDist: landDist, arc: arc, brow: brow, miss: b.dineReachMiss, trayPhase: tray.phase))
    }

    /// Apparent slant (rad, inner end up) of each brow as the game camera sees the skinned render mesh.
    func browSlant() -> SIMD2<Float> {
        rig.render()
        let vp = GameCamera.camera(aspect: GameCamera.aspect).viewProj
        func scr(_ v: Int32) -> SIMD2<Float> {
            let o = 6 * Int(v), c = vp * SIMD4(rig.dyn[o], rig.dyn[o + 1], rig.dyn[o + 2], 1)
            return SIMD2(c.x / c.w * GameCamera.aspect, c.y / c.w)
        }
        var out = SIMD2<Float>(0, 0)
        for side in 0..<2 {
            let pts = Self.browIdx[side].map { scr($0) }
            guard let lo = pts.min(by: { $0.x < $1.x }), let hi = pts.max(by: { $0.x < $1.x }) else { continue }
            // left brow (side 0): inner end = the larger screen x; right brow: the smaller
            let inner = side == 0 ? hi : lo, outer = side == 0 ? lo : hi
            out[side] = atan2f(inner.y - outer.y, abs(inner.x - outer.x))
        }
        return out
    }

    func run(_ seconds: Float, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) { tick(); if let until, until() { break } }
    }

    /// Where he stands now: far from the tray's place so there is a real walk.
    func moveAway() {
        brain.requestNow(.goTo(SIMD2(-1.3, 0.0)))
        run(8) { self.brain.activity == .idle && self.rig.t > 1 }
        run(1.5)
        frames.removeAll()
    }

    /// Whole meal: from the tap to the tray gone (and a short settle).
    func meal(_ id: String, limit: Float = 40) {
        let c = Consumables.with(id: id)!
        if c.kind == .food { care.feed(id) } else { care.drink(id) }
        started = rig.t
        run(limit) { self.tray.phase == .absent && !self.care.trayOut && self.rig.t - (self.started ?? 0) > 2 }
    }

    // MARK: derived

    /// Per-frame trace (every 4th frame) when the DINE_TRACE environment variable is set: debugging aid for tuning, no assertions.
    func trace(_ label: String) {
        guard ProcessInfo.processInfo.environment["DINE_TRACE"] != nil else { return }
        for (i, f) in frames.enumerated() where f.phase != "-" && i % 4 == 0 {
            MotionLog.write(String(format: "TRACE %@ t=%.2f %@ %@ armS=%.2f miss=%.3f hold=%d fork=%d mouth=%.2f held=%@ straw=%@ cap=%d pre=%@", label, f.t, "\(f.activity)", f.phase, f.armS, f.miss,
                                   f.holding ? 1 : 0, f.forkHeld ? 1 : 0, f.mouth, f.heldDist.map { String(format: "%.3f", $0) } ?? "-", f.mouthToStraw.map { String(format: "%.3f", $0) } ?? "-", f.capsuleOut ? 1 : 0, f.pre.map { String(format: "%.3f", $0) } ?? "-"))
        }
    }

    var dineFrames: [Frame] { frames.filter { $0.phase != "-" } }
    func runs(_ pred: (Frame) -> Bool) -> Int {
        var n = 0, was = false
        for f in frames { let p = pred(f); if p && !was { n += 1 }; was = p }
        return n
    }
}

@MainActor
final class DiningFlowTests: XCTestCase {
    private func bodyOffsets(_ r: MotionRig) -> [SIMD3<Float>] {
        let p = r.sim.bodyPose(iterations: 8), q = p.rotation.inverse
        return (0..<r.sim.x.count / 3).map { q.act(SIMD3(r.sim.x[3 * $0], r.sim.x[3 * $0 + 1], r.sim.x[3 * $0 + 2]) - p.centroid) }
    }
    private func rms(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> Float {
        var s: Float = 0
        for i in a.indices { s += simd_length_squared(a[i] - b[i]) }
        return (s / Float(a.count)).squareRoot()
    }

    // MARK: shared checks

    /// Everything every meal must satisfy (eat or sip).
    private func checkCommon(_ m: MealRun, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let d = m.dineFrames
        XCTAssertFalse(d.isEmpty, "\(name): he dined", file: file, line: line)
        // the tray popped in, he arrived at his place squared up to it
        XCTAssertNotNil(m.arrival, "\(name): he reached his place", file: file, line: line)
        if let a = m.arrival {
            XCTAssertLessThan(a.dist, 0.03, "\(name): his root is at his place (u)", file: file, line: line)
            XCTAssertLessThan(a.yaw, 0.05, "\(name): he faces the tray (rad)", file: file, line: line)
        }
        // mouth only while eating / drinking, and only inside the chomp / gulp windows
        XCTAssertTrue(m.frames.allSatisfy { $0.mouth == 0 || ($0.window && ($0.activity == .eating || $0.activity == .drinking)) },
                      "\(name): the mouth is open only inside the chomp / gulp windows", file: file, line: line)
        XCTAssertTrue(m.frames.filter { $0.phase != "chew" }.allSatisfy { $0.mouth == 0 }, "\(name): no mouth outside the chewing phase", file: file, line: line)
        XCTAssertEqual(m.frames.last?.mouth, 0, "\(name): mouth gone at the end", file: file, line: line)
        // a happy, closed-eyes finish; eyes open again afterwards
        let happy = d.filter { $0.phase == "happy" }
        XCTAssertGreaterThan(happy.count, 30, "\(name): a happy finish", file: file, line: line)
        XCTAssertTrue(happy.dropFirst(2).allSatisfy { $0.eyes == 0 }, "\(name): eyes closed in the happy finish", file: file, line: line)
        XCTAssertTrue(d.filter { $0.phase != "happy" }.allSatisfy { $0.eyes == 1 }, "\(name): eyes open outside it", file: file, line: line)
        XCTAssertEqual(m.frames.last?.eyes, 1, file: file, line: line)
        // the closed-eyes happy "ahh" comes BEFORE the tray poofs (at least 0.6 s of closed eyes right up to the poof)
        if let pi = m.frames.firstIndex(where: { $0.trayPhase == .poofing }) {
            let closed = m.frames[..<pi].reversed().prefix { $0.eyes == 0 }.count
            XCTAssertGreaterThanOrEqual(Float(closed) * m.rig.sim.stepDt, 0.6, "\(name): eyes closed for 0.6 s before the tray poofs", file: file, line: line)
        } else { XCTFail("\(name): the tray poofed", file: file, line: line) }
        // the brows never read angry while he dines: no brow's apparent slant (inner end up) drops more than 0.06 rad below the rest face's flattest brow
        let slants = m.frames.compactMap { $0.brow }
        // measured against the flattest brow of the rest face (the rest slants are -0.041 / +0.045 rad from the game camera)
        let restFloor = min(m.restBrow.x, m.restBrow.y)
        let worst = slants.map { min($0.x, $0.y) }.min() ?? 0
        MotionLog.write(String(format: "DINEFLOW %@ brows: rest slant %.3f / %.3f rad, flattest brow while dining %.3f rad over %d samples", name, m.restBrow.x, m.restBrow.y, worst, slants.count))
        for f in m.frames where (f.brow.map { min($0.x, $0.y) } ?? 0) < restFloor - 0.06 { MotionLog.write(String(format: "BROWDIP t=%.2f %@ slant %.3f/%.3f", f.t, f.phase, f.brow!.x, f.brow!.y)) }
        XCTAssertGreaterThan(slants.count, 20, file: file, line: line)
        XCTAssertGreaterThan(worst, restFloor - 0.06, "\(name): no brow slants down toward the middle more than the rest face's flattest brow (3 deg tolerance)", file: file, line: line)
        // the hand-off: no keyframe arm path ever runs while a walking capsule is out (no double arm)
        XCTAssertFalse(m.frames.contains { $0.capsuleOut && $0.armPath }, "\(name): no double arm", file: file, line: line)
        // the tray poofs away and the care flow is free again
        XCTAssertEqual(m.tray.phase, .absent, "\(name): the tray poofed away", file: file, line: line)
        XCTAssertFalse(m.care.trayOut, "\(name): the menu is free again", file: file, line: line)
        XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty, "\(name): no leftover collider", file: file, line: line)
        XCTAssertEqual(m.brain.activity, .idle, "\(name): idle again", file: file, line: line)
    }

    /// He is back at his exact rest shape after the meal.
    private func checkReturnsToRest(_ m: MealRun, before: [SIMD3<Float>], tilt0: Float? = nil, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        m.run(3.0)
        let pose = m.rig.sim.bodyPose(iterations: 8)
        let shape = rms(bodyOffsets(m.rig), before)
        MotionLog.write(String(format: "DINEFLOW %@ rest: tilt %.3f rad, shape rms %.4f u, centroid y %.3f", name, pose.tilt, shape, pose.centroid.y))
        // his idle stance leans back toward the camera a little (attention pitch): the same tilt as before the meal
        XCTAssertEqual(pose.tilt, tilt0 ?? m.restTilt, accuracy: 0.03, "\(name): the same stance again (rad)", file: file, line: line)
        XCTAssertLessThan(shape, 0.03, "\(name): his rest shape again (rms vs before the meal, u)", file: file, line: line)
        XCTAssertFalse(m.brain.armCapsuleOut && m.brain.armPathActive, file: file, line: line)
        XCTAssertFalse(m.brain.armPathActive, "\(name): no arm path left running", file: file, line: line)
    }

    private func setup() -> (MealRun, [SIMD3<Float>]) {
        let m = MealRun()
        let before = bodyOffsets(m.rig)
        m.restTilt = m.rig.sim.bodyPose(iterations: 8).tilt
        m.restBrow = m.browSlant()
        m.moveAway()
        return (m, before)
    }

    // MARK: eat

    /// The toss: a quick flick of the stub, the bite flies a small arc and lands in the open mouth.
    private func checkToss(_ m: MealRun, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let d = m.dineFrames, dt = m.rig.sim.stepDt, grabS = Float(ArmPath.nubGrabS)
        // the bite stays on the nub / tines until it is flicked off (<= 0.01 u)
        let carry = d.filter { $0.holding && !$0.flying && $0.phase != "grab" }.compactMap { $0.heldDist }
        MotionLog.write("DINEFLOW \(name) carry max \(carry.max() ?? -1) over \(carry.count) frames")
        XCTAssertGreaterThan(carry.count, 60, file: file, line: line)
        XCTAssertLessThan(carry.max() ?? 1, 0.01, "\(name): the bite stays on the nub until the flick", file: file, line: line)
        // the arm never extends: the nub stays on the stub part of its path (s <= the grab pose) for the whole meal
        XCTAssertLessThanOrEqual(d.map { $0.armS }.max() ?? 1, grabS + 0.001, "\(name): the nub never goes past the stub's swing", file: file, line: line)
        // the flick: the nub swings from its cocked pose to the grab pose in <= 0.15 s, once per bite
        var flicks: [Float] = [], start: Int?
        for (i, f) in d.enumerated() where f.phase == "chew" && !f.flying {
            if f.armS < grabS - 0.002 && start == nil && f.armS >= 0.02 && (i == 0 || d[i - 1].armS <= f.armS) { start = i }
            if f.armS >= grabS - 0.002, let s0 = start { flicks.append(Float(i - s0 + 1) * dt); start = nil }
        }
        MotionLog.write("DINEFLOW \(name) flicks \(flicks)")
        XCTAssertEqual(flicks.count, 3, "\(name): one flick per bite", file: file, line: line)
        XCTAssertLessThanOrEqual(flicks.max() ?? 1, 0.15, "\(name): the flick takes <= 0.15 s", file: file, line: line)
        // the arc: up to about 0.15 u off the straight line
        let arcs = d.compactMap { $0.arc }
        MotionLog.write("DINEFLOW \(name) arc max \(arcs.max() ?? -1)")
        XCTAssertGreaterThan(arcs.max() ?? 0, 0.10, "\(name): the bite flies an arc", file: file, line: line)
        XCTAssertLessThan(arcs.max() ?? 1, 0.20, file: file, line: line)
        // it lands in the mouth (<= 0.03 u from the mouth centre) from the landing to the swallow
        let land = d.compactMap { $0.landDist }
        MotionLog.write("DINEFLOW \(name) landing max \(land.max() ?? -1) over \(land.count) frames")
        XCTAssertGreaterThanOrEqual(land.count, 3 * 6, file: file, line: line)
        XCTAssertLessThan(land.max() ?? 1, 0.03, "\(name): the bite lands in his mouth", file: file, line: line)
        // the mouth opens just before the bite lands (within 0.25 s) and never earlier
        var opened = 0
        for (i, f) in d.enumerated() where f.mouth > 0.05 && (i == 0 || d[i - 1].mouth <= 0.05) && f.phase == "chew" {
            // first opening of a bite: the landing follows within 0.25 s
            let ahead = d[i...].prefix(Int(0.25 / dt) + 1)
            if ahead.contains(where: { $0.landed }) && !(d[max(0, i - 1)].landed) { opened += 1 }
        }
        XCTAssertGreaterThanOrEqual(opened, 3, "\(name): the mouth opens just before each landing", file: file, line: line)
        XCTAssertFalse(m.frames.contains { $0.landed && $0.phase != "chew" }, file: file, line: line)
    }

    func testBerriesByFinger() {
        let (m, before) = setup()
        m.meal("berries")
        m.trace("berries")
        MotionLog.write("DINEFLOW berries arrival \(String(describing: m.arrival)) lastMiss \(m.brain.dineReachMiss)")
        checkCommon(m, "berries")
        let d = m.dineFrames
        XCTAssertEqual(m.tray.bitesLeft, [0], "all three berries eaten")
        XCTAssertEqual(m.runs { $0.holding }, 3, "three bites, one piece each")
        XCTAssertEqual(m.runs { $0.mouth > 0.05 }, 6, "two chomps per bite")
        checkToss(m, "berries")
        // the reach: the stubby nub meets the berry (miss recorded at each lean)
        // the stubby nub reaches every berry within a berry radius, 0.065 u (a berry is 0.13 wide): the piece blends onto the nub over the grab beat, so this is not a visible pop
        let misses = d.map { $0.miss }.filter { $0 > 0 }
        MotionLog.write("DINEFLOW berries reach misses max \(misses.max() ?? -1) min \(misses.min() ?? -1)")
        XCTAssertLessThan(misses.max() ?? 1, 0.065, "the nub reaches every berry (u)")
        // no mouth during the lean / grab
        XCTAssertTrue(d.filter { $0.phase == "lean" || $0.phase == "grab" }.allSatisfy { $0.mouth == 0 })
        checkReturnsToRest(m, before: before, "berries")
    }

    func testPizzaThreeSlicesTossedIntoHisMouth() {
        let (m, before) = setup()
        m.meal("pizza")
        m.trace("pizza")
        checkCommon(m, "pizza")
        let d = m.dineFrames
        XCTAssertEqual(m.tray.bitesLeft, [0], "all three slices eaten")
        XCTAssertEqual(m.runs { $0.holding }, 3, "three tosses, one slice each")
        XCTAssertEqual(m.runs { $0.mouth > 0.05 }, 6, "two chomps per slice")
        checkToss(m, "pizza")
        // no fork, ever: finger food only
        XCTAssertTrue(m.frames.allSatisfy { !$0.forkVisible && !$0.forkHeld }, "no fork")
        // each slice leaves the tray when it is picked up: the plate goes 3 -> 2 -> 1 -> 0 slices (one in hand at a time)
        XCTAssertTrue(m.tray.pieceInHand.allSatisfy { $0 == nil }, "nothing left in hand")
        // the mouth is only open while eating (chew beat), never during the lean / grab
        XCTAssertTrue(d.filter { $0.phase == "lean" || $0.phase == "grab" || $0.phase == "straighten" }.allSatisfy { $0.mouth == 0 })
        // the slice sticks to the nub on the way up (like a berry) - within the same reach tolerance as the berries
        let misses = d.map { $0.miss }.filter { $0 > 0 }
        MotionLog.write("DINEFLOW pizza reach misses max \(misses.max() ?? -1)")
        var perBite: [Float] = [], cur: Float = 0
        for f in d { if f.phase == "lean" || f.phase == "grab" { cur = max(cur, f.miss) } else if cur > 0 { perBite.append(cur); cur = 0 } }
        MotionLog.write("DINEFLOW pizza miss per bite \(perBite)")
        XCTAssertLessThan(misses.max() ?? 1, 0.09, "the nub touches every slice (miss from its middle, slice is 0.26 x 0.16) \(perBite)")
        // no arm reach to the mouth: the held slice rides the nub until the flick, then flies (never arm-to-mouth)
        checkReturnsToRest(m, before: before, "pizza")
    }

    func testBerriesAndPizzaTakeTheSameTime() {
        var chew: [Float] = [], cycle: [Float] = []
        for id in ["berries", "pizza"] {
            let (m, _) = setup()
            m.meal(id)
            let d = m.dineFrames, dt = m.rig.sim.stepDt
            chew.append(Float(d.filter { $0.phase == "chew" }.count) * dt)
            cycle.append(Float(d.filter { $0.phase == "chew" || $0.phase == "straighten" }.count) * dt)
        }
        let b = DiningTiming.beatPeriod
        XCTAssertEqual(chew[0], chew[1], accuracy: 0.05, "every food takes the same chewing time")
        XCTAssertEqual(cycle[0], cycle[1], accuracy: 0.05, "and the same straighten + chew time per meal")
        XCTAssertEqual(chew[0], Float(DiningTiming.bitesPerServing) * b, accuracy: 0.1, "3 bites x 1 beat of chewing")
        XCTAssertEqual(cycle[0], Float(DiningTiming.bitesPerServing) * 1.45 * b, accuracy: 0.15)
    }

    // MARK: sip

    func checkSip(_ id: String) {
        let (m, before) = setup()
        m.meal(id)
        checkCommon(m, id)
        let d = m.dineFrames
        XCTAssertTrue(d.allSatisfy { !$0.holding && !$0.forkHeld && !$0.armPath }, "\(id): hands-free")
        XCTAssertEqual(m.runs { $0.mouth > 0.05 }, 3, "three gulps")
        let gulp = d.filter { $0.phase == "chew" }.compactMap { $0.mouthToStraw }
        MotionLog.write("DINEFLOW \(id) mouth-to-straw max \(gulp.max() ?? -1) mean \(gulp.reduce(0, +) / Float(max(gulp.count, 1)))")
        XCTAssertEqual(simd_distance(m.arrivalRoot, m.tray.places[0].stand + SIMD2(0, 1) * GameCare.sipCloser), 0, accuracy: 0.03, "\(id): he stands \(GameCare.sipCloser) u closer to his straw")
        MotionLog.write("DINEFLOW \(id) geometry: strawTip \(String(describing: m.tray.strawTip(place: 0))) stand \(m.tray.places[0].stand) mouthRest \(DineGeometry.mouthRest) miss \(m.brain.dineReachMiss)")
        XCTAssertGreaterThan(gulp.count, 100)
        XCTAssertLessThan(gulp.max() ?? 1, 0.05, "his mouth stays on his straw tip while he sips (u)")
        XCTAssertEqual(Float(d.filter { $0.phase == "chew" }.count) * m.rig.sim.stepDt, DiningTiming.drinkDuration, accuracy: 0.1)
        XCTAssertEqual(m.tray.drunk[0], 1, accuracy: 1e-4, "his share is drunk")
        XCTAssertEqual(m.tray.bitesLeft, [0], "the bottle drained one step per gulp (ServingState.totalLeft)")
        let fills = d.map { $0.fill }
        XCTAssertEqual(fills.first ?? 0, 1, accuracy: 0.02, "starts full")
        XCTAssertLessThan(fills.last ?? 1, 0.35, "the drink level dropped")
        XCTAssertTrue(zip(fills, fills.dropFirst()).allSatisfy { $0 >= $1 - 1e-5 }, "the level only drops")
        checkReturnsToRest(m, before: before, id)
    }
    func testWaterSip() { checkSip("water") }
    func testSodaSip() { checkSip("soda") }

    // MARK: the hand-off

    /// The walking capsules hold 0.7 s after the walk: the lean never starts under one.
    func testCapsuleHandOff() {
        let (m, _) = setup()
        m.meal("berries")
        let d = m.frames
        guard let first = d.firstIndex(where: { $0.phase != "-" }) else { return XCTFail("no dine") }
        // the walk ended with the capsules out; they were swapped out before the first lean tick
        XCTAssertTrue(d[..<first].contains { $0.capsuleOut }, "the capsules were out during the walk")
        let leanStart = d.firstIndex { $0.phase == "lean" && $0.armPath } ?? d.count
        XCTAssertTrue(d[leanStart...].allSatisfy { !$0.capsuleOut }, "no capsule after the keyframe arm starts")
        XCTAssertFalse(d.contains { $0.capsuleOut && $0.armPath }, "no double arm on any frame")
        let waited = d[first...].prefix { !$0.armPath }.count
        MotionLog.write("DINEFLOW hand-off: \(waited) frames (\(Float(waited) / 60) s) from arrival to the keyframe arm")
        XCTAssertLessThan(Float(waited) / 60, 0.8, "the swap-out is quick")
    }

    // MARK: the care flow

    func testTapTwiceMakesOneTray() {
        let (m, _) = setup()
        m.care.feed("berries"); m.care.feed("berries"); m.care.drink("water")
        m.run(0.5)
        XCTAssertTrue(m.care.trayOut)
        XCTAssertEqual(m.care.servingKind, .food, "the first tap wins")
        XCTAssertEqual(m.tray.serving.id, "berries")
        XCTAssertEqual(RoomLayout.dynamicBoxes.count, 1, "one tray collider")
        m.care.feed("pizza"); m.care.drink("soda")
        m.run(0.5)
        XCTAssertEqual(m.tray.serving.id, "berries", "taps while a tray is out are ignored")
        XCTAssertEqual(RoomLayout.dynamicBoxes.count, 1)
        m.run(40) { m.tray.phase == .absent }
        XCTAssertEqual(m.tray.phase, .absent)
    }

    func testCallMidMealPoofsTheTrayAndHeReturnsToRest() {
        for id in ["berries", "pizza", "water"] {
            let (m, before) = setup()
            let c = Consumables.with(id: id)!
            if c.kind == .food { m.care.feed(id) } else { m.care.drink(id) }
            // wait until he is mid-bite (something in hand / mid-gulp)
            m.run(30) { m.brain.activity == .eating || m.brain.activity == .drinking ? (m.brain.dinePhaseName == "chew" || m.brain.dinePhaseName == "straighten") : false }
            XCTAssertTrue(m.brain.activity == .eating || m.brain.activity == .drinking, "\(id): mid-meal")
            m.care.call()
            m.run(1.0)
            XCTAssertNotEqual(m.tray.phase, .present, "\(id): the tray starts to poof")
            XCTAssertTrue(m.brain.activity == .coming || m.brain.activity == .walking || m.brain.activity == .turning, "\(id): he answers the call \(m.brain.activity)")
            m.run(20) { m.tray.phase == .absent && m.brain.activity == .idle }
            XCTAssertEqual(m.tray.phase, .absent, "\(id): tray gone")
            XCTAssertFalse(m.care.trayOut, "\(id): the menu is free")
            XCTAssertFalse(m.brain.dineForkHeld)
            XCTAssertFalse(m.brain.dineHolding, "\(id): nothing held")
            XCTAssertEqual(m.brain.mouthOpen, 0)
            XCTAssertTrue(m.tray.pieceInHand.allSatisfy { $0 == nil })
            XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty)
            checkReturnsToRest(m, before: before, "call-\(id)")
        }
    }

    // MARK: perf

    /// The brain, the tray and the sim during a meal stay cheap (60 fps): mean and worst per fixed step of brain.tick + care.tick, the tray mesh
    /// rebuild (`DiningSet.frame`, twice a frame in the stage: after the tick and after the refresh) and sim.step.
    func testMealTickCost() {
        for id in ["berries", "pizza"] {
            let m = MealRun()
            m.care.feed(id)
            var worst = 0.0, sum = 0.0, n = 0, frameSum = 0.0, frameWorst = 0.0, frames = 0, stepSum = 0.0
            let theme = RoomTheme()
            for _ in 0..<(60 * 25) {
                let a = CACurrentMediaTime()
                m.brain.tick(sim: m.rig.sim, skinner: m.rig.skinner, dt: m.rig.sim.stepDt, touched: false)
                m.care.tick(brain: m.brain, renderer: nil, dt: m.rig.sim.stepDt)
                let b = CACurrentMediaTime()
                m.rig.sim.step()
                let c = CACurrentMediaTime()
                m.brain.refreshHeld(sim: m.rig.sim)
                let f = m.tray.frame(theme: theme)
                let d = CACurrentMediaTime()
                if m.brain.activity == .eating {
                    let us = (b - a) * 1e6; worst = max(worst, us); sum += us; n += 1; stepSum += (c - b) * 1e6
                    if f != nil { let fu = (d - c) * 1e6; frameSum += fu; frameWorst = max(frameWorst, fu); frames += 1 }
                }
                if m.care.trayOut == false && m.rig.t > 3 { break }
                m.rig.t += m.rig.sim.stepDt
            }
            XCTAssertGreaterThan(n, 200)
            MotionLog.write(String(format: "DINEFLOW perf %@: brain.tick + care.tick mean %.1f us, worst %.1f us; tray frame() %.1f us mean / %.1f us worst over %d rebuilds; sim.step mean %.0f us (%d steps)",
                                   id, sum / Double(n), worst, frames > 0 ? frameSum / Double(frames) : 0, frameWorst, frames, stepSum / Double(n), n))
            XCTAssertLessThan(sum / Double(n), 300)
            XCTAssertLessThan(worst, 4000, "the reach solve on a lean is the only spike")
            XCTAssertLessThan(frameWorst, 4000, "a tray mesh rebuild stays well under a frame")
        }
    }
}
