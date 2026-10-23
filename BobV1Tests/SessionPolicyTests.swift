import XCTest
import AVFoundation
@testable import BobV1

final class SessionPolicyTests: XCTestCase {
    func testNeverDucksOrInterruptsInAnyState() {
        for music in [true, false] { for other in [true, false] { for mic in [true, false] {
            let p = SessionPolicy.plan(musicOn: music, otherAudioPlaying: other, micActive: mic)
            XCTAssertFalse(p.options.contains(.duckOthers))
            XCTAssertFalse(p.options.contains(.interruptSpokenAudioAndMixWithOthers))
            XCTAssertTrue(p.options.contains(.mixWithOthers))
        } } }
    }
    func testPlayIsAmbient() {
        XCTAssertEqual(SessionPolicy.plan(musicOn: false, otherAudioPlaying: true, micActive: false).category, .ambient)
        XCTAssertEqual(SessionPolicy.plan(musicOn: true, otherAudioPlaying: false, micActive: false).category, .ambient)
    }
    func testMicIsPlayAndRecordMixing() {
        let p = SessionPolicy.plan(musicOn: false, otherAudioPlaying: true, micActive: true)
        XCTAssertEqual(p.category, .playAndRecord)
        XCTAssertTrue(p.options.isSuperset(of: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]))
    }
    func testGameMusicSilentWhenOffOrOthersPlaying() {
        XCTAssertTrue(SessionPolicy.gameMusicAllowed(musicOn: true, otherAudioPlaying: false))
        XCTAssertFalse(SessionPolicy.gameMusicAllowed(musicOn: true, otherAudioPlaying: true))
        XCTAssertFalse(SessionPolicy.gameMusicAllowed(musicOn: false, otherAudioPlaying: false))
    }
    @MainActor func testHubSilencesMusicButKeepsSettingWhenOtherAudioPlays() {
        let hub = AudioHub(defaults: UserDefaults(suiteName: "SessionPolicyTests")!, muted: true)
        XCTAssertGreaterThan(hub._musicLevelNow, 0)
        hub._setOtherAudio(true)
        XCTAssertEqual(hub._musicLevelNow, 0)
        XCTAssertTrue(hub.settings.musicOn)
    }
}
