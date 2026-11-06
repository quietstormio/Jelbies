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
        if t < 0.1 { socialBook.hopStarted2 = false; socialBook.soccerReturned = false }
        if !socialBook.hopStarted2, t >= 0.12, !feet.active {
            socialBook.hopStarted2 = true
            idleFootStep(reach: SoccerTuning.stompReach, rate: SoccerTuning.stompRate, peak: SoccerTuning.stompPeak)
            socialBook.soccerStompSide = feet.side
        }
        // the ball has left (t = 0.38) and the stomp foot has landed (the swing is over; the kicker may have been mid-step when the pass began, so the landing can come after 0.38): the kicking foot comes straight back under him (it used to stay out ahead for the rest of the pass)
        if socialBook.hopStarted2, !socialBook.soccerReturned, t >= 0.38, !feet.swinging {
            socialBook.soccerReturned = true
            nextSwing = socialBook.soccerStompSide
            idleFootStep(reach: 0, rate: SoccerTuning.returnRate, peak: SoccerTuning.returnPeak)
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
