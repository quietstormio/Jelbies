//
//  BlobBrain+ChatOverlay.swift
//  cafe-talk-r1: the small in-place body language of the café table talk. An additive overlay on the standing pose (a nod, a lean toward the one he talks to, a slight look,
//  the arms lifted a little, the mouth moving): it never touches the feet, the root or the heading (`yaw`), so a body that talks stays on its stand and keeps its facing.
//  The conversation (CafeChat.swift) only sets goals; the brain eases to them and lets go by itself `hold` seconds after the last goal.
//

import Foundation

struct ChatOverlay {
    /// What the conversation asked for (rad): a steady lean forward (pitch) and to the side (roll, + = toward increasing yaw), a look (twist) and the arms up (0...1).
    var leanPitch: Float = 0, leanRoll: Float = 0, look: Float = 0, arm: Float = 0
    /// A nod / talking bob on top: amplitude (rad forward) and rate (Hz); the mouth flap amount (0...1).
    var bobAmp: Float = 0, bobHz: Float = 2.2, mouth: Float = 0
    /// Seconds the goals stay valid (a refreshed goal restarts it); 0 = nothing asked.
    var hold: Float = 0
    // eased values (what the pose really adds)
    var pitch: Float = 0, roll: Float = 0, twist: Float = 0, armW: Float = 0, mouthNow: Float = 0
    var phase: Float = 0
    var active: Bool { hold > 0 || abs(pitch) > 1e-4 || abs(roll) > 1e-4 || abs(twist) > 1e-4 || armW > 1e-3 || mouthNow > 1e-3 }

    mutating func tick(_ dt: Float) {
        if hold > 0 { hold -= dt } else { leanPitch = 0; leanRoll = 0; look = 0; arm = 0; bobAmp = 0; mouth = 0 }
        phase += dt * bobHz * 2 * .pi
        let k = min(1, dt * 7)
        let bob = bobAmp * (0.5 - 0.5 * cosf(phase))          // (a dip forward and back up: never backwards)
        pitch += (leanPitch + bob - pitch) * k
        roll += (leanRoll - roll) * k
        twist += (look - twist) * k
        armW += (arm - armW) * min(1, dt * 6)
        let flap = mouth * (0.35 + 0.35 * sinf(phase * 2.3))
        mouthNow += (flap - mouthNow) * min(1, dt * 18)
        if hold <= 0, !active { self = ChatOverlay() }
    }
}

extension BlobBrain {
    /// Ask for a bit of table-talk body language for `hold` seconds (the caps keep every lean small: a face never comes near another face, the heading never changes).
    func chatPose(lean: Float = 0, toward bearing: Float = 0, look: Float = 0, bob: Float = 0, bobHz: Float = 2.2, arm: Float = 0, mouth: Float = 0, hold: Float) {
        let l = min(max(lean, 0), 0.09)
        chat.leanPitch = l * cosf(bearing)
        chat.leanRoll = l * sinf(bearing)
        chat.look = max(-0.1, min(0.1, look))
        chat.bobAmp = min(max(bob, 0), 0.07); chat.bobHz = bobHz
        chat.arm = min(max(arm, 0), 1); chat.mouth = min(max(mouth, 0), 1)
        chat.hold = max(chat.hold, hold)
    }
    /// Let go at once (the overlay eases out).
    func chatPoseClear() { chat.hold = 0 }
}
