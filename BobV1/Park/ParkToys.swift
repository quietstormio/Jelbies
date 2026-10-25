//
//  ParkToys.swift
//  The Park's own toys (2026-10-25): a seesaw (two ride, the plank tilts, timed and squishy), a spring rider (one rides a bouncy bunny on a spring, the others take
//  turns) and a sandbox (up to three sit and dig, sand puffs). They are ordinary DecorKinds (a hop-sit piece in the decor field, so player Jelbies AND visitors use them
//  through the same sit / turn-taking code as the swing), but they are not in any store list and not in any room: `ParkToys.placed` is what `syncDecor` puts in the
//  field while the park is the world. Procedural rounded meshes in the room's toy palette (cream, honey, sky, pink, mint); nothing is rebuilt unless one is in use.
//

import simd
import Foundation

nonisolated enum ParkToys {
    /// Uids well clear of any saved piece. Positions are on the lawn's two flanks so the middle stays clear for the Jelbies.
    static let seesawUID = 9001, riderUID = 9002, sandUID = 9003
    nonisolated(unsafe) static var layout: [PlacedDecor] = [
        PlacedDecor(uid: seesawUID, kind: .seesaw, x: -2.7, z: -2.3, turns: nil),
        PlacedDecor(uid: riderUID, kind: .springrider, x: 2.7, z: 1.2, turns: nil),
        PlacedDecor(uid: sandUID, kind: .sandbox, x: 2.9, z: -1.5, turns: nil),
    ]
    static var placed: [PlacedDecor] { layout }
}

extension DecorKind {
    static let parkOnly: [DecorKind] = [.seesaw, .springrider, .sandbox]
    /// Pieces whose seat is carried by the toy's own motion (the seesaw's plank, the spring rider's bounce).
    var parkRocker: Bool { self == .seesaw || self == .springrider }

    var parkSpec: DecorSpec {
        switch self {
        case .seesaw: return DecorSpec(half: SIMD2(1.05, 0.30), height: 0.55, solid: true, units: 2, corner: 0.2, reach: 1, box: true)
        case .springrider: return DecorSpec(half: SIMD2(0.50, 0.55), height: 0.95, solid: true, units: 1, corner: 0.4, reach: 1, box: true)
        case .sandbox: return DecorSpec(half: SIMD2(1.25, 0.90), height: 0.22, solid: true, units: 3, corner: 0.25, reach: 1, box: true)
        default: return DecorSpec(half: SIMD2(0.4, 0.4), height: 1, solid: true, units: 1, corner: 0.2, reach: 1, box: true)
        }
    }
    var parkSitPoints: [SIMD3<Float>] {
        switch self {
        case .seesaw: return [SIMD3(-0.70, 0.42, 0), SIMD3(0.70, 0.42, 0)]
        case .springrider: return [SIMD3(0, 0.66, -0.02)]
        case .sandbox: return [SIMD3(-0.66, 0.16, -0.22), SIMD3(0.66, 0.16, -0.22), SIMD3(0, 0.16, 0.42)]
        default: return []
        }
    }
    var parkTitle: String {
        switch self { case .seesaw: return "Seesaw"; case .springrider: return "Spring bunny"; case .sandbox: return "Sandbox"; default: return rawValue.capitalized }
    }
    var parkUse: String {
        switch self {
        case .seesaw: return "A Park seesaw. Two Jelbies ride it up and down."
        case .springrider: return "A Park spring bunny. One rides, the others take turns."
        case .sandbox: return "A Park sandbox. Up to three sit and dig."
        default: return ""
        }
    }
}

extension DecorModels {
    // seesaw: plank pivot and swing; spring rider: base of the spring and the bounce
    static let seesawPivotY: Float = 0.34
    static func seesawAngle(_ a: DecorAnim) -> Float { 0.26 * sinf(2 * .pi * a.rockT / 1.7) * min(a.rockAmp, 1) }
    static let springBase = SIMD3<Float>(0, 0.20, 0)
    /// Fore-and-aft rock about the spring's foot; the seat also drops and rises with the spring's squash.
    static func springAngle(_ a: DecorAnim) -> Float { 0.20 * sinf(2 * .pi * a.rockT / 1.2) * min(a.rockAmp, 1) }
    static func springSquash(_ a: DecorAnim) -> Float { 0.10 * min(a.rockAmp, 1) * (0.5 - 0.5 * cosf(2 * .pi * 2 * a.rockT / 1.2)) + 0.05 * a.sink }

    static func parkSeatPoint(_ kind: DecorKind, seat: Int, anim a: DecorAnim) -> SIMD3<Float> {
        let sp = kind.sitPoints[min(seat, kind.sitPoints.count - 1)], k = kind.scale
        switch kind {
        case .seesaw:
            let th = seesawAngle(a), py = seesawPivotY * k
            return SIMD3(sp.x * cosf(th), py + (sp.y - py) * cosf(th) + sp.x * sinf(th), sp.z)
        case .springrider:
            let q = simd_quatf(angle: springAngle(a), axis: SIMD3(1, 0, 0)), base = springBase * k
            let p = base + q.act(sp - base)
            return SIMD3(p.x, base.y + (p.y - base.y) * (1 - springSquash(a)), p.z)
        default: return SIMD3(sp.x, sp.y - 0.03 * a.sink, sp.z)
        }
    }

