//
//  RelayModel.swift
//  Jelly Circuit RELAY: three teams (the player's and two rival teams) of three runners each. The course is split into three legs; runner 2 and 3 wait at a
//  handoff box (a line, then `RelayTuning.boxGap` of floor to stand on) and start the moment the runner before him crosses the line.
//
//  The rules are the ordinary race's: `RaceSim` has one racer per TEAM and swaps the runner at each handoff line (`RaceSim.configureRelay`), so the tap
//  model, trips, look-arounds, hurdles, rival AI, finish grace and placings are all the race's own. This file is the pure part (no bodies, no screen).
//

import Foundation
import simd

nonisolated enum RelayTuning {
    /// JellyCoins by TEAM place (1-based).
    static let prizes = [30, 18, 10]
    static func prize(place: Int) -> Int { prizes[min(max(place, 1), prizes.count) - 1] }
    static let legCount = 3
    /// Floor between the handoff line and the waiting runner's spot (world units): more than a body length, so the incoming runner never touches him.
    static let boxGap: Float = 1.3
    /// A waiting runner starts bouncing when the runner before him is this close to the line.
    static let bounceAhead: Float = 3.0
    /// Seconds between his bounces.
    static let bounceEvery: Float = 0.8
    /// A Park friend's stats: a steady, average runner.
    static let friendStats = RacerStats(waddle: 0.5, focus: 0.6)
    /// Lane of team `t`: the player's team in the middle, the rivals either side.
    static let lanes = [1, 0, 2]

    /// Arc lengths of a course of `length`: where each leg starts (the waiting spots) and where each leg ends (the handoff lines, then the finish).
    static func legs(length: Float) -> (starts: [Float], ends: [Float]) {
        let run = (length - Float(legCount - 1) * boxGap) / Float(legCount)
        let starts = (0..<legCount).map { Float($0) * (run + boxGap) }
        return (starts, starts.map { $0 + run })
    }
}

/// One runner of a team: who, how good, whether a Park friend (AI) runs him, and where his leg starts (arc length).
nonisolated struct RelayLeg: Equatable, Sendable {
    var name: String
    var stats: RacerStats
    var ai: Bool
    var startDist: Float
}

/// Who runs, as the care glue decides it (the bodies are chosen later, under the white).
nonisolated struct RelayPlan: Sendable {
    /// One entry per team: its three runners in leg order. Team 0 is the player's.
    var teams: [[RelayLeg]]
    var teamNames: [String]
    /// Team 0's runner ids per leg: the roster id of an owned Jelbie, nil for a Park friend (then `friendIDs`' next entry).
    var ownedIDs: [Int?]
    var friendIDs: [Int]
    /// The Park visitors that run the rival teams (ParkVisitor ids), team 1 then team 2, in leg order.
    var rivalVisitorIDs: [Int]
    var course: RaceCourse

    var lines: [Float] { Array(RelayTuning.legs(length: course.length).ends.dropLast()) }
}

extension RelayPlan {
    /// The sim for this plan: one racer per team (team 0 = the player's), legs configured.
    func makeSim(seed: UInt64) -> RaceSim {
        let rivals = teams.dropFirst().map { Rival(name: $0[0].name, tint: SIMD3(0.8, 0.8, 0.8), stats: $0[0].stats) }
        var sim = RaceSim(player: teams[0][0].stats, playerName: teams[0][0].name, rivals: Array(rivals), seed: seed, course: course)
        sim.configureRelay(lines: lines, legs: teams)
        return sim
    }
}
