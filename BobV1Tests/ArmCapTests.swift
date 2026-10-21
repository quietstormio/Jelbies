//
//  ArmCapTests.swift
//  The global arm cap (ArmCap in ArmPath.swift): in EVERY scripted move Bob's arm stands out of the body no further than the WAVE's thumb
//  (the user-approved maximum, "everything has to be stubby") and its base stays buried in the body (fused, no gap). Also logs the
//  measurement table (exposed length in body heights H, before the cap / after, base width, root depth).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ArmCapTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let H = BobForm.top

    struct Stat {
        var rawMax = 0.0, capMax = 0.0, ledMax = 0.0, ledFrames = 0, baseW = 0.0, minDepth = 1.0, frames = 0
        mutating func add(a: SIMD3<Double>, b: SIMD3<Double>, rawB: SIMD3<Double>, r1: Double, r2: Double, led: Bool = false) {
            if led { ledMax = max(ledMax, ArmCap.exposed(a: a, b: b, r2: r2)); ledFrames += 1 }
            capMax = max(capMax, ArmCap.exposed(a: a, b: b, r2: r2))
            rawMax = max(rawMax, ArmCap.exposed(a: a, b: rawB, r2: r2))
            baseW = max(baseW, 2 * r1)
            minDepth = min(minDepth, -BobForm.bodySDF(a))      // how deep the root centre is buried (>0 = inside)
            frames += 1
        }
    }

    /// Wave's own numbers (the control): max exposed length and the root depth over its path.
    func waveStat() -> Stat {
        var st = Stat()
        for i in 0...100 {
            let g = ArmPath.wave.geom(at: Double(i) / 100)
            if i >= 40 { st.add(a: g.A, b: g.B, rawB: g.B, r1: g.r1, r2: g.r2) } else { st.frames += 1; st.capMax = max(st.capMax, ArmCap.exposed(a: g.A, b: g.B, r2: g.r2)); st.rawMax = st.capMax }
        }
        return st
    }

    func pathStat(_ p: ArmPath) -> Stat {
        var st = Stat()
        for i in 0...100 {
            let s = Double(i) / 100
            let g = p.geom(at: s), r = p.geomRaw(at: s)
            st.add(a: g.A, b: g.B, rawB: r.B, r1: g.r1, r2: g.r2)
        }
        return st
    }

    /// Run a move on a fresh rig and collect the capsule stats whenever a walking capsule is drawn.
    func capsuleStat(_ seconds: Float, game: Bool = true, start: (MotionRig) -> Void, until: ((MotionRig) -> Bool)? = nil) -> Stat {
        let r = MotionRig(game: game)
        Self.keep.append(r)
        r.brain.seed = 11
        r.brain.amplitude = 1
        start(r)
        var st = Stat()
        r.run(seconds, until: until.map { u in { u(r) } }) {
            guard r.brain.armG > 0.5 else { return }
            for si in 0..<2 {
                let g = r.brain.armLastGeom[si]
                st.add(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), rawB: SIMD3<Double>(r.brain.armLastRawTip[si]), r1: Double(g.r1), r2: Double(g.r2), led: r.brain.armShortW >= 0.95)
            }
        }
        return st
    }

    func testEveryMoveStaysWithinTheWaveThumb() {
        defer { DecorField.shared.clear() }
        let wave = waveStat()
        let cap = ArmCap.maximum
        MotionLog.write(String(format: "ARMCAP wave (control): exposed max %.3f H (%.4f u), base width %.3f H, root depth min %.3f u", wave.capMax / Self.H, wave.capMax, wave.baseW / Self.H, wave.minDepth))
        XCTAssertEqual(wave.capMax, cap, accuracy: 1e-9, "the wave defines the cap and passes it untouched")
        var rows: [(String, Stat)] = [("wave (control)", wave)]
        func note(_ n: String) { MotionLog.write("ARMCAP progress: \(n)") }
        let dineTo = pathStat(.nubToMouth), fwd = pathStat(.nubForward), back = pathStat(.nubBack)
        rows += [("dining reach/toss (nubToMouth)", dineTo), ("held dangle (wave s<=0.25)", pathStat(.wave)), ("nub swing fwd", fwd), ("nub swing back", back)]
        // the walking-capsule moves
        func idle(_ k: IdleKind) -> (MotionRig) -> Void { { r in r.brain.idleForced = true; _ = r.brain.idleStart(k, r.sim) } }
        note("idle (rest)"); rows.append(("idle (rest)", capsuleStat(3, start: { _ in })))
        note("walk"); rows.append(("walk", capsuleStat(7, start: { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) })))
        note("run"); rows.append(("run", capsuleStat(10, start: idle(.run), until: { $0.brain.idleState.kind == nil })))
        note("jacks"); rows.append(("jacks", capsuleStat(20, start: idle(.jacks), until: { $0.brain.idleState.kind == nil })))
        note("zoomies"); rows.append(("zoomies", capsuleStat(12, start: idle(.zoomies), until: { $0.brain.idleState.kind == nil })))
        note("belly slide"); rows.append(("belly slide", capsuleStat(12, start: idle(.slide), until: { $0.brain.idleState.kind == nil })))
        note("hop-scoot"); rows.append(("hop-scoot", capsuleStat(8, start: idle(.scoot), until: { $0.brain.idleState.kind == nil })))
        note("stumble"); rows.append(("stumble", capsuleStat(10, start: idle(.stumble), until: { $0.brain.idleState.kind == nil })))
        note("sit"); rows.append(("sit", capsuleStat(20, start: idle(.sit), until: { $0.brain.idleState.kind == nil })))
        note("look"); rows.append(("look", capsuleStat(20, start: idle(.look), until: { $0.brain.idleState.kind == nil })))
        note("sleep roll"); rows.append(("sleep (yawn, roll onto the back and up)", capsuleStat(20, start: { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sleep, r.sim); r.brain.sleep.hold = 2 }, until: { $0.brain.idleState.kind == nil && $0.t > 3 })))
        note("sleep hand-hold"); rows.append(("sleep hand-hold (arm reaches sideways)", capsuleStat(20, start: { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sleep, r.sim); r.brain.sleep.hold = 5; r.brain.sleep.holdForce = true }, until: { $0.brain.idleState.kind == nil && $0.t > 3 })))
        note("sleep hand-hold + cuddle"); rows.append(("sleep hand-hold + cuddle lean", capsuleStat(20, start: { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sleep, r.sim); r.brain.sleep.hold = 5; r.brain.sleep.holdForce = true; r.brain.sleep.mode = .cuddle }, until: { $0.brain.idleState.kind == nil && $0.t > 3 })))
        for (n, k) in [("tail spin", IdleKind.tail), ("flop", .flop), ("bounce", .bounce), ("roll", .roll), ("window", .window), ("stretch", .stretch), ("peek", .peek), ("sway", .sway)] {
            note(n); rows.append((n, capsuleStat(14, start: idle(k), until: { $0.brain.idleState.kind == nil && $0.t > 1 })))
        }
        for (n, kind, move, at) in [("decor: hop onto the beanbag, sit on top, hop off", DecorKind.beanbag, IdleKind.decorSit, SIMD2<Float>(1.1, 0.9)), ("decor: sit on a cushion", .cushion, .decorSit, SIMD2(-1.1, 0.9)),
                                   ("decor: boop the plant", .plant, .decorBoop, SIMD2(1.1, 0.9)), ("decor: kick the ball", .ball, .decorKick, SIMD2(0.9, 0.9)),
                                   ("decor: hop on the mat", .bouncymat, .decorHop, SIMD2(-1.1, 0.9)), ("decor: peek in the toy box", .toybox, .decorPeek, SIMD2(1.1, 0.9))] {
            note(n); rows.append((n, capsuleStat(26, start: { FeetAttachTests.decorStart($0, kind, at, move) }, until: { $0.brain.idleState.kind == nil && $0.t > 1 })))
        }
        for d in FeetAttachTests.batch2Decor {
            note(d.0); rows.append((d.0, capsuleStat(d.4, start: { $0.brain.throwFateForce = d.6; FeetAttachTests.decorStart($0, d.1, d.2, d.3) }, until: { $0.brain.idleState.kind == nil && $0.t > 1 })))
        }
        note("flap-hop"); rows.append(("Lavender flap-hop", capsuleStat(7, start: { $0.brain.feature = .wings; $0.brain.idleForced = true; _ = $0.brain.idleStart(.flapHop, $0.sim) }, until: { $0.brain.idleState.kind == nil && $0.t > 1 })))
        note("hop"); rows.append(("hop", capsuleStat(2, start: { $0.brain.startHopPlay(sim: $0.sim) })))
        note("name hop"); rows.append(("name hop", capsuleStat(2, start: { $0.brain.startNameHop($0.sim, $0.skinner) })))
        note("flip clean"); rows.append(("flip clean", capsuleStat(4, start: { $0.brain.startFlip(sim: $0.sim) })))
        note("faceplant"); rows.append(("faceplant", capsuleStat(5, start: { $0.brain.startFlip(sim: $0.sim, fail: true) })))
        note("thrown tumble"); rows.append(("thrown tumble", capsuleStat(3, start: { $0.rig_launch() })))
        MotionLog.write("ARMCAP table (H = \(Self.H) u; cap = \(String(format: "%.3f", cap / Self.H)) H = \(String(format: "%.4f", cap)) u)")
        MotionLog.write("ARMCAP move | frames | exposed before (H) | exposed after (H) | base width (H) | min root depth (u)")
        for (n, s) in rows {
            MotionLog.write(String(format: "ARMCAP %@ | %d | %.3f | %.3f | %.3f | %.3f", n, s.frames, s.rawMax / Self.H, s.capMax / Self.H, s.baseW / Self.H, s.minDepth))
        }
        MotionLog.write(String(format: "ARMCAP rest nub exposed %.3f H (%.4f u); body-led limit x1.10 = %.3f H", ArmCap.restNub / Self.H, ArmCap.restNub, 1.10 * ArmCap.restNub / Self.H))
        for (n, s) in rows where s.ledFrames > 0 {
            MotionLog.write(String(format: "ARMCAP body-led %@: %d frames fully body-led, exposed max %.3f H", n, s.ledFrames, s.ledMax / Self.H))
            XCTAssertLessThanOrEqual(s.ledMax, ArmCap.restNub * 1.10, "\(n): body-led moves keep the arm at or below the rest nub (+10 %)")
        }
        XCTAssertTrue(rows.contains { $0.0 == "jacks" && $0.1.ledFrames > 50 }, "jacks are body-led")
        XCTAssertTrue(rows.contains { $0.0 == "flip clean" && $0.1.ledFrames > 50 }, "the flip is body-led")
        for n in ["zoomies", "belly slide", "hop-scoot"] { XCTAssertTrue(rows.contains { $0.0 == n && $0.1.ledFrames > 20 }, "\(n) is body-led (arms capped to the rest nub)") }
        for (n, s) in rows {
            XCTAssertLessThanOrEqual(s.capMax, cap * 1.02, "\(n): exposed arm length within the wave's maximum")
            if s.frames > 0 && n != "idle (rest)" { XCTAssertGreaterThanOrEqual(s.minDepth, 0.015, "\(n): the arm base stays buried in the body (fused, no gap)") }
        }
        let capsuleRows = rows.filter { !["wave (control)"].contains($0.0) && $0.1.frames > 0 }
        XCTAssertGreaterThan(capsuleRows.count, 5, "the moves actually drew arms")
        XCTAssertTrue(rows.contains { $0.0.hasPrefix("sleep hand-hold (") && $0.1.frames > 100 }, "the hand-hold drew its reaching arm")
    }

    /// Shoes are separate props on the feet: building them every frame in the walking / jacks / run / hop moves leaves every arm within the wave's thumb.
    func testShoesLeaveTheArmsStubby() {
        func idle(_ k: IdleKind) -> (MotionRig) -> Void { { r in r.brain.idleForced = true; _ = r.brain.idleStart(k, r.sim) } }
        let moves: [(String, Float, (MotionRig) -> Void)] = [
            ("walk + shoes", 7, { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) }), ("run + shoes", 6, idle(.run)), ("jacks + shoes", 8, idle(.jacks)),
            ("zoomies + shoes", 8, idle(.zoomies)), ("hop + shoes", 2, { $0.brain.startHopPlay(sim: $0.sim) }), ("bounce + shoes", 4, idle(.bounce)),
        ]
        for (name, secs, start) in moves {
            let r = MotionRig(game: true)
            Self.keep.append(r)
            r.brain.seed = 11; r.brain.amplitude = 1
            start(r)
            var st = Stat(), k = 0
            r.run(secs) {
                k += 1
                if k % 4 == 0, r.skinner.beansActive {
                    r.render()
                    for s in 0..<2 {
                        let bean = r.bean[s].map { id -> SIMD3<Float> in let o = 6 * Int(id); return SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2]) }
                        guard bean.count == FootBean.vertexCount else { continue }
                        let b = RoomMeshBuilder(); b.material = .plain
                        ShoeModel.build(.glitterShoes, bean: bean, floorY: r.sim.floorY, time: Float(k) / 60, side: s, into: b)
                    }
                }
                guard r.brain.armG > 0.5 else { return }
                for si in 0..<2 {
                    let g = r.brain.armLastGeom[si]
                    st.add(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), rawB: SIMD3<Double>(r.brain.armLastRawTip[si]), r1: Double(g.r1), r2: Double(g.r2), led: r.brain.armShortW >= 0.95)
                }
            }
            MotionLog.write(String(format: "ARMCAP shoes %@: %d frames, exposed max %.3f H", name, st.frames, st.capMax / Self.H))
            XCTAssertLessThanOrEqual(st.capMax, ArmCap.maximum * 1.02, "\(name): arms stay within the wave's thumb")
            if st.frames > 0 { XCTAssertGreaterThanOrEqual(st.minDepth, 0.015, "\(name): arm bases stay buried") }
        }
    }

    /// Cost of the cap + fillet collar per walking step: brain.tick with ArmCap on vs off.
    func testCapAndCollarCost() {
        var us: [Bool: Double] = [:]
        var capOnly = Double.infinity
        for (on, col) in [(false, true), (true, true), (true, false), (false, true), (true, true), (true, false)] {
            ArmCap.enabled = on; ArmCap.collar = col
            let r = MotionRig(game: false)
            r.renderSamples = false
            r.brain.request(.goTo(r.root + SIMD2(0, 4)))
            r.run(1.2)
            var tick = 0.0, n = 0
            for _ in 0..<240 {
                let a = CACurrentMediaTime()
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                let b = CACurrentMediaTime()
                r.sim.step()
                guard r.skinner.beansActive else { continue }
                tick += b - a; n += 1
            }
            let v = tick / Double(max(n, 1)) * 1e6
            if on && !col { capOnly = min(capOnly, v) } else { us[on] = min(us[on] ?? .infinity, v) }
        }
        ArmCap.enabled = true; ArmCap.collar = true
        MotionLog.write(String(format: "ARMCAP cost: cap only (no collar) %.1f us", capOnly))
        MotionLog.write(String(format: "ARMCAP cost: brain.tick off %.1f us, on %.1f us, collar+cap = %.1f us per step; collar vertices %d", us[false]!, us[true]!, us[true]! - us[false]!, ArmCollar.build(rest: MotionRig.renderMesh.rest, skip: []).ids.count))
        XCTAssertLessThan(us[true]! - us[false]!, 60, "the cap + collar stay a small slice of the step")
    }

    func testCapLeavesShortArmsAloneAndShortensLongOnes() {
        let a = SIMD3<Double>(0.5, 0.5, 0.15)
        let short = a + SIMD3(0.05, 0.1, 0)
        XCTAssertEqual(ArmCap.clampTip(a: a, b: short, r2: 0.115), short)
        let long = a + SIMD3(0.6, 0.6, 0)
        let c = ArmCap.clampTip(a: a, b: long, r2: 0.115)
        XCTAssertLessThan(simd_length(c - a), simd_length(long - a))
        XCTAssertLessThanOrEqual(ArmCap.exposed(a: a, b: c, r2: 0.115), ArmCap.maximum + 1e-6)
        let d = simd_normalize(long - a)
        XCTAssertLessThan(simd_length(simd_cross(c - a, d)), 1e-9, "only shortened along its own axis")
    }
}

extension MotionRig {
    /// A hard throw: launch the sim (the tumble the touch throw gives him).
    func rig_launch() { sim.launch(velocity: SIMD3<Float>(0.6, 2.8, 0.2), spin: SIMD3<Float>(0, 0, -2.5)) }
}
