//
//  GroupCalmTests.swift
//  The seven calm group emotes (BlobSocial+GroupCalm.swift): each starts with the right number of bodies, runs, ends with everybody free; a cancel mid-way leaves nobody scripted; the evening
//  kinds start only at night and awake and never delay bedtime; the calm kinds are ~60 % of the group picks. The per-kind feet runs (every species, bare and with shoes) are the
//  `testCalm...` methods at the bottom, an extension of SocialFeetTests (its `run`, run ONE kind per xcodebuild: -only-testing:BobV1Tests/SocialFeetTests/testCalmRowWave).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class GroupCalmTests: XCTestCase {
    override func setUp() { super.setUp(); GroupEmoteFeetTests.reset() }
    override func tearDown() { GroupEmoteFeetTests.reset(); super.tearDown() }

    static let kinds: [(SocialKind, [Int], Bool)] = [          // (kind, body counts it is run with, evening only)
        (.rowWave, [3, 5], false), (.singAlong, [2, 3, 5], false), (.storyTime, [3, 5], false), (.lookAtThat, [2, 3, 5], false),
        (.sitCircle, [3, 5], false), (.stargazeTogether, [2, 3], true), (.yawnChain, [2, 3, 5], true),
    ]

    /// The neck join of one rig on ANY frame with the feet blended in (planted ones too: EmoteFeetTests.sample only reads frames with both pieces in the air, which a sit / a wave never has).
    static func joinAny(_ r: MotionRig) -> Float? {
        guard r.skinner.beansActive, r.skinner.beanBlend > 0.9 else { return nil }
        let pose = r.sim.bodyPose(iterations: 4)
        let fp = (centroid: pose.centroid, rotation: pose.rotation, restCentroid: r.sim.restCentroid)
        let A = EmoteFeetTests.A
        var join = Float.infinity
        r.dyn.withUnsafeBufferPointer { d in
            @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
            for k in 0..<2 {
                let first = Int(r.bean[k][0])
                for j in 0..<A {
                    var best = -Float.infinity
                    for ring in 10..<FootBean.rings { best = max(best, Skinner.fittedDepth(P(first + 1 + A * ring + j), fp).0) }
                    join = min(join, best)
                }
            }
        }
        return join
    }

    func lab(_ n: Int, night: Bool, seed: UInt64 = 31) -> SocialTests.Lab {
        let l = SocialTests.Lab(n: n, positions: n == 2 ? [SIMD2(-0.7, 0.6), SIMD2(0.9, 0.9)] : (n == 3 ? SocialTests.starts : GroupSocialTests.five), seed: seed)
        for r in l.rigs { r.brain.anticsEnabled = true; if night { r.brain.idleNight = 1 } }
        return l
    }
    func start(_ l: SocialTests.Lab, _ kind: SocialKind) -> Bool {
        l.rigs[0].brain.socialStartGroup(kind, with: l.rigs.dropFirst().map { $0.brain }, l.rigs[0].sim)
    }
    func assertFree(_ l: SocialTests.Lab, _ why: String) {
        for (i, r) in l.rigs.enumerated() {
            let b = r.brain
            XCTAssertNil(b.social, "\(why): rig \(i) still in a session")
            XCTAssertNil(b.idleState.kind, "\(why): rig \(i) still in idle \(String(describing: b.idleState.kind))")
            XCTAssertTrue(b.scriptIsNone, "\(why): rig \(i) still scripted \(b.script)")
            XCTAssertFalse(b.socialBook.hold, "\(why): rig \(i) hold left on")
            XCTAssertEqual(b.socialBook.pitch, 0, accuracy: 0.02, "\(why): rig \(i) pitch left on"); XCTAssertEqual(b.socialBook.roll, 0, accuracy: 0.02, "\(why): rig \(i) roll left on")
            XCTAssertEqual(b.socialBook.squash, 1, accuracy: 0.02, "\(why): rig \(i) squash left on"); XCTAssertFalse(b.socialBook.passThrough)
        }
    }
    /// No autonomous follow-up (a new group, a zoomies) muddies what the cancel / the end left behind.
    func quiet(_ l: SocialTests.Lab) { for r in l.rigs { r.brain.socialBook.groupCool = 1e6; r.brain.socialBook.cooldown = 1e6; r.brain.socialBook.treatCool = 1e6; r.brain.idleState.cooldown = 1e6; r.brain.restTimer = 1e6 } }
    func settle(_ l: SocialTests.Lab, seconds: Float = 8) { for _ in 0..<5 { l.tick() }; quiet(l); for _ in 0..<Int(seconds * 60) { l.tick() } }

    // MARK: start, run, end

    func testEachKindStartsWithTheRightBodiesRunsAndEndsFree() {
        for (kind, counts, night) in Self.kinds {
            for n in counts {
                let l = lab(n, night: night)
                XCTAssertTrue(start(l, kind), "\(kind) x\(n): starts")
                guard l.rigs.allSatisfy({ $0.brain.isSocial }) else { XCTFail("\(kind) x\(n): not everybody is in"); continue }
                XCTAssertEqual(l.rigs[0].brain.social?.crewIDs.count, n, "\(kind) x\(n): the crew is everybody")
                XCTAssertEqual(l.rigs[0].brain.socialKind, kind)
                var f = 0
                while f < 60 * 45 { l.tick(); f += 1; if !l.anySocial && f > 10 { break } }
                XCTAssertFalse(l.anySocial, "\(kind) x\(n): ends (\(Float(f) / 60) s)")
                XCTAssertGreaterThan(Float(f) / 60, 5, "\(kind) x\(n): takes a while (\(Float(f) / 60) s)")
                XCTAssertLessThan(Float(f) / 60, 26, "\(kind) x\(n): not too long (\(Float(f) / 60) s)")
                XCTAssertTrue(l.events[0].contains { if case .ended(let k, _, let how) = $0, k == kind { return how == .done }; return false }, "\(kind) x\(n): ends happily")
                MotionLog.write(String(format: "GROUPCALM %@ x%d completed in %.1f s", kind.rawValue, n, Float(f) / 60))
                settle(l); assertFree(l, "\(kind) x\(n) after the end")
                l.checkAll("calm \(kind) x\(n)", plainBound: 0.03)
            }
        }
    }

    func testThreePlusKindsNeedThree() {
        for kind in [SocialKind.rowWave, .storyTime, .sitCircle] {
            let l = lab(2, night: true)
            XCTAssertFalse(start(l, kind), "\(kind): two are not enough")
            XCTAssertFalse(l.anySocial)
        }
    }

    // MARK: cancel

    func testCancelMidWayLeavesNoOneScripted() {
        for (kind, _, night) in Self.kinds {
            for (secs, how) in [(2.0, 0), (5.5, 1), (8.0, 0)] as [(Double, Int)] {
                let l = lab(3, night: night)
                XCTAssertTrue(start(l, kind), "\(kind): starts")
                for _ in 0..<Int(secs * 60) { l.tick() }
                if how == 0 { for _ in 0..<5 { l.rigs[2].tick(touched: true); l.rigs[0].tick(); l.rigs[1].tick() } }          // the player touches one
                else { l.rigs[1].brain.stop() }          // the voice "stop"
                settle(l, seconds: 10)
                XCTAssertFalse(l.anySocial, "\(kind) cut at \(secs) s (\(how == 0 ? "touch" : "stop")): the session is over")
                assertFree(l, "\(kind) cut at \(secs) s (\(how == 0 ? "touch" : "stop"))")
            }
        }
    }

    // MARK: the evening kinds

    func testEveningKindsOnlyAtNightAndAwake() {
        for kind in [SocialKind.stargazeTogether, .yawnChain] {
            let day = lab(3, night: false)
            XCTAssertFalse(start(day, kind), "\(kind): not by day")
            let deep = lab(3, night: true)
            for r in deep.rigs { r.brain.idleDeepNight = 1 }
            XCTAssertFalse(start(deep, kind), "\(kind): not in the deep night (bedtime)")
            let oneAsleep = lab(3, night: true)
            _ = oneAsleep.rigs[2].brain.idleStart(.sleep, oneAsleep.rigs[2].sim)
            for _ in 0..<30 { oneAsleep.tick() }
            _ = start(oneAsleep, kind)
            XCTAssertFalse(oneAsleep.rigs[2].brain.isSocial, "\(kind): a sleeper is never pulled in")
            let night = lab(3, night: true)
            XCTAssertTrue(start(night, kind), "\(kind): at night, awake")
        }
        // the yawn chain also by evening (the night factor 0.4), the stargaze not
        let evening = lab(3, night: false)
        for r in evening.rigs { r.brain.idleNight = 0.4 }
        XCTAssertFalse(start(evening, .stargazeTogether), "stargaze: needs a real night")
        XCTAssertTrue(start(evening, .yawnChain), "yawn chain: the evening is enough")
    }

    func testDeepNightEndsItAtOnceAndNobodyStaysDown() {
        for kind in [SocialKind.stargazeTogether, .yawnChain, .singAlong] {
            let l = lab(3, night: true)
            XCTAssertTrue(start(l, kind))
            for _ in 0..<(60 * 5) { l.tick() }
            for r in l.rigs { r.brain.idleDeepNight = 1 }          // bedtime
            for _ in 0..<(60 * 2) { l.tick() }
            XCTAssertFalse(l.anySocial, "\(kind): over within 2 s of the deep night")
            settle(l, seconds: 6)
            for (i, r) in l.rigs.enumerated() { XCTAssertNil(r.brain.idleState.kind, "\(kind): rig \(i) is up again (\(String(describing: r.brain.idleState.kind)))") }
        }
    }

    // MARK: the table

    func testCalmKindsAreSixtyPercentOfTheTableWhateverItsWeights() {
        let l = lab(3, night: true)
        let me = l.rigs[0].brain, crew = [l.rigs[1].brain, l.rigs[2].brain]
        let tables: [[(SocialKind, Float)]] = [[(.groupHug, 14), (.groupCheer, 3), (.conga, 2.7), (.circleDance, 3)], [(.groupHug, 5), (.groupCheer, 3), (.conga, 2.7), (.circleDance, 3)]]
        for table in tables {
            for night: Float in [0, 0.45, 1] {
                for r in l.rigs { r.brain.idleNight = night }
                var w = table
                me.calmAppend(&w, crew: crew)
                let calm = w.filter { $0.0.isCalmGroup }.reduce(0) { $0 + $1.1 }, all = w.reduce(0) { $0 + $1.1 }
                XCTAssertEqual(calm / all, 0.6, accuracy: 0.001, "night \(night): calm share")
                let names = Set(w.filter { $0.0.isCalmGroup }.map { $0.0 })
                XCTAssertEqual(names.contains(.stargazeTogether), night > 0.6, "stargaze only at night (night \(night))")
                XCTAssertEqual(names.contains(.yawnChain), night > 0.3, "yawn chain only in the evening / night (night \(night))")
                MotionLog.write("GROUPCALM table hug \(table[0].1) night \(night): " + w.filter { $0.0.isCalmGroup }.map { String(format: "%@ %.1f%%", $0.0.rawValue, $0.1 / all * 100) }.joined(separator: ", "))
            }
        }
    }
}

