//
//  JLog.swift
//  show-perfect-r1: a small persistent RING LOG for what the phone's own console cannot give back (the unified log can't be pulled off a device without root).
//  Application Support/jlog.txt, at most ~2000 lines (the oldest are dropped), one line each: "MM-dd HH:mm:ss.SSS up=<s> [cat] text". The Jelly Show's flow steps (rounds, picks, queued picks, Skip, Home,
//  walk-back snaps) and the audio's events (scene asks, voice start / stop, engine start / stop, interruptions, route / category changes, watchdog restarts). No names, no text the player typed, no PII.
//  Cheap: a serial background queue appends to the file; the app's frames never wait on it. Release-safe (always on, ~100 bytes a line, a few lines a second at the most).
//
//  Pull it from a phone (the app must be installed; no root needed):
//      xcrun devicectl device copy from --device <name or id> --domain-type appDataContainer --domain-identifier <bundle id> --source Library/Application\ Support/jlog.txt --destination ./jlog.txt
//

import Foundation

nonisolated enum JLog {
    static let keep = 2000
    private static let queue = DispatchQueue(label: "jlog", qos: .utility)
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var lines = -1
    nonisolated(unsafe) private static var overridePath: String?
    private static let enabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil || ProcessInfo.processInfo.environment["JLOG_FORCE"] != nil

    static var path: String {
        if let o = overridePath { return o }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("jlog.txt").path
    }
    /// Tests: write to another file (and always write).
    static func redirect(to p: String?) { queue.sync { handle = nil; lines = -1; overridePath = p } }

    static func show(_ s: String) { write("show", s) }
    static func audio(_ s: String) { write("audio", s) }

    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss.SSS"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    static func write(_ cat: String, _ s: String) {
        guard enabled || overridePath != nil else { return }
        let up = ProcessInfo.processInfo.systemUptime
        let now = Date()
        queue.async {
            let line = "\(stamp.string(from: now)) up=\(String(format: "%.1f", up)) [\(cat)] \(s.replacingOccurrences(of: "\n", with: " "))\n"
            append(line)
        }
    }

    private static func append(_ line: String) {
        let p = overridePath ?? path
        if handle == nil {
            if !FileManager.default.fileExists(atPath: p) { FileManager.default.createFile(atPath: p, contents: nil) }
            handle = FileHandle(forWritingAtPath: p)
            _ = try? handle?.seekToEnd()
            if lines < 0 { lines = (FileManager.default.contents(atPath: p)?.reduce(0) { $1 == 10 ? $0 + 1 : $0 }) ?? 0 }
        }
        handle?.write(Data(line.utf8)); lines += 1
        if lines > keep + 400 { trim(p) }
    }

    /// Drops the oldest lines (every 400 lines: a rewrite of ~200 KB at most).
    private static func trim(_ p: String) {
        try? handle?.close(); handle = nil
        guard let d = FileManager.default.contents(atPath: p), let text = String(data: d, encoding: .utf8) else { lines = 0; return }
        let all = text.split(separator: "\n", omittingEmptySubsequences: true)
        let kept = all.suffix(keep).joined(separator: "\n") + "\n"
        try? kept.write(toFile: p, atomically: true, encoding: .utf8)
        lines = min(all.count, keep)
    }

    /// Tests: waits for the queue.
    static func flush() { queue.sync {} }
}
