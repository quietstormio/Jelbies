//
//  GlitchEmoteTests.swift
//  glitch-hunt-r1: the dev glitch probe's core (Melon/GlitchProbe.swift) run headless on one MotionRig per solo emote: every step is skinned like the stage does and fed to
//  `GlitchCore`; the pose POPS (a drawn vertex that moves 3 cm or more in one step after moving under a third of that, then stops or goes back) are counted per part.
//  Pins the fix: a plain hop's landing / chained crouch eased (`GaitDriver.hopEase`): the happy bounce's per-hop pops go.
//  `GLITCH_EMOTE_SURVEY=1` (TEST_RUNNER_GLITCH_EMOTE_SURVEY) logs every emote's counts to the motion log.
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import XCTest
import simd
@testable import BobV1

@MainActor
final class GlitchEmoteTests: XCTestCase {
    struct Pops { var byPart: [String: Int] = [:]; var max: [String: Float] = [:]; var lines: [String] = []; var diag = ""; var events: [(part: String, cm: Float, hop: Bool)] = [] }

    /// Runs `kind` on a fresh rig for `seconds` (plus 1.5 s after it ends) and counts the pops over `bar` cm per step.
    func pops(_ kind: IdleKind, seconds: Float = 8, bar: Float = 3, dumpWindow: ClosedRange<Float> = 99...99, label: String? = nil,
              start: ((MotionRig) -> Void)? = nil, isOn: ((MotionRig) -> Bool)? = nil, each: ((MotionRig, Float) -> Void)? = nil, dumpEnd: Bool = false) -> Pops {
        let r = MotionRig(game: true)
        var core = GlitchCore(); core.bars.poseCm = bar
        var out = Pops()
        if let start { start(r) } else { r.brain.commandedIdle = kind }          // (as the tour / a voice command does: the brain starts it on its next tick)
        let on = isOn ?? { $0.brain.idleState.kind != nil }
        let name = label ?? "\(kind)"
        var ring: [String] = [], tail = 0
        var started = false
        var after: Float = -1
        let n = Int(seconds * 60)
        var frames = 0, maxArmBlend: Float = 0, maxBean: Float = 0, maxV: Float = 0, counts = Set<Int>()
        var lastLocal: [SIMD3<Float>] = []
        for i in 0..<n {
            r.tick()
            each?(r, Float(i) / 60)
            r.render()
            if dumpEnd {
                let b = r.brain, a = r.sim.attractor
                let line = String(format: "GLITCH end %@ t=%.3f script=%@ act=%@ gait=%@ k=%.0f squash=%.3f poseW=%.2f feetInit=%d bean=%.2f armG=%.2f armBlend=%.2f lift=%.2f walkWant=%.1f dirW=%.2f anchorY=%.3f fitY=%.3f",
                    name, Float(i) / 60, b.scriptKindName, "\(b.activity)", "\(b.gait.phase)", a.strength, a.squash, b.poseW, b.feetInit ? 1 : 0, r.skinner.beanBlend, b.armG, r.skinner.armBlend, b.armLiftNow, b.armWalkWant, b.armDirW, a.anchor.y, r.sim.bodyPose(iterations: 8).centroid.y)
                let line2 = line + String(format: " sleep=%d/%.2f/k%.2f idlePhase=%d extra=%d override=%d retract=%d", b.sleep.stage, b.sleep.t, b.sleep.k, b.idleState.phase, r.skinner.extraVertices.count, r.skinner.overrideVertices.count, r.skinner.retractVertices.count)
                if tail > 0 { MotionLog.write(line2); tail -= 1 } else { ring.append(line2); if ring.count > 4 { ring.removeFirst() } }
            }
            if dumpWindow.contains(Float(i) / 60) {
                let a = r.sim.attractor, f = r.sim.bodyPose(iterations: 8)
                let ae = a.rotation.act(SIMD3<Float>(0, 0, 1)), au = a.rotation.act(SIMD3<Float>(0, 1, 0))
                MotionLog.write(String(format: "GLITCH dump %@ t=%.3f gait=%@ k=%.0f anchor=(%.3f,%.3f,%.3f) squash=%.3f attYaw=%.1f attTilt=%.1f fitC=(%.3f,%.3f,%.3f) fitYaw=%.1f armTip0=(%.3f,%.3f,%.3f) lift=%.3f S=%.1f",
                    "\(kind)", Float(i) / 60, "\(r.brain.gait.phase)", a.strength, a.anchor.x, a.anchor.y, a.anchor.z, a.squash, atan2f(ae.x, ae.z) * 180 / .pi, acosf(min(1, au.y)) * 180 / .pi,
                    f.centroid.x, f.centroid.y, f.centroid.z, f.yaw * 180 / .pi, r.brain.armLastGeom[0].b.x, r.brain.armLastGeom[0].b.y, r.brain.armLastGeom[0].b.z, r.brain.armLiftNow, r.brain.armLastS[0]))
            }
            let l = GlitchProbe.buildLayout(r.skinner)
            let s = r.dyn.withUnsafeBufferPointer { GlitchProbe.makeSample(sim: r.sim, skinner: r.skinner, brain: r.brain, dyn: $0.baseAddress!, group: l.group, idx: l.idx) }
            frames += 1; maxArmBlend = Swift.max(maxArmBlend, r.skinner.armBlend); maxBean = Swift.max(maxBean, r.skinner.beanBlend); counts.insert(s.local.count)
            if lastLocal.count == s.local.count { for k in 0..<s.local.count { maxV = Swift.max(maxV, simd_distance(lastLocal[k], s.local[k])) } }
            lastLocal = s.local
            for e in core.observe(s, steps: 1) where e.kind == "pose" {
                let part = String(e.detail.split(separator: " ").first ?? "").replacingOccurrences(of: "part=", with: "")
                out.byPart[part, default: 0] += 1
                out.max[part] = Swift.max(out.max[part] ?? 0, e.perStep)
                out.events.append((part, e.perStep, r.brain.gait.isBusy))
                if dumpEnd, e.perStep >= 4, let vi = Int32(e.detail.components(separatedBy: "vi=").last ?? "") {
                    let sk = r.skinner, fs = r.brain.footSkin
                    let member = "retract=\(sk.retractVertices.contains(vi)) armRetract=\(sk.armRetractVertices.contains(vi)) override=\(sk.overrideVertices.contains(vi)) extra=\(sk.extraVertices.contains(vi)) footSkin=\(fs.verts.indices.map { fs.verts[$0].contains(vi) }) skinVerts=\(sk.skinVerts.contains(vi))"
                    MotionLog.write(String(format: "GLITCH popdump %@ t=%.3f %@ %.1f cm vi=%d %@", name, Float(i) / 60, part, e.perStep, vi, member))
                    for l in ring { MotionLog.write("GLITCH   " + l) }
                    ring = []; tail = 2
                }
                out.lines.append(String(format: "%@ t=%.3f %@ %.1f cm %@ armDirW=%.2f armLift=%.2f armG=%.2f gait=%@ k=%.0f", name, Float(i) / 60, part, e.perStep, e.detail, r.brain.armDirW, r.brain.armLiftNow, r.brain.armG, "\(r.brain.gait.phase)", r.sim.attractor.strength))
            }
            if on(r) { started = true }
            if after < 0, started, !on(r) { after = Float(i) / 60; if dumpEnd { for l in ring { MotionLog.write(l) }; ring = []; tail = 8 } }
            if after >= 0, Float(i) / 60 > after + 1.5 { break }
        }
        if !started { out.diag = "did not start: "; }
        out.diag += String(format: "frames %d armBlend max %.2f beanBlend max %.2f max vertex step %.1f cm, sample sizes %@", frames, maxArmBlend, maxBean, maxV * 100, "\(counts.sorted())")
        return out
    }

