//
//  ParkToys.swift
//  The Park's own toys (2026-10-25): a seesaw (two ride, the plank tilts, timed and squishy), and a sandbox (up to three sit and dig, sand puffs). They are ordinary DecorKinds (a hop-sit piece in the decor field, so player Jelbies AND visitors use them
//  through the same sit / turn-taking code as the swing), but they are not in any store list and not in any room: `ParkToys.placed` is what `syncDecor` puts in the
//  field while the park is the world. Procedural rounded meshes in the room's toy palette (cream, honey, sky, pink, mint); nothing is rebuilt unless one is in use.
//

import simd
import Foundation

nonisolated enum ParkToys {
    /// Uids well clear of any saved piece. Positions are on the lawn's two flanks so the middle stays clear for the Jelbies.
    static let seesawUID = 9001, hopscotchUID = 9005, slideUID = 9006          // (9003, the park sandbox, was removed 2026-11-05: the slide stands in its place)
    nonisolated(unsafe) static var layout: [PlacedDecor] = [
        // the seesaw on the back left, moved from x -2.7 to -3.2 (2026-11-09: its right pad sat on the path's edge): its right end (footprint half x 1.47) is at -1.73, 0.62 clear of the path's left edge (-1.11 at z -2.3)
        PlacedDecor(uid: seesawUID, kind: .seesaw, x: -3.2, z: -2.3, turns: nil),
        // hopscotch on the left lawn (square 1 at the back, home toward the camera), the room's slide on the right where the sandbox used to be (the sandbox was removed from the park 2026-11-05, and so was the play tunnel)
        PlacedDecor(uid: hopscotchUID, kind: .hopscotch, x: -2.1, z: 1.9, turns: nil),
        PlacedDecor(uid: slideUID, kind: .slide, x: 2.9, z: 1.0, turns: nil)          // (STRAIGHT, on the right lawn where the sandbox was: the chute points down the screen toward the camera. Footprint x 2.1...3.7, z -0.4...2.4, whose back edge is 2.8 clear of the pond (pond (3.5, -4.2) r 1.0): the tall ladder posts at its back would overlap the pond on screen if it stood further back (at z -0.3 they did). The climb spot behind it is z -1.17; the rider lands at z 3.19 on open lawn, well off the path (its right edge is x 1.2 there), and a body there is above the Go home pill's roam cut-out in landscape (HUDLayout.parkHomeRect). The park floor's front edge is back at z 4.5)
    ]
    static var placed: [PlacedDecor] { layout }

    /// The player's own floor toys that come along (up to 3, GameCare+Park.swift): fixed spots in the back corners of the lawn, clear of the path (centre x = 0.7 sin(0.34 z), half width 0.62),
    /// the hopscotch court (x -3.05...-1.15, z -0.75...4.55) and its queue (z about -1.1), the slide (x 2.1...3.7, z -0.4...2.4) and its climb spot (2.9, -1.17), the pond (3.5, -4.2) r 1.0,
    /// the bench, the flower bed and the Go home pill's cut-out (bottom centre). The first is on the left lawn beside the court's far side (the seesaw stands in the back left corner).
    static let ownSpots: [SIMD2<Float>] = [SIMD2(-3.7, 1.9), SIMD2(1.7, -2.8), SIMD2(2.95, -2.65)]
    static let ownUIDBase = 9101
    /// The pieces a Jelbie plays with by himself on the floor, small enough for a spot (a seat, a rolling ball, a booped or kicked toy; not the big ones, the slide or the park-only pieces).
    static func isCarryable(_ k: DecorKind) -> Bool {
        let s = k.spec
        return k.category == .toys && k.activeInteraction != nil && !k.isRetired && !DecorKind.parkOnly.contains(k) && k != .slide && k != .playtunnel && s.units <= 1 && max(s.half.x, s.half.y) <= 0.55
    }
    /// Up to three of the room's placed toys (in placement order), moved to the park's spots with their own uids; the room's list is only read.
    static func ownToys(from room0: [PlacedDecor]) -> [PlacedDecor] {
        var room = room0
        #if targetEnvironment(simulator)
        // capture aid: `-ParkToys kindA,kindB,kindC` brings those toys instead of the save's (any raw value; `list` logs the kinds that travel)
        if let s = UserDefaults.standard.string(forKey: "ParkToys") {
            NSLog("[parktoys] carryable: %@", DecorKind.allCases.filter { isCarryable($0) }.map(\.rawValue).joined(separator: ","))
            room = s.split(separator: ",").enumerated().compactMap { i, n in DecorKind(rawValue: String(n)).map { PlacedDecor(uid: 100 + i, kind: $0, x: 0, z: 0, turns: nil) } }
            return room.prefix(ownSpots.count).enumerated().map { PlacedDecor(uid: ownUIDBase + $0.offset, kind: $0.element.kind, x: ownSpots[$0.offset].x, z: ownSpots[$0.offset].y, turns: nil) }
        }
        #endif
        return room.filter { isCarryable($0.kind) }.prefix(ownSpots.count).enumerated().map { PlacedDecor(uid: ownUIDBase + $0.offset, kind: $0.element.kind, x: ownSpots[$0.offset].x, z: ownSpots[$0.offset].y, turns: nil) }
    }
}

