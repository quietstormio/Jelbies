import XCTest
@testable import BobV1

@MainActor
final class TouchSoundTests: XCTestCase {
    func testOnlyTheFirstPulseOfARingSounds() {
        var r = LetGoRing()
        XCTAssertTrue(r.shouldSound(now: 0))
        XCTAssertFalse(r.shouldSound(now: 0.15))
        XCTAssertFalse(r.shouldSound(now: 0.3))
        XCTAssertTrue(r.shouldSound(now: 0.9), "a new ring after the gap")
    }

    func testJellyPulseHapticsMatchTransient() {
        func run(_ f: (HapticDriver) -> Void) -> [RecordingHapticSink.Event] {
            let rec = RecordingHapticSink()
            let d = HapticDriver(sinks: [rec])
            d.enabled = true
            d.setWarm(true)
            rec.clear()
            f(d)
            return rec.events
        }
        let a = run { $0.transient(now: 1, intensity: 0.4, sharpness: 0.6) }
        let b = run { $0.jellyPulse(now: 1, intensity: 0.4, sharpness: 0.6) }
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.map { "\($0.kind)\($0.intensity)\($0.sharpness)" }, b.map { "\($0.kind)\($0.intensity)\($0.sharpness)" })
    }
}
