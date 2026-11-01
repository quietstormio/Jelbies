import XCTest
import simd
@testable import BobV1

/// The room's per-Jelbie sound requests over 60 simulated seconds with 3 Jelbies (the 2026-11-01 "they stopped making noise" report).
@MainActor
final class RoomSFXCountTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { AudioHub.requestTap = nil; RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func testCountRoomSoundRequests() {
        var counts: [String: Int] = [:]
        AudioHub.requestTap = { counts[$0, default: 0] += 1 }
        var total: [String: Int] = [:]
        for seed in [11, 23, 37] as [UInt64] {
            counts = [:]
            let lab = SocialTests.Lab(n: 3, quiet: false, seed: seed)
            for (i, r) in lab.rigs.enumerated() { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy; r.brain.restTimer = 0.5 + Float(i) }
            for _ in 0..<(60 * 60) { lab.tick() }
            for (k, v) in counts { total[k, default: 0] += v }
        }
        let line = "ROOMSFX " + total.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print(line); MotionLog.write(line)
        XCTAssertGreaterThan(total["jump", default: 0], 0)
    }

    /// An unmuted hub that is started plays the room's cues past every guard (not just the request taps above).
    func testStartedHubLetsRoomCuesThrough() {
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        hub.start()
        for s in [SFX.jump, .boop, .squish, .wobble, .footstep, .zoomies, .setdown] { hub.play(s, jelly: 0, x: 0) }
        hub.chirp(jelly: 0, .happy); hub.chirp(jelly: 1, .babble)
        print("HUBLOG \(hub._playLog)")
        XCTAssertEqual(hub._playLog.sorted(), ["boop", "footstep", "jump", "setdown", "squish", "wobble", "zoomies"])
    }

    /// Two Jelbies pressed together must be able to get closer than ContactTuning.contactFrac of the gap, or the contact squish + kick (BlobBrain+Contact) never fires.
    /// (g-bodysep floored keepApart at the full gap: 0 contacts at home, r1052.)
    func testKeepApartStillAllowsContact() {
        let peers: [(pos: SIMD2<Float>, walking: Bool)] = [(SIMD2(0, 0), false), (SIMD2(0.3, 0), false)]
        let q = MelonController.keepApart(SIMD3(0.3, 0, 0), id: 1, peers: peers)
        let d = simd_length(SIMD2(q.x, q.z))
        XCTAssertLessThan(d, MelonController.jellyGap * ContactTuning.contactFrac, "pressed pair reaches contact distance (d=\(d))")
    }
}
