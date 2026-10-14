//
//  M4.swift
//  Column-major matrix helpers matching the JS `M4` (clip z in [0,1], right-handed view) + CameraRig.
//
//  JS flat index i of a column-major Float32Array == simd columns[i / 4][i % 4]:
//  proj[8] -> columns.2.x, proj[9] -> columns.2.y (used for the lens shift).
//

import simd
import Foundation
import CoreGraphics

enum M4 {
    static func mul(_ a: simd_float4x4, _ b: simd_float4x4) -> simd_float4x4 { a * b }

    static func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1 / tanf(fovy / 2)
        return simd_float4x4(columns: (
            SIMD4<Float>(f / aspect, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, near * far / (near - far), 0)))
    }

    static func ortho(l: Float, r: Float, b: Float, t: Float, n: Float, f: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(2 / (r - l), 0, 0, 0),
            SIMD4<Float>(0, 2 / (t - b), 0, 0),
            SIMD4<Float>(0, 0, 1 / (n - f), 0),
            SIMD4<Float>(-(r + l) / (r - l), -(t + b) / (t - b), n / (n - f), 1)))
    }

    static func lookAt(eye: SIMD3<Float>, at: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - at)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
    }

    static func invert(_ m: simd_float4x4) -> simd_float4x4 { m.inverse }
}

