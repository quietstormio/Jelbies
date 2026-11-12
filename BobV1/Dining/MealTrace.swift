//
//  MealTrace.swift
//  Simulator-only meal tracer + start-state arguments for the group-meal captures. On a device every call compiles to nothing.
//  `-MealTraceFile <path>`   appends `t=<s since the Feed order> <event>` lines to that file (opened once, written line by line so a killed app keeps them).
//  `-DiningSpot x,z`         forces the tray origin of the next group meal (once).
//  `-MealStart "x,z;x,z;.."` puts the Jelbies (in id order) on these floor points at the Feed order, right before the group starts (once).
//  `-MealOld 1`              turns the new meal-flow flags off (A/B captures).
//

import Foundation
import simd

nonisolated enum MealTrace {
    #if targetEnvironment(simulator)
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var t0: Double = 0
    nonisolated(unsafe) private static var opened = false
    private static func arg(_ name: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    private static func floats(_ s: String) -> [Float] { s.split(separator: ",").compactMap { Float($0) } }
    nonisolated(unsafe) static var spotOnce: SIMD2<Float>? = {
        guard let s = arg("-DiningSpot"), case let f = floats(s), f.count == 2 else { return nil }
        return SIMD2(f[0], f[1])
    }()
    nonisolated(unsafe) static var startOnce: [SIMD2<Float>]? = {
        guard let s = arg("-MealStart") else { return nil }
        let pts = s.split(separator: ";").map { floats(String($0)) }.filter { $0.count == 2 }.map { SIMD2<Float>($0[0], $0[1]) }
        return pts.isEmpty ? nil : pts
    }()
    static let old: Bool = arg("-MealOld") == "1"
    /// `-MealAwake <id>`: once every Jelbie is asleep, that one is woken 4 s later (case: two asleep, one awake).
    static let awakeID: Int? = arg("-MealAwake").flatMap { Int($0) }
    nonisolated(unsafe) static var awakeT: Float = 0
    nonisolated(unsafe) static var awakeDone = false
    private static let path: String? = arg("-MealTraceFile")
    #endif

    /// Single-flow trace state (GameCare+Dining.traceSingle).
    nonisolated(unsafe) static var singleActive = false

    /// True when `-MealOld 1` asks for the old behaviour (simulator only).
    static var oldFlow: Bool {
        #if targetEnvironment(simulator)
        return old
        #else
        return false
        #endif
    }

    /// The Feed order was just seen: the clock for every later line starts here.
    static func begin(_ what: @autoclosure () -> String) {
        #if targetEnvironment(simulator)
        guard let path else { return }
        if !opened {
            opened = true
            FileManager.default.createFile(atPath: path, contents: nil)
            handle = FileHandle(forWritingAtPath: path)
        }
        t0 = Date().timeIntervalSince1970
        write(String(format: "t=0.00 %@ epoch=%.3f", what(), t0))
        #endif
    }

    static func log(_ event: @autoclosure () -> String) {
        #if targetEnvironment(simulator)
        guard path != nil, handle != nil else { return }
        write(String(format: "t=%.2f ", Date().timeIntervalSince1970 - t0) + event())
        #endif
    }

    /// A line only when the text differs from the last one logged this way.
    static func logOnChange(_ event: @autoclosure () -> String) {
        #if targetEnvironment(simulator)
        guard path != nil else { return }
        let e = event()
        if e != lastChange { lastChange = e; log(e) }
        #endif
    }

    #if targetEnvironment(simulator)
    nonisolated(unsafe) private static var lastChange = ""
    private static func write(_ line: String) {
        handle?.seekToEndOfFile()
        handle?.write((line + "\n").data(using: .utf8) ?? Data())
    }
    #endif

    /// Simulator only: the one-shot tray origin from `-DiningSpot` (nil otherwise / once used).
    static func takeSpot() -> SIMD2<Float>? {
        #if targetEnvironment(simulator)
        defer { spotOnce = nil }
        return spotOnce
        #else
        return nil
        #endif
    }

    /// Simulator only: the one-shot start points from `-MealStart`.
    static func takeStarts() -> [SIMD2<Float>]? {
        #if targetEnvironment(simulator)
        defer { startOnce = nil }
        return startOnce
        #else
        return nil
        #endif
    }
}
