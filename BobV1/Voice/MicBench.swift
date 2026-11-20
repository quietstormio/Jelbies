//
//  MicBench.swift
//  Developer launch argument `-MicBench N` (inside the DevArgs gate: it does nothing in an App Store build): once the room has been on screen for
//  6 s it makes N presses of 1.5 s through the SAME `VoiceCoordinator.begin()` / `release()` the mic button uses (each press waits until the
//  previous one has settled, at least 3 s after the release and 2 s after its put-back, so the control window is quiet), then 2 quick re-presses
//  (each 0.6 s after the previous release). One `[micbench] press ...` line per press (NSLog + Documents/micbench.log); a dropped press is a line
//  with the reason; the last line is `[micbench] done` with the median of every field. Afterwards the app runs on. `-MicVariant <name>` is printed
//  on every line (deliverable 2 picks a variant with it; only `base` exists here). Pull the file with
//    devicectl device copy from --domain-type appDataContainer --domain-identifier io.mgsllc.BobV1 --source Documents/micbench.log
//

import Foundation
import QuartzCore

nonisolated enum MicBench {
    /// N presses asked for; 0 where dev arguments are off (a store build), whatever the saved defaults say. Never persisted by this code.
    static func count(devArgs: Bool = DevArgs.enabled, defaults: UserDefaults = .standard) -> Int {
        guard devArgs else { return 0 }
        return max(0, defaults.integer(forKey: "MicBench"))
    }
    /// The variant name printed on every line ("base" when none, and always "base" where dev arguments are off).
    static func variant(devArgs: Bool = DevArgs.enabled, defaults: UserDefaults = .standard) -> String {
        guard devArgs, let v = defaults.string(forKey: "MicVariant"), !v.isEmpty else { return "base" }
        let ok = v.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return ok.isEmpty ? "base" : String(ok.prefix(24))
    }
    /// True while the bench runs (the trace then leaves printing to the bench).
    nonisolated(unsafe) static var active = false
    nonisolated(unsafe) private static var started = false

    /// GameScreen's task: waits for the room (first frame drawn), 6 s more, then runs. Once per launch.
    @MainActor
    static func runIfRequested(model: MelonModel) async {
        let n = count()
        guard n > 0, !started else { return }
        started = true
        for _ in 0..<1200 where model.status != .live { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .seconds(6))
        await run(voice: model.care.voice, count: n)
    }

    /// The scripted presses. `hold`, `settle` and `quickGap` are the brief's 1.5 s, 3 s and 0.6 s (tests shorten them).
    @MainActor
    static func run(voice: VoiceCoordinator, count n: Int, hold: Double = 1.5, settle: Double = 3.0, quickGap: Double = 0.6, afterPutBack: Double = 2.05,
                    emit: @escaping @Sendable (String) -> Void = { l in MicTrace.q.async { MicTrace.emit(l) } }) async {
        active = true
        defer { active = false }
        let variant = Self.variant()
        var traces: [PressTrace] = []
        var dropped = 0
        var number = 0

        /// One press. Returns the release time (nil when the press was dropped).
        func press(quick: Bool) async -> PressTrace? {
            number += 1
            let reason = voice.traceDropReason
            guard voice.begin() else {
                dropped += 1
                emit("[micbench] press \(number) variant=\(variant) quick=\(quick ? 1 : 0) DROPPED overlap=\(MicTuning.overlapTail ? 1 : 0) reason=\(reason)")
                return nil
            }
            let tr = MicTrace.latest
            tr?.quick = quick
            try? await Task.sleep(for: .seconds(hold))
            let wasListening = voice.isListening
            voice.release()
            if let tr {
                traces.append(tr)
                tr.whenFinished { if let s = tr.summary { emit(s.line(number: tr.number, cold: tr.cold, variant: variant)) } }          // the press's line, as soon as its window closed
                if !wasListening { MicTrace.abandon(tr, reason: "release-ignored: not listening") }
            }
            return tr
        }
        func settled(_ tr: PressTrace?) async {
            guard let tr else { try? await Task.sleep(for: .seconds(settle)); return }
            let t = tr.time(.release) ?? CACurrentMediaTime()
            await finished(tr, timeout: 12)
            let pb = tr.time(.putBack) ?? CACurrentMediaTime()
            let wait = max(t + settle, pb + afterPutBack) - CACurrentMediaTime()
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }

        for i in 0..<n {
            let tr = await press(quick: false)
            if i < n - 1 { await settled(tr) }
            else { try? await Task.sleep(for: .seconds(quickGap)) }          // the last one goes straight into the quick re-presses
        }
        for _ in 0..<2 {
            _ = await press(quick: true)
            try? await Task.sleep(for: .seconds(quickGap))
        }
        for tr in traces { await finished(tr, timeout: 12) }
        try? await Task.sleep(for: .milliseconds(300))          // (the last line is on its queue)
        let sums = traces.compactMap(\.summary)
        emit(doneLine(variant: variant, presses: traces.count, dropped: dropped, sums: sums))
    }

    nonisolated private static func finishedOrTimeout(_ tr: PressTrace, seconds: Double) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let once = OnceBox(c)
            tr.whenFinished { once.resume() }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume() }
        }
    }
    @MainActor private static func finished(_ tr: PressTrace, timeout: Double) async { await finishedOrTimeout(tr, seconds: timeout) }

    private final class OnceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var c: CheckedContinuation<Void, Never>?
        init(_ c: CheckedContinuation<Void, Never>) { self.c = c }
        func resume() { lock.lock(); let x = c; c = nil; lock.unlock(); x?.resume() }
    }

    /// The median of every numeric field over the presses that measured it.
    static func medians(_ sums: [PressSummary]) -> [(String, Double)] {
        guard let first = sums.first else { return [] }
        var out: [(String, Double)] = []
        for (i, (k, _)) in first.fields.enumerated() {
            let v = sums.compactMap { $0.fields.count > i && $0.fields[i].0 == k ? $0.fields[i].1 : nil }.sorted()
            if !v.isEmpty { out.append((k, v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2)) }
        }
        return out
    }

    static func doneLine(variant: String, presses: Int, dropped: Int, sums: [PressSummary]) -> String {
        "[micbench] done variant=\(variant) presses=\(presses) dropped=\(dropped) median: " + medians(sums).map { "\($0.0)=\(PressSummary.fmt($0.1))" }.joined(separator: " ")
    }
}
