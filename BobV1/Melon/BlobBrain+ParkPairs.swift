//
//  BlobBrain+ParkPairs.swift
//  The park-only pick rules of round park-pairs-r1 (Park/ParkPairTuning.swift): the roll and the per-creature cooldown on the autonomous pick of the seesaw and of a new hopscotch line, and the
//  pair-only seesaw's recruiting and waiting (the first one at the seesaw stands at his spot until the partner is there). Nothing here runs for a brain whose `outingPlay` is off, except the seesaw's
//  waiting rule (`ParkPairTuning.pairSeesaw`), which is about the piece, not the room.
//

import Foundation
import simd

extension BlobBrain {
    /// May an autonomous start on `f` go ahead? (`decorStart`'s `wanted` filter.) A use the player asked for, a partner's start and the old switch always pass; so does joining something that is already
    /// going on (a seat is taken, a hopscotch line is running: those have their own chances). Else the cooldown, then the roll.
    func parkToyGate(_ f: DecorFoot) -> Bool {
        guard outingPlay, ParkPairTuning.toyRateNew, !commanded, !seesawPartnerStart else { return true }
        let chance: Float
        switch f.kind {
        case .seesaw:
            if !(DecorField.shared.seatOccupant[f.uid]?.isEmpty ?? true) { return true }
            chance = ParkPairTuning.seesawPickChance
        case .hopscotch:
            if HopscotchLine.shared.active { return true }
            chance = ParkPairTuning.hopscotchPickChance
        default: return true
        }
        if let until = toy.parkCool[f.kind], until > DecorField.shared.toys.clock { parkGateRejected = f.uid; ParkPairTuning.stats.coolNo += 1; return false }
        if rand() < chance { return true }
        parkGateRejected = f.uid
        ParkPairTuning.stats.rollNo += 1
        return false
    }

    /// A use of the seesaw / hopscotch is over (or given up): this creature does not pick it again by himself for a while.
    func parkToyUsed(_ kind: DecorKind) {
        let r: ClosedRange<Float>
        switch kind {
        case .seesaw: r = ParkPairTuning.seesawCooldown
        case .hopscotch: r = ParkPairTuning.hopscotchCooldown
        default: return
        }
        toy.parkCool[kind] = DecorField.shared.toys.clock + rand(r.lowerBound, r.upperBound)
    }

    // MARK: the pair-only seesaw

    /// `decorStart(.decorSit)` for the social sit-together: any seat piece except the seesaw (which has its own pairing).
    func decorStartSeat(_ sim: SoftBody) -> Bool {
        decorSkipSeesaw = true; defer { decorSkipSeesaw = false }
        return decorStart(.decorSit, sim)
    }

    /// The creature on the other seat of this seesaw (a brain on the piece, roster creature or visitor alike).
    func seesawPartner(_ f: DecorFoot) -> BlobBrain? {
        socialOthers().first { $0 !== self && $0.idleState.kind == .decorSit && $0.idleState.decorUID == f.uid && $0.idleState.seat != idleState.seat }
    }

    /// Finds a free creature near the seesaw who agrees and starts him on the other seat (the caller has already taken his own seat in the field). `nil` = nobody. A commanded asker does not skip a
    /// partner who has ridden lately; an autonomous one does.
    @discardableResult
    func seesawRecruit(_ f: DecorFoot, _ sim: SoftBody) -> BlobBrain? {
        let field = DecorField.shared, clock = field.toys.clock, at = field.position(f)
        let cooled = outingPlay && ParkPairTuning.toyRateNew && !commanded
        let cands = toyPeers.filter { o in
            o.toyFree && o.socialFree && o.toy.waitUID < 0 && o.toy.noticeUID < 0 && o.outingPlay == outingPlay && simd_distance(o.position, at) < ParkPairTuning.partnerRadius
                && !(cooled && (o.toy.parkCool[.seesaw] ?? 0) > clock)
        }.sorted { simd_distance($0.position, at) < simd_distance($1.position, at) }
        for o in cands {
            guard rand() < ParkPairTuning.partnerAgree else { continue }
            o.seesawPartnerStart = true
            let ok = o.decorStart(.decorSit, sim, only: .seesaw, uid: f.uid)          // (decorStart never reads the body: the asker's does for both)
            o.seesawPartnerStart = false
            if ok {
                o.toy.lastDirect = o.variety.now
                o.idleState.cooldown = max(o.idleState.cooldown, 3)
                ParkPairTuning.stats.recruited += 1
                return o
            }
        }
        return nil
    }

    /// Stage 0 of the seesaw, just before the hop up: may he get on? True when the creature on the other seat is at his spot (or within `readyDist` of it) or already on the piece. Otherwise he stands
    /// where he is (not seated, nothing moves) and waits: up to `waitCap` s from his arrival for a partner who is on his way; `partnerGoneGrace` s when nobody is on the other seat any more (a commanded
    /// asker looks for a free partner every `recruitEvery` s for the whole `waitCap` instead). `giveUp` ends his use calmly.
    func seesawPartnerGate(_ sim: SoftBody, _ f: DecorFoot, dt: Float, giveUp: (String) -> Void) -> Bool {
        guard ParkPairTuning.pairSeesaw else { return true }
        let R = SeesawRide.shared, uid = f.uid, seat = idleState.seat
        if let o = seesawPartner(f) {
            let st = o.idleState
            let leaving = !st.decorGo && (st.bagStage == 3 || (st.bagStage == 2 && st.phase == 3))
            if !leaving {
                let ready = st.decorGo ? simd_distance(o.position, st.target) < ParkPairTuning.readyDist : true
                if ready { return true }
                _ = R.wait(uid, seat, "partner", dt: dt, info: String(format: "partner %.2f m from his spot", simd_distance(o.position, st.target)))
                if idleState.phaseT > ParkPairTuning.waitCap { giveUp("noPartner") }
                return false
            }
        }
        if seesawRecruiting {
            if idleState.phaseT >= seesawRecruitAt { seesawRecruitAt = idleState.phaseT + ParkPairTuning.recruitEvery; if seesawRecruit(f, sim) != nil { idleState.phaseT = 0.2; seesawRecruitAt = 0.2 + ParkPairTuning.recruitEvery } }          // (a partner found: his own wait cap starts over)
            _ = R.wait(uid, seat, "recruit", dt: dt)
            if idleState.phaseT > ParkPairTuning.waitCap { giveUp("noPartner") }
            return false
        }
        if R.wait(uid, seat, "partnerGone", dt: dt) > ParkPairTuning.partnerGoneGrace { giveUp("partnerGone") }
        return false
    }
}
