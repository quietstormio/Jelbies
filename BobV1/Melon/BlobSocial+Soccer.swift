//
//  BlobSocial+Soccer.swift
//  The pass social (BlobSocial+Pass.swift) with the soccer ball: the kicker takes the stomp step a beat before the ball leaves (the same step as the solo
//  kick, BlobBrain+Soccer.swift) and the pass speed stays in the ball's kick range. Two Jellies, 2...4 passes, as before.
//

import Foundation
import simd

extension BlobBrain {
    /// Phase 1 of the pass, every tick: the stomp step at t = 0.12 (the ball leaves at 0.38 as the foot lands).
    func soccerPassStomp(_ s: SocialSession, _ t: Float) {
        if t < 0.1 { socialBook.hopStarted2 = false }
        if !socialBook.hopStarted2, t >= 0.12, !feet.active {
            socialBook.hopStarted2 = true
            idleFootStep(reach: SoccerTuning.stompReach, rate: SoccerTuning.stompRate, peak: SoccerTuning.stompPeak)
        }
    }
    /// The pass kick: toward the friend, stopping about a body-length short of him, within the ball's kick speeds.
    func soccerPassKick(_ uid: Int, direction dir: SIMD2<Float>, roll: Float) {
        let speed = min(max(SoccerTuning.linearDecayPerS * roll + 0.1, SoccerTuning.kickSpeed.lowerBound), SoccerTuning.kickSpeed.upperBound)
        DecorField.shared.kickBall(uid, direction: dir, speed: speed, by: steerID)
        SoccerState.shared.newKick(uid)
        SoccerEvents.emit(.kick(jelly: steerID, speed: speed, shot: false))
    }
}
