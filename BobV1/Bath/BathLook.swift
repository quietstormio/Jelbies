//
//  BathLook.swift
//  What the clean-up does to Bob's look. The flow writes it every frame; the renderer reads it (`renderer.bathLook`).
//  Pure value type, no UI: foam is a direction grid in the body's REST frame, so suds stick when he squishes.
//
//  Frames: every `local` / `dir` here is relative to `BathLook.centre`, the body ellipsoid's centre in the rest frame
//  (TouchPlay's `hitLocal` is relative to the rest centroid, y = 0.636 above the floor; the render worker samples the grid from
//  BathSet.bodyCentre = (0, H/2, 0) in floor-based rest space, which is `centre` below in the hit frame).
//  Grid: row = polar angle from +y (0 = top ... rows-1 = bottom), col = azimuth around +y, col 0 at +z, increasing toward +x.
//

import simd
import Foundation

enum LintKind: UInt8 { case dust, crumb, leaf, glitter, fuzz, drop }

struct LintBit: Equatable {
    var kind: LintKind
    var dir: SIMD3<Float>      // body-local REST-frame direction from body centre (where it sticks)
    var spin: Float            // radians around the surface normal
    var size: Float            // world units, ~0.06-0.14
    var peel: Float = 0        // 0 stuck ... 1 gone (renderer lifts/curls it off)
}

enum BathTool: UInt8 { case none, roller, soap, rinse, shine }

/// What the bath does to Bob's look. Flow writes it every frame; the renderer reads it.
struct BathLook: Equatable {
    static let rows = 12, cols = 24          // direction grid: row = polar angle from +y (0 top ... rows-1 bottom), col = azimuth around +y, col 0 at +z, increasing toward +x
    /// The grid's centre in the hit frame (rest centroid + this = ellipsoid centre).
    static let centre = SIMD3<Float>(0, 1.35 * 0.5 - 0.636, 0)      // H / 2 above the floor, minus the rest centroid's height
    /// Angular reach per world unit of brush radius (the body is ~0.65 across).
    static let radiansPerUnit: Float = 1 / 0.65

    var foam: [Float] = Array(repeating: 0, count: rows * cols)   // 0...1 suds per cell, body-local rest frame
    var wet: Float = 0
    var sparkle: Float = 0
    var visible: Bool = false
    var spray: SIMD3<Float>? = nil
    var bubbles: [SIMD4<Float>] = []          // <= 48
    var lint: [LintBit] = []                  // <= 10; drawn on Bob in the room AND the bath
    var tool: BathTool = .none
    var toolAt: SIMD3<Float>? = nil           // world point where the held tool mesh is drawn (roller / soap bar / cloth); rinse still uses `spray`
    static let dry = BathLook()
    static let maxBubbles = 48, maxLint = 10

    // MARK: grid

    private static func unit(_ d: SIMD3<Float>) -> SIMD3<Float> {
        let l = simd_length(d)
        return l > 1e-6 ? d / l : SIMD3(0, 0, 1)
    }

    /// Cell index (row * cols + col) of a direction.
    static func cell(for dir: SIMD3<Float>) -> Int {
        let d = unit(dir)
        let polar = acosf(max(-1, min(1, d.y)))
        let row = min(rows - 1, max(0, Int(polar / .pi * Float(rows))))
        var az = atan2f(d.x, d.z); if az < 0 { az += 2 * .pi }
        let col = min(cols - 1, Int(az / (2 * .pi) * Float(cols)) % cols)
        return row * cols + col
    }

    /// Unit direction of a cell's centre.
    static func direction(ofCell i: Int) -> SIMD3<Float> {
        let row = i / cols, col = i % cols
        let polar = (Float(row) + 0.5) / Float(rows) * .pi
        let az = (Float(col) + 0.5) / Float(cols) * 2 * .pi
        return SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az))
    }
    private static let centres: [SIMD3<Float>] = (0..<(rows * cols)).map { direction(ofCell: $0) }

    /// Coverage definition: the cells he shows the camera. Rows 0 ... rows-3 (the bottom two rows are the base, never seen) whose centre is in
    /// the front hemisphere the camera can reach (z > 0.15), weighted by the cell's solid angle (sin of the polar angle).
    private static let coverageCells: [(Int, Float)] = (0..<(rows * cols)).compactMap { i in
        let c = centres[i]
        guard i / cols < rows - 2, c.z > 0.15 else { return nil }
        return (i, sqrtf(max(0, 1 - c.y * c.y)))
    }
    private static let coverageWeight: Float = coverageCells.reduce(0) { $0 + $1.1 }

    func foamAt(_ dir: SIMD3<Float>) -> Float { foam[Self.cell(for: dir)] }

    /// Smooth falloff weight (1 at the centre, 0 at the angular radius).
    private static func weight(_ cellDir: SIMD3<Float>, _ d: SIMD3<Float>, reach: Float) -> Float {
        let a = acosf(max(-1, min(1, simd_dot(cellDir, d))))
        guard a < reach else { return 0 }
        let k = 1 - a / reach
        return k * k * (3 - 2 * k)
    }

    /// Foam appears around `local` (a body-local point; only its direction counts). `radius` in world units, `amount` 0...1 at the centre.
    mutating func paint(local: SIMD3<Float>, radius: Float, amount: Float) {
        guard amount > 0 else { return }
        let d = Self.unit(local - Self.centre), reach = max(radius, 0.01) * Self.radiansPerUnit
        for i in 0..<foam.count {
            let w = Self.weight(Self.centres[i], d, reach: reach)
            if w > 0 { foam[i] = min(1, foam[i] + amount * w) }
        }
    }

    /// The same, washing foam away.
    mutating func rinse(local: SIMD3<Float>, radius: Float, amount: Float) {
        guard amount > 0 else { return }
        let d = Self.unit(local - Self.centre), reach = max(radius, 0.01) * Self.radiansPerUnit
        for i in 0..<foam.count {
            let w = Self.weight(Self.centres[i], d, reach: reach)
            if w > 0 { foam[i] = max(0, foam[i] - amount * w) }
        }
    }

    /// Mean suds over the cells he presents to the camera (see `coverageCells`), 0...1.
    var coverage: Float {
        var s: Float = 0
        for (i, w) in Self.coverageCells { s += foam[i] * w }
        return s / Self.coverageWeight
    }

    /// Angle (rad) between a lint bit and a hit point (both directions from the body centre).
    static func angle(_ a: SIMD3<Float>, hit local: SIMD3<Float>) -> Float {
        acosf(max(-1, min(1, simd_dot(unit(a), unit(local - centre)))))
    }
}
