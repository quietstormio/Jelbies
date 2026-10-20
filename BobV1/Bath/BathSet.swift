//
//  BathSet.swift
//  The Bath SET: where Bob stands, the close-up camera, and the per-frame props drawn over him (the held
//  tool, dust puffs off a filthy coat, sud bubbles, spray droplets). Static meshes live in BathModels.swift; shading in BathShaders.metal; drawing in RoomRenderer.
//
//  Chosen layout (world: y up, floor = xz, +z toward the camera):
//    basin (Bob's shallow wash tub)  centre (0, 1.0), outer radius 1.12, rim top y 0.37, water y 0.17 (ankle height)
//    standPoint                      (0, 0.17, 1.0)  floor xz + water height. Bob's feet rest on the basin bottom at y ~ 0.02, so the
//                                    flow should put his root at standPoint.xz and y = 0 (the water is a see-through disc over his ankles).
//    bathroom (modern luxury: stone, oak, brass)  back wall z = -2, side walls x = +-3.4, ceiling y 8.0 (above the game camera eye), floor out to z = 14.5 (fills the whole frame,
//                                    also from the living-room camera if the camera blends out)
//    rain shower head                showerNozzle (0, 2.85, -1.0): a good spray origin
//  Close-up camera (`closeUpPose`): target (0, 0.80, 1.0), elevation 0.36 rad, distance so ~2.6 world units are visible across the
//  screen (Bob ~54% of the width): for a 440x956 portrait aspect that is about eye (0, 3.5, 9.9), target (0, 0.8, 1.0).
//

import simd
import Foundation

nonisolated enum BathSet {
    static let standPoint = SIMD3<Float>(BathModels.basinCentre.x, BathModels.waterY, BathModels.basinCentre.y)
    static let showerNozzle = SIMD3<Float>(0, 2.85, BathModels.backZ + 1.0)
    static let closeUpVisibleWidth: Float = 2.6
    static let closeUpElevation: Float = 0.36
    static let closeUpTargetY: Float = 0.80
    /// Rest-frame body centre the foam grid is measured from (the shader and BathLook directions use this).
    static var bodyCentre: SIMD3<Float> { SIMD3(0, 0.5 * BlobShape.H, 0) }

    static func closeUpPose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let visH = closeUpVisibleWidth / max(GameCamera.framingAspect(aspect), 0.2)
        let dist = visH / (2 * tanf(GameCamera.fovY / 2))
        let t = SIMD3<Float>(standPoint.x, closeUpTargetY, standPoint.z)
        let e = t + SIMD3<Float>(0, sinf(closeUpElevation), cosf(closeUpElevation)) * dist
        return (e, t)
    }

    static func closeUpCamera(aspect: Float) -> CameraState {
        let p = closeUpPose(aspect: aspect)
        var c = CameraState()
        c.view = M4.lookAt(eye: p.eye, at: p.target, up: SIMD3(0, 1, 0))
        c.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.3, far: 60), c.view)
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = p.eye
        c.fwd = simd_normalize(p.target - p.eye)
        return c
    }
}

// MARK: - per-frame props

