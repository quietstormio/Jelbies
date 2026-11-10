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
    /// `warm` would start a new warm-up right now (none in flight, or the last one failed).
    var wouldWarm: Bool { task == nil || failed }
    /// The current warm task finished and failed, and nothing has replaced it.
    var isSettledFailed: Bool { task != nil && failed }

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

/// Cancels the hub's queued `.ambient` put-back when the mic is pressed again before it ran. Every release queues a put-back on
/// `AudioSessionQueue` (AudioHub.setUpSession); a quick re-press would otherwise run it first and bounce the session
/// (`.playAndRecord` -> `.ambient` -> `.playAndRecord`) before the mic could start. Thread-safe: queued blocks check it on the session queue.
nonisolated final class PutBackGate: @unchecked Sendable {
    static let shared = PutBackGate()
    private let lock = NSLock()
    private var generation = 0
    private var pending = 0
    private var skipped = 0
    init() {}

    /// A put-back is being queued: the generation it must still match when it runs.
    func enqueue() -> Int { lock.lock(); defer { lock.unlock() }; pending += 1; return generation }
    /// The queued block is running: false = a newer mic press voided it, skip it.
    func shouldRun(_ gen: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        pending = max(0, pending - 1)
        if gen != generation { skipped += 1; return false }
        return true
    }
    /// A mic bring-up is starting: every put-back still queued is void. Returns how many were pending.
    @discardableResult
    func voidQueued() -> Int {
        lock.lock(); defer { lock.unlock() }
        let n = pending
        if n > 0 { generation += 1 }
        return n
    }
    var skippedTotal: Int { lock.lock(); defer { lock.unlock() }; return skipped }
    var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return pending }
}
