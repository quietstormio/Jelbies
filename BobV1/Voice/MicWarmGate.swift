//
//  MicWarmGate.swift
//  The speculative "bring the mic up" shared by the real input and the fake. A FAILED warm-up is never handed to the next press
//  (that was the "double-tap-hold has to be done twice" bug): `ready` retries once, and teardown invalidates.
//

import Foundation

@MainActor
final class MicWarmGate {
    typealias Make = () async -> Bool           // true = engine running

    private var task: Task<Bool, Never>?
    private var failed = false
    /// Number of warm-ups started (tests).
    private(set) var makes = 0

    nonisolated init() {}
    nonisolated deinit {}

    var isWarming: Bool { task != nil }

    /// Starts a warm-up unless one is in flight or succeeded. A finished FAILED one is replaced.
    func warm(_ make: @escaping Make) {
        guard task == nil || failed else { return }
        failed = false
        makes += 1
        task = Task { [weak self] in
            let ok = await make()
            if !ok { self?.failed = true }
            return ok
        }
    }

    /// The in-flight warm-up's result, if any (nil when none was started).
    func value() async -> Bool? { await task?.value }

    /// Awaits the warm engine (starting one if none). When it failed, or `stillRunning()` says the engine died, `beforeRetry` runs
    /// and a fresh one is brought up, up to `retries` more times.
    func ready(retries: Int = VoiceAudioTuning.warmRetries, stillRunning: () -> Bool,
               _ make: @escaping Make, beforeRetry: () -> Void) async -> Bool {
        if task == nil { warm(make) }
        var left = retries
        while true {
            let ok = await task?.value ?? false
            if ok && stillRunning() { return true }
            guard left > 0 else { return false }
            left -= 1
            VoiceTranscriptLog.log(ok ? "warm engine not running -> retry" : "warm-up failed -> retry")
            beforeRetry()
            invalidate()
            warm(make)
        }
    }

    func invalidate() { task = nil; failed = false }
}
