//
//  GroupEmoteFeetTests.swift
//  The three group emotes (2026-11-02: highFive, congaLine, ringDance; BlobSocial+Friends / +Emotes) with the SAME feet invariant as EmoteFeetTests, for every participant:
//    leash    the skin's leash / tether never moves a foot piece (Skinner.leashObserver, any rig, any frame);
//    ring     with both pieces off the floor, the piece's ring 2 under the top is >= 70 % of the standing boot's;
//    join     with both pieces off the floor, every neck meridian has a point inside the drawn body by >= 1 cm;
//    collar   with both pieces off the floor, the collar moves no skin more than 2 cm;
//  plus the social layer's own all-frames checks (SocialTests.Watch: FeetAttach + ArmCap, i.e. the W1d short arms), and nobody inside anybody.
//  Three rigs (a Lab, wired as the stage), characters rotated so every character takes part, bare and with shoes. The first bad frame is named in the message.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class GroupEmoteFeetTests: XCTestCase {
    override func setUp() { super.setUp(); Self.reset() }
    override func tearDown() { Self.reset(); super.tearDown() }
    static func reset() {
        EmoteFeetTests.reset()
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
    }
    static let out = EmoteFeetTests.out

    /// Three characters per run; together the runs cover all six, bare and with shoes.
    static let casts: [[Int]] = [[0, 1, 2], [3, 4, 5], [5, 2, 4]]

    struct Result { var frames = 0, completed = false, seconds: Float = 0, minGap: Float = .infinity, minGapTag = "", leashFrames = 0, airFrames = 0
        var ratio: Float = .infinity, join: Float = .infinity, collar: Float = 0, bad = "" }

    /// Runs `kind` (started by rig 0 with rig 1) to its end; every frame checked.
    func run(_ kind: SocialKind, cast: [Int], shoes: Bool, n: Int = 3, seed: UInt64 = 31, maxSeconds: Float = 70) -> Result {
        _ = OnePieceInvariantTests.configured
        let lab = SocialTests.Lab(n: n, positions: Array(SocialTests.starts.prefix(n)), seed: seed)
        var res = Result()
        for (i, r) in lab.rigs.enumerated() {
            r.brain.anticsEnabled = true
            r.brain.feature = OnePieceInvariantTests.characters[cast[i % cast.count]].1
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            r.brain.shoesWorn = shoes
        }
        var hit = 0, firstHit = -1, maxPull: Float = 0, frame = 0
        Skinner.leashObserver = { _, pull, _ in hit += 1; if firstHit < 0 { firstHit = frame }; maxPull = max(maxPull, pull) }
        defer { Skinner.leashObserver = nil }
        let who = "\(kind.rawValue) x\(n), cast \(cast.map { OnePieceInvariantTests.characters[$0].0 }) \(shoes ? "with shoes" : "bare")"
        XCTAssertTrue(lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim), "\(who): starts")
        while frame < Int(maxSeconds * 60) {
            lab.tick(watching: true)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            for (i, r) in lab.rigs.enumerated() {
                guard let s = EmoteFeetTests.sample(r, frame: frame) else { continue }
                res.airFrames += 1
                if res.bad.isEmpty, s.ratio < EmoteFeetTests.minRatio || s.join < OnePieceInvariantTests.minNeck || s.collar > EmoteFeetTests.maxCollar { res.bad = "rig \(i) frame \(frame): ratio \(s.ratio) join \(s.join * 100) cm collar \(s.collar * 100) cm (\(s.info))" }
                res.ratio = min(res.ratio, s.ratio); res.join = min(res.join, s.join); res.collar = max(res.collar, s.collar)
            }
            // nobody inside anybody (the whole run, the session and the walks round it)
            for i in 0..<n { for j in (i + 1)..<n {
                let g = lab.centreGap(i, j)
                if g < res.minGap { res.minGap = g; res.minGapTag = "t \(Float(frame) / 60) \(i)-\(j) social \(String(describing: lab.rigs[i].brain.socialKind)) phase \(lab.rigs[i].brain.social?.phase ?? -1)" }
            } }
            frame += 1
            if !lab.anySocial && frame > 10 { res.completed = true; break }
        }
        res.frames = frame; res.seconds = Float(frame) / 60; res.leashFrames = hit
        XCTAssertTrue(res.completed, "\(who): completes (\(res.seconds) s)")
        XCTAssertEqual(hit, 0, "\(who): the skin's leash / tether moved a foot piece in \(hit) frames, first at frame \(firstHit), max pull \(String(format: "%.1f", maxPull * 100)) cm")
        if res.airFrames > 0 {
            XCTAssertGreaterThanOrEqual(res.ratio, EmoteFeetTests.minRatio, "\(who): neck ring shrank to \(res.ratio * 100) %: \(res.bad)")
            XCTAssertGreaterThanOrEqual(res.join, OnePieceInvariantTests.minNeck, "\(who): the join is open by \(-res.join * 100) cm: \(res.bad)")
            XCTAssertLessThanOrEqual(res.collar, EmoteFeetTests.maxCollar, "\(who): the collar moved skin \(res.collar * 100) cm: \(res.bad)")
        }
        lab.checkAll(who, plainBound: 0.03)
        let line = String(format: "GROUPEMOTE %@ | %.1f s | air frames %d | min ring ratio %.2f | min join %.1f cm | max collar %.1f cm | leash frames %d | min centre gap %.2f (%@)", who, res.seconds, res.airFrames, res.ratio, res.join * 100, res.collar * 100, hit, res.minGap, res.minGapTag)
        MotionLog.write(line)
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        if let h = FileHandle(forWritingAtPath: Self.out + "group_emotes.txt") { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() } else { try? (line + "\n").write(toFile: Self.out + "group_emotes.txt", atomically: true, encoding: .utf8) }
        return res
    }

    private func all(_ kind: SocialKind, minSeconds: Float, minGapFactor: Float = 0.66) {
        for cast in Self.casts { for shoes in [false, true] {
            let r = run(kind, cast: cast, shoes: shoes)
            XCTAssertGreaterThan(r.seconds, minSeconds, "\(kind) takes a while")
            // bodies never overlap visibly: neighbours keep >= the close-social gap (0.74 x the room gap) less a hair (contact at the close gap is fine)
            XCTAssertGreaterThanOrEqual(r.minGap, MelonController.jellyGap * minGapFactor - 0.04, "\(kind): two bodies came to \(r.minGap) (\(r.minGapTag))")
        } }
    }

    func testHighFiveKeepsFeetAndArms() { all(.highFive, minSeconds: 3, minGapFactor: 0.62) }
    func testCongaLineKeepsFeetAndArms() { all(.congaLine, minSeconds: 8) }
    func testRingDanceKeepsFeetAndArms() { all(.ringDance, minSeconds: 8) }
    func testCongaLineOfTwo() { _ = run(.congaLine, cast: [0, 3], shoes: false, n: 2); _ = run(.congaLine, cast: [4, 1], shoes: true, n: 2) }
}
