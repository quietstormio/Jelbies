import Foundation

/// The home room's "walk around better" round (2026-11-15): they stop running into each other, do more emotes and things together, and speak more.
/// Three independent switches, all ON by default. A dev argument (`DevArgs.enabled`: Debug, the simulator and the owner's test builds only) turns one off and gives
/// exactly the behaviour from before the round: `-RoomTraffic 0`, `-RoomTogether 0`, `-RoomVoices 0`.
/// Every new code path is gated on one of the three brain properties below. They are true only for a body that is in the HOME room while no meal, drink or bath is on
/// (`homeRoom`, set by the stage) and that nothing owns right now (`roomFree`). The park, the races, the café, a meal, bedtime, the bath and the headless suites
/// (which never set `homeRoom`) stay on the old paths.
/// `-RoomTrace 1` (dev builds) writes the gates' activity into the meal trace file (`-MealTraceFile`): a proof aid.
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
    /// How often each step's gate said yes since launch (0 traffic, 1 together, 2 voices). The measuring test and the meal proof read it.
    nonisolated(unsafe) static var ran = [0, 0, 0]
    /// `-RoomTrace 1` (dev builds; the lines only reach a file in the simulator, with `-MealTraceFile`): the gates report into the meal trace, so one file shows that
    /// nothing of the round ran between a Feed order and the tray leaving. `room traffic on at=<epoch>` = the gate said yes after more than a second of silence;
    /// `room traffic n=<count> from=<epoch> to=<epoch>` = a closed batch of yeses (at most 2 s long).
    private static let traceOn = DevArgs.enabled && UserDefaults.standard.integer(forKey: "RoomTrace") == 1
    private static let stepNames = ["traffic", "together", "voices"]
    nonisolated(unsafe) private static var batchFrom: [Double] = [0, 0, 0]
    nonisolated(unsafe) private static var batchTo: [Double] = [0, 0, 0]
    nonisolated(unsafe) private static var batchN = [0, 0, 0]
    /// Every gate passes its answer through here.
    static func gate(_ step: Int, _ on: Bool) -> Bool {
        guard on else { return false }
        ran[step] += 1
        guard traceOn else { return true }
        let now = Date().timeIntervalSince1970
        let silent = now - batchTo[step] > 1
        if silent || now - batchFrom[step] >= 2 {
            if batchN[step] > 0 { MealTrace.log(String(format: "room %@ n=%d from=%.3f to=%.3f", stepNames[step], batchN[step], batchFrom[step], batchTo[step])) }
            if silent { MealTrace.log(String(format: "room %@ on at=%.3f", stepNames[step], now)) }
            batchFrom[step] = now; batchN[step] = 0
        }
        batchN[step] += 1; batchTo[step] = now
        return true
    }
}

extension BlobBrain {
    /// Nothing owns him right now: no request is being served or queued (a call, the walk to the tray, a drink), no player command or goodnight is running, no meal
    /// reservation / close-up / bath / play hold is on, and he is not on his way to bed or asleep. A body that is not free keeps the code from before the round.
    var roomFree: Bool {
        autonomy && job == nil && pending == nil && !commanded && !commandedGoodnight && !held && !focusPaused && idleState.kind != .sleep
    }
    /// Step 1 is live for this body: a free body in the home room that is not in a social session (a walk-up to a friend keeps its own arrival code).
    var roomTraffic: Bool { RoomRoam.gate(0, homeRoom && RoomRoam.traffic && roomFree && social == nil) }
    /// Step 2 is live for this body.
    var roomTogether: Bool { RoomRoam.gate(1, homeRoom && RoomRoam.together && roomFree) }
    /// Step 3 is live for this body.
    var roomVoices: Bool { RoomRoam.gate(2, homeRoom && RoomRoam.voices && roomFree) }
}
