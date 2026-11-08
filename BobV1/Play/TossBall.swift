//
//  TossBall.swift
//  The thrown ball as pure data (no UIKit, no Metal): a sphere in room coordinates (x right, y up, z toward the camera) with gravity, bounces on the floor
//  (restitution 0.58, a little sideways friction), a roll that decays like the soccer ball's (e^-1.15 t), the room's side walls, the back wall, and the
//  Jelbies as upright cylinders with a rounded top. A ball landing on a Jelbie's HEAD does not bounce by itself: the world reports `.headHit` and the play
//  controller (PlayToss.swift) decides what the header does. Everything is deterministic given the world.
//
//  Also here: `TossAim`, the flick -> throw mapping (screen swipe -> a ballistic launch that lands near the swipe's end, with a gentle aim assist toward the
//  Jelbie nearest the swipe's direction).
//

import Foundation
import simd

nonisolated enum TossTuning {
    /// Floaty ball (user 2026-11-07): every flight lasts `slow` x longer than before and gravity falls with its square, so the arcs keep their height and reach.
    static let slow: Float = 1.25
    static let gravity: Float = 9.5 / (slow * slow)
    static let restitution: Float = 0.58
    static let bounceFriction: Float = 0.90          // sideways speed kept by a floor bounce
    static let rollDecayPerS: Float = 1.15
    static let stopSpeed: Float = 0.06
    static let bodyRestitution: Float = 0.45
    static let wallRestitution: Float = 0.55
    /// A Jelbie as the ball sees him: a cylinder of this radius under a dome; the head (a header) is the top disc of this radius.
    static let bodyRadius: Float = 0.62
    static let headRadius: Float = 0.46
    static let bodyTop: Float = 1.35
    /// The hand: the ball is held at this height above the floor under the finger.
    static let handHeight: Float = 0.8
    /// Back wall z, and the floor's far corners (the soccer ball's floor).
    static let zBack: Float = -2.4
    /// The largest step the physics takes (a third of the smallest ball's radius).
    static let maxStep: Float = 0.05
}

nonisolated struct TossBody: Equatable, Sendable {
    var id: Int
    var pos: SIMD2<Float>
    var top: Float = TossTuning.bodyTop
}

nonisolated enum TossEvent: Equatable, Sendable {
    case floorBounce(speed: Float)
    case wall
    case bodyHit(id: Int, speed: Float)
    case headHit(id: Int)
}

/// What the ball may not enter, besides the Jelbies. `xHalf(z)` is the visible half width of the floor at depth z; `solid` is the signed distance to the
/// nearest solid piece (negative inside) and `solidTop` how high those pieces are (the ball passes over them).
nonisolated struct TossWorld {
    var bodies: [TossBody] = []
    var xHalf: (Float) -> Float = { _ in 4 }
    var zFront: Float = 9
    var solid: ((SIMD2<Float>) -> Float)?
    var solidTop: Float = 0.9
}

