//
//  WearPreviewLog.swift
//  Timing lines for the shop's fitting-room picture, appended to the file named by the launch argument `-WearPreviewLog <path>`. Off (a no-op) without it.
//

import Foundation

nonisolated enum WearPreviewLog {
    static let path: String? = UserDefaults.standard.string(forKey: "WearPreviewLog")
    static func write(_ line: String) {
        guard let path else { return }
        let l = String(format: "%.3f ", Date().timeIntervalSince1970) + line + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(l.utf8)); try? h.close() }
        else { try? l.write(toFile: path, atomically: false, encoding: .utf8) }
    }
}