/// Builds the small meshes drawn over Bob each frame into one reusable soup (no allocation once warm).
nonisolated final class BathOverlay {
    private(set) var soup = BathSoup()
    var isEmpty: Bool { soup.i.isEmpty }
    static let sparkleSpots = 32
    static let maxPuffs = 3, maxBubbles = 48, sprayDrops = 30

    private struct Frame {
        var o: SIMD3<Float>, t: SIMD3<Float>, b: SIMD3<Float>, n: SIMD3<Float>, s: Float
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { o + (t * x + b * y + n * z) * s }
        func a(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { (t * x + b * y + n * z) * s }
    }

    /// Fills the soup. `sparkleAt(i)` returns the deformed surface point and normal at one of `sparkleSpots` evenly spread spots (nil = none).
    func compose(look: BathLook, time: Float, camRight: SIMD3<Float> = SIMD3(1, 0, 0), camUp: SIMD3<Float> = SIMD3(0, 1, 0),
                 sparkleAt: ((Int) -> (p: SIMD3<Float>, n: SIMD3<Float>)?)? = nil) {
        soup.clear()
        if look.tool != .none, look.tool != .rinse, let at = look.toolAt { addTool(look.tool, at: at, time: time) }
        if let nz = look.spray { addSpray(from: nz, time: time) }
        for b in look.bubbles.prefix(Self.maxBubbles) where b.w > 0.003 {
            soup.sphere(SIMD3(b.x, b.y, b.z), b.w, color: .zero, mat: .bubble, alpha: 1, rings: 4, segs: 8)
        }
        if look.sparkle > 0.02, let sparkleAt { addStars(count: Int((look.sparkle * 8).rounded(.up)), time: time, right: camRight, up: camUp, at: sparkleAt) }
        // a filthy, sooty coat sheds a few tiny grey dust puffs (fewer as the soot is washed off)
        let sooty = look.dirt * min(1, look.sootMean * 1.2)
        if sooty > 0.7, let sparkleAt {
            addPuffs(count: min(Self.maxPuffs, Int(((sooty - 0.7) / 0.25 * Float(Self.maxPuffs)).rounded(.up))), time: time, right: camRight, up: camUp, at: sparkleAt)
        }
        if soup.v.isEmpty { bounds = nil; return }
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for x in soup.v { let p = SIMD3(x.pos.x, x.pos.y, x.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        bounds = (lo, hi)
    }

    /// World AABB of this frame's props (the room cache re-shades it), nil when there are none.
    private(set) var bounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)?

    // MARK: dust puffs

    /// Tiny grey camera-facing puffs that rise off his skin, swell and fade (soft discs, depth-tested like the sparkle stars).
    private func addPuffs(count: Int, time: Float, right: SIMD3<Float>, up: SIMD3<Float>, at: (Int) -> (p: SIMD3<Float>, n: SIMD3<Float>)?) {
        for i in 0..<count {
            let rate = 0.28 + 0.2 * hash1(i, 41)
            let t = time * rate + hash1(i, 42) * 9
            let cycle = Int(floorf(t)), u = t - floorf(t)
            let spot = Int(hash1(i, cycle + 300) * Float(Self.sparkleSpots)) % Self.sparkleSpots
            guard let s = at(spot) else { continue }
            let fade = sinf(u * .pi) * (1 - 0.5 * u)
            if fade < 0.03 { continue }
            let size = (0.028 + 0.022 * hash1(i, cycle + 45)) * (0.6 + 0.9 * u)
            let drift = SIMD3<Float>(0.05 * sinf(t * 2.1 + Float(i)), 0.30 * u, 0.04 * cosf(t * 1.7 + Float(i)))
            let c = s.p + s.n * (0.04 + 0.16 * u) + drift
            let g = 0.42 + 0.14 * hash1(i, cycle + 47)
            var ids: [UInt32] = []
            for (x, y) in [(Float(-1), Float(-1)), (1, -1), (1, 1), (-1, 1)] {
                ids.append(soup.vert(c + (right * x + up * y) * size, SIMD3(x, y, 0), SIMD3(g, g, g * 1.02), mat: .puff, alpha: fade * 0.5))
            }
            soup.i.append(contentsOf: [ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])
        }
    }

    // MARK: tools

    private func addTool(_ tool: BathTool, at t: SIMD3<Float>, time: Float) {
        switch tool {
        case .soap:
            // translucent pastel jelly bar with a tiny bubble riding on it
            let c = bathLin(0.84, 0.83, 0.82)
            let ct = cosf(0.4), st = sinf(0.4)
            soup.ellipsoid(t + SIMD3(0, 0.02, 0.02), ax: SIMD3(0.24 * ct, 0, 0.24 * st), ay: SIMD3(0, 0.12, 0), az: SIMD3(-0.15 * st, 0, 0.15 * ct), color: c, mat: .jelly, alpha: 0.86, rings: 7, segs: 14)
            soup.sphere(t + SIMD3(0.08, 0.17, 0.05), 0.035, color: .zero, mat: .bubble, rings: 4, segs: 8)
            soup.sphere(t + SIMD3(0.14, 0.12, 0.09), 0.02, color: .zero, mat: .bubble, rings: 3, segs: 6)
        case .shine:
            // soft polishing cloth / wax pad: a plump cream pad with a folded edge and a pink fold
            let cl = bathLin(0.96, 0.96, 0.95), fold = bathLin(0.86, 0.86, 0.85)
            soup.ellipsoid(t + SIMD3(0, 0, 0.02), ax: SIMD3(0.27, 0, 0), ay: SIMD3(0, 0.07, 0), az: SIMD3(0, 0, 0.22), color: cl, mat: .fabric, rings: 5, segs: 12)
            soup.ellipsoid(t + SIMD3(0.04, 0.07, 0), ax: SIMD3(0.2, 0, 0), ay: SIMD3(0, 0.05, 0), az: SIMD3(0, 0, 0.15), color: fold, mat: .fabric, rings: 4, segs: 10)
            soup.ellipsoid(t + SIMD3(-0.1, 0.1, 0.05), ax: SIMD3(0.07, 0, 0), ay: SIMD3(0, 0.04, 0), az: SIMD3(0, 0, 0.07), color: cl, mat: .fabric, rings: 3, segs: 6)
        case .none, .rinse: break
        }
    }

    // MARK: floating sparkles

    private func hash1(_ a: Int, _ b: Int) -> Float { BathModels.hash(a &* 7919 &+ 13, b &* 104729 &+ 7) }

    /// Camera-facing four-point stars that pop up just off his skin, drift up and fade (each at its own rate and spot).
    private func addStars(count: Int, time: Float, right: SIMD3<Float>, up: SIMD3<Float>, at: (Int) -> (p: SIMD3<Float>, n: SIMD3<Float>)?) {
        for i in 0..<min(count, 20) {
            let rate = 0.22 + 0.3 * hash1(i, 1)
            let t = time * rate + hash1(i, 2) * 9
            let cycle = Int(floorf(t)), u = t - floorf(t)
            let spot = Int(hash1(i, cycle + 100) * Float(Self.sparkleSpots)) % Self.sparkleSpots
            guard let s = at(spot) else { continue }
            let fade = powf(max(sinf(u * .pi), 0), 1.3)
            if fade < 0.02 { continue }
            let size = (0.13 + 0.13 * hash1(i, cycle + 5)) * (0.55 + 0.45 * fade)
            let c = s.p + s.n * (0.07 + 0.30 * u) + SIMD3<Float>(0, 0.22 * u, 0)
            let rot = hash1(i, cycle + 9) * 0.8
            let r = right * cosf(rot) + up * sinf(rot), v = up * cosf(rot) - right * sinf(rot)
            let col = hash1(i, cycle + 3) < 0.5 ? SIMD3<Float>(1.0, 0.97, 0.85) : SIMD3<Float>(0.85, 0.95, 1.0)
            var ids: [UInt32] = []
            for (x, y) in [(Float(-1), Float(-1)), (1, -1), (1, 1), (-1, 1)] {
                ids.append(soup.vert(c + (r * x + v * y) * size, SIMD3(x, y, 0), col, mat: .star, alpha: fade))
            }
            soup.i.append(contentsOf: [ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])
        }
    }

    // MARK: spray

    private func addSpray(from s: SIMD3<Float>, time: Float) {
        let target = s - BathLook.sprayOffset          // short fall onto the rinsed spot (the flow puts `spray` sprayOffset above the hit)
        for k in 0..<Self.sprayDrops {
            let seed = Float(k) * 0.61803
            let ph = (time * 1.7 + seed).truncatingRemainder(dividingBy: 1)
            let p = ph < 0 ? ph + 1 : ph
            let spread = SIMD3<Float>(sinf(seed * 91.7) * 0.10, 0, cosf(seed * 57.3) * 0.10) * (0.3 + p)
            let base = s + (target - s) * SIMD3<Float>(p, 0.5 * p + 0.5 * p * p, p)
            let pos = base + spread
            let r: Float = 0.022 + 0.01 * Float(k % 3)
            soup.ellipsoid(pos, ax: SIMD3(r, 0, 0), ay: SIMD3(0, r * 2.2, 0), az: SIMD3(0, 0, r), color: bathLin(0.6, 0.85, 1.0), mat: .droplet, rings: 3, segs: 6)
        }
    }
}
