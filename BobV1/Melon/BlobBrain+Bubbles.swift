//
//  BlobBrain+Bubbles.swift
//  What a Jelbie does about the bubble wand's bubbles, built ONLY from moves that already exist (so the feet suites already cover them): a look
//  (`beginLook`: the turn-and-watch with the curious face, the "look-up" stance is that same pose), a walk (`goTo`) to stand under a bubble, and a hop
//  (`.bounce` / `.skipHop`) whose top reaches it. No arm is moved (the arms stay stubby thumbs). The decisions live in Toys/BubbleWand.swift.
//

import Foundation
import simd

extension BlobBrain {
    /// Nothing owns him: he may start something of his own.
    var bubbleFree: Bool {
        anticsEnabled && autonomy && !held && !sleepLocked && reactFree && scriptIsNone && pending == nil && idleState.kind == nil
            && !race.active && social == nil && !commanded && idleMood != .grumpy && idleNight < 0.6
    }
    /// He is on his own errand (a walk) and nobody has taken him over since: keep going.
    var bubbleStillMine: Bool { attached && !held && !sleepLocked && social == nil && !commanded && !race.active }

    /// Turn and watch the bubble at floor point `p` (excited face), for `hold` seconds.
    @discardableResult
    func bubbleWatch(_ p: SIMD2<Float>, hold: Float, excited: Bool) -> Bool {
        beginLook(at: p, hold: hold, resume: nil, face: excited ? .excited : .curious, kind: .watch)
    }
    /// Walk to stand under the bubble.
    func bubbleGo(_ p: SIMD2<Float>) { requestNow(.goTo(fixed(p))) }
    /// A hop to reach it. False when he cannot hop now.
    @discardableResult
    func bubbleHop(_ sim: SoftBody) -> Bool {
        face(.excited, hold: 1.0)
        return idleStart(rand() < 0.5 ? .bounce : .skipHop, sim)
    }
}