/// Orbit camera + key light rig, framed for Bob (a dome of radius BobShape.R and height BobShape.H on y = 0).
struct CameraRig {
    /// Front-on, near eye level (Bob's reference view). DEBUG launch argument -MelonCamYaw <radians> overrides the yaw
    /// (+pi/2 / -pi/2 look at his sides) and -MelonCamElev <radians> the elevation.
    static var defaultAzimuth: Float {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "MelonCamYaw") != nil { return Float(UserDefaults.standard.double(forKey: "MelonCamYaw")) }
        #endif
        return 0.056      // front reference: ~3 deg toward his left (fitted)
    }
    static var defaultElevation: Float {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "MelonCamElev") != nil {
            let e = Float(UserDefaults.standard.double(forKey: "MelonCamElev"))
            return UserDefaults.standard.integer(forKey: "MelonCamElevNeg") != 0 ? -e : e      // iOS reads a leading "-" in a value as a flag
        }
        #endif
        return 0.123      // front reference elevation ~7 deg (fitted)
    }
    var azimuth: Float = CameraRig.defaultAzimuth
    var elevation: Float = CameraRig.defaultElevation
    var zoom: Float = 1
    var target = CameraRig.home

    /// Look-at point: slightly above the middle of the dome so the face sits a touch above screen centre.
    static let home = SIMD3<Float>(0, 0.45 * BobShape.H, 0)
    /// Bob's rest centroid (follow() eases the target towards it).
    static let restCentroid = SIMD3<Float>(0, 0.5 * BobShape.H, 0)
    static var fov: Float {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "MelonCamFov") != nil { return Float(UserDefaults.standard.double(forKey: "MelonCamFov")) * Float.pi / 180 }
        #endif
        return 18 * Float.pi / 180
    }
    /// DEBUG: explicit pinhole camera for reference matching (-MelonCamDist <world units> -MelonCamTargetY <y>, plus yaw / elev / fov).
    static var debugExplicit: (dist: Float, targetY: Float)? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "MelonCamDist") != nil {
            return (Float(UserDefaults.standard.double(forKey: "MelonCamDist")), Float(UserDefaults.standard.double(forKey: "MelonCamTargetY")))
        }
        #endif
        return nil
    }
    /// Key light: in front, above and to the left so the face is lit; the shader adds a separate back rim for the edge glow.
    static let referenceAzimuth: Float = 0.056
    static let keyDir: SIMD3<Float> = simd_normalize(SIMD3<Float>(-0.5, 0.8, 0.55))

    mutating func reset() { azimuth = Self.defaultAzimuth; elevation = Self.defaultElevation; zoom = 1; target = Self.home }

    /// Wheel / pinch zoom clamp.
    mutating func applyZoom(factor: Float) { zoom = max(0.65, min(1.6, zoom * factor)) }

    /// Orbit clamps (azimuth wide enough to see his back).
    mutating func orbit(dAzimuth: Float, dElevation: Float) {
        azimuth = max(-1.6, min(1.6, azimuth + dAzimuth))
        elevation = max(0.08, min(1.25, elevation + dElevation))
    }

    /// Eases the target after Bob's centroid (skip while the user holds him).
    mutating func follow(centroid c: SIMD3<Float>, dt: Float, grabbing: Bool) {
        if grabbing { return }
        let k = 1 - expf(-dt * 2.2)
        let gx = Self.home.x + (c.x - Self.restCentroid.x) * 0.92
        let gy = Self.home.y + (c.y - Self.restCentroid.y) * 0.5
        let gz = Self.home.z + (c.z - Self.restCentroid.z) * 0.92
        target.x += (gx - target.x) * k
        target.y += (gy - target.y) * k
        target.z += (gz - target.z) * k
    }

    /// viewSize and safeRect are in the same units (points); safeRect is relative to the stage view.
    func camera(viewSize: CGSize, safeRect r: CGRect) -> CameraState {
        let W = Float(viewSize.width), H = Float(viewSize.height)
        let aspect = W / H
        let hf = Float(r.height) / H, wf = Float(r.width) / W
        // Half extents to keep in frame: Bob is 2R wide and H tall; leave room for floor shadow and squash/stretch.
        let Rh: Float = BobShape.R * 1.25, Rv: Float = BobShape.H * 0.74
        let t2 = tanf(Self.fov / 2)
        let dist = max(Rv / (t2 * 0.9 * hf), Rh / (t2 * 0.92 * aspect * wf)) * zoom
        let ce = cosf(elevation)
        if let ex = Self.debugExplicit {
            let tgt = SIMD3<Float>(0, ex.targetY, 0)
            let e2 = tgt + SIMD3<Float>(ex.dist * sinf(azimuth) * ce, ex.dist * sinf(elevation), ex.dist * cosf(azimuth) * ce)
            var c2 = CameraState()
            c2.view = M4.lookAt(eye: e2, at: tgt, up: SIMD3<Float>(0, 1, 0))
            c2.viewProj = M4.mul(M4.perspective(fovy: Self.fov, aspect: aspect, near: 0.1, far: 60), c2.view)
            c2.invViewProj = M4.invert(c2.viewProj)
            c2.pos = e2; c2.fwd = simd_normalize(tgt - e2)
            return c2
        }
        let eye = SIMD3<Float>(target.x + dist * sinf(azimuth) * ce,
                               target.y + dist * sinf(elevation),
                               target.z + dist * cosf(azimuth) * ce)
        let view = M4.lookAt(eye: eye, at: target, up: SIMD3<Float>(0, 1, 0))
        var proj = M4.perspective(fovy: Self.fov, aspect: aspect, near: 0.1, far: 60)
        let cx = Float(r.midX) / W, cy = Float(r.midY) / H
        proj.columns.2.x -= (cx * 2 - 1)      // JS proj[8]
        proj.columns.2.y -= -(cy * 2 - 1)     // JS proj[9]
        var cam = CameraState()
        cam.view = view
        cam.viewProj = M4.mul(proj, view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye
        cam.fwd = simd_normalize(target - eye)
        return cam
    }

    /// Shadow and height maps are centred on Bob himself (ortho bounds cover R = 1 plus stretch/squash and the cast shadow).
    func light(centroid c: SIMD3<Float>) -> LightState {
        // The key light is fixed relative to the camera (the reference's lit flank always faces the camera): turn it about
        // the vertical axis by however far the camera has orbited from the reference view.
        let th = azimuth - Self.referenceAzimuth
        let kd = Self.keyDir
        let k = simd_normalize(SIMD3<Float>(kd.x * cosf(th) + kd.z * sinf(th), kd.y, -kd.x * sinf(th) + kd.z * cosf(th)))
        let at = SIMD3<Float>(c.x, 0.4 * BobShape.H, c.z)
        var l = LightState()
        l.dir = k
        l.intensity = 2.3
        l.lightVP = M4.mul(M4.ortho(l: -2.2, r: 2.2, b: -2.2, t: 2.2, n: 0.1, f: 14),
                           M4.lookAt(eye: at + k * 7, at: at, up: SIMD3<Float>(0, 0, 1)))
        l.topVP = M4.mul(M4.ortho(l: -2.4, r: 2.4, b: -2.4, t: 2.4, n: 0, f: 5),
                         M4.lookAt(eye: SIMD3<Float>(at.x, -1, at.z), at: SIMD3<Float>(at.x, 1, at.z), up: SIMD3<Float>(0, 0, -1)))
        return l
    }

    /// Stacked (iPhone) layout: the safe rect is the whole view.
    static func fullSafeRect(_ size: CGSize) -> CGRect { CGRect(origin: .zero, size: size) }
}
