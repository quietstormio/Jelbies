//
//  SoftBody+Separation.swift
//  2026-11-01: two Jelbies are two bodies. The sim bodies used to ignore each other (only the steering roots kept a gap), so a hug, a wobble or a lean
//  sank one into the other like a single blob. Now every body is summarised as a BodyProxy (a stack of horizontal discs, one per height band, fitted to
//  its current particles) BEFORE the parallel step; each body then pushes its own particles out of every other proxy inside the substeps (position
//  projection with a stiffness < 1: two soft bodies pressing, not a wall). Both bodies do it, so the correction is shared. Pairs further apart than the
//  sum of their radii cost one distance test per step.
//

import Foundation
import simd

nonisolated struct BodyProxy {
    static let bands = 5, sectors = 12, bandH: Float = 0.3
    var floorY: Float = 0
    var cx = SIMD8<Float>(repeating: 0), cz = SIMD8<Float>(repeating: 0)
    /// Reach per band and 30-degree sector (index band * 12 + sector), measured from the band's centre over ALL the band's particles (arms and feet included); 0 = nothing there.
    var r = SIMD64<Float>(repeating: 0)
    /// Radius of the band's body proper (no arms / feet): only to centre and size the whole proxy.
    var core = SIMD8<Float>(repeating: 0)
    /// Largest reach of each band over all sectors (the cheap reject before the sector lookup).
    var rmax = SIMD8<Float>(repeating: 0)
    var centre = SIMD2<Float>(0, 0)
    var radius: Float = 0
    /// The 30-degree sector of a horizontal offset.
    /// The height band of `h` above the floor (never traps: a non-finite height lands in band 0).
    @inline(__always) static func band(_ h: Float) -> Int {
        let f = h / bandH
        return f.isFinite ? Int(min(Float(bands - 1), max(0, f))) : 0
    }
    @inline(__always) static func sector(_ dx: Float, _ dz: Float) -> Int {
        let a = atan2f(dz, dx) + .pi          // 0 ... 2 pi
        let f = a * (Float(sectors) / (2 * .pi))
        return f.isFinite ? min(sectors - 1, max(0, Int(f))) : 0
    }
    var enabled = true
    /// 0.5 when the other body also moves out of this one's proxy (the correction is shared), 1 when it sleeps.
    var share: Float = 1
}

nonisolated enum BodySeparation {
    /// A/B switch for the tests.
    nonisolated(unsafe) static var enabled = true
    /// Fraction of the penetration given back per substep (1 = a wall).
    static let stiffness: Float = 1.0
    /// Share of the penetration a body resolves when the other one is moving out too (0.5 = exactly half each; the pose attractors pull back every substep, so a bit more).
    static let sharedPush: Float = 0.8

    /// Call on the main thread right before the parallel step: every awake body gets the proxies of all the OTHER bodies in `all` (sleeping ones included).
    static func prepare(awake: [SoftBody], all: [SoftBody]) {
        guard enabled, all.count > 1 else { for s in awake where !s.peerProxies.isEmpty { s.peerProxies = [] }; return }
        var proxies: [BodyProxy] = []
        proxies.reserveCapacity(all.count)
        for s in all { var p = s.makeProxy(); p.share = awake.contains { $0 === s } && p.enabled ? Self.sharedPush : 1; proxies.append(p) }
        for s in awake {
            let idx = all.firstIndex { $0 === s }
            var mine = idx.map { proxies[$0] } ?? s.makeProxy()
            mine.enabled = mine.enabled && s.separates
            s.peerMine = mine
            var near: [BodyProxy] = []
            for (i, p) in proxies.enumerated() where i != idx && p.radius > 0 && simd_distance(p.centre, mine.centre) < p.radius + mine.radius { near.append(p) }
            s.peerProxies = near
        }
    }
}

extension SoftBody {
    /// The body's proxy now (two passes over the particles).
    func makeProxy() -> BodyProxy {
        var p = BodyProxy(); p.floorY = floorY; p.enabled = separates
        let B = BodyProxy.bands, S = BodyProxy.sectors
        var sx = [Float](repeating: 0, count: B), sz = sx, cnt = sx
        let mask = appendageMask
        x.withUnsafeBufferPointer { q in
            for i in 0..<n where !mask[i] {
                let b = BodyProxy.band(q[3 * i + 1] - floorY)
                sx[b] += q[3 * i]; sz[b] += q[3 * i + 2]; cnt[b] += 1
            }
            for b in 0..<B where cnt[b] > 0 { p.cx[b] = sx[b] / cnt[b]; p.cz[b] = sz[b] / cnt[b] }
            for i in 0..<n {
                let b = BodyProxy.band(q[3 * i + 1] - floorY)
                if cnt[b] == 0 { continue }
                let dx = q[3 * i] - p.cx[b], dz = q[3 * i + 2] - p.cz[b]
                let d = (dx * dx + dz * dz).squareRoot()
                // the reach is recorded in the particle's sector and, near a border (a quarter sector), in the neighbour too: an arm tip on a border
                // (two bodies side by side along an axis) must be seen from both sides
                let fr = (atan2f(dz, dx) + .pi) * (Float(S) / (2 * .pi)), s0 = BodyProxy.sector(dx, dz), t = fr - Float(s0)
                p.r[b * S + s0] = max(p.r[b * S + s0], d)
                if t < 0.25 { let k = b * S + (s0 + S - 1) % S; p.r[k] = max(p.r[k], d) }
                else if t > 0.75 { let k = b * S + (s0 + 1) % S; p.r[k] = max(p.r[k], d) }
                if !mask[i] { p.core[b] = max(p.core[b], d) }
            }
        }
        var wsum = SIMD2<Float>(0, 0), w: Float = 0
        for b in 0..<B where p.core[b] > 0 { wsum += SIMD2(p.cx[b], p.cz[b]) * p.core[b]; w += p.core[b] }
        if w > 0 { p.centre = wsum / w }
        var rad: Float = 0
        for b in 0..<B { for s in 0..<S where p.r[b * S + s] > 0 { rad = max(rad, p.r[b * S + s] + simd_distance(SIMD2(p.cx[b], p.cz[b]), p.centre)) } }
        for b in 0..<B { for s in 0..<S { p.rmax[b] = max(p.rmax[b], p.r[b * S + s]) } }
        p.radius = rad
        return p
    }

    /// Push every particle out of the other bodies' discs (horizontally), `BodySeparation.stiffness` of the depth per substep.
    func solvePeers(_ x: UnsafeMutablePointer<Float>) {
        guard peerMine.enabled else { return }
        let k = BodySeparation.stiffness
        for o in peerProxies where o.enabled {
            for i in 0..<n {
                let j = 3 * i
                let b = BodyProxy.band(x[j + 1] - o.floorY)
                let dx = x[j] - o.cx[b], dz = x[j + 2] - o.cz[b]
                if dx * dx + dz * dz >= o.rmax[b] * o.rmax[b] { continue }          // (outside the band's widest reach: no sector lookup)
                let rb = o.r[b * BodyProxy.sectors + BodyProxy.sector(dx, dz)]
                if rb <= 0 { continue }
                let d2 = dx * dx + dz * dz
                if d2 >= rb * rb { continue }
                let d = d2.squareRoot()
                if d > 1e-5 { let f = (rb - d) * k * o.share / d; x[j] += dx * f; x[j + 2] += dz * f }
                else { x[j] += rb * k * o.share }
            }
        }
    }
}
