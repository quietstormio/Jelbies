import XCTest
@testable import BobV1

/// Voices are keyed by CHARACTER (Bob / Pip / Moss / Lavender), not by slot.
@MainActor
final class JellyVoiceTests: XCTestCase {
    func testFourDistinctSetsAndClamping() {
        var names = Set<String>()
        for c in 0...3 { for v in [JellyVoice.happy, .sad, .babble] { names.insert(JellyVoiceSet.file(character: c, v)) } }
        XCTAssertEqual(names.count, 12)
        XCTAssertEqual(JellyVoiceSet.file(character: -1, .happy), JellyVoiceSet.file(character: 0, .happy))
        XCTAssertEqual(JellyVoiceSet.file(character: 9, .sad), "chirp_jelly4_sad")
    }

    func testSlotMapsThroughTheRoster() {
        let saved = JellyRoster.current
        defer { JellyRoster.current = saved }
        JellyRoster.current = [1, 2, 3]
        XCTAssertEqual(AudioHub.voiceFile(slot: 0, .happy), "chirp_jelly2_happy", "Pip, not Bob")
        XCTAssertEqual(AudioHub.voiceFile(slot: 2, .sad), "chirp_jelly4_sad")
        XCTAssertEqual(AudioHub.voiceFile(slot: 1, .babble), "babble_jelly3")
        JellyRoster.current = [0, 1, 2]
        XCTAssertEqual(AudioHub.voiceFile(slot: 0, .happy), "chirp_jelly1_happy")
    }

    func testSnoresAreInTheCharactersOwnVoice() {
        XCTAssertEqual(JellyVoiceSet.snoreFile(character: 0, roll: 0.9), "snore_jelly1_1", "Bob, plain")
        XCTAssertEqual(JellyVoiceSet.snoreFile(character: 1, roll: 0.9), "snore_jelly2_1")
        XCTAssertEqual(JellyVoiceSet.snoreFile(character: 2, roll: 0.1), "snore_jelly3_2", "Moss, bubble pop")
        XCTAssertEqual(JellyVoiceSet.snoreFile(character: 3, roll: 0.3), "snore_jelly4_1", "the pop is the rarer one (roll < 0.3)")
        XCTAssertEqual(JellyVoiceSet.snoreFile(character: 9, roll: 0.9), "snore_jelly4_1", "clamped like the chirps")
        XCTAssertEqual(JellyVoiceSet.snoreFile(character: -1, roll: 0.9), "snore_jelly1_1")
        var pops = 0
        for k in 0..<1000 where JellyVoiceSet.snoreFile(character: 0, roll: Double(k) / 1000).hasSuffix("_2") { pops += 1 }
        XCTAssertEqual(pops, 300, "about 30% are the bubble-pop variant")
        var names = Set<String>()
        for c in 0...3 { for r in [0.0, 0.9] { names.insert(JellyVoiceSet.snoreFile(character: c, roll: r)) } }
        XCTAssertEqual(names.count, 8)
    }
}