nonisolated struct TossBall: Sendable {
    var pos: SIMD3<Float>
    var vel: SIMD3<Float> = .zero
    var radius: Float
    var rot = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    var floorBounces = 0
    /// The Jelbie whose head the ball is on (a header in progress): the ball is not tested against him until it has left.
    var ignoring: Int?
    var ignoreT: Float = 0

    init(pos: SIMD3<Float>, radius: Float) { self.pos = pos; self.radius = radius }

    var onFloor: Bool { pos.y <= radius + 0.004 && abs(vel.y) < 0.25 }
    var speedXZ: Float { simd_length(SIMD2(vel.x, vel.z)) }
    var resting: Bool { onFloor && speedXZ < TossTuning.stopSpeed }

    /// Where the ball will come down on the floor if nothing touches it (the same gravity as `sub`; there is no air drag): the xz point (kept inside the visible floor) and the seconds to go. Nil when it is not airborne.
    func landing(xHalf: (Float) -> Float) -> (xz: SIMD2<Float>, t: Float)? {
        let g = TossTuning.gravity
        let y0 = pos.y - radius
        guard y0 > 0.03 || vel.y > 0.5 else { return nil }
        let t = (vel.y + (vel.y * vel.y + 2 * g * max(y0, 0)).squareRoot()) / g
        let x = pos.x + vel.x * t, z = pos.z + vel.z * t
        let zc = min(max(z, TossTuning.zBack + radius), 9 - radius)
        let lim = max(xHalf(zc) - radius, 0.5)
        return (SIMD2(min(max(x, -lim), lim), zc), t)
    }

    /// One physics step of `dt` (sub-stepped). Returns what happened, in order.
    @discardableResult
    mutating func step(_ dt: Float, in w: TossWorld) -> [TossEvent] {
        var ev: [TossEvent] = []
        let speed = simd_length(vel)
        let n = max(1, Int((speed * dt / TossTuning.maxStep).rounded(.up)))
        let h = dt / Float(n)
        for _ in 0..<n { sub(h, w, &ev) }
        if ignoring != nil { ignoreT -= dt; if ignoreT <= 0 { ignoring = nil } }
        return ev
    }

    private mutating func sub(_ h: Float, _ w: TossWorld, _ ev: inout [TossEvent]) {
        let r = radius
        let before = pos
        vel.y -= TossTuning.gravity * h
        pos += vel * h
        // floor
        if pos.y < r {
            pos.y = r
            if vel.y < 0 {
                let vy = -vel.y
                if vy > 0.7 / TossTuning.slow {
                    vel.y = vy * TossTuning.restitution
                    vel.x *= TossTuning.bounceFriction; vel.z *= TossTuning.bounceFriction
                    floorBounces += 1
                    ev.append(.floorBounce(speed: vy))
                } else { vel.y = 0 }
            }
        }
        // rolling friction on the floor
        if pos.y <= r + 0.004, abs(vel.y) < 0.25 {
            let k = expf(-TossTuning.rollDecayPerS * h)
            vel.x *= k; vel.z *= k
            if speedXZ < TossTuning.stopSpeed { vel.x = 0; vel.z = 0 }
        }
        // side walls (the visible floor), the back wall and the front limit
        let lim = max(w.xHalf(pos.z) - r, 0.5)
        if pos.x < -lim { pos.x = -lim; if vel.x < 0 { vel.x = -vel.x * TossTuning.wallRestitution; ev.append(.wall) } }
        if pos.x > lim { pos.x = lim; if vel.x > 0 { vel.x = -vel.x * TossTuning.wallRestitution; ev.append(.wall) } }
        if pos.z < TossTuning.zBack + r { pos.z = TossTuning.zBack + r; if vel.z < 0 { vel.z = -vel.z * TossTuning.wallRestitution; ev.append(.wall) } }
        if pos.z > w.zFront - r { pos.z = w.zFront - r; if vel.z > 0 { vel.z = -vel.z * TossTuning.wallRestitution; ev.append(.wall) } }
        // furniture: a low piece is a wall for a ball under its top
        if let solid = w.solid, pos.y - r < w.solidTop {
            let p = SIMD2(pos.x, pos.z)
            let d = solid(p)
            if d < r {
                let e: Float = 1e-3
                let g = SIMD2(solid(p + SIMD2(e, 0)) - solid(p - SIMD2(e, 0)), solid(p + SIMD2(0, e)) - solid(p - SIMD2(0, e)))
                let nrm = simd_length(g) > 1e-6 ? simd_normalize(g) : SIMD2<Float>(0, 1)
                pos.x += nrm.x * (r - d); pos.z += nrm.y * (r - d)
                let vn = vel.x * nrm.x + vel.z * nrm.y
                if vn < 0 { vel.x -= nrm.x * vn * (1 + 0.5); vel.z -= nrm.y * vn * (1 + 0.5); ev.append(.wall) }
            }
        }
        // the Jelbies
        for b in w.bodies where b.id != ignoring {
            let d = SIMD2(pos.x - b.pos.x, pos.z - b.pos.y)
            let dist = simd_length(d)
            let reach = TossTuning.bodyRadius + r
            guard dist < reach, pos.y - r < b.top + 0.02 else { continue }
            // a ball whose centre is about level with the crown or above it, near the top of the dome, is ON HIS HEAD (the shoulder of the dome counts: the ball rolls off it onto the crown)
            if pos.y > b.top - 0.15, dist < TossTuning.headRadius + 0.3, vel.y <= 0.5 {
                ev.append(.headHit(id: b.id))
                return
            }
            // the side (or the shoulder of the dome): pushed out along the radius, bounced with a soft restitution
            let nrm = dist > 1e-5 ? d / dist : SIMD2<Float>(0, 1)
            pos.x = b.pos.x + nrm.x * reach; pos.z = b.pos.y + nrm.y * reach
            let vn = vel.x * nrm.x + vel.z * nrm.y
            if vn < 0 {
                vel.x -= nrm.x * vn * (1 + TossTuning.bodyRestitution); vel.z -= nrm.y * vn * (1 + TossTuning.bodyRestitution)
                ev.append(.bodyHit(id: b.id, speed: -vn))
            }
        }
        // roll angle
        let step = pos - before
        let flat = SIMD2(step.x, step.z)
        let L = simd_length(flat)
        if L > 1e-6 {
            let dir = flat / L
            rot = simd_normalize(simd_quatf(angle: L / r, axis: SIMD3<Float>(dir.y, 0, -dir.x)) * rot)
        }
    }
}

// MARK: - the flick

/// A flick as the screen delivers it: where the finger let go and how fast it was moving (points / second, y down), in a view of `size`.
nonisolated struct TossFlick: Sendable {
    var release: CGPoint
    var velocity: CGVector
    var size: CGSize
}

nonisolated struct TossThrow: Sendable {
    var start: SIMD3<Float>
    var velocity: SIMD3<Float>
    var target: SIMD3<Float>
    var flight: Float
    /// The Jelbie the aim assist pulled the throw toward (nil = a free throw), and how strongly (0...1).
    var assistedBody: Int?
    var assist: Float
}

