//
//  RoomSwipe.swift
//  A one-finger horizontal swipe on empty floor / space in the home room turns the room camera a little around the room's centre (yaw only).
//  The camera follows the finger with a soft rubber band at the limit, coasts a moment on release, and after `idleReturn` s with no touch eases back
//  to the default view. Off (and snapped back in `offEase`) in every close-up / script / trip; `-RoomSwipeOff 1` disables it. Applied in GameCamera.camera.
//

import Foundation
import simd

nonisolated enum RoomSwipe {
    /// The limit (rad, ~30 deg) and how far the rubber band may stretch past it.
    static let limit: Float = 10 * .pi / 180
    static let stretch: Float = 0.035
    static let radPerPoint: Float = 0.0022
    static let idleReturn: Double = 4.0
    static let returnTime: Double = 0.8
    static let offEase: Float = 0.25
    /// Horizontal travel (pt) before a touch counts as a swipe, and how much more horizontal than vertical it must be.
    static let startDistance: CGFloat = 10

    /// The camera yaw now (rad), after the rubber band.
    nonisolated(unsafe) static var yaw: Float = 0
    nonisolated(unsafe) private static var raw: Float = 0          // the finger's unbanded yaw
    nonisolated(unsafe) private static var vel: Float = 0          // rad / s, momentum
    nonisolated(unsafe) static var dragging = false
    nonisolated(unsafe) private static var lastTouch: Double = 0
    nonisolated(unsafe) private static var returnFrom: Float = 0
    nonisolated(unsafe) private static var returnStart: Double = -1

    static let off: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "RoomSwipeOff") != 0

    /// raw -> displayed: linear inside the limit, an exponential soft stop beyond it.
    static func band(_ x: Float) -> Float {
        let a = abs(x)
        if a <= limit { return x }
        return (x < 0 ? -1 : 1) * (limit + stretch * (1 - expf(-(a - limit) / stretch)))
    }

    static func begin(now: Double) { dragging = true; vel = 0; lastTouch = now; returnStart = -1; raw = unband(yaw) }
    private static func unband(_ y: Float) -> Float {
        let a = abs(y)
        if a <= limit { return y }
        let f = min(max((a - limit) / stretch, 0), 0.999)
        return (y < 0 ? -1 : 1) * (limit - stretch * logf(1 - f))
    }

    /// A finger move of `dx` points (right = positive): the scene follows the finger.
    static func drag(dx: CGFloat, dt: Double, now: Double) {
        let d = -Float(dx) * radPerPoint          // (the camera turns the other way, so the room follows the finger)
        // dragging past the limit gets harder: the finger's travel is scaled down as the band stretches
        let over = max(0, abs(raw) - limit)
        raw += (raw * d > 0 ? d / (1 + over * 6) : d)
        yaw = band(raw)
        if dt > 0.001 { vel = vel * 0.6 + (d / Float(dt)) * 0.4 }
        lastTouch = now
    }

    static func end(now: Double) { dragging = false; if now - lastTouch > 0.08 { vel = 0 }; lastTouch = now }          // (a finger that stopped before it lifted does not fling)
    /// Any touch anywhere on the stage restarts the idle clock.
    static func touched(now: Double) { lastTouch = now; if returnStart >= 0, yaw != 0 { returnStart = -1 } }

    /// Once a frame. `allowed` false = a close-up / script is on: ease the yaw to 0 fast.
    static func tick(dt: Float, now: Double, allowed: Bool, touching: Bool = false) {
        if !allowed {
            dragging = false; vel = 0; returnStart = -1
            if yaw != 0 { yaw = abs(yaw) < 0.002 ? 0 : yaw * expf(-dt / (offEase / 4)); raw = yaw }
            return
        }
        if dragging { return }
        if touching { lastTouch = now }          // (a finger resting on the room keeps it where it is)
        if yaw == 0 { vel = 0; returnStart = -1; return }
        if returnStart >= 0 {          // easing home (0.8 s, smoothstep)
            let k = Float(min(max((now - returnStart) / returnTime, 0), 1))
            yaw = returnFrom * (1 - k * k * (3 - 2 * k)); raw = yaw
            if k >= 1 { yaw = 0; raw = 0; returnStart = -1 }
            return
        }
        if abs(vel) > 0.02 {          // momentum after release, decaying
            raw += vel * dt; vel *= expf(-dt * 4.5)
            if abs(raw) > limit {          // coasting into the band: it pushes back, the stretch springs closed
                let s: Float = raw < 0 ? -1 : 1
                vel *= expf(-dt * 12)
                raw = s * (limit + (abs(raw) - limit) * expf(-dt * 10))
            }
            yaw = band(raw)
        } else if abs(raw) > limit {          // resting in the band: spring to the limit
            let s: Float = raw < 0 ? -1 : 1
            raw = s * (limit + (abs(raw) - limit) * expf(-dt * 10)); yaw = band(raw)
        }
        if now - lastTouch >= idleReturn, abs(vel) <= 0.02 { returnFrom = yaw; returnStart = now }
    }

    /// The room camera, turned `yaw` about the vertical line through the target.
    static func apply(eye e: SIMD3<Float>, target t: SIMD3<Float>) -> SIMD3<Float> {
        guard yaw != 0 else { return e }
        let v = e - t, c = cosf(yaw), s = sinf(yaw)
        return t + SIMD3<Float>(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)
    }
}
