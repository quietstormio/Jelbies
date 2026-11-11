//
//  BubbleJumpRateTests.swift
//  How much the Jelbies JUMP in bubble-wand play ("make the Jelbies jump a lot more when playing with bubble wand", 2026-11-11). Casts of 1, 2 and 3 Jelbies of different species, a steady
//  blow for 60 sim-seconds, per run one line: hop starts per Jelbie-minute (every take-off of the body: any pop move, the leash's hop on the spot, ...), by what he was doing at take-off,
//  pops per minute by kind, apex (crown rise) median / max, the longest horizontal travel of one hop, airborne share, the shortest ground time between two hops of one Jelbie,
//  haptic transients requested by pops and the jump / pop / chirp sounds PLAYED past every guard.
//  A "hop" is one airborne episode of the whole body (lowest sim particle above its standing height); a skip or a bounce counts every touch-down.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubbleJumpRateTests: XCTestCase {
    var wand: BubbleWand { BubbleWand.shared }
    override func setUp() { super.setUp(); wand.resetForTests(); EmoteFeetTests.reset(); BubbleTuning.restoreHead() }
    override func tearDown() { BubbleTuning.restoreHead(); wand.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    static let seconds = 60
    /// (name, feature) of the species used in the casts (OnePieceInvariantTests.characters).
    static let species: [String: JellyFeature] = ["Bob": .none, "Pip": .spines, "Lavender": .wings, "Teddy": .ears]
    static let casts: [[String]] = [["Bob"], ["Pip", "Lavender"], ["Pip", "Lavender", "Teddy"]]

    struct Hop { var start: Float; var end: Float; var travel: Float; var apex: Float; var cause: String }
    struct Result {
        var minutes: Float = 0                       // Jelbie-minutes
        var hops: [Hop] = []
        var causes: [String: Int] = [:]
        var airborne: [Float] = []                   // share of time per Jelbie
        var minGround: Float = .infinity             // shortest ground time between two hops of one Jelbie
        var minGroundSeq: Float = .infinity          // the same, ignoring the touch-downs inside one move (< 0.35 s are the move's own)
        var movePops: [BubblePopMove: Int] = [:]
        var hopPops = 0, contactPops = 0, quiet = 0, totalPops = 0, chases = 0
        var played: [String: Int] = [:]
        var dup = 0, outside = 0
        var longest: Hop?
    }

    func run(cast: [String], seed: Int, park: Bool, free: Set<Int> = [], size: CGSize = CGSize(width: 440, height: 956)) -> Result {
        wand.resetForTests(); BubbleTuning.forceMove = nil
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        if park { GameCamera.configurePark() } else { GameCamera.configureRoom(count: 3, option: .A, wide: 2) }
        _ = GameCamera.camera(aspect: Float(size.width / size.height))
        defer { if park { GameCamera.endPark(count: 3) } }
        let allSpots: [[SIMD2<Float>]] = [[SIMD2(0, 1.0)], [SIMD2(-1.2, 0.5), SIMD2(1.2, 0.5)], [SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)]]
        let spots = allSpots[cast.count - 1]
        var keep: [MotionRig] = []
        let rs: [MotionRig] = cast.enumerated().map { i, name in
            let r = MotionRig(game: true, settle: 0.5)
            let f = Self.species[name] ?? .none
            r.brain.feature = f
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = f == .spines; r.brain.skinnerRef = r.skinner
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = UInt64(seed * 31 + i * 7 + 5)
            r.sim.teleport(toXZ: spots[i]); r.run(0.3)
            keep.append(r)
            return r
        }
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        BubblePlayTests.clockBase += 1000; var now = BubblePlayTests.clockBase; AudioHub.clock = { now }
        var res = Result()
        AudioHub.dropTap = { what, why in if why == nil { res.played[what, default: 0] += 1 } }
        defer { AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() } }
        wand.viewSize = size
        wand.activate(care: nil)
        wand.demo = { _ in 0.7 }
        let js = rs.enumerated().map { BubbleJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, free: free.contains($0.offset)) }
        // per Jelbie hop tracker
        struct Track { var base: Float = 0, crown0: Float = 0, air = false, t0: Float = 0, xz0 = SIMD2<Float>(0, 0), apex: Float = 0, cause = "", landedAt: Float = -9, everHopped = false, airTime: Float = 0, maxTravel: Float = 0 }
        var tr: [Track] = rs.map { r in var t = Track(); t.base = r.sim.minY(); t.crown0 = r.sim.centroid().y + BobShape.H * 0.5; return t }
        let up: Float = 0.04, down: Float = 0.015
        var steps = 0
        for _ in 0..<(60 * Self.seconds) {
            for r in rs { r.tick() }
            wand.tick(jellies: js, dt: 1.0 / 60)
            now += 1.0 / 60; steps += 1
            let t = Float(steps) / 60
            for (i, r) in rs.enumerated() {
                let lift = r.sim.minY() - tr[i].base
                let c = r.sim.centroid()
                let crown = c.y + BobShape.H * 0.5 - tr[i].crown0
                if !tr[i].air {
                    if lift > up {
                        tr[i].air = true; tr[i].t0 = t; tr[i].xz0 = SIMD2(c.x, c.z); tr[i].apex = crown; tr[i].maxTravel = 0
                        let k = r.brain.idleState.kind.map { $0.rawValue } ?? "-"
                        tr[i].cause = "\(k)/\(r.brain.scriptKindName)"
                        if tr[i].everHopped { let g = t - tr[i].landedAt; res.minGround = min(res.minGround, g); if g >= 0.35 { res.minGroundSeq = min(res.minGroundSeq, g) } }
                        tr[i].everHopped = true
                    }
                } else {
                    tr[i].apex = max(tr[i].apex, crown)
                    tr[i].maxTravel = max(tr[i].maxTravel, simd_distance(SIMD2(c.x, c.z), tr[i].xz0))
                    if lift < down {
                        tr[i].air = false; tr[i].landedAt = t; tr[i].airTime += t - tr[i].t0
                        let h = Hop(start: tr[i].t0, end: t, travel: tr[i].maxTravel, apex: tr[i].apex, cause: tr[i].cause)
                        res.hops.append(h); res.causes[h.cause, default: 0] += 1
                        if h.travel > (res.longest?.travel ?? -1) { res.longest = h }
                    }
                }
            }
            let tg = wand.activeTargets
            if Set(tg).count != tg.count { res.dup += 1 }
            if steps > 60 * 4 { for r in rs where !(r.brain.bubbleLeash?.contains(r.brain.position, margin: 1.2) ?? true) { res.outside += 1 } }
        }
        let secs = Float(steps) / 60
        res.minutes = Float(cast.count) * secs / 60
        res.airborne = tr.map { $0.airTime / secs }
        res.movePops = wand.movePops; res.hopPops = wand.hopPops; res.contactPops = wand.contactPops; res.chases = wand.chaseRecords.count
        res.totalPops = wand.popsByJelly.values.reduce(0, +); res.quiet = wand.field.popped - res.totalPops
        let totalMode = max(wand.modeSeconds.values.reduce(0, +), 1)
        print("BUBBLEJUMP DIAG \(park ? "park" : "room") \(cast.joined(separator: "+")) seed \(seed): time share by mode \(wand.modeSeconds.sorted { $0.key < $1.key }.map { String(format: "%@=%.0f%%", $0.key, 100 * $0.value / totalMode) }.joined(separator: " ")) | wait hops \(wand.waitHops) | chases \(wand.chaseRecords.count) ended in a pop \(wand.chaseRecords.filter(\.popped).count) | diag \(wand.diag.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        wand.deactivate()
        keep.removeAll()
        return res
    }

    func median(_ a: [Float]) -> Float { a.isEmpty ? 0 : a.sorted()[a.count / 2] }

    /// The aggregate of several runs of one cast, printed as one line.
    struct Agg {
        var hopsPerMin: Float, apexMed: Float, apexMax: Float, maxTravel: Float, airMax: Float, airMean: Float, minGround: Float, minGroundSeq: Float
        var popsPerMin: Float, movePerMin: [BubblePopMove: Float], contactPerMin: Float, quietPerMin: Float, hapticPerMin: Float
        var causes: [String: Float], jumpPlays: Float, popPlays: Float, voicePlays: Float, dup: Int, outside: Int, longest: String
    }
    func aggregate(_ rs: [Result]) -> Agg {
        let mins = rs.reduce(0) { $0 + $1.minutes }
        let hops = rs.flatMap(\.hops)
        var move: [BubblePopMove: Float] = [:]
        for r in rs { for (m, n) in r.movePops { move[m, default: 0] += Float(n) / mins } }
        var causes: [String: Float] = [:]
        for r in rs { for (k, n) in r.causes { causes[k, default: 0] += Float(n) / mins } }
        var played: [String: Int] = [:]
        for r in rs { for (k, n) in r.played { played[k, default: 0] += n } }
        let voices = played.filter { $0.key.contains("chirp") || $0.key.contains("giggle") || $0.key.contains("babble") }.values.reduce(0, +)
        let air = rs.flatMap(\.airborne)
        let lg = rs.compactMap(\.longest).max { $0.travel < $1.travel }
        // hop-start rate counts every take-off (a skip is two, a bounce up to three); the ground gap includes those touch-downs
        return Agg(hopsPerMin: Float(hops.count) / mins, apexMed: median(hops.map(\.apex)), apexMax: hops.map(\.apex).max() ?? 0, maxTravel: hops.map(\.travel).max() ?? 0,
                   airMax: air.max() ?? 0, airMean: air.reduce(0, +) / Float(max(air.count, 1)), minGround: rs.map(\.minGround).min() ?? 0, minGroundSeq: rs.map(\.minGroundSeq).min() ?? 0,
                   popsPerMin: Float(rs.reduce(0) { $0 + $1.totalPops }) / mins, movePerMin: move, contactPerMin: Float(rs.reduce(0) { $0 + $1.contactPops }) / mins,
                   quietPerMin: Float(rs.reduce(0) { $0 + $1.quiet }) / mins, hapticPerMin: Float(rs.reduce(0) { $0 + $1.hopPops }) / mins,
                   causes: causes, jumpPlays: Float(played["play:jump"] ?? 0) / mins, popPlays: Float(played["play:bubblewand_pop"] ?? 0) / mins, voicePlays: Float(voices) / mins,
                   dup: rs.reduce(0) { $0 + $1.dup }, outside: rs.reduce(0) { $0 + $1.outside }, longest: lg.map { String(format: "%.2f m at t=%.1f by %@", $0.travel, $0.start, $0.cause) } ?? "-")
    }
    func line(_ tag: String, _ a: Agg) -> String {
        let mv = a.movePerMin.sorted { $0.key.rawValue < $1.key.rawValue }.map { String(format: "%@=%.2f", $0.key.rawValue, $0.value) }.joined(separator: " ")
        let cs = a.causes.sorted { $0.value > $1.value }.map { String(format: "%@=%.2f", $0.key, $0.value) }.joined(separator: " ")
        return String(format: "BUBBLEJUMP %@ | hops/Jelbie-min %.2f | pops/min %.2f (%@; contact %.2f; quiet %.2f) | apex median %.3f max %.3f | longest hop travel %.2f m (%@) | airborne share mean %.0f%% max %.0f%% | min ground %.2f s (move touch-downs incl.), min ground between moves %.2f s | haptic transients requested/min %.2f | plays/min jump %.1f pop %.1f voices %.1f | dup %d outside %d | causes/min: %@",
                      tag, a.hopsPerMin, a.popsPerMin, mv, a.contactPerMin, a.quietPerMin, a.apexMed, a.apexMax, a.maxTravel, a.longest, 100 * a.airMean, 100 * a.airMax, a.minGround, a.minGroundSeq, a.hapticPerMin, a.jumpPlays, a.popPlays, a.voicePlays, a.dup, a.outside, cs)
    }

    /// Prints the numbers for every cast (room, 2 seeds each) and one park run; asserts the targets once the baseline constants below are filled in.
    func testJumpRates() {
        var all: [(String, Agg)] = []
        for cast in Self.casts {
            var rs: [Result] = []
            for seed in 0..<2 {
                let r = run(cast: cast, seed: seed, park: false)
                print("BUBBLEJUMP RUN room \(cast.joined(separator: "+")) seed \(seed): hops \(r.hops.count) in \(String(format: "%.1f", r.minutes)) Jelbie-min")
                rs.append(r)
            }
            all.append(("room \(cast.joined(separator: "+"))", aggregate(rs)))
        }
        let pr = run(cast: ["Pip", "Lavender", "Teddy"], seed: 0, park: true, free: [2])
        all.append(("park Pip+Lavender+Teddy(free)", aggregate([pr])))
        for (tag, a) in all { print(line(tag, a)) }
        for (_, a) in all { XCTAssertEqual(a.dup, 0, "two Jelbies on the same bubble"); XCTAssertEqual(a.outside, 0, "a Jelbie left the play area") }
        // the targets, against the BASELINE measured on launch-next 23c8c7f2 (the untouched code, this same test, 2 seeds per room cast, 1 park run)
        for (k, (tag, a)) in all.enumerated() {
            XCTAssertGreaterThanOrEqual(a.hopsPerMin, 2.0 * Self.baseHops[k], "\(tag): hop starts per Jelbie-minute \(a.hopsPerMin) vs baseline \(Self.baseHops[k])")
            XCTAssertLessThanOrEqual(a.apexMax, Self.baseApexMax * 1.05, "\(tag): highest apex \(a.apexMax) above the baseline max")
            XCTAssertLessThanOrEqual(a.maxTravel, 0.8, "\(tag): a single hop travelled \(a.maxTravel) m (\(a.longest))")
            XCTAssertLessThanOrEqual(a.airMax, 0.45, "\(tag): a Jelbie was airborne \(a.airMax) of the time")
            XCTAssertGreaterThanOrEqual(a.minGroundSeq, 0.35, "\(tag): ground time between two hops of one Jelbie")
        }
        // the other pop styles keep at least 90 % of their baseline rate (per Jelbie-minute over the three room casts)
        var rate: [BubblePopMove: Float] = [:]
        for (k, (_, a)) in all.prefix(3).enumerated() { for (m, v) in a.movePerMin { rate[m, default: 0] += v * Self.jelbieMinutes[k] / 12 } }
        print("BUBBLEJUMP pops per Jelbie-minute over the room casts: \(rate.sorted { $0.key.rawValue < $1.key.rawValue }.map { String(format: "%@=%.2f", $0.key.rawValue, $0.value) }.joined(separator: " ")) (baseline \(Self.basePopRate.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")))")
        XCTAssertGreaterThanOrEqual(rate[.header] ?? 0, 0.9 * Self.basePopRate["header"]!, "header pops per Jelbie-minute")
        XCTAssertGreaterThanOrEqual(rate[.leap] ?? 0, 0.9 * Self.basePopRate["leap"]!, "leap pops per Jelbie-minute")
        XCTAssertGreaterThanOrEqual(rate[.bounce] ?? 0, 0.9 * Self.basePopRate["bounce"]!, "bounce pops per Jelbie-minute")
        XCTAssertGreaterThanOrEqual((rate[.skip] ?? 0) + (rate[.flap] ?? 0), 0.9 * Self.basePopRate["skip+flap"]!, "skip + flap pops per Jelbie-minute")
    }
    /// Baseline pops per Jelbie-minute over the three room casts (12 Jelbie-minutes: bounce 23, header 37, leap 49, skip 3, flap 4 pops).
    static let basePopRate: [String: Float] = ["bounce": 1.92, "header": 3.08, "leap": 4.08, "skip+flap": 0.58]
    /// Baseline (launch-next 23c8c7f2): hop starts per Jelbie-minute for Bob / Pip+Lavender / Pip+Lavender+Teddy in the room, and the park run; the highest crown rise (the flap, 0.350).
    static let baseHops: [Float] = [18.00, 15.75, 11.17, 7.67]
    static let baseApexMax: Float = 0.350
    static let jelbieMinutes: [Float] = [2, 4, 6, 3]
}
