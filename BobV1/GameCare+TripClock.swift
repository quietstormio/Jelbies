//
//  GameCare+TripClock.swift
//  Being out (Park, Café, Groomer) takes a little while: on the way home the Jelbies who went get a small extra step of time on the ONE existing
//  time-away path (`BlobNeeds.applyAway`, the gentle away curve with its floor), so the day moves a bit faster for them. No second clock.
//  After the Park they are also a little thirstier (they played).
//

import Foundation

enum TripClockTuning {
    /// Real seconds of away time applied to the Jelbies who went out (hunger -4.5 %, thirst -5.6 %, attention -7.5 % on the away curve).
    static let outAway: TimeInterval = 2700
    /// Extra thirst lost after the Park (on top of the step above).
    static let parkThirst: Float = 0.10
}

extension GameCare {
    /// `ids`: the roster ids that were out. `thirst`: the extra thirst to take off (the Park only).
    func tripReturned(_ ids: [Int], extraThirst thirst: Float = 0) {
        for id in ids {
            guard let j = jelly(id) else { continue }
            j.needs.applyAway(seconds: TripClockTuning.outAway)
            if thirst > 0 { j.needs.gain(.thirst, -thirst) }
            j.needs.save()
        }
    }
}
