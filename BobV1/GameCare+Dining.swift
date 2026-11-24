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
    /// `callRunning` (set by a Come call, cleared when it arrives) can never hold a meal for more than this many seconds of the meal's own clock; only with the soft wake on.
    static func softMealWakeWatchdog(age: Float) -> Bool { BlobBrain.softMealWakeOn && age > 20 }
    /// Serves the last picked drink to Jelly `jelly` (same as `water(jelly:)`).
    func drink(jelly: Int? = nil) { drink(selectedDrinkID, jelly: jelly) }
    /// The Jelly the tray / meal is for (0 when none).
    var diningJelly: Int { mealJelly }
    /// Where the refusal label anchors: over the head of the Jelly that is refusing.
    var noticeHeadWorld: SIMD3<Float> { mealJelly == 0 || noticeAtBob ? headWorld : mealHead }

    /// One fixed step of the meal flow for Jelly `id` (a no-op unless the tray is for him): the walk to his place, the tray pop-in, the pieces
    /// paid as eaten, the refusal label, the re-serve loop. Jelly 0 keeps the Call / queued-request gating it always had.
    /// The ball game's hold on a Jelmiko (`reserved` + the PlayToss wait focus) applies only when no meal is wanted or running and he is not the meal's Jelly.
    static func playHolds(reserving: Bool, mealActive: Bool, holds: Bool) -> Bool { !reserving && !mealActive && holds }

    func tickDining(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        if id == 0, notice != nil { noticeAge += dt; if noticeAge > 1.9 { notice = nil } }
        traceSingle(id: id, brain: brain, sim: sim, dt: dt)
        if !groupActive {             // single serving: the Jelly the tray is for waits where he stands (reserved), everybody else is free (a group's waiter stays reserved between its sittings)
            let reserving = id == mealJelly && (wanted != nil || meal != nil)
            let playHeld = Self.playHolds(reserving: reserving, mealActive: wanted != nil || meal != nil, holds: play.holds(id))          // (play-ball-r2: the ball game holds its Jelmiko on the line: the wait pose, no roam leg / stroll; PlayToss sets their waitFocus. NEVER while a meal is wanted or running: then these lines compute exactly what the phone build computes)
            brain.reserved = reserving || playHeld
            if !playHeld { brain.waitFocus = reserving ? (dining.isPresent ? dining.places.first?.stand : (wantedOrigin ?? DiningSpot.preferred)) : nil }
            brain.mealFaceYaw = reserving && DiningGroup.calmWait ? DiningLayout.make(n: 1).places[0].yaw : nil          // (C3: the calm wait faces his place)
        }
        if id != mealJelly, wanted != nil || meal != nil { stepAside(id: id, brain: brain, sim: sim, dt: dt); return }
        guard id == mealJelly, wanted != nil || meal != nil else { return }
        let act: BlobActivity = brain.mealWaking ? .turning : brain.activity          // (a meal-waking sleeper is busy, not idle: the walk retries below never count his wake)
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
        orderAge += dt
        if own, callRunning, Self.softMealWakeWatchdog(age: orderAge) { MealTrace.log("callRunning watchdog cleared (single)"); callRunning = false }
        if own, orderAge > Self.staleCallAfter { _ = clearStaleCall(brain: brain, why: "single order") }          // (night-meal-r1)
        let free = !own || (!callRunning && queued.isEmpty)
        // a meal-woken sleeper whose wake has run past its longest legal length (a stuck stage) is called the hard way, once (the group's `wakeCap` fallback, for the single flow)
        if brain.mealWaking, brain.sleep.mealWakeT > DiningGroup.wakeCap {
            MealTrace.log("wake FALLBACK single jelly=\(id) after \(brain.sleep.mealWakeT) s")
            brain.sleep.mealWake = false; brain.sleep.mealCall = nil
            if let c = meal { brain.requestHard(mealRequest(c)) }          // (his tier's pieces, as `startMeal` asked)
            else if let c = wanted {
                var stand = (wantedOrigin ?? DiningSpot.preferred) + DiningLayout.make(n: 1).places[0].rel
                stand.y += c.eatStyle == .sip ? Self.sipCloser : Self.eatCloser
                standRequested = true; standIdle = 0
                brain.requestHard(.goTo(SIMD2(stand.x, stand.y - Self.approachBack)))
            }
        }

        // pop the tray in once he is at (or behind) his place; in front of it he walks there first
        if let c = wanted, free { serveWanted(c, brain: brain, here: Self.floorPos(brain, sim), act: act, dt: dt) }

        if let c = meal {
            payPieces()
            if brain.isRefusing, !noticeDone {
                noticeDone = true; noticeAtBob = false
                notice = MealAppetite.refusalText(c.kind == .food ? .hunger : .thirst); noticeSerial += 1; noticeAge = 0
            }
            mealAge += dt
            if mealAge > Self.mealTimeout { let ate = mealPaid > 0; endMeal(); retries = 0; if !ate, mealPieces > 0 { tapRefused("Couldn't get the food to the table — try again") } }
            else if free, mealApproach {
                // C5d: the tray is out; he walks to his approach point and squares up (the calm wait turns him), then the dine request: a straight step-in.
                // Bounded: 2 walk re-sends, the facing fallback, else the dine request as before.
                var stand = dining.places.first?.stand ?? DiningSpot.preferred
                stand.y += c.eatStyle == .sip ? Self.sipCloser : Self.eatCloser
                let approach = SIMD2(stand.x, stand.y - Self.approachBack), here = Self.floorPos(brain, sim)
                let idleNow = act == .idle || act == .lookingAround || act == .steppingInPlace
                let there = simd_distance(here, approach) < 0.3
                if there, idleNow { singleFacingT += dt }
                let facingNow = abs(Self.wrapAngle(brain.yaw - (dining.places.first?.yaw ?? 0))) < DiningGroup.calmFacing
                if there, idleNow, facingNow || singleFacingT >= DiningGroup.calmFacingWait {
                    mealApproach = false; startMeal(c, brain: brain); mealRequested = true; MealTrace.log("single sent to eat")
                } else if !there, idleNow {
                    standIdle += dt
                    if standIdle > 0.8 {
                        standIdle = 0
                        if standRetries < 2 { standRetries += 1; brain.callToMeal(.goTo(approach)) }
                        else { mealApproach = false; startMeal(c, brain: brain); mealRequested = true; MealTrace.log("single sent to eat (fallback)") }
                    }
                } else { standIdle = 0 }
            }
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

    /// Simulator-only meal trace for the single flow (one line per change): the order, the tray out, the first piece, the end.
    private func traceSingle(id: Int, brain: BlobBrain, sim: SoftBody?, dt: Float) {
        #if targetEnvironment(simulator)
        guard !groupActive, id == mealJelly else { return }
        if wanted != nil, !MealTrace.singleActive { MealTrace.singleActive = true; MealTrace.singleTray = false; MealTrace.singleBite = false; MealTrace.singleGone = false; MealTrace.singleOver = false; MealTrace.begin("single order jelly=\(id) kind=\(wanted?.kind == .food ? "food" : "drink")") }
        if meal != nil, dining.isPresent, !MealTrace.singleTray {
            MealTrace.singleTray = true; MealTrace.log("single tray out")
            let box = dining.drawnBox(scale: 1)
            MealTrace.log("tray box c=(\(box.centre.x),\(box.centre.y)) half=(\(box.half.x),\(box.half.y)) stands=" + dining.places.map { "(\($0.stand.x),\($0.stand.y))" }.joined(separator: ";"))
        }
        if let c = meal, dining.isPresent, !dining.bitesLeft.isEmpty {
            let got = c.kind == .drink ? Int((dining.drunk[0] * Float(DiningTiming.gulpsPerDrink) + 0.001).rounded(.down)) : DiningTiming.bitesPerServing - dining.bitesLeft[0]
            if got > 0, !MealTrace.singleBite { MealTrace.singleBite = true; MealTrace.log("single first piece eaten (\(got))") }
        }
        if wanted == nil, meal == nil, MealTrace.singleActive, !MealTrace.singleOver { MealTrace.singleOver = true; MealTrace.log("single meal over paid=\(mealPaid)") }
        if MealTrace.singleActive, dining.phase == .absent, meal == nil, wanted == nil, !MealTrace.singleGone { MealTrace.singleGone = true; MealTrace.singleActive = false; MealTrace.log("single tray gone") }
        if MealTrace.singleActive { MealTrace.singleAge += dt } else { MealTrace.singleAge = 0 }
        if MealTrace.poseOn, MealTrace.singleActive {
            // (every fixed step) the single eater's brain root, floor point, yaw and activity: the meal smoothness survey
            let f = Self.floorPos(brain, sim)
            let c = sim.map { (s: SoftBody) -> SIMD2<Float> in let v = s.centroid(); return SIMD2(v.x, v.z) } ?? f          // (the body centroid: what the eye follows)
            var ms = ",nan"          // (his mouth to his straw tip while he sips a gulp: the drink "mouth at the rim" check)
            if let s = sim, brain.dineIsSipping, brain.dinePhaseName == "chew", let tip = dining.strawTip(place: 0) { ms = String(format: ",%.4f", simd_distance(brain.mouthWorld(sim: s), tip)) }
            MealTrace.log(String(format: "pose a=%.4f", MealTrace.singleAge) + " \(id)@p0=" + String(format: "%.4f,%.4f,%.4f,%.4f,%.4f", brain.position.x, brain.position.y, f.x, f.y, brain.yaw) + ",\(brain.activity),-" + String(format: ",%.4f,%.4f", c.x, c.y) + ms + (dining.isPresent ? " tray=1" : " tray=0"))
        }
        #endif
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
        let layout1 = DiningLayout.make(n: 1), trayOrigin = dining.isPresent ? dining.origin : (wantedOrigin ?? DiningSpot.preferred)
        func trayD(_ p: SIMD2<Float>) -> Float { DiningSpot.distance(from: p, origin: trayOrigin, layout: layout1) }          // (and off the tray's own rectangle, where it lands)
        guard simd_distance(here, stand) < reach || simd_distance(here, approach) < reach || trayD(here) < DiningGroup.trayClearance else { return }
        // the room is narrow: try a few spots round the place and take the one the floor rules leave farthest from it
        let spots: [SIMD2<Float>] = [SIMD2(2.1, 0.3), SIMD2(-2.1, 0.3), SIMD2(1.5, -1.0), SIMD2(-1.5, -1.0), SIMD2(0, -2.0)].map { stand + $0 }
        var best: (d: Float, p: SIMD2<Float>)?
        for c in spots {
            let q = brain.resolve(SIMD3(c.x, 0, c.y), 0.6)
            let p = SIMD2(q.x, q.z)
            let d = min(simd_distance(p, stand), simd_distance(p, approach), trayD(p) + 0.5) - 0.2 * simd_distance(p, here)
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
