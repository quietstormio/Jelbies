//
//  DecorModels+Batch5.swift
//  How the fifth batch's Blender parts are posed (2026-11-04): the hacky sack rolls with its panels, the frisbee spins flat as it skids, the skateboard heads the
//  way it travels and turns its wheels (the toy car's pose), the hoop's backboard rattles and its net swings when booped.
//

import simd
import Foundation

extension DecorModels {
    private static func spin5(_ v: SIMD3<Float>, _ n: SIMD3<Float>, about p: SIMD3<Float>, _ q: simd_quatf) -> (SIMD3<Float>, SIMD3<Float>) { (p + q.act(v - p), q.act(n)) }

    static func addBatch5(_ kind: DecorKind, _ art: DecorMeshes.Art, o: SIMD3<Float>, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) -> Bool {
        let k = min(a.kick, 1.2), ph = Float(uid) * 0.7
        switch kind {
        case .footbag:
            guard let ball = art.part("ball") else { return false }
            let q = a.rot, pv = ball.pivot
            DecorMeshes.emit(ball, into: b, offset: o, pose: { v, n, _ in spin5(v, n, about: pv, q) })
        case .frisbee:
            guard let disc = art.part("disc") else { return false }
            let q = simd_quatf(angle: a.spinAngle, axis: SIMD3(0, 1, 0))
            DecorMeshes.emit(disc, into: b, offset: o, pose: { v, n, _ in (q.act(v), q.act(n)) })
        case .skateboard:
            let yaw = simd_quatf(angle: a.heading, axis: SIMD3(0, 1, 0))
            for part in art.parts {
                if part.name.hasPrefix("wheel") {
                    let pv = part.pivot, q = simd_quatf(angle: -a.wheel, axis: SIMD3(1, 0, 0))
                    DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, _ in let (p1, n1) = spin5(v, n, about: pv, q); return (yaw.act(p1), yaw.act(n1)) })
                } else {
                    DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, _ in (yaw.act(v), yaw.act(n)) })
                }
            }
        case .hoop:
            // a boop rattles the whole hoop a little about its base and swings the net further (w = depth below the rim)
            let q = simd_quatf(angle: 0.018 * k * sinf(time * 23 + ph), axis: SIMD3(1, 0, 0))
            let s1 = k * sinf(time * 13 + ph), s2 = k * sinf(time * 9 + 1.1 + ph)
            for part in art.parts {
                if part.name == "net" {
                    DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, w in (q.act(SIMD3(v.x + 0.07 * s2 * w, v.y, v.z + 0.10 * s1 * w)), q.act(n)) })
                } else {
                    DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, _ in (q.act(v), q.act(n)) })
                }
            }
        default:
            for part in art.parts { DecorMeshes.emit(part, into: b, offset: o) }          // (any other kind: all parts as exported)
        }
        return true
    }
}
