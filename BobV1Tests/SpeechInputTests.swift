import XCTest
@testable import BobV1

@MainActor
final class SpeechInputTests: XCTestCase {
    func testFakeStartStopReturnsText() async throws {
        let fake = FakeSpeechInput()
        await fake.prepare(contextualWords: ["bob"])
        XCTAssertEqual(fake.availability, .ready)
        fake.nextTranscript = "sit down"
        try await fake.start(contextualWords: ["bob", "sit"])
        XCTAssertEqual(fake.lastContextualWords, ["bob", "sit"])
        let text = await fake.stop()
        XCTAssertEqual(text, "sit down")
        let again = await fake.stop()
        XCTAssertEqual(again, "")
    }

    func testFakeLevelFiresWhileStartedOnly() async throws {
        let fake = FakeSpeechInput()
        var levels: [Float] = []
        fake.onLevel = { levels.append($0) }
        try await fake.start(contextualWords: [])
        try await Task.sleep(nanoseconds: 300_000_000)
        _ = await fake.stop()
        XCTAssertGreaterThan(levels.count, 2)
        XCTAssertTrue(levels.allSatisfy { (0...1).contains($0) })
        let n = levels.count
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(levels.count, n)
    }

    func testFakeUsesDefaultsText() async throws {
        UserDefaults.standard.set("hello", forKey: "VoiceFakeText")
        defer { UserDefaults.standard.removeObject(forKey: "VoiceFakeText") }
        let fake = FakeSpeechInput()
        try await fake.start(contextualWords: [])
        let text = await fake.stop()
        XCTAssertEqual(text, "hello")
    }

    func testFactoryHonoursFakeMic() {
        let on = UserDefaults(suiteName: "SpeechInputTests.on")!
        on.removePersistentDomain(forName: "SpeechInputTests.on")
        on.set(true, forKey: "VoiceFakeMic")
        XCTAssertTrue(SpeechInputFactory.make(defaults: on) is FakeSpeechInput)
        let off = UserDefaults(suiteName: "SpeechInputTests.off")!
        off.removePersistentDomain(forName: "SpeechInputTests.off")
        XCTAssertTrue(SpeechInputFactory.make(defaults: off) is DictationSpeechInput)
    }

    func testDictationDoesNotCrashInSimulator() async throws {
        #if targetEnvironment(simulator)
        let real = DictationSpeechInput()
        XCTAssertEqual(real.availability, .unknown)
        // A permission prompt could block an unattended run; poll with a bound
        // instead of awaiting (awaiting a blocked prepare() would hang the suite).
        var finished = false
        let task = Task { @MainActor in await real.prepare(contextualWords: ["bob"]); finished = true }
        for _ in 0..<200 where !finished { try await Task.sleep(nanoseconds: 100_000_000) }
        if !finished { task.cancel() }
        try XCTSkipUnless(finished, "prepare() blocked (permission UI / asset download)")
        print("SPEECH_AVAILABILITY_SIM: \(real.availability)")
        switch real.availability {
        case .ready:
            do { try await real.start(contextualWords: ["bob"]); _ = await real.stop() } catch {}
        case .unknown, .needsDownload, .unavailable, .denied:
            do { try await real.start(contextualWords: []); _ = await real.stop() } catch {}
        }
        #else
        throw XCTSkip("simulator only")
        #endif
    }
}
