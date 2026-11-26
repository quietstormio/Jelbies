//
//  RoomSwipe.swift
//  A one-finger horizontal swipe on empty floor / space in the home room turns the room camera a little around the room's centre (yaw), and the vertical part of the same drag tips it a little up / down (pitch, same feel, same ease home).
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
    /// Pitch (elevation about the same target): slight. The limit (rad), its rubber band, and radians per finger point.
    static let pitchLimit: Float = pitchDeg * .pi / 180
    static let pitchStretch: Float = pitchLimit * 0.35
    private static var pitchDeg: Float { DevArgs.enabled && UserDefaults.standard.float(forKey: "RoomSwipePitchDeg") > 0 ? UserDefaults.standard.float(forKey: "RoomSwipePitchDeg") : 4 }          // (-RoomSwipePitchDeg <deg>: a capture aid)
    static let pitchPerPoint: Float = 0.0012
    static let idleReturn: Double = 4.0
    static let returnTime: Double = 0.8
    static let offEase: Float = 0.25
    /// Horizontal travel (pt) before a touch counts as a swipe, and how much more horizontal than vertical it must be.
    static let startDistance: CGFloat = 10

    /// The camera yaw now (rad), after the rubber band.
    nonisolated(unsafe) static var yaw: Float = 0
    nonisolated(unsafe) private static var raw: Float = 0          // the finger's unbanded yaw
    nonisolated(unsafe) private static var vel: Float = 0          // rad / s, momentum
    nonisolated(unsafe) static var pitch: Float = 0          // + = the camera rises (looks down on the room more)
    nonisolated(unsafe) private static var rawP: Float = 0
    nonisolated(unsafe) private static var velP: Float = 0
    nonisolated(unsafe) private static var returnFromP: Float = 0
    nonisolated(unsafe) static var dragging = false
    nonisolated(unsafe) private static var lastTouch: Double = 0
    nonisolated(unsafe) private static var returnFrom: Float = 0
    nonisolated(unsafe) private static var returnStart: Double = -1

    static let off: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "RoomSwipeOff") != 0

    /// raw -> displayed: linear inside the limit, an exponential soft stop beyond it.
    static func band(_ x: Float) -> Float { band(x, limit: limit, stretch: stretch) }
    static func band(_ x: Float, limit: Float, stretch: Float) -> Float {
        let a = abs(x)
        if a <= limit { return x }
        return (x < 0 ? -1 : 1) * (limit + stretch * (1 - expf(-(a - limit) / stretch)))
    }

    static func begin(now: Double) { dragging = true; vel = 0; velP = 0; lastTouch = now; returnStart = -1; raw = unband(yaw, limit, stretch); rawP = unband(pitch, pitchLimit, pitchStretch) }
    private static func unband(_ y: Float, _ limit: Float, _ stretch: Float) -> Float {
        let a = abs(y)
        if a <= limit { return y }
        let f = min(max((a - limit) / stretch, 0), 0.999)
        return (y < 0 ? -1 : 1) * (limit - stretch * logf(1 - f))
    }

    /// A finger move of `dx` points (right = positive): the scene follows the finger.
    /// `dy` (down = positive) tips the camera: a finger pulling down raises the eye (the room's top comes toward you).
    static func drag(dx: CGFloat, dy: CGFloat = 0, dt: Double, now: Double) {
        let dp = Float(dy) * pitchPerPoint
        let overP = max(0, abs(rawP) - pitchLimit)
        rawP += (rawP * dp > 0 ? dp / (1 + overP * 6 * (limit / pitchLimit)) : dp)
        pitch = band(rawP, limit: pitchLimit, stretch: pitchStretch)
        if dt > 0.001 { velP = velP * 0.6 + (dp / Float(dt)) * 0.4 }

        let d = -Float(dx) * radPerPoint          // (the camera turns the other way, so the room follows the finger)
        // dragging past the limit gets harder: the finger's travel is scaled down as the band stretches
        let over = max(0, abs(raw) - limit)
        raw += (raw * d > 0 ? d / (1 + over * 6) : d)
        yaw = band(raw)
        if dt > 0.001 { vel = vel * 0.6 + (d / Float(dt)) * 0.4 }
        lastTouch = now
    }

    static func end(now: Double) { dragging = false; if now - lastTouch > 0.08 { vel = 0; velP = 0 }; lastTouch = now }          // (a finger that stopped before it lifted does not fling)
    /// Any touch anywhere on the stage restarts the idle clock.
    static func touched(now: Double) { lastTouch = now; if returnStart >= 0, yaw != 0 || pitch != 0 { returnStart = -1 } }

    /// Once a frame. `allowed` false = a close-up / script is on: ease the yaw to 0 fast.
    static func tick(dt: Float, now: Double, allowed: Bool, touching: Bool = false) {
        if !allowed {
            dragging = false; vel = 0; velP = 0; returnStart = -1
            if pitch != 0 { pitch = abs(pitch) < 0.002 ? 0 : pitch * expf(-dt / (offEase / 4)); rawP = pitch }
            if yaw != 0 { yaw = abs(yaw) < 0.002 ? 0 : yaw * expf(-dt / (offEase / 4)); raw = yaw }
            return
        }
        if dragging { return }
        if touching { lastTouch = now }          // (a finger resting on the room keeps it where it is)
        if yaw == 0, pitch == 0 { vel = 0; velP = 0; returnStart = -1; return }
        if returnStart >= 0 {          // easing home (0.8 s, smoothstep)
            let k = Float(min(max((now - returnStart) / returnTime, 0), 1))
            let e = 1 - k * k * (3 - 2 * k)
            yaw = returnFrom * e; raw = yaw; pitch = returnFromP * e; rawP = pitch
            if k >= 1 { yaw = 0; raw = 0; pitch = 0; rawP = 0; returnStart = -1 }
            return
        }
        coast(&raw, &vel, &yaw, dt: dt, lim: limit, str: stretch)
        coast(&rawP, &velP, &pitch, dt: dt, lim: pitchLimit, str: pitchStretch)
        if now - lastTouch >= idleReturn, abs(vel) <= 0.02, abs(velP) <= 0.02 { returnFrom = yaw; returnFromP = pitch; returnStart = now }
    }

    /// One axis after release: momentum decaying, pushing back at the band, or springing to the limit.
    private static func coast(_ raw: inout Float, _ vel: inout Float, _ out: inout Float, dt: Float, lim: Float, str: Float) {
        if abs(vel) > 0.02 {
            raw += vel * dt; vel *= expf(-dt * 4.5)
            if abs(raw) > lim {
                let s: Float = raw < 0 ? -1 : 1
                vel *= expf(-dt * 12)
                raw = s * (lim + (abs(raw) - lim) * expf(-dt * 10))
            }
            out = band(raw, limit: lim, stretch: str)
        } else if abs(raw) > lim {
            let s: Float = raw < 0 ? -1 : 1
            raw = s * (lim + (abs(raw) - lim) * expf(-dt * 10)); out = band(raw, limit: lim, stretch: str)
        }
    }

    /// The room camera, turned `yaw` about the vertical line through the target.
    /// The pitch actually applied. Tipping UP (finger up, pitch < 0) lowers the eye and the back wall's top edge nears the screen top; with the yaw at its limit
    /// a sliver of void shows (measured: none with yaw alone, growing with the up pitch). So the up pitch shrinks to 0 as the yaw reaches its limit; down is free.
    static func effectivePitch(yaw y: Float, pitch p: Float) -> Float {
        guard p < 0 else { return p }
        return max(p, -pitchLimit * max(0, 1 - abs(y) / limit))
    }

    static func apply(eye e: SIMD3<Float>, target t: SIMD3<Float>) -> SIMD3<Float> {
        guard yaw != 0 || pitch != 0 else { return e }
        let pitch = effectivePitch(yaw: yaw, pitch: pitch)
        var v = e - t
        if yaw != 0 { let c = cosf(yaw), s = sinf(yaw); v = SIMD3<Float>(v.x * c + v.z * s, v.y, -v.x * s + v.z * c) }
        if pitch != 0 {          // raise / lower the eye on its circle about the target, the distance unchanged
            let h = hypotf(v.x, v.z), r = hypotf(h, v.y)
            if h > 1e-4, r > 1e-4 {
                let el = min(max(atan2f(v.y, h) + pitch, 0.05), 1.45)
                let k = r * cosf(el) / h
                v = SIMD3<Float>(v.x * k, r * sinf(el), v.z * k)
            }
        }
        return t + v
    }
}
