//
//  CafeCrowd.swift
//  cafe-busy-r1: the café's other customers, as pure values (no bodies here; GameCare+CafeCrowd.swift runs the bodies).
//   - `CafeTables`: where the café's tables are (the player's group takes ONE of the player candidates per visit, the customers use the rest) and the entrance.
//   - `CafeCrowd`: a seeded schedule. 1-2 groups (a pair or a single customer) are already seated when the player arrives, then a group walks in every 20...45 s
//     (the first one a little sooner), stays 40...90 s and leaves. At most two groups at a time, never more groups than free tables, never more bodies than the pool,
//     and only ONE group walks at a time (so nobody walks into anybody).
//   - `CafeRoute`: a tiny visibility-graph path planner round discs (seated bodies, tables), so a customer never walks through anybody.
//

import Foundation
import simd

nonisolated enum CafeTables {
    /// The entrance: the right-hand side of the room (just inside the floor), where the guests have always come in.
    static func door(landscape: Bool) -> SIMD2<Float> {
        if DevArgs.enabled, let s = UserDefaults.standard.string(forKey: landscape ? "CafeDoorL" : "CafeDoorP") {          // capture aid: -CafeDoorP 4.4,1.2 (an "m" in front of a number is a minus)
            let v = s.split(separator: ",").compactMap { t in Float(t.hasPrefix("m") ? "-" + t.dropFirst() : String(t)) }
            if v.count == 2 { return SIMD2(v[0], v[1]) }
        }
        return landscape ? SIMD2(4.4, 1.0) : SIMD2(3.7, 1.8)
    }
    /// Tables the player's group may take (floor x, z of the table centre) with their weight. The first of each aspect is the old fixed spot ("the middle").
    /// Portrait: the middle, or one table left / right of it at the same depth (the group stays inside the middle 60 % of the width, clear of the order card).
    /// Landscape: the old left spot, a table further back and one nearer the camera (the order card sits on the right).
    static func playerTables(landscape: Bool) -> [(centre: SIMD2<Float>, weight: Int)] {
        landscape ? [(SIMD2(-2.1, 0.2), 3), (SIMD2(-1.5, -0.9), 2), (SIMD2(-1.2, 0.9), 2)]
                  : [(SIMD2(0, -1.35), 3), (SIMD2(-1.0, -1.35), 2), (SIMD2(1.0, -1.35), 2)]
    }
    /// The customers' tables (the ENDS table: two places facing each other, a single customer takes one).
    static func customerTables(landscape: Bool) -> [SIMD2<Float>] {
        landscape ? [SIMD2(2.8, -2.6), SIMD2(1.0, 1.4), SIMD2(-0.4, -2.9)]
                  : [SIMD2(2.7, -3.3), SIMD2(-1.6, -3.3)]
    }
    /// Which player table this visit takes: weighted by `weight`, from the candidates `allowed` lets through (nil = none fits). `roll` is 0..<1.
    static func pickPlayer(landscape: Bool, roll: Float, allowed: (SIMD2<Float>) -> Bool) -> Int? {
        let c = playerTables(landscape: landscape)
        let ok = c.indices.filter { allowed(c[$0].centre) }
        guard !ok.isEmpty else { return nil }
        let total = ok.reduce(0) { $0 + c[$1].weight }
        var r = Int(roll * Float(total)); r = min(r, total - 1)
        for i in ok { r -= c[i].weight; if r < 0 { return i } }
        return ok[0]
    }
}

nonisolated struct CafeCrowdGroup: Equatable {
    enum Phase { case arriving, seated, leaving }
    var id: Int
    var size: Int
    var slot: Int
    var phase: Phase
    /// Seconds of staying left (counts down once seated).
    var stay: Float
}

