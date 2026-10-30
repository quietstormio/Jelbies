//
//  BathLook.swift
//  What the bath (and the Clean care action) does to Bob's look. Flow writes it every frame; the renderer reads it.
//  CONTRACT FILE: the render worker's copy keeps to this API with simple bodies; the flow worker's copy wins at merge.
//  Directions are measured from the body centre (0, H/2, 0) in the body-local REST frame.
//

import simd

enum LintKind: UInt8 { case dust, crumb, leaf, glitter, fuzz, drop }

struct LintBit: Equatable {
    var kind: LintKind
    var dir: SIMD3<Float>      // body-local REST-frame direction from body centre (where it sticks)
    var spin: Float            // radians around the surface normal
    var size: Float            // world units, ~0.06-0.14
    var peel: Float = 0        // 0 stuck ... 1 gone (renderer lifts/curls it off)
}

enum BathTool: UInt8 { case none, roller, soap, rinse, shine }

struct BathLook: Equatable {
    static let rows = 12, cols = 24          // direction grid: row = polar angle from +y (0 top ... rows-1 bottom), col = azimuth around +y, col 0 at +z, increasing toward +x
    var foam: [Float] = Array(repeating: 0, count: rows * cols)   // 0...1 suds per cell, body-local rest frame
    var wet: Float = 0                        // 0 dry ... 1 dripping
    var sparkle: Float = 0                    // 0 ... 1 glints
    var visible: Bool = false                 // bath set shown, living room hidden
    var spray: SIMD3<Float>? = nil            // world-space nozzle while rinsing, nil = off
    var bubbles: [SIMD4<Float>] = []          // world xyz + radius, <= 48 floating sud bubbles
    var lint: [LintBit] = []                  // <= 10; drawn on Bob in room AND bath
    var tool: BathTool = .none
    var toolAt: SIMD3<Float>? = nil           // world point where the held tool mesh is drawn
    static let dry = BathLook()

    /// Polar / azimuth fractions (0...1) of a direction.
    private static func angles(_ d: SIMD3<Float>) -> (row: Float, col: Float) {
        let l = simd_length(d)
        guard l > 1e-6 else { return (0.5, 0) }
        let pol = acosf(max(-1, min(1, d.y / l)))
        var az = atan2f(d.x, d.z)
        if az < 0 { az += 2 * .pi }
        return (pol / .pi, az / (2 * .pi))
    }

    static func cell(for dir: SIMD3<Float>) -> Int {
        let a = angles(dir)
        let r = min(rows - 1, Int(a.row * Float(rows)))
        let c = min(cols - 1, Int(a.col * Float(cols)))
        return r * cols + c
    }

    func foamAt(_ dir: SIMD3<Float>) -> Float {
        let a = BathLook.angles(dir)
        let fr = a.row * Float(BathLook.rows) - 0.5, fc = a.col * Float(BathLook.cols) - 0.5
        let r0 = Int(floorf(fr)), c0 = Int(floorf(fc))
        let tr = fr - Float(r0), tc = fc - Float(c0)
        func v(_ r: Int, _ c: Int) -> Float {
            let rr = min(max(r, 0), BathLook.rows - 1)
            let cc = ((c % BathLook.cols) + BathLook.cols) % BathLook.cols
            return foam[rr * BathLook.cols + cc]
        }
        let top = v(r0, c0) * (1 - tc) + v(r0, c0 + 1) * tc
        let bot = v(r0 + 1, c0) * (1 - tc) + v(r0 + 1, c0 + 1) * tc
        return top * (1 - tr) + bot * tr
    }

    private static func cellDir(_ i: Int) -> SIMD3<Float> {
        let r = i / cols, c = i % cols
        let pol = (Float(r) + 0.5) / Float(rows) * .pi, az = (Float(c) + 0.5) / Float(cols) * 2 * .pi
        return SIMD3(sinf(pol) * sinf(az), cosf(pol), sinf(pol) * cosf(az))
    }

    private mutating func apply(local: SIMD3<Float>, radius: Float, amount: Float) {
        let d = simd_length(local) > 1e-6 ? simd_normalize(local) : SIMD3<Float>(0, 0, 1)
        let rad = max(radius, 0.02)
        for i in 0..<foam.count {
            let dist = simd_distance(BathLook.cellDir(i), d)
            if dist < rad {
                let w = 1 - dist / rad
                foam[i] = min(1, max(0, foam[i] + amount * w * w * (3 - 2 * w)))
            }
        }
    }
    mutating func paint(local: SIMD3<Float>, radius: Float, amount: Float) { apply(local: local, radius: radius, amount: abs(amount)) }
    mutating func rinse(local: SIMD3<Float>, radius: Float, amount: Float) { apply(local: local, radius: radius, amount: -abs(amount)) }

    var coverage: Float { foam.isEmpty ? 0 : foam.reduce(0, +) / Float(foam.count) }
}
