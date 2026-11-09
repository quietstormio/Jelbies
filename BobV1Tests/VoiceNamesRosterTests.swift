//
//  VoiceNamesRosterTests.swift
//  The name registry follows the live room roster and clears its nicknames when the game is wiped.
//

import XCTest
@testable import BobV1

@MainActor
final class VoiceNamesRosterTests: XCTestCase {
    private var saved: [Int] = []
    override func setUp() { saved = JellyRoster.current }
    override func tearDown() { JellyRoster.current = saved }

    func testRosterFollowsCurrentWithoutRecreatingTheRegistry() {
        let n = JellyNames(defaults: UserDefaults(suiteName: "VoiceNamesRosterTests.a")!, key: "nick", persists: false)
        JellyRoster.current = [1]
        XCTAssertEqual(n.roster, [1])
        XCTAssertEqual(n.resolve(tokens: ["pip"]).first?.id, 0, "the only Jelbie in the room is slot 0")
        JellyRoster.current = [0, 1]
        XCTAssertEqual(n.resolve(tokens: ["pip"]).first?.id, 1)
    }

    func testWipeNotificationClearsNicknames() {
        let d = UserDefaults(suiteName: "VoiceNamesRosterTests.b")!
        d.removePersistentDomain(forName: "VoiceNamesRosterTests.b")
        let n = JellyNames(defaults: d, key: "nick", persists: true)
        n.roster = [0]
        XCTAssertTrue(n.addNickname("blueberry", for: 0))
        d.removeObject(forKey: "nick")
        NotificationCenter.default.post(name: Notification.Name("JelbiesDidWipe"), object: nil)
        XCTAssertTrue(n.nicknames(for: 0).isEmpty)
    }
}
