//
//  HeadPortraitFrame.swift
//  2026-11-15 (the user's Jelly Race lobby picture: "Why is it showing top view weird random bug"). A lobby avatar and the Studio's action shot are drawn from
//  the body as it is in the paused room. The snapshot camera (MelonStage.renderSnapshot) stood in front of the body's FLATTENED facing and framed it by world
//  heights, so a Jelmiko caught lying, flopped, flung or mid-flip was photographed from its crown or from its feet.
//
//  This is the frame of the same body STOOD UP about its own centre. The stage works out the camera and the key light for that upright body with the lines it
//  always had, then carries them over to the body as it really lies (`carry`). Nothing of the body is touched: no particle, no skinning, no wear moves, so the
//  room never sees the picture being taken. An upright body (a lean, a walk shear, an idle tilt) has no frame and keeps the camera it always had.
//

import simd

struct HeadPortraitFrame {
    /// The tilt (rad, between the body's up axis and world up) from which the body is stood up for its picture. Below it there is no frame.
    static let minTilt: Float = 0.2

    /// The facing of the stood body: horizontal, unit length (the heading of the body's turn about world up).
    let forward: SIMD3<Float>
    /// The stood body's highest particle (world y): its crown, measured along its own up axis.
    let topY: Float
    /// The stood body's lowest particle (world y): its soles, measured along its own up axis.
    let floorY: Float
    /// The body's centre: the point it is stood up about.
    let centroid: SIMD3<Float>
    /// The tip: the rotation (about `centroid`) that takes the stood body to the body as it is.
    let tip: simd_quatf

    /// nil for a body that is upright enough (tilt below `minTilt`) and for a pose that cannot be read (no particles, a broken rotation or centre).
    /// `x`: the particles, xyz per particle (SoftBody.x).
    init?(rotation: simd_quatf, centroid c: SIMD3<Float>, particles x: [Float], minTilt: Float = HeadPortraitFrame.minTilt) {
        let v = rotation.vector          // (ix, iy, iz, r)
        let len = simd_length(v)
        guard len.isFinite, len > 1e-6, c.x.isFinite, c.y.isFinite, c.z.isFinite else { return nil }
        let q = simd_quatf(ix: v.x / len, iy: v.y / len, iz: v.z / len, r: v.w / len)
        let up = q.act(SIMD3<Float>(0, 1, 0))
        guard up.y < cosf(minTilt) else { return nil }          // upright enough: the camera it always had
        // rotation = tip * turn. `turn` is the part about world up (the body's heading); `tip` is what is left, and it lays the up axis over.
        // (A body turned exactly upside down has no heading of its own: it stands up facing the +z of its rest shape.)
        let ty = q.imag.y, tw = q.real
        let tl = (ty * ty + tw * tw).squareRoot()
        let turn = tl > 1e-4 ? simd_quatf(ix: 0, iy: ty / tl, iz: 0, r: tw / tl) : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let t = (q * turn.inverse).vector
        let tLen = simd_length(t)
        guard tLen.isFinite, tLen > 1e-6 else { return nil }
        // the crown and the soles: the particles' reach along the body's own up axis
        var top = -Float.infinity, low = Float.infinity
        var k = 0
        while k + 2 < x.count {
            let h = (x[k] - c.x) * up.x + (x[k + 1] - c.y) * up.y + (x[k + 2] - c.z) * up.z
            top = max(top, h); low = min(low, h)
            k += 3
        }
        guard top.isFinite, low.isFinite else { return nil }
        var f = turn.act(SIMD3<Float>(0, 0, 1)); f.y = 0
        forward = simd_length(f) > 1e-3 ? simd_normalize(f) : SIMD3<Float>(0, 0, 1)
        topY = c.y + top
        floorY = c.y + low
        centroid = c
        tip = simd_quatf(ix: t.x / tLen, iy: t.y / tLen, iz: t.z / tLen, r: t.w / tLen)
    }

    /// A world point of the body as it is -> the same point of the stood body.
    var stand: simd_float4x4 {
        let r = simd_float3x3(tip.inverse)
        let o = centroid - r * centroid
        return simd_float4x4(columns: (SIMD4<Float>(r.columns.0, 0), SIMD4<Float>(r.columns.1, 0), SIMD4<Float>(r.columns.2, 0), SIMD4<Float>(o, 1)))
    }

    /// Carries a camera and a light that were set up for the STOOD body over to the body as it is: every point of the body lands on the pixel, on the
    /// shadow-map texel and under the key light that the stood body would have.
    func carry(camera cam: inout CameraState, light: inout LightState) {
        let m = stand
        cam.view = cam.view * m
        cam.viewProj = cam.viewProj * m
        cam.invViewProj = cam.viewProj.inverse
        cam.pos = centroid + tip.act(cam.pos - centroid)
        cam.fwd = tip.act(cam.fwd)
        light.dir = tip.act(light.dir)
        light.lightVP = light.lightVP * m
        light.topVP = light.topVP * m
    }
}
