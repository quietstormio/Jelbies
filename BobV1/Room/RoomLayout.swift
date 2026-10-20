//
//  RoomLayout.swift
//  Room dimensions, collision data for the sim, and the fixed Nintendogs-style camera.
//  Units match the Blob sim (floor at y = 0, Blob ~1.25 tall / ~1.6 wide).
//

import simd
import Foundation

enum RoomLayout {
    static let floorY: Float = 0
    static let minX: Float = -5, maxX: Float = 5
    static let minZ: Float = -5, maxZ: Float = 3.5      // back wall at minZ; maxZ is an invisible front boundary
    static let wallHeight: Float = 5
    /// Visual extents only (the room is a cutaway: walls/floor are drawn past the camera-facing edge and above the ceiling line
    /// so tall portrait views never show empty background). Collision still uses minX...maxZ.
    static let renderMaxZ: Float = 14, renderHeight: Float = 10

    /// Half-space: a point p is inside while dot(normal, p) >= d.
    struct Plane { var normal: SIMD3<Float>; var d: Float }
    nonisolated(unsafe) static var walls: [Plane] = makeWalls(front: maxZ)
    private static func makeWalls(front: Float) -> [Plane] {
        [Plane(normal: SIMD3(0, 0, 1), d: minZ),     // back
         Plane(normal: SIMD3(0, 0, -1), d: -front),  // front (invisible)
         Plane(normal: SIMD3(1, 0, 0), d: minX),     // left
         Plane(normal: SIMD3(-1, 0, 0), d: -maxX)]   // right
    }
    /// Moves the invisible front wall (the roaming floor follows the screen: `GameCamera.refreshRoam`); `maxZ` itself stays the drawn room's front.
    static func setFront(z: Float) { walls = makeWalls(front: z) }

    static let rugCentre = SIMD2<Float>(0, 0)       // (x, z)
    static let rugRadius: Float = 2.8
    static let rugHeight: Float = 0.022

    struct RoundedBox { var centre: SIMD3<Float>; var halfExtents: SIMD3<Float>; var radius: Float }
    /// Whole sofa (arms included) as one rounded box.
    static let sofa = RoundedBox(centre: SIMD3(0, 0.5, -4.2), halfExtents: SIMD3(1.8, 0.5, 0.65), radius: 0.2)

    struct Cylinder { var centre: SIMD2<Float>; var radius: Float; var height: Float }
    static let table = Cylinder(centre: SIMD2(3.7, -4.0), radius: 0.5, height: 0.65)
    static let plant = Cylinder(centre: SIMD2(-4.2, -4.2), radius: 0.4, height: 0.5)
    static var cylinders: [Cylinder] { [table, plant] }

    /// Temporary floor obstacles (the dining tray while it exists): axis-aligned rounded rectangles in xz, `height` tall.
    struct FlatBox: Equatable { var centre: SIMD2<Float>; var half: SIMD2<Float>; var height: Float; var radius: Float = 0.04 }
    /// Set by DiningSet; empty when no meal set is out, so nothing is left behind.
    nonisolated(unsafe) static var dynamicBoxes: [FlatBox] = []
    /// Decor (Room/DecorModel.swift): the placed pieces. Solid ones are walking obstacles in `resolve`; every one is kept clear of by sleep spots.
    nonisolated(unsafe) static var decorFeet: [DecorFoot] = []
    /// The meal tray is only 0.3 high: his round belly goes over it, so only his base (about 0.6 of his footprint radius) has to keep off its box. Without this
    /// the visible floor beside the tray (|x| <= ~1.0 there) is too narrow to pass it, and he was stuck in front of it.
    static let lowPropRadiusScale: Float = 0.5

    /// Signed distance in the xz plane to a FlatBox (negative inside).
    static func boxDistanceXZ(_ p: SIMD2<Float>, _ b: FlatBox) -> Float {
        let inner = simd_max(b.half - SIMD2(repeating: b.radius), .zero)
        let q = simd_abs(p - b.centre) - inner
        return simd_length(simd_max(q, .zero)) + min(max(q.x, q.y), 0) - b.radius
    }

    /// Pushes a sphere out of one FlatBox (no-op when clearly above it).
    static func pushOut(_ p: inout SIMD3<Float>, radius: Float, box b: FlatBox) {
        guard p.y - radius < floorY + b.height else { return }
        let xz = SIMD2(p.x, p.z)
        let sd = boxDistanceXZ(xz, b)
        guard sd < radius else { return }
        let e: Float = 1e-3
        var g = SIMD2(boxDistanceXZ(xz + SIMD2(e, 0), b) - boxDistanceXZ(xz - SIMD2(e, 0), b),
                      boxDistanceXZ(xz + SIMD2(0, e), b) - boxDistanceXZ(xz - SIMD2(0, e), b))
        if simd_length(g) < 1e-6 { g = xz - b.centre }
        g = simd_length(g) > 1e-6 ? simd_normalize(g) : SIMD2(0, 1)
        let push = g * (radius - sd)
        p.x += push.x; p.z += push.y
    }

