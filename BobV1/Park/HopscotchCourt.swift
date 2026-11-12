//
//  HopscotchCourt.swift
//  The Park's hopscotch court (2026-11-04): the numbered squares 1...8 (single, single, double, single, double, single: 1, 2, 3|4, 5, 6|7, 8) painted as soft chalk on a paving slab,
//  and the LINE: when one Jelbie starts hopscotch the others who are free get one roll each (`HopscotchTuning.joinChance`) to join behind him. Jelbies have short legs and
//  cannot stride, so they hop from square centre to square centre (BlobBrain+Hopscotch.swift). This file is the geometry, the tunables and the shared line state.
//  The court is flat paint (not solid): nothing is walked round, and who may hop where is decided by the line, not by collision.
//

import simd
import Foundation

nonisolated enum HopscotchTuning {
    /// Chance (per free Jelbie, rolled once per line) to join a line that has started: "sometimes they all do it in a line".
    nonisolated(unsafe) static var joinChance: Float = 0.35
    static let joinRange: ClosedRange<Float> = 0.30...0.40
    /// Most Jelbies in one line.
    static let maxPlayers = 4
    /// A follower may hop to square `s` only when the one ahead has landed on square `s + spacingAhead` or later (squares are ~0.85 apart: 2 = 1.7 u, a body is ~1.0 across).
    static let spacingAhead = 2
    /// ... and he may step up to the start only when the one ahead is on at least this square (0-based): "a couple of squares in".
    static let startAfter = 2
    /// Least distance (u) between a hopper's landing spot and any other Jelbie.
    static let landingClear: Float = 1.05
    /// Seconds a follower waits for its turn before it gives up and wanders off.
    static let patience: Float = 30
    /// Queue spots are this far apart (the park keeps bodies 1.4 apart; 1.0 was refused by `peerFree`).
    static let queueGap: Float = 1.7
    /// Walks to the start a stepped-up Jelbie tries before he gives the game up (a blocked start must not loop).
    static let startTries = 3
    /// A walk that stops further from the start than this is still travelling (it does not use up a try).
    static let startBlockedWithin: Float = 2.5
}

nonisolated enum HopscotchCourt {
    static let pitch: Float = 0.85, cell: Float = 0.78, double: Float = 0.42
    /// The court's squares in order, piece-local (x right, z toward the camera): 1, 2, then 3 | 4, 5, 6 | 7, 8.
    static let squares: [SIMD2<Float>] = {
        func z(_ r: Int) -> Float { (Float(r) - 2.5) * pitch }
        return [SIMD2(0, z(0)), SIMD2(0, z(1)), SIMD2(-double, z(2)), SIMD2(double, z(2)), SIMD2(0, z(3)), SIMD2(-double, z(4)), SIMD2(double, z(4)), SIMD2(0, z(5))]
    }()
    static let count = 8
    /// Half extents of the slab (x, z).
    static let slabHalf = SIMD2<Float>(double + cell / 2 + 0.14, 2.5 * pitch + cell / 2 + 0.14)
    /// Where the line forms: slot 0 is the start, behind square 1; slot 1 is beside it to the right, slots 2 and 3 a row further back in a fan (all `queueGap` apart, the park keeps
    /// bodies 1.4 apart; slot 3 is the far end of that row, to the right of slot 2, clear of the seesaw (park-room-r2: seesaw at (-3.2, -3.2)) and of the slide's approach).
    static func queueSpot(slot: Int) -> SIMD2<Float> {
        let g = HopscotchTuning.queueGap, z0 = squares[0].y - 0.9
        switch slot {
        case ...0: return SIMD2(0, z0)
        case 1: return SIMD2(g, z0)
        case 2: return SIMD2(1.5 * g, z0 - 0.866 * g)
        default: return SIMD2(2.5 * g, z0 - 0.866 * g)
        }
    }
    /// Where the finished hopper walks: past the last square, to the side.
    static let exitSpot = SIMD2<Float>(1.5, squares[7].y + 0.25)
}

/// Who is in the line at each court: their order, their slot in the queue and the last square each has landed on. Main thread, like `DecorField`.
final class HopscotchLine {
    static let shared = HopscotchLine()
    struct Player { var id: Int; var slot: Int; var sq = -1 }
    /// Players of each court, in the order they started (the first is the leader).
    private(set) var lines: [Int: [Player]] = [:]
    /// Brains that already had their one roll for the line that is running now.
    private(set) var rolled: [Int: Set<Int>] = [:]
    static let done = 99