extension DecorKind {
    static let parkOnly: [DecorKind] = [.seesaw, .sandbox, .hopscotch]
    /// Pieces whose seat is carried by the toy's own motion (the seesaw's plank, the spring rider's bounce).
    var parkRocker: Bool { self == .seesaw }

    var parkSpec: DecorSpec {
        switch self {
        case .seesaw: return DecorSpec(half: SIMD2(1.05, 0.28), height: 0.55, solid: true, units: 2, corner: 0.2, reach: 1, box: true)
        case .sandbox: return DecorSpec(half: SIMD2(1.25, 0.90), height: 0.22, solid: true, units: 3, corner: 0.25, reach: 1, box: true)
        case .hopscotch: return DecorSpec(half: HopscotchCourt.slabHalf, height: 0.05, solid: false, units: 3, corner: 0.1, reach: 0.5, box: true)
        default: return DecorSpec(half: SIMD2(0.4, 0.4), height: 1, solid: true, units: 1, corner: 0.2, reach: 1, box: true)
        }
    }
    var parkSitPoints: [SIMD3<Float>] {
        switch self {
        case .seesaw: return [SIMD3(-0.66, 0.475, 0), SIMD3(0.66, 0.475, 0)]          // (the cushion's flat top, 0.475: the beam's top 0.345, the hinge 0.3775 and the pad's underside 0.41 under it; they SIT on it now, see Park/SeesawRide.swift; the footprint's half depth 0.28 x 1.4 = 0.392 covers the base's axle caps (|z| 0.272 x 1.4 = 0.381) and the stand spot in front is 0.81 from the seat, 0.31 clear of the cushion's edge for a body of radius 0.5)
        case .sandbox: return [SIMD3(-0.72, 0.16, -0.25), SIMD3(0.72, 0.16, -0.25), SIMD3(0, 0.16, 0.45)]          // (three bodies of ~1.0 stand in a triangle with >1.1 between centres)
        default: return []
        }
    }
    var parkTitle: String {
        switch self { case .seesaw: return "Seesaw"; case .sandbox: return "Sandbox"; case .hopscotch: return "Hopscotch"; default: return rawValue.capitalized }
    }
    var parkUse: String {
        switch self {
        case .seesaw: return "A Park seesaw. Two Jelbies sit on it and ride up and down."
        case .sandbox: return "A Park sandbox. Up to three stand in it and dig."
        case .hopscotch: return "A Park hopscotch court. Short legs, so they hop square to square, and friends line up behind."
        default: return ""
        }
    }
}

extension DecorModels {
    // seesaw: plank pivot and swing; spring rider: base of the spring and the bounce
    static let seesawPivotY: Float = SeesawTuning.pivotY
    // (the plank's angle and the seats' frame: Park/SeesawRide.swift)

    // MARK: meshes

    private static let wood = hex2(0x7A5634), plank = hex2(0x8A5E36), padA = hex2(0xA8372A), padB = hex2(0x35607F), post = hex2(0x2B3430)
    private static let sandC = hex2(0xC9B183)
    private static func hex2(_ v: UInt32) -> SIMD3<Float> {
        OKLab.srgbToLinear(SIMD3(Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255))
    }

