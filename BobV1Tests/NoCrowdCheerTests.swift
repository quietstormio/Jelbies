import XCTest
@testable import BobV1

/// no-cheer-r1: the owner asked for the small crowd cheer (children saying "yay") to be taken away. Nothing may request or ship it.
@MainActor
final class NoCrowdCheerTests: XCTestCase {
    func testNoShowCueResolvesToACheerFile() {
        var seen: [String] = []
        AudioHub.requestTap = { seen.append($0) }
        defer { AudioHub.requestTap = nil }
        let cues: [ShowCue] = [.perfect, .good, .slip, .countdown, .go, .ring, .land, .flop, .burst, .jingle(win: true), .jingle(win: false)]
        for c in cues { AudioHub.shared.showCue(c) }
        XCTAssertFalse(seen.contains { $0.hasPrefix("cheer_small") }, "no cue plays the crowd cheer: \(seen)")
    }
    func testNoSFXIsNamedCheerSmallAndNoFileShips() {
        XCTAssertNil(SFX(rawValue: "cheer_small"))
        for n in ["cheer_small_1", "cheer_small_2"] { XCTAssertNil(Bundle.main.url(forResource: n, withExtension: "m4a"), n) }
    }
}
