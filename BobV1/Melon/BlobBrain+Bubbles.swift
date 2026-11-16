//
//  BlobBrain+Bubbles.swift
//  What a Jelbie does about the bubble wand's bubbles, built ONLY from moves that already exist (so the feet suites already cover them): a look
//  (`beginLook`: the turn-and-watch with the curious face, the "look-up" stance is that same pose), a walk (`goTo`) to stand under a bubble, and a hop
//  (`.bounce` / `.skipHop`) whose top reaches it. No arm is moved (the arms stay stubby thumbs). The decisions live in Toys/BubbleWand.swift.
//

import Foundation
import simd

/// Where a Jelbie stays while the bubble wand is out: the play rectangle on the floor (what the play camera shows above the HUD), his own spot in it, and the wand's floor point he looks up at.
struct BubbleLeash {
    var lo: SIMD2<Float>, hi: SIMD2<Float>
    var slot: SIMD2<Float>
    var look: SIMD2<Float>
    func contains(_ p: SIMD2<Float>, margin: Float = 0) -> Bool {
        p.x >= lo.x - margin && p.x <= hi.x + margin && p.y >= lo.y - margin && p.y <= hi.y + margin
    }
    func clamp(_ p: SIMD2<Float>, margin: Float = 0) -> SIMD2<Float> {
        SIMD2(min(max(p.x, lo.x - margin), hi.x + margin), min(max(p.y, lo.y - margin), hi.y + margin))
    }
}

extension BlobBrain {
    /// The next small move while the wand is out (instead of a wander): back to his spot when he strayed, else a hop on the spot, a look up at the wand, a step in place or a short shuffle.
    func bubbleIdle(_ sim: SoftBody, _ lz: BubbleLeash) {
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
        let here = SIMD2(px, pz)
        func walk(_ g: SIMD2<Float>) {
            let t = fixed(lz.clamp(g))
            if simd_distance(t, here) < 0.3 { restTimer = 0.3; return }
            script = .walk(target: t, then: .none); activity = .walking
        }
        if !lz.contains(here, margin: 0.4) || simd_distance(here, lz.slot) > 1.7 {
            walk(lz.slot + SIMD2(rand(-0.3, 0.3), rand(-0.3, 0.3)))
            return
        }
        let r = rand()
        if r < 0.32 {
            face(.excited, hold: 1.2)
            startHop(sim, distance: 0.0001)          // (a happy hop on the spot)
        } else if r < 0.72 {
            trackPoint = lz.look
            waitPose(sim)          // (look up at the wand; or step in place / a bounce and a blink)
        } else if r < 0.86 {
            script = .stepInPlace(t: 0, dur: rand(0.8, 1.6)); activity = .steppingInPlace
        } else {
            walk(lz.slot + SIMD2(rand(-0.6, 0.6), rand(-0.45, 0.45)))
        }
    }

    /// Nothing owns him: he may start something of his own.
    var bubbleFree: Bool {
        anticsEnabled && autonomy && !held && !decorLocked && reactFree && scriptIsNone && pending == nil && idleState.kind == nil
            && !race.active && social == nil && !commanded && idleMood != .grumpy && idleNight < 0.6
    }
    /// He is on his own errand (a walk) and nobody has taken him over since: keep going.
    var bubbleStillMine: Bool { attached && !held && !decorLocked && social == nil && !commanded && !race.active }

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

extension BlobBrain {
    /// The deliberate pop: the header hop (a hop on the spot with more air than the happy bounce, `tossApex`; the short stubby arms lift in it like the bounce's, the squash on take-off
    /// and the stretch at the top are the hop machinery's own). The crown is at the top `tossHeaderLead` s after this call; the wand pops the bubble when it is on the crown.
    /// False when he cannot hop right now.
    @discardableResult
    func bubbleHeaderHop(_ sim: SoftBody) -> Bool {
        guard idleState.kind == nil, scriptIsNone, !feet.active else { return false }
        face(.excited, hold: 1.2)
        return tossHeaderStart(sim)
    }
}
