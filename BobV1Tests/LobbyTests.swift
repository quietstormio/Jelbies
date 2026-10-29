//
//  LobbyTests.swift
//  The Volleyball lobby's team rules (the chosen partner is who plays, no swap with two Jelbies, the Park friend is one visitor per day) and the SVG reader of the lobby art.
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class LobbyTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func care(_ n: Int) -> GameCare {
        let c = GameCare(jellyCount: n, persistent: false, defaults: UserDefaults(suiteName: "LobbyTests.\(n)")!)
        Self.keep.append(c)
        return c
    }

    func testThePartnerDefaultsToTheFirstOtherJelbie() {
        let c = care(3)
        XCTAssertEqual(c.volleyPartner(for: 0)?.id, 1)
        XCTAssertEqual(c.volleyPartner(for: 1)?.id, 0)
    }

    func testTheChosenPartnerIsTheOneWhoPlays() {
        let c = care(3)
        c.volley.book.partner = c.jellies[2].character
        XCTAssertEqual(c.volleyPartner(for: 0)?.id, 2, "the chosen one, not the first other Jelbie")
        c.startVolley(jelly: 0, mode: .match(.sandcastle), seed: 5)
        XCTAssertEqual(c.volleyWork.partnerID, 2, "the match is set up with the chosen partner")
    }

    func testAChosenPartnerWhoIsThePlayerOrGoneFallsBack() {
        let c = care(3)
        c.volley.book.partner = c.jellies[0].character
        XCTAssertEqual(c.volleyPartner(for: 0)?.id, 1, "he cannot partner himself: the first other Jelbie")
        c.volley.book.partner = 99
        XCTAssertEqual(c.volleyPartner(for: 0)?.id, 1, "a partner no longer in the room is ignored")
    }

    func testSwapNeedsABench() {
        XCTAssertNil(care(2).volleyBench(for: 0), "two Jelbies: nobody on the bench, so the swap buttons are hidden")
        XCTAssertNil(care(1).volleyBench(for: 0))
        let c = care(3)
        XCTAssertEqual(c.volleyBench(for: 0)?.id, 2)
        c.volley.book.partner = c.jellies[2].character
        XCTAssertEqual(c.volleyBench(for: 0)?.id, 1, "the bench is whoever is neither the player nor the partner")
    }

    func testAloneThereIsNoPartnerButAParkFriend() {
        let c = care(1)
        XCTAssertNil(c.volleyPartner(for: 0))
        XCTAssertEqual(c.volleyParkFriend().id, c.volleyParkFriend().id)
    }

    func testTheParkFriendIsTheSameAllDayAndChangesAcrossDays() {
        let pool = ParkPool.generate()
        for day in [20_000, 20_001, 20_500] { XCTAssertEqual(ParkPool.dailyFriend(dayKey: day, pool: pool).id, ParkPool.dailyFriend(dayKey: day, pool: pool).id) }
        let ids = Set((20_000..<20_030).map { ParkPool.dailyFriend(dayKey: $0, pool: pool).id })
        XCTAssertGreaterThan(ids.count, 5, "different days bring different friends")
    }

    func testThePartnerChoiceIsSaved() {
        let d = UserDefaults(suiteName: "LobbyTests.save")!
        d.removePersistentDomain(forName: "LobbyTests.save")
        let a = VolleyBook(persists: true, defaults: d)
        XCTAssertNil(a.partner)
        a.partner = 2
        XCTAssertEqual(VolleyBook(persists: true, defaults: d).partner, 2)
        a.partner = nil
        XCTAssertNil(VolleyBook(persists: true, defaults: d).partner)
    }

    func testDrillsListTheStatsTheyRaise() {
        XCTAssertEqual(VolleyDrillKind.bonk.raises, [.timing, .hops])
        XCTAssertEqual(VolleyDrillKind.spike.raises, [.power])
        XCTAssertEqual(VolleyDrillKind.block.raises, [.hops])
        XCTAssertEqual(VolleyDrillKind.sprint.raises, [.speed])
    }

    func testDrillInstructionsDropTheRaisesSentence() {
        for k in VolleyDrillKind.allCases {
            XCTAssertFalse(k.instruction.isEmpty)
            XCTAssertFalse(k.instruction.contains("Raises"), "\(k): the caption is how to play, not what it trains")
            XCTAssertTrue(k.blurb.hasPrefix(k.instruction))
        }
        XCTAssertEqual(VolleyDrillKind.spike.instruction, "Swipe the Hit button to aim the spike at the pink cushion.")
    }

    func testTheDailyFriendHasNoSignatureFeature() {
        let pool = ParkPool.generate()
        for day in 20_000..<20_120 { XCTAssertEqual(ParkPool.dailyFriend(dayKey: day, pool: pool).signature, .none, "day \(day): what the lobby renders is exactly what plays") }
    }

    func testTheSVGReaderHandlesTheMockupPaths() {
        let tight = SVG.path("M1.5 .5h3v2.2h-3z").boundingRect
        XCTAssertEqual(tight.width, 3, accuracy: 0.01); XCTAssertEqual(tight.height, 2.2, accuracy: 0.01)
        let arc = SVG.path("M8 10.8V8a4 4 0 0 1 8 0v2.8").boundingRect
        XCTAssertEqual(arc.minY, 4, accuracy: 0.1, "the lock's shackle arcs up to y = 4")
        XCTAssertEqual(SVG.path("M54 10 C 34 24, 84 32, 62 44 S 48 58, 60 64").currentPoint?.y ?? 0, 64, accuracy: 0.01)
    }

    func testTheLobbyHintShowsThenReverts() async {
        let h = LobbyHint()
        h.show("Win a match to open", seconds: 0.2)
        XCTAssertEqual(h.text, "Win a match to open")
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(h.text)
    }
}
