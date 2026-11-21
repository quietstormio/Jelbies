//
//  GameCamera+Wall.swift
//  The wall picture's share of the camera: the editor's raised view (`wallEditBlend`, 0 everywhere else, so the normal camera is untouched) and the maths between the
//  screen and the back wall (the plane z = RoomLayout.minZ), the way `floorPoint` / `screenPoint` do it for the floor.
//

import simd
import CoreGraphics

extension GameCamera {
    /// 0 = the room camera, 1 = the wall editor's view (eased by `GameCare.tickWallEdit`; like `playBlend`, global so the finger maths follow it).
    nonisolated(unsafe) static var wallEditBlend: Float = 0
    /// How far (wall units) the view rises on a phone on its side so the band above the windows (up to y = 7) is in view above the editor's header and clear of its panel; the portrait view already shows it.
    static let wallEditLift: Float = 2.5
    static func wallEditPose(eye e: SIMD3<Float>, target t: SIMD3<Float>, aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let lift = SIMD3<Float>(0, wallEditLift * poseBlend(aspect), 0)
        return (e + lift, t + lift)
    }

    /// The point (x, y) on the back wall under a screen point of a view of `size`, or nil when the ray misses it.
    static func wallPoint(screen: CGPoint, size: CGSize) -> SIMD2<Float>? {
        guard size.width > 1, size.height > 1 else { return nil }
        let cam = camera(aspect: Float(size.width / size.height))
        let ndc = SIMD2<Float>(Float(screen.x / size.width) * 2 - 1, 1 - Float(screen.y / size.height) * 2)
        return wallHit(ndc: ndc, invViewProj: cam.invViewProj)
    }
    static func wallHit(ndc: SIMD2<Float>, invViewProj: simd_float4x4) -> SIMD2<Float>? {
        let ray = unproject(ndc: ndc, invViewProj: invViewProj)
        guard abs(ray.d.z) > 1e-4 else { return nil }
        let t = (RoomLayout.minZ - ray.o.z) / ray.d.z
        guard t > 0 else { return nil }
        let p = ray.o + ray.d * t
        return SIMD2(p.x, p.y)
    }

    /// Where a point of the back wall lands on the screen of a view of `size`; nil when it is behind the camera.
    static func screenPoint(wall: SIMD2<Float>, size: CGSize) -> CGPoint? {
        guard size.width > 1, size.height > 1 else { return nil }
        let cam = camera(aspect: Float(size.width / size.height))
        let c = cam.viewProj * SIMD4<Float>(wall.x, wall.y, RoomLayout.minZ, 1)
        guard c.w > 1e-4 else { return nil }
        return CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (c.y / c.w * 0.5 + 0.5)) * size.height)
    }

    /// The wall height at the middle of the screen's top edge for a view of this aspect (the room camera, as the player sees it with the editor closed).
    static func wallVisibleTop(aspect: Float) -> Float? {
        let keep = wallEditBlend, keepAspect = self.aspect          // (`camera` records the aspect it was asked for)
        wallEditBlend = 0; defer { wallEditBlend = keep; self.aspect = keepAspect }
        let cam = camera(aspect: aspect)
        return wallHit(ndc: SIMD2(0, 1), invViewProj: cam.invViewProj)?.y
    }
}
