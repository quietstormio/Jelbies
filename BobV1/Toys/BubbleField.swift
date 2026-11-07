//
//  BubbleField.swift
//  The bubbles of the bubble wand as pure data (no UIKit, no Metal): at most `cap` live bubbles in room coordinates (x, y up, z toward the camera).
//  A bubble leaves the wand's mouth near the bottom of the screen, rises with a slow wobble, drifts back into the room with a little randomness
//  (a soft air drag), and pops after `life` seconds or at the ceiling. Contact pops (a Jelbie's head or body) come from BubbleWand.
//

import Foundation
import simd

nonisolated struct Bubble: Equatable, Sendable {
    var id: Int
    var pos: SIMD3<Float>
    var vel: SIMD3<Float>
    var radius: Float
    var age: Float = 0
    var life: Float
    var phase: Float
    /// The Jelbie going for it (steer id), -1 = nobody.
    var claimedBy: Int = -1
    /// Already bumped by a body (a bubble that is only nudged away is not bumped again).
    var touched = false
    /// Squash of the wobble, -1...1 (the renderer stretches by it).
    var wobble: Float { sinf(age * 5.2 + phase) }
}

nonisolated struct BubbleField: Sendable {
    static let cap = 40
    static let ceiling: Float = 2.7
    private(set) var bubbles: [Bubble] = []
    private(set) var nextID = 1
    /// Totals (tests, report).
    private(set) var spawned = 0, popped = 0
    private var rng: UInt64 = 0xB0BB1E5

    init(seed: UInt64 = 0xB0BB1E5) { rng = seed | 1 }

    private mutating func r() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 24)
    }
    private mutating func r(_ a: Float, _ b: Float) -> Float { a + (b - a) * r() }

    /// A bubble from the wand's mouth `at` (x, y, z). `strength` 0...1 sets its size and push. False when the cap is reached.
    @discardableResult
    mutating func spawn(strength s: Float, at mouth: SIMD3<Float>) -> Bool {
        guard bubbles.count < Self.cap else { return false }
        let s = min(max(s, 0), 1)
        let radius = r(0.16, 0.26) + 0.20 * s * r(0.4, 1)
        let vel = SIMD3<Float>(r(-0.3, 0.3), r(0.35, 0.6) * (0.8 + 0.5 * s), -r(0.9, 1.6) * (0.6 + 0.5 * s))
        let p = mouth + SIMD3(r(-0.25, 0.25), r(-0.05, 0.1), r(-0.15, 0.15))
        bubbles.append(Bubble(id: nextID, pos: p, vel: vel, radius: radius, life: r(3.8, 6.5), phase: r(0, 6.28)))
        nextID += 1; spawned += 1
        return true
    }

    /// A bubble exactly there (tests, captures).
    @discardableResult
    mutating func insert(at p: SIMD3<Float>, radius: Float = 0.2, life: Float = 6) -> Int? {
        guard bubbles.count < Self.cap else { return nil }
        let id = nextID; nextID += 1; spawned += 1
        bubbles.append(Bubble(id: id, pos: p, vel: .zero, radius: radius, life: life, phase: 0))
        return id
    }

    /// Moves the bubbles; returns the ones that popped by themselves (age or ceiling) so the caller can show the pop.
    @discardableResult
    mutating func step(dt: Float) -> [Bubble] {
        var gone: [Bubble] = []
        var i = 0
        while i < bubbles.count {
            var b = bubbles[i]
            b.age += dt
            // a soft air drag on the push, a gentle lateral sway, a slow rise that eases
            b.vel.z *= max(0, 1 - 0.25 * dt)
            b.vel.x += sinf(b.age * 1.7 + b.phase) * 0.35 * dt
            // the rise eases to a stop around head height and then settles a hair (2026-11-07: bubbles hover where a hop can reach them, not up at the ceiling)
            let y = b.pos.y
            let vyGoal: Float = y < 1.0 ? 0.30 : max(-0.03, 0.30 * (1.5 - y) / 0.5)
            b.vel.y += (vyGoal - b.vel.y) * (y < 1.0 ? 0.4 : 1.2) * dt
            b.pos += b.vel * dt
            if b.age >= b.life || b.pos.y >= Self.ceiling { gone.append(b); bubbles.remove(at: i); popped += 1 } else { bubbles[i] = b; i += 1 }
        }
        return gone
    }

    /// Pops bubble `id`; the bubble, or nil when it is already gone.
    @discardableResult
    mutating func pop(_ id: Int) -> Bubble? {
        guard let i = bubbles.firstIndex(where: { $0.id == id }) else { return nil }
        popped += 1
        return bubbles.remove(at: i)
    }

    mutating func claim(_ id: Int, by jelly: Int) { if let i = bubbles.firstIndex(where: { $0.id == id }) { bubbles[i].claimedBy = jelly } }
    mutating func release(jelly: Int) { for i in bubbles.indices where bubbles[i].claimedBy == jelly { bubbles[i].claimedBy = -1 } }
    func bubble(_ id: Int) -> Bubble? { bubbles.first { $0.id == id } }
    mutating func clear() { bubbles.removeAll(keepingCapacity: true) }
}

extension BubbleField {
    /// A body bumped bubble `id`: it is pushed away from (x, z) `from` and will not be bumped again.
    mutating func nudge(_ id: Int, awayFrom from: SIMD2<Float>) {
        guard let i = bubbles.firstIndex(where: { $0.id == id }) else { return }
        var d = SIMD2(bubbles[i].pos.x, bubbles[i].pos.z) - from
        d = simd_length(d) > 0.01 ? simd_normalize(d) : SIMD2(0, -1)
        bubbles[i].vel.x += d.x * 0.9; bubbles[i].vel.z += d.y * 0.9; bubbles[i].vel.y += 0.25
        bubbles[i].touched = true
    }
}
