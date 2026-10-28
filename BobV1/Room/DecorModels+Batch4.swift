//
//  DecorModels+Batch4.swift
//  How the fourth batch's Blender parts are posed (2026-10-27). Same machinery as batch 3: `DecorAnim` is driven by the Jellies' existing kick / boop / peek
//  hooks, animation that belongs to a boop is read from `kickT` while `kick` is alive, so every piece rests in its exported pose when nobody touches it.
//
//    beach ball    rolls (its panels turn with it, `a.rot`)      play tunnel   a ripple runs along it (peek / boop)
//    ring stacker  the rings wobble on the post, top first       toy rocket    rocks on its runners like the horse, the flame flickers
//    plush dino    squash-and-stretch, head wobble, tail swish   kick scooter  handlebars twist, wheels turn a little
//

import simd
import Foundation

extension DecorModels {
    private static func sm4(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }
    private static func spin4(_ v: SIMD3<Float>, _ n: SIMD3<Float>, about p: SIMD3<Float>, _ q: simd_quatf) -> (SIMD3<Float>, SIMD3<Float>) { (p + q.act(v - p), q.act(n)) }

    /// The rocket's axis tilt above horizontal (toy_rocket.json: RK_T) and its body centre; the runners are the horse's arc.
    static let rocketTilt: Float = 0.5
    static let rocketTail = SIMD3<Float>(0, 0.84, 0) + 0.62 * SIMD3<Float>(-cosf(0.5), -sinf(0.5), 0)
    /// The scooter's steering axis (column from its fork joint up to the top of the column) and the top.
    static let scooterTop = SIMD3<Float>(0.30, 1.02, 0)
    static let scooterAxis = simd_normalize(SIMD3<Float>(-0.13, 0.82, 0))

    static func addBatch4(_ kind: DecorKind, _ art: DecorMeshes.Art, o: SIMD3<Float>, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) -> Bool {
        typealias Pose = (SIMD3<Float>, SIMD3<Float>, Float) -> (SIMD3<Float>, SIMD3<Float>)
        func emit(_ part: DecorMeshes.Part, _ pose: Pose? = nil) { DecorMeshes.emit(part, into: b, offset: o, pose: pose) }
        func all(except: Set<String> = [], _ pose: Pose? = nil) { for part in art.parts where !except.contains(part.name) { emit(part, pose) } }
        let k = min(a.kick, 1.2), t: Float = a.kick > 0.002 ? a.kickT : 99, ph = Float(uid) * 0.7
        switch kind {
        case .beachball:
            guard let ball = art.part("ball") else { return false }
            let q = a.rot, pv = ball.pivot
            emit(ball) { v, n, _ in spin4(v, n, about: pv, q) }
        case .playtunnel:
            // a ripple travelling along the tunnel (x): every ring swells and shrinks a little, one after the other
            let amp = 0.07 * max(k, min(a.peek, 1) * 0.6)
            all { v, n, w in (SIMD3(v.x, v.y * (1 + amp * sinf(v.x * 6.5 - time * 13 + ph)), v.z * (1 + 0.4 * amp * sinf(v.x * 6.5 - time * 13 + ph))), n) }
        case .ringstacker:
            all(except: Set((0..<6).map { "ring\($0)" }))
            for i in 0..<6 {
                guard let r = art.part("ring\(i)") else { continue }
                let pv = r.pivot, f = Float(i)
                let s1 = k * sinf(time * 21 - f * 0.9 + ph), s2 = k * sinf(time * 17 - f * 0.9 + 1.3 + ph)
                let amp = 0.10 + 0.05 * f
                let hop = 0.035 * k * max(0, sinf(time * 13 - f * 1.1))
                emit(r) { v, n, _ in
                    let (p, n2) = spin4(v, n, about: pv, simd_quatf(angle: amp * s1, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: amp * s2, axis: SIMD3(1, 0, 0)))
                    return (p + SIMD3(0, hop, 0), n2)
                }
            }
        case .toyrocket:
            let theta = 0.22 * k * sinf(t * 6.5)
            let c = SIMD3<Float>(0, horseArcY, 0), q = simd_quatf(angle: -theta, axis: SIMD3(0, 0, 1)), roll = SIMD3<Float>(horseArcR * theta, 0, 0)
            func rock(_ v: SIMD3<Float>, _ n: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) { let (p, n2) = spin4(v, n, about: c, q); return (p + roll, n2) }
            if let r = art.part("rocket") { emit(r) { v, n, _ in rock(v, n) } }
            if let fl = art.part("flame") {
                // the flame grows and flickers along the rocket's axis (about the nozzle)
                let axis = SIMD3<Float>(cosf(rocketTilt), sinf(rocketTilt), 0), pv = rocketTail
                let s = 1 + 0.10 * sinf(time * 27 + ph) + 0.12 * sinf(time * 41) + 0.5 * k
                emit(fl) { v, n, _ in
                    let d = v - pv
                    return rock(v + axis * (simd_dot(d, axis) * (s - 1)), n)
                }
            }
        case .plushdino:
            let s = 0.12 * k * cosf(t * 14)
            func squash(_ v: SIMD3<Float>, _ n: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
                let w = min(max(v.y / 1.0, 0), 1)
                return (SIMD3(v.x * (1 + 0.5 * s * w), v.y * (1 - s * w), v.z * (1 + 0.5 * s * w)), n)
            }
            if let body = art.part("body") { emit(body) { v, n, _ in squash(v, n) } }
            if let head = art.part("head") {
                let pv = head.pivot, wob = 0.20 * k * sinf(t * 11)
                emit(head) { v, n, _ in
                    let (p1, n1) = spin4(v, n, about: pv, simd_quatf(angle: wob, axis: SIMD3(0, 0, 1)))
                    return squash(p1, n1)
                }
            }
            if let tl = art.part("tail") {
                let pv = tl.pivot, sw = 0.55 * k * sinf(t * 12 + 1)
                emit(tl) { v, n, w in
                    let (p1, n1) = spin4(v, n, about: pv, simd_quatf(angle: sw * w, axis: SIMD3(0, 1, 0)))
                    return squash(p1, n1)
                }
            }
        case .kickscooter:
            all(except: ["bars", "wheelF", "wheelR"])
            let wheelA = 5.0 * sm4(0, 0.9, t) * k
            for name in ["wheelF", "wheelR"] {
                guard let w = art.part(name) else { continue }
                let pv = w.pivot
                emit(w) { v, n, _ in spin4(v, n, about: pv, simd_quatf(angle: -wheelA, axis: SIMD3(0, 0, 1))) }
            }
            if let bars = art.part("bars") {
                let ang = 0.55 * k * sinf(t * 11) * expf(-1.2 * min(t, 4))
                emit(bars) { v, n, _ in spin4(v, n, about: scooterTop, simd_quatf(angle: ang, axis: scooterAxis)) }
            }
        default:
            all()
        }
        return true
    }
}
