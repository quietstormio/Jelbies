//
//  PerfOverlay.swift
//  Which SwiftUI overlays are over the Metal view right now, as one short tag string ("menu+bag", "place", ...). The game screen sets it when its
//  overlay state changes; the renderer folds it into the PerfMeter `ctx:` note so a slow GPU window can be matched to the overlay that was up
//  (Liquid Glass / material compositing shares the GPU with the app).
//

import Foundation

nonisolated enum PerfOverlay {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var tags = ""
    static func set(_ list: [String]) { lock.lock(); tags = list.sorted().joined(separator: "+"); lock.unlock() }
    static var current: String { lock.lock(); defer { lock.unlock() }; return tags }
}
