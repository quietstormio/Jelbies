//
//  RoamFloor.swift
//  The floor the Jellies roam (user 2026-10-20: "they should use the whole room"). With 2-3 Jellies the camera is pulled back and (in portrait) lifted, and
//  much more floor is on screen than the old fixed box (x +-3.2, z -2.6...3.5) let them use: the front half of a portrait screen was empty floor.
//
//  `GameCamera.refreshRoam(aspect:)` projects the screen through `floorPoint` (the bottom edge, inset by `roamBottomMargin`, less the body's own depth) and the
//  per-depth width rule (`visibleHalfWidthAtBody * (1 - 2 * roamSideMargin) - roamLateralExtent`, clipped by the side walls) into one walkable polygon (rows of
//  `step` in z) that runs from the back wall to the bottom of the screen. The furniture (sofa, plant, side table) is cut out of each row (`free`), so the strip in
//  front of the sofa and the pockets beside it are walkable. Goals are sampled by free AREA, some picks are ZONE picks (front / back / left / right and the four
//  corners), and the sim's safety arena, the front wall and `constrain` follow it. Call it whenever the aspect changes (a rotation); with no refresh (the headless
//  suites, one Jelly) everything keeps the old box.
//  2026-10-21 (user: "they stay in the centre too much"): the fill went 0.90 -> 0.97, corner zones were added, and `constrain` reads the polygon's width.
//  2026-10-21 (user: "perimeter to the edges almost and further up, full range, still pleasing"): the limits are now derived as `roamSideMargin` /
//  `roamBottomMargin` (see the "limits" block below), the HUD button trim is gone, and the back reaches the furniture.
//

import simd
import Foundation

extension GameCamera {
    struct RoamFloor {
        var aspect: Float
        var minZ: Float, maxZ: Float
        /// Row z values (minZ, minZ + step ...) and the half width allowed at each.
        var zs: [Float], hw: [Float]
        /// Per row, the x intervals inside +-hw that the furniture (sofa, plant, side table) leaves free for a body (empty = the whole row).
        var free: [[ClosedRange<Float>]] = []
        static let step: Float = 0.25
        /// Zones of `sampleZone`: 0 front, 1 back, 2 left, 3 right, 4 front-left, 5 front-right, 6 back-left, 7 back-right.
        static let zoneCount = 8
        /// Zone depths are measured from the sofa's front (the back of the open floor), not from the pockets beside the sofa that `minZ` reaches.
        static let zoneBackZ: Float = -2.8