    func players(_ uid: Int) -> [Player] { lines[uid] ?? [] }
    var active: Bool { !lines.isEmpty }
    func contains(_ uid: Int, _ id: Int) -> Bool { lines[uid]?.contains { $0.id == id } ?? false }
    /// The slot a newcomer would get: 0 (the start spot) for the first, else the lowest free slot from 1.
    func nextSlot(_ uid: Int) -> Int {
        if players(uid).isEmpty { return 0 }
        let used = Set(players(uid).map(\.slot))
        var k = 1
        while used.contains(k) { k += 1 }
        return k
    }
    @discardableResult func enroll(_ uid: Int, _ id: Int) -> Int {
        if let p = lines[uid]?.first(where: { $0.id == id }) { return p.slot }
        let s = nextSlot(uid)
        lines[uid, default: []].append(Player(id: id, slot: s))
        if lines[uid]!.count == 1 { rolled[uid] = [id] }
        return s
    }
    func remove(_ uid: Int, _ id: Int) {
        guard var l = lines[uid] else { return }
        l.removeAll { $0.id == id }
        lines[uid] = l.isEmpty ? nil : l
        if l.isEmpty { rolled[uid] = nil }
    }
    func landed(_ uid: Int, _ id: Int, _ sq: Int) { if let i = lines[uid]?.firstIndex(where: { $0.id == id }) { lines[uid]![i].sq = sq } }
    func square(_ uid: Int, _ id: Int) -> Int { lines[uid]?.first { $0.id == id }?.sq ?? -1 }
    /// The player right in front of `id` in the line.
    func ahead(_ uid: Int, _ id: Int) -> Player? {
        guard let l = lines[uid], let i = l.firstIndex(where: { $0.id == id }), i > 0 else { return nil }
        return l[i - 1]
    }
    /// Is the start free for the next one? (Nobody has stepped up, or the last one who did is a couple of squares in.)
    func startOpen(_ uid: Int) -> Bool {
        guard let last = lines[uid]?.last(where: { $0.slot == 0 }) else { return true }
        return last.sq >= HopscotchTuning.startAfter
    }
    /// `id` leaves the queue for the start: slot 0, and his place in the order is right behind the last one who stepped up (the hop spacing follows the order).
    func start(_ uid: Int, _ id: Int) {
        guard var l = lines[uid], let i = l.firstIndex(where: { $0.id == id }) else { return }
        var p = l.remove(at: i); p.slot = 0
        let at = (l.lastIndex(where: { $0.slot == 0 }) ?? -1) + 1
        l.insert(p, at: at); lines[uid] = l
    }
    /// May he hop to square `target` now? (The one ahead is at least `spacingAhead` squares beyond it, or has finished.)
    func mayHop(_ uid: Int, _ id: Int, to target: Int) -> Bool {
        guard let a = ahead(uid, id) else { return true }
        return a.sq >= Self.done || a.sq >= target + HopscotchTuning.spacingAhead
    }
    /// `id` has just been told a line is running: the one roll. True = he joins.
    func invitation(_ uid: Int, _ id: Int, roll: Float) -> Bool {
        guard let l = lines[uid], !l.isEmpty, l.count < HopscotchTuning.maxPlayers, !l.contains(where: { $0.id == id }) else { return false }
        guard !(rolled[uid]?.contains(id) ?? false) else { return false }
        rolled[uid, default: []].insert(id)
        return roll < HopscotchTuning.joinChance
    }
    /// The court is gone or the park is left: nobody is in a line any more.
    func prune(keeping uids: Set<Int>) {
        for u in Array(lines.keys) where !uids.contains(u) { lines[u] = nil }
        for u in Array(rolled.keys) where !uids.contains(u) { rolled[u] = nil }
    }
}

extension DecorField {
    /// A line has started at the court: the free Jelbies get one roll each to join it (their notice code, BlobBrain+ToyPlay.swift).
    func hopscotchInvite(_ uid: Int, at p: SIMD2<Float>) {
        toys.serial += 1
        toys.news.append(ToyNews(serial: toys.serial, uid: uid, t: toys.clock, pos: p))
        if toys.news.count > 4 { toys.news.removeFirst() }
    }
}
