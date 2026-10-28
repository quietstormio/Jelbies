//
//  BlobBrain+Unstick.swift
//  The brain's side of the no-getting-stuck guarantee (StuckWatchdog): a walker that is trying to get somewhere, and a gentle shift of the
//  floor spot that moves root, planted feet and the running step together, so the walk and the pose carry on from the new spot (no teleport).
//

import Foundation
import simd

extension BlobBrain {
    /// He is on a walk (his own, a request, a meal approach, a social walk-up): the kind of motion a watchdog can call "no progress".
    var tryingToMove: Bool {
        guard enabled, attached, !isNapping, !race.active else { return false }
        if case .walk = script { return activity == .walking || activity == .coming }
        return false
    }

    /// Slides the floor spot by `d` (at most `maxStep` long), through the floor rules (walls, decor, the tray), so a nudge never pushes into something.
    /// Returns the distance really moved.
    @discardableResult
    func unstickNudge(_ d: SIMD2<Float>, maxStep: Float) -> Float {
        guard attached, !isNapping else { return 0 }
        var v = d
        let L = simd_length(v)
        guard L > 1e-5 else { return 0 }
        if L > maxStep { v *= maxStep / L }
        let want = SIMD2(px, pz) + v
        let r = resolve(SIMD3(want.x, 0, want.y), footprint)
        let got = SIMD2(r.x, r.z) - SIMD2(px, pz)
        guard simd_length(got) > 1e-5 else { return 0 }
        px += got.x; pz += got.y
        stepRoot0 += got
        if feet.pos.count > 1 { feet.pos[0] += got; feet.pos[1] += got }
        stallRoot = SIMD2(px, pz)          // (the nudge itself is not the walk's progress)
        return simd_length(got)
    }

    /// Drops the walk he is on and stands where he is; his job's completion fires, so the owner (a meal, a social, a call) re-plans or gives up.
    func unstickGiveUp() {
        route = []; steerWait = 0; steerGiveUp = false; stuckT = 0
        requestNow(.goTo(position))
    }
}