    /// A plain hop's landing and chained crouch start from the attractor's squash and strength (GaitDriver.hopEase): the happy bounce's per-hop arm / foot / body pops go.
    func testChainedHopsHandTheHoldOver() {
        let saved = GaitDriver.hopEase
        defer { GaitDriver.hopEase = saved }
        GaitDriver.hopEase = false
        let off = pops(.bounce, dumpWindow: 0.38...0.47)
        GaitDriver.hopEase = true
        let on = pops(.bounce)
        let n = { (p: Pops) in p.byPart.values.reduce(0, +) }
        MotionLog.write("GLITCH bounce pops: off \(n(off)) \(off.byPart), on \(n(on)) \(on.byPart)")
        for l in on.lines { MotionLog.write("GLITCH on " + l) }
        let hopPops = { (p: Pops) in p.events.filter { $0.hop } }
        MotionLog.write("GLITCH bounce pops while hopping: off \(hopPops(off).count), on \(hopPops(on).count); arm max off \(hopPops(off).filter { $0.part == "arm" }.map(\.cm).max() ?? 0), on \(hopPops(on).filter { $0.part == "arm" }.map(\.cm).max() ?? 0)")
        let big = { (p: Pops) in hopPops(p).filter { $0.cm >= 6 }.count }
        MotionLog.write("GLITCH bounce pops of 6 cm or more while hopping: off \(big(off)), on \(big(on))")
        let worst = { (p: Pops) in hopPops(p).map(\.cm).max() ?? 0 }
        MotionLog.write("GLITCH bounce worst pop while hopping: off \(worst(off)) cm, on \(worst(on)) cm")
        XCTAssertLessThanOrEqual(big(on), big(off))
        XCTAssertLessThan(worst(on), worst(off), "the worst pop while hopping is under the snap's (measured 2026-11-24: 15.7 -> 9.9 cm, the arms 15.7 -> 5.5)")
        XCTAssertLessThan(hopPops(on).filter { $0.part == "arm" }.map(\.cm).max() ?? 0, 6, "no arm pop of 6 cm or more while hopping")
    }

