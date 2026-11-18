//
//  FocusLegsTests.swift
//  The owner, 2026-11-17: "Look at pandas leg bro" - in the close-up a petted Panda leaned and its near leg stuck out sideways, long and angular, from under the body.
//  Measured on the DRAWN feet (the skinned render mesh, as the renderer draws it), every step, against where the body carries each foot (the fitted rigid pose):
//    leg     distance from the foot's sole (lowest drawn vertices) to its hip (the buried top of the leg, rest frame, carried by the fitted pose), / the rest value
//    off     how far the sole sits from its own place under the body (body frame, xz)
//    cross   the two soles keep their order across the body (side 0 = -x stays left of side 1)
//    depth   while the foot pieces are out, the piece's top pole lies inside the body (no gap at the join)
//  States: standing, petted (short and long strokes, each side), the cuddle with hearts, the phone tilted while petted, let go; every species' feature; and the
//  three-Jelmiko close-up (arrival, standing, each one petted while his neighbours stand beside him, "Let them go").
//  Exempt by design: the foot of a step that is in its swing (it is in the air on its way to a new spot; its leg length still counts).
//

import XCTest
import simd
@testable import BobV1

@MainActor
struct LegProbe {
    static let legLimit: Float = 1.15, offLimit: Float = 0.05, crossMin: Float = 0.10
    /// The hip: the buried top of the foot piece above its sole (bean-local y of the crown pole).
    static let hipH: Float = FootBean.localF[FootBean.vertexCount - 1].y
    var worstLeg: Float = 0, worstOff: Float = 0, worstCross: Float = 9, worstDepth: Float = 9
    var worstLegAt = "", worstOffAt = "", worstCrossAt = "", worstDepthAt = ""
    var byState: [String: (leg: Float, off: Float)] = [:]
    var frames = 0
    var dyn: [Float] = []

    /// One measurement of one body. `tag` names the state; `extra` is logged with the worst frame (the cause numbers).
    mutating func measure(_ tag: String, sim: SoftBody, skinner: Skinner, brain: BlobBrain, rm: RenderMesh, core: [[Int32]], extra: () -> String = { "" }) {
        if dyn.count != rm.vertexCount * 6 { dyn = [Float](repeating: 0, count: rm.vertexCount * 6) }
        skinner.update(x: sim.x, index: rm.index, into: &dyn)
        guard brain.geom.valid else { return }
        frames += 1
        let pose = sim.bodyPose(iterations: 3), c0 = sim.restCentroid, inv = pose.rotation.inverse
        let beans = skinner.beansActive && skinner.beanFirst.count == 2
        var sole: [SIMD3<Float>] = [.zero, .zero]
        for s in 0..<2 {
            let ids: [Int32] = beans ? (skinner.beanFirst[s]..<(skinner.beanFirst[s] + FootBean.vertexCount)).map { Int32($0) } : core[s]
            var lo = Float.infinity
            for v in ids { lo = min(lo, dyn[6 * Int(v) + 1]) }
            var a = SIMD3<Float>.zero, n: Float = 0
            for v in ids { let o = 6 * Int(v); if dyn[o + 1] < lo + 0.015 { a += SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]); n += 1 } }
            sole[s] = c0 + inv.act(a / max(n, 1) - pose.centroid)          // (rest frame)
        }
        let swingSide: Int? = brain.feet.swinging ? brain.feet.side : nil
        var line = ""
        for s in 0..<2 {
            let c = brain.geom.contact[s]
            let hip = c + SIMD3(0, Self.hipH, 0)
            let leg = simd_length(sole[s] - hip) / Self.hipH
            let off = simd_length(SIMD2(sole[s].x - c.x, sole[s].z - c.z))
            let offCounted = swingSide == s ? 0 : off
            var b = byState[tag] ?? (0, 0); b.leg = max(b.leg, leg); b.off = max(b.off, offCounted); byState[tag] = b
            line += String(format: " f%d leg %.2f off %.3f", s, leg, off)
            if leg > worstLeg { worstLeg = leg; worstLegAt = "\(tag):\(line) \(extra())" }
            if offCounted > worstOff { worstOff = offCounted; worstOffAt = "\(tag):\(line) \(extra())" }
            if beans {
                let f = skinner.beanFirst[s] + FootBean.vertexCount - 1
                let d = Skinner.fittedDepth(SIMD3(dyn[6 * f], dyn[6 * f + 1], dyn[6 * f + 2]), (pose.centroid, pose.rotation, c0)).0
                if d < worstDepth { worstDepth = d; worstDepthAt = "\(tag) f\(s) \(extra())" }
            }
        }
        let cross = sole[1].x - sole[0].x
        if cross < worstCross { worstCross = cross; worstCrossAt = "\(tag) \(extra())" }
    }

    var summary: String {
        String(format: "leg %.2f (%@) | off %.3f (%@) | cross %.3f (%@) | depth %.3f (%@)", worstLeg, worstLegAt, worstOff, worstOffAt, worstCross, worstCrossAt, worstDepth, worstDepthAt)
    }
    var states: String { byState.keys.sorted().map { String(format: "%@ leg %.2f off %.3f", $0, byState[$0]!.leg, byState[$0]!.off) }.joined(separator: "; ") }

    func check(_ who: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(worstLeg, Self.legLimit, "\(who): a leg stretched to \(worstLeg)x its rest length at \(worstLegAt)", file: file, line: line)
        XCTAssertLessThanOrEqual(worstOff, Self.offLimit, "\(who): a planted foot \(worstOff) m out of its place under the body at \(worstOffAt)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(worstCross, Self.crossMin, "\(who): the feet came \(worstCross) m apart / crossed at \(worstCrossAt)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(worstDepth, 0, "\(who): a foot piece's top came out of the body (\(worstDepth) m) at \(worstDepthAt)", file: file, line: line)
    }
}

