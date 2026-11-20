//
//  ParentGateSwitchTests.swift
//  Owner 2026-11-19: "remove the parent gate if we don't need it". `ParentGate.required` (UI/ParentGate.swift) is the one switch: off = a gated exit runs its action at once and
//  the gate screen is never up; on = the gate comes first and the old grown-up wording is back.
//

import XCTest
@testable import BobV1

@MainActor
final class ParentGateSwitchTests: XCTestCase {
    private var saved = false
    override func setUp() { saved = ParentGate.required }
    override func tearDown() { ParentGate.required = saved }

    func testShippedDefaultIsOff() { XCTAssertFalse(saved, "the gate ships off") }

    func testSwitchOffRunsTheActionWithNoGate() {
        var ran = 0
        let handled = ParentGate.intercept(isPresented: true, required: false) { ran += 1 }
        XCTAssertTrue(handled, "the request is closed: the gate screen is never shown")
        XCTAssertEqual(ran, 1, "the action ran at once")
        XCTAssertFalse(ParentGate.intercept(isPresented: false, required: false) { ran += 1 }); XCTAssertEqual(ran, 1, "nothing runs when nothing was asked")
    }

    func testSwitchOnShowsTheGateFirst() {
        var ran = 0
        let handled = ParentGate.intercept(isPresented: true, required: true) { ran += 1 }
        XCTAssertFalse(handled, "the gate screen stays up")
        XCTAssertEqual(ran, 0, "the action waits for the hold")
    }

    func testGlobalSwitchIsWhatTheModifierReads() {
        ParentGate.required = false
        var ran = 0
        XCTAssertTrue(ParentGate.intercept(isPresented: true) { ran += 1 }); XCTAssertEqual(ran, 1)
        ParentGate.required = true
        XCTAssertFalse(ParentGate.intercept(isPresented: true) { ran += 1 }); XCTAssertEqual(ran, 1)
    }

    func testGrownUpWordingFollowsTheSwitch() {
        ParentGate.required = false
        XCTAssertEqual(ParentGate.hint("Asks a grown-up first, then opens Mail", ungated: "Opens Mail"), "Opens Mail")
        XCTAssertFalse(PrivacyText.sections.contains { $0.heading == "Grown-up check" })
        ParentGate.required = true
        XCTAssertEqual(ParentGate.hint("Asks a grown-up first, then opens Mail", ungated: "Opens Mail"), "Asks a grown-up first, then opens Mail")
        XCTAssertTrue(PrivacyText.sections.contains { $0.heading == "Grown-up check" })
    }

    func testShareSheetExcludesSaveToCameraRoll() {
        let vc = ShareSheet.make(items: [UIImage()])
        XCTAssertEqual(vc.excludedActivityTypes, [.saveToCameraRoll])
    }
}