    /// The body-rigid feet's ball / boot morph is rate-limited (BlobBrain.beanMorphEase): the landing's toe pop goes.
    func testHopLandingFeetMorphWithoutAPop() {
        let saved = BlobBrain.beanMorphEase
        defer { BlobBrain.beanMorphEase = saved }
        var off = 0, on = 0, offMax: Float = 0, onMax: Float = 0
        for k in [IdleKind.bounce, .jacks, .hopscotch] {
            BlobBrain.beanMorphEase = false
            let a = pops(k).events.filter { $0.hop && $0.part == "foot" }
            BlobBrain.beanMorphEase = true
            let b = pops(k).events.filter { $0.hop && $0.part == "foot" }
            off += a.count; on += b.count; offMax = Swift.max(offMax, a.map(\.cm).max() ?? 0); onMax = Swift.max(onMax, b.map(\.cm).max() ?? 0)
        }
        MotionLog.write("GLITCH hop foot pops (bounce + jacks + hopscotch): morph snap \(off) (max \(offMax) cm), eased \(on) (max \(onMax) cm)")
        XCTAssertLessThan(on, Swift.max(1, off))
    }

    /// The arm override is drawn eased (BlobBrain.armDirEase): the end of a bounce / jacks / joy no longer snaps the arms (21 cm in one step).
    func testEmoteEndArmsWithoutAPop() {
        let saved = BlobBrain.armDirEase
        defer { BlobBrain.armDirEase = saved }
        var off: [Float] = [], on: [Float] = []
        for k in [IdleKind.bounce, .jacks, .joy] {
            BlobBrain.armDirEase = false
            off += pops(k).events.filter { !$0.hop && $0.part == "arm" }.map(\.cm)
            BlobBrain.armDirEase = true
            on += pops(k).events.filter { !$0.hop && $0.part == "arm" }.map(\.cm)
        }
        MotionLog.write("GLITCH emote-end arm pops (bounce + jacks + joy, not hopping): snap \(off.count) (max \(off.max() ?? 0) cm), eased \(on.count) (max \(on.max() ?? 0) cm)")
        XCTAssertLessThan(on.max() ?? 0, Swift.max(6, 0.5 * (off.max() ?? 0)), "the end of an emote leaves the arms without a big pop")
    }

    /// The bean collar fades out at the end of its reach along the foot axis (Skinner.collarEdgeEase): the wave's lifted foot no longer flicks the belly skin over it.
    func testWaveLegSkinWithoutAPop() {
        let saved = Skinner.collarEdgeEase
        defer { Skinner.collarEdgeEase = saved }
        func run() -> [Float] { pops(.bounce, seconds: 6, label: "wave", start: { $0.brain.pending = .wave }, isOn: { $0.brain.isWaving }).events.filter { $0.part == "body" && $0.cm >= 3 }.map(\.cm) }
        Skinner.collarEdgeEase = false; let off = run()
        Skinner.collarEdgeEase = true; let on = run()
        MotionLog.write("GLITCH wave body pops >= 3 cm: cut \(off.count) (max \(off.max() ?? 0)), faded \(on.count) (max \(on.max() ?? 0))")
        XCTAssertLessThan(on.count, off.count)
    }