@MainActor
final class FocusLegsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var savedHour: Double?
    private var savedLean = true
    /// TEST_RUNNER_FOCUSLEGS_BASE=1: run every test with the fix switched off (the behaviour before focus-legs-r1: the red run).
    override func setUp() {
        savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12
        savedLean = BlobBrain.leanFeetFollow
        if ProcessInfo.processInfo.environment["FOCUSLEGS_BASE"] == "1" { BlobBrain.leanFeetFollow = false }
    }
    override func tearDown() { DayClock.shared.forcedHour = savedHour; BlobBrain.leanFeetFollow = savedLean }

    /// The bug itself, kept as a pinned "before": with the fix off, a Panda petted long on one side stretches the high side's leg past the limit.
    func testBeforeTheFixThePettedLegStretched() {
        BlobBrain.leanFeetFollow = false
        let r = Solo(feature: .ears, panda: true); Self.keep.append(r)
        r.state = "standing"; r.idle(1.5)
        r.state = "pet long right"; r.stroke(4.5, cx: 0.34)
        MotionLog.write("FOCUSLEGS before-fix Panda: \(r.probe.summary)")
        XCTAssertGreaterThan(r.probe.worstLeg, LegProbe.legLimit, "the stretched leg the owner saw (fix off)")
    }

    /// The seven species by what their bodies carry (the legs are the same body; the feature pieces and the Panda ink ride on it).
    static let species: [(name: String, feature: JellyFeature, panda: Bool)] = [
        ("Bob", .none, false), ("Pip", .spines, false), ("Moss", .daisy, false), ("Lavender", .wings, false),
        ("Teddy", .ears, false), ("Pearl", .wings, false), ("Panda", .ears, true),
    ]

    static func cause(_ b: BlobBrain, _ sim: SoftBody) -> String {
        let up = sim.bodyPose(iterations: 3).rotation.act(SIMD3<Float>(0, 1, 0))
        let fitRoll = atan2f(up.x, up.y)
        let nom = (0..<2).map { simd_distance(b.feet.pos[$0], SIMD2(b.px, b.pz) + rotXZ(b.geom.off[$0], b.yaw)) }
        return String(format: "[touchRoll %.3f socialRoll %.3f fitRoll %.3f pivot %@ planted-vs-nominal %.3f/%.3f feetActive %d act %@ beanCorr %.3f/%.3f]",
                      b.touchRoll, b.socialBook.roll, fitRoll, b.pivotSide.map { "\($0)" } ?? "mid", nom[0], nom[1], b.feet.active ? 1 : 0, "\(b.activity)",
                      simd_length(b.beanCorr[0]), simd_length(b.beanCorr[1]))
    }

    // MARK: one Jelmiko, standing in the game pose, petted

    @MainActor final class Solo {
        let rig = MotionRig(game: true, settle: 2)
        let rec = RecordingHapticSink()
        let play: TouchPlay
        let surface = RestSurface(mesh: MotionRig.renderMesh)
        var clock = 100.0
        var probe = LegProbe()
        var maxHearts = 0, purred = false
        var state = ""
        init(feature: JellyFeature, panda: Bool) {
            let d = HapticDriver(sinks: [rec])
            rec.clock = { 0 }
            play = TouchPlay(haptics: d)
            d.enabled = true; d.setWarm(true)
            rec.clock = { [unowned self] in self.clock }
            rec.clear()
            rig.brain.feature = feature; rig.brain.pandaInk = panda
        }
        func ray(localX: Float, localY: Float) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
            let e = BodyEllipsoid(sim: rig.sim)
            let p = e.center + e.rot.act(SIMD3(localX, localY, 0))
            let eye = SIMD3<Float>(0, 0.9, 6)
            return (eye, simd_normalize(p - eye))
        }
        func frame(_ r: (o: SIMD3<Float>, d: SIMD3<Float>)?, tilt: Float = 0) {
            play.petFrame(dt: 1.0 / 60, now: clock, ray: r, screen: r == nil ? nil : SIMD2(0.5, 0.5), sim: rig.sim, brain: rig.brain, skinner: rig.skinner, surface: surface)
            if tilt != 0 { play.motionFrame(dt: 1.0 / 60, now: clock, gravityX: tilt, shake: 0, sim: rig.sim, brain: rig.brain, skinner: rig.skinner) }
            rig.tick()
            clock += 1.0 / 60
            maxHearts = max(maxHearts, play.hearts.count); purred = purred || play.isPurring
            let b = rig.brain, s = rig.sim
            probe.measure(state, sim: rig.sim, skinner: rig.skinner, brain: rig.brain, rm: MotionRig.renderMesh, core: rig.core) { FocusLegsTests.cause(b, s) }
        }
        /// A stroke on one side (`cx` = body-frame x of its centre, + = the viewer's right), `amp` wide.
        func stroke(_ seconds: Float, cx: Float, amp: Float = 0.12, y: Float = 0, tilt: Float = 0) {
            var t: Float = 0
            while t < seconds { frame(ray(localX: cx + amp * sinf(2 * .pi * 1.2 * t), localY: y), tilt: tilt); t += 1.0 / 60 }
        }
        func idle(_ seconds: Float) { for _ in 0..<Int(seconds * 60) { frame(nil) } }
    }

    /// Every species, standing in the game pose: petted short and long on each side, cuddled with hearts, petted with the phone tilted, let go.
    func testPettedFeetStayUnderTheBodyEverySpecies() {
        for sp in Self.species {
            let r = Solo(feature: sp.feature, panda: sp.panda); Self.keep.append(r)
            r.state = "standing"; r.idle(1.5)
            r.state = "pet short left"; r.stroke(1.0, cx: -0.32); r.state = "let go"; r.idle(1.0)
            r.state = "pet short right"; r.stroke(1.0, cx: 0.32); r.state = "let go"; r.idle(1.0)
            r.state = "pet long left"; r.stroke(4.5, cx: -0.34)
            r.state = "pet long right"; r.stroke(4.5, cx: 0.34)
            r.state = "cuddle hearts"; r.stroke(3.0, cx: 0, amp: 0.35)
            r.state = "pet + phone tilt"; r.stroke(2.5, cx: 0.3, tilt: -0.6); r.stroke(2.5, cx: -0.3, tilt: 0.6)
            r.state = "let go"; r.idle(2.5)
            MotionLog.write("FOCUSLEGS solo \(sp.name): \(r.probe.summary)\n   states: \(r.probe.states)")
            r.probe.check("\(sp.name) petted")
            XCTAssertGreaterThan(r.maxHearts, 0, "\(sp.name): the cuddle still sends hearts")
            XCTAssertFalse(r.rec.events(.transient).isEmpty && r.rec.events(.continuous).isEmpty, "\(sp.name): petting still buzzes")
        }
    }

    // MARK: three Jelmiko in the close-up

    @MainActor final class Row {
        let r = FocusAnyRun(peers: true)
        let play = TouchPlay(haptics: nil)
        var clock = 100.0
        var t: Float = 0
        var strokeCX: Float? = nil
        var probes: [LegProbe]
        var cores: [[[Int32]]] = []
        var state = ""
        var minGap: Float = 9, minGapAt = ""
        init(species: [(name: String, feature: JellyFeature, panda: Bool)]) {
            probes = [LegProbe](repeating: LegProbe(), count: r.actors.count)
            r.care.touchPlay = play
            for (i, a) in r.actors.enumerated() {
                let b = a.brain!
                b.feature = species[i].feature; b.pandaInk = species[i].panda
                cores.append([b.footCoreVertices(0, sim: a.sim, skinner: a.skinner), b.footCoreVertices(1, sim: a.sim, skinner: a.skinner)])
            }
        }
        var care: GameCare { r.care }
        func tick(measure: Bool = true) {
            let dt: Float = 1.0 / 60
            let id = care.focusGroup.touchID
            let a = r.actors[id]
            if care.focus.isFocused {
                var ray: (o: SIMD3<Float>, d: SIMD3<Float>)?
                if let cx = strokeCX {
                    t += dt
                    let e = BodyEllipsoid(sim: a.sim)
                    let p = e.center + e.rot.act(SIMD3(cx + 0.12 * sinf(2 * .pi * 1.2 * t), 0, 0))
                    let eye = SIMD3<Float>(p.x, 0.9, 8)
                    ray = (eye, simd_normalize(p - eye))
                }
                play.petFrame(dt: dt, now: clock, ray: ray, screen: ray == nil ? nil : SIMD2(0.5, 0.5), sim: a.sim, brain: a.brain, skinner: a.skinner, surface: nil)
            } else if !play.holdsBrain { play.cancel(sim: a.sim, brain: a.brain, skinner: a.skinner) }
            r.tick()
            for x in r.actors { x.brain?.refitBeans(x.sim, x.skinner) }          // (the stage's order: the beans follow the body's pose AFTER the step)
            clock += Double(dt)
            guard measure else { return }
            for (i, x) in r.actors.enumerated() {
                let b = x.brain!, s = x.sim
                probes[i].measure(state, sim: x.sim, skinner: x.skinner, brain: b, rm: r.rm, core: cores[i]) { FocusLegsTests.cause(b, s) }
            }
            // the neighbours' drawn skins along the row (x): the gap between the right edge of one and the left edge of the next, in the body band
            let xs = r.actors.map { x -> (lo: Float, hi: Float, cx: Float) in
                let c = x.sim.centroid()
                var lo = Float.infinity, hi = -Float.infinity
                for i in 0..<x.sim.n { let y = x.sim.x[3 * i + 1]; if y > x.sim.floorY + 0.1 { lo = min(lo, x.sim.x[3 * i]); hi = max(hi, x.sim.x[3 * i]) } }
                return (lo, hi, c.x)
            }.sorted { $0.cx < $1.cx }
            for k in 0..<(xs.count - 1) {
                let g = xs[k + 1].lo - xs[k].hi
                if g < minGap { minGap = g; minGapAt = state }
            }
        }
        func run(_ s: Float, measure: Bool = true, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { tick(measure: measure); if until?() == true { return } } }
    }

    /// Three Jelmiko called to the close-up (the species of the owner's screenshot: Moss, Lavender, Panda; then Teddy, Pearl, Pip; then Bob and two more),
    /// each petted on each side in turn while the others stand beside him, then "Let them go".
    func testCloseUpRowFeetStayUnderEveryBody() {
        let rows: [[Int]] = [[2, 3, 6], [4, 5, 1], [0, 6, 4]]
        for ids in rows {
            let sp = ids.map { Self.species[$0] }
            let row = Row(species: sp); Self.keep.append(row)
            row.run(1.5, measure: false)
            row.care.comeHereEveryone()
            row.state = "arriving"
            row.run(40) { row.care.focus.isFocused }
            XCTAssertTrue(row.care.focus.isFocused, "the close-up framed the row")
            row.state = "standing"; row.run(1.5)
            for who in 0..<3 {
                row.care.focusGroup.touchID = who
                for (cx, side) in [(Float(-0.32), "left"), (Float(0.32), "right")] {
                    row.strokeCX = cx; row.t = 0
                    row.state = "\(sp[who].name) petted \(side)"; row.run(4.0)
                    row.strokeCX = nil
                    row.state = "after \(sp[who].name) petted"; row.run(1.0)
                }
            }
            row.state = "let them go"
            row.care.release()
            row.run(3)
            let names = sp.map(\.name).joined(separator: ",")
            for i in 0..<3 {
                MotionLog.write("FOCUSLEGS row [\(names)] \(sp[i].name): \(row.probes[i].summary)\n   states: \(row.probes[i].states)")
                row.probes[i].check("row [\(names)] \(sp[i].name)")
            }
            MotionLog.write(String(format: "FOCUSLEGS row [\(names)] min sim skin gap along the row %.3f m at %@", row.minGap, row.minGapAt))
        }
    }
}
