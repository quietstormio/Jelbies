//
//  PeerContact.swift
//  Touching Jelbies (2026-10-30): the soft bodies used to collide with nothing but a root-level spring (MelonStage.keepApart), so a hug, a bump or a leapfrog drew one body inside the
//  other and a Jelbie could stand in Pip's tail. Now, once per fixed step before the bodies step, every pair that is close enough to touch gets a contact plane between them
//  (the normal along the line between the two centres, placed where the surfaces meet: each body's own reach along the line is its support distance, and when they overlap the
//  overlap is split evenly), and every body gets the spheres of the others' rigid tails. SoftBody.solvePeers keeps the particles on their side of the plane / out of the spheres inside the
//  substeps; the volume constraints bulge the body round the contact patch and the shape constraints wobble it. Allocation-free; a pair that is not close does no work.
//

import Foundation
import simd

@MainActor
enum PeerContact {
    /// Off = the old behaviour (A/B in the tests and the captures).
    nonisolated(unsafe) static var enabled = true
    enum Tuning {
        /// Centres further apart than this are never in contact (a body is ~1.2 across, arms and a hop included).
        static let reach: Float = 2.9
        /// A plane is set when the surfaces are closer than this (it sits mid-gap: the bodies close the last of it softly, and the arms, hats and wings, which reach past the particles, stop at it) ...
        static let margin: Float = 0.2
        /// ... but never when the centres are nearer than this (a degenerate line; the root spring separates those).
        static let minCentre: Float = 0.25
        /// An overlap deeper than this wakes a sleeper: the plane has particles to move.
        static let wakeDepth: Float = 0.01
        /// How far a tail sphere may be from a body's centre to matter (body radius + the tube).
        static let tailReach: Float = 1.25
        /// Each body keeps this far inside the plane (0: the drawn egg is pressed onto the plane itself, Skinner.clampEggToPeers, so no allowance is needed; any value > 0 holds a steady squeeze that never lets the pair settle).
        static let skin: Float = 0
        /// What the contact gives back to the whole body (SoftBody.peerGiveBack).
        static let giveBack: Float = 0.5
    }

    private static var centres: [SIMD3<Float>] = []

    /// `sims` / `skins` are the bodies in the scene (same order). Clears every body's last contact, then sets this step's.
    static func prepare(_ sims: [SoftBody], skins: [Skinner?]) {
        let m = sims.count
        for s in sims { s.clearPeers() }
        for k in skins { k?.peerPlanes.removeAll(keepingCapacity: true); k?.peerSpheres.removeAll(keepingCapacity: true) }
        guard enabled, m > 1 else { return }
        if centres.count < m { centres = [SIMD3<Float>](repeating: .zero, count: m) }
        for i in 0..<m { centres[i] = sims[i].centroid() }
        for i in 0..<(m - 1) {
            for j in (i + 1)..<m {
                let d = centres[j] - centres[i], dist = simd_length(d)
                guard dist < Tuning.reach, dist > Tuning.minCentre else { continue }
                let u = d / dist
                let si = support(sims[i], centres[i], u), sj = support(sims[j], centres[j], -u)
                let gap = dist - si - sj
                guard gap < Tuning.margin else { continue }
                let at = centres[i] + u * (si + gap / 2)
                let s = simd_dot(at, u)
                sims[i].addPlane(normal: u, offset: s - Tuning.skin)
                sims[j].addPlane(normal: -u, offset: -s - Tuning.skin)
                if i < skins.count { skins[i]?.peerPlanes.append(SIMD4(u, s)) }          // (the limbs and the worn pieces are skin: they stop at the plane itself)
                if j < skins.count { skins[j]?.peerPlanes.append(SIMD4(-u, -s)) }
                if gap < -Tuning.wakeDepth { sims[i].wakeForContact(); sims[j].wakeForContact() }
            }
        }
        // Pip's tail is solid for everybody else
        for (j, sk) in skins.enumerated() where j < m {
            guard let sk, !sk.tailSpheres.isEmpty else { continue }
            for i in 0..<m where i != j {
                for sp in sk.tailSpheres {
                    let c = SIMD3(sp.x, sp.y, sp.z), d = c - centres[i], dist = simd_length(d)
                    guard dist < Tuning.tailReach + sp.w else { continue }
                    guard sims[i].addSphere(sp) else { continue }
                    if i < skins.count { skins[i]?.peerSpheres.append(sp) }
                    if dist - sp.w < support(sims[i], centres[i], d / max(dist, 1e-4)) - Tuning.wakeDepth { sims[i].wakeForContact() }          // (a sphere that touches him wakes a sleeper)
                }
            }
        }
        for s in sims { s.peerGiveBack = Tuning.giveBack }
    }

    /// How far the body reaches from `c` along the unit vector `u` (its particles' furthest dot).
    static func support(_ s: SoftBody, _ c: SIMD3<Float>, _ u: SIMD3<Float>) -> Float {
        var best: Float = -.infinity
        s.x.withUnsafeBufferPointer { p in
            for i in 0..<s.n {
                let d = p[3 * i] * u.x + p[3 * i + 1] * u.y + p[3 * i + 2] * u.z
                if d > best { best = d }
            }
        }
        return best - simd_dot(c, u)
    }
}
