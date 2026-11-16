//
//  FoodCaptureArgs.swift
//  The meal capture arguments (`-FoodSeed 1`, `-GameAction feed:<food id>`) act only where dev arguments are on, like the other capture aids (see ReleaseSwitchesTests).
//

import Foundation

nonisolated enum FoodCaptureArgs {
    /// `-FoodSeed 1`: three of each power-up food in the bag.
    static func foodSeed(devArgs: Bool = DevArgs.enabled, defaults: UserDefaults = .standard) -> Bool { devArgs && defaults.integer(forKey: "FoodSeed") != 0 }
    /// `-GameAction feed:<food id>`: the food id, nil when the action is not that or dev arguments are off.
    static func feedID(_ action: String, devArgs: Bool = DevArgs.enabled) -> String? { devArgs && action.hasPrefix("feed:") ? String(action.dropFirst(5)) : nil }
}
