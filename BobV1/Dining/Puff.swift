//
//  Puff.swift
//  The ONE puff effect used for every pop-in and poof-out: a handful of soft low-poly spheres in the room's lightest colour that
//  swell, drift apart and fade. Rendered in 3D through the room pipeline's translucent pass (vertex alpha). No sprites.
//

import simd
import Foundation

nonisolated struct PuffInstance {
    var centre: SIMD3<Float>
    var radius: Float
    var age: Float = 0
    var seed: UInt32
}

nonisolated final class PuffEffect {
    static let life: Float = 0.55
    static let spheresPerPuff = 6
    private(set) var instances: [PuffInstance] = []
    private var counter: UInt32 = 1
    var isActive: Bool { !instances.isEmpty }

    func spawn(at centre: SIMD3<Float>, radius: Float) {
        counter = counter &* 1664525 &+ 1013904223
        instances.append(PuffInstance(centre: centre, radius: radius, seed: counter))
    }

    func update(dt: Float) {
        for i in instances.indices { instances[i].age += dt }
        instances.removeAll { $0.age >= Self.life }
    }

    func reset() { instances.removeAll() }

    /// Progress 0...1 of an instance.
    static func progress(_ p: PuffInstance) -> Float { min(max(p.age / life, 0), 1) }

    /// Fade: strong at first (so the pop hides in it), gone at the end.
    static func alpha(_ u: Float) -> Float { 0.95 * powf(max(1 - u, 0), 1.1) }

    /// Appends all spheres of all instances (world space) with their alpha.
    func append(to b: RoomMeshBuilder, sphere: RoomMesh) {
        for p in instances {
            let u = Self.progress(p)
            let ease = 1 - (1 - u) * (1 - u)
            let a = Self.alpha(u)
            var s = p.seed
            func rnd() -> Float { s = s &* 1664525 &+ 1013904223; return Float(s >> 8) / Float(1 << 24) }
            for k in 0..<Self.spheresPerPuff {
                // spread around the centre (golden-angle azimuth, some up, some out)
                let az = Float(k) * 2.39996 + rnd() * 0.6
                let el = (rnd() - 0.25) * 0.9
                let dir = SIMD3<Float>(cosf(az) * cosf(el), sinf(el) * 0.8, sinf(az) * cosf(el))
                let dist = p.radius * (0.25 + 0.75 * ease) * (0.7 + 0.5 * rnd())
                let grow = DiningCurve.pop(min(u / 0.45, 1))                       // springy swell: overshoots, settles, then drifts / fades
                let r = p.radius * (0.22 + 0.2 * rnd()) * (0.3 + 0.95 * grow)
                let t = DiningModels.translation(p.centre + dir * dist, scale: r)
                DiningModels.append(sphere, to: b, transform: t, alpha: a)
            }
        }
    }
}
