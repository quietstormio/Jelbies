//
//  Haptics+Play.swift
//  smooth-motion-r1: the feel of the thrown ball. One short tap for a kick, a header and a firm floor bounce; strength from the impact speed; softer and rounder for a
//  head or a foot than for the floor; none for small rolling bounces. The generators are kept and prepared when the ball is THROWN (`prepare()` lowers the latency for
//  a few seconds; calling it right before a tap does not help), and prepared again after each tap. It reuses the game's one gate (`HapticSettings.enabled`, the Settings
//  "Haptics" switch) and the system generators of `Haptic` (Haptics.swift): there is no second haptics system. Behind the same switch as the smooth drawing.
//

import UIKit

enum PlayHaptics {
    /// Below this ball speed (u/s) a floor bounce is a roll: no tap.
    static let floorMin: Float = 3.0
    static let minGap = 0.07          // s between two taps (a ball bouncing on a head and the floor never buzzes twice at once)

    enum Kind: Equatable { case head, foot, floor }

    /// nil = no tap. Pure: the numbers that decide how it feels.
    static func tap(_ k: Kind, speed s: Float) -> (style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)? {
        let c = { (v: Float, lo: Float, hi: Float) in CGFloat(min(max(v, lo), hi)) }
        switch k {
        case .head: return (.soft, c(0.30 + 0.045 * s, 0.30, 0.80))
        case .foot: return (.soft, c(0.25 + 0.040 * s, 0.25, 0.70))
        case .floor: return s < floorMin ? nil : (.medium, c(0.30 + 0.05 * (s - floorMin), 0.30, 0.90))
        }
    }

    private static var gens: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static var lastTap = 0.0
    /// While a play event's own tap is out, the sound it plays must not add the room's `sfx.boop` cue (AudioHub.play) on top: one tap per impact, none for a small bounce.
    static var ownsTap = false
    private static var enabled: Bool { SmoothDraw.on && HapticSettings.enabled }
    private static func gen(_ s: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let g = gens[s] { return g }
        let g = UIImpactFeedbackGenerator(style: s); gens[s] = g; return g
    }

    /// When the ball is thrown (and after every tap): get the engine ready for the next few seconds.
    static func prepare() {
        guard enabled else { return }
        for s in [UIImpactFeedbackGenerator.FeedbackStyle.soft, .medium] { gen(s).prepare() }
    }

    /// Plays the tap of a play event. True = handled here (the caller skips its older fixed buzz).
    @discardableResult
    static func play(_ e: PlayEvent, incoming: Float, outgoing: Float, now: Double = CACurrentMediaTime()) -> Bool {
        guard SmoothDraw.on else { return false }
        let k: Kind
        var speed = incoming
        switch e {
        case .release: prepare(); return false          // (the throw's own buzz stays)
        case .floorBounce(let s): k = .floor; speed = s
        case .header: k = .head; speed = max(incoming, outgoing * 0.5)          // (the head turns the ball: how hard it came in, and how hard it goes)
        case .kick: k = .foot; speed = max(incoming, outgoing)          // (a foot sends a resting ball off: its strength is the outgoing speed)
        default: return false
        }
        if let t = tap(k, speed: speed), HapticSettings.enabled, now - lastTap >= minGap {
            lastTap = now
            gen(t.style).impactOccurred(intensity: t.intensity)
            gen(t.style).prepare()
        }
        return true
    }
}
