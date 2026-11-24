//
//  MoveCrowd.swift
//  move-crowd-r1 (owner 11-24: "The collisions and crowding is killing the game"). Fewer bumps BY CONSTRUCTION for free, autonomous walkers (no job, no command, no social, no choreography).
//  ONE master switch: `MoveCrowd.on` (DevArgs `-MoveCrowd 0` or env MOVECROWD=0 = exactly the old steering). Parts, each its own sub-switch (env MOVECROWD_OFF=part,goal,... turns parts off
//  for a measurement; every number below has an env seam so a headless iteration needs no rebuild):
//    gap    one constant `gap` (1.45, just outside the 1.4 push radius) for the look-ahead trigger and the detour point (each walker clears the other's predicted spot by it alone)
//    goal   a roam goal is rejected if another body stands within `gap` of it or is walking to a spot within `gap` of it
//    yield  symmetric give-way: the one who is slower to the meeting / has less far to go waits (was always the lower id)
//    look   a walker on a waypoint leg looks ahead too
//    part   after a pair / group moment the members leave to different sides, staggered
//  The gait and the run are untouched (heading, route and start / stop timing only).
//

import Foundation
import simd

nonisolated enum MoveCrowd {
    private static let env = ProcessInfo.processInfo.environment
    private static func master() -> Bool {
        if let e = env["MOVECROWD"] { return e != "0" }
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "MoveCrowd") else { return defaultOn }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    static let defaultOn = false
    nonisolated(unsafe) static var on: Bool = master()
    private static let offParts = Set((env["MOVECROWD_OFF"] ?? "").split(separator: ",").map { String($0) })
    private static func part(_ k: String) -> Bool { !offParts.contains(k) }
    nonisolated(unsafe) static var gapOn = part("gap")
    nonisolated(unsafe) static var goalOn = part("goal")
    nonisolated(unsafe) static var yieldOn = part("yield")
    nonisolated(unsafe) static var lookOn = part("look")
    nonisolated(unsafe) static var partOn = part("part")
    private static func num(_ k: String, _ d: Float) -> Float { Float(env[k] ?? "") ?? d }

    /// The one clearance (u, centre to centre): trigger, detour offset, goal rejection.
    nonisolated(unsafe) static var gap = num("MOVECROWD_GAP", 1.45)

    static var text: String { "MoveCrowd on=\(on) gap=\(gapOn) goal=\(goalOn) yield=\(yieldOn) look=\(lookOn) part=\(partOn) gapU=\(gap)" }
}

/// Read by the scoreboard (tests): the switches as they stand.
enum MoveCrowdInfo { static var text: String { MoveCrowd.text } }