        func halfWidth(at z: Float) -> Float {
            guard let first = zs.first, let last = zs.last else { return 0 }
            if z <= first { return hw[0] }
            if z >= last { return hw[hw.count - 1] }
            let f = (z - first) / Self.step, i = min(Int(f), zs.count - 2), t = f - Float(i)
            return hw[i] + (hw[i + 1] - hw[i]) * t
        }
        func contains(_ p: SIMD2<Float>) -> Bool { p.y >= minZ && p.y <= maxZ && abs(p.x) <= halfWidth(at: p.y) }
        var area: Float { (0..<zs.count).reduce(0) { $0 + rowFree($1, side: 0, from: 0) * Self.step } }
        var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
            let m = hw.max() ?? 0
            return (SIMD2(-m, minZ), SIMD2(m, maxZ))
        }
        /// The free x intervals of row `i` (the whole row when none were built), cut to `side` (-1 left, +1 right, 0 both) and to |x| >= `from` * hw.
        private func intervals(_ i: Int, side: Int, from: Float) -> [ClosedRange<Float>] {
            let h = hw[i]
            var out = [ClosedRange<Float>]()
            func cut(_ lo: Float, _ hi: Float) { if lo < hi { out.append(lo ... hi) } }
            for r in (i < free.count ? free[i] : [-h ... h]) {
                let lo = r.lowerBound, hi = r.upperBound
                if side < 0 { cut(lo, min(hi, -from * h)) }
                else if side > 0 { cut(max(lo, from * h), hi) }
                else if from > 0 { cut(lo, min(hi, -from * h)); cut(max(lo, from * h), hi) }
                else { cut(lo, hi) }
            }
            return out
        }
        private func rowFree(_ i: Int, side: Int, from: Float) -> Float { intervals(i, side: side, from: from).reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } }
        /// A point in row `i` at fraction `u` along its free length (cut as `intervals`).
        private func place(_ i: Int, side: Int, from: Float, _ u: Float, _ u3: Float) -> SIMD2<Float> {
            let iv = intervals(i, side: side, from: from)
            var t = u * iv.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
            for r in iv { let l = r.upperBound - r.lowerBound; if t <= l { return SIMD2(r.lowerBound + t, zs[i] + u3 * Self.step) }; t -= l }
            return SIMD2(0, zs[i] + u3 * Self.step)
        }
        /// A point in the rows of z `zLo...zHi`, weighted by the free length of each (cut by `side` / `from`), uniform over that free AREA; nil when none is free.
        private func sampleRegion(zLo: Float, zHi: Float, side: Int, from: Float, _ u1: Float, _ u2: Float, _ u3: Float) -> SIMD2<Float>? {
            var rows = [(Int, Float)](), total: Float = 0
            for i in zs.indices where zs[i] + Self.step > zLo && zs[i] <= zHi { let f = rowFree(i, side: side, from: from); if f > 1e-4 { rows.append((i, f)); total += f } }
            guard total > 1e-4 else { return nil }
            var x = u1 * total
            var row = rows[rows.count - 1].0
            for (i, f) in rows { if x < f { row = i; break }; x -= f }
            return place(row, side: side, from: from, u2, u3)
        }
        /// A point uniform over the polygon's free AREA (`u1` picks the row by its free width, `u2`/`u3` place it in the row).
        func sampleArea(_ u1: Float, _ u2: Float, _ u3: Float) -> SIMD2<Float> {
            sampleRegion(zLo: minZ, zHi: maxZ, side: 0, from: 0, u1, u2, u3) ?? SIMD2(0, (minZ + maxZ) / 2)
        }
        /// A point in a zone: 0 front (the nearest 30 % of the depth), 1 back (the farthest quarter, with the pockets beside the sofa), 2 left, 3 right (the outer
        /// 45 % of the width), 4...7 the corners (the outer 40 % of the width in the front 30 % / back 25 % of the depth: front-left, front-right, back-left, back-right).
        /// Depths count from the sofa's front (`zoneBackZ`); free area only.
        func sampleZone(_ zone: Int, _ u1: Float, _ u2: Float, _ u3: Float) -> SIMD2<Float> {
            let b = Self.zoneBackZ, depth = maxZ - b
            let frontLo = maxZ - 0.30 * depth, backHi = b + 0.25 * depth
            let r: SIMD2<Float>?
            switch zone {
            case 0: r = sampleRegion(zLo: frontLo, zHi: maxZ, side: 0, from: 0, u1, u2, u3)
            case 1: r = sampleRegion(zLo: minZ, zHi: backHi, side: 0, from: 0, u1, u2, u3)
            case 2, 3: r = sampleRegion(zLo: b + 0.05 * depth, zHi: b + 0.95 * depth, side: zone == 2 ? -1 : 1, from: 0.55, u1, u2, u3)
            default:
                let front = zone == 4 || zone == 5, left = zone == 4 || zone == 6
                r = sampleRegion(zLo: front ? frontLo : minZ, zHi: front ? maxZ : backHi, side: left ? -1 : 1, from: 0.6, u1, u2, u3)
            }
            return r ?? sampleArea(u1, u2, u3)
        }
        /// The four extreme spots (front-left, front-right, back-left, back-right): the front row's ends and, behind, the free spot farthest back on each side (then the
        /// outermost one in its row).
        var extremeCorners: [SIMD2<Float>] {
            let last = zs.count - 1
            var out = [SIMD2<Float>(-hw[last], zs[last]), SIMD2(hw[last], zs[last])]
            for side in [-1, 1] {
                var pick: SIMD2<Float>?
                for i in zs.indices {
                    let iv = intervals(i, side: side, from: 0)
                    if let e = side < 0 ? iv.map(\.lowerBound).min() : iv.map(\.upperBound).max() { pick = SIMD2(e, zs[i]); break }
                }
                out.append(pick ?? SIMD2(Float(side) * hw[0], zs[0]))
            }
            return out
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
    /// The back limit of a roaming centre: the polygon's (the pockets beside the sofa reach the back wall), else the old `walkMinZ`.
    static var roamMinZ: Float { roamFloor?.minZ ?? walkMinZ }

    // MARK: limits (2026-10-21 "roam the whole visible floor, edges almost, back to just in front of the furniture")
    //
    //  Everything below is derived from the camera projection and the room layout, so it holds in both orientations and on any aspect:
    //   * SIDES: the Jelbie's widest point (`roamLateralExtent` from its centre: the body, a wing tip, Pip's spines, Moss's flower, sway) must stay `roamSideMargin`
    //     of the screen width inside each screen edge, so a row's centre half width is `visibleHalfWidthAtBody(z) * (1 - 2 * margin) - extent` (the side walls clip it too).
    //   * BOTTOM: the front of the Jelbie (feet + shadow, `roamBodyDepth` in front of its centre) must stay `roamBottomMargin` of the screen height above the bottom edge.
    //   * BACK: the sofa, plant and side table, with `roamFurnitureClearance` between the body's centre and their edges (the body just touches them), and the back wall;
    //     the rows reach `roamMinZ` and the free spans of each row exclude the furniture, so the pockets beside the sofa are walkable and the strip in front of it is.
    //   The HUD's corner buttons and the "go out" pill are NOT kept clear: they float over the scene (the user circled the whole floor, 2026-10-21).

    /// How much of the screen width stays clear between the Jelbie's widest point and each side edge.
    static let roamSideMargin: Float = 0.04
    /// How much of the screen height stays clear below the Jelbie's feet and shadow.
    static let roamBottomMargin: Float = 0.03
    /// How far the widest Jelbie feature reaches sideways from the body centre (world units): the body radius 0.8 plus the wing tips / spines / sway / the shadow's side, measured with the pixel check of FeatureCaptureTests.testCaptureRoamCorners*.
    static let roamLateralExtent: Float = 0.9
    /// A body's depth toward the camera (its front edge, with the shadow, is this much nearer than its centre).
    static let roamBodyDepth: Float = 0.85
    /// The gap between a body's centre and the furniture edge (`BlobBrain.footprint` 0.7 plus a hair, so `resolve` never pushes a goal).
    static let roamFurnitureClearance: Float = 0.78
    /// Never roam nearer the camera than this (a wild aspect; the drawn floor reaches `RoomLayout.renderMaxZ` 14). A portrait phone sees the floor out to about z 9.
    static let roamMaxZCap: Float = 12.0

    /// Builds the polygon for `aspect` and applies it: `constrain`, the front wall and the arena follow (the stage re-reads the arena for its sims). Needs the
    /// room camera for 2-3 Jellies (`configureRoom(count:)`); one Jelly keeps the old floor.
    @discardableResult
    static func refreshRoam(aspect: Float) -> RoamFloor? {
        guard roomWideScale != 1 || roomEye != baseEye else { roamFloor = nil; return nil }          // the one-Jelly pose: the old floor
        _ = camera(aspect: aspect)
        let size = CGSize(width: CGFloat(1000 * aspect), height: 1000)
        let bottom = (1 - roamBottomMargin) * 1000
        let zb = floorPoint(screen: CGPoint(x: size.width / 2, y: CGFloat(bottom)), size: size)?.y ?? walkMaxZ
        let maxZ = min(max(zb - roamBodyDepth, walkMaxZ), roamMaxZCap)
        let c = roamFurnitureClearance
        let minZ = RoomLayout.minZ + c
        let wallX = RoomLayout.maxX - (roamLateralExtent + 0.05)          // (the body, wings and shadow stay off the side walls too)
        var zs = [Float](), hw = [Float](), free = [[ClosedRange<Float>]]()
        var z = minZ
        while z <= maxZ + 1e-4 {
            // (the body's nearest surface, 0.25 u nearer than `visibleHalfWidthAtBody`'s depth, sets the width the screen allows)
            let wide = visibleHalfWidthAtBody(z: z + 0.25, aspect: aspect) * (1 - 2 * roamSideMargin) - roamLateralExtent
            let h = max(min(wide, wallX), 0.6)
            // the free spans of the row: what the sofa, plant and table leave (sampled every 5 cm)
            var spans = [ClosedRange<Float>](), start: Float?
            var x = -h
            while x <= h + 1e-4 {
                let p = SIMD2(x, z)
                let blocked = RoomLayout.sofaDistanceXZ(p) < c || RoomLayout.cylinders.contains { simd_distance(p, $0.centre) < $0.radius + c }
                if !blocked { if start == nil { start = x } }
                else if let s = start { spans.append(s ... x - 0.05); start = nil }
                x += 0.05
            }
            if let s = start { spans.append(s ... h) }
            zs.append(z); hw.append(h); free.append(spans.filter { $0.upperBound - $0.lowerBound > 0.1 })
            z += RoamFloor.step
        }
        let f = RoamFloor(aspect: aspect, minZ: minZ, maxZ: zs.last ?? maxZ, zs: zs, hw: hw, free: free)
        roamFloor = f
        RoomLayout.setFront(z: f.maxZ + 0.8)
        let a = f.arena
        arenaCenter = a.centre; arenaRadius = a.radius
        return f
    }

    /// Back to the old fixed floor (a new room set-up, tests).
    static func clearRoam() { roamFloor = nil; RoomLayout.setFront(z: RoomLayout.maxZ) }
}
