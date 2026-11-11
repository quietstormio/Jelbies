//
//  BlobBrain+HopNear.swift
//  The hop onto and off a seat uses a NEAR stand spot, never the far side of a two-seat piece (a leap across the room, at home and at the park).
//  `hopStandSpots` (BlobBrain+Decor.swift) lists the candidates; this file chooses among them: a spot inside the piece's own footprint or farther than
//  `hopFar` from the seat is no stand spot, the front row keeps its place when it is near, every other spot goes by hop length.
//

import Foundation
import simd

extension BlobBrain {
    /// The hop length a front-row spot may have and still keep its place first (the limit grows to the shortest legal hop + 0.05 when every spot is farther).
    static let hopNear: Float = 1.2
    /// No stand spot is farther than this from the seat's floor spot (this drops exactly the far end of a two-seat piece).
    static let hopFar: Float = 2.0
    /// A candidate closer than this to the piece's edge is inside the piece's own footprint (the "behind" spots of an off-centre seat) and is no stand spot.
    static let hopOwnClear: Float = bagHopGap - 0.05
    /// How long he stays seated past the rest while no near spot is free to hop down to.
    static let hopExitWait: Float = 3

    /// One floor-legal stand candidate.
    struct HopCandidate {
        var spot: SIMD2<Float>
        /// The hop length: from the spot to the seat's neutral floor spot.
        var hop: Float
        /// One of the first five spots of `hopStandSpots` (the front row; a test guards that list's shape).
        var front: Bool
    }

    /// The seat's neutral floor spot: the formula of `seatGoal` (private, and it reads `idleState.seat`).
    func hopSeatXZ(_ f: DecorFoot, seat: Int) -> SIMD2<Float> {
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        return f.centre + f.turned(SIMD2(sp.x, sp.z))
    }

    /// The seat to sit on: the picked one when it has a stand spot (always for the beanbag and a one-seat piece), else the nearest FREE other seat that has one,
    /// else the picked seat unchanged (the caller's guard then skips the piece, as it always did). Changes no state.
    func hopNearSeat(_ f: DecorFoot, seat: Int) -> Int {
        let n = f.kind.sitPoints.count
        if f.kind == .beanbag || n <= 1 { return seat }
        let here = SIMD2(px, pz)
        if decorStand(.decorSit, f, from: here, seat: seat) != nil { return seat }
        let mine = hopSeatXZ(f, seat: seat)
        let others = (0..<n).filter { $0 != seat && DecorField.shared.seatOccupant[f.uid]?[$0] == nil }
            .sorted { simd_distance(hopSeatXZ(f, seat: $0), mine) < simd_distance(hopSeatXZ(f, seat: $1), mine) }
        for s in others where decorStand(.decorSit, f, from: here, seat: s) != nil { return s }
        return seat
    }

    /// The floor-legal candidates in pick order, and the near limit L. Legal = outside the piece's own footprint, within `hopFar` of the seat, and the floor
    /// (walls, other pieces; not the peers) leaves it where it is (`tolerance`). Order: the front-row candidates within L in today's order, then every other
    /// candidate by hop length, nearest first (ties keep today's order).
    func hopNearOrder(_ f: DecorFoot, seat: Int, tolerance: Float) -> (spots: [HopCandidate], near: Float) {
        let seatP = hopSeatXZ(f, seat: seat)
        var legal: [HopCandidate] = []
        var order: [Int] = []
        for (i, p) in hopStandSpots(f, seat: seat).enumerated() {
            guard f.distance(p) >= Self.hopOwnClear else { continue }
            let hop = simd_distance(p, seatP)
            guard hop <= Self.hopFar, simd_distance(p, fixed(p)) < tolerance else { continue }
            legal.append(HopCandidate(spot: p, hop: hop, front: i < 5)); order.append(i)
        }
        guard let shortest = legal.map(\.hop).min() else { return ([], Self.hopNear) }
        let limit = max(Self.hopNear, shortest + 0.05)
        var first: [HopCandidate] = [], rest: [(c: HopCandidate, i: Int)] = []
        for (k, c) in legal.enumerated() {
            if c.front && c.hop <= limit { first.append(c) } else { rest.append((c, order[k])) }
        }
        rest.sort { $0.c.hop != $1.c.hop ? $0.c.hop < $1.c.hop : $0.i < $1.i }
        return (first + rest.map(\.c), limit)
    }

    /// The hop-on pick: the first candidate in pick order with nobody on it, nil when there is none (the piece is skipped).
    func hopNearStand(_ f: DecorFoot, seat: Int) -> SIMD2<Float>? {
        for c in hopNearOrder(f, seat: seat, tolerance: 0.06).spots where peerFree(fixed(c.spot)) { return c.spot }
        return nil
    }

    /// The hop-off pick (every piece but the beanbag): the first free candidate within L, else the first free one of the whole order, else the front spot as it was.
    func hopExitPick(_ f: DecorFoot) -> SIMD2<Float> {
        let ignore = decorIgnore
        let o = hopNearOrder(f, seat: idleState.seat, tolerance: 0.05)
        if let c = o.spots.first(where: { $0.hop <= o.near && peerFree(fixed($0.spot)) }) { return c.spot }
        if let c = o.spots.first(where: { peerFree(fixed($0.spot)) }) { return c.spot }
        decorIgnore = ignore
        return fixed(hopStandSpots(f, seat: idleState.seat)[0])
    }

    /// Whether he can hop down now: true for the beanbag and when there is no legal candidate at all (nothing to wait for), else when a free spot within L exists.
    func hopExitNear(_ f: DecorFoot) -> Bool {
        if f.kind == .beanbag { return true }
        let o = hopNearOrder(f, seat: idleState.seat, tolerance: 0.05)
        if o.spots.isEmpty { return true }
        return o.spots.contains { $0.hop <= o.near && peerFree(fixed($0.spot)) }
    }
}