    // MARK: meshes

    private static let wood = hex2(0xF2C46B), plank = hex2(0xF9CC59), padA = hex2(0xE98AA4), padB = hex2(0x6EB3D1), post = hex2(0xF7F0E0)
    private static let sandC = hex2(0xF0DDB0), bunny = hex2(0xF7F0E0), saddle = hex2(0xE98AA4), mintC = hex2(0x9FD9B0)
    private static func hex2(_ v: UInt32) -> SIMD3<Float> {
        OKLab.srgbToLinear(SIMD3(Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255))
    }

    static func addParkToy(_ kind: DecorKind, at p: SIMD2<Float>, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) {
        typealias S = ParkShapes
        let o = SIMD3<Float>(p.x, 0, p.y), first0 = b.mesh.vertices.count, k0 = kind.scale
        func rbox(_ c: SIMD3<Float>, _ h: SIMD3<Float>, _ r: Float, _ col: SIMD3<Float>) { b.roundedBox(centre: o + c, half: h, radius: r, segments: 3, aoFloor: false, color: col) }
        switch kind {
        case .seesaw:
            // two chunky rounded feet, a fat fulcrum, a tilting plank with a pad and a grip at each end, rubber bumpers on the ground
            rbox(SIMD3(0, 0.10, -0.2), SIMD3(0.20, 0.10, 0.10), 0.09, post)
            rbox(SIMD3(0, 0.10, 0.2), SIMD3(0.20, 0.10, 0.10), 0.09, post)
            rbox(SIMD3(0, 0.25, 0), SIMD3(0.14, 0.15, 0.14), 0.12, post)
            let th = seesawAngle(a), q = simd_quatf(angle: th, axis: SIMD3(0, 0, 1)), pv = SIMD3<Float>(0, seesawPivotY, 0)
            func on(_ v: SIMD3<Float>) -> SIMD3<Float> { pv + q.act(v) }
            // plank as a rotated rounded box: build it unrotated then rotate its vertices
            let v0 = b.mesh.vertices.count
            func addRot(_ c: SIMD3<Float>, _ h: SIMD3<Float>, _ r: Float, _ col: SIMD3<Float>) {
                let first = b.mesh.vertices.count
                b.roundedBox(centre: c, half: h, radius: r, segments: 3, aoFloor: false, color: col)
                for i in first..<b.mesh.vertices.count {
                    let pp = b.mesh.vertices[i].pos, n = b.mesh.vertices[i].normal
                    let rp = pv + q.act(SIMD3(pp.x, pp.y, pp.z) - pv), rn = q.act(SIMD3(n.x, n.y, n.z))
                    b.mesh.vertices[i].pos = SIMD4(rp + o, pp.w); b.mesh.vertices[i].normal = SIMD4(rn, n.w)
                }
            }
            _ = on; _ = v0
            addRot(SIMD3(0, pv.y + 0.02, 0), SIMD3(0.98, 0.055, 0.19), 0.05, plank)
            for sx: Float in [-1, 1] {
                let squash = 1 - 0.18 * max(0, -sx * sinf(th) * 3.2)          // the low end's pad squishes
                addRot(SIMD3(sx * 0.70, pv.y + 0.09, 0), SIMD3(0.24, 0.045 * squash, 0.17), 0.045, sx < 0 ? padA : padB)
                addRot(SIMD3(sx * 0.46, pv.y + 0.22, 0.12), SIMD3(0.025, 0.07, 0.025), 0.02, post)
                // bumper on the ground under the end
                S.blob(b, o + SIMD3(sx * 0.98, 0.07, 0), rx: 0.11, ry: 0.07, rz: 0.11, color: padA * 0.9, segments: 10, rings: 5, ao: 0.9)
            }
        case .springrider:
            // flat round base, a stack of chunky spring rings, and a puffy bunny that rocks on top
            S.cylinder(b, x: o.x, z: o.z, r: 0.34, y0: 0, y1: 0.07, color: mintC)
            S.blob(b, o + SIMD3(0, 0.07, 0), rx: 0.34, ry: 0.05, rz: 0.34, color: mintC, segments: 16, rings: 4)
            let sq = springSquash(a), th = springAngle(a), q = simd_quatf(angle: th, axis: SIMD3(1, 0, 0))
            let base = springBase
            func pose(_ v: SIMD3<Float>) -> SIMD3<Float> {
                let r = base + q.act(v - base)
                return SIMD3(r.x, base.y + (r.y - base.y) * (1 - sq), r.z)
            }
            for k in 0..<5 {
                let t = Float(k) / 4
                let c = pose(SIMD3(0, 0.12 + t * 0.20, 0))
                S.blob(b, o + c, rx: 0.15, ry: 0.035, rz: 0.15, color: post * (k % 2 == 0 ? 1 : 0.82), segments: 12, rings: 3, ao: 0.85)
            }
            func part(_ c: SIMD3<Float>, _ rx: Float, _ ry: Float, _ rz: Float, _ col: SIMD3<Float>) {
                S.blob(b, o + pose(c), rx: rx, ry: ry, rz: rz, color: col, segments: 14, rings: 7, ao: 0.95)
            }
            part(SIMD3(0, 0.55, -0.02), 0.40, 0.30, 0.44, bunny)           // body
            part(SIMD3(0, 0.66, 0.36), 0.26, 0.24, 0.24, bunny)            // head toward the camera
            part(SIMD3(-0.12, 0.98, 0.34), 0.07, 0.19, 0.06, bunny)        // ears
            part(SIMD3(0.12, 0.98, 0.34), 0.07, 0.19, 0.06, bunny)
            part(SIMD3(-0.12, 0.98, 0.37), 0.04, 0.14, 0.03, padA)
            part(SIMD3(0.12, 0.98, 0.37), 0.04, 0.14, 0.03, padA)
            part(SIMD3(0, 0.62, 0.58), 0.05, 0.04, 0.04, padA)             // nose
            part(SIMD3(-0.09, 0.72, 0.55), 0.025, 0.03, 0.02, ink)
            part(SIMD3(0.09, 0.72, 0.55), 0.025, 0.03, 0.02, ink)
            part(SIMD3(0, 0.45, -0.34), 0.10, 0.10, 0.09, post)            // tail
            part(SIMD3(0, 0.58, -0.02), 0.28, 0.08, 0.30, saddle)          // saddle
        case .sandbox:
            // a low rounded frame, soft sand with a gentle mound, a bucket and a spade
            let h = SIMD3<Float>(1.25, 0.11, 0.90)
            rbox(SIMD3(0, 0.11, -h.z + 0.09), SIMD3(h.x, 0.11, 0.09), 0.08, wood)
            rbox(SIMD3(0, 0.11, h.z - 0.09), SIMD3(h.x, 0.11, 0.09), 0.08, wood)
            rbox(SIMD3(-h.x + 0.09, 0.11, 0), SIMD3(0.09, 0.11, h.z - 0.17), 0.08, wood)
            rbox(SIMD3(h.x - 0.09, 0.11, 0), SIMD3(0.09, 0.11, h.z - 0.17), 0.08, wood)
            b.roundedBox(centre: o + SIMD3(0, 0.07, 0), half: SIMD3(h.x - 0.12, 0.07, h.z - 0.12), radius: 0.06, segments: 3, aoFloor: false, color: sandC)
            S.blob(b, o + SIMD3(-0.05, 0.14, -0.55), rx: 0.38, ry: 0.07, rz: 0.2, color: sandC * 1.06, segments: 12, rings: 4)
            // bucket (pink, tapered) and a spade
            b.lathe(cx: o.x + 0.95, cz: o.z + 0.45, profile: [PP(r: 0.0, y: 0.14, nr: 0, ny: -1), PP(r: 0.12, y: 0.14, nr: 1, ny: 0), PP(r: 0.16, y: 0.38, nr: 1, ny: 0), PP(r: 0.0, y: 0.38, nr: 0, ny: 1)], segments: 14, color: padA)
            rbox(SIMD3(-0.95, 0.17, 0.5), SIMD3(0.035, 0.015, 0.20), 0.012, padB)
            rbox(SIMD3(-0.95, 0.17, 0.74), SIMD3(0.08, 0.015, 0.07), 0.012, padB)
            // sand puffs at every seated Jelbie's hands
            let seats = (DecorField.shared.seatOccupant[uid] ?? [:]).keys
            if a.rockAmp > 0.05, !seats.isEmpty {
                for s in seats {
                    let sp = kind.sitPoints[min(s, 2)] / k0
                    for i in 0..<4 {
                        let f = (time * 1.4 + Float(i) / 4 + Float(s) * 0.31).truncatingRemainder(dividingBy: 1)
                        let sd: Float = i % 2 == 0 ? -1 : 1
                        let c = o + SIMD3(sp.x + sd * (0.30 + 0.28 * f), 0.22 + 0.50 * f * (1.2 - f), sp.z + 0.32 + 0.05 * Float(i))
                        S.ball(b, c, 0.075 * (1 - f) * min(a.rockAmp, 1) + 0.01, sandC * 1.05, segments: 7, rings: 4)
                    }
                }
            }
        default: break
        }
        // the pieces are modelled at 1x about their centre and drawn at `kind.scale`
        for i in first0..<b.mesh.vertices.count {
            let q = b.mesh.vertices[i].pos
            b.mesh.vertices[i].pos = SIMD4(o.x + (q.x - o.x) * k0, q.y * k0, o.z + (q.z - o.z) * k0, q.w)
        }
    }
    private typealias PP = RoomMeshBuilder.ProfilePoint
}
