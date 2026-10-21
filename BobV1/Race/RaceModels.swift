//
//  RaceModels.swift
//  The Waddle Sprint track as a RoomMesh (the room renderer draws it instead of the living room while `raceVisible`): grass in mown stripes, a clay
//  running track with three lanes (white lane lines, a start line, a checkered finish line), a finish gantry with a checkered banner, bushes along
//  the sides, far hills and a sky wall. Materials: plain for everything lit; "glow" (the window pane) for the sky, so the day / night sky colours
//  of DayLight reach it for free. All colours are pastel and linear.
//
//  The track follows a RaceCourse (Race/RaceCourse.swift): the clay, the lane bands, the lines and the curbs are ribbons sampled along the
//  centreline; the start line is at arc length 0, the finish checkers and the gantry at the end (every course finishes facing +z, so the gantry's
//  boxes stay axis-aligned). The Puddle is the straight along z from RaceTuning.startZ to finishZ, as it always was. Scenery is kept off the clay:
//  a bush or a tree that would land on another part of a winding course is left out.
//

import simd
import Foundation

enum RaceModels {
    /// Half width of the clay strip (three lanes + a margin).
    static let trackHalfW: Float = 2.7
    static let gantryX: Float = 2.95
    static let gantryHeight: Float = 3.5
    /// Sampling step (arc length) of the ribbons.
    static let ribbonStep: Float = 0.25
    /// The clay runs this far before the start line and past the finish.
    static let before: Float = 2.2, after: Float = 6

