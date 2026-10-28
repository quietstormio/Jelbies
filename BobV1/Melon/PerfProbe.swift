//
//  PerfProbe.swift
//  Timing probes for the behaviour code that can be expensive (a toy's start, the steering look-ahead, a scooter loop's planning), off by default (one Bool test per call).
//  The tests switch it on and read `table`; each probe is also an os_signpost interval (category "toys", Instruments > os_signpost) while on.
//

import Foundation
import os

enum PerfProbe {
    nonisolated(unsafe) static var on = false
    nonisolated(unsafe) static var table: [String: (calls: Int, total: Double, max: Double)] = [:]
    private static let signposter = OSSignposter(subsystem: "io.mgsllc.BobV1", category: "toys")
    private static let tb: Double = { var i = mach_timebase_info_data_t(); mach_timebase_info(&i); return Double(i.numer) / Double(i.denom) / 1e6 }()

    /// Starts a probe: 0 when probes are off.
    @inline(__always) static func begin() -> UInt64 { on ? mach_absolute_time() : 0 }
    /// Ends it (the name is recorded under `table`, in ms).
    @inline(__always) static func end(_ name: String, _ t0: UInt64) {
        guard on, t0 != 0 else { return }
        let ms = Double(mach_absolute_time() - t0) * tb
        var e = table[name] ?? (0, 0, 0)
        e.calls += 1; e.total += ms; e.max = max(e.max, ms)
        table[name] = e
        if ms > 2 { signposter.emitEvent("slow", "\(name) \(ms) ms") }
    }
    static func reset() { table = [:] }
    static var report: String { table.sorted { $0.value.total > $1.value.total }.map { String(format: "%@: %d calls, total %.1f ms, mean %.3f, max %.2f", $0.key, $0.value.calls, $0.value.total, $0.value.total / Double(max($0.value.calls, 1)), $0.value.max) }.joined(separator: "\n") }
}
