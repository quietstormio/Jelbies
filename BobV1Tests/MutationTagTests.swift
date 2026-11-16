//
//  MutationTagTests.swift
//  The Where-to card's "Mutation Available" pill and the pick page's "Rare" tag come from the same answer (JellyVariantBook.offer): they can never disagree.
//

import XCTest
@testable import BobV1

final class MutationTagTests: XCTestCase {
    private var days: [Int] { Array(738_000..<738_900) }

    func testTheTagFollowsTheRareOffer() {
        var rare = 0, plain = 0
        for day in days {
            let on = JellyVariantBook.rareOnOffer(dayKey: day)
            XCTAssertEqual(TownTag.mutationAvailable(day: day, home: 2, camp: 0), on, "day \(day)")
            XCTAssertEqual(TownTag.mutationAvailable(day: day, home: 3, camp: 0), on, "a full home with room at Camp: the Spring still sells, the tag follows the offer")
            XCTAssertEqual(TownTag.mutationAvailable(day: day, home: 3, camp: JellyCamp.cap - 1), on, "one place left at Camp")
            XCTAssertFalse(TownTag.mutationAvailable(day: day, home: 3, camp: JellyCamp.cap), "home and Camp full: the Spring cannot sell, no tag")
            if on { rare += 1 } else { plain += 1 }
        }
        XCTAssertGreaterThan(rare, 0, "about 4 percent of species-days: some day in 900 has one"); XCTAssertGreaterThan(plain, 0)
    }

    func testTheTagAgreesWithWhatThePickPageOffers() {
        for day in days {
            // the pick page's three slots (JellyVariantBook.shades) hold a rare mutation exactly when `offer` has one for that species
            let pickPageHasRare = (0...3).contains { sp in JellyVariantBook.shades(species: sp, dayKey: day, owned: 0).contains { $0?.rare == true } }
            XCTAssertEqual(JellyVariantBook.rareOnOffer(dayKey: day), pickPageHasRare, "day \(day)")
            for sp in 0...3 { XCTAssertEqual(JellyVariantBook.offer(species: sp, dayKey: day) != nil, JellyVariantBook.shades(species: sp, dayKey: day, owned: 1).contains { $0?.rare == true }) }
        }
    }
}
