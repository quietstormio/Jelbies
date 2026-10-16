//
//  GameCamera.swift
//  Fixed Nintendogs-style camera for the game screen: low (~18 deg), looking straight at the back wall.
//  Also the visible-floor bounds Bob (and the brain) must stay within.
//

import simd
import Foundation

enum GameCamera {
    static let eye = SIMD3<Float>(0, 7.2, 14)
    static let target = SIMD3<Float>(0, 0.0, -0.3)
    static let fovY: Float = 34 * .pi / 180
    /// Key light for the room (toward the light): front, upper left. Fixed, since the camera is.
    static let keyDir = simd_normalize(SIMD3<Float>(-0.5, 0.8, 0.55))
    /// Default portrait aspect (iPhone 17 Pro Max); the stage updates this from its real size.
    nonisolated(unsafe) static var aspect: Float = 440.0 / 956.0

    /// `focus` 0 = the normal low room camera; 1 = the focus-mode close-up on the front spot (see `focusPose`); in between the two poses are blended.
    static func camera(aspect: Float, focus: Float = 0) -> CameraState {
        self.aspect = aspect
        var e = eye, t = target
        if focus != 0 {
            let p = focusPose(aspect: aspect)
            e += (p.eye - e) * focus
            t += (p.target - t) * focus
        }
        var c = CameraState()
        c.view = M4.lookAt(eye: e, at: t, up: SIMD3(0, 1, 0))
        c.viewProj = M4.mul(M4.perspective(fovy: fovY, aspect: aspect, near: 0.3, far: 60), c.view)
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = e
        c.fwd = simd_normalize(t - e)
        return c
    }

    // MARK: Focus close-up

    /// Share of the screen width Bob's body (2R wide) fills in the close-up. A portrait phone is about as tall as Bob is wide, so the
    /// width, not the height, limits the zoom: ~36% of the screen height at 0.86 of the width.
    static let focusWidthFill: Float = 0.86
    /// Where Bob's middle sits on screen (0 top ... 1 bottom): a little above centre, the actions dock takes the bottom.
    static let focusBodyScreenY: Float = 0.44
    /// Camera elevation in the close-up (rad): low, like the room camera, so the room stays softly visible behind him.
    static let focusElevation: Float = 0.17

    /// Eye / target of the close-up: centred on the front spot, facing him.
    static func focusPose(aspect: Float, spot: SIMD2<Float> = callSpot) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let visW = 2 * BobShape.R / focusWidthFill
        let visH = visW / max(aspect, 0.2)
        let dist = visH / (2 * tanf(fovY / 2))
        let mid = 0.5 * BobShape.H
        let ty = mid - (0.5 - focusBodyScreenY) * visH           // below his middle -> he sits above the screen centre
        let t = SIMD3<Float>(spot.x, ty, spot.y)
        let e = t + SIMD3<Float>(0, sinf(focusElevation), cosf(focusElevation)) * dist
        return (e, t)
    }

    /// Key light + shadow / height maps centred on Bob (same extents the studio uses).
    /// Direction used only to build the shadow map: steeper than the shading key, so the cast shadow stays short.
    static let shadowDir = simd_normalize(SIMD3<Float>(-0.18, 1.0, 0.22))

    static func light(centroid c: SIMD3<Float>) -> LightState {
        let k = keyDir
        let at = SIMD3<Float>(c.x, 0.4 * BobShape.H, c.z)
        var l = LightState()
        l.dir = k
        l.intensity = 2.3
        l.lightVP = M4.mul(M4.ortho(l: -2.2, r: 2.2, b: -2.2, t: 2.2, n: 0.1, f: 14),
                           M4.lookAt(eye: at + shadowDir * 7, at: at, up: SIMD3<Float>(0, 0, 1)))
        l.topVP = M4.mul(M4.ortho(l: -2.4, r: 2.4, b: -2.4, t: 2.4, n: 0, f: 5),
                         M4.lookAt(eye: SIMD3<Float>(at.x, -1, at.z), at: SIMD3<Float>(at.x, 1, at.z), up: SIMD3<Float>(0, 0, -1)))
        return l
    }

    // MARK: Visible floor

    /// Walkable depth range (z) and the circular safety arena used by the sim.
    static let walkMinZ: Float = -2.6, walkMaxZ: Float = 3.0
    static let arenaCenter = SIMD2<Float>(0, 0.5), arenaRadius: Float = 3.3
    /// Bob's half width (rest) ~0.8.
    static let bobRadius: Float = 0.8

    /// Half width of the visible floor strip at depth z (world units, camera looks down -z).
    static func visibleHalfWidth(z: Float, aspect: Float = GameCamera.aspect) -> Float {
        let v = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        let p = v * SIMD4<Float>(0, 0, z, 1)
        return -p.z * tanf(fovY / 2) * aspect
    }

    /// Half width of the screen at the height of Bob's widest part (y 0.65), a little nearer than his centre.
    static func visibleHalfWidthAtBody(z: Float, aspect: Float = GameCamera.aspect) -> Float {
        let v = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        let p = v * SIMD4<Float>(0, 0.65, z + 0.3, 1)
        return -p.z * tanf(fovY / 2) * aspect
    }
    /// Projected half extent Bob needs sideways (body + sway + jiggle) and the fraction of the screen half width he may use.
    static let bodyHalfExtent: Float = 0.8, screenFill: Float = 0.9

    /// Clamps a floor position (centroid) so a body of `radius` stays on the visible floor, off the sofa and props.
    static func constrain(_ p: SIMD3<Float>, radius: Float = GameCamera.bobRadius, lowPropScale: Float = 1) -> SIMD3<Float> {
        var q = RoomLayout.resolve(position: p, radius: radius, lowPropScale: lowPropScale)
        q.z = min(max(q.z, walkMinZ), walkMaxZ)
        let hw = max(visibleHalfWidthAtBody(z: q.z) * screenFill - max(bodyHalfExtent, radius * 0.9), 0)
        q.x = min(max(q.x, -hw), hw)
        return q
    }

    /// Good spots (x, z) on the visible floor, in room coordinates.
    static let centre = SIMD2<Float>(0, 0)
    /// Front-centre "come here" spot, close to the camera.
    static let callSpot = SIMD2<Float>(0, 2.4)
    /// Bowl spots (the bowls sit beside the call spot, near the front; just inside the screen).
    static let foodBowlSpot = SIMD2<Float>(-0.9, 1.9)
    static let waterBowlSpot = SIMD2<Float>(0.9, 1.9)
}
