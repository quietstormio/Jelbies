//
//  BlobBrain+SlideFoot.swift
//  The park slide's foot stays free (2026-11-11): the one who has just ridden walks off to the lawn left of the path, and a free Jelbie who stands on the foot
//  while someone else has the slide steps off too. Before, the ex-rider got up and stayed on the landing: the next rider waited on the platform for the 8 s cap
//  (`runSlide` stage 4) and then rode into him.
//

import simd
import Foundation

extension BlobBrain {
    /// Where the chute lets him off: the floor spot at the end of the ride.
    func slideLanding(_ f: DecorFoot) -> SIMD2<Float> { f.centre + f.turned(SIMD2(0, Self.slideAt(Self.slideLength).z)) }

    /// The lawn spots an ex-rider (or a stander asked off the foot) walks to, in the slide's own frame (x to the side, z along the chute). With the park's layout
    /// (slide (2.9, 1.0), court (-2.1, 1.9)) they are (-0.35, 3.5), (-0.5, 2.1), (-0.5, 0.65): one column left of the path, each at least `peerGap + 0.3` from
    /// the landing, 1.15 from every hopscotch square and one gap from the next. ParkSlideCrowdTests pins all three.
    static let slideOutSpots: [SIMD2<Float>] = [SIMD2(-3.25, 2.5), SIMD2(-3.4, 1.1), SIMD2(-3.4, -0.35)]

    /// Park slide only: the first free one of `slideOutSpots`, starting at this brain's own index (two who leave together do not pick the same spot).
    /// nil = none is free (the caller keeps the old behaviour).
    func slideWalkOut(_ f: DecorFoot) -> SIMD2<Float>? {
        guard f.uid == ParkToys.slideUID else { return nil }
        let landing = slideLanding(f)
        let n = Self.slideOutSpots.count
        for k in 0..<n {
            let q = f.centre + f.turned(Self.slideOutSpots[(steerID + k) % n])
            guard let out = decorFreeSpot(near: q), simd_distance(out, q) < 0.3, simd_distance(out, landing) >= peerGap + 0.3 else { continue }
            return out
        }
        return nil
    }

    /// Park slide only, called with no behaviour running (`decorExitCheck`): a free Jelbie who stands on the slide's foot while someone else has the slide walks off
    /// to the lawn, so the rider has a clear landing. No spot free = he stays (no request, so nothing repeats).
    func slideFootCheck() {
        guard !held, !decorLocked, pending == nil, social == nil, case .none = script else { return }
        guard let f = DecorField.shared.foot(ParkToys.slideUID), let rider = DecorField.shared.occupant[f.uid], rider != steerID else { return }
        guard simd_distance(position, slideLanding(f)) < peerGap + 0.1, let out = slideWalkOut(f) else { return }
        requestNow(.goTo(out))
    }
}
