//
//  ProfileEntryTests.swift
//  profile-entry-r1: the roster card and the name header open that Jelmiko's Profile from the room. Nobody is selected, called or dressed differently by it, and back leaves to the room.
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class ProfileEntryTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func care3() -> GameCare {
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "ProfileEntry.3")!)
        Self.keep.append(c); return c
    }

    func testBothButtonsOpenTheRightJelmikoAtHome() {
        let care = care3()
        XCTAssertTrue(care.profileEntryAvailable)
        for id in 0..<3 { XCTAssertEqual(care.profileEntryTarget(id), id, "the button on Jelmiko \(id)'s card / header opens Jelmiko \(id)") }
        XCTAssertNil(care.profileEntryTarget(7), "no such Jelmiko: nothing opens")
    }

    func testOpeningSelectsNobodyCallsNobodyAndChangesNoOutfit() {
        let care = care3()
        care.store.saved.wearables = [WearLook.partyHat.rawValue]
        XCTAssertTrue(care.store.wear(.partyHat, on: 1))
        let outfit = care.store.outfit(1), sel = care.select.selectedID, queued = care.queued.count, hasEveryday = care.store.hasEveryday
        // the roster card opens Jelmiko 1 while Jelmiko 2 is the one on screen: the target is the card's, the selection stays
        _ = care.profileEntryTarget(1)
        XCTAssertEqual(care.select.selectedID, sel, "the selection is untouched")
        XCTAssertFalse(care.focus.isActive, "no snuggle: nobody is called over")
        XCTAssertEqual(care.queued.count, queued)
        // the Town flow closing runs the wardrobe guard's leave-lobby: with no Jelly Show lobby opened it changes nothing
        care.showWardrobeLeaveLobby()
        XCTAssertEqual(care.store.outfit(1), outfit, "no outfit change")
        XCTAssertEqual(care.store.hasEveryday, hasEveryday)
    }

    func testNotShownAwayFromHome() {
        let care = care3()
        care.arranging = true; XCTAssertFalse(care.profileEntryAvailable); XCTAssertNil(care.profileEntryTarget(0)); care.arranging = false
        XCTAssertTrue(care.profileEntryAvailable)
        care.park.openPicker(all: [0]); XCTAssertFalse(care.profileEntryAvailable, "the park picker / the park / the camp"); care.park.cancelPicker()
        XCTAssertTrue(care.profileEntryAvailable)
    }

    func testBackReturnsToTheRoomFromTheRoomAndToTheLobbyFromTheShow() {
        XCTAssertTrue(TownFlow.profileBackLeaves(focusActive: false, root: .condition), "opened from the room: back leaves the flow")
        XCTAssertTrue(TownFlow.profileBackLeaves(focusActive: true, root: .condition), "from the close-up: as before")
        XCTAssertFalse(TownFlow.profileBackLeaves(focusActive: false, root: .studio), "from the Jelly Show lobby: back to the lobby")
    }

    func testTheButtonsExistWithTheRightNameAndTheCloseUpsSymbol() {
        let h = UIHostingController(rootView: ProfileEntryButton(name: "Pip", action: {}))
        h.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(h.sizeThatFits(in: CGSize(width: 400, height: 400)), CGSize(width: 44, height: 44), "a 44 pt target, fixed size")
    }
}
