//
//  BlobSocial+Toss.swift
//  The loveseat cuddle (the second decor batch; BlobSocial+Pass.swift is the pattern):
//    cuddle   two Jellies hop onto the two cushions of a loveseat, settle, and lean toward each other (the snuggle lean; BlobBrain+Decor `seatMotion`)
//  (The football toss that lived here was removed with the football, 2026-10-20: the soccer ball is kicked and passed instead, BlobBrain+Soccer.swift.)
//

import Foundation
import simd

extension BlobBrain {
    /// A loveseat with both cushions free.
    func freeLoveseat() -> DecorFoot? {
        let f = DecorField.shared
        return f.feet.first { $0.kind == .loveseat && f.available($0) && (f.seatOccupant[$0.uid]?.count ?? 0) == 0 }
    }

    func socialStartToss(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let d = simd_distance(position, o.position)
        guard !sleepLocked, d > 1.2, d < 6.5, kind == .cuddle else { return false }
        guard freeLoveseat() != nil, idleState.kind == nil, decorStart(.decorSit, sim, only: .loveseat) else { return false }
        let s = newSession(.cuddle, with: o, duration: 70)
        s.uid = idleState.decorUID
        idleState.hold = rand(10, 13)
        o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
        return true
    }

    // MARK: cuddle on the loveseat

    func driveCuddle(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if isA {
            if s.t > s.duration { s.finish(.aborted); return }
            if s.phaseT > 3, idleState.kind == nil, o.idleState.kind == nil, scriptIsNone, o.scriptIsNone, o.socialBook.hopStarted { s.finish(.done) }
            return
        }
        if !socialBook.hopStarted {
            guard s.phaseT > 0.5 else { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw(); return }
            if scriptIsNone, idleState.kind == nil {
                socialBook.hold = false; socialBook.faceYaw = nil
                socialBook.hopStarted = true
                if decorStart(.decorSit, sim, only: .loveseat) { idleState.hold = rand(10, 13); return }
                s.finish(.aborted)          // no second cushion
            }
        }
    }
}
