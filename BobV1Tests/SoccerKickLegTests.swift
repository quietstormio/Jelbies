//
//  SoccerKickLegTests.swift
//  The kicking leg returns: after the ball leaves, the stomp foot is back under the body within ~0.35 s (user 2026-11-05: "their leg just stay out there,
//  make it a quick motion"). Measures, per frame, each sole's distance from its stand spot (body root + the foot's nominal offset) for the decor kick
//  and the pass kick, plus the standing foot's drift.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SoccerKickLegTests: XCTestCase {
    /// Extension of foot `s` from its stand spot (xz, metres-ish world units) and its lift.
    static func ext(_ b: BlobBrain, _ s: Int) -> Float {
        let nominal = SIMD2(b.px, b.pz) + rotXZ(b.geom.off[s], b.yaw)
        return simd_distance(b.feet.pos[s], nominal)
    }
    struct Trace { var fireFrame = -1; var side = 0; var frames: [(t: Int, e0: Float, e1: Float, active: Bool)] = []; var note: [Int: String] = [:] }

    func summarize(_ name: String, _ tr: Trace, _ fps: Float = 60) -> (outSecs: Float, returned: Bool, drift: Float) {
        guard tr.fireFrame >= 0 else { return (999, false, 0) }
        let after = tr.frames.filter { $0.t >= tr.fireFrame && $0.t <= tr.fireFrame + 90 }          // (1.5 s after contact: still inside the kick / the pass, before any later walk steps)
        let kicker = tr.side
        func e(_ f: (t: Int, e0: Float, e1: Float, active: Bool)) -> Float { kicker == 0 ? f.e0 : f.e1 }
        func o(_ f: (t: Int, e0: Float, e1: Float, active: Bool)) -> Float { kicker == 0 ? f.e1 : f.e0 }
        let thr: Float = 0.08
        var lastOut = tr.fireFrame
        for f in after where e(f) > thr { lastOut = f.t }
        let returned = after.last.map { e($0) <= thr } ?? false
        var line = "SOCCERLEG \(name): fire@\(tr.fireFrame) kickerFoot \(kicker) lastExtended>\(thr)@+\(Float(lastOut - tr.fireFrame) / fps)s returned \(returned)\n"
        for f in after.prefix(300) where (f.t - tr.fireFrame) % 3 == 0 { line += String(format: "  +%.2fs ext %.3f other %.3f active %d %@\n", Float(f.t - tr.fireFrame) / fps, e(f), o(f), f.active ? 1 : 0, tr.note[f.t] ?? "") }
        MotionLog.write(line)
        let drift = after.prefix(40).map { o($0) }.max() ?? 0          // (the standing foot's distance from its stand spot over the 0.67 s after contact)
        return (Float(lastOut - tr.fireFrame) / fps, returned, drift)
    }

    func testTheDecorKickLegComesBackQuickly() {
        for seed in [UInt64(3), 11] {
            SoccerState.shared.reset(); SoccerEvents.clear(); DecorField.shared.clear(); DecorField.shared.bodies = []
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0)
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.3, z: 0.9)])
            let r = MotionRig(game: true); SoccerTests.keep.append(r)
            r.renderSamples = false; r.brain.anticsEnabled = true
            r.brain.abortScript(r.sim, r.skinner); r.sim.teleport(toXZ: SIMD2(-1.4, 1.4))
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            r.brain.seed = seed; r.brain.soccerModeForce = 0; r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(.soccerKick, r.sim))
            var tr = Trace(), n = 0, firedSeen = false
            r.run(30, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
                DecorField.shared.bodies = [(r.brain.steerID, r.brain.position)]; DecorField.shared.tick(dt: 1.0 / 60)
                n += 1
                if !firedSeen, r.brain.idleState.soccer.fired { firedSeen = true; tr.fireFrame = n; tr.side = r.brain.idleState.soccer.stompSide }
                tr.frames.append((n, Self.ext(r.brain, 0), Self.ext(r.brain, 1), r.brain.feet.active))
                tr.note[n] = "side \(r.brain.feet.side) stage \(r.brain.idleState.soccer.stage) kind \(String(describing: r.brain.idleState.kind)) script \(r.brain.script)"
            }
            // keep watching 1.5 s after the move ends (the foot must not be left out for the next move)
            for _ in 0..<90 { r.tick(); n += 1; tr.frames.append((n, Self.ext(r.brain, 0), Self.ext(r.brain, 1), r.brain.feet.active)) }
            let s = summarize("decor seed \(seed)", tr)
            XCTAssertTrue(firedSeen, "seed \(seed): a kick fired")
            XCTAssertLessThanOrEqual(s.outSecs, 0.40, "seed \(seed): the kicking leg is back under him within 0.4 s of contact (was out \(s.outSecs) s)")
            XCTAssertTrue(s.returned, "seed \(seed): the leg ends under the body")
            XCTAssertLessThanOrEqual(s.drift, 0.01, "seed \(seed): the planted foot stays put (drift \(s.drift))")
        }
    }

    func testThePassKickLegComesBackQuickly() {
        for seed in [UInt64(5), 9] {
            SoccerState.shared.reset(); SoccerEvents.clear(); DecorField.shared.clear(); DecorField.shared.bodies = []
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0)
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.2, z: 1.0)])
            let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.5, 1.4), SIMD2(1.8, 1.6)], quiet: true, seed: seed)
            SoccerTests.keep.append(lab)
            let a = lab.rigs[0], b = lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(.pass, with: b.brain, a.sim))
            var tr = Trace(), n = 0, kicker = a, passTr: [Trace] = [], impactFrame = -1
            for _ in 0..<(60 * 40) {
                lab.tick(watching: false)
                DecorField.shared.bodies = lab.rigs.map { ($0.brain.steerID, $0.brain.position) }
                DecorField.shared.tick(dt: 1.0 / 60)
                n += 1
                // contact = the stomp foot's LANDING after the pass flagged the kick (the ball leaves at phase t = 0.38; a kicker still mid-step when the pass began lands later)
                if impactFrame < 0, let ss = a.brain.social, ss.phase == 1, ss.impacted { impactFrame = n; kicker = ss.roles == 0 ? a : b; tr.side = kicker.brain.socialBook.soccerStompSide }
                if tr.fireFrame < 0, impactFrame > 0, Self.ext(kicker.brain, tr.side) > 0.2 { tr.fireFrame = n; MotionLog.write("SOCCERLEG pass seed \(seed): ball left at frame \(impactFrame), stomp foot landed +\(Float(n - impactFrame) / 60) s later") }
                tr.frames.append((n, Self.ext(kicker.brain, 0), Self.ext(kicker.brain, 1), kicker.brain.feet.active))
                if tr.fireFrame >= 0, n > tr.fireFrame + 300 { break }
            }
            _ = passTr
            let s = summarize("pass seed \(seed)", tr)
            XCTAssertGreaterThan(tr.fireFrame, 0, "seed \(seed): a pass kick fired")
            XCTAssertLessThanOrEqual(s.outSecs, 0.40, "seed \(seed): the pass-kicking leg is back under him within 0.4 s of contact (was out \(s.outSecs) s)")
            XCTAssertTrue(s.returned, "seed \(seed): the leg ends under the body")
            XCTAssertLessThanOrEqual(s.drift, 0.01, "seed \(seed): the planted foot stays put (drift \(s.drift))")
        }
    }
}
