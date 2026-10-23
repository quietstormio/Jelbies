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
}
