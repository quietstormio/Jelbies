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
    override func tearDown() { BubbleTuning.seedRandom(nil); BubbleTuning.restoreHead(); wand.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    static let seconds = 60
    static let seeds = 6
    /// (name, feature) of the species used in the casts (OnePieceInvariantTests.characters).
    static let species: [String: JellyFeature] = ["Bob": .none, "Pip": .spines, "Lavender": .wings, "Teddy": .ears]
    static let casts: [[String]] = [["Bob"], ["Pip", "Lavender"], ["Pip", "Lavender", "Teddy"]]

    struct Hop { var start: Float; var end: Float; var travel: Float; var apex: Float; var cause: String; var jelly = 0 }
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
        wand.resetForTests(); BubbleTuning.forceMove = nil; BubbleTuning.seedRandom(UInt64(seed + 1))
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
                        let h = Hop(start: tr[i].t0, end: t, travel: tr[i].maxTravel, apex: tr[i].apex, cause: tr[i].cause, jelly: i)
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

    /// One cast under one configuration: `seeds` runs of `seconds` sim-seconds (the wand's dice and the brains' seeds are fixed by the seed: a rerun gives the same numbers).
    struct Cast { var tag: String; var agg: Agg; var perSeed: [Float]; var lockstep: Float }
    func measureAll() -> [Cast] {
        var out: [Cast] = []
        let setups: [(String, [String], Bool)] = Self.casts.map { ("room " + $0.joined(separator: "+"), $0, false) } + [("park Pip+Lavender+Teddy(free)", ["Pip", "Lavender", "Teddy"], true)]
        for (tag, cast, park) in setups {
            var rs: [Result] = []
            for seed in 0..<Self.seeds { rs.append(run(cast: cast, seed: seed, park: park, free: park ? [2] : [])) }
            // lockstep: the share of take-offs that have another Jelbie's take-off within 0.1 s
            let hops = rs.map(\.hops)
            var near = 0, all = 0
            for h in hops { for a in h { all += 1; if h.contains(where: { $0.jelly != a.jelly && abs($0.start - a.start) < 0.1 }) { near += 1 } } }
            out.append(Cast(tag: tag, agg: aggregate(rs), perSeed: rs.map { Float($0.hops.count) / $0.minutes }, lockstep: cast.count > 1 ? Float(near) / Float(max(all, 1)) : 0))
        }
        return out
    }
    func report(_ title: String, _ cs: [Cast]) {
        for c in cs {
            print("BUBBLEJUMP \(title) | " + line(c.tag, c.agg) + String(format: " | per-seed hops/min min %.1f max %.1f | lockstep share %.0f%%", c.perSeed.min() ?? 0, c.perSeed.max() ?? 0, 100 * c.lockstep))
        }
    }
    static let styles: [BubblePopMove] = [.bounce, .header, .leap, .skip, .flap]

    /// Run ONCE with the BEFORE numbers (BubbleTuning.applyBaseline: the classic path, the old weights / shares / radii) to (re)measure the constants below.
    func testBaselineRates() {
        BubbleTuning.applyBaseline()
        let cs = measureAll()
        report("BASELINE", cs)
        var consts = "BUBBLEJUMP BASELINE CONSTANTS\nstatic let baseHops: [Float] = [\(cs.map { String(format: "%.2f", $0.agg.hopsPerMin) }.joined(separator: ", "))]\nstatic let baseApexMax: Float = \(String(format: "%.3f", cs.map(\.agg.apexMax).max() ?? 0))\nstatic let baseStyle: [[String: Float]] = [\n"
        for c in cs { consts += "    [" + Self.styles.map { "\"\($0.rawValue)\": " + String(format: "%.2f", c.agg.movePerMin[$0] ?? 0) }.joined(separator: ", ") + "],\n" }
        print(consts + "]")
    }

    /// This round's tuning at energy 1.0 and 1.25: the floors on the mean hop rate, every pop style at >= 90 % of its BEFORE rate (mean over the seeds of a cast), and the limits.
    func testJumpRates() {
        for energy: Float in [1.0, 1.25] {
            BubbleTuning.restoreHead(); BubbleTuning.playEnergy = energy
            let cs = measureAll()
            report(String(format: "HEAD energy %.2f", energy), cs)
            for (k, c) in cs.enumerated() {
                let a = c.agg, tag = String(format: "%@ @%.2f", c.tag, energy)
                XCTAssertEqual(a.dup, 0, "\(tag): two Jelbies on the same bubble"); XCTAssertEqual(a.outside, 0, "\(tag): a Jelbie left the play area")
                XCTAssertGreaterThanOrEqual(a.hopsPerMin, Self.floor[k] * Self.baseHops[k], "\(tag): hop starts per Jelbie-minute \(a.hopsPerMin) vs baseline \(Self.baseHops[k]) x \(Self.floor[k])")
                XCTAssertLessThanOrEqual(a.apexMax, Self.baseApexMax * 1.05, "\(tag): highest apex \(a.apexMax) above the baseline max")
                XCTAssertLessThanOrEqual(a.maxTravel, 0.8, "\(tag): a single hop travelled \(a.maxTravel) m (\(a.longest))")
                XCTAssertLessThanOrEqual(a.airMax, 0.45, "\(tag): a Jelbie was airborne \(a.airMax) of the time")
                XCTAssertGreaterThanOrEqual(a.minGroundSeq, 0.35, "\(tag): ground time between two hops of one Jelbie")
                XCTAssertLessThanOrEqual(c.lockstep, Self.maxLockstep, "\(tag): \(c.lockstep) of the take-offs have another Jelbie's within 0.1 s")
                for m in Self.styles {
                    let base = Self.baseStyle[k][m.rawValue] ?? 0
                    XCTAssertGreaterThanOrEqual(a.movePerMin[m] ?? 0, 0.9 * base, "\(tag): \(m.rawValue) pops per Jelbie-minute \(a.movePerMin[m] ?? 0) vs baseline \(base)")
                }
            }
        }
    }
    /// The asserted floors on the mean hop rate against the BEFORE rate: solo, pair, trio, park.
    static let floor: [Float] = [1.45, 1.45, 1.40, 1.30]
    /// Take-offs of different Jelbies within 0.1 s of each other: chance alone gives ~10 % at these rates; more than this is lockstep.
    static let maxLockstep: Float = 0.25
    // BASELINE: filled in from testBaselineRates (BubbleTuning.applyBaseline, 6 seeds x 60 sim-s per cast, the wand's dice seeded).
    static let baseHops: [Float] = [0, 0, 0, 0]
    static let baseApexMax: Float = 9
    static let baseStyle: [[String: Float]] = [[:], [:], [:], [:]]
}
