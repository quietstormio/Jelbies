//
//  StormFeetTests.swift
//  Feet stay attached in every storm move (docs/HANDOFF.md "Feet stay attached"): the huddle stance, the tremble, the flash flinch (standing, in a hop, mid-scurry), the
//  scurry itself (the walk at the hurry speed) and the shake-off after it. Each runs for all 6 characters, bare and with shoes, driving the REAL storm pose values
//  (StormPose.huddle) through the brain's storm channel, and asserts in every frame what EmoteFeetTests does: the skin's leash / tether never moves a foot piece
//  (the runtime guard in OnePieceInvariantTests.run), no foot detached, the neck ring >= 70 % of standing and the join >= 1 cm inside the body whenever both pieces are
//  off the floor, the collar moves no skin more than 2 cm; plus: the body never tips past 0.5 rad.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class StormFeetTests: XCTestCase {
    override func setUp() { super.setUp(); EmoteFeetTests.reset() }
    override func tearDown() { EmoteFeetTests.reset(); super.tearDown() }

    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/weather/"

    /// Drives the storm channel from the step counter: `stance(t)` gives (standing seconds, flinch seconds or -1) or nil for no pose.
    static func drive(_ r: MotionRig, n: Int, stance: (Float) -> (standing: Float, flinch: Float)?) {
        let t = Float(n) / 60
        if let s = stance(t) {
            let p = StormPose.huddle(t: t, standing: s.standing, phase: 1.7, flinch: s.flinch, amplitude: 1)
            r.brain.storm.write(pitch: p.pitch, roll: p.roll, squash: p.squash)
        } else { r.brain.storm.clear() }
    }

    /// A flinch every 1.3 s (as the flashes come at the peak).
    static func flinchEvery(_ t: Float) -> Float { t.truncatingRemainder(dividingBy: 1.3) }

    typealias SC = LegsDrawnAuditTests.Scenario

    static func scenario(_ name: String) -> SC {
        var n = 0
        switch name {
        case "tremble":          // the huddle stance, standing: hunched, trembling, a flinch every 1.3 s
            return SC(name: "storm: tremble", game: true, seconds: 7, setup: { r, _ in n = 0; return true }, each: { r in n += 1; drive(r, n: n) { t in (t, flinchEvery(t)) } })
        case "flinch hop":       // the startle: a hop with a big flinch at the take-off
            return SC(name: "storm: startle hop", game: true, seconds: 3, setup: { r, _ in n = 0; r.brain.startHopPlay(sim: r.sim, distance: 0.0001); return true },
                      each: { r in n += 1; drive(r, n: n) { t in t < 2 ? (min(t, 0.5), t - 0.15) : nil } })
        case "scurry":          // the walk at the hurry speed, with the flinch mid-stride, then the stance
            return SC(name: "storm: scurry", game: true, seconds: 8, setup: { r, _ in n = 0; r.brain.hurry = true; r.brain.request(.come(to: SIMD2(1.8, 0.5))); return true },
                      each: { r in
                          n += 1
                          r.brain.hurryUpdate(dt: r.sim.stepDt)
                          let t = Float(n) / 60
                          if r.brain.activity == .idle, r.brain.pending == nil { drive(r, n: n) { _ in (max(0, t - 4), flinchEvery(t)) } }
                          else if t > 1.0, t < 1.5 { drive(r, n: n) { _ in (0, (t - 1.0)) } }          // (the flinch pose rides on the run)
                          else { r.brain.storm.clear() }
                      })
        case "shake":            // the relief: out of the stance into the shake-off, then the scatter walk
            return SC(name: "storm: shake-off and scatter", game: true, seconds: 9, setup: { r, _ in
                n = 0; r.brain.idleForced = true; return true
            }, each: { r in
                n += 1
                let t = Float(n) / 60
                if t < 1.5 { drive(r, n: n) { t in (t + 1, flinchEvery(t)) } }
                else {
                    r.brain.storm.clear()
                    if n == 90 { r.brain.commandedIdle = .shake }
                    if n == 90 + 60 * 4 { r.brain.request(.goTo(SIMD2(-1.4, 0.6))) }
                }
            })
        case "scatter":          // flinch standing then walk off, no hurry
            return SC(name: "storm: scatter", game: true, seconds: 6, setup: { r, _ in n = 0; r.brain.request(.goTo(SIMD2(-1.6, 0.2))); return true },
                      each: { r in n += 1; if n < 90 { drive(r, n: n) { t in (1, flinchEvery(t)) } } else { r.brain.storm.clear() } })
        default: fatalError(name)
        }
    }

    @discardableResult
    func storm(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        var report = String(format: "STORM %@\nchar shoes | frames | leash frames | airborne frames | min ring ratio | worst join (cm; need >= 1) | max collar (cm; need <= 2) | max tilt (rad; need <= 0.5)\n", name)
        for c in 0..<OnePieceInvariantTests.characters.count {
            for shoes in [false, true] {
                var air = 0, badFrame = -1, badInfo = "", tiltMax: Float = 0, leashFrame = -1
                var worst: (ratio: Float, join: Float, collar: Float) = (.infinity, .infinity, 0)
                let a = OnePieceInvariantTests.run(Self.scenario(name), char: c, shoes: shoes, pacing: .hz60, seed: 3) { frame, r, f in
                    tiltMax = max(tiltMax, f.tilt)
                    if leashFrame < 0, f.beans, f.leash > 0.002 || f.weldPull > 0.002 { leashFrame = frame }
                    guard let s = EmoteFeetTests.sample(r, frame: frame) else { return }
                    air += 1
                    if (s.ratio < EmoteFeetTests.minRatio || s.join < OnePieceInvariantTests.minNeck || s.collar > EmoteFeetTests.maxCollar) && badFrame < 0 { badFrame = frame; badInfo = s.info }
                    worst = (min(worst.ratio, s.ratio), min(worst.join, s.join), max(worst.collar, s.collar))
                }
                let who = "storm \(name), \(OnePieceInvariantTests.characters[c].0) \(shoes ? "with shoes" : "bare")"
                guard a.started else { XCTFail("\(who): did not start", file: file, line: line); continue }
                report += String(format: "%@ %@ | %d | %d | %d | %.2f | %.1f | %.1f | %.3f\n", OnePieceInvariantTests.characters[c].0, shoes ? "shoes" : "bare", a.frames, a.leashed, air, worst.ratio, worst.join * 100, worst.collar * 100, tiltMax)
                XCTAssertEqual(a.leashed, 0, "\(who): the leash / tether moved a foot piece in \(a.leashed) frames, first at frame \(leashFrame), max pull \(String(format: "%.1f", a.leashMax * 100)) cm", file: file, line: line)
                XCTAssertEqual(a.detached, 0, "\(who): a foot came off the body in \(a.detached) frames (worst leg sdf \(a.worstLeg))", file: file, line: line)
                XCTAssertEqual(a.neckBad, 0, "\(who): the neck join is open in \(a.neckBad) frames", file: file, line: line)
                XCTAssertLessThanOrEqual(tiltMax, 0.5, "\(who): the body tipped \(tiltMax) rad (limit 0.5)", file: file, line: line)
                if air > 0 {
                    XCTAssertGreaterThanOrEqual(worst.ratio, EmoteFeetTests.minRatio, "\(who): the neck ring shrank to \(String(format: "%.0f", worst.ratio * 100)) % of standing (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                    XCTAssertGreaterThanOrEqual(worst.join, OnePieceInvariantTests.minNeck, "\(who): the join is open: \(String(format: "%.1f", -worst.join * 100)) cm outside the body (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                    XCTAssertLessThanOrEqual(worst.collar, EmoteFeetTests.maxCollar, "\(who): the collar moved the skin \(String(format: "%.1f", worst.collar * 100)) cm (first bad frame \(badFrame): \(badInfo))", file: file, line: line)
                }
            }
        }
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? report.write(toFile: Self.out + "feet_storm_\(name.replacingOccurrences(of: " ", with: "_")).txt", atomically: true, encoding: .utf8)
        return true
    }

    func testTremble() { storm("tremble") }
    func testStartleHopWithFlinch() { storm("flinch hop") }
    func testScurry() { storm("scurry") }
    func testShakeOffAndScatter() { storm("shake") }
    func testScatterWalk() { storm("scatter") }

    /// The channel itself never leaves the pose past the tilt limit, with the extremes of every term at once.
    func testChannelExtremes() {
        let worst = StormPose.huddle(t: 0.027, standing: 9, phase: 0, flinch: StormTuning.flinchRise, amplitude: 1)
        XCTAssertLessThan(abs(worst.pitch) + abs(worst.roll), 0.2)
        XCTAssertGreaterThan(worst.squash, 0.8)
    }
}
