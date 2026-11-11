//
//  ParkSharedPlay.swift
//  Park friendship from playing TOGETHER: a home Jelbie and a park visitor on the same seesaw ride or in the same hopscotch line earn a one-off bonus.
//  Pure values in, awards out (no GameCare, no singletons): GameCare+Park.swift gathers the inputs from the real seesaw / court and applies the awards.
//

import Foundation

enum SharedPlayTuning {
    static let rideBonus: Float = 8        // one shared seesaw ride
    static let hopBonus: Float = 6         // one shared hopscotch line
    static let rideSeconds: Float = 4      // seconds of real pair riding before the ride counts
    static let capPerPair = 3              // awards per (home Jelbie, visitor) per park visit, rides and lines together
}

/// A seesaw as seen this step: its piece, its ride mode and the body ids on its seats.
struct SharedSeesaw {
    var uid: Int
    var mode: SeesawRide.Mode
    var seats: [Int]
}

/// A hopscotch court as seen this step: its piece and its players (body id, last landed square; -1 = not yet on the court, 99 = done).
struct SharedCourt {
    var uid: Int
    var players: [(id: Int, sq: Int)]
}

struct SharedPlayAward: Equatable {
    enum Kind { case ride, line }
    var home: Int, visitor: Int
    var points: Float
    var uid: Int
    var kind: Kind
}

struct SharedPlayTracker {
    private struct Pair: Hashable { var home: Int, visitor: Int }
    private struct Ride { var pair: Pair; var t: Float = 0; var paid = false }
    private var rides: [Int: Ride] = [:]
    private var lines: [Int: Set<Pair>] = [:]
    private var counts: [Pair: Int] = [:]

    mutating func reset() { rides = [:]; lines = [:]; counts = [:] }

    mutating func step(dt: Float, seesaws: [SharedSeesaw], courts: [SharedCourt], isHome: (Int) -> Bool, isVisitor: (Int) -> Bool) -> [SharedPlayAward] {
        var out: [SharedPlayAward] = []
        func pay(_ p: Pair, _ points: Float, _ uid: Int, _ kind: SharedPlayAward.Kind) {
            guard counts[p, default: 0] < SharedPlayTuning.capPerPair else { return }
            counts[p, default: 0] += 1
            out.append(SharedPlayAward(home: p.home, visitor: p.visitor, points: points, uid: uid, kind: kind))
        }
        // seesaws
        let seen = Set(seesaws.map(\.uid))
        for uid in Array(rides.keys) where !seen.contains(uid) { rides[uid] = nil }
        for s in seesaws {
            let same: Bool
            switch s.mode { case .pairBeat, .pairRide, .ending, .endBeat: same = true; default: same = false }
            var pair: Pair?
            if same, s.seats.count == 2 {
                let h = s.seats.filter(isHome), v = s.seats.filter(isVisitor)
                if h.count == 1, v.count == 1 { pair = Pair(home: h[0], visitor: v[0]) }
            }
            guard let p = pair else { rides[s.uid] = nil; continue }
            if rides[s.uid]?.pair != p { rides[s.uid] = Ride(pair: p) }
            if s.mode == .pairRide, var r = rides[s.uid], !r.paid {
                r.t += dt
                if r.t >= SharedPlayTuning.rideSeconds { r.paid = true; pay(p, SharedPlayTuning.rideBonus, s.uid, .ride) }
                rides[s.uid] = r
            }
        }
        // hopscotch
        let courtIDs = Set(courts.map(\.uid))
        for uid in Array(lines.keys) where !courtIDs.contains(uid) { lines[uid] = nil }
        for c in courts {
            let ids = Set(c.players.map(\.id))
            var paid = (lines[c.uid] ?? []).filter { ids.contains($0.home) && ids.contains($0.visitor) }
            let homes = c.players.filter { isHome($0.id) }, visitors = c.players.filter { isVisitor($0.id) }
            for h in homes where h.sq >= 0 {
                for v in visitors where v.sq >= 0 {
                    let p = Pair(home: h.id, visitor: v.id)
                    if paid.contains(p) { continue }
                    paid.insert(p)
                    pay(p, SharedPlayTuning.hopBonus, c.uid, .line)
                }
            }
            lines[c.uid] = paid
        }
        return out
    }
}
