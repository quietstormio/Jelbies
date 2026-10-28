//
//  DecorField+Toys.swift
//  What the room remembers about its toys (2026-10-25, "toys should matter much more"): when a piece was put down or moved (its NOVELTY), when a Jelly last
//  finished with it (its RECENCY), and the few news items the Jellies read to notice a new toy. Nothing here allocates per frame: the dictionaries only grow when
//  a piece is added, and the news list is capped.
//    pull(uid) = (baseline + (1 - baseline) * novelty) * recency
//      novelty   1 at placing, decays with `noveltyTau` (minutes); baseline keeps a toy that has been out for hours at a lower but non-zero pull
//      recency   after a play the pull is x`recencyFloor`, back to 1 over `returnAfter` seconds (they come back every few minutes, not at once)
//

import Foundation
import simd

enum ToyTuning {
    static let noveltyTau: Float = 240, baseline: Float = 0.30
    static let returnAfter: Float = 150, recencyFloor: Float = 0.08
    /// How many awake free Jelbies notice a new toy (all of them when the toy takes several players).
    static let noticeNearest = 2
    static let noticeDelay: ClosedRange<Float> = 1.0...2.0
    static let newsLife: Float = 20
    /// A Jelly waiting for his turn gives up after this long; at most this many wait at one toy.
    static let queueTimeout: Float = 16, queueMax = 2
    /// After a timeout / an unreachable toy he leaves it alone this long.
    static let boredFor: Float = 90
    /// Idle weight of a decor behaviour = 1 + gain * pull of the best piece for it (see BlobBrain.toyWeight).
    static let weightGain: Float = 2.4
    /// When he picks his next idle activity and a toy is out: the direct chance he goes to play with one, before the variety bag (the single knob for how much toy play there is).
    static let directChance: Float = 0.40
    /// Least seconds between two of his toy sessions' starts (so toy play is mixed with roaming, socials and rest).
    static let directGap: Float = 20
    /// Founding set-up (launch, room switches) is not news.
    nonisolated(unsafe) static var settle: TimeInterval = 5
}

struct ToyNews { var serial: Int; var uid: Int; var t: Float; var pos: SIMD2<Float> }

struct ToyBook {
    var clock: Float = 0
    var born: [Int: Float] = [:]
    var played: [Int: Float] = [:]
    var known: [Int: (at: SIMD2<Float>, quarter: Int)] = [:]
    var firstSet: TimeInterval = -1
    var serial = 0
    var news: [ToyNews] = []
    /// The bubble machine's last burst: who booped, where, when.
    var burstSerial = 0
    var burstUID = -1, burstBy = -1
    var burstT: Float = -99
    var burstPos = SIMD2<Float>.zero
}

extension DecorField {
    /// Interest in a piece, 0...1 (novelty x recency).
    func toyPull(_ uid: Int) -> Float {
        let age = toys.clock - (toys.born[uid] ?? -1e5)
        let nov = expf(-max(age, 0) / ToyTuning.noveltyTau)
        let base = ToyTuning.baseline + (1 - ToyTuning.baseline) * nov
        let since = toys.clock - (toys.played[uid] ?? -1e5)
        let rec = ToyTuning.recencyFloor + (1 - ToyTuning.recencyFloor) * min(1, max(since, 0) / ToyTuning.returnAfter)
        return base * rec
    }
    /// Is it a thing a Jelly notices when it arrives (a toy or an interactive piece; the goal stands for its ball).
    func toyInteresting(_ k: DecorKind) -> Bool { k.activeInteraction != nil || k == .minigoal }
    func toyPlayed(_ uid: Int) { toys.played[uid] = toys.clock }

    func toyAdvance(_ dt: Float) {
        toys.clock += dt
        if !toys.news.isEmpty { let now = toys.clock; toys.news.removeAll { now - $0.t > ToyTuning.newsLife } }
    }
    func toyPostNews(_ uid: Int, _ pos: SIMD2<Float>) {
        toys.serial += 1
        toys.born[uid] = toys.clock
        toys.news.append(ToyNews(serial: toys.serial, uid: uid, t: toys.clock, pos: pos))
        if toys.news.count > 4 { toys.news.removeFirst() }
    }
    func toyPostBurst(_ uid: Int, by: Int, at p: SIMD2<Float>) {
        toys.burstSerial += 1; toys.burstUID = uid; toys.burstBy = by; toys.burstT = toys.clock; toys.burstPos = p
    }

    /// `set` calls this with the new list (before it replaces the old): a new piece, or one turned, is news; so is one put down after being held.
    func toyNoteChanges(_ list: [PlacedDecor]) {
        let now = ProcessInfo.processInfo.systemUptime
        if toys.firstSet < 0 { toys.firstSet = now }
        let settled = now - toys.firstSet >= ToyTuning.settle
        for p in list {
            guard let k = toys.known[p.uid] else {
                toys.known[p.uid] = (p.at, p.quarter)
                if settled, toyInteresting(p.kind), p.uid != held { toyPostNews(p.uid, p.at) }
                continue
            }
            if p.quarter != k.quarter {
                toys.known[p.uid] = (p.at, p.quarter)
                if settled, toyInteresting(p.kind) { toyPostNews(p.uid, p.at) }
            } else if p.uid == held || p.kind.rolls {
                toys.known[p.uid] = (p.at, p.quarter)          // (dragged: the drop is the news; a ball that rolled is not)
            } else if simd_distance(p.at, k.at) > 0.05 {
                toys.known[p.uid] = (p.at, p.quarter)
                if settled, toyInteresting(p.kind) { toyPostNews(p.uid, p.at) }
            }
        }
    }
    /// The piece the player was holding was put down: that is news too.
    func toyDropped(_ uid: Int) {
        guard let f = foot(uid), toyInteresting(f.kind), ProcessInfo.processInfo.systemUptime - toys.firstSet >= ToyTuning.settle else { return }
        toyPostNews(uid, f.centre)
    }
}
