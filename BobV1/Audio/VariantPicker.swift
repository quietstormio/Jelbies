//
//  VariantPicker.swift
//  Random variant of a sound, never the same twice in a row.
//

import Foundation

nonisolated struct VariantPicker: Sendable {
    private var last: [String: Int] = [:]
    init() {}
    mutating func pick(_ key: String, count: Int, r: Double = Double.random(in: 0..<1)) -> Int {
        guard count > 1 else { return 0 }
        var i = min(count - 1, Int(r * Double(count)))
        if let l = last[key], l == i { i = (i + 1 + Int(r * 7) % (count - 1)) % count }
        last[key] = i
        return i
    }
}
