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
    func pops(_ kind: IdleKind, seconds: Float = 8, bar: Float = 3, dumpWindow: ClosedRange<Float> = 99...99) -> Pops {
        let r = MotionRig(game: true)
        var core = GlitchCore(); core.bars.poseCm = bar
        var out = Pops()
        r.brain.commandedIdle = kind          // (as the tour / a voice command does: the brain starts it on its next tick)
        var started = false
        var after: Float = -1
        let n = Int(seconds * 60)
        var frames = 0, maxArmBlend: Float = 0, maxBean: Float = 0, maxV: Float = 0, counts = Set<Int>()
        var lastLocal: [SIMD3<Float>] = []
        for i in 0..<n {
            r.tick()
            r.render()
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
                out.lines.append(String(format: "%@ t=%.3f %@ %.1f cm %@ armDirW=%.2f armLift=%.2f armG=%.2f gait=%@ k=%.0f", "\(kind)", Float(i) / 60, part, e.perStep, e.detail, r.brain.armDirW, r.brain.armLiftNow, r.brain.armG, "\(r.brain.gait.phase)", r.sim.attractor.strength))
            }
            if r.brain.idleState.kind != nil { started = true }
            if after < 0, started, r.brain.idleState.kind == nil { after = Float(i) / 60 }
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
