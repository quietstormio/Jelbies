//
//  DevArgsStrip.swift
//  BobV1
//

import Foundation

extension DevArgs {
    /// Store build: launch arguments (`-Room loft`, `-RaceCourse splash`, ...) must not act as developer switches.
    /// Many read sites go straight to `UserDefaults.standard` without the `DevArgs.enabled` gate, so one central strip
    /// at app start empties the launch-argument (volatile) domain when developer arguments are off.
    /// Saved settings live in the app's own domain and are untouched. `removeVolatileDomain` does NOT clear
    /// `UserDefaults.argumentDomain`; setting it to an empty dictionary does.
    nonisolated static func stripLaunchArguments(enabled: Bool = DevArgs.enabled, defaults: UserDefaults = .standard) {
        guard !enabled else { return }
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    }
}
