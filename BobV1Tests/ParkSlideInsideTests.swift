//
//  ParkSlideInsideTests.swift
//  park-slide-r3 ("They're still walking in slide", 2026-11-16): five autonomous bodies in the park, portrait, wired like the real stage (SocialTests.Lab: keepApart under the
//  floor rules, makeRoom), no seesaw (the owner's park). Counts every sample where a body is inside the slide's box while he is NOT using the slide from the steps on:
//  `deep` = his centre inside the box, `overlap` = his footprint over the box's edge by more than 5 cm (the floor rule's own measure, `decorExitCheck`), per tag (what he is doing:
//  `ParkSlideProbe.doing`), and the park's activity starts (slide rides, hopscotch, socials, idles) for the "add, never displace" check. PSI lines.
//  Three runs: as the game plays (autonomy), DENSE (every free body is sent to the slide every 0.5 s, autonomy left on: many ride exits next to friends), SOCIAL (the social
//  cooldowns forced short every second: the park with more socials, branch social-more-r1).
//

import XCTest
import simd
@testable import BobV1

extension ParkSlideRoundTests {
    struct InsideRun {
        var samples = 0, overlap = 0, deep = 0, episodes = 0
        var byTag: [String: Int] = [:], deepTag: [String: Int] = [:], notes: [String] = []
        var rides = 0, hops = 0, socials: [String: Int] = [:], idles: [String: Int] = [:]
        var closePairs = 0, closeTags: [String: Int] = [:]
        var deepNotes: [String] = [], closeNotes: [String] = []
        /// Pairs closer than 0.9 with one of the two near the slide's landing (within peerGap + 0.5): the bunching at the chute's end. The foot rule's turn-aways (r4).
        var landingClose = 0, turnAways = 0
        mutating func merge(_ o: InsideRun) {
            samples += o.samples; overlap += o.overlap; deep += o.deep; episodes += o.episodes; rides += o.rides; hops += o.hops; closePairs += o.closePairs
            landingClose += o.landingClose; turnAways += o.turnAways
            for (k, v) in o.byTag { byTag[k, default: 0] += v }; for (k, v) in o.deepTag { deepTag[k, default: 0] += v }
            for (k, v) in o.socials { socials[k, default: 0] += v }; for (k, v) in o.idles { idles[k, default: 0] += v }; for (k, v) in o.closeTags { closeTags[k, default: 0] += v }
            notes += o.notes; deepNotes += o.deepNotes; closeNotes += o.closeNotes
        }
    }
    /// The walk's target (or "-") for the notes.
    static func walkTarget(_ b: BlobBrain) -> String { if case .walk(let t, _) = b.script { return String(format: "(%.2f,%.2f)", t.x, t.y) }; return "-" }
    enum InsideMode { case plain, dense, social }

