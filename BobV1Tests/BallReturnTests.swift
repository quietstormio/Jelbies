//
//  BallReturnTests.swift
//  play-ball-r1 (owner 2026-11-22: "Ensure Jelmikos kick the ball back to you and when you bounce off their head they are facing you and actually jump and hit it back").
//  Flicks a spread of 50 balls (floor rolls, low lobs, mid lobs, high lobs, front drops; left / centre / right; two depths) through the real play code (PlayToss.launch is the
//  flick's own release), with one Jelmiko and with three, and measures every strike: kick or header, the angle between the ball's outgoing direction and the direction to the
//  player, whether the Jelmiko faced the player (within 20 deg) at contact, whether both feet were off the floor for a header, and where the ball came down.
//  `PlayTuning.ballReturnOld` (dev `-BallReturnOld 1`) = the play as it was; the test runs both and prints the before / after table (PBR lines; BALLRETURN_OUT writes them to a file).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BallReturnTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let portrait = CGSize(width: 440, height: 956)
    static let landscape = CGSize(width: 956, height: 440)

    override func setUp() { super.setUp(); Self.reset() }
    override func tearDown() { Self.reset(); super.tearDown() }
    static func reset() {
        PlayTuning.old = false; PlayTuning.zoomOverride = nil; PlayTuning.ballReturnOld = false
        GameCamera.playBlend = 0; RoomLayout.ballSpheres = []
        DecorField.shared.clear()
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(portrait.width / portrait.height))
    }
    static func room(_ size: CGSize) {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let a = Float(size.width / size.height); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
    }

    // MARK: the spread

    enum Arc: String, CaseIterable { case roll, lowLob, midLob, highLob, frontDrop }
    struct Spec { var arc: Arc; var x: Float; var deep: Bool; var jitter: Float }
    /// 5 arcs x 5 sides x 2 depths = 50 balls (the sides are fractions of the floor's half width at the target depth).
    static func spread() -> [Spec] {
        var out: [Spec] = []
        var k: Float = 0
        for arc in Arc.allCases { for x in [Float(-0.8), -0.4, 0, 0.4, 0.8] { for deep in [false, true] { k += 1; out.append(Spec(arc: arc, x: x, deep: deep, jitter: sinf(k * 12.9898) * 0.5)) } } }
        return out
    }

    struct Strike { var reflex: Bool; var rest: SIMD2<Float>; var arc: Arc; var header: Bool; var pass: Bool; var faceErr: Float; var outErr: Float; var landFront: Bool; var feetOff: Bool; var hopping: Bool; var jelly: Int; var landZ: Float }
    struct BallRun { var spec: Spec; var reachable: Bool; var strikes: [Strike] = []; var bodyHits = 0; var rescued = false; var caught = false; var secs: Float = 0 }
    struct Report { var n: Int; var size: String; var runs: [BallRun]; var line = ""; var fails: [String] = []; var minPass: Float = 99 }

    /// Prints a line and appends it to $BALLRETURN_OUT.log (the test runner's stdout is not in the xcodebuild log).
    static func say(_ l: String) {
        print(l)
        guard let f = ProcessInfo.processInfo.environment["BALLRETURN_OUT"] else { return }
        let path = f + ".log"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((l + "\n").data(using: .utf8)!); try? h.close() } else { try? (l + "\n").write(toFile: path, atomically: true, encoding: .utf8) }
    }
    static func angle(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let la = simd_length(a), lb = simd_length(b)
        guard la > 1e-4, lb > 1e-4 else { return 0 }
        return acosf(max(-1, min(1, simd_dot(a, b) / (la * lb)))) * 180 / .pi
    }

    /// World height of the lowest vertex of each drawn foot (floor = 0).
    static func footLows(_ r: MotionRig) -> [Float] {
        r.render()
        let beans = r.skinner.beansActive && r.skinner.beanBlend > 0.05
        var out: [Float] = []
        for s in 0..<2 {
            let ids = beans ? r.bean[s] : r.core[s]
            guard !ids.isEmpty else { continue }
            var lo = Float.infinity
            for id in ids { lo = min(lo, r.dyn[6 * Int(id) + 1]) }
            out.append(lo)
        }
        return out
    }
    nonisolated(unsafe) static var restFootLow: Float = 0

    func runSpread(jellies n: Int, size: CGSize, old: Bool, kind: DecorKind = .ball, seed: UInt64 = 5, balls ballsIn: [Spec]? = nil, log: Bool = false) -> Report {
        let balls = ballsIn ?? Self.spread()
        PlayTuning.ballReturnOld = old
        Self.room(size)
        BlobBrain.pickBudgetSeconds = .infinity
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        let start: [SIMD2<Float>] = n == 1 ? [SIMD2(0, 1.4)] : [SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)]
        let rs: [MotionRig] = start.enumerated().map { i, s in
            let r = MotionRig(game: true, settle: 0.5)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = seed &* 31 &+ UInt64(i) &* 7 &+ 5
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: s); r.run(0.3)
            return r
        }
        let p = PlayToss(); p.seed(seed &* 977 &+ 13); p.viewSize = size
        TossTuning.zBack = -2.4; TossTuning.zFront = 9
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        p.begin(ball: kind, title: "ball", jellies: js(), snapCamera: true)
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf
        let dt = rs[0].sim.stepDt
        for r in rs { _ = r }
        var t: Float = 0
        func step() { for r in rs { r.tick() }; p.tick(dt: dt, world: w, jellies: js()); t += dt }
        while t < 5 || p.phase != .inHand { step(); if t > 14 { break } }          // (they walk to the line)
        // reference: the foot's low point standing
        Self.restFootLow = rs[0].brain.idleState.kind == nil ? (Self.footLows(rs[0]).min() ?? 0) : 0
        let floor = GameCamera.roamFloor
        let fz0 = floor?.minZ ?? -2
        let frontZ = TossTuning.zBack + (TossTuning.zFront - TossTuning.zBack) * 2 / 3          // (the front third of the ball's room, back wall to front limit)
        var runs: [BallRun] = []
        var cur = BallRun(spec: balls[0], reachable: true)
        var curArc = Arc.roll
        var passNext = false
        var minPass: Float = 99
        var player = SIMD2<Float>.zero
        p.onEvent = { e in
            switch e {
            case .rescue: cur.rescued = true
            case .bodyBoop: cur.bodyHits += 1
            case .pass(let a, let b): passNext = true; if a < rs.count, b < rs.count { minPass = min(minPass, simd_distance(rs[a].brain.position, rs[b].brain.position)) }
            case .header(let id, _), .kick(let id):
                var isHeader = false; if case .header = e { isHeader = true }
                let r = rs[id]
                let j = r.brain.position
                let face = Self.angle(SIMD2(sinf(r.sim.yaw()), cosf(r.sim.yaw())), player - j)
                let bxz = SIMD2(p.ball.pos.x, p.ball.pos.z)
                let out = Self.angle(SIMD2(p.ball.vel.x, p.ball.vel.z), player - bxz)
                // where the struck ball ends up (left alone: its bounces and roll-out)
                var sb = p.ball; sb.ignoring = nil; var sw = w; sw.bodies = []
                // (it is caught at the catch zone in the game: the front-third test is how far toward the player it gets, not where it would rest after bouncing back off the front wall)
                var maxZ = sb.pos.z
                for _ in 0..<420 { sb.step(1.0 / 30, in: sw); maxZ = max(maxZ, sb.pos.z); if sb.resting || sb.pos.z >= p.catchZ() { break } }
                let land = SIMD2(sb.pos.x, maxZ)
                let lows = isHeader ? Self.footLows(r) : []
                let off = isHeader && lows.count == 2 && lows.allSatisfy { $0 > 0.02 }
                cur.strikes.append(Strike(reflex: false, rest: land, arc: curArc, header: isHeader, pass: passNext, faceErr: face, outErr: out, landFront: land.y >= frontZ, feetOff: off, hopping: r.brain.idleState.kind == .tossHeader, jelly: id, landZ: land.y))
                passNext = false
            case .caught: cur.caught = true
            default: break
            }
        }
        let arcs: [String]? = { let l = (ProcessInfo.processInfo.environment["BALLRETURN_ARCS"] ?? "").split(separator: ",").map(String.init); return l.isEmpty ? nil : l }()
        for (i, spec) in balls.enumerated() {
            if let arcs, !arcs.contains(spec.arc.rawValue) { continue }
            // wait until the ball is in the hand and the Jelmiko are back on the line
            var wait: Float = 0
            while (p.phase != .inHand || wait < 1.6) && wait < 20 { step(); wait += dt }
            let hand = p.handWorld()
            player = SIMD2(hand.x, hand.z)
            let z0 = p.spots.values.map(\.y).reduce(0, +) / Float(max(p.spots.count, 1))
            let tz = spec.deep ? z0 - 1.0 : z0 + 0.6
            let reach = PlayToss.ballReach(tz) - 0.7
            let tx = min(max(spec.x * reach, -reach), reach)
            let r = p.ball.radius
            let g = TossTuning.gravity
            var from = hand, v = SIMD3<Float>.zero
            let tgt = SIMD2(tx, tz + spec.jitter * 0.3)
            switch spec.arc {
            case .roll:
                from = SIMD3(hand.x, r, hand.z - 0.2)
                let d = tgt - SIMD2(from.x, from.z)
                let speed = min(simd_length(d) * TossTuning.rollDecayPerS * 1.1 + 0.6, 6)
                let u = d / simd_length(d)
                v = SIMD3(u.x * speed, 0, u.y * speed)
            case .lowLob: v = TossAim.ballistic(from: from, to: SIMD3(tgt.x, r, tgt.y), flight: 0.62 * TossTuning.slow)
            case .midLob: v = TossAim.ballistic(from: from, to: SIMD3(tgt.x, 1.7, tgt.y), flight: 0.9 * TossTuning.slow)
            case .highLob:
                // comes down on the head of whoever is nearest the aim point
                var aim = tgt; var best = Float.infinity
                for q in rs { let d = simd_distance(q.brain.position, tgt); if d < best { best = d; aim = q.brain.position } }
                let top = p.jellies.first?.headTop ?? 1.2
                v = TossAim.ballistic(from: from, to: SIMD3(aim.x, top + 0.2, aim.y), flight: 1.25 * TossTuning.slow)
            case .frontDrop: v = TossAim.ballistic(from: from, to: SIMD3(tgt.x * 0.6, r, z0 + 2.2), flight: 0.8 * TossTuning.slow)
            }
            _ = g
            curArc = spec.arc
            cur = BallRun(spec: spec, reachable: true)
            let tStart = t
            p.launch(from: from, velocity: v)
            // reachable (the rule, fixed): left alone the ball comes to rest on the play floor, inside the Jelmiko's own reach, not in the catch zone and not hard against a wall (nobody can stand behind it)
            var land = SIMD2(from.x, from.z) + SIMD2(v.x, v.z) * 0.8
            if let l = p.ball.landing(xHalf: PlayToss.ballReach) { land = l.xz }
            var sb = p.ball; var sw = w; sw.bodies = []
            for _ in 0..<420 { sb.step(1.0 / 30, in: sw); if sb.resting { break } }
            let rest = SIMD2(sb.pos.x, sb.pos.z)
            let rz = fz0
            cur.reachable = abs(rest.x) <= PlayToss.bodyReach(rest.y) - 0.3 && rest.y >= rz + 0.9 && rest.y <= p.catchZ() - 0.8
            var guardT: Float = 0
            let trace = Set((ProcessInfo.processInfo.environment["BALLRETURN_TRACE"] ?? "").split(separator: ",").compactMap { Int($0) })
            var nextTrace: Float = 0
            while !(p.phase == .catching || p.phase == .inHand) && guardT < 16 {
                step(); guardT += dt
                if trace.contains(i), guardT >= nextTrace {
                    nextTrace += 0.25
                    Self.say(String(format: "PBRTRACE %d t %.2f %@ ball (%.2f,%.2f,%.2f) v (%.1f,%.1f,%.1f) jellies %@", i, guardT, String(describing: p.phase), p.ball.pos.x, p.ball.pos.y, p.ball.pos.z, p.ball.vel.x, p.ball.vel.y, p.ball.vel.z,
                                          rs.map { String(format: "(%.1f,%.1f %@ %@)", $0.brain.position.x, $0.brain.position.y, String(describing: $0.brain.idleState.kind), $0.brain.idleState.kind == .tossBump ? "st\($0.brain.idleState.toss.stage)" : "") }.joined(separator: " ")))
                }
            }
            cur.secs = t - tStart
            runs.append(cur)
            if log { Self.say("PBRBALL \(i) \(spec.arc.rawValue) x \(spec.x) deep \(spec.deep) reach \(cur.reachable) strikes \(cur.strikes.map { "\($0.header ? "H" : "K")\($0.jelly) face \(Int($0.faceErr)) out \(Int($0.outErr)) feet \($0.feetOff) landZ \(String(format: "%.1f", $0.landZ))" }) bodyHits \(cur.bodyHits) rescued \(cur.rescued) land (\(String(format: "%.1f", land.x)),\(String(format: "%.1f", land.y))) secs \(String(format: "%.1f", cur.secs))") }
        }
        p.end()
        TossTuning.zBack = -2.4; TossTuning.zFront = 9
        PlayTuning.ballReturnOld = false
        var rep = Report(n: n, size: size.width > size.height ? "landscape" : "portrait", runs: runs)
        rep.minPass = minPass
        rep.line = Self.describe(rep, old: old, frontZ: frontZ) + String(format: " | zBack %.1f zFront %.1f catchZ %.1f", TossTuning.zBack, TossTuning.zFront, p.catchZ())
        return rep
    }

    // MARK: table

    struct Stats { var balls = 0, reachable = 0, struckReach = 0, kicks = 0, headers = 0, passes = 0, ignored = 0, bounceOnly = 0, rescued = 0
        var strikes = 0, aimed = 0, aimedFront = 0, faced = 0, headersFeetOff = 0, awayStrikes = 0, outMean: Float = 0, faceMean: Float = 0 }
    static func stats(_ rep: Report) -> Stats {
        var s = Stats()
        for r in rep.runs {
            s.balls += 1; if r.reachable { s.reachable += 1 }
            let real = r.strikes.filter { !$0.pass }
            if r.strikes.isEmpty { if r.bodyHits > 0 { s.bounceOnly += 1 } else { s.ignored += 1 } }
            if r.rescued { s.rescued += 1 }
            if r.reachable, !r.strikes.isEmpty { s.struckReach += 1 }
            for k in r.strikes {
                s.strikes += 1; if k.header { s.headers += 1 } else { s.kicks += 1 }
                if k.pass { s.passes += 1 }
            }
            for k in real {
                if k.outErr <= 20 { s.aimed += 1; if k.landFront { s.aimedFront += 1 } }
                if k.faceErr <= 20 { s.faced += 1 } else { s.awayStrikes += 1 }
                s.outMean += k.outErr; s.faceMean += k.faceErr
                if k.header, k.feetOff { s.headersFeetOff += 1 }
            }
        }
        let nr = Float(max(rep.runs.flatMap { $0.strikes.filter { !$0.pass } }.count, 1))
        s.outMean /= nr; s.faceMean /= nr
        return s
    }
    static func describe(_ rep: Report, old: Bool, frontZ: Float) -> String {
        let s = stats(rep)
        let realN = max(s.strikes - s.passes, 1)
        let hdrN = rep.runs.flatMap { $0.strikes.filter { $0.header && !$0.pass } }.count
        var perArc = ""
        for arc in Arc.allCases {
            let rs = rep.runs.filter { $0.spec.arc == arc }
            perArc += "\(arc.rawValue) \(rs.filter { !$0.strikes.isEmpty }.count)/\(rs.count) (headed \(rs.filter { $0.strikes.contains { $0.header } }.count), reachable \(rs.filter { $0.reachable }.count)) "
        }
        let reflex = rep.runs.flatMap { $0.strikes }.filter { $0.reflex }.count
        let struckAll = rep.runs.filter { !$0.strikes.isEmpty }.count
        let a = String(format: "%@ %@ x%d | STRUCK of all %d balls: %d (%.0f%%); per arc: %@| reachable %d, struck of reachable %d (%.0f%%) | kicks %d (reflex %d) headers %d (passes %d) | ignored %d, body-bounce only %d, rescued %d | ",
                       old ? "BEFORE" : "AFTER", rep.size, rep.n, s.balls, struckAll, 100 * Float(struckAll) / Float(max(s.balls, 1)), perArc, s.reachable, s.struckReach, 100 * Float(s.struckReach) / Float(max(s.reachable, 1)),
                       s.kicks, reflex, s.headers, s.passes, s.ignored, s.bounceOnly, s.rescued)
        let b = String(format: "strikes within 20 deg of the player %d/%d (%.0f%%), of those ending in the front third (z >= %.1f) %d (%.0f%%) | facing within 20 deg %d/%d (%.0f%%), away %d | mean out angle %.0f deg, mean facing error %.0f deg | headers with both feet off the floor %d/%d",
                       s.aimed, realN, 100 * Float(s.aimed) / Float(realN), frontZ, s.aimedFront, 100 * Float(s.aimedFront) / Float(max(s.aimed, 1)),
                       s.faced, realN, 100 * Float(s.faced) / Float(realN), s.awayStrikes, s.outMean, s.faceMean, s.headersFeetOff, hdrN)
        return a + b
    }

    // MARK: tests

    /// The jump's numbers: seconds from the start of the hop to its top, how far the crown and each foot rise (both old and new apex).
    func testHeaderJumpNumbers() {
        Self.room(Self.portrait)
        for old in [true, false] {
            PlayTuning.ballReturnOld = old
            let r = MotionRig(game: true, settle: 0.5)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.anticsEnabled = true
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: SIMD2(0, 0.6)); for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            let rest = r.sim.centroid().y + BobShape.H * 0.5
            let restLows = Self.footLows(r)
            BlobBrain.tossApexOverride = old ? nil : BlobBrain.tossJumpApex
            XCTAssertTrue(r.brain.tossHeaderStart(r.sim))
            BlobBrain.tossApexOverride = nil
            var best: Float = 0, bestT: Float = 0, t: Float = 0, feetUp: Float = 0
            while t < 1.2 { r.tick(); t += r.sim.stepDt; let h = r.sim.centroid().y + BobShape.H * 0.5; if h > best { best = h; bestT = t; feetUp = (Self.footLows(r).min() ?? 0) } }
            Self.say("PBR jump \(old ? "OLD" : "NEW"): apex at \(bestT) s, crown rest \(rest) +\(best - rest), lowest foot at the top \(feetUp) (standing \(restLows))")
        }
        PlayTuning.ballReturnOld = false
    }

    func testBeforeAfterTable() {
        var out = ""
        var reps: [Report] = []
        let env = ProcessInfo.processInfo.environment
        let cases = (env["BALLRETURN_CASES"] ?? "1p,3p,3l").split(separator: ",").map(String.init)
        for (n, size) in [(1, Self.portrait), (3, Self.portrait), (3, Self.landscape)] {
            guard cases.contains("\(n)\(size.width > size.height ? "l" : "p")") else { continue }
            for kind in [DecorKind.ball, .soccerball, .beachball] {
                for old in [true, false] {
                    if env["BALLRETURN_ONLY"] == "new", old { continue }
                    var rep = runSpread(jellies: n, size: size, old: old, kind: kind, log: ProcessInfo.processInfo.environment["BALLRETURN_LOG"] == "1")
                    rep.line = "\(kind) " + rep.line
                    Self.say("PBR " + rep.line); out += rep.line + "\n"
                    reps.append(rep)
                }
            }
        }
        out = "REACHABLE = left alone, the ball comes to rest on the play floor inside the Jelmiko's reach (|x| <= bodyReach - 0.3), at least 0.9 in front of the back wall, and at least 0.8 behind the catch zone; STRUCK = a header or kick (not a pass, not a soft bounce)\n" + out
        if let f = ProcessInfo.processInfo.environment["BALLRETURN_OUT"] { try? out.write(toFile: f, atomically: true, encoding: .utf8) }
        guard ProcessInfo.processInfo.environment["BALLRETURN_NOASSERT"] != "1" else { return }
        for rep in reps where !rep.line.contains(" BEFORE ") {
            let s = Self.stats(rep)
            let real = max(s.strikes - s.passes, 1)
            let tag = "\(rep.size) x\(rep.n)"
            XCTAssertGreaterThanOrEqual(Float(s.faced), 0.9 * Float(real), "\(tag): facing the player at \(s.faced)/\(real) strikes")
                        let hdr = rep.runs.flatMap { $0.strikes.filter { $0.header } }
            XCTAssertEqual(hdr.filter { $0.feetOff }.count, hdr.count, "\(tag): every header has both feet off the floor")
            XCTAssertGreaterThanOrEqual(rep.minPass, PlayTuning.passMinDist - 0.4, "\(tag): a pass between Jelmiko closer than that")
        }
    }
}
