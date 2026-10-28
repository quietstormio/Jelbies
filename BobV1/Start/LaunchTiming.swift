//
//  LaunchTiming.swift
//  Cold-launch timings in the "[melon]" log style: marks are seconds since the first mark (process start side), and `span` logs how long a
//  start-up chunk took. Cheap enough to leave on; the lines are `[melon] launch: <what> ...`.
//

import Foundation
import QuartzCore

nonisolated enum LaunchTiming {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var t0: CFTimeInterval = 0
    nonisolated(unsafe) private static var seen = Set<String>()

    /// Logs `what` once, with the time since the first mark.
    static func mark(_ what: String) {
        let now = CACurrentMediaTime()
        lock.lock()
        if t0 == 0 { t0 = now }
        let first = seen.insert(what).inserted, t = now - t0
        lock.unlock()
        if first { NSLog("%@", String(format: "[melon] launch: %@ at +%.3f s", what, t)) }
    }

    /// Runs `body`, logging how long it took (and on which thread kind).
    @discardableResult
    static func span<T>(_ what: String, _ body: () throws -> T) rethrows -> T {
        let s = CACurrentMediaTime()
        defer { NSLog("%@", String(format: "[melon] launch: %@ took %.1f ms%@", what, (CACurrentMediaTime() - s) * 1000, Thread.isMainThread ? " (main)" : " (bg)")) }
        return try body()
    }
}
