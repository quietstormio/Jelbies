//
//  BlobBrain+ParkPlay.swift
//  The park-only pick rule of round park-play-r1 (Park/ParkPlayTuning.swift): a roll and a per-creature cooldown on the autonomous pick of the slide and of a new hopscotch line. Nothing here runs for a brain whose
//  `outingPlay` is off (the room), and a use the player asked for (`commanded`) always goes ahead.
//

import Foundation
import simd

extension BlobBrain {
    /// May an autonomous start on `f` go ahead? (`decorStart`'s `wanted` filter.) The player's own request, the home room and the old switch always pass. Else the cooldown (a join of a running line only has that), then the roll; a "no" holds the toy off for `rejectHold` seconds.
    func parkToyGate(_ f: DecorFoot) -> Bool {
        guard outingPlay, ParkPlayTuning.toyRateNew, !commanded else { return true }
        let chance: Float
        switch f.kind {
        case .slide: chance = ParkPlayTuning.slidePickChance
        case .hopscotch:
            chance = HopscotchLine.shared.active ? 1 : ParkPlayTuning.hopscotchPickChance          // (a line that is running: joining it is not rolled, only the cooldown below applies; measured: with joins free the court was never empty)
        default: return true
        }
        let clock = DecorField.shared.toys.clock
        if let until = toy.parkCool[f.kind], until > clock { parkGateRejected = f.uid; ParkPlayTuning.stats.coolNo += 1; return false }
        if chance >= 1 || rand() < chance { return true }
        parkGateRejected = f.uid
        ParkPlayTuning.stats.rollNo += 1
        toy.parkCool[f.kind] = clock + rand(ParkPlayTuning.rejectHold.lowerBound, ParkPlayTuning.rejectHold.upperBound)
        return false
    }

    /// A use of the slide / hopscotch is over (or given up): he does not pick it again by himself for a while.
    func parkToyUsed(_ kind: DecorKind) {
        let r: ClosedRange<Float>
        switch kind {
        case .slide: r = ParkPlayTuning.slideCooldown
        case .hopscotch: r = ParkPlayTuning.hopscotchCooldown
        default: return
        }
        toy.parkCool[kind] = DecorField.shared.toys.clock + rand(r.lowerBound, r.upperBound)
    }
}
