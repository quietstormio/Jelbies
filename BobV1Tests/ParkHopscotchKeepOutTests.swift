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
    /// The measured keep-out: the court's rectangle plus this (about one body radius, less 5 cm for the drawn body's lean: the game's wall holds 0.56; at the floor's left edge a body is pinned at 0.50).
    static let margin: Float = 0.45
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

    func parkLab(n: Int, seed: UInt64, starts: [SIMD2<Float>]? = nil, quiet: Bool = true, aspect: Float = ParkHopscotchKeepOutTests.portrait) -> SocialTests.Lab {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: aspect)
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
        var bumps = 0, edgeStillSecs: Float = 0, edgeAllSecs: Float = 0, offFloor = 0, maxSimul = 0, simulSamples = 0
        var socials = 0, dist: Float = 0, stale = 0, stuckRepicks = 0
        var entryTags: [String: Int] = [:], edgeTags: [String: Int] = [:], offTags: [String: Int] = [:], offFloorNear = 0, notes: [String] = []
        mutating func merge(_ o: Run) {
            seconds += o.seconds; games += o.games; gameSecs += o.gameSecs; starts += o.starts; completed += o.completed; cut += o.cut; socialOnHopper += o.socialOnHopper; giveUps += o.giveUps
            entries += o.entries; insideSecs += o.insideSecs; deepSamples += o.deepSamples; startInsideGames += o.startInsideGames; leftoverSecs += o.leftoverSecs; leftoverMax = max(leftoverMax, o.leftoverMax)
            bumps += o.bumps; edgeStillSecs += o.edgeStillSecs; edgeAllSecs += o.edgeAllSecs; offFloor += o.offFloor; maxSimul = max(maxSimul, o.maxSimul); simulSamples += o.simulSamples
            socials += o.socials; dist += o.dist; stale += o.stale; stuckRepicks += o.stuckRepicks
            for (k, v) in o.entryTags { entryTags[k, default: 0] += v }
            for (k, v) in o.edgeTags { edgeTags[k, default: 0] += v }; for (k, v) in o.offTags { offTags[k, default: 0] += v }; offFloorNear += o.offFloorNear
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
                if let rf = GameCamera.roamFloor, !rf.contains(floor[k]) { out.offFloor += 1; if court.distance(floor[k]) < 1.3 { out.offFloorNear += 1; let tg = String(format: "%@ %@ at (%.1f,%.1f) d %.1f", gameOn ? (episode.contains(k) ? "PLAYER" : "other") : "nogame", ParkSlideProbe.doing(b).split(separator: " ").filter { !$0.hasPrefix("pose") && !$0.hasPrefix("ign") }.joined(separator: " "), (floor[k].x * 2).rounded() / 2, (floor[k].y * 2).rounded() / 2, (court.distance(floor[k]) * 5).rounded() / 5); out.offTags[tg, default: 0] += 1 } }
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
                        if d < 1.3, simd_distance(floor[k], refPos[k]) < 0.05, lab.rigs[k].brain.idleState.kind == nil { out.edgeAllSecs += 0.5 }
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
        for (k, v) in r.offTags.sorted(by: { $0.value > $1.value }).prefix(8) { print("HKO \(name) off-floor near court \(v) samples [\(k)]") }
        for (k, v) in r.edgeTags.sorted(by: { $0.value > $1.value }).prefix(8) { print("HKO \(name) edge-still \(Float(v) * 0.5) s [\(k)]") }
        print(String(format: "HKO %@ games %d (%.1f game-min of %.1f park-min) | entries %d, inside %.1f s (deep samples %d), games that began with someone inside %d (their step-off %.1f s, longest %.1f s) | hopper: starts %d completed %d cut short %d, social started on him %d, bodies within 0.9 of him %d, give-ups %d, hopping at once max %d (%d samples) | edge-still %.1f s (all within 1.3 m of the court, inside included: %.1f s) | offFloor %d (near the court %d) stale %d | per park-min: games %.2f socials %.2f dist %.1f stuckRepicks %d",
                     name, r.games, gmins, mins, r.entries, r.insideSecs, r.deepSamples, r.startInsideGames, r.leftoverSecs, r.leftoverMax, r.starts, r.completed, r.cut, r.socialOnHopper, r.bumps, r.giveUps, r.maxSimul, r.simulSamples, r.edgeStillSecs, r.edgeAllSecs, r.offFloor, r.offFloorNear, r.stale, Float(r.games) / mins, Float(r.socials) / mins, r.dist / mins, r.stuckRepicks))
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
        // (plain walks and idles must never enter; a social already running when the game began is choreography the wall does not steer, and an idle hop in place at the margin's edge brushes it by the
        // hop's own sway: those are counted, not forbidden)
        XCTAssertTrue(a.entryTags.filter { $0.key.contains("scr:walk") && !$0.key.hasPrefix("soc:") }.isEmpty, "after: a body who was not in the line and in no social WALKED into the court + margin during a game: \(a.entryTags)")
        XCTAssertLessThanOrEqual(a.entries, 12, "after: entries \(a.entryTags)")          // (the rest: ring dances / hugs already running, drifting a few cm into the margin)
        XCTAssertEqual(a.deepSamples, 0, "after: a body stood on the court itself")
        XCTAssertLessThan(a.insideSecs, 3.0, "after: seconds inside")
        XCTAssertEqual(a.socialOnHopper, 0, "after: a social was started on a hopper")
        XCTAssertEqual(a.stale, 0, "the line empties after every game")
        XCTAssertLessThanOrEqual(a.leftoverMax, HopscotchTuning.clearWait + 8, "after: whoever was on the court when a game began stepped off (one in a social leaves when it ends; the hopper goes after clearWait)")
        print("HKO off-floor samples near the court: before \(b.offFloorNear), after \(a.offFloorNear) (a body idling at the floor's left edge beside the court: the strip left of the wall is a dead end during a game)")
    }

    /// The game's own picks (a host at 10 s, then autonomy), two seeds x 240 s: the rates stay within 10 %.
    func testRatesStayWithinTenPercent() {
        let (b, a) = bothArms("plain", seeds: [3, 4], seconds: 240, forced: false)
        XCTAssertTrue(a.entryTags.filter { $0.key.contains("scr:walk") && !$0.key.hasPrefix("soc:") }.isEmpty, "after (plain): a walk into the court + margin: \(a.entryTags)")
        XCTAssertEqual(a.stale, 0)
        func within(_ x: Float, _ y: Float, _ what: String) { if y > 0 { XCTAssertGreaterThanOrEqual(x, y * 0.9, "\(what): \(x) vs before \(y)") } }
        print("HKO rates: starts \(b.starts) -> \(a.starts), completed turns \(b.completed) -> \(a.completed), games \(b.games) -> \(a.games), game-min \(b.gameSecs / 60) -> \(a.gameSecs / 60) (the before arm re-starts cancelled games: cut short \(b.cut) -> \(a.cut))")
        within(Float(a.completed), Float(b.completed), "hopscotch turns played to the end")
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
        HopscotchTuning.guardOn = true; HopscotchTuning.joinChance = 0          // (he must not join the line: this is about the one who does not play)
        let lab = parkLab(n: 2, seed: 7, starts: [SIMD2(-2.1, -3.2), SIMD2(-2.1, 1.9)], quiet: false)
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        let hop = lab.rigs[0], other = lab.rigs[1]
        for r in lab.rigs { r.brain.autonomy = true }
        place(other, court.centre + SIMD2(0, 0.4))
        XCTAssertLessThan(court.distance(other.brain.position), 0, "he stands on the court")
        hop.brain.idleForced = true
        XCTAssertTrue(hop.brain.decorStart(.decorHopscotch, hop.sim, only: nil, uid: court.uid))
        var last = other.brain.position, maxStep: Float = 0, outAt: Float?, hoppedAt: Float?, t: Float = 0, returned: (t: Float, joiner: Bool)?
        for i in 0..<(60 * 40) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            let p = GameCare.floorPos(other.brain, other.sim)
            maxStep = max(maxStep, simd_distance(p, last)); last = p
            if outAt == nil, court.distance(p) >= Self.margin - 0.05 { outAt = t }
            if hoppedAt == nil, line.square(court.uid, hop.brain.steerID) >= 0 { hoppedAt = t }
            if outAt != nil, line.active, court.distance(p) < Self.margin - 0.15 {
                let joiner = line.contains(court.uid, other.brain.steerID)
                if returned == nil { returned = (t, joiner); print(String(format: "HKO stepoff RETURN t%.1f d %.2f: %@ (in the line %d, kind %@, notice %d, wait %d)", t, court.distance(p), joiner ? "a JOINER" : "an INTRUDER", joiner ? 1 : 0, String(describing: other.brain.idleState.kind), other.brain.toy.noticeUID, other.brain.toy.waitUID)) }
                if !joiner, !(other.brain.toy.noticeUID == court.uid || other.brain.toy.waitUID == court.uid) { XCTFail("t \(t): he walked back onto the court without being in the line (stepped off at \(outAt ?? -1))") }
            }
            if i % 30 == 0, t < 14 { print(String(format: "HKO stepoff t%.1f other d %.2f %@ ign %d | hopper stage %d step %d phaseT %.1f line %d on-court %d", t, court.distance(p), ParkSlideProbe.doing(other.brain), other.brain.decorIgnore ?? -1, hop.brain.idleState.slideStage, hop.brain.idleState.slideStep, hop.brain.idleState.phaseT, line.active ? 1 : 0, hop.brain.hopscotchOthersOn(court).count)) }
        }
        print("HKO stepoff: out at \(String(describing: outAt)) hopper landed on square 1 at \(String(describing: hoppedAt)) max step \(maxStep)")
        XCTAssertNotNil(outAt, "he stepped off the court"); XCTAssertLessThan(outAt ?? 99, 5, "promptly")
        XCTAssertLessThan(maxStep, 0.3, "a walk, not a teleport or a slide")
        XCTAssertNotNil(hoppedAt, "the game was played")
    }

    /// Walks the player asks for (a target in the middle of the court, a target across it) never go on to the court while a game is on, and do not stall for good.
    func testCalledWalksGoRoundTheCourt() {
        HopscotchTuning.guardOn = true; HopscotchTuning.joinChance = 0
        let lab = parkLab(n: 2, seed: 9, starts: [SIMD2(-2.1, -3.2), SIMD2(-0.2, 3.9)], quiet: false)
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

    /// A body who stands in the court's margin when a line starts and rolls "join" is not walked off: he joins (HopscotchTests' three-Jelmiko line has Jelmiko 1 there).
    func testBodyInTheMarginStillJoinsTheLine() {
        HopscotchTuning.guardOn = true; HopscotchTuning.joinChance = 1
        let lab = parkLab(n: 3, seed: 5, starts: [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)])
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        for r in lab.rigs { r.brain.autonomy = true }
        lab.rigs[0].brain.idleForced = true
        XCTAssertTrue(lab.rigs[0].brain.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: court.uid))
        var maxPlayers = 0, landed = Set<Int>()
        for i in 0..<(60 * 160) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            maxPlayers = max(maxPlayers, line.players(court.uid).count)
            for a in 0..<3 where line.square(court.uid, a) >= 0 { landed.insert(a) }
            if i % 120 == 0, i < 60 * 20 { let b = lab.rigs[1].brain; print("HKO join t\(i / 60) rig1 kind \(String(describing: b.idleState.kind)) notice \(b.toy.noticeUID) wait \(b.toy.waitUID) pending \(b.pending != nil) job \(b.job != nil) d \(court.distance(b.position)) ign \(b.decorIgnore ?? -1)") }
            if i > 600, !line.active, lab.rigs.allSatisfy({ $0.brain.idleState.kind == nil }) { break }
        }
        print("HKO join: players at most \(maxPlayers), landed \(landed.sorted())")
        XCTAssertEqual(maxPlayers, 3, "all three joined the line"); XCTAssertEqual(landed, [0, 1, 2], "all three hopped (the one in the margin was not kept out)")
        for sl in 0..<4 { let w = court.centre + court.turned(HopscotchCourt.queueSpot(slot: sl)); print(String(format: "HKO join: queue slot %d spot (%.2f,%.2f) is %.2f from the court's wall box", sl, w.x, w.y, court.distance(w))) }
    }

    /// The line's own route is no wall; a body who quits the line is a bystander on that same tick and is kept out like anyone else.
    func testAQueuedBodyWhoQuitsIsKeptOut() {
        HopscotchTuning.guardOn = true; HopscotchTuning.joinChance = 1
        let lab = parkLab(n: 3, seed: 5, starts: [SIMD2(-2.1, -3.0), SIMD2(0.4, -2.4), SIMD2(-3.0, 4.0)], quiet: false)
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        for r in lab.rigs { r.brain.autonomy = true; r.brain.idleForced = true }
        let a = lab.rigs[0], b = lab.rigs[1], c = lab.rigs[2]
        XCTAssertTrue(a.brain.decorStart(.decorHopscotch, a.sim, only: nil, uid: court.uid))
        XCTAssertTrue(b.brain.decorStart(.decorHopscotch, b.sim, only: nil, uid: court.uid))
        XCTAssertEqual(a.brain.hopPass, court.uid, "a member is on the line's route"); XCTAssertEqual(b.brain.hopPass, court.uid)
        XCTAssertNil(c.brain.hopPass, "a bystander is not")
        let start = court.centre + court.turned(HopscotchCourt.queueSpot(slot: 0))
        func push(_ ign: Int?) -> Float { let q = RoomLayout.resolve(position: SIMD3(start.x, 0, start.y), radius: 0.7, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: ign); return simd_distance(SIMD2(q.x, q.z), start) }
        print(String(format: "HKO quit: the start spot is %.2f from the wall box; push for a bystander %.2f, for a member %.2f", court.distance(start), push(nil), push(a.brain.hopPass)))
        XCTAssertGreaterThan(push(nil), 0.05, "the start spot is inside the margin for a bystander"); XCTAssertLessThan(push(a.brain.hopPass), 0.01, "and no wall to a member")
        for _ in 0..<(60 * 4) { lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertTrue(line.contains(court.uid, 1), "he is in the line")
        b.brain.abortAll(b.sim, b.skinner)          // (he quits)
        XCTAssertFalse(line.contains(court.uid, 1)); XCTAssertNil(b.brain.hopPass, "a bystander on the same tick")
        XCTAssertTrue(line.active, "the game goes on")
        b.brain.autonomy = false
        b.brain.requestNow(.goTo(court.centre))
        var least: Float = 9
        for _ in 0..<(60 * 10) where line.active {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            least = min(least, court.distance(GameCare.floorPos(b.brain, b.sim)))
        }
        print(String(format: "HKO quit: after quitting the least distance to the court was %.2f", least))
        XCTAssertGreaterThan(least, Self.margin - 0.15, "the one who quit was kept out")
    }

    /// A body 0.45 m from the court's edge joins the line within the base time (+10 %): the same seeds with the guard off, and on.
    func joinTime(seed: UInt64, guardOn: Bool) -> Float? {
        HopscotchTuning.guardOn = guardOn; HopscotchTuning.joinChance = 1
        let lab = parkLab(n: 3, seed: seed, starts: [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)])
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        for r in lab.rigs { r.brain.autonomy = true }
        lab.rigs[0].brain.idleForced = true
        _ = lab.rigs[0].brain.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: court.uid)
        var found: Float?
        var diag = 0, ev: [String] = [], pn = [-2, -2, -2], pw = [-2, -2, -2], pe = [false, false, false], pk = [String](repeating: "", count: 3)
        for i in 0..<(60 * 100) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            if i < 60 * 20 { for k in 1...2 {
                let b = lab.rigs[k].brain
                let kind = String(describing: b.idleState.kind), en = line.contains(court.uid, k)
                if b.toy.noticeUID != pn[k] || b.toy.waitUID != pw[k] || en != pe[k] || kind != pk[k] {
                    ev.append(String(format: "t%.1f rig%d kind %@ notice %d wait %d enrolled %d pending %d job %d at (%.2f,%.2f)", Float(i) / 60, k, kind, b.toy.noticeUID, b.toy.waitUID, en ? 1 : 0, b.pending != nil ? 1 : 0, b.job != nil ? 1 : 0, b.position.x, b.position.y))
                    pn[k] = b.toy.noticeUID; pw[k] = b.toy.waitUID; pe[k] = en; pk[k] = kind
                    if k == 1, guardOn, b.toy.waitUID == court.uid, diag == 0 {          // (he queued: why did his decorStart say no? read-only checks, the wall on and off)
                        diag = 1
                        let keep = b.decorIgnore; b.decorIgnore = court.uid
                        let c = DecorField.shared.foot(court.uid)!
                        func probe(_ tag: String) -> String {
                            let st = b.hopscotchStand(c), ds = b.decorStand(.decorHopscotch, c, from: b.position)
                            var leg = "-"
                            if let ds { leg = String(format: "legClear %d reachable %d dist %.2f peers %@", b.legClear(b.position, ds, margin: b.steerMargin) ? 1 : 0, b.reachable(b.position, ds) ? 1 : 0, c.distance(ds), b.steerPeers().map { String(format: "%d@(%.2f,%.2f)", $0.id, $0.pos.x, $0.pos.y) }.joined(separator: ",")) }
                            return "\(tag): stand \(String(describing: st)) decorStand \(String(describing: ds)) \(leg)"
                        }
                        ev.append("DIAG " + probe("wall on, court soft"))
                        HopscotchTuning.guardOn = false
                        ev.append("DIAG " + probe("wall off"))
                        HopscotchTuning.guardOn = true
                        b.decorIgnore = nil
                        ev.append("DIAG " + probe("wall on, NOT soft (hopPass \(String(describing: b.hopPass)))"))
                        b.decorIgnore = keep
                    }
                }
            } }
            if found == nil, line.contains(court.uid, 1) { found = Float(i) / 60 }
            if i > 600, !line.active, lab.rigs.allSatisfy({ $0.brain.idleState.kind == nil }) { break }
        }
        print("HKO join events guard \(guardOn): \(ev.joined(separator: " | "))")
        for r in lab.rigs { r.brain.abortAll(r.sim, r.skinner) }
        return found
    }
    func testJoinTimeMatchesTheBase() {
        var off: [Float] = [], on: [Float] = []
        for seed: UInt64 in [5, 6, 7, 8] {
            let b = joinTime(seed: seed, guardOn: false), a = joinTime(seed: seed, guardOn: true)
            print("HKO join time seed \(seed): base \(String(describing: b)) guard \(String(describing: a))")
            XCTAssertNotNil(a, "seed \(seed): the body 0.45 m from the court joined")
            if let b, let a { off.append(b); on.append(a) }
        }
        let mo = off.reduce(0, +) / Float(max(off.count, 1)), mn = on.reduce(0, +) / Float(max(on.count, 1))
        print("HKO join time mean: base \(mo) s, guard \(mn) s")
        XCTAssertLessThanOrEqual(mn, mo * 1.1 + 0.2, "within the base time +10 %")
    }

    /// Dead-end sweep: every 0.1 m of the floor within 1.5 m of the court, with a game on, in both orientations: a body standing there has a way out to open floor (hard walls: the floor rules leave a cell alone;
    /// a body inside the wall's box walks out soft). A strip narrower than a body that has no way out is a dead end.
    func deadEnds(aspect: Float) -> [String] {
        let lab = parkLab(n: 1, seed: 3, aspect: aspect)
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!
        HopscotchLine.shared.enroll(court.uid, 99)
        defer { HopscotchLine.shared.remove(court.uid, 99) }
        let fp = lab.rigs[0].brain.footprint, wall = fp * HopscotchTuning.wallReach, h: Float = 0.1
        func disp(_ p: SIMD2<Float>, soft: Bool) -> Float {
            let q = GameCamera.constrain(SIMD3(p.x, 0, p.y), radius: fp, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: soft ? court.uid : nil)
            return simd_distance(SIMD2(q.x, q.z), p)
        }
        func floor(_ p: SIMD2<Float>) -> Bool { GameCamera.roamFloor?.contains(p) ?? false }
        let x0: Float = -7, z0: Float = -4.5, nx = 140, nz = 110
        func pt(_ i: Int, _ j: Int) -> SIMD2<Float> { SIMD2(x0 + Float(i) * h, z0 + Float(j) * h) }
        var hard = [Bool](repeating: false, count: nx * nz)
        for j in 0..<nz { for i in 0..<nx { let p = pt(i, j); hard[j * nx + i] = floor(p) && disp(p, soft: false) < 0.06 } }
        // the open component: flood fill from a cell far from the court
        var comp = [Bool](repeating: false, count: nx * nz)
        var seedCell = -1
        for j in 0..<nz { for i in 0..<nx where hard[j * nx + i] && court.distance(pt(i, j)) > 2.5 { seedCell = j * nx + i; break }; if seedCell >= 0 { break } }
        var stack = [seedCell]; comp[seedCell] = true
        while let c = stack.popLast() {
            let ci = c % nx, cj = c / nx
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { let i = ci + di, j = cj + dj; guard i >= 0, i < nx, j >= 0, j < nz, hard[j * nx + i], !comp[j * nx + i] else { continue }; comp[j * nx + i] = true; stack.append(j * nx + i) }
        }
        var dead: [String] = [], probes = 0
        for j in 1..<(nz - 1) { for i in 1..<(nx - 1) {
            let p = pt(i, j)
            guard floor(p), court.distance(p) < 1.5 else { continue }
            probes += 1
            var ok = comp[j * nx + i]
            if !ok {
                // a BFS from here: hard cells in the open component are the way out; while inside the wall's zone he is soft (walks out of it)
                let inside = court.distance(p) < wall + 0.05
                var seen = Set<Int>([j * nx + i]), q = [j * nx + i]
                while let c = q.popLast(), !ok {
                    let ci = c % nx, cj = c / nx
                    for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                        let a = ci + di, b = cj + dj; guard a >= 0, a < nx, b >= 0, b < nz else { continue }
                        let k = b * nx + a; guard !seen.contains(k) else { continue }
                        if comp[k] { ok = true; break }
                        let pp = pt(a, b)
                        if inside, court.distance(pp) < wall + 0.05, floor(pp), disp(pp, soft: true) < 0.06 { seen.insert(k); q.append(k) }
                    }
                }
            }
            if !ok { dead.append(String(format: "(%.1f,%.1f) d %.2f", p.x, p.y, court.distance(p))) }
        } }
        print("HKO dead ends aspect \(aspect > 1 ? "landscape" : "portrait"): \(probes) probes every 0.1 m within 1.5 m of the court, \(dead.count) without a way out \(dead.prefix(12))")
        return dead
    }
    func testNoDeadEndsAroundTheCourt() {
        HopscotchTuning.guardOn = true
        XCTAssertEqual(deadEnds(aspect: Self.portrait).count, 0, "portrait: a strip with no way out")
        XCTAssertEqual(deadEnds(aspect: 956.0 / 440.0).count, 0, "landscape: a strip with no way out")
    }

    /// A line nobody plays in any more (an entry left behind) does not stay a wall for good: the watchdog drops it after `staleAfter` s; a line with a live member is kept.
    func testALeakedLineIsDropped() {
        HopscotchTuning.guardOn = true; HopscotchTuning.joinChance = 0
        let lab = parkLab(n: 1, seed: 3, starts: [SIMD2(-2.1, -3.0)])
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)!, line = HopscotchLine.shared
        line.enroll(court.uid, 77)          // (nobody ticks as 77)
        XCTAssertTrue(HopscotchTuning.walled)
        for _ in 0..<(60 * 4) { DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertTrue(line.active, "not yet")
        for _ in 0..<(60 * 2) { DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertFalse(line.active, "dropped after the watchdog"); XCTAssertFalse(HopscotchTuning.walled); XCTAssertEqual(HopscotchTuning.lineCount, 0)
        // a live member keeps his line for as long as he plays
        let a = lab.rigs[0]
        a.brain.idleForced = true
        XCTAssertTrue(a.brain.decorStart(.decorHopscotch, a.sim, only: nil, uid: court.uid))
        for _ in 0..<(60 * 12) { lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); XCTAssertTrue(line.active || a.brain.idleState.kind == nil, "a live member's line was dropped") }
        a.brain.abortAll(a.sim, a.skinner)
        XCTAssertFalse(line.active)
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
