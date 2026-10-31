//
//  CartwheelRemovalSaveTests.swift
//  The cartwheel emote was removed. No current save format stores it, but a save that did (a trick lesson keyed "cartwheel", a stray raw
//  value) must still load with everything else intact.
//

import XCTest
@testable import BobV1

@MainActor
final class CartwheelRemovalSaveTests: XCTestCase {
    func testOldSaveWithACartwheelLessonLoadsAndKeepsEverythingElse() throws {
        let json = """
        {"name":{"word":"bob","reps":3,"sessions":[1,2,3],"learned":true,"reliability":0.9},
         "tricks":{"sit":{"word":"sit down","reps":3,"sessions":[1,2,3],"learned":true,"reliability":0.8},
                   "flip":{"word":"flip","reps":1,"sessions":[4],"learned":false,"reliability":0},
                   "cartwheel":{"word":"wheel","reps":3,"sessions":[5,6,7],"learned":true,"reliability":0.7}},
         "sessionCounter":7}
        """
        // the raw model decodes the unknown key as plain data (a String-keyed dictionary)...
        let raw = try JSONDecoder().decode(VoiceBook.self, from: Data(json.utf8))
        XCTAssertEqual(raw.sessionCounter, 7)
        XCTAssertEqual(raw.tricks.count, 3)

        // ...and the store drops the retired key but keeps the rest
        let name = "CartwheelRemovalSaveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        defaults.set(Data(json.utf8), forKey: VoiceTuning.defaultsKey)
        let v = VoiceTraining(defaults: defaults, persists: false)
        v.load()
        XCTAssertEqual(v.book.sessionCounter, 7, "counters survive")
        XCTAssertEqual(v.book.name.word, "bob", "the name lesson survives")
        XCTAssertTrue(v.isLearned(.sit), "a learned trick stays learned")
        XCTAssertEqual(v.book.tricks["sit"]?.word, "sit down")
        XCTAssertEqual(v.book.tricks["flip"]?.reps, 1, "a half-taught trick keeps its reps")
        XCTAssertNil(v.book.tricks["cartwheel"], "the removed trick is dropped, not a failure")
    }

    func testNoIdleKindDecodesFromCartwheel() {
        XCTAssertNil(IdleKind(rawValue: "cartwheel"))
        XCTAssertFalse(IdleKind.allCases.map(\.rawValue).contains("cartwheel"))
    }
}
