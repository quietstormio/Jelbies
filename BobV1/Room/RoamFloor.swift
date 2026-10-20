//
//  RoamFloor.swift
//  The floor the Jellies roam (user 2026-10-20: "they should use the whole room"). With 2-3 Jellies the camera is pulled back and (in portrait) lifted, and
//  much more floor is on screen than the old fixed box (x +-3.2, z -2.6...3.5) let them use: the front half of a portrait screen was empty floor.
//
//  `GameCamera.refreshRoam(aspect:)` projects the screen through `floorPoint` (the bottom edge inset for the HUD and the body's own depth) and the
//  per-depth width rule of `constrain` (`visibleHalfWidthAtBody * screenFill - bodyHalfExtent`, clipped by the side walls) into one walkable
//  polygon (rows of `step` in z). Goals are sampled by AREA over it, some picks are ZONE picks (front / back / left / right), and the sim's
//  safety arena, the front wall and `constrain` follow it. Call it whenever the aspect changes (a rotation); with no refresh (the headless suites, one
//  Jelly) everything keeps the old box.
//

import simd
import Foundation

extension GameCamera {
    struct RoamFloor {
        var aspect: Float
        var minZ: Float, maxZ: Float
        /// Row z values (minZ, minZ + step ...) and the half width allowed at each.
        var zs: [Float], hw: [Float]
        static let step: Float = 0.25

        func halfWidth(at z: Float) -> Float {
            guard let first = zs.first, let last = zs.last else { return 0 }
            if z <= first { return hw[0] }
            if z >= last { return hw[hw.count - 1] }
            let f = (z - first) / Self.step, i = min(Int(f), zs.count - 2), t = f - Float(i)
            return hw[i] + (hw[i + 1] - hw[i]) * t
        }
        func contains(_ p: SIMD2<Float>) -> Bool { p.y >= minZ && p.y <= maxZ && abs(p.x) <= halfWidth(at: p.y) }
        var area: Float { zip(zs, hw).reduce(0) { $0 + 2 * $1.1 * Self.step } }
        var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
            let m = hw.max() ?? 0
            return (SIMD2(-m, minZ), SIMD2(m, maxZ))
        }
        /// A point uniform over the polygon's AREA (`u1` picks the row by its width, `u2`/`u3` place it in the row).
        func sampleArea(_ u1: Float, _ u2: Float, _ u3: Float) -> SIMD2<Float> {
            let total = hw.reduce(0, +)
            var x = u1 * total
            var row = hw.count - 1
            for (i, w) in hw.enumerated() { if x < w { row = i; break }; x -= w }
            return SIMD2((u2 * 2 - 1) * hw[row], zs[row] + u3 * Self.step)
        }
        /// A point in a zone: 0 front (the nearest third of the depth), 1 back (the farthest quarter), 2 left, 3 right (the outer thirds of the width).
        func sampleZone(_ zone: Int, _ u1: Float, _ u2: Float, _ u3: Float) -> SIMD2<Float> {
            let depth = maxZ - minZ
            switch zone {
            case 0:
                let z = maxZ - u1 * depth * 0.30
                let h = halfWidth(at: z); return SIMD2((u2 * 2 - 1) * h, z)
            case 1:
                let z = minZ + u1 * depth * 0.25
                let h = halfWidth(at: z); return SIMD2((u2 * 2 - 1) * h, z)
            default:
                let z = minZ + (0.05 + 0.9 * u1) * depth
                let h = halfWidth(at: z)
                let x = h * (0.55 + 0.45 * u2)
                return SIMD2(zone == 2 ? -x : x, z)
            }
        }
        /// The sim's circular safety arena that holds the whole polygon.
        var arena: (centre: SIMD2<Float>, radius: Float) {
            let c = SIMD2<Float>(0, (minZ + maxZ) / 2)
            var r: Float = 0
            for (z, h) in zip(zs, hw) { r = max(r, simd_distance(c, SIMD2(h, z))) }
            return (c, r + 0.9)
        }
    }

    /// The roaming polygon of the current aspect (nil = the old fixed box).
    nonisolated(unsafe) static var roamFloor: RoamFloor?
    /// The front limit of a roaming centre: the polygon's, else the old `walkMaxZ`.
    static var roamMaxZ: Float { roamFloor?.maxZ ?? walkMaxZ }
    /// How much of the bottom of the screen the HUD keeps (fraction of the height): portrait has the mic / book / care row, landscape the same row shorter.
    static func roamBottomInset(aspect: Float) -> Float { 0.20 - 0.04 * portraitAmount(aspect) }
    /// A body's depth toward the camera (its front edge is this much nearer than its centre).
    static let roamBodyDepth: Float = 0.75
    /// Never roam nearer the camera than this (a wild aspect), nor further back than the old front.
    static let roamMaxZCap: Float = 7.0

    /// Builds the polygon for `aspect` and applies it: `constrain`, the front wall and the arena follow (the stage re-reads the arena for its sims). Needs the
    /// room camera for 2-3 Jellies (`configureRoom(count:)`); one Jelly keeps the old floor.
    @discardableResult
    static func refreshRoam(aspect: Float) -> RoamFloor? {
        guard roomWideScale != 1 || roomEye != baseEye else { roamFloor = nil; return nil }          // the one-Jelly pose: the old floor
        _ = camera(aspect: aspect)
        let size = CGSize(width: CGFloat(1000 * aspect), height: 1000)
        let bottom = (1 - roamBottomInset(aspect: aspect)) * 1000
        let zb = floorPoint(screen: CGPoint(x: size.width / 2, y: CGFloat(bottom)), size: size)?.y ?? walkMaxZ
        let maxZ = min(max(zb - roamBodyDepth, walkMaxZ), roamMaxZCap)
        var zs = [Float](), hw = [Float]()
        var z = walkMinZ
        while z <= maxZ + 1e-4 {
            let wide = visibleHalfWidthAtBody(z: z, aspect: aspect) * screenFill - bodyHalfExtent
            zs.append(z); hw.append(max(min(wide, RoomLayout.maxX - 0.7), 0.6))
            z += RoamFloor.step
        }
        let f = RoamFloor(aspect: aspect, minZ: walkMinZ, maxZ: zs.last ?? maxZ, zs: zs, hw: hw)
        roamFloor = f
        RoomLayout.setFront(z: f.maxZ + 0.8)
        let a = f.arena
        arenaCenter = a.centre; arenaRadius = a.radius
        return f
    }

    /// Back to the old fixed floor (a new room set-up, tests).
    static func clearRoam() { roamFloor = nil; RoomLayout.setFront(z: RoomLayout.maxZ) }
}