// MARK: - the per-kind feet runs (SocialFeetTests' run: leash, attach / float, skating, the air-only join, plus the join on every frame)

extension SocialFeetTests {
    /// Seven species over four casts (Panda too), each bare and with shoes.
    static let calmCasts: [(String, [Int])] = [("Bob+Pip+Moss", [0, 1, 2]), ("Lavender+Teddy+Pearl", [3, 4, 5]), ("Panda+Moss+Teddy", [6, 2, 4]), ("Pearl+Panda+Pip", [5, 6, 1])]
    static let calmOut = ProcessInfo.processInfo.environment["GROUPCALM_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/groupcalm/"

    func calm(_ kind: SocialKind) {
        let night = kind == .stargazeTogether || kind == .yawnChain
        var worstJoin = Float.infinity, worstTag = ""
        try? FileManager.default.createDirectory(atPath: Self.calmOut, withIntermediateDirectories: true)
        for (label, cast) in Self.calmCasts {
            for shoes in [false, true] {
                let r = run(kind.rawValue, .social(kind), cast: cast, castName: label + (shoes ? " shoes" : " bare"), maxSec: 45, prepare: { d in
                    for rg in d.lab.rigs { rg.brain.shoesWorn = shoes; if night { rg.brain.idleNight = 1 } }
                })
                if r.joinAny < worstJoin { worstJoin = r.joinAny; worstTag = "\(label) \(shoes ? "shoes" : "bare")" }
                XCTAssertGreaterThanOrEqual(r.joinAny, OnePieceInvariantTests.minNeck, "\(kind) [\(label) \(shoes ? "shoes" : "bare")]: the neck join on a planted / any frame is open by \(-r.joinAny * 100) cm")
                let line = String(format: "GROUPCALMFEET %@ | %@ %@ | %.1f s | air frames %d | joinAny %.1f cm over %d frames | air join %.1f cm | leash %d | attach overlap %.3f soleRise %.3f centre %.3f | skate worst %.1f mm", kind.rawValue, label, shoes ? "shoes" : "bare", r.seconds, r.air, r.joinAny * 100, r.joinAnyFrames, r.join * 100, r.leash, r.overlap, r.soleRise, r.centre, r.skate.worst * 1000)
                if let h = FileHandle(forWritingAtPath: Self.calmOut + "feet_\(kind.rawValue).txt") { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() } else { try? (line + "\n").write(toFile: Self.calmOut + "feet_\(kind.rawValue).txt", atomically: true, encoding: .utf8) }
                MotionLog.write(line)
            }
        }
        let l = String(format: "GROUPCALMFEET WORST %@ | joinAny %.1f cm at %@\n", kind.rawValue, worstJoin * 100, worstTag)
        if let h = FileHandle(forWritingAtPath: Self.calmOut + "feet_\(kind.rawValue).txt") { h.seekToEndOfFile(); h.write(Data(l.utf8)); try? h.close() }
        MotionLog.write(l)
    }
    func testCalmRowWave() { calm(.rowWave) }
    func testCalmSingAlong() { calm(.singAlong) }
    func testCalmStoryTime() { calm(.storyTime) }
    func testCalmLookAtThat() { calm(.lookAtThat) }
    func testCalmSitCircle() { calm(.sitCircle) }
    func testCalmStargazeTogether() { calm(.stargazeTogether) }
    func testCalmYawnChain() { calm(.yawnChain) }
}
