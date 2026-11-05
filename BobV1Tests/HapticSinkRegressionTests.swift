import XCTest
@testable import BobV1

/// The touch / cuddle haptics at the SINK (the CHHapticEngine seam) - portable: the same file runs on the approved build and on HEAD (scripts/regression-gate.sh).
/// 2026-11-02: "the haptics are gone, including the cuddle / touch ones": a second engine in the room layer had taken them out.
@MainActor
final class HapticSinkRegressionTests: XCTestCase {
    var saved: Any?
    override func setUp() { super.setUp(); BlobBrain.pickBudgetSeconds = .infinity; saved = UserDefaults.standard.object(forKey: HapticSettings.key) }
    override func tearDown() { super.tearDown(); BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds; if let v = saved { UserDefaults.standard.set(v, forKey: HapticSettings.key) } else { UserDefaults.standard.removeObject(forKey: HapticSettings.key) } }

    func testTouchAndCuddleHapticsReachTheSink() {
        UserDefaults.standard.removeObject(forKey: HapticSettings.key)          // a fresh / old save: the key was never written
        XCTAssertTrue(HapticSettings.enabled, "Haptics default to ON for a save that never wrote the key")
        let rec = RecordingHapticSink()
        let d = HapticDriver(sinks: [rec])
        d.setWarm(true)
        XCTAssertTrue(d.enabled)
        var now = 100.0
        for i in 0..<10 { d.transient(now: now, intensity: 0.3 + 0.05 * Float(i), sharpness: 0.2); now += 0.2 }          // strokes / cheek touches
        d.jellyPulse(now: now, intensity: 0.4, sharpness: 0.2); now += 0.2
        d.impact(now: now, speed: 3); now += 0.2
        d.wobble(now: now, peak: 0.4); now += 0.2
        for i in 0..<30 { d.update(now: now, petIntensity: 0.4, petSharpness: 0.2, squishIntensity: i < 15 ? 0.3 : 0, squishSharpness: 0.1); now += 1.0 / 30 }
        let line = "HAPTICSINK transient=\(rec.events.filter { $0.kind == .transient }.count) wobble=\(rec.events.filter { $0.kind == .wobble }.count) continuous=\(rec.events.filter { $0.kind == .continuous }.count) start=\(rec.startCount)"
        print(line)
        try? line.write(toFile: ProcessInfo.processInfo.environment["HAPTICSINK_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/hapticsink_last.txt", atomically: true, encoding: .utf8)
        XCTAssertGreaterThanOrEqual(rec.events.filter { $0.kind == .transient }.count, 12)
        XCTAssertGreaterThanOrEqual(rec.events.filter { $0.kind == .wobble }.count, 1)
        XCTAssertGreaterThanOrEqual(rec.events.filter { $0.kind == .continuous }.count, 2)
        XCTAssertEqual(rec.startCount, 1)
    }
}
