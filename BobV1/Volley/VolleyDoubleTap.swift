//
//  VolleyDoubleTap.swift
//  Switching to your teammate in Jelly Volleyball by a double tap, as plain testable pieces: the timing of two taps (`VolleyDoubleTap`) and which Jelmiko a point on the screen means
//  (`VolleyPick`). The screen (VolleyChrome) feeds them every finger that lifts after a short, still touch, in the court layer's own coordinate space, so the same code serves the left
//  half (where the floating stick lives) and the right half. Whatever the auto-switch setting, a double tap on either of your two Jelmiko gives you that one.
//

import Foundation
import CoreGraphics
import simd

/// Two short taps close together in time and place.
struct VolleyDoubleTap {
    /// The most time between the two taps (touch-ups) and the most distance (points).
    static let window: TimeInterval = 0.3
    static let slop: CGFloat = 70
    /// A tap is a short, still touch: it lasts no longer than this and the finger moves no further than this.
    static let maxPress: TimeInterval = 0.3
    static let maxTravel: CGFloat = 16
    private var last: (at: CGPoint, time: TimeInterval)?

    /// A finger lifted at `at` / `time` after `press` seconds and `travel` points of movement. True when this tap completes a double tap (the pair is then used up).
    mutating func lift(at: CGPoint, time: TimeInterval, press: TimeInterval, travel: CGFloat) -> Bool {
        guard press <= Self.maxPress, travel <= Self.maxTravel else { last = nil; return false }
        if let l = last, time - l.time <= Self.window, time >= l.time, hypot(at.x - l.at.x, at.y - l.at.y) <= Self.slop {
            last = nil
            return true
        }
        last = (at, time)
        return false
    }
    mutating func reset() { last = nil }
}

enum VolleyPick {
    /// The screen point of a body's middle (its centre height is half its crown height).
    static func centre(_ body: SIMD3<Float>, size: CGSize) -> CGPoint? {
        GameCamera.screenPoint(floor: SIMD2(body.x, body.z), y: body.y * 0.5, size: size)
    }

    /// How far from the middle of a body (points) still counts as touching it: about a body and three quarters wide on the screen (a body is ~1.1 world units across; measured from the
    /// projected court, so it follows the portrait / landscape camera), never under 72 or over 170.
    static func reach(_ body: SIMD3<Float>, size: CGSize) -> CGFloat? {
        guard let l = GameCamera.screenPoint(floor: SIMD2(body.x - 0.55, body.z), y: body.y * 0.5, size: size),
              let r = GameCamera.screenPoint(floor: SIMD2(body.x + 0.55, body.z), y: body.y * 0.5, size: size) else { return nil }
        return min(max(hypot(r.x - l.x, r.y - l.y) * 1.75, 72), 170)
    }

    /// The nearest of your two Jelmiko (0 or 1) to `at` within reach, nil when the point is on neither.
    static func nearest(bodies: [SIMD3<Float>], at: CGPoint, size: CGSize) -> Int? {
        var best: (Int, CGFloat)?
        for i in 0..<min(2, bodies.count) {
            guard let c = centre(bodies[i], size: size), let reach = reach(bodies[i], size: size) else { continue }
            let d = hypot(c.x - at.x, c.y - at.y)
            if d < reach, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }
}