@MainActor
enum TossAim {
    /// Seconds-of-travel scale: the landing point on the screen is the release point plus the flick's direction times `reach` x (speed in screens/s).
    static let reach: CGFloat = 0.20
    static let minReach: CGFloat = 0.07, maxReach: CGFloat = 0.78
    /// A flick slower than this (screens/s) is a drop: the ball falls where it is let go.
    static let dropSpeed: CGFloat = 0.45
    /// The aim assist cone (degrees) and its strongest pull.
    static let assistCone: Float = 26
    static let assistMax: Float = 0.85

    /// The world point of a screen point on the hand plane (y = handHeight), or nil above the horizon.
    static func hand(at p: CGPoint, size: CGSize) -> SIMD3<Float>? {
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let ndc = SIMD2<Float>(Float(p.x / size.width) * 2 - 1, 1 - Float(p.y / size.height) * 2)
        let ray = unproject(ndc: ndc, invViewProj: cam.invViewProj)
        guard ray.d.y < -1e-4 else { return nil }
        let t = (TossTuning.handHeight - ray.o.y) / ray.d.y
        guard t > 0 else { return nil }
        return ray.o + ray.d * t
    }

    /// The throw for a flick. `bodies` are the Jelbies (for the aim assist), `radius` the ball's.
    static func throwFor(_ f: TossFlick, bodies: [TossBody], radius: Float) -> TossThrow? {
        guard let start = hand(at: f.release, size: f.size) else { return nil }
        let H = max(f.size.height, 1)
        let sp = hypot(f.velocity.dx, f.velocity.dy) / H          // screens per second
        let dir = sp > 1e-3 ? CGVector(dx: f.velocity.dx / (sp * H), dy: f.velocity.dy / (sp * H)) : CGVector(dx: 0, dy: -1)
        // a drop: it falls from the hand
        if sp < dropSpeed {
            return TossThrow(start: start, velocity: SIMD3(0, 0, 0), target: SIMD3(start.x, radius, start.z), flight: 0, assistedBody: nil, assist: 0)
        }
        let travel = min(max(reach * sp, minReach), maxReach) * H
        let end = CGPoint(x: f.release.x + dir.dx * travel, y: f.release.y + dir.dy * travel)
        var floor = GameCamera.floorPoint(screen: end, size: f.size) ?? SIMD2(Float(start.x) + Float(dir.dx) * 3, TossTuning.zBack + 0.3)
        floor.y = max(floor.y, TossTuning.zBack + 0.4)
        var target = SIMD3<Float>(floor.x, radius, floor.y)
        // aim assist: the Jelbie whose head lies nearest the swipe's direction from the release point
        var best: (id: Int, angle: Float, head: SIMD3<Float>)?
        let swipe = SIMD2<Float>(Float(dir.dx), Float(dir.dy))
        for b in bodies {
            let headW = SIMD3<Float>(b.pos.x, b.top + radius * 0.5, b.pos.y)
            guard let s = GameCamera.screenPoint(floor: b.pos, y: b.top, size: f.size) else { continue }
            let to = SIMD2<Float>(Float(s.x - f.release.x), Float(s.y - f.release.y))
            let L = simd_length(to)
            guard L > 8 else { continue }
            let c = max(-1, min(1, simd_dot(to / L, swipe)))
            let ang = acosf(c) * 180 / .pi
            // far past the swipe's reach is not what he meant
            let reachPts = Float(travel)
            if L > reachPts * 1.9 + 120 || L < reachPts * 0.25 - 40 { continue }
            if ang < assistCone, best == nil || ang < best!.angle { best = (b.id, ang, headW) }
        }
        var assisted: Int?
        var pull: Float = 0
        if let b = best {
            pull = assistMax * (1 - powf(b.angle / assistCone, 1.6)) + 0.1
            pull = min(1, max(0, pull))
            target = target + (b.head - target) * pull
            assisted = b.id
        }
        // the flight: longer for a longer throw
        let rng = simd_length(SIMD2(target.x - start.x, target.z - start.z))
        let T = min(max(0.55 + 0.085 * rng, 0.55), 1.25) * TossTuning.slow
        let g = TossTuning.gravity
        let v = SIMD3<Float>((target.x - start.x) / T, (target.y - start.y + 0.5 * g * T * T) / T, (target.z - start.z) / T)
        return TossThrow(start: start, velocity: v, target: target, flight: T, assistedBody: assisted, assist: pull)
    }

    /// The velocity that takes a ball from `from` to `to` in `T` seconds (gravity only).
    static func ballistic(from: SIMD3<Float>, to: SIMD3<Float>, flight T: Float) -> SIMD3<Float> {
        let g = TossTuning.gravity
        return SIMD3((to.x - from.x) / T, (to.y - from.y + 0.5 * g * T * T) / T, (to.z - from.z) / T)
    }
}
