//
//  BlobSocial+TailClear.swift
//  Pip's floor tail lies straight back with the spikes up. When a social puts a body BEHIND him (backToBack: the backs meet; sneak: the sneaker comes up to his back) the tail
//  is what touches the partner, so the bodies stay a tail-length apart and the spikes poke into him. The tail wraps round to one side (the existing hug curl, TailDrive.bendYaw)
//  while the body is behind him, eased in before the backs close and out after: the way a cat wraps its tail. Wings are not touched.
//
import Foundation
import simd

extension BlobBrain {
    /// Degrees of sustained tail curl (signed, + = toward the body's +x side) the running social wants right now; 0 = none.
    func socialTailCurl() -> Float {
        guard let s = social, s.end == nil, hasTailToPlay else { tailPlay.socialSide = 0; return 0 }
        var on = false
        let partner: BlobBrain? = s.a === self ? s.b : s.a
        switch s.kind {
        case .backToBack:
            on = s.phase >= 2 && !(s.phase >= 3 && s.phaseT > s.duration - 0.5)
        case .sneak:
            on = s.b === self && s.phase <= 2          // (the one being sneaked up on: his back is where the other comes)
        default: break
        }
        guard on, let o = partner else { tailPlay.socialSide = 0; return 0 }
        if tailPlay.socialSide == 0 {          // the side away from the partner's body (latched: it does not flip while he moves round)
            let dir = o.position - position
            let right = SIMD2(cosf(yaw), -sinf(yaw))
            tailPlay.socialSide = simd_dot(dir, right) > 0.02 ? -1 : 1
        }
        return tailPlay.socialSide * Self.socialCurlDeg
    }
    static let socialCurlDeg: Float = 120
}
