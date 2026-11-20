//
//  ParkHopscotchKeepOutTests.swift
//  park-hopscotch-r1 ("Last bug, at the park if one is hopscotching please try to keep the others away", 2026-11-20). Five autonomous bodies in the park (portrait, wired like the real stage:
//  SocialTests.Lab) with hopscotch games on. Every sample of a game (from the first hopper's commit until the line is empty) the bodies who are NOT in the line are measured against the
//  court's rectangle plus half a metre (about one body radius): entries, seconds inside, who was inside when the game began, the hopper's interruptions (his game cut short, a social
//  started on him, a body within 0.9 of him), bodies standing still at the court's edge, and the park's rates (games, socials, distance walked) for the "add, never displace" check.
//  The before arm is the same build with `HopscotchTuning.guardOn` false (what `-ParkHopGuard old` does): the court is flat paint as it was. HKO lines.
//  Modes: forced (a body is sent to the court whenever none is on, 8 s after the last game: the inside counts) and plain (the game's own picks after the first host at 10 s: the rates).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkHopscotchKeepOutTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let portrait: Float = 440.0 / 956.0
    static let starts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(-1.2, 2.2), SIMD2(1.0, 2.9)]
    /// The measured keep-out: the court's rectangle plus this (about one body radius).
    static let margin: Float = 0.5
    var hour0: Double?, guard0 = true, join0: Float = 0.35, seesaw0 = true, budget0: CFTimeInterval = 0

    override func setUp() {
        hour0 = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 14          // (day: the meal / night rules do not run in the soak)
        guard0 = HopscotchTuning.guardOn; join0 = HopscotchTuning.joinChance; seesaw0 = ParkPlayTuning.seesawInPark; budget0 = BlobBrain.pickBudgetSeconds
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
    }
    override func tearDown() {
        HopscotchTuning.guardOn = guard0; HopscotchTuning.joinChance = join0; ParkPlayTuning.seesawInPark = seesaw0; BlobBrain.pickBudgetSeconds = budget0
        DayClock.shared.forcedHour = hour0
        DecorField.shared.clear(); ToyTuning.settle = 5; ContactTuning.lookAhead = true
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: Self.portrait)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    func parkLab(n: Int, seed: UInt64, starts: [SIMD2<Float>]? = nil, quiet: Bool = true) -> SocialTests.Lab {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: Self.portrait)
        let lab = SocialTests.Lab(n: n, positions: Array((starts ?? Self.starts).prefix(n)), quiet: quiet, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        return lab
    }
    func place(_ r: MotionRig, _ p: SIMD2<Float>) {
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: p)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
    }

    // MARK: the soak

    struct Run {
        var seconds: Float = 0, games = 0, gameSecs: Float = 0
        var starts = 0, completed = 0, cut = 0, socialOnHopper = 0, giveUps = 0
        var entries = 0, insideSecs: Float = 0, deepSamples = 0, startInsideGames = 0, leftoverSecs: Float = 0, leftoverMax: Float = 0
        var bumps = 0, edgeStillSecs: Float = 0, offFloor = 0, maxSimul = 0, simulSamples = 0
        var socials = 0, dist: Float = 0, stale = 0, stuckRepicks = 0
        var entryTags: [String: Int] = [:], edgeTags: [String: Int] = [:], offFloorNear = 0, notes: [String] = []
        mutating func merge(_ o: Run) {
            seconds += o.seconds; games += o.games; gameSecs += o.gameSecs; starts += o.starts; completed += o.completed; cut += o.cut; socialOnHopper += o.socialOnHopper; giveUps += o.giveUps
            entries += o.entries; insideSecs += o.insideSecs; deepSamples += o.deepSamples; startInsideGames += o.startInsideGames; leftoverSecs += o.leftoverSecs; leftoverMax = max(leftoverMax, o.leftoverMax)
            bumps += o.bumps; edgeStillSecs += o.edgeStillSecs; offFloor += o.offFloor; maxSimul = max(maxSimul, o.maxSimul); simulSamples += o.simulSamples
            socials += o.socials; dist += o.dist; stale += o.stale; stuckRepicks += o.stuckRepicks
            for (k, v) in o.entryTags { entryTags[k, default: 0] += v }
            for (k, v) in o.edgeTags { edgeTags[k, default: 0] += v }; offFloorNear += o.offFloorNear
            notes += o.notes
        }
    }

    func soak(seed: UInt64, seconds: Float, guardOn: Bool, forced: Bool) -> Run {
        var out = Run()
        HopscotchTuning.guardOn = guardOn
        HopscotchTuning.joinChance = ParkPlayTuning.hopscotchJoin
        ParkPlayTuning.seesawInPark = false          // (the owner's park: no seesaw)
        BlobBrain.pickBudgetSeconds = .infinity          // (repeatable picks)
        ParkVisitPlan.current = .all
        let lab = parkLab(n: 5, seed: seed, quiet: false)
        for (k, r) in lab.rigs.enumerated() {
            r.brain.feature = JellyRoster.feature([3, 2, JellyRoster.pandaID, 1, 3][k])
            r.skinner.autoBlink = false; r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, uid = court.uid
        let line = HopscotchLine.shared
        let n = lab.rigs.count
        var gameOn = false, gameStart: Float = 0, lastEnd: Float = 2
        var episode = Set<Int>(), leftover = Set<Int>(), leftoverSince = [Int: Float]()
        var prevInside = [Bool](repeating: false, count: n), prevKind = [IdleKind?](repeating: nil, count: n), sawLeave = [Bool](repeating: false, count: n)
        var lastSocial = [ObjectIdentifier?](repeating: nil, count: n), socialOnNow = [Bool](repeating: false, count: n)
        var lastPos = lab.rigs.indices.map { GameCare.floorPos(lab.rigs[$0].brain, lab.rigs[$0].sim) }, refPos = lastPos
        var bumpNow = Set<Int>()
        let giveUps0 = BlobBrain.hopApproachGiveUps, repicks0 = lab.rigs.map { $0.brain.stuckRepicks }
        var rng = seed &* 6364136223846793005 &+ 1442695040888963407
        func rnd() -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int(rng >> 33) }
        var t: Float = 0
        var hosted = false
        for i in 0..<Int(seconds * 60) {
            // the driver
            if i % 30 == 3 {
                let wantGame = forced ? (!line.active && t - lastEnd > 8) : (!hosted && t > 10)
                if wantGame {
                    let free = lab.rigs.filter { $0.brain.idleState.kind == nil && !$0.brain.isSocial && $0.brain.pending == nil }
                    if !free.isEmpty {
                        let r = free[rnd() % free.count]
                        if r.brain.startCommandedDecor(.decorHopscotch, only: .hopscotch, r.sim, r.skinner) { hosted = true }
                    }
                }
            }
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            let players = line.players(uid)
            let on = !players.isEmpty
            let floor = lab.rigs.indices.map { GameCare.floorPos(lab.rigs[$0].brain, lab.rigs[$0].sim) }
            if on && !gameOn {
                gameOn = true; gameStart = t; out.games += 1; episode = []; sawLeave = [Bool](repeating: false, count: n); bumpNow = []
                leftover = Set((0..<n).filter { k in !players.contains { $0.id == k } && court.distance(floor[k]) < Self.margin })
                leftoverSince = [:]; for k in leftover { leftoverSince[k] = t }
                if !leftover.isEmpty { out.startInsideGames += 1; if out.notes.count < 30 { out.notes.append(String(format: "seed %d t%.1f game start with %d inside: %@", Int(seed), t, leftover.count, leftover.map { ParkSlideProbe.doing(lab.rigs[$0].brain) }.joined(separator: " | "))) } }
            }
            if on { for p in players { episode.insert(p.id) } }
            if !on && gameOn { gameOn = false; out.gameSecs += t - gameStart; lastEnd = t; for k in leftover { out.leftoverSecs += t - (leftoverSince[k] ?? t) }; leftover = [] }
            var simul = 0
            for (k, r) in lab.rigs.enumerated() {
                let b = r.brain
                // distance walked
                out.dist += simd_distance(floor[k], lastPos[k]); lastPos[k] = floor[k]
                // activity starts
                if let s = b.social { let id = ObjectIdentifier(s); if lastSocial[k] != id { lastSocial[k] = id; out.socials += 1 } } else { lastSocial[k] = nil }
                let kind = b.idleState.kind
                if kind == .decorHopscotch, prevKind[k] != .decorHopscotch { out.starts += 1; sawLeave[k] = false }
                if kind == .decorHopscotch, b.idleState.slideStage == 3 { sawLeave[k] = true }
                if prevKind[k] == .decorHopscotch, kind != .decorHopscotch { if sawLeave[k] { out.completed += 1 } else { out.cut += 1; if out.notes.count < 30 { out.notes.append(String(format: "seed %d t%.1f body %d cut short, now [%@]", Int(seed), t, k, ParkSlideProbe.doing(b))) } } }
                prevKind[k] = kind
                if kind == .decorHopscotch, b.social != nil { if !socialOnNow[k] { out.socialOnHopper += 1 }; socialOnNow[k] = true } else { socialOnNow[k] = false }
                if kind == .decorHopscotch, court.distance(floor[k]) < 0.9, b.idleState.slideStage == 1 || b.idleState.slideStage == 6 { simul += 1 }
                if let rf = GameCamera.roamFloor, !rf.contains(floor[k]) { out.offFloor += 1; if court.distance(floor[k]) < 1.3 { out.offFloorNear += 1 } }
                guard gameOn, !episode.contains(k) else { prevInside[k] = false; continue }
                // a body who is not in the line
                let d = court.distance(floor[k])
                let inside = d < Self.margin
                if leftover.contains(k) {
                    if inside { } else { out.leftoverSecs += t - (leftoverSince[k] ?? t); out.leftoverMax = max(out.leftoverMax, t - (leftoverSince[k] ?? t)); leftover.remove(k) }
                } else if inside {
                    out.insideSecs += 1.0 / 60
                    if d < 0 { out.deepSamples += 1 }
                    if !prevInside[k] {
                        out.entries += 1
                        let tag = ParkSlideProbe.doing(b).split(separator: " ").filter { !$0.hasPrefix("pose") && !$0.hasPrefix("ign") }.joined(separator: " ")
                        out.entryTags[tag, default: 0] += 1
                        if out.notes.count < 30 { out.notes.append(String(format: "seed %d t%.1f body %d ENTERS d %.2f at (%.2f,%.2f) [%@]", Int(seed), t, k, d, floor[k].x, floor[k].y, ParkSlideProbe.doing(b))) }
                    }
                }
                prevInside[k] = inside
                // a hopper and this body closer than 0.9
                for p in players where p.id != k {
                    let key = p.id * 8 + k
                    if simd_distance(floor[p.id], floor[k]) < 0.9 { if !bumpNow.contains(key) { bumpNow.insert(key); out.bumps += 1 } } else { bumpNow.remove(key) }
                }
            }
            if simul > 0 { out.simulSamples += 1 }
            out.maxSimul = max(out.maxSimul, simul)
            // standing still at the court's edge (0.5 s windows)
            if i % 30 == 29 {
                if gameOn {
                    for k in 0..<n where !episode.contains(k) && !leftover.contains(k) {
                        let d = court.distance(floor[k])
                        if d >= Self.margin, d < 1.3, simd_distance(floor[k], refPos[k]) < 0.05, lab.rigs[k].brain.idleState.kind == nil { out.edgeStillSecs += 0.5; let tg = ParkSlideProbe.doing(lab.rigs[k].brain).split(separator: " ").filter { !$0.hasPrefix("pose") && !$0.hasPrefix("ign") }.joined(separator: " ") + (d < 0.7 ? " [d<0.7]" : " [d>=0.7]"); out.edgeTags[tg, default: 0] += 1 }
                    }
                }
                refPos = floor
            }
        }
        out.seconds = t
        if gameOn { out.gameSecs += t - gameStart }
        out.giveUps = BlobBrain.hopApproachGiveUps - giveUps0
        out.stuckRepicks = zip(lab.rigs, repicks0).reduce(0) { $0 + $1.0.brain.stuckRepicks - $1.1 }
        for r in lab.rigs { r.brain.abortAll(r.sim, r.skinner) }
        for _ in 0..<5 { lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60) }
        if line.active || HopscotchTuning.lineCount != 0 { out.stale += 1 }
        return out
    }

    func report(_ name: String, _ r: Run) {
        let mins = max(r.seconds / 60, 0.001), gmins = max(r.gameSecs / 60, 0.001)
        for nt in r.notes.prefix(30) { print("HKO \(name) note \(nt)") }
        for (k, v) in r.entryTags.sorted(by: { $0.value > $1.value }) { print("HKO \(name) entry \(v) [\(k)]") }
        for (k, v) in r.edgeTags.sorted(by: { $0.value > $1.value }).prefix(8) { print("HKO \(name) edge-still \(Float(v) * 0.5) s [\(k)]") }
        print(String(format: "HKO %@ games %d (%.1f game-min of %.1f park-min) | entries %d, inside %.1f s (deep samples %d), games that began with someone inside %d (their step-off %.1f s, longest %.1f s) | hopper: starts %d completed %d cut short %d, social started on him %d, bodies within 0.9 of him %d, give-ups %d, hopping at once max %d (%d samples) | edge-still %.1f s | offFloor %d (near the court %d) stale %d | per park-min: games %.2f socials %.2f dist %.1f stuckRepicks %d",
                     name, r.games, gmins, mins, r.entries, r.insideSecs, r.deepSamples, r.startInsideGames, r.leftoverSecs, r.leftoverMax, r.starts, r.completed, r.cut, r.socialOnHopper, r.bumps, r.giveUps, r.maxSimul, r.simulSamples, r.edgeStillSecs, r.offFloor, r.offFloorNear, r.stale, Float(r.games) / mins, Float(r.socials) / mins, r.dist / mins, r.stuckRepicks))
    }

    /// Both arms on the same seeds. Returns (before, after).
    func bothArms(_ name: String, seeds: [UInt64], seconds: Float, forced: Bool) -> (Run, Run) {
        var b = Run(), a = Run()
        for seed in seeds {
            let bs = soak(seed: seed, seconds: seconds, guardOn: false, forced: forced), as1 = soak(seed: seed, seconds: seconds, guardOn: true, forced: forced)
            print("HKO \(name) seed \(seed): before entries \(bs.entries) inside \(String(format: "%.1f", bs.insideSecs)) s games \(bs.games) cut \(bs.cut) | after entries \(as1.entries) inside \(String(format: "%.1f", as1.insideSecs)) s games \(as1.games) cut \(as1.cut) startInside \(as1.startInsideGames)")
            b.merge(bs); a.merge(as1)
        }
        report(name + "-BEFORE", b); report(name + "-AFTER", a)
        return (b, a)
    }

    /// Forced games, two seeds: before the fix others walk through / stand on the court during a game, after it nobody does; nobody is left inside, the line always empties.
    func testOthersStayOffTheCourtDuringAGame() {
        let (b, a) = bothArms("forced", seeds: [1, 2], seconds: 150, forced: true)
        XCTAssertGreaterThan(b.games, 0, "the before arm played games")
        XCTAssertGreaterThan(a.games, 0, "the after arm played games")
        XCTAssertGreaterThan(b.entries + b.startInsideGames, 0, "vacuous: nobody ever walked onto the court in the before arm (the soak does not show the bug)")
        XCTAssertEqual(a.entries, 0, "after: a body who was not in the line entered the court + margin during a game: \(a.entryTags)")
        XCTAssertEqual(a.deepSamples, 0, "after: a body stood on the court itself")
        XCTAssertEqual(a.insideSecs, 0, accuracy: 0.001, "after: seconds inside")
        XCTAssertEqual(a.socialOnHopper, 0, "after: a social was started on a hopper")
        XCTAssertEqual(a.stale, 0, "the line empties after every game")
        XCTAssertLessThanOrEqual(a.maxSimul, 1, "after: one hopper at a time on the court")
        XCTAssertLessThanOrEqual(a.leftoverMax, HopscotchTuning.clearWait + 1, "after: whoever was on the court when a game began stepped off within the hopper's wait")
        XCTAssertEqual(a.offFloor, 0, "after: nobody is pushed off the park floor")
    }

    /// The game's own picks (a host at 10 s, then autonomy), two seeds x 240 s: the rates stay within 10 %.
    func testRatesStayWithinTenPercent() {
        let (b, a) = bothArms("plain", seeds: [3, 4], seconds: 240, forced: false)
        XCTAssertEqual(a.entries, 0, "after (plain): entries \(a.entryTags)")
        XCTAssertEqual(a.stale, 0)
        func within(_ x: Float, _ y: Float, _ what: String) { if y > 0 { XCTAssertGreaterThanOrEqual(x, y * 0.9, "\(what): \(x) vs before \(y)") } }
        within(Float(a.starts), Float(b.starts), "hopscotch starts")
        within(Float(a.socials), Float(b.socials), "socials")
        within(a.dist, b.dist, "distance walked")
    }

    /// Exploration (`TEST_RUNNER_HKO_SEEDS` "1,2,3", `TEST_RUNNER_HKO_MODE` forced / plain, `TEST_RUNNER_HKO_SECS`): the same table for any seeds; skipped without the variables.
    func testSoakSeeds() throws {
        let env = ProcessInfo.processInfo.environment
        guard let s = env["HKO_SEEDS"] else { throw XCTSkip("set TEST_RUNNER_HKO_SEEDS") }
        let seeds = s.split(separator: ",").compactMap { UInt64($0) }
        let forced = env["HKO_MODE"] != "plain"
        _ = bothArms("soak-\(forced ? "forced" : "plain")", seeds: seeds, seconds: Float(env["HKO_SECS"].flatMap { Float($0) } ?? 180), forced: forced)
    }

    // MARK: focused

    /// Someone standing on the court when a game is committed walks off (a normal walk: no step over 0.2 in one tick), and the hopper hops once the court is clear.
    func testBodyOnTheCourtStepsOffAndTheGameStarts() {
        HopscotchTuning.guardOn = true
        let lab = parkLab(n: 2, seed: 7, starts: [SIMD2(-2.1, -3.2), SIMD2(-2.1, 1.9)])
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        let hop = lab.rigs[0], other = lab.rigs[1]
        for r in lab.rigs { r.brain.autonomy = true }
        place(other, court.centre + SIMD2(0, 0.4))
        XCTAssertLessThan(court.distance(other.brain.position), 0, "he stands on the court")
        hop.brain.idleForced = true
        XCTAssertTrue(hop.brain.decorStart(.decorHopscotch, hop.sim, only: nil, uid: court.uid))
        var last = other.brain.position, maxStep: Float = 0, outAt: Float?, hoppedAt: Float?, t: Float = 0
        for i in 0..<(60 * 40) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            let p = GameCare.floorPos(other.brain, other.sim)
            maxStep = max(maxStep, simd_distance(p, last)); last = p
            if outAt == nil, court.distance(p) >= Self.margin - 0.05 { outAt = t }
            if hoppedAt == nil, line.square(court.uid, hop.brain.steerID) >= 0 { hoppedAt = t }
            if let o = outAt, line.active { XCTAssertGreaterThan(court.distance(p), Self.margin - 0.15, "t \(t): he walked back onto the court (stepped off at \(o))") }
            if i % 30 == 0, t < 14 { print(String(format: "HKO stepoff t%.1f other d %.2f %@ ign %d | hopper stage %d step %d phaseT %.1f line %d on-court %d", t, court.distance(p), ParkSlideProbe.doing(other.brain), other.brain.decorIgnore ?? -1, hop.brain.idleState.slideStage, hop.brain.idleState.slideStep, hop.brain.idleState.phaseT, line.active ? 1 : 0, hop.brain.hopscotchOthersOn(court).count)) }
        }
        print("HKO stepoff: out at \(String(describing: outAt)) hopper landed on square 1 at \(String(describing: hoppedAt)) max step \(maxStep)")
        XCTAssertNotNil(outAt, "he stepped off the court"); XCTAssertLessThan(outAt ?? 99, 5, "promptly")
        XCTAssertLessThan(maxStep, 0.2, "a walk, not a teleport or a slide")
        XCTAssertNotNil(hoppedAt, "the game was played")
    }

    /// Walks the player asks for (a target in the middle of the court, a target across it) never go on to the court while a game is on, and do not stall for good.
    func testCalledWalksGoRoundTheCourt() {
        HopscotchTuning.guardOn = true
        let lab = parkLab(n: 2, seed: 9, starts: [SIMD2(-2.1, -3.2), SIMD2(-0.2, 3.9)])
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        let hop = lab.rigs[0], other = lab.rigs[1]
        hop.brain.idleForced = true
        XCTAssertTrue(hop.brain.decorStart(.decorHopscotch, hop.sim, only: nil, uid: court.uid))
        for _ in 0..<60 { lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertTrue(line.active)
        let targets: [SIMD2<Float>] = [court.centre, SIMD2(-2.1, -1.9), court.centre + SIMD2(0.2, -1.0)]
        for (ti, target) in targets.enumerated() {
            other.brain.requestNow(.goTo(target))
            var t: Float = 0, least: Float = 9
            while t < 12, line.active {
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
                least = min(least, court.distance(GameCare.floorPos(other.brain, other.sim)))
            }
            print(String(format: "HKO called walk %d to (%.2f,%.2f): least distance to the court %.2f, ends at (%.2f,%.2f) after %.1f s (game on %d)", ti, target.x, target.y, least, other.brain.position.x, other.brain.position.y, t, line.active ? 1 : 0))
            XCTAssertGreaterThan(least, Self.margin - 0.15, "walk \(ti): he went onto the court during the game")
            if !line.active { break }
        }
    }

    /// One at a time: three in the line (joins forced), at most one of them hops on the court at any moment, all three finish, and the line is empty at the end.
    func testOneHopperAtATime() {
        HopscotchTuning.guardOn = true
        let lab = parkLab(n: 3, seed: 5, starts: [SIMD2(-2.1, -3.2), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)])
        HopscotchTuning.joinChance = 1
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        for r in lab.rigs { r.brain.autonomy = true }
        lab.rigs[0].brain.idleForced = true
        XCTAssertTrue(lab.rigs[0].brain.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: court.uid))
        var maxPlayers = 0, maxOn = 0, done = false
        for i in 0..<(60 * 120) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            maxPlayers = max(maxPlayers, line.players(court.uid).count)
            var on = 0
            for r in lab.rigs where r.brain.idleState.kind == .decorHopscotch && (r.brain.idleState.slideStage == 1 || r.brain.idleState.slideStage == 6) && line.square(court.uid, r.brain.steerID) < HopscotchLine.done {
                let p = GameCare.floorPos(r.brain, r.sim)
                if court.distance(p) < 0.1 { on += 1 }
            }
            maxOn = max(maxOn, on)
            if i > 600, !line.active, lab.rigs.allSatisfy({ $0.brain.idleState.kind == nil }) { done = true; break }
        }
        print("HKO one-at-a-time: players in the line at most \(maxPlayers), hopping on the court at once at most \(maxOn)")
        XCTAssertGreaterThanOrEqual(maxPlayers, 2, "a line formed")
        XCTAssertLessThanOrEqual(maxOn, 1, "two hoppers on the court at once")
        XCTAssertTrue(done, "the line broke up")
        XCTAssertFalse(line.active); XCTAssertEqual(HopscotchTuning.lineCount, 0)
    }

    /// The court is flat paint when no game is on (the floor rules, `ParkClearSpot`), a wall with a body's margin during one, and the park floor left of the court is wide enough to pass
    /// (printed: the roam floor's half width against the court's west edge).
    func testCourtIsAWallOnlyDuringAGame() {
        HopscotchTuning.guardOn = true
        _ = parkLab(n: 1, seed: 3)
        let line = HopscotchLine.shared
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!
        XCTAssertFalse(court.spec.solid, "no game: flat")
        let edge = court.centre + SIMD2(court.spec.half.x + 0.2, 0)
        XCTAssertFalse(ParkClearSpot.blocked(edge, radius: 0.7), "no game: the margin is free floor")
        line.enroll(court.uid, 0)
        let c2 = DecorField.shared.foot(ParkToys.hopscotchUID)!
        XCTAssertTrue(c2.spec.solid, "a game: a wall"); XCTAssertEqual(c2.spec.reach, HopscotchTuning.wallReach)
        XCTAssertTrue(ParkClearSpot.blocked(edge, radius: 0.7), "a game: inside the margin")
        XCTAssertFalse(ParkClearSpot.blocked(edge, radius: 0.7, ignoring: court.uid), "a hopper: his own court is no wall")
        let far = court.centre + SIMD2(court.spec.half.x + 0.9, 0)
        XCTAssertFalse(ParkClearSpot.blocked(far, radius: 0.7), "a game: 0.9 off the edge is free")
        if let rf = GameCamera.roamFloor {
            for z: Float in [0, 1, 2, 3, 4] { print(String(format: "HKO roam floor z %.0f: half width %.2f, court west edge x %.2f, wall west edge x %.2f", z, rf.halfWidth(at: z), court.centre.x - court.spec.half.x, court.centre.x - court.spec.half.x - 0.7 * HopscotchTuning.wallReach)) }
        }
        line.remove(court.uid, 0)
        XCTAssertFalse(DecorField.shared.foot(ParkToys.hopscotchUID)!.spec.solid, "the game is over: flat again at once")
        XCTAssertEqual(HopscotchTuning.lineCount, 0)
    }
}
