//
//  TouchPick.swift
//  Which Jelly is under the finger: the nearest rendered surface among the given bodies, else the nearest particle within a fingertip.
//

import Foundation
import simd

enum TouchPick {
    /// One body to test: his id, his render-vertex stream (6 floats per vertex) and his sim particles.
    struct Body { var id: Int; var dyn: UnsafePointer<Float>; var x: [Float] }

    /// The Jelly under screen point `p` (origin top-left) and the point on him, nearest the camera first. `bodies` are only the ones that can be touched
    /// (hidden Jellies are left out by the caller).
    static func pick(_ p: CGPoint, size: CGSize, viewProj: simd_float4x4, invViewProj: simd_float4x4, bodies: [Body],
                     index: [UInt32], bodyIndexCount: Int, maxPx: Float = 34) -> (id: Int, hit: SIMD3<Float>)? {
        let ndc = SIMD2<Float>(Float(p.x / size.width) * 2 - 1, 1 - Float(p.y / size.height) * 2)
        let ray = unproject(ndc: ndc, invViewProj: invViewProj)
        var best: (id: Int, hit: SIMD3<Float>, d: Float)?
        for b in bodies {
            if let h = pickRay(origin: ray.o, dir: ray.d, dyn: b.dyn, index: index, bodyIndexCount: bodyIndexCount) {
                let d = simd_distance(h, ray.o)
                if best == nil || d < best!.d { best = (b.id, h, d) }
            }
        }
        if let best { return (best.id, best.hit) }
        // no surface under the finger: the nearest particle within a fingertip (the closest on screen wins)
        let screen = SIMD2<Float>(Float(p.x), Float(p.y)), view = SIMD2<Float>(Float(size.width), Float(size.height))
        var near: (id: Int, hit: SIMD3<Float>, px: Float)?
        for b in bodies {
            guard let h = pickNear(screenPoint: screen, viewProj: viewProj, viewSize: view, x: b.x, maxPx: maxPx) else { continue }
            let c = viewProj * SIMD4<Float>(h.x, h.y, h.z, 1)
            let sp = SIMD2<Float>((c.x / c.w * 0.5 + 0.5) * view.x, (0.5 - c.y / c.w * 0.5) * view.y)
            let px = simd_distance(sp, screen)
            if near == nil || px < near!.px { near = (b.id, h, px) }
        }
        return near.map { ($0.id, $0.hit) }
    }
}
