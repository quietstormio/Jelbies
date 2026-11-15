import Foundation

/// The home room's "walk around better" round (2026-11-15): they stop running into each other, do more emotes and things together, and speak more.
/// Three independent switches, all ON by default. A dev argument (`DevArgs.enabled`: Debug, the simulator and the owner's test builds only) turns one off and gives
/// exactly the behaviour from before the round: `-RoomTraffic 0`, `-RoomTogether 0`, `-RoomVoices 0`.
/// Every new code path is gated on one of the three brain properties below. They are true only for a body that is in the HOME room while no meal, drink or bath is on
/// (`homeRoom`, set by the stage) and that nothing owns right now (`roomFree`). The park, the races, the café, a meal, bedtime, the bath and the headless suites
/// (which never set `homeRoom`) stay on the old paths.
nonisolated enum RoomRoam {
    private static func devSwitch(_ key: String) -> Bool {
        !(DevArgs.enabled && UserDefaults.standard.object(forKey: key) != nil && UserDefaults.standard.integer(forKey: key) == 0)
    }
    /// Step 1: they stop running into each other (steering, goal choice).
    nonisolated(unsafe) static var traffic = devSwitch("RoomTraffic")
    /// Step 2: more emotes alone, more interaction together.
    nonisolated(unsafe) static var together = devSwitch("RoomTogether")
    /// Step 3: more Jelmiko voices that fit what they are doing.
    nonisolated(unsafe) static var voices = devSwitch("RoomVoices")
}

extension BlobBrain {
    /// Nothing owns him right now: no request is being served or queued (a call, the walk to the tray, a drink), no player command or goodnight is running, no meal
    /// reservation / close-up / bath / play hold is on, and he is not on his way to bed or asleep. A body that is not free keeps the code from before the round.
    var roomFree: Bool {
        autonomy && job == nil && pending == nil && !commanded && !commandedGoodnight && !held && !focusPaused && idleState.kind != .sleep
    }
    /// Step 1 is live for this body: a free body in the home room that is not in a social session (a walk-up to a friend keeps its own arrival code).
    var roomTraffic: Bool { homeRoom && RoomRoam.traffic && roomFree && social == nil }
    /// Step 2 is live for this body.
    var roomTogether: Bool { homeRoom && RoomRoam.together && roomFree }
    /// Step 3 is live for this body.
    var roomVoices: Bool { homeRoom && RoomRoam.voices && roomFree }
}
