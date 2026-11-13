//
//  GuestPartyTests.swift
//  The welcome party after the arrival hug (Park/GuestParty.swift): a group emote with every Jelbie AND the guest (ring dance for three, circle dance for a bigger
//  house), then staggered happy hops with voices, then everybody free again; the visit goes on. The Lab is wired as the stage (SocialTests.Lab), the last rig is the guest.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class GuestPartyTests: XCTestCase {
    override func setUp() { super.setUp(); GroupEmoteFeetTests.reset() }
    override func tearDown() { GroupEmoteFeetTests.reset(); super.tearDown() }

    struct Run {
        var hugSeconds: Float = 0, partySeconds: Float = 0, freeAfter: Float = 0
        var kind: SocialKind?, crew = 0, hops: [Int] = [], voices: [Int] = [], sawKind = Set<Int>(), finished = false, allFree = false
        var hugOnly: Float = 0
    }

    private func run(n: Int, seed: UInt64 = 31) -> Run {
        _ = OnePieceInvariantTests.configured
        let lab = SocialTests.Lab(n: n, positions: n <= 3 ? Array(SocialTests.starts.prefix(n)) : Array(GroupSocialTests.five.prefix(n)), seed: seed)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.autonomy = true }
        let brains = lab.rigs.map(\.brain), sims = lab.rigs.map(\.sim)
        var res = Run()
        // the hug, as the arrival starts it
        XCTAssertTrue(brains[0].socialStartGroup(.groupHug, with: Array(brains.dropFirst()), sims[0]), "the hug starts")
        var party = GuestParty()
        party.begin()
        var voices = [Int](repeating: 0, count: n)
        var frame = 0, hugEnd = -1
        let dt: Float = 1.0 / 60
        while frame < 60 * 70 {
            lab.tick(watching: false)
            party.step(brains: brains, sims: sims, dt: dt) { i, _ in voices[i] += 1 }
            for (i, b) in brains.enumerated() where b.social?.kind == .ringDance || b.social?.kind == .circleDance { res.sawKind.insert(i) }
            if hugEnd < 0, party.hugSeen, !lab.anySocial { hugEnd = frame }
            frame += 1
            if party.stage == .done, lab.rigs.allSatisfy({ $0.brain.fxFree && $0.brain.social == nil }) { res.freeAfter = Float(frame) / 60; break }
        }
        res.finished = party.stage == .done
        res.allFree = lab.rigs.allSatisfy { $0.brain.fxFree && $0.brain.social == nil && !$0.brain.commanded && !$0.brain.held }
        res.partySeconds = Float(frame) / 60
        res.hugSeconds = Float(max(hugEnd, 1)) / 60
        res.kind = party.kind; res.crew = party.crew.count; res.hops = party.hops; res.voices = voices
        return res
    }

    private func check(_ r: Run, n: Int, expect: SocialKind, line: String) {
        XCTAssertEqual(r.kind, expect, "\(line): the group emote")
        XCTAssertEqual(r.crew, n, "\(line): every Jelmiko and the guest are in it")
        XCTAssertEqual(r.sawKind.count, n, "\(line): every one of them really ran it (saw \(r.sawKind.sorted()))")
        XCTAssertEqual(r.hops.count, n)
        for (i, h) in r.hops.enumerated() { XCTAssertGreaterThanOrEqual(h, 2, "\(line): rig \(i) did >= 2 happy hops (\(h))") }
        for (i, v) in r.voices.enumerated() { XCTAssertGreaterThanOrEqual(v, 2, "\(line): rig \(i) made >= 2 voice requests (\(v))") }
        XCTAssertTrue(r.finished, "\(line): the party ends")
        XCTAssertTrue(r.allFree, "\(line): everybody is free and idle again")
        // longer than the hug alone, but bounded: the new length (hug + dance + finale) is what the tuning allows, plus 2 s
        XCTAssertGreaterThanOrEqual(r.partySeconds, r.hugSeconds * 1.5, "\(line): 1.5x the hug at least (\(r.partySeconds) vs \(r.hugSeconds))")
        let bound = PartyTuning.hugMax + PartyTuning.danceMax + PartyTuning.finaleMax + 2
        XCTAssertLessThanOrEqual(r.partySeconds, bound, "\(line): ends within the tuned length + 2 s")
        MotionLog.write(String(format: "GUESTPARTY %@ | hug ends %.1f s | all free %.1f s | ratio %.2f | hops %@ | voices %@", line, r.hugSeconds, r.freeAfter, r.freeAfter / max(r.hugSeconds, 0.1), r.hops.description, r.voices.description))
    }

    func testRingDanceWithTwoJelbiesAndTheGuest() {
        let r = run(n: 3)
        check(r, n: 3, expect: .ringDance, line: "ring x3")
    }

    func testCircleDanceWithThreeJelbiesAndTheGuest() {
        let r = run(n: 4)
        check(r, n: 4, expect: .circleDance, line: "circle x4")
    }

    func testTheVisitGoesOnAfterTheParty() {
        let book = GuestBook(defaults: UserDefaults(suiteName: "GuestParty.\(UUID().uuidString)")!)
        XCTAssertTrue(book.invite(visitor: 1, kind: .playDate, now: 100))
        book.markArrived(now: 200)
        book.party.begin()
        XCTAssertTrue(book.party.active)
        book.party.cancel()          // (an outing or the goodbye ends it quietly)
        XCTAssertFalse(book.party.active)
        XCTAssertTrue(book.visit?.arrived ?? false, "the visit is untouched by the party")
        book.finish()
        XCTAssertFalse(book.party.active)
    }

    func testStaggerOffsetsAreInTheTunedRange() {
        var prev: Float = -1
        for i in 0..<4 {
            let o = GuestParty.hopOffset(place: i)
            XCTAssertGreaterThanOrEqual(o, prev, "each place starts a little later")
            if i > 0 { XCTAssertGreaterThanOrEqual(o - prev, 0.2 - 1e-4, "0.2 s apart at least"); XCTAssertLessThanOrEqual(o - prev, 0.5 + 1e-4, "0.5 s apart at most") }
            prev = o
        }
    }
}
