//
//  DecorField+BallContact.swift
//  Balls are solid (2026-10-31). The room's round toys (bouncy ball, yarn ball, soccer ball, beach ball) used to be walked over: a Jelbie's body went straight through
//  a ball that lay on the floor. Now:
//    body -> ball   `RoomLayout.resolve` keeps every body out of a ball's contact circle (the ball's radius + `RoomLayout.ballBodyReach` x the body's footprint), so
//                   a walker, a dragged patch and every planner/route that asks the one floor resolver treat a ball as a soft obstacle: they go round it, and a body
//                   that meets one stops at its surface.
//    ball <- body   each field step a body that is moving INTO a ball (within `pushMargin` of its contact circle) gives it a roll along the push direction, at
//                   the body's own (smoothed) speed x 1.15, never less than `minPush`; a ball pinned against a wall just stops the body there.
//    ball <-> ball  two balls overlapping push each other apart (equal masses, restitution `ballRestitution`), waking the resting one.
//  Cost: one circle test per body per ball, a circle test per ball pair, a handful of fixed-size arrays; no allocation after the first step.
//

import Foundation
import simd

/// A ball's contact circle for the floor resolver (main-thread, rebuilt by `DecorField.tick`).
nonisolated struct BallSphere: Sendable {
    var c: SIMD2<Float>
    var r: Float
    var uid: Int
}

extension RoomLayout {
    /// The contact circle of a body is this fraction of its footprint (clamped to 0.6...0.7 so a big margin or the small drag patch still keeps a Jelbie-sized gap).
    static let ballBodyReach: Float = 0.65
    /// The gap a body of this footprint keeps from a ball's centre, besides the ball's radius.
    @inline(__always) static func ballBodyGap(_ footprint: Float) -> Float { min(max(footprint, 0.6), 0.7) * ballBodyReach }

    /// Pushes a body (xz of `p`) out of every ball (but `ignore`); true when it moved.
    @discardableResult
    static func pushOutOfBalls(_ p: inout SIMD3<Float>, radius: Float, ignore: Int?) -> Bool {
        var moved = false
        let gap = ballBodyGap(radius)
        for b in ballSpheres where b.uid != ignore {
            let dx = p.x - b.c.x, dz = p.z - b.c.y
            let need = b.r + gap
            let l2 = dx * dx + dz * dz
            if l2 < need * need {
                let len = l2.squareRoot()
                if len > 1e-5 { p.x = b.c.x + dx / len * need; p.z = b.c.y + dz / len * need } else { p.z = b.c.y + need }
                moved = true
            }
        }
        return moved
    }
}

extension DecorField {
    /// The switch (tests and before/after captures turn it off: TEST_RUNNER_JELBIES_BALLS_OFF=1).
    nonisolated(unsafe) static var ballsSolid = ProcessInfo.processInfo.environment["JELBIES_BALLS_OFF"] == nil
    static let pushMargin: Float = 0.05
    static let minPush: Float = 0.8
    static let pushGain: Float = 1.15
    static let ballRestitution: Float = 0.6

    /// Can this ball be pushed right now (not in a hand, a goal, or under a rider)?
    private func free(_ f: DecorFoot) -> Bool { f.uid != held && occupant[f.uid] == nil && anim[f.uid]?.inGoal ?? -1 < 0 && anim[f.uid]?.carried != true }

    /// Once per step before the pieces animate: refreshes the resolver's ball circles, lets moving bodies push balls and balls push each other.
    func ballContactStep(dt: Float) {
        guard dt > 0 else { return }
        guard Self.ballsSolid else { if !RoomLayout.ballSpheres.isEmpty { RoomLayout.ballSpheres = [] }; return }
        // the circles for the resolver
        spheres.removeAll(keepingCapacity: true)
        for f in feet where f.kind.isBallLike {
            guard free(f), let a = anim[f.uid] else { continue }
            spheres.append(BallSphere(c: a.pos, r: f.kind.rollRadius, uid: f.uid))
        }
        // the bodies' smoothed velocities (position changes; a body held back by a ball keeps its pace for a moment: the EMA decays over ~0.25 s)
        let k = min(1, dt / 0.25)
        for b in bodies {
            if let p = bodyPrev[b.id] {
                let v = (b.pos - p) / dt
                if simd_length_squared(v) > 36 { bodyVel[b.id] = .zero }          // (a teleport / a new scene, not a walk: nothing to push with)
                else { bodyVel[b.id] = (bodyVel[b.id] ?? .zero) * (1 - k) + v * k }
            }
            bodyPrev[b.id] = b.pos
        }
        guard !spheres.isEmpty else { RoomLayout.ballSpheres = spheres; return }
        for s in spheres {
            guard var a = anim[s.uid] else { continue }
            var changed = false
            for b in bodies {
                if a.kicker == b.id, a.kickAge < (feet.first(where: { $0.uid == s.uid })?.kind == .soccerball ? 1.5 : 0.6) { continue }          // (the toe that just kicked it)
                let gap = RoomLayout.ballBodyGap(0.7)
                let d = a.pos - b.pos
                let reach = s.r + gap + Self.pushMargin
                let l2 = d.x * d.x + d.y * d.y
                guard l2 < reach * reach else { continue }
                let len = max(l2.squareRoot(), 1e-4)
                let n = d / len
                let vb = bodyVel[b.id] ?? .zero
                let along = simd_dot(vb, n)
                guard along > 0.05 || len < s.r + gap - 0.01 else { continue }          // moving into it (or already overlapping, e.g. a piece put down on him)
                let push = max(along * Self.pushGain, Self.minPush)
                let cur = simd_dot(a.vel, n)
                if cur < push { a.vel += n * (push - cur) }
                if len < s.r + gap { a.pos += n * (s.r + gap - len) }          // (never stay inside his contact circle)
                a.kicker = -1
                changed = true
            }
            if changed { setAnim(s.uid, a) }
        }
        // ball <-> ball
        if spheres.count > 1 {
            for i in 0..<spheres.count - 1 {
                for j in (i + 1)..<spheres.count {
                    guard var a = anim[spheres[i].uid], var b = anim[spheres[j].uid] else { continue }
                    let d = b.pos - a.pos
                    let need = spheres[i].r + spheres[j].r
                    let l2 = d.x * d.x + d.y * d.y
                    guard l2 < need * need else { continue }
                    let len = l2.squareRoot()
                    let n = len > 1e-5 ? d / len : SIMD2<Float>(0, 1)
                    let pen = need - len
                    a.pos -= n * (pen * 0.5); b.pos += n * (pen * 0.5)
                    let rel = simd_dot(a.vel - b.vel, n)          // > 0: closing
                    if rel > 0 {
                        let imp = rel * (1 + Self.ballRestitution) * 0.5
                        a.vel -= n * imp; b.vel += n * imp
                    }
                    // a resting ball struck by a touching one must roll: never leave them overlapped and still
                    if rel <= 0, simd_length_squared(a.vel) < 1e-4, simd_length_squared(b.vel) < 1e-4 { a.vel -= n * 0.3; b.vel += n * 0.3 }
                    setAnim(spheres[i].uid, a); setAnim(spheres[j].uid, b)
                }
            }
        }
        RoomLayout.ballSpheres = spheres
    }
}
