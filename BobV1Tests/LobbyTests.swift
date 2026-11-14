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
        XCTAssertEqual(c.volleyPartner(for: 0)?.id, 2, "the chosen one, not the first other Jelmiko")
        c.startVolley(jelly: 0, mode: .match(.sandcastle), seed: 5)
        XCTAssertEqual(c.volleyWork.partnerID, 2, "the match is set up with the chosen partner")
    }

    func testAChosenPartnerWhoIsThePlayerOrGoneFallsBack() {
        let c = care(3)
        c.volley.book.partner = c.jellies[0].character
        XCTAssertEqual(c.volleyPartner(for: 0)?.id, 1, "he cannot partner himself: the first other Jelmiko")
        c.volley.book.partner = 99
        XCTAssertEqual(c.volleyPartner(for: 0)?.id, 1, "a partner no longer in the room is ignored")
    }

    func testSwapNeedsABench() {
        XCTAssertNil(care(2).volleyBench(for: 0), "two Jelmiko: nobody on the bench, so the swap buttons are hidden")
        XCTAssertNil(care(1).volleyBench(for: 0))
        let c = care(3)
        XCTAssertEqual(c.volleyBench(for: 0)?.id, 2)
        c.volley.book.partner = c.jellies[2].character
        XCTAssertEqual(c.volleyBench(for: 0)?.id, 1, "the bench is whoever is neither the player nor the partner")
    }

    func testAloneThereIsNoPartnerButAParkFriend() {
        let c = care(1)
        XCTAssertNil(c.volleyPartner(for: 0))
        XCTAssertNil(c.volleyParkFriend(), "a new game has no Park friends")
        XCTAssertEqual(c.volleyBlocker(jelly: 0, match: true), GameCare.volleyNeedsPartner, "alone and friendless: no match")
        XCTAssertNotEqual(c.volleyBlocker(jelly: 0, match: true) == nil, true)
        c.parkBook.add(points: ParkTuning.palAt + 1, visitor: 7, character: c.jellies[0].character)
        XCTAssertEqual(c.volleyParkFriend()?.id, 7, "a Pal fills in")
        c.parkBook.add(points: ParkTuning.friendAt, visitor: 9, character: c.jellies[0].character)
        XCTAssertEqual(c.volleyParkFriend()?.id, 9, "the closest friend (highest level) fills in")
        XCTAssertEqual(c.closestParkFriends(2).map(\.id), [9, 7])
        XCTAssertNil(c.volleyPartnerBlocker(jelly: 0))
        XCTAssertNil(care(2).volleyPartnerBlocker(jelly: 0), "two Jelmiko are a team without a friend")
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

    // MARK: Jelly Race lobby: who has won the picked course

    func testAWinIsKeptPerJelmikoPerCourse() {
        let c = care(2)
        let a = c.jellies[0].character, b = c.jellies[1].character
        let t = c.race.trophies
        func won(_ ch: Int, _ tier: CourseTier) -> Int { t.shelf(character: ch).raceRibbons(tier)[0] }
        XCTAssertEqual(won(a, .ripple), 0, "nobody has won yet")
        t.recordRace(character: a, tier: .ripple, place: 1)
        t.recordRace(character: a, tier: .ripple, place: 1)
        t.recordRace(character: b, tier: .ripple, place: 2)
        XCTAssertEqual(won(a, .ripple), 2)
        XCTAssertEqual(won(b, .ripple), 0, "a 2nd place is not a win")
        XCTAssertEqual(won(a, .wave), 0, "a different course shows none")
    }

    func testAnOldSaveWithoutRaceWinsDecodesToZero() throws {
        let old = Data(#"{"earned":[]}"#.utf8)
        let s = try JSONDecoder().decode(JelbieTrophies.self, from: old)
        XCTAssertEqual(s.raceRibbons(.puddle)[0], 0)
        let kept = Data(#"{"race":{"puddle":[2,0,0]},"earned":["first.puddle"]}"#.utf8)
        let k = try JSONDecoder().decode(JelbieTrophies.self, from: kept)
        XCTAssertEqual(k.raceRibbons(.puddle)[0], 2, "wins an older save already holds per Jelmiko stay")
        XCTAssertEqual(k.raceRibbons(.ripple)[0], 0)
    }

    func testTheTileLabelSaysWonThisCourse() {
        XCTAssertEqual(LobbyJelbiePicker.label("Lemon", won: 0), "Lemon")
        XCTAssertEqual(LobbyJelbiePicker.label("Lemon", won: 1), "Lemon, won this course")
        XCTAssertEqual(LobbyJelbiePicker.label("Lemon", won: 3), "Lemon, won this course 3 times")
    }
}