    /// Distance from `p` to the nearest decor piece's edge (infinite when there is none); `solidOnly` skips the flat ones.
    static func decorDistance(_ p: SIMD2<Float>, solidOnly: Bool = false) -> Float {
        var d = Float.infinity
        for f in decorFeet where !solidOnly || f.spec.solid { var g = f; g.centre = DecorField.shared.position(f); d = min(d, g.distance(p)) }
        return d
    }

    /// Signed distance in the xz plane to the sofa's rounded footprint (negative inside).
    static func sofaDistanceXZ(_ p: SIMD2<Float>) -> Float {
        let b = sofa, inner = SIMD2(b.halfExtents.x, b.halfExtents.z) - SIMD2(repeating: b.radius)
        let q = simd_abs(p - SIMD2(b.centre.x, b.centre.z)) - inner
        return simd_length(simd_max(q, .zero)) + min(max(q.x, q.y), 0) - b.radius
    }

    /// Pushes a sphere (centre, radius) out of walls, sofa and props; returns the corrected centre (y untouched).
    static func resolve(position p0: SIMD3<Float>, radius: Float, lowPropScale: Float = 1, ignoreDecor: Int? = nil) -> SIMD3<Float> {
        var p = p0
        for _ in 0..<2 {
            for w in walls {
                let dist = simd_dot(w.normal, p) - w.d
                if dist < radius { p += w.normal * (radius - dist) }
            }
            // sofa (skip when clearly above it)
            if p.y - radius < sofa.centre.y + sofa.halfExtents.y {
                let xz = SIMD2(p.x, p.z)
                let sd = sofaDistanceXZ(xz)
                if sd < radius {
                    let e: Float = 1e-3
                    var g = SIMD2(sofaDistanceXZ(xz + SIMD2(e, 0)) - sofaDistanceXZ(xz - SIMD2(e, 0)),
                                  sofaDistanceXZ(xz + SIMD2(0, e)) - sofaDistanceXZ(xz - SIMD2(0, e)))
                    g = simd_length(g) > 1e-6 ? simd_normalize(g) : SIMD2(0, 1)
                    let push = g * (radius - sd)
                    p.x += push.x; p.z += push.y
                }
            }
            for c in cylinders where p.y - radius < floorY + c.height {
                let d = SIMD2(p.x, p.z) - c.centre
                let len = simd_length(d), need = c.radius + radius
                if len < need {
                    let dir = len > 1e-6 ? d / len : SIMD2(0, 1)
                    p.x = c.centre.x + dir.x * need; p.z = c.centre.y + dir.y * need
                }
            }
            for b in dynamicBoxes { pushOut(&p, radius: radius * lowPropScale, box: b) }
            for f in decorFeet where f.spec.solid && f.uid != ignoreDecor { pushOut(&p, radius: radius * f.spec.reach, box: f.box) }
        }
        return p
    }
}

/// Fixed 3/4 view: azimuth locked (looking toward -z), elevation ~38 deg, ~3 m back from the rug edge.
enum RoomCamera {
    static let elevation: Float = 38 * .pi / 180
    static let baseFovY: Float = 32 * .pi / 180
    static let maxFovY: Float = 52 * .pi / 180
    static let baseDistance: Float = 9.5
    static let halfWidthToFrame: Float = 3.7                 // rug radius + margin
    static let target = SIMD3<Float>(0, 0.9, -1.2)

    struct Result { var view: simd_float4x4; var proj: simd_float4x4; var eye: SIMD3<Float>; var fovY: Float }

    static func make(aspect: Float) -> Result {
        // Portrait screens: widen the FOV (up to a limit), then back off, so the rug always fits the width.
        var fov = baseFovY, dist = baseDistance
        let needHalfTan = halfWidthToFrame / (baseDistance * aspect)
        if needHalfTan > tanf(baseFovY / 2) {
            fov = min(maxFovY, 2 * atanf(needHalfTan))
            dist = halfWidthToFrame / (tanf(fov / 2) * aspect)
        }
        let eye = target + SIMD3(0, sinf(elevation), cosf(elevation)) * dist
        let view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        let proj = M4.perspective(fovy: fov, aspect: aspect, near: 0.3, far: 60)
        return Result(view: view, proj: proj, eye: eye, fovY: fov)
    }

    static func viewProj(aspect: Float) -> (viewProj: simd_float4x4, eye: SIMD3<Float>) {
        let r = make(aspect: aspect)
        return (r.proj * r.view, r.eye)
    }
}