nonisolated struct CafeCrowd {
    enum Event: Equatable { case enter(group: CafeCrowdGroup), leave(group: Int) }
    static let interval: ClosedRange<Float> = 20...45, firstInterval: ClosedRange<Float> = 15...30, stay: ClosedRange<Float> = 40...90
    static let maxGroups = 2, poolBodies = 4, pairShare: Float = 0.65

    var rng: CafeChatRNG
    var slots: Int
    var bodies: Int
    private(set) var groups: [CafeCrowdGroup] = []
    private(set) var nextArrival: Float
    private var serial = 0
    var entered = 0, left = 0

    init(slots: Int, bodies: Int = CafeCrowd.poolBodies, seed: UInt64) {
        rng = CafeChatRNG(seed: seed); self.slots = slots; self.bodies = bodies
        nextArrival = 0
        nextArrival = rng.range(Self.firstInterval.lowerBound, Self.firstInterval.upperBound)
    }
    var usedSlots: Set<Int> { Set(groups.map(\.slot)) }
    var usedBodies: Int { groups.reduce(0) { $0 + $1.size } }
    var freeSlots: [Int] { (0..<slots).filter { !usedSlots.contains($0) } }
    var walking: Bool { groups.contains { $0.phase != .seated } }

    /// 1 or 2 groups already seated when the player arrives (fewer when there are not that many tables / bodies); the stays are partly gone already.
    mutating func seatInitial() -> [CafeCrowdGroup] {
        let want = min(rng.chance(0.5) ? 1 : 2, slots)
        var made: [CafeCrowdGroup] = []
        for _ in 0..<want {
            guard let slot = freeSlots.first, let g = makeGroup(slot: slot, phase: .seated) else { break }
            var h = g; h.stay = rng.range(Self.stay.lowerBound * 0.4, Self.stay.upperBound * 0.8)          // (they have been here a while)
            groups.append(h); made.append(h)
        }
        return made
    }
    private mutating func makeGroup(slot: Int, phase: CafeCrowdGroup.Phase) -> CafeCrowdGroup? {
        let size = rng.chance(Self.pairShare) ? 2 : 1
        let fit = min(size, bodies - usedBodies)
        guard fit >= 1 else { return nil }
        serial += 1
        return CafeCrowdGroup(id: serial, size: fit, slot: slot, phase: phase, stay: rng.range(Self.stay.lowerBound, Self.stay.upperBound))
    }

    /// The runtime reports: the whole group is seated (its stay starts) / the whole group is out of the door (its table and bodies are free again).
    mutating func seated(_ id: Int) { if let i = groups.firstIndex(where: { $0.id == id }) { groups[i].phase = .seated } }
    mutating func gone(_ id: Int) { if groups.contains(where: { $0.id == id }) { groups.removeAll { $0.id == id }; left += 1 } }

    /// Once per step. Only one group walks at a time: a due entrance or exit waits until nobody is walking.
    mutating func tick(dt: Float) -> [Event] {
        var out: [Event] = []
        for i in groups.indices where groups[i].phase == .seated { groups[i].stay -= dt }
        nextArrival -= dt
        guard !walking else { return out }
        if let i = groups.indices.filter({ groups[$0].phase == .seated && groups[$0].stay <= 0 }).min(by: { groups[$0].stay < groups[$1].stay }) {
            groups[i].phase = .leaving
            out.append(.leave(group: groups[i].id))
            return out
        }
        if nextArrival <= 0, groups.count < Self.maxGroups, let slot = freeSlots.first, var g = makeGroup(slot: slot, phase: .arriving) {
            g.slot = freeSlots[min(freeSlots.count - 1, Int(rng.next() * Float(freeSlots.count)))]
            groups.append(g); entered += 1
            nextArrival = rng.range(Self.interval.lowerBound, Self.interval.upperBound)
            out.append(.enter(group: g))
        }
        return out
    }
}

/// A path round discs (seated bodies, tables). Nodes: the start, the goal and eight points round every disc; an edge is open when it misses every disc (the start / goal's
/// own discs excluded by the caller). Dijkstra over that. When no path exists an empty list is returned (the caller waits and looks again).
nonisolated enum CafeRoute {
    struct Disc { var c: SIMD2<Float>; var r: Float }
    static func segmentClear(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ d: Disc) -> Bool {
        let ab = b - a, l2 = simd_dot(ab, ab)
        let t = l2 < 1e-6 ? 0 : max(0, min(1, simd_dot(d.c - a, ab) / l2))
        return simd_distance(a + ab * t, d.c) >= d.r - 1e-4
    }
    static func path(from: SIMD2<Float>, to: SIMD2<Float>, discs: [Disc], inside: (SIMD2<Float>) -> Bool = { _ in true }) -> [SIMD2<Float>] {
        var nodes: [SIMD2<Float>] = [from, to]
        for d in discs { for k in 0..<8 { let a = Float(k) * .pi / 4; let p = d.c + SIMD2(sinf(a), cosf(a)) * (d.r + 0.25); if inside(p) { nodes.append(p) } } }
        func open(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool { discs.allSatisfy { segmentClear(a, b, $0) } }
        let n = nodes.count
        var dist = [Float](repeating: .infinity, count: n), prev = [Int](repeating: -1, count: n), done = [Bool](repeating: false, count: n)
        dist[0] = 0
        for _ in 0..<n {
            var u = -1
            for i in 0..<n where !done[i] && (u < 0 || dist[i] < dist[u]) { u = i }
            guard u >= 0, dist[u] < .infinity else { break }
            done[u] = true
            if u == 1 { break }
            for v in 0..<n where !done[v] && open(nodes[u], nodes[v]) {
                let nd = dist[u] + simd_distance(nodes[u], nodes[v])
                if nd < dist[v] { dist[v] = nd; prev[v] = u }
            }
        }
        guard prev[1] >= 0 else { return [] }
        var out: [SIMD2<Float>] = [], k = 1
        while k != 0 { out.append(nodes[k]); k = prev[k] }
        return out.reversed()
    }
}
