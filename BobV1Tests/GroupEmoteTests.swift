//
//  GroupEmoteTests.swift
//  The group emotes' behaviour (BlobSocial+Emotes / +Friends): the haptic pattern of each (counted like the SFX requests), a touch / voice stop / request aborts the session and releases everybody,
//  the per-pair high-five cooldown and the treat cooldown, and nothing starts while somebody is busy.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class GroupEmoteTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { EmoteHaptic.requestTap = nil; RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func lab(n: Int = 3) -> SocialTests.Lab {
        let l = SocialTests.Lab(n: n, positions: Array(SocialTests.starts.prefix(n)), seed: 31)
        for r in l.rigs { r.brain.anticsEnabled = true }
        return l
    }

    func testHapticPatternPerEmote() {
        let expect: [SocialKind: [String]] = [.highFive: ["highFive.bump"], .congaLine: ["congaLine.form", "congaLine.scatter"], .ringDance: ["ringDance.form", "ringDance.scatter"]]
        for (kind, want) in expect {
            var got: [String] = []
            EmoteHaptic.requestTap = { got.append($0) }
            let l = lab()
            XCTAssertTrue(l.rigs[0].brain.socialStart(kind, with: l.rigs[1].brain, l.rigs[0].sim), "\(kind) starts")
            var f = 0
            while f < 60 * 60 { l.tick(); f += 1; if !l.anySocial && f > 10 { break } }
            XCTAssertEqual(got, want, "\(kind): haptic requests")
        }
    }

    /// The jelly bump: no arm raise at all (no wave script on either), the one haptic tap, and both end upright.
    func testHighFiveIsABumpNotAnArmRaise() {
        var got: [String] = []
        EmoteHaptic.requestTap = { got.append($0) }
        let l = lab()
        XCTAssertTrue(l.rigs[0].brain.socialStart(.highFive, with: l.rigs[1].brain, l.rigs[0].sim))
        var f = 0, wave = 0
        while f < 60 * 40 {
            l.tick(); f += 1
            for r in l.rigs[0...1] { if case .wave = r.brain.script { wave += 1 } }
            if !l.anySocial && f > 10 { break }
        }
        XCTAssertEqual(wave, 0, "no arm raise during the high five")
        XCTAssertEqual(got, ["highFive.bump"])
        for r in l.rigs { XCTAssertEqual(r.brain.socialBook.roll, 0, accuracy: 0.05, "upright again") }
    }

    /// A touch on any member, a voice "stop" and a request each end the session at once and release everybody (nobody keeps walking the line, no overlay is left).
    func testInterruptionReleasesEveryone() {
        for kind in [SocialKind.highFive, .congaLine, .ringDance] {
            for how in ["touch", "stop", "request"] {
                let l = lab()
                XCTAssertTrue(l.rigs[0].brain.socialStart(kind, with: l.rigs[1].brain, l.rigs[0].sim), "\(kind) starts")
                var f = 0
                let wait = kind == .highFive ? 60 * 3 : (kind == .congaLine ? 60 * 6 : 60 * 5)
                while f < wait { l.tick(); f += 1 }
                XCTAssertTrue(l.anySocial, "\(kind): still on before the interruption (\(how))")
                switch how {
                case "touch": for _ in 0..<5 { l.rigs[2].tick(touched: true); l.rigs[0].tick(); l.rigs[1].tick() }
                case "stop": l.rigs[1].brain.stop(); for _ in 0..<5 { l.tick() }
                default: l.rigs[0].brain.request(.goTo(SIMD2(1.0, 1.5))); for _ in 0..<5 { l.tick() }
                }
                for _ in 0..<90 { l.tick() }
                XCTAssertFalse(l.anySocial, "\(kind) \(how): everybody is released")
                for r in l.rigs {
                    XCTAssertNil(r.brain.social, "\(kind) \(how)")
                    XCTAssertEqual(r.brain.socialBook.roll, 0, accuracy: 0.02, "\(kind) \(how): no roll overlay left")
                    XCTAssertFalse(r.brain.waveFootOff, "\(kind) \(how): the wave foot lift is back")
                }
            }
        }
    }

    func testHighFiveCooldownPerPair() {
        let l = lab()
        XCTAssertTrue(l.rigs[0].brain.socialStart(.highFive, with: l.rigs[1].brain, l.rigs[0].sim))
        var f = 0
        while f < 60 * 30 { l.tick(); f += 1; if !l.anySocial && f > 10 { break } }
        XCTAssertFalse(l.anySocial)
        for (a, b) in [(0, 1), (1, 0)] {
            XCTAssertGreaterThanOrEqual(l.rigs[a].brain.socialBook.fiveCool[b] ?? 0, 55, "the pair waits about a minute")
        }
        // the pick table of that pair has no high five now
        var w: [(SocialKind, Float)] = []
        l.rigs[0].brain.socialFriendWeights(into: &w, partner: l.rigs[1].brain, grumpy: false, night: 0, fastOK: true)
        XCTAssertFalse(w.contains { $0.0 == .highFive }, "no high five in the pair's pick during the cooldown")
        var w2: [(SocialKind, Float)] = []
        l.rigs[0].brain.socialFriendWeights(into: &w2, partner: l.rigs[2].brain, grumpy: false, night: 0, fastOK: true)
        XCTAssertTrue(w2.contains { $0.0 == .highFive } || l.rigs[0].brain.socialBook.lastKind == .highFive, "another pair may")
    }

    func testTreatsAreRareAndRespectBusy() {
        // never while somebody is busy; after one, every member waits >= 4 minutes
        let l = lab()
        for r in l.rigs { r.brain.idleMood = .happy; r.brain.socialBook.treatCool = 0; r.brain.socialBook.treatIdle = 999; r.brain.socialBook.treatLimit = 1 }
        l.rigs[2].brain.idleBlocked = true          // a meal / bath / trip anywhere
        var treats = 0
        for _ in 0..<(60 * 20) { l.tick(); if l.rigs.contains(where: { $0.brain.socialKind?.isTreat == true }) { treats += 1 } }
        XCTAssertEqual(treats, 0, "no treat while one of them is busy")
        l.rigs[2].brain.idleBlocked = false
        var started = false
        for _ in 0..<(60 * 60) { l.tick(); if l.rigs.contains(where: { $0.brain.socialKind?.isTreat == true }) { started = true; break } }
        XCTAssertTrue(started, "a treat starts once everybody is free and has waited")
        var f = 0
        while f < 60 * 60 { l.tick(); f += 1; if !l.anySocial && f > 10 { break } }
        for r in l.rigs { XCTAssertGreaterThanOrEqual(r.brain.socialBook.treatCool, EmoteTuning.treatCooldown.0 - 70, "every member waits minutes for the next treat") }
    }
}
