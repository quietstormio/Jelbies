//
//  MicTuning.swift
//  Developer-selectable mic behaviour. `overlapTail` is the off switch for the overlapping command tail (a press during the previous command's
//  post-roll / finalize opens at once). Default ON; `-MicOverlapTail 0|1` (dev arguments only) WRITES the value to the standard defaults
//  (key "MicOverlapTail") so it sticks for later normal launches until changed or the app is reinstalled.
//

import Foundation

nonisolated enum MicTuning {
    static let overlapKey = "MicOverlapTail"

    /// Call once at launch. A dev launch with `-MicOverlapTail 0|1` stores it; outside the dev gate nothing is written.
    static func applyLaunchArguments(devArgs: Bool = DevArgs.enabled, defaults: UserDefaults = .standard) {
        guard devArgs, defaults.object(forKey: overlapKey) != nil else { return }
        defaults.set(defaults.bool(forKey: overlapKey), forKey: overlapKey)
    }

    /// The switch as stored (true when none is stored). Outside the dev gate only a STORED value counts (the app's own persistent domain), never a launch argument.
    static func storedOverlap(devArgs: Bool = DevArgs.enabled, defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) -> Bool {
        if devArgs { return defaults.object(forKey: overlapKey) == nil ? true : defaults.bool(forKey: overlapKey) }
        let stored = domain.flatMap { defaults.persistentDomain(forName: $0) }?[overlapKey]
        return (stored as? Bool) ?? (stored as? NSNumber)?.boolValue ?? true
    }
    /// Test seam: nil = read the defaults.
    nonisolated(unsafe) static var overlapOverride: Bool?
    static var overlapTail: Bool { overlapOverride ?? storedOverlap() }
}
