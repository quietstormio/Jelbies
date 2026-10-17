import XCTest
import AVFoundation
import Speech
@testable import BobV1

@MainActor
final class VoiceRecoveryTests: XCTestCase {
    private func make() -> VoiceTraining {
        let n = "VoiceRecovery.\(UUID().uuidString)"
        return VoiceTraining(defaults: UserDefaults(suiteName: n)!, random: { 0.0 })      // roll 0 = always succeeds
    }

    func testComeVariantsMatchPrelearned() {
        for said in ["Come here.", "come here bob", "Calm here", "come hear", "C'mere", "come ear", "Come!", "here", "Bob, come here please"] {
            let v = make()
            let r = v.decide(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertEqual(r, .perform(.come), "\(said)")
        }
    }

    func testUnrelatedDoesNotCome() {
        let v = make()
        XCTAssertNotEqual(v.decide(transcript: "banana pudding", runningMove: nil, mood: .happy, session: 1), .perform(.come))
    }

    func testAccumulatorFallsBackToVolatile() {
        var a = TranscriptAccumulator()
        a.add(text: "come", isFinal: false)
        a.add(text: "come here", isFinal: false)
        XCTAssertEqual(a.result, "come here")
        a.add(text: "Come here.", isFinal: true)
        XCTAssertEqual(a.result, "Come here.")
        a.add(text: "bob", isFinal: false)
        XCTAssertEqual(a.result, "Come here. bob")
    }

    func testAudioBufferedBeforeAttachIsDelivered() async throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let pipe = AudioPipe(format: fmt)
        func buf() -> AVAudioPCMBuffer {
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1600)!
            b.frameLength = 1600
            return b
        }
        for _ in 0..<3 { pipe.handle(buf()) }                       // engine up, no analyzer yet
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        XCTAssertEqual(pipe.attach(cont), 3)
        pipe.handle(buf())                                          // live
        pipe.finish()
        var n = 0
        for await _ in stream { n += 1 }
        XCTAssertEqual(n, 4)
        XCTAssertEqual(pipe.buffersBefore, 3)
        XCTAssertEqual(pipe.buffersAfter, 1)
    }

    func testPreRollRingIsBounded() async {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let pipe = AudioPipe(format: fmt)
        for _ in 0..<100 {            // 10 s of audio
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1600)!; b.frameLength = 1600
            pipe.handle(b)
        }
        let (_, cont) = AsyncStream<AnalyzerInput>.makeStream()
        let kept = pipe.attach(cont)
        XCTAssertLessThanOrEqual(kept, 16)
        XCTAssertGreaterThan(kept, 5)
    }

    func testPostRollTuning() {
        XCTAssertEqual(VoiceAudioTuning.postRoll, 0.4, accuracy: 0.001)
        XCTAssertEqual(DictationSpeechInput().postRoll, VoiceAudioTuning.postRoll, accuracy: 0.001)
    }
}
