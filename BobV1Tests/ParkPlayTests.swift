//
//  ParkPlayTests.swift
//  Round park-play-r1 (Park/ParkPlayTuning.swift): the seesaw is not in the park, the slide and the hopscotch are picked more rarely, more pair and group play, friendship from play.
//  The soak is long and runs only with TEST_RUNNER_PARK_PLAY_SOAK=1 (TEST_RUNNER_PARK_PLAY_SEEDS=n, default 5; TEST_RUNNER_PARK_PLAY_SECONDS=n per run, default 300). Table lines go to MotionLog (TEST_RUNNER_MOTION_LOG).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkPlayTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() {
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        HopscotchLine.shared.prune(keeping: [])
        setSwitches(new: true)
        ParkPlayTuning.stats = .init()
        BlobBrain.pickBudgetSeconds = .infinity
    }
    override func tearDown() {
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        DecorField.shared.clear(); ToyTuning.settle = 5; HopscotchTuning.joinChance = 0.35
        HopscotchLine.shared.prune(keeping: [])
        setSwitches(new: true); ParkPlayTuning.seesawInPark = true          // (under XCTest the seesaw is in, for its own suites)
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }
    /// new = the three park rules on and the seesaw out; old = all off and the seesaw in (`-ParkSeesaw 1 -ParkToyRate old -ParkSocial old`).
    private func setSwitches(new: Bool) { ParkPlayTuning.toyRateNew = new; ParkPlayTuning.socialNew = new; ParkPlayTuning.seesawInPark = !new }

    // MARK: the seesaw is gone

    func testSeesawIsNotPlacedInThePark() {
        ParkPlayTuning.seesawInPark = false
        XCTAssertFalse(ParkToys.placed.contains { $0.kind == .seesaw }, "no seesaw in the park's list")
        XCTAssertFalse(ParkVisitPlan.placedToday.contains { $0.kind == .seesaw })
        XCTAssertTrue(ParkToys.placed.contains { $0.kind == .hopscotch }); XCTAssertTrue(ParkToys.placed.contains { $0.kind == .slide }, "the slide and the hopscotch stay")
        DecorField.shared.set(ParkVisitPlan.placedToday)
        XCTAssertFalse(DecorField.shared.feet.contains { $0.kind == .seesaw }, "nothing in the field offers it")
        XCTAssertFalse(BlobBrain.decorOffers().contains(where: { _ in DecorField.shared.feet.contains { $0.kind == .seesaw } }))
        ParkPlayTuning.seesawInPark = true
        XCTAssertTrue(ParkToys.placed.contains { $0.kind == .seesaw }, "-ParkSeesaw 1 (and every test run) has it")
    }

    // MARK: the gate

    func testGateIsOpenAtHomeAndForCommandedAndTheOldSwitchAndRollsOtherwise() {
        let lab = SocialTests.Lab(n: 1, positions: [SIMD2(0, 0)], quiet: true, seed: 1)
        Self.keep.append(lab)
        DecorField.shared.set(ParkToys.placed.filter { $0.kind == .slide || $0.kind == .hopscotch })
        let b = lab.rigs[0].brain
        let slide = DecorField.shared.foot(ParkToys.slideUID)!, hop = DecorField.shared.foot(ParkToys.hopscotchUID)!
        b.outingPlay = false
        for _ in 0..<50 { XCTAssertTrue(b.parkToyGate(slide)); XCTAssertTrue(b.parkToyGate(hop)) }
        b.outingPlay = true; b.commanded = true
        for _ in 0..<50 { XCTAssertTrue(b.parkToyGate(slide), "commanded: never rolled") }
        b.commanded = false
        ParkPlayTuning.toyRateNew = false
        for _ in 0..<50 { XCTAssertTrue(b.parkToyGate(slide), "old switch") }
        ParkPlayTuning.toyRateNew = true
        // (a "no" holds the toy off: count first rolls on fresh brains' cooldown state)
        var yes = 0
        for _ in 0..<1000 { b.toy.parkCool = [:]; if b.parkToyGate(slide) { yes += 1 } }
        XCTAssertEqual(Float(yes) / 1000, ParkPlayTuning.slidePickChance, accuracy: 0.06)
        b.toy.parkCool = [:]; b.parkToyUsed(.slide)
        for _ in 0..<50 { XCTAssertFalse(b.parkToyGate(slide), "right after a use: the cooldown") }
        b.toy.parkCool = [:]
        HopscotchLine.shared.prune(keeping: [])
    }

    /// The room is untouched: with `outingPlay` off every park hook is a pass-through and draws no random number, whatever the switches are (a repeat room soak is not repeatable even old against old, see ParkPairs notes).
    func testRoomHooksAreInertAtHome() {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(0, 0), SIMD2(1.5, 0)], quiet: true, seed: 3)
        Self.keep.append(lab)
        DecorField.shared.set(ParkToys.placed.filter { $0.kind == .slide || $0.kind == .hopscotch })
        let b = lab.rigs[0].brain
        b.outingPlay = false
        for new in [false, true] {
            setSwitches(new: new)
            XCTAssertEqual(b.parkSocialPickMul, 1); XCTAssertEqual(b.parkSocialWaitMul, 1); XCTAssertFalse(b.parkSocialOn)
            let before = b.seed
            for f in DecorField.shared.feet { XCTAssertTrue(b.parkToyGate(f)) }
            XCTAssertEqual(b.seed, before, "the gate drew no random number at home")
        }
        XCTAssertTrue(b.toy.parkCool.isEmpty)
    }

    // MARK: the soak

    struct Run {
        var slide = 0, hop = 0, see = 0, pairS = 0, groupS = 0
        var slideSec: Float = 0, hopSec: Float = 0, seeSec: Float = 0, idleSec: Float = 0, friend: Float = 0
    }
    /// Home creatures = the first `homes` rigs, the rest strangers (closeness 0.55 both ways, as a first visit).
    private func soak(homes: Int, n: Int, seconds: Float, seed: UInt64, new: Bool) -> Run {
        setSwitches(new: new)
        ParkPlayTuning.stats = .init()
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: []); SeesawRide.shared.reset()
        HopscotchTuning.joinChance = ParkPlayTuning.hopscotchJoin
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let pts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(1.6, 1.2), SIMD2(-1.6, 1.6)]
        let lab = SocialTests.Lab(n: n, positions: Array(pts.prefix(n)), quiet: false, seed: seed)
        Self.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(k % 5)
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            for (j, o) in lab.rigs.enumerated() where o !== r && (j >= homes || k >= homes) { r.brain.socialBook.close[o.brain.steerID] = 0.55 }
        }
        WearBody.install(MotionRig.renderMesh)
        let field = DecorField.shared
        field.set(ParkVisitPlan.placedToday); field.toys.news.removeAll()
        var out = Run(), prev = [IdleKind?](repeating: nil, count: n), seen = Set<ObjectIdentifier>(), keepAlive: [SocialSession] = [], lastSession = [ObjectIdentifier?](repeating: nil, count: homes)
        let dt: Float = 1.0 / 60
        for _ in 0..<Int(seconds * 60) {
            lab.tick(watching: false); field.tick(dt: dt)
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain, now = b.idleState.kind
                let onSee = now == .decorSit && field.foot(b.idleState.decorUID)?.kind == .seesaw
                if prev[i] != now {
                    if now == .decorSlide { out.slide += 1 }
                    if now == .decorHopscotch { out.hop += 1 }
                    if onSee { out.see += 1 }
                }
                prev[i] = now
                if now == .decorSlide { out.slideSec += dt } else if now == .decorHopscotch { out.hopSec += dt } else if onSee { out.seeSec += dt }
                if i < homes, now == nil, b.scriptIsNone, b.social == nil, b.activity != .walking { out.idleSec += dt }
                if let s = b.social, !seen.contains(ObjectIdentifier(s)) { seen.insert(ObjectIdentifier(s)); keepAlive.append(s);          // (kept alive: a freed session's address is reused by the next one and would not count)
                    if s.kind.isGroup { out.groupS += 1 } else { out.pairS += 1 } }
            }
            for h in 0..<homes {
                for v in homes..<n where simd_distance(lab.rigs[h].brain.position, lab.rigs[v].brain.position) < ParkTuning.nearRadius {
                    var rate = ParkTuning.pointsPerSecond * dt
                    if let s = lab.rigs[h].brain.social, s.involves(lab.rigs[v].brain.steerID) {          // (the park's own rule, GameCare+Park tickFriends)
                        if s.kind.isFriendly, s.end == nil { rate *= ParkTuning.friendlyMul; if lastSession[h] != ObjectIdentifier(s) { lastSession[h] = ObjectIdentifier(s); out.friend += ParkTuning.friendlyStartBonus } }
                        else { rate *= ParkTuning.socialMul }
                    }
                    out.friend += rate
                }
            }
        }
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        field.clear(); HopscotchLine.shared.prune(keeping: [])
        setSwitches(new: true)
        return out
    }

    private func med(_ v: [Float]) -> Float { let s = v.sorted(); return s.isEmpty ? 0 : (s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2) }
    private func cell(_ v: [Float], per: Float) -> String { String(format: "%.1f (%.1f-%.1f)", med(v) * per, (v.min() ?? 0) * per, (v.max() ?? 0) * per) }

    /// Old arm (switches old, seesaw in) against new, the same seeds, one and two home creatures plus the park's visitors. Per 5 minutes; medians with (min-max) over the seeds.
    func testParkSoakOldVersusNew() throws {
        guard ProcessInfo.processInfo.environment["PARK_PLAY_SOAK"] != nil else { throw XCTSkip("set TEST_RUNNER_PARK_PLAY_SOAK=1 to run the soak") }
        let seconds = Float(ProcessInfo.processInfo.environment["PARK_PLAY_SECONDS"].flatMap { Float($0) } ?? 300)
        let seedCount = ProcessInfo.processInfo.environment["PARK_PLAY_SEEDS"].flatMap { Int($0) } ?? 5
        let seeds: [UInt64] = (0..<seedCount).map { 41 + 7 * UInt64($0) }
        let per = 300 / seconds
        for (label, homes, n) in [("1 home + 3 visitors", 1, 4), ("2 home + 3 visitors", 2, 5)] {
            var o: [Run] = [], w: [Run] = []
            let onlyNew = ProcessInfo.processInfo.environment["PARK_PLAY_ONLY_NEW"] != nil          // (the old arm of a tuning run is the same as the last full run's: skip it)
            for s in seeds {
                if !onlyNew { o.append(soak(homes: homes, n: n, seconds: seconds, seed: s, new: false)) }
                w.append(soak(homes: homes, n: n, seconds: seconds, seed: s, new: true))
                MotionLog.write("PLAY SOAK \(label) seed \(s): old \(o.last.map { "\($0)" } ?? "-") | new \(w.last!)")
            }
            if onlyNew { for name in ["slide rides", "hopscotch runs", "pair interactions", "group interactions", "friendship"] { _ = name }
                func r(_ f: (Run) -> Float) -> String { cell(w.map(f), per: per) }
                MotionLog.write("PLAY NEWONLY \(label) | slide \(r { Float($0.slide) }) | hop runs \(r { Float($0.hop) }) | hop s \(r { $0.hopSec }) | pair \(r { Float($0.pairS) }) | group \(r { Float($0.groupS) }) | idle s \(r { $0.idleSec / Float(homes) }) | friend \(r { $0.friend }) | seesaw \(r { Float($0.see) })")
                XCTAssertEqual(w.map(\.see).max() ?? 0, 0); continue }
            func row(_ name: String, _ f: (Run) -> Float) { MotionLog.write("PLAY TABLE \(label) | \(name) | old \(cell(o.map(f), per: per)) | new \(cell(w.map(f), per: per)) | new/old of medians \(med(o.map(f)) > 0 ? String(format: "%.2f", med(w.map(f)) / med(o.map(f))) : "-")") }
            row("slide rides", { Float($0.slide) }); row("slide seconds", { $0.slideSec })
            row("hopscotch runs", { Float($0.hop) }); row("hopscotch seconds", { $0.hopSec })
            row("seesaw rides", { Float($0.see) }); row("seesaw seconds", { $0.seeSec })
            row("pair interactions", { Float($0.pairS) }); row("group interactions", { Float($0.groupS) })
            row("home creature doing nothing (s, per home creature)", { $0.idleSec / Float(homes) }); row("friendship points gained (all home creatures)", { $0.friend })
            XCTAssertEqual(w.map(\.see).max() ?? 0, 0, "\(label): no seesaw ride with the new arm")
            let toysOld = med(o.map { Float($0.slide + $0.hop) }), toysNew = med(w.map { Float($0.slide + $0.hop) })
            if toysOld >= 4 { XCTAssertLessThanOrEqual(toysNew / toysOld, 0.6, "\(label): slide + hopscotch used about half or less (\(toysNew) / \(toysOld))") }
            let intOld = med(o.map { Float($0.pairS + $0.groupS) }), intNew = med(w.map { Float($0.pairS + $0.groupS) })
            if intOld >= 4 { XCTAssertGreaterThanOrEqual(intNew / intOld, 1.4, "\(label): interactions at least about 1.5x (\(intNew) / \(intOld))") }
            XCTAssertLessThanOrEqual(med(w.map(\.idleSec)), med(o.map(\.idleSec)) * 1.15 + 3, "\(label): idle time not up")
            XCTAssertGreaterThanOrEqual(med(w.map(\.friend)), med(o.map(\.friend)), "\(label): friendship gain up")
        }
    }
}