    static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }

    // pastel palette
    static let grassA = srgb(0.60, 0.82, 0.50), grassB = srgb(0.54, 0.77, 0.45)
    static let clay = srgb(0.93, 0.66, 0.55), clayDark = srgb(0.88, 0.60, 0.50)
    static let white = srgb(0.99, 0.98, 0.95), ink = srgb(0.28, 0.24, 0.30)
    static let banner = srgb(0.96, 0.58, 0.68), post = srgb(0.99, 0.95, 0.88)
    static let curb = srgb(0.97, 0.80, 0.78)
    /// The sky pane is lit x1.25 x up to 1.5 by the room shader, so its albedo is the target blue divided by that.
    static let skyDay = srgb(0.62, 0.80, 0.98) / 1.8
    static let skyLow = srgb(0.86, 0.93, 1.0) / 1.8
    /// The room shader's ambient / fog swatches for the outdoors: pal2 = ground bounce, pal3 = haze toward the horizon, pal4 = sky light.
    static let swatch2 = srgb(0.52, 0.74, 0.44), swatch3 = srgb(0.86, 0.93, 1.0) / 0.62, swatch4 = srgb(0.74, 0.86, 1.0)
    static let greens = [srgb(0.46, 0.72, 0.42), srgb(0.52, 0.78, 0.46), srgb(0.40, 0.66, 0.40), srgb(0.58, 0.80, 0.50)]

    static func build() -> RoomMesh { build(course: .puddle) }

    static func build(course c: RaceCourse) -> RoomMesh {
        let b = RoomMeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        let bb = c.bounds(margin: 12)
        let z0 = min(-70, bb.min.y - 20) as Float, z1 = max(40, bb.max.y + 20) as Float, xw = max(60, max(-bb.min.x, bb.max.x) + 20) as Float
        let s0 = -before, s1 = c.length + after
        func p3(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3(p.x, y, p.y) }
        /// A ribbon between offsets `a` and `b` (right of the centreline) from arc `from` to `to`, at height `y`.
        func ribbon(_ a: Float, _ bOff: Float, from: Float, to: Float, y: Float, color: SIMD3<Float>) {
            b.color = color
            var s = from
            while s < to - 1e-4 {
                let e = min(s + ribbonStep, to)
                let q0 = c.pose(at: s), q1 = c.pose(at: e)
                let r0 = RaceCourse.right(q0.heading), r1 = RaceCourse.right(q1.heading)
                b.flatQuad(p3(q0.pos + r0 * a, y), p3(q1.pos + r1 * a, y), p3(q1.pos + r1 * bOff, y), p3(q0.pos + r0 * bOff, y), normal: up)
                s = e
            }
        }
        /// A patch across the track: offsets `a`...`bOff`, arcs `from`...`to` (one quad).
        func patch(_ a: Float, _ bOff: Float, from: Float, to: Float, y: Float, color: SIMD3<Float>) {
            b.color = color
            let q0 = c.pose(at: from), q1 = c.pose(at: to)
            let r0 = RaceCourse.right(q0.heading), r1 = RaceCourse.right(q1.heading)
            b.flatQuad(p3(q0.pos + r0 * a, y), p3(q1.pos + r1 * a, y), p3(q1.pos + r1 * bOff, y), p3(q0.pos + r0 * bOff, y), normal: up)
        }
        let spine = c.polyline(from: s0, to: s1, step: 0.5)
        /// The scenery stays off the clay: true when `p` is at least `clear` from every part of the track.
        func offTrack(_ p: SIMD2<Float>, clear: Float) -> Bool { spine.allSatisfy { simd_distance($0, p) > trackHalfW + clear } }

        // ---- grass: mown stripes across the whole field (a strong depth cue) ----
        b.material = .plain
        var z = z0
        var k = 0
        let tb = c.bounds(margin: 0)
        let tz0 = tb.min.y - before, tz1 = tb.max.y + after
        while z < z1 {
            let step: Float = z > tz0 - 4 && z < tz1 + 4 ? 1.5 : 8
            b.color = k % 2 == 0 ? grassA : grassB
            b.flatQuad(SIMD3(-xw, 0, z), SIMD3(-xw, 0, min(z + step, z1)), SIMD3(xw, 0, min(z + step, z1)), SIMD3(xw, 0, z), normal: up)
            z += step; k += 1
        }

        // ---- the clay strip ----
        let y1: Float = 0.006, y2: Float = 0.012, y3: Float = 0.018
        ribbon(-trackHalfW, trackHalfW, from: s0, to: s1, y: y1, color: clay)
        // darker bands (every other lane) so the lanes read
        for lane in [0, 2] {
            let cx = RaceTuning.laneX(lane), hw = RaceTuning.laneSpacing / 2
            ribbon(cx - hw, cx + hw, from: s0, to: s1, y: y2, color: clayDark)
        }
        // curbs along both edges on a winding course (a thin pink-white rim)
        if !c.isStraight {
            ribbon(-trackHalfW - 0.16, -trackHalfW + 0.02, from: s0, to: s1, y: y2, color: curb)
            ribbon(trackHalfW - 0.02, trackHalfW + 0.16, from: s0, to: s1, y: y2, color: curb)
        }

        // ---- white lines: lane lines, track edges, the start line ----
        let lw: Float = 0.07
        for k in 0..<4 { let x = (Float(k) - 1.5) * RaceTuning.laneSpacing
            ribbon(x - lw, x + lw, from: s0, to: s1, y: y3, color: white)
        }
        let ss: Float = 0.45
        let tw = RaceTuning.laneSpacing * 1.5 + lw
        patch(-tw, tw, from: ss - 0.1, to: ss + 0.1, y: y3, color: white)

        // ---- the finish line: two rows of checkers across the track ----
        let fs = c.length
        let cell: Float = 0.30, cols = Int((2 * tw / cell).rounded())
        for row in 0..<2 {
            for col in 0..<cols {
                let x0 = -tw + Float(col) * cell, sz = fs - cell + Float(row) * cell
                patch(x0, x0 + cell, from: sz, to: sz + cell, y: y3, color: (col + row) % 2 == 0 ? ink : white)
            }
        }

        // ---- the finish gantry: two posts and a checkered banner (the finish faces +z on every course, so the boxes are axis-aligned) ----
        let fp = c.pose(at: fs).pos
        let fx = fp.x, fz = fp.y
        b.color = post
        for s in [Float(-1), 1] {
            b.roundedBox(centre: SIMD3(fx + s * gantryX, gantryHeight / 2, fz), half: SIMD3(0.13, gantryHeight / 2, 0.13), radius: 0.1, color: post)
            b.roundedBox(centre: SIMD3(fx + s * gantryX, 0.12, fz), half: SIMD3(0.32, 0.12, 0.32), radius: 0.1, color: banner)
        }
        b.roundedBox(centre: SIMD3(fx, gantryHeight + 0.05, fz), half: SIMD3(gantryX + 0.2, 0.34, 0.1), radius: 0.12, color: banner)
        // checkers on the banner's near face
        let bcell: Float = 0.2, bcols = Int(((gantryX + 0.12) * 2 / bcell).rounded())
        let bn = SIMD3<Float>(0, 0, 1)
        for row in 0..<3 {
            for col in 0..<bcols where (col + row) % 2 == 0 {
                b.color = white
                let x0 = fx - (gantryX + 0.12) + Float(col) * bcell, y0 = gantryHeight - 0.2 + Float(row) * bcell
                let zf = fz + 0.105
                b.flatQuad(SIMD3(x0, y0, zf), SIMD3(x0 + bcell, y0, zf), SIMD3(x0 + bcell, y0 + bcell, zf), SIMD3(x0, y0 + bcell, zf), normal: bn)
            }
        }

        // ---- bushes along both sides, hills far behind, a few trees ----
        var rng = RaceRNG(seed: 77)
        for side in [Float(-1), 1] {
            var sb = s0 - 4
            while sb < s1 {
                let w = rng.range(0.5, 0.9), h = rng.range(0.4, 0.75)
                let off = side * (4.3 + rng.range(0, 0.8))
                let col = greens[Int(rng.next() * 4) % 4]
                let q = c.pose(at: sb)
                let p = q.pos + RaceCourse.right(q.heading) * off
                if c.isStraight || offTrack(p, clear: w + 0.3) { b.roundedBox(centre: SIMD3(p.x, h * 0.8, p.y), half: SIMD3(w, h, w * 1.2), radius: min(w, h) * 0.9, color: col) }
                sb += rng.range(1.3, 2.2)
            }
        }
        for i in 0..<9 {
            let x = (Float(i) - 4) * 11 + rng.range(-3, 3)
            b.roundedBox(centre: SIMD3(x, 0.9, -50 - rng.range(0, 5)), half: SIMD3(rng.range(6, 9), rng.range(1.6, 2.6), rng.range(3, 5)), radius: 1.6, color: greens[i % 4])
        }
        for side in [Float(-1), 1] {
            for j in 0..<3 {                                   // round trees beside the track
                let q = c.pose(at: 2 + Float(j) * 4.5)
                let p = q.pos + RaceCourse.right(q.heading) * (side * (6.8 + Float(j) * 3.2))
                guard c.isStraight || offTrack(p, clear: 1.4) else { continue }
                b.roundedBox(centre: SIMD3(p.x, 0.9, p.y), half: SIMD3(0.18, 0.9, 0.18), radius: 0.12, color: srgb(0.72, 0.55, 0.45))
                b.roundedBox(centre: SIMD3(p.x, 2.5, p.y), half: SIMD3(1.15, 1.15, 1.15), radius: 1.1, color: greens[(j + (side > 0 ? 1 : 0)) % 4])
            }
        }
        if !c.isStraight {
            // a winding course is seen from every side: more trees around it (off the clay), and hills on the other three horizons
            let mid = (bb.min + bb.max) * 0.5
            for i in 0..<14 {
                let ang = Float(i) / 14 * 2 * .pi + rng.range(-0.15, 0.15)
                let rad = max(bb.max.x - bb.min.x, bb.max.y - bb.min.y) * 0.5 + rng.range(2, 7)
                let p = mid + SIMD2(cosf(ang), sinf(ang)) * rad
                guard offTrack(p, clear: 1.6) else { continue }
                let hgt = rng.range(0.8, 1.1)
                b.roundedBox(centre: SIMD3(p.x, hgt, p.y), half: SIMD3(0.18, hgt, 0.18), radius: 0.12, color: srgb(0.72, 0.55, 0.45))
                b.roundedBox(centre: SIMD3(p.x, hgt * 2 + 0.7, p.y), half: SIMD3(repeating: rng.range(1.0, 1.3)), radius: 1.1, color: greens[i % 4])
            }
            for i in 0..<9 {
                let t = (Float(i) - 4) * 11 + rng.range(-3, 3)
                b.roundedBox(centre: SIMD3(t, 0.9, z1 + 10 + rng.range(0, 5)), half: SIMD3(rng.range(6, 9), rng.range(1.6, 2.6), rng.range(3, 5)), radius: 1.6, color: greens[i % 4])
                b.roundedBox(centre: SIMD3(-xw - 10 - rng.range(0, 5), 0.9, t + mid.y), half: SIMD3(rng.range(3, 5), rng.range(1.6, 2.6), rng.range(6, 9)), radius: 1.6, color: greens[(i + 1) % 4])
                b.roundedBox(centre: SIMD3(xw + 10 + rng.range(0, 5), 0.9, t + mid.y), half: SIMD3(rng.range(3, 5), rng.range(1.6, 2.6), rng.range(6, 9)), radius: 1.6, color: greens[(i + 2) % 4])
            }
            // the grass reaches the far hills on every side
            b.color = grassB
            b.flatQuad(SIMD3(-xw - 40, -0.002, z0 - 40), SIMD3(-xw - 40, -0.002, z1 + 40), SIMD3(xw + 40, -0.002, z1 + 40), SIMD3(xw + 40, -0.002, z0 - 40), normal: up)
        }

        // ---- the sky: one wall behind everything (and, round a winding course, the other three sides); "glow" so the time of day colours it ----
        b.material = .glow
        b.color = skyDay
        let sky0 = SIMD3<Float>(-200, -2, -64), sky1 = SIMD3<Float>(200, 90, -64)
        b.flatQuad(SIMD3(sky0.x, sky0.y, sky0.z), SIMD3(sky1.x, sky0.y, sky0.z), SIMD3(sky1.x, sky1.y, sky0.z), SIMD3(sky0.x, sky1.y, sky0.z), normal: SIMD3(0, 0, 1),
                   colors: [skyLow, skyLow, skyDay, skyDay])
        if !c.isStraight {
            let far = max(xw + 60, 120), zf = max(z1 + 60, 120)
            b.flatQuad(SIMD3(far, -2, zf), SIMD3(-far, -2, zf), SIMD3(-far, 90, zf), SIMD3(far, 90, zf), normal: SIMD3(0, 0, -1), colors: [skyLow, skyLow, skyDay, skyDay])
            b.flatQuad(SIMD3(-far, -2, zf), SIMD3(-far, -2, -200), SIMD3(-far, 90, -200), SIMD3(-far, 90, zf), normal: SIMD3(1, 0, 0), colors: [skyLow, skyLow, skyDay, skyDay])
            b.flatQuad(SIMD3(far, -2, -200), SIMD3(far, -2, zf), SIMD3(far, 90, zf), SIMD3(far, 90, -200), normal: SIMD3(-1, 0, 0), colors: [skyLow, skyLow, skyDay, skyDay])
        }
        return b.mesh
    }
}
