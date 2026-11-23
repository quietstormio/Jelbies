//
//  GameCare+BestFriend.swift
//  best-friend-r1: hands "who is whose best friend" (Park/ParkModels.swift `ParkBestFriend`, the Profile's rule) to the brains while the friend is there, and runs the park's
//  first greeting. The pairing itself is Melon/BondPairing.swift. Nothing here is saved.
//

import Foundation
import simd

extension GameCare {
    nonisolated(unsafe) static var bondLogged: Set<Int> = []
    /// Writes `socialBook.bestFriends` on every body that is part of a (roster Jelmiko, visitor) pair where the visitor is that Jelmiko's best friend and is in the room.
    /// `visitors` = the bodies of the visitors present (the park's cast, or the guest) with their record ids; `homes` = (roster slot, body).
    /// Overwrites wholesale (body ids are reused), so a body whose friend left is cleared. Returns the (home body, visitor body) best-friend pairs.
    @discardableResult
    func syncBestFriends(homes: [(slot: Int, actor: JellyActor)], visitors: [(vid: Int, actor: JellyActor)]) -> [(home: JellyActor, visitor: JellyActor)] {
        var sets: [Int: Set<Int>] = [:]
        var pairs: [(home: JellyActor, visitor: JellyActor)] = []
        for h in homes {
            guard let prof = jelly(h.slot), let best = ParkBestFriend.of(character: prof.character, in: parkBook.visitors) else { continue }
            for v in visitors where parkBook.visitor(v.vid)?.id == best.0.id && v.actor.id != h.actor.id {
                sets[h.actor.id, default: []].insert(v.actor.id); sets[v.actor.id, default: []].insert(h.actor.id)
                pairs.append((h.actor, v.actor))
            }
        }
        if EmoteSpot.logOn { let now = Set(pairs.map { $0.home.id * 100 + $0.visitor.id }); if now != Self.bondLogged { Self.bondLogged = now; NSLog("[bond] best-friend pairs (home body, visitor body): %@", pairs.map { "\($0.home.id)-\($0.visitor.id)" }.joined(separator: " ")) } }
        for h in homes { h.actor.brain?.socialBook.bestFriends = sets[h.actor.id] ?? [] }
        for v in visitors { v.actor.brain?.socialBook.bestFriends = sets[v.actor.id] ?? [] }
        return pairs
    }

    /// The park: each Jelmiko that came and the visitors there. Once per visit and pair the visitor greets its Jelmiko with the shy wave (a wave from afar, then a run to each other: BlobSocial+Friends3).
    func tickBestFriendsPark(_ actors: [JellyActor], dt: Float) {
        let book = parkBook, work = book.work
        let homes = book.comers.filter { actors.indices.contains($0) }.map { (slot: $0, actor: actors[$0]) }
        let pairs = syncBestFriends(homes: homes, visitors: Array(zip(book.cast, book.actors)).map { (vid: $0.0, actor: $0.1) })
        if EmoteSpot.logOn, BondPairing.onPick == nil { BondPairing.onPick = { c, cands, chosen in NSLog("[bondpick] chooser=%d cands=%@ chosen=%d", c.steerID, cands.map { String($0.steerID) }.joined(separator: ","), chosen.steerID) } }          // (capture aid)
        guard BondPairing.multiplier != 1 else { return }
        if work.bondT < ParkBondTuning.holdFor {          // the first seconds: the pair is not sent off on a first leg / solo before it has said hello (nothing is stopped: only the next pick waits)
            for p in pairs where !work.bondGreeted.contains(p.home.id * 100 + p.visitor.id) {
                for b in [p.home.brain, p.visitor.brain].compactMap({ $0 }) { b.restTimer = max(b.restTimer, 0.5); b.idleState.cooldown = max(b.idleState.cooldown, 0.5); b.socialBook.cooldown = max(b.socialBook.cooldown, 0.5) }
            }
        }
        guard park.phase == .playing else { return }
        work.bondT += dt
        for p in pairs {
            let key = p.home.id * 100 + p.visitor.id
            guard !work.bondGreeted.contains(key) else { continue }
            if work.bondT > ParkBondTuning.greetGiveUp { work.bondGreeted.insert(key); continue }
            guard work.bondT > ParkBondTuning.greetAfter, Int(work.bondT * 4) != Int((work.bondT - dt) * 4),          // (tried four times a second)
                  let v = p.visitor.brain, let h = p.home.brain, !v.isSleeping, !h.isSleeping, v.commandedIdle == nil, h.commandedIdle == nil else { continue }
            if v.socialStart(simd_distance(v.position, h.position) < 2.3 ? .greet : .shyWave, with: h, p.visitor.sim) { work.bondGreeted.insert(key); if EmoteSpot.logOn { NSLog("[bond] park greeting: visitor body %d waves to %d at visit second %.1f", p.visitor.id, p.home.id, work.bondT) } }
        }
    }

    /// Home: the guest and the Jelmiko whose best friend he is.
    func tickBestFriendsHome(_ actors: [JellyActor], guest a: JellyActor, vid: Int) {
        if EmoteSpot.logOn, BondPairing.onPick == nil { BondPairing.onPick = { c, cands, chosen in NSLog("[bondpick] chooser=%d cands=%@ chosen=%d", c.steerID, cands.map { String($0.steerID) }.joined(separator: ","), chosen.steerID) } }
        syncBestFriends(homes: actors.enumerated().map { (slot: $0.offset, actor: $0.element) }, visitors: [(vid: vid, actor: a)])
    }
    func clearBestFriends(_ actors: [JellyActor]) { for a in actors { a.brain?.socialBook.bestFriends = [] } }

    /// Capture aid (`-BestFriend <visitorId>:<slot>`, dev arguments only): that visitor is Best friend (100 points) of that Jelmiko and nobody else's. Idempotent.
    func devSeedBestFriend() {
        guard DevArgs.enabled, let s = UserDefaults.standard.string(forKey: "BestFriend") else { return }
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let c = jelly(parts[1])?.character else { return }
        parkBook.markSeen([parts[0]], at: Date().timeIntervalSince1970)
        _ = parkBook.add(points: 100, visitor: parts[0], character: c)
        parkBook.save()
    }
}

nonisolated enum ParkBondTuning {
    /// The first greeting: seconds into the visit before it is tried, and when it is given up (the pair was never free and apart at once).
    static let greetAfter: Float = 0.3, greetGiveUp: Float = 60, holdFor: Float = 6
}
