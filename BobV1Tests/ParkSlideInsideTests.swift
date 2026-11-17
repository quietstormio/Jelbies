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
    }
    enum InsideMode { case plain, dense, social }

    static let insideStarts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(-1.2, 2.2), SIMD2(1.0, 2.9)]

    func insideRun(seeds: [UInt64], seconds: Float, mode: InsideMode = .plain, fix: Bool = true) -> InsideRun {
        var out = InsideRun()
        let seesaw = ParkPlayTuning.seesawInPark, budget = BlobBrain.pickBudgetSeconds
        ParkPlayTuning.seesawInPark = false          // (the owner's park: no seesaw since park-play-r1; XCTest places it for the seesaw's own suites)
        BlobBrain.pickBudgetSeconds = .infinity          // (repeatable picks: the wall-clock budget would time out at random on a loaded host)
        BlobBrain.slideSoftEndEnabled = fix          // (false = main's rule: the before arm)
        defer { ParkPlayTuning.seesawInPark = seesaw; BlobBrain.pickBudgetSeconds = budget; BlobBrain.slideSoftEndEnabled = true }
        for seed in seeds {
            let lab = parkLab(n: 5, seed: seed, aspect: Self.portrait, starts: Self.insideStarts, quiet: false)
            // the owner's park: Lavender (wings), Moss (daisy), Panda (ears), the visitors Bubbles (yellow: spines) and Freckles (lavender: wings); set as ParkPlayTests' soak sets them
            for (k, r) in lab.rigs.enumerated() {
                r.brain.feature = JellyRoster.feature([3, 2, JellyRoster.pandaID, 1, 3][k])
                r.skinner.autoBlink = false; r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            }
            let sf = DecorField.shared.foot(ParkToys.slideUID)!
            let n = lab.rigs.count
            var inNow = [Bool](repeating: false, count: n), hist = [[String]](repeating: [], count: n), last = [String](repeating: "", count: n)
            var lastSocial = [ObjectIdentifier?](repeating: nil, count: n), lastIdle = [IdleKind?](repeating: nil, count: n), lastStage = [Int](repeating: 0, count: n)
            var closeNow = Set<Int>()
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
                        if d < 0 { out.deep += 1; out.deepTag[st, default: 0] += 1 }
                        if !inNow[k] {
                            inNow[k] = true; out.episodes += 1
                            if out.notes.count < 40 { out.notes.append(String(format: "seed %d t%.1f body %d d %.2f at (%.2f,%.2f) [%@] hist %@", Int(seed), t, k, d, fl.x, fl.y, st, hist[k].joined(separator: " > "))) }
                        }
                    } else { inNow[k] = false }
                }
                // two bodies' roots closer than 0.9 (the circle spring holds 1.09; a touching emote's skins meet at ~0.95), not in one session together
                for i in 0..<n { for j in (i + 1)..<n {
                    let bi = lab.rigs[i].brain, bj = lab.rigs[j].brain
                    let same = bi.social != nil && bi.social === bj.social
                    let dist = simd_distance(GameCare.floorPos(bi, lab.rigs[i].sim), GameCare.floorPos(bj, lab.rigs[j].sim))
                    let key = i * 8 + j
                    if dist < 0.9, !same {
                        out.closePairs += 1
                        let tag = [ParkSlideProbe.doing(bi), ParkSlideProbe.doing(bj)].sorted().joined(separator: " x ")
                        out.closeTags[tag, default: 0] += 1
                        if !closeNow.contains(key) { closeNow.insert(key); if out.notes.count < 60 { out.notes.append(String(format: "close seed %d t%.1f %d-%d dist %.2f [%@]", Int(seed), t, i, j, dist, tag)) } }
                    } else { closeNow.remove(key) }
                } }
            }
            for r in lab.rigs { r.brain.abortAll(r.sim, r.skinner) }
        }
        return out
    }

    func insideReport(_ name: String, _ r: InsideRun, wall: TimeInterval) {
        for nt in r.notes { print("PSI \(name) note \(nt)") }
        for (k, v) in r.byTag.sorted(by: { $0.value > $1.value }) { print("PSI \(name) overlap \(v) deep \(r.deepTag[k] ?? 0) samples [\(k)]") }
        for (k, v) in r.closeTags.sorted(by: { $0.value > $1.value }).prefix(12) { print("PSI \(name) close \(v) samples [\(k)]") }
        print("PSI \(name) rates rides \(r.rides) hopscotch \(r.hops) socials \(r.socials.values.reduce(0, +)) [\(r.socials.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))]")
        print("PSI \(name) idles [\(r.idles.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))]")
        print("PSI \(name) total samples \(r.samples) overlap \(r.overlap) deep \(r.deep) episodes \(r.episodes) closePairs \(r.closePairs) wall \(Int(wall)) s")
    }

    /// Both arms on the same seeds: `fix` false (main's rule, the soft slide as before) then true (park-slide-r3). The after arm: no centre inside the box; the activity starts
    /// (rides, hopscotch, socials) at 0.9x of the before arm or more.
    func insideBothArms(_ name: String, seeds: [UInt64], seconds: Float, mode: InsideMode) -> (before: InsideRun, after: InsideRun) {
        let t0 = Date()
        let b = insideRun(seeds: seeds, seconds: seconds, mode: mode, fix: false)
        insideReport(name + "-before", b, wall: Date().timeIntervalSince(t0))
        let t1 = Date()
        let a = insideRun(seeds: seeds, seconds: seconds, mode: mode, fix: true)
        insideReport(name + "-after", a, wall: Date().timeIntervalSince(t1))
        XCTAssertEqual(a.deep, 0, "\(name): a centre inside the slide's box while not on it: \(a.deepTag)")
        let sb = b.socials.values.reduce(0, +), sa = a.socials.values.reduce(0, +)
        print("PSI \(name) rates before/after: rides \(b.rides)/\(a.rides) hopscotch \(b.hops)/\(a.hops) socials \(sb)/\(sa)")
        if sb >= 10 { XCTAssertGreaterThanOrEqual(Float(sa), 0.9 * Float(sb), "\(name): socials stay at 0.9x or more") }
        return (b, a)
    }
    /// As the game plays: five bodies, two seeds x 180 sim-s per arm.
    func testParkNobodyInsideTheSlide() { _ = insideBothArms("plain", seeds: [1, 2], seconds: 180, mode: .plain) }
    /// DENSE: every free body is sent to the slide every 0.5 s (autonomy on): many ride exits and approaches next to friends. One seed x 180 sim-s per arm.
    func testParkNobodyInsideTheSlideDense() {
        let r = insideBothArms("dense", seeds: [3], seconds: 180, mode: .dense)
        XCTAssertGreaterThan(r.after.rides, 5, "the slide is ridden")
    }
    /// SOCIAL: the social cooldowns forced short every second (the park with more socials). One seed x 180 sim-s per arm.
    func testParkNobodyInsideTheSlideSocial() { _ = insideBothArms("social", seeds: [4], seconds: 180, mode: .social) }

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
