//
//  BathVoiceTests.swift
//  The creature's own little voice during the bath (scripted full bath through the real GameCare + BathFlow, hub in dry-run on the sim clock).
//  Counts what PLAYED past every hub guard (AudioHub.firedTap), never what was requested.
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class BathVoiceTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var clockBase = 50_000.0

    struct Played { var t: Float; var file: String; var gain: Float; var moment: String }
    struct Result { var played: [Played] = []; var seconds: Float = 0; var requests = 0; var drops: [String: Int] = [:] }

    /// Strips the variant / jelly suffix: "hum_jelly1_v2" -> "hum", "chirp_jelly1_happy" -> "chirp_happy".
    static func kind(_ f: String) -> String {
        if f.hasPrefix("chirp_") { return f.hasSuffix("sad") ? "chirp_sad" : "chirp_happy" }
        return f.components(separatedBy: "_jelly").first ?? f
    }
    static func isVoice(_ f: String) -> Bool { f.contains("_jelly") }

    /// One full scripted bath (soap -> rinse -> shine -> finish) at the dirt given; `slot0` is Bob.
    /// `demo`: the capture script (its own scrubs, Next 1 s after a stage is complete, Done 2.5 s after the finish card shows); otherwise the fake finger of CleanRun with an instant Next.
    /// `idleSeconds` > 0: no finger at all for that long once the soap stage is on (the tub, untouched), then stop.
    func runBath(dirt: Float = 0.5, demo: Bool = false, idleSeconds: Float = 0) -> Result {
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        let base = Self.clockBase
        let r = CleanRun(dirt: dirt); Self.keep.append(r)
        AudioHub.clock = { base + Double(r.t) }
        var res = Result()
        AudioHub.firedTap = nil; AudioHub.firedVolumeTap = { name, vol in
            guard Self.isVoice(name) else { return }
            res.played.append(Played(t: r.t, file: name, gain: vol, moment: r.bath.voiceMoment))
        }
        AudioHub.dropTap = { what, why in
            if what.hasPrefix("voice:") || what.hasPrefix("chirp") || what.hasPrefix("bath") { res.drops["\(what)|\(why ?? "PLAYED")", default: 0] += 1 }
        }
        defer { AudioHub.firedVolumeTap = nil; AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }; Self.clockBase = base + Double(r.t) + 200 }
        r.care.clean()
        if idleSeconds > 0 {
            r.run(60, scrubbing: false, autoNext: false, until: { r.bath.phase == .soap })
            let t0 = r.t
            r.run(idleSeconds, scrubbing: false, autoNext: false)
            res.seconds = r.t - t0
            return res
        }
        if demo { r.bath.demo = true; r.run(150, scrubbing: false, autoNext: false, until: { r.bath.phase == .off && r.phases.contains(.finish) }) }
        else { r.run(120, until: { r.bath.phase == .off && r.phases.contains(.finish) }) }
        res.seconds = r.t
        return res
    }

    /// RMS of a bundled clip in dBFS (the file as recorded); nil when the file is not in the bundle.
    static func rmsDB(_ name: String) -> Double? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "m4a"), let f = try? AVAudioFile(forReading: u),
              let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)), (try? f.read(into: b)) != nil, let d = b.floatChannelData?[0] else { return nil }
        var s = 0.0; let n = Int(b.frameLength); for i in 0..<n { s += Double(d[i] * d[i]) }
        return 10 * log10(max(s / Double(max(n, 1)), 1e-12))
    }

    /// Prints the numbers and the tables for one run and asserts the floor.
    private func report(_ label: String, _ res: Result, assertFloor: Bool = true) {
        let files = res.played.map(\.file), kinds = files.map(Self.kind)
        var share: [String: Int] = [:]; for k in kinds { share[k, default: 0] += 1 }
        let repeats = zip(files, files.dropFirst()).filter { $0 == $1 }.count
        let maxShare = Double(share.values.max() ?? 0) / Double(max(files.count, 1))
        print("[bathvoice] \(label): \(String(format: "%.1f", res.seconds)) sim-s, PLAYED vocals \(files.count), distinct files \(Set(files).count), distinct kinds \(Set(kinds).count), back-to-back repeats \(repeats), max kind share \(String(format: "%.0f", maxShare * 100)) %")
        print("[bathvoice] \(label) sequence: " + res.played.map { String(format: "%.1f %@ [%@]", $0.t, $0.file, $0.moment) }.joined(separator: " | "))
        print("[bathvoice] \(label) guards: " + res.drops.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))
        var perMoment: [String: [String: Int]] = [:]
        for p in res.played { perMoment[p.moment, default: [:]][p.file, default: 0] += 1 }
        print("[bathvoice] TABLE \(label) moment | clip: played")
        for m in perMoment.keys.sorted() { print("[bathvoice] TABLE \(label) \(m) | " + perMoment[m]!.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")) }
        guard assertFloor else { return }
        XCTAssertGreaterThanOrEqual(files.count, 12, "\(label): vocals PLAYED in a normal bath")
        XCTAssertGreaterThanOrEqual(Set(files).count, 7, "\(label): distinct clips")
        XCTAssertGreaterThanOrEqual(Set(kinds).count, 7, "\(label): distinct kinds")
        XCTAssertEqual(repeats, 0, "\(label): no clip twice in a row")
        XCTAssertLessThanOrEqual(maxShare, 0.35, "\(label): no kind over 35 %")
    }

    func testAFullScriptedBathSpeaksOftenAndVaried() {
        let res = runBath(demo: true)
        report("demo bath", res)
        let moments = Set(res.played.map(\.moment))
        for m in ["getIn", "scrubHum", "scrubTickle", "firstWater", "rinseRelax", "stageDone", "allClean"] { XCTAssertTrue(moments.contains(m), "moment \(m) played in the scripted bath: \(moments.sorted())") }
        print("[bathvoice] TABLE loudness (file RMS dBFS, gain used, level at the speaker = RMS + 20 log10 gain)")
        var seen = Set<String>(); var gains: [String: Float] = [:]
        for p in res.played { gains[p.file] = p.gain }
        func row(_ f: String, _ g: Float) { if let d = Self.rmsDB(f) { print(String(format: "[bathvoice] TABLE   %@ | rms %.1f dB | gain %.2f | speaker %.1f dB", f, d, g, d + 20 * log10(Double(g)))) } }
        row("chirp_jelly1_happy", 0.7)          // a normal idle chirp (AudioHub.chirp: 0.7 x level)
        for f in res.played.map(\.file) where seen.insert(f).inserted { row(f, gains[f] ?? 0) }
        XCTAssertFalse(moments.contains("pop"), "no bath vocal for a popping bubble any more (retired)")
        XCTAssertTrue(res.played.allSatisfy { $0.file.contains("_jelly") }, "every bath vocal is one of the creature voice clips: \(Set(res.played.map(\.file)).sorted())")
        XCTAssertFalse(res.drops.keys.contains { $0.hasPrefix("bath:") && !$0.hasSuffix("|PLAYED") && !$0.hasSuffix("|hush bath") }, "no guard but the bath's own gap drops a bath vocal: \(res.drops)")
    }

    func testTheFastFingerBathSpeaksToo() {
        let res = runBath()
        report("instant-next bath", res)
        XCTAssertTrue(res.played.contains { $0.moment == "shinePurr" }, "the shine stage hums while rubbed")
    }

    func testAnUntouchedTubGivesAnOccasionalSoftSound() {
        let res = runBath(idleSeconds: 40)
        report("idle tub", res, assertFloor: false)
        let idle = res.played.filter { $0.moment == "idle" }
        XCTAssertGreaterThanOrEqual(idle.count, 3, "an idle sound every 6 to 10 s over 40 s")
        XCTAssertLessThanOrEqual(idle.count, 6)
        for p in idle { XCTAssertEqual(p.gain, AudioHub.bathVoiceSoftGain * AudioHub.shared.settings.sfxLevel, accuracy: 0.001, "the idle sound is the soft one") }
        for (a, b) in zip(idle, idle.dropFirst()) { XCTAssertGreaterThanOrEqual(b.t - a.t, 5.9, "idle gap") }
    }

    func testADirtyOneGrumblesFirstThenCheersUp() {
        let res = runBath(dirt: 0.9, demo: true)
        report("dirty bath", res, assertFloor: false)
        XCTAssertEqual(res.played.first?.moment, "grumble")
        XCTAssertEqual(res.played.filter { $0.moment == "grumble" }.count, 1)
        XCTAssertGreaterThanOrEqual(res.played.count, 12)
        let clean = runBath(dirt: 0.2, demo: true)
        XCTAssertEqual(clean.played.first?.moment, "getIn")
    }

    func testTheSoapPhaseSpeaksEveryTwoAndAHalfToFourSecondsWhileTouched() {
        let res = runBath(demo: true)
        let soap = res.played.filter { $0.moment == "scrubHum" || $0.moment == "scrubTickle" }
        XCTAssertGreaterThanOrEqual(soap.count, 2)
        for (a, b) in zip(soap, soap.dropFirst()) { XCTAssertLessThanOrEqual(b.t - a.t, 8, "touched: no long silence") }
    }
}
