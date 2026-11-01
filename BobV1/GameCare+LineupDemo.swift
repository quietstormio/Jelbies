//
//  GameCare+LineupDemo.swift
//  Capture aid (like GameFeedAfterCall): `-LineupDemo come|meal` asks for the group line-up 6 s after the game starts, so a screenshot loop can film it.
//

import Foundation

extension GameCare {
    func lineupDemoTick(dt: Float) {
        guard let mode = UserDefaults.standard.string(forKey: "LineupDemo"), !mode.isEmpty, jellies.count > 1 else { return }
        let before = lineupDemoClock
        lineupDemoClock += dt
        guard before < 6, lineupDemoClock >= 6 else { return }
        if mode == "come" { comeHereEveryone() } else { drink() }
    }
}