    static let insideStarts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(-1.2, 2.2), SIMD2(1.0, 2.9)]

    func insideRun(seeds: [UInt64], seconds: Float, mode: InsideMode = .plain, level: Int = 2) -> InsideRun {
        var out = InsideRun()
        let seesaw = ParkPlayTuning.seesawInPark, budget = BlobBrain.pickBudgetSeconds
        ParkPlayTuning.seesawInPark = false          // (the owner's park: no seesaw since park-play-r1; XCTest places it for the seesaw's own suites)
        BlobBrain.pickBudgetSeconds = .infinity          // (repeatable picks: the wall-clock budget would time out at random on a loaded host)
        BlobBrain.slideFixLevel = level          // (0 = main's rules: the before arm; 1 = park-slide-r3; 2 = park-slide-r4)
        let turn0 = BlobBrain.slideFootTurnAways
        defer { ParkPlayTuning.seesawInPark = seesaw; BlobBrain.pickBudgetSeconds = budget; BlobBrain.slideFixLevel = 2 }
        for seed in seeds {
            let lab = parkLab(n: 5, seed: seed, aspect: Self.portrait, starts: Self.insideStarts, quiet: false)
            // the owner's park: Lavender (wings), Moss (daisy), Panda (ears), the visitors Bubbles (yellow: spines) and Freckles (lavender: wings); set as ParkPlayTests' soak sets them
            for (k, r) in lab.rigs.enumerated() {
                r.brain.feature = JellyRoster.feature([3, 2, JellyRoster.pandaID, 1, 3][k])
                r.skinner.autoBlink = false; r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            }
            let sf = DecorField.shared.foot(ParkToys.slideUID)!
            let landing = lab.rigs[0].brain.slideLanding(sf)
            let n = lab.rigs.count
            var inNow = [Bool](repeating: false, count: n), hist = [[String]](repeating: [], count: n), last = [String](repeating: "", count: n)
            var lastSocial = [ObjectIdentifier?](repeating: nil, count: n), lastIdle = [IdleKind?](repeating: nil, count: n), lastStage = [Int](repeating: 0, count: n)
            var closeNow = Set<Int>(), deepNow = [Bool](repeating: false, count: n)
            var t: Float = 0
            for i in 0..<Int(seconds * 60) {
                if mode == .dense, i % 30 == 5 {
                    for r in lab.rigs where r.brain.idleState.kind == nil && !r.brain.isSocial && r.brain.pending == nil { _ = r.brain.startCommandedDecor(.decorSlide, only: .slide, r.sim, r.skinner) }
                }
                if mode == .social, i % 60 == 7 {
                    for r in lab.rigs {
                        let b = r.brain
                        b.socialBook.cooldown = min(b.socialBook.cooldown, 1); b.socialBook.groupCool = min(b.socialBook.groupCool, 2)
                        for k in Array(b.socialBook.pair.keys) { b.socialBook.pair[k] = min(b.socialBook.pair[k]!, 1) }
                    }
                }
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
                for (k, r) in lab.rigs.enumerated() {
                    let b = r.brain
                    let st = ParkSlideProbe.doing(b)
                    if st != last[k] { last[k] = st; hist[k].append(String(format: "%.1f[%@]@(%.2f,%.2f)", t, st, b.position.x, b.position.y)); if hist[k].count > 6 { hist[k].removeFirst() } }
                    // activity starts
                    if let s = b.social { let id = ObjectIdentifier(s); if lastSocial[k] != id { lastSocial[k] = id; out.socials[s.kind.rawValue, default: 0] += 1 } } else { lastSocial[k] = nil }
                    if b.idleState.kind != lastIdle[k] { lastIdle[k] = b.idleState.kind; if let i = b.idleState.kind { out.idles["\(i)", default: 0] += 1; if i == .decorHopscotch { out.hops += 1 } } }
                    let stage = b.idleState.kind == .decorSlide ? b.idleState.slideStage : 0
                    if stage == 5, lastStage[k] != 5 { out.rides += 1 }
                    lastStage[k] = stage
                    // the box
                    let fl = GameCare.floorPos(b, r.sim)
                    let d = min(sf.distance(fl), sf.distance(b.position))
                    let riding = b.idleState.kind == .decorSlide && b.idleState.decorUID == ParkToys.slideUID && b.idleState.slideStage >= 1
                    out.samples += 1
                    if d < b.footprint * sf.spec.reach - 0.05, !riding {
                        out.overlap += 1
                        out.byTag[st, default: 0] += 1
                        if d < 0 {
                            out.deep += 1; out.deepTag[st, default: 0] += 1
                            if !deepNow[k] {
                                deepNow[k] = true
                                if out.deepNotes.count < 24 { out.deepNotes.append(String(format: "seed %d t%.1f body %d d %.2f at (%.2f,%.2f) target %@ insideT %.2f [%@] hist %@", Int(seed), t, k, d, fl.x, fl.y, Self.walkTarget(b), b.insideDecorT, st, hist[k].joined(separator: " > "))) }
                            }
                        } else { deepNow[k] = false }
                        if !inNow[k] {
                            inNow[k] = true; out.episodes += 1
                            if out.notes.count < 40 { out.notes.append(String(format: "seed %d t%.1f body %d d %.2f at (%.2f,%.2f) [%@] hist %@", Int(seed), t, k, d, fl.x, fl.y, st, hist[k].joined(separator: " > "))) }
                        }
                    } else { inNow[k] = false; deepNow[k] = false }
                }
                // two bodies' roots closer than 0.9 (the circle spring holds 1.09; a touching emote's skins meet at ~0.95), not in one session together
                for i in 0..<n { for j in (i + 1)..<n {
                    let bi = lab.rigs[i].brain, bj = lab.rigs[j].brain
                    let same = bi.social != nil && bi.social === bj.social
                    let dist = simd_distance(GameCare.floorPos(bi, lab.rigs[i].sim), GameCare.floorPos(bj, lab.rigs[j].sim))
                    let key = i * 8 + j
                    if dist < 0.9, !same {
                        out.closePairs += 1
                        let pi0 = GameCare.floorPos(bi, lab.rigs[i].sim), pj0 = GameCare.floorPos(bj, lab.rigs[j].sim)
                        if min(simd_distance(pi0, landing), simd_distance(pj0, landing)) < MelonController.jellyGap + 0.5 { out.landingClose += 1 }
                        let tag = [ParkSlideProbe.doing(bi), ParkSlideProbe.doing(bj)].sorted().joined(separator: " x ")
                        out.closeTags[tag, default: 0] += 1
                        if !closeNow.contains(key) {
                            closeNow.insert(key)
                            if out.closeNotes.count < 24 {
                                let pi = GameCare.floorPos(bi, lab.rigs[i].sim), pj = GameCare.floorPos(bj, lab.rigs[j].sim)
                                out.closeNotes.append(String(format: "seed %d t%.1f %d-%d dist %.2f at (%.2f,%.2f)/(%.2f,%.2f) box %.2f/%.2f targets %@/%@ [%@] histI %@ histJ %@", Int(seed), t, i, j, dist, pi.x, pi.y, pj.x, pj.y, sf.distance(pi), sf.distance(pj), Self.walkTarget(bi), Self.walkTarget(bj), tag, hist[i].suffix(3).joined(separator: " > "), hist[j].suffix(3).joined(separator: " > ")))
                            }
                        }
                    } else { closeNow.remove(key) }
                } }
            }
            for r in lab.rigs { r.brain.abortAll(r.sim, r.skinner) }
        }
        out.turnAways = BlobBrain.slideFootTurnAways - turn0
        return out
    }

    func insideReport(_ name: String, _ r: InsideRun, wall: TimeInterval) {
        for nt in r.notes { print("PSI \(name) note \(nt)") }
        for nt in r.deepNotes { print("PSI \(name) DEEP \(nt)") }
        for nt in r.closeNotes { print("PSI \(name) CLOSE \(nt)") }
        for (k, v) in r.byTag.sorted(by: { $0.value > $1.value }) { print("PSI \(name) overlap \(v) deep \(r.deepTag[k] ?? 0) samples [\(k)]") }
        for (k, v) in r.closeTags.sorted(by: { $0.value > $1.value }).prefix(12) { print("PSI \(name) close \(v) samples [\(k)]") }
        print("PSI \(name) rates rides \(r.rides) hopscotch \(r.hops) socials \(r.socials.values.reduce(0, +)) [\(r.socials.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))]")
        print("PSI \(name) idles [\(r.idles.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))]")
        print("PSI \(name) total samples \(r.samples) overlap \(r.overlap) deep \(r.deep) episodes \(r.episodes) closePairs \(r.closePairs) landingClose \(r.landingClose) footTurnAways \(r.turnAways) wall \(Int(wall)) s")
    }

    /// Both arms on the same seeds, seed by seed: `fix` false (main's rule) then true (park-slide-r3/r4). The after arm: no centre inside the box; the socials (the park's "more play
    /// together") at 0.9x of the before arm or more, as the MEAN of the per-seed ratios (one seed alone diverges: the two arms' runs part ways at the first different step).
    func insideBothArms(_ name: String, seeds: [UInt64], seconds: Float, mode: InsideMode, level: Int = 2, meanCheck: Bool = true) -> (before: InsideRun, after: InsideRun, ratios: [UInt64: Float]) {
        var b = InsideRun(), a = InsideRun()
        var ratios: [Float] = [], bySeed: [UInt64: Float] = [:]
        let t0 = Date()
        for seed in seeds {
            let bs = insideRun(seeds: [seed], seconds: seconds, mode: mode, level: 0), as1 = insideRun(seeds: [seed], seconds: seconds, mode: mode, level: level)
            let sb = bs.socials.values.reduce(0, +), sa = as1.socials.values.reduce(0, +)
            if sb >= 5 { ratios.append(Float(sa) / Float(sb)); bySeed[seed] = Float(sa) / Float(sb) }
            print("PSI \(name) seed \(seed): before deep \(bs.deep) overlap \(bs.overlap) close \(bs.closePairs) landingClose \(bs.landingClose) rides \(bs.rides) hopscotch \(bs.hops) socials \(sb) | after(level \(level)) deep \(as1.deep) overlap \(as1.overlap) close \(as1.closePairs) landingClose \(as1.landingClose) rides \(as1.rides) hopscotch \(as1.hops) socials \(sa) footTurnAways \(as1.turnAways)")
            b.merge(bs); a.merge(as1)
        }
        insideReport(name + "-before", b, wall: Date().timeIntervalSince(t0))
        insideReport(name + "-after", a, wall: Date().timeIntervalSince(t0))
        XCTAssertEqual(a.deep, 0, "\(name): a centre inside the slide's box while not on it: \(a.deepTag)")
        let sb = b.socials.values.reduce(0, +), sa = a.socials.values.reduce(0, +)
        let mean = ratios.isEmpty ? 1 : ratios.reduce(0, +) / Float(ratios.count)
        print("PSI \(name) rates before/after: rides \(b.rides)/\(a.rides) hopscotch \(b.hops)/\(a.hops) socials \(sb)/\(sa) per-seed social ratios \(ratios.map { String(format: "%.2f", $0) }) mean \(String(format: "%.2f", mean)) closePairs \(b.closePairs)/\(a.closePairs) landingClose \(b.landingClose)/\(a.landingClose)")
        if meanCheck, !ratios.isEmpty { XCTAssertGreaterThanOrEqual(mean, 0.9, "\(name): socials stay at 0.9x or more (mean of the per-seed ratios)") }
        return (b, a, bySeed)
    }
    /// As the game plays: five bodies, two seeds x 180 sim-s per arm.
    func testParkNobodyInsideTheSlide() { _ = insideBothArms("plain", seeds: [1, 2], seconds: 180, mode: .plain) }
    /// DENSE: every free body is sent to the slide every 0.5 s (autonomy on): many ride exits and approaches next to friends. One seed x 180 sim-s per arm. The bodies do not bunch at the
    /// chute's end: the pairs closer than 0.9 stay near the before arm.
    func testParkNobodyInsideTheSlideDense() {
        let r = insideBothArms("dense", seeds: [3], seconds: 180, mode: .dense)
        XCTAssertGreaterThan(r.after.rides, 5, "the slide is ridden")
        XCTAssertLessThanOrEqual(r.after.landingClose, max(10, r.before.landingClose * 2), "dense: bodies bunch at the chute's end")
    }
    /// SOCIAL: the social cooldowns forced short every second (the park with more socials). Seeds 4, 5, 6 x 180 sim-s per arm, ONE TEST PER SEED (r4: the three in one test took 668 s,
    /// over the gate's budget; one seed is ~225 s). Each asserts deep 0 for its seed and records its social ratio (after / before); the last of the three to run in the process asserts
    /// the 3-seed mean >= 0.9, as the one test did (the three are in one class, so they share a process even with parallel testing on).
    nonisolated(unsafe) static var socialSeedRatios: [UInt64: Float] = [:]
    func socialSeed(_ seed: UInt64) {
        let r = insideBothArms("social-s\(seed)", seeds: [seed], seconds: 180, mode: .social, meanCheck: false)
        Self.socialSeedRatios[seed] = r.ratios[seed] ?? -1          // (-1: fewer than 5 socials before, left out of the mean as before)
        let all: [UInt64] = [4, 5, 6]
        let have = all.compactMap { Self.socialSeedRatios[$0] }
        guard have.count == all.count else { print("PSI social: \(have.count)/3 seeds so far; the 3-seed mean is asserted by the last of the three to run"); return }
        let used = have.filter { $0 >= 0 }
        let mean = used.isEmpty ? 1 : used.reduce(0, +) / Float(used.count)
        print("PSI social 3-seed social ratios \(all.map { String(format: "%.2f", Self.socialSeedRatios[$0] ?? -1) }) mean \(String(format: "%.2f", mean))")
        if !used.isEmpty { XCTAssertGreaterThanOrEqual(mean, 0.9, "social: socials stay at 0.9x or more (mean of the seeds 4, 5, 6 ratios)") }
    }
    func testParkNobodyInsideTheSlideSocial4() { socialSeed(4) }
    func testParkNobodyInsideTheSlideSocial5() { socialSeed(5) }
    func testParkNobodyInsideTheSlideSocial6() { socialSeed(6) }
    /// Exploration (`TEST_RUNNER_PSI_MODE` plain / dense / social, `TEST_RUNNER_PSI_SEEDS` "4,5,6"): the same report for any seeds; skipped without the variables.
    func testParkInsideSeeds() throws {
        let env = ProcessInfo.processInfo.environment
        guard let s = env["PSI_SEEDS"] else { throw XCTSkip("set TEST_RUNNER_PSI_SEEDS") }
        let seeds = s.split(separator: ",").compactMap { UInt64($0) }
        let mode: InsideMode = env["PSI_MODE"] == "dense" ? .dense : env["PSI_MODE"] == "social" ? .social : .plain
        _ = insideBothArms("seeds-\(env["PSI_MODE"] ?? "plain")", seeds: seeds, seconds: Float(env["PSI_SECS"].flatMap { Float($0) } ?? 180), mode: mode, level: Int(env["PSI_LEVEL"] ?? "") ?? 2)
    }

    /// The real-app before watch (the Panda, 2 s into the visit): his centre 0.58 from the slide's box (inside its 0.65 zone, outside the box) on a walk past its front corner. Main's rule
    /// turned the slide soft for him (`decorExitCheck`) and the walk cut the corner 0.25 from the box. Both arms, the same walk: the least distance from his centre to the box.
    func testRimWalkKeepsTheSlideSolid() {
        var least: [Bool: Float] = [:]
        for fix in [false, true] {
            BlobBrain.slideSoftEndEnabled = fix
            defer { BlobBrain.slideSoftEndEnabled = true }
            let lab = parkLab(n: 1, seed: 3, aspect: Self.portrait)
            let sl = DecorField.shared.foot(ParkToys.slideUID)!
            let r = lab.rigs[0], b = r.brain
            place(r, SIMD2(1.52, 2.09))
            b.requestNow(.goTo(SIMD2(3.21, 3.41)))
            var l: Float = 9, soft = 0
            for _ in 0..<(8 * 60) {
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
                l = min(l, sl.distance(b.position))
                if b.decorIgnore == ParkToys.slideUID { soft += 1 }
            }
            print(String(format: "PSI RIM fix %d: least centre-to-box %.2f, soft for %d steps, ends at (%.2f,%.2f)", fix ? 1 : 0, l, soft, b.position.x, b.position.y))
            least[fix] = l
            b.abortAll(r.sim, r.skinner)
        }
        XCTAssertGreaterThanOrEqual(least[true] ?? 0, 0.55, "with the fix the walk keeps his footprint off the slide")
    }
}
