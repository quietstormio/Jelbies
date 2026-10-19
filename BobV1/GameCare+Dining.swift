//
//  GameCare+Dining.swift
//  Meals for whichever Jelly the care action targets (`feed(jelly:)`, `drink(jelly:)`, `water(jelly:)`).
//  One meal at a time: while a tray is wanted or out, another Feed / Drink is ignored (the same rule as before). The meal remembers its Jelly
//  (`mealJelly`); that Jelly's brain walks to the tray, his tier sets the pieces, his needs gain, and the refusal label sits over his head.
//  Jelly 0 is driven from `tick`, the others from `tickOthers`; both call `tickDining`. The other Jellies keep wandering and steer round the eater
//  (a standing Jelly is an obstacle to every peer: `keepApart`), and the tray is an obstacle for all of them (`wireWorld`).
//

import Foundation
import simd

extension GameCare {
    /// Serves the last picked drink to Jelly `jelly` (same as `water(jelly:)`).
    func drink(jelly: Int? = nil) { drink(selectedDrinkID, jelly: jelly) }
    /// The Jelly the tray / meal is for (0 when none).
    var diningJelly: Int { mealJelly }
    /// Where the refusal label anchors: over the head of the Jelly that is refusing.
    var noticeHeadWorld: SIMD3<Float> { mealJelly == 0 ? headWorld : mealHead }

    /// One fixed step of the meal flow for Jelly `id` (a no-op unless the tray is for him): the walk to his place, the tray pop-in, the pieces
    /// paid as eaten, the refusal label, the re-serve loop. Jelly 0 keeps the Call / queued-request gating it always had.
    func tickDining(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        if id == 0, notice != nil { noticeAge += dt; if noticeAge > 1.9 { notice = nil } }
        if id != mealJelly, wanted != nil || meal != nil { stepAside(id: id, brain: brain, sim: sim, dt: dt); return }
        guard id == mealJelly, wanted != nil || meal != nil else { return }
        let act = brain.activity
        let own = id == 0
        if !own {
            if eaterBrain !== brain {
                eaterBrain = brain; eaterFinished.removeAll()
                brain.onFinished = { [weak self] r in self?.eaterFinished.append(r) }
            }
            if let sim { let c = sim.centroid(); mealHead = SIMD3(c.x, c.y + BlobShape.H * 0.5, c.z) }
            if !brain.commanded { brain.idleBlocked = true }                // no idle trick mid-order, like Bob
            for r in eaterFinished {
                switch r {
                case .dine, .sip: if meal != nil { payPieces(); endMeal(); retries = 0 }
                default: break
                }
            }
            eaterFinished.removeAll()
        }
        let free = !own || (!callRunning && queued.isEmpty)

        // pop the tray in once he is at (or behind) his place; in front of it he walks there first
        if let c = wanted, free { serveWanted(c, brain: brain, here: Self.floorPos(brain, sim), act: act, dt: dt) }

        if let c = meal {
            payPieces()
            if brain.isRefusing, !noticeDone {
                noticeDone = true
                notice = MealAppetite.refusalText(c.kind == .food ? .hunger : .thirst); noticeSerial += 1; noticeAge = 0
            }
            mealAge += dt
            if mealAge > Self.mealTimeout { endMeal(); retries = 0 }
            else if free, mealRequested {
                // the request was cancelled (for example he was grabbed): ask again a couple of times, then give up
                if act == .idle || act == .lookingAround || act == .steppingInPlace {
                    idleT += dt
                    if idleT > 0.8 {
                        idleT = 0
                        if retries < Self.maxReserves, let st = dining.places.first?.stand, Self.floorPos(brain, sim).y > st.y + Self.popTolerance + 0.05 {
                            // dropped in front of his place (the tray is between him and it): the tray poofs, he walks back, it pops in again
                            retries += 1; endMeal(); wanted = c; resetStandWalk()
                        }
                        else if retries < Self.maxReserves { retries += 1; startMeal(c, brain: brain) }
                        else { endMeal(); retries = 0 }          // out of re-serves: the tray poofs, he is left at rest
                    }
                } else { idleT = 0 }
            }
        }
    }

    /// A Jelly that is NOT eating but stands at the eater's place (or on the way to it) walks off to the side, so the eater is never boxed in
    /// by the peer rule (every Jelly keeps `jellyGap` from a standing one). Walkers steer by themselves; Jellies in a command are left alone.
    func stepAside(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        clearCool[id, default: 0] -= dt
        guard clearCool[id, default: 0] <= 0, !brain.commanded, !(id == 0 && (focus.isActive || bath.active)) else { return }
        let act = brain.activity
        guard act == .idle || act == .lookingAround || act == .steppingInPlace else { return }
        let stand = dining.isPresent ? (dining.places.first?.stand ?? DiningSpot.preferred) : (wantedOrigin ?? DiningSpot.preferred) + DiningLayout.make(n: 1).places[0].rel
        let approach = SIMD2(stand.x, stand.y - Self.approachBack)
        let here = Self.floorPos(brain, sim)
        let reach = MelonController.jellyGap + 0.1
        guard simd_distance(here, stand) < reach || simd_distance(here, approach) < reach else { return }
        // the room is narrow: try a few spots round the place and take the one the floor rules leave farthest from it
        let spots: [SIMD2<Float>] = [SIMD2(2.1, 0.3), SIMD2(-2.1, 0.3), SIMD2(1.5, -1.0), SIMD2(-1.5, -1.0), SIMD2(0, -2.0)].map { stand + $0 }
        var best: (d: Float, p: SIMD2<Float>)?
        for c in spots {
            let q = brain.resolve(SIMD3(c.x, 0, c.y), 0.6)
            let p = SIMD2(q.x, q.z)
            let d = min(simd_distance(p, stand), simd_distance(p, approach)) - 0.2 * simd_distance(p, here)
            if best == nil || d > best!.d { best = (d, p) }
        }
        if let best { brain.requestNow(.goTo(best.p)) }
        clearCool[id] = 2
    }

    /// A meal for another Jelly ends early (Come here, timeout): his dine job stops where he stands, so he does not keep eating at a tray that is gone.
    func standDownEater() {
        guard mealJelly != 0, let b = eaterBrain else { return }
        if b.activity == .eating || b.activity == .drinking { b.requestNow(.goTo(b.position)) }
    }

    /// After the frame's last sim step: what the eater holds goes back onto his nub (Jelly 0 or another).
    func refreshHeld(actors: [JellyActor], renderer: MelonRenderer?) {
        if group.isActive {
            for a in actors { if let b = a.brain, b.enabled { b.refreshHeld(sim: a.sim) } }
            if let room = renderer?.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
            return
        }
        guard actors.indices.contains(mealJelly), let b = actors[mealJelly].brain, b.enabled else { return }
        refreshHeld(brain: b, sim: actors[mealJelly].sim, renderer: renderer)
    }
}