    static func addParkToy(_ kind: DecorKind, at p: SIMD2<Float>, anim a: DecorAnim, time: Float, uid: Int, into b: RoomMeshBuilder) {
        typealias S = ParkShapes
        let o = SIMD3<Float>(p.x, 0, p.y), first0 = b.mesh.vertices.count, k0 = kind.scale
        func rbox(_ c: SIMD3<Float>, _ h: SIMD3<Float>, _ r: Float, _ col: SIMD3<Float>) { b.roundedBox(centre: o + c, half: h, radius: r, segments: 3, aoFloor: false, color: col) }
        switch kind {
        case .seesaw:
            // the baked model (decor_seesaw.bin, already at the piece's scale: DecorMeshes.loaded scales positions and pivots), contract v2: the base as it is, the plank turned by theta about its
            // pivot on z, each seat (seatL / seatR) only TRANSLATED by what its hinge point travels with the plank and never turned (so it stays level), and a rubber bumper under each end
            // scaled in height about its floor pivot so its top follows the plank's underside. The angle is the one the riders were placed with in this step (`drawnTheta`).
            // An art file of the old contract (no seat parts, another plank pivot) falls through to the procedural piece below.
            if let art = DecorMeshes.loaded[.seesaw], let base = art.part("base"), let plankPart = art.part("plank"), let bl = art.part("bumperL"), let br = art.part("bumperR"),
               let seatL = art.part("seatL"), let seatR = art.part("seatR"), abs(plankPart.pivot.y - SeesawTuning.pivotY * k0) < 0.004 {
                let th = SeesawRide.shared.drawnTheta(uid), q = simd_quatf(angle: th, axis: SIMD3(0, 0, 1)), pv = plankPart.pivot
                DecorMeshes.emit(base, into: b, offset: o)
                DecorMeshes.emit(plankPart, into: b, offset: o, pose: { v, n, _ in (pv + q.act(v - pv), q.act(n)) })
                for seat in [seatL, seatR] {
                    let h = seat.pivot - pv, d = q.act(h) - h
                    DecorMeshes.emit(seat, into: b, offset: o, pose: { v, n, _ in (v + d, n) })
                }
                for (part, sx) in [(bl, Float(-1)), (br, Float(1))] {
                    let sy = SeesawTuning.bumperTop(side: sx, theta: th) / SeesawTuning.bumperRest
                    DecorMeshes.emit(part, into: b, offset: o, pose: { v, n, _ in (SIMD3(v.x, v.y * sy, v.z), simd_normalize(SIMD3(n.x, n.y / max(sy, 0.05), n.z))) })
                }
                return          // (no second scale: the art is scaled already)
            }
            // fallback without the art file: the procedural piece to the same contract (SeesawTuning, model units)
            // the contract (SeesawTuning, model units): two chunky feet and a fat fulcrum (all within |x| 0.24), a plank 0.09 thick turned by theta about the pivot (0.27) with a T-handle at each end,
            // two LEVEL pads (top y 0.475) on a small hinge block each, translated with their hinge point and never turned, and a rubber dome on the ground under each end that the underside
            // presses down (apex = underside at its centre line)
            rbox(SIMD3(0, 0.10, -0.2), SIMD3(0.20, 0.10, 0.10), 0.09, post)
            rbox(SIMD3(0, 0.10, 0.2), SIMD3(0.20, 0.10, 0.10), 0.09, post)
            rbox(SIMD3(0, 0.20, 0), SIMD3(0.14, 0.10, 0.14), 0.09, post)
            let th = SeesawRide.shared.drawnTheta(uid), q = simd_quatf(angle: th, axis: SIMD3(0, 0, 1)), pv = SIMD3<Float>(0, SeesawTuning.pivotY, 0)
            // a rounded box built unrotated, then its vertices turned about the pivot with the plank (or, `turn` false, only moved by `shift`)
            func addRot(_ c: SIMD3<Float>, _ h: SIMD3<Float>, _ r: Float, _ col: SIMD3<Float>, turn: Bool = true, shift: SIMD3<Float> = .zero) {
                let first = b.mesh.vertices.count
                b.roundedBox(centre: c, half: h, radius: r, segments: 3, aoFloor: false, color: col)
                for i in first..<b.mesh.vertices.count {
                    let pp = b.mesh.vertices[i].pos, n = b.mesh.vertices[i].normal
                    let p3 = SIMD3(pp.x, pp.y, pp.z)
                    let rp = turn ? pv + q.act(p3 - pv) : p3 + shift, rn = turn ? q.act(SIMD3(n.x, n.y, n.z)) : SIMD3(n.x, n.y, n.z)
                    b.mesh.vertices[i].pos = SIMD4(rp + o, pp.w); b.mesh.vertices[i].normal = SIMD4(rn, n.w)
                }
            }
            addRot(SIMD3(0, SeesawTuning.beamCentreY, 0), SeesawTuning.beamHalf, 0.04, plank)
            for sx: Float in [-1, 1] {
                // the pad (level) and its hinge block under it, moved by the seat's shift: the hinge point of the plank is the block's centre
                let shift = SeesawTuning.seatShift(seat: sx < 0 ? 0 : 1, theta: th)
                addRot(SIMD3(sx * SeesawTuning.cushionX, SeesawTuning.cushionCentreY, 0), SeesawTuning.cushionHalf, 0.028, sx < 0 ? padA : padB, turn: false, shift: shift)
                addRot(SIMD3(sx * SeesawTuning.hingeX, SeesawTuning.hingeY - 0.012, 0), SIMD3(0.07, 0.04, 0.09), 0.03, post, turn: false, shift: shift)
                // the T-handle: one central post from the plank up, a crossbar along z (reaching +-0.136), top y 0.636, nothing of it beyond |x| 0.235
                let postTop = SeesawTuning.handleTopY - 0.036, postBot = SeesawTuning.handleBottomY
                addRot(SIMD3(sx * SeesawTuning.handleX, (postTop + postBot) / 2, 0), SIMD3(0.02, (postTop - postBot) / 2, 0.02), 0.018, post)
                addRot(SIMD3(sx * SeesawTuning.handleX, SeesawTuning.handleTopY - 0.018, 0), SIMD3(SeesawTuning.handleBarHalfX, 0.018, SeesawTuning.handleBarHalfZ), 0.016, post)
                // the rubber bumper: a dome (its lower half is under the lawn) whose apex follows the plank's underside while pressed
                S.blob(b, o + SIMD3(sx * SeesawTuning.bumperX, 0, 0), rx: SeesawTuning.bumperRadius, ry: SeesawTuning.bumperTop(side: sx, theta: th), rz: SeesawTuning.bumperRadius, color: padA * 0.9, segments: 10, rings: 5, ao: 0.9)
            }
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
        case .hopscotch: addHopscotchCourt(b, at: o)
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
