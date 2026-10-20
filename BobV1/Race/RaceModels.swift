//
//  RaceModels.swift
//  The Waddle Sprint track as a RoomMesh (the room renderer draws it instead of the living room while `raceVisible`): grass in mown stripes, a clay
//  running track with three lanes (white lane lines, a start line, a checkered finish line), a finish gantry with a checkered banner, bushes along
//  the sides, far hills and a sky wall. Materials: plain for everything lit; "glow" (the window pane) for the sky, so the day / night sky colours
//  of DayLight reach it for free. All colours are pastel and linear.
//
//  The track runs along z: the start line at RaceTuning.startZ (far), the finish at RaceTuning.finishZ (near the camera). Lanes are RaceTuning.laneX.
//

import simd
import Foundation

enum RaceModels {
    /// Half width of the clay strip (three lanes + a margin).
    static let trackHalfW: Float = 2.7
    static let gantryX: Float = 2.95
    static let gantryHeight: Float = 3.5

    static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }

    // pastel palette
    static let grassA = srgb(0.60, 0.82, 0.50), grassB = srgb(0.54, 0.77, 0.45)
    static let clay = srgb(0.93, 0.66, 0.55), clayDark = srgb(0.88, 0.60, 0.50)
    static let white = srgb(0.99, 0.98, 0.95), ink = srgb(0.28, 0.24, 0.30)
    static let banner = srgb(0.96, 0.58, 0.68), post = srgb(0.99, 0.95, 0.88)
    /// The sky pane is lit x1.25 x up to 1.5 by the room shader, so its albedo is the target blue divided by that.
    static let skyDay = srgb(0.62, 0.80, 0.98) / 1.8
    /// The room shader's ambient / fog swatches for the outdoors: pal2 = ground bounce, pal3 = haze toward the horizon, pal4 = sky light.
    static let swatch2 = srgb(0.52, 0.74, 0.44), swatch3 = srgb(0.86, 0.93, 1.0) / 0.62, swatch4 = srgb(0.74, 0.86, 1.0)

    static func build() -> RoomMesh {
        let b = RoomMeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        let z0 = -70 as Float, z1 = 40 as Float, xw = 60 as Float
        let tz0 = RaceTuning.startZ - 2.2, tz1 = RaceTuning.finishZ + 6

        // ---- grass: mown stripes across the whole field (a strong depth cue) ----
        b.material = .plain
        var z = z0
        var k = 0
        while z < z1 {
            let step: Float = z > tz0 - 4 && z < tz1 + 4 ? 1.5 : 8
            b.color = k % 2 == 0 ? grassA : grassB
            b.flatQuad(SIMD3(-xw, 0, z), SIMD3(-xw, 0, min(z + step, z1)), SIMD3(xw, 0, min(z + step, z1)), SIMD3(xw, 0, z), normal: up)
            z += step; k += 1
        }

        // ---- the clay strip ----
        let y1: Float = 0.006, y2: Float = 0.012, y3: Float = 0.018
        b.color = clay
        b.flatQuad(SIMD3(-trackHalfW, y1, tz0), SIMD3(-trackHalfW, y1, tz1), SIMD3(trackHalfW, y1, tz1), SIMD3(trackHalfW, y1, tz0), normal: up)
        // darker bands (every other lane) so the lanes read
        b.color = clayDark
        for lane in [0, 2] {
            let cx = RaceTuning.laneX(lane), hw = RaceTuning.laneSpacing / 2
            b.flatQuad(SIMD3(cx - hw, y2, tz0), SIMD3(cx - hw, y2, tz1), SIMD3(cx + hw, y2, tz1), SIMD3(cx + hw, y2, tz0), normal: up)
        }

        // ---- white lines: lane lines, track edges, the start line ----
        b.color = white
        let lw: Float = 0.07
        for k in 0..<4 { let x = (Float(k) - 1.5) * RaceTuning.laneSpacing
            
            b.flatQuad(SIMD3(x - lw, y3, tz0), SIMD3(x - lw, y3, tz1), SIMD3(x + lw, y3, tz1), SIMD3(x + lw, y3, tz0), normal: up)
        }
        let sz = RaceTuning.startZ + 0.45
        let tw = RaceTuning.laneSpacing * 1.5 + lw
        b.flatQuad(SIMD3(-tw, y3, sz - 0.1), SIMD3(-tw, y3, sz + 0.1), SIMD3(tw, y3, sz + 0.1), SIMD3(tw, y3, sz - 0.1), normal: up)

        // ---- the finish line: two rows of checkers across the track ----
        let fz = RaceTuning.finishZ
        let cell: Float = 0.30, cols = Int((2 * tw / cell).rounded())
        for row in 0..<2 {
            for c in 0..<cols {
                b.color = (c + row) % 2 == 0 ? ink : white
                let x0 = -tw + Float(c) * cell, zz = fz - cell + Float(row) * cell
                b.flatQuad(SIMD3(x0, y3, zz), SIMD3(x0, y3, zz + cell), SIMD3(x0 + cell, y3, zz + cell), SIMD3(x0 + cell, y3, zz), normal: up)
            }
        }

        // ---- the finish gantry: two posts and a checkered banner ----
        b.color = post
        for s in [Float(-1), 1] {
            b.roundedBox(centre: SIMD3(s * gantryX, gantryHeight / 2, fz), half: SIMD3(0.13, gantryHeight / 2, 0.13), radius: 0.1, color: post)
            b.roundedBox(centre: SIMD3(s * gantryX, 0.12, fz), half: SIMD3(0.32, 0.12, 0.32), radius: 0.1, color: banner)
        }
        b.roundedBox(centre: SIMD3(0, gantryHeight + 0.05, fz), half: SIMD3(gantryX + 0.2, 0.34, 0.1), radius: 0.12, color: banner)
        // checkers on the banner's near face
        let bcell: Float = 0.2, bcols = Int(((gantryX + 0.12) * 2 / bcell).rounded())
        let bn = SIMD3<Float>(0, 0, 1)
        for row in 0..<3 {
            for c in 0..<bcols where (c + row) % 2 == 0 {
                b.color = white
                let x0 = -(gantryX + 0.12) + Float(c) * bcell, y0 = gantryHeight - 0.2 + Float(row) * bcell
                let zf = fz + 0.105
                b.flatQuad(SIMD3(x0, y0, zf), SIMD3(x0 + bcell, y0, zf), SIMD3(x0 + bcell, y0 + bcell, zf), SIMD3(x0, y0 + bcell, zf), normal: bn)
            }
        }

        // ---- bushes along both sides, hills far behind, a few trees ----
        var rng = RaceRNG(seed: 77)
        let greens = [srgb(0.46, 0.72, 0.42), srgb(0.52, 0.78, 0.46), srgb(0.40, 0.66, 0.40), srgb(0.58, 0.80, 0.50)]
        for s in [Float(-1), 1] {
            var zb = tz0 - 4
            while zb < tz1 {
                let w = rng.range(0.5, 0.9), h = rng.range(0.4, 0.75)
                b.roundedBox(centre: SIMD3(s * (4.3 + rng.range(0, 0.8)), h * 0.8, zb), half: SIMD3(w, h, w * 1.2), radius: min(w, h) * 0.9, color: greens[Int(rng.next() * 4) % 4])
                zb += rng.range(1.3, 2.2)
            }
        }
        for i in 0..<9 {
            let x = (Float(i) - 4) * 11 + rng.range(-3, 3)
            b.roundedBox(centre: SIMD3(x, 0.9, -50 - rng.range(0, 5)), half: SIMD3(rng.range(6, 9), rng.range(1.6, 2.6), rng.range(3, 5)), radius: 1.6, color: greens[i % 4])
        }
        for s in [Float(-1), 1] {
            for j in 0..<3 {                                   // round trees beside the track
                let x = s * (6.8 + Float(j) * 3.2), zt = RaceTuning.startZ + 2 + Float(j) * 4.5
                b.roundedBox(centre: SIMD3(x, 0.9, zt), half: SIMD3(0.18, 0.9, 0.18), radius: 0.12, color: srgb(0.72, 0.55, 0.45))
                b.roundedBox(centre: SIMD3(x, 2.5, zt), half: SIMD3(1.15, 1.15, 1.15), radius: 1.1, color: greens[(j + (s > 0 ? 1 : 0)) % 4])
            }
        }

        // ---- the sky: one wall behind everything; "glow" so the time of day colours it ----
        b.material = .glow
        b.color = skyDay
        let sky0 = SIMD3<Float>(-200, -2, -64), sky1 = SIMD3<Float>(200, 90, -64)
        b.flatQuad(SIMD3(sky0.x, sky0.y, sky0.z), SIMD3(sky1.x, sky0.y, sky0.z), SIMD3(sky1.x, sky1.y, sky0.z), SIMD3(sky0.x, sky1.y, sky0.z), normal: SIMD3(0, 0, 1),
                   colors: [srgb(0.86, 0.93, 1.0) / 1.8, srgb(0.86, 0.93, 1.0) / 1.8, skyDay, skyDay])
        return b.mesh
    }
}