    /// A nap's lie-down and get-up ease the attractor's anchor (BlobBrain.sleepAnchorEase): no 13 cm anchor step, fewer pops.
    func testNapWithoutAnchorPops() {
        let saved = BlobBrain.sleepAnchorEase
        defer { BlobBrain.sleepAnchorEase = saved }
        func run() -> (pops: [Float], step: Float) {
            var held = false, last: SIMD3<Float>? = nil, step: Float = 0
            let p = pops(.sleep, seconds: 16, label: "sleep", start: { $0.brain.commandedIdle = .sleep }, isOn: { $0.brain.idleState.kind == .sleep },
                         each: { r, _ in
                             if !held, r.brain.idleState.kind == .sleep { held = true; r.brain.sleep.hold = 4 }
                             let a = r.sim.attractor.anchor; if let l = last { step = Swift.max(step, simd_length(a - l)) }; last = a })
            return (p.events.filter { $0.cm >= 5 }.map(\.cm), step)
        }
        BlobBrain.sleepAnchorEase = false; let off = run()
        BlobBrain.sleepAnchorEase = true; let on = run()
        MotionLog.write("GLITCH nap: pops >= 5 cm snap \(off.pops.count) (max \(off.pops.max() ?? 0)), eased \(on.pops.count) (max \(on.pops.max() ?? 0)); largest anchor step snap \(off.step), eased \(on.step)")
        XCTAssertLessThan(on.step, 0.05, "no anchor step of 5 cm or more")
        XCTAssertLessThanOrEqual(on.pops.count, off.pops.count)
    }

    /// Log only (GLITCH_DUMP=1): the ends of a bounce and a jacks, a wave, a nap and its wake, with the brain / attractor state around each end and every pop.
    func testDumpEndsWaveSleep() throws {
        guard ProcessInfo.processInfo.environment["GLITCH_DUMP"] == "1" else { throw XCTSkip("GLITCH_DUMP=1 runs the dump") }
        var cases: [Pops] = []
        cases.append(pops(.bounce, dumpEnd: true))
        cases.append(pops(.jacks, dumpEnd: true))
        cases.append(pops(.bounce, seconds: 6, label: "wave", start: { $0.brain.pending = .wave }, isOn: { $0.brain.isWaving }, dumpEnd: true))
        var held = false
        cases.append(pops(.sleep, seconds: 20, label: "sleep", start: { $0.brain.commandedIdle = .sleep }, isOn: { $0.brain.idleState.kind == .sleep },
                          each: { r, _ in if !held, r.brain.idleState.kind == .sleep { held = true; r.brain.sleep.hold = 4 } }, dumpEnd: true))
        for p in cases {
            MotionLog.write("GLITCH dumpcase [\(p.diag)]: " + p.byPart.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) (max \(String(format: "%.1f", p.max[$0.key] ?? 0)))" }.joined(separator: ", "))
            for l in p.lines { MotionLog.write("GLITCH pop " + l) }
        }
    }

    /// Survey (log only): every solo emote's pops by part.
    func testSurveyEveryEmote() throws {
        guard ProcessInfo.processInfo.environment["GLITCH_EMOTE_SURVEY"] == "1" else { throw XCTSkip("GLITCH_EMOTE_SURVEY=1 runs the survey") }
        let kinds: [IdleKind] = [.jacks, .bounce, .skipHop, .hopscotch, .legSpin, .joy, .giggle, .startle, .sigh, .hmph, .tail, .flop, .stretch, .stopLook, .scoot, .slide, .stumble, .look, .yawn, .sit, .slump, .sway]
        for k in kinds {
            let p = pops(k)
            MotionLog.write("GLITCH survey \(k) [\(p.diag)]: " + p.byPart.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) (max \(String(format: "%.1f", p.max[$0.key] ?? 0)))" }.joined(separator: ", "))
            for l in p.lines.prefix(12) { MotionLog.write("GLITCH   " + l) }
        }
    }
}
#endif
