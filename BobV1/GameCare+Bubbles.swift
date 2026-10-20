//
//  GameCare+Bubbles.swift
//  Needs feedback for every Jelly. The room has ONE thought-bubble slot (the bubble view draws one cloud); with several Jellies the slot goes to the
//  neediest Jelly that has something to say, rotating fairly (`BubbleRotation`, pure). The owner's own schedules (BubbleSchedule / CoatBubbleSchedule)
//  run the show/hide cycle; the others wait, frozen. Jelly 0's schedules stay GameCare's (`schedule`, `coatSchedule`), so a one-Jelly game is unchanged:
//  the hub is never touched without a second Jelly. Also the greeting's stagger and the hearts of Pip and Moss (Bob's come from the touch model).
//

import Foundation
import SwiftUI
import simd

/// One Jelly that has something to say.
struct BubbleCandidate: Equatable { var id: Int; var urgency: Float }

/// Who gets the bubble slot: pure and headless.
enum BubbleRotation {
    /// Each bubble turn a Jelly waited adds this to its urgency (up to `waitCap` turns), so a lesser need gets its turn after a couple of rounds.
    static let waitBonus: Float = 0.2
    static let waitCap = 3

    /// How badly a Jelly wants a bubble: nil when he has nothing to say. A wanted need counts 0.7...1 (lower level = more urgent); a Dirty coat 0.4, Filthy 0.75.
    static func urgency(needs: BlobNeeds, coat: BlobGrime.CoatTier) -> Float? {
        var u: Float?
        if needs.wantedNeed != nil { u = 1 - min(needs.level(.hunger), needs.level(.thirst), needs.level(.attention)) }
        let c: Float? = coat == .filthy ? 0.75 : (coat == .dirty ? 0.4 : nil)
        if let c { u = max(u ?? 0, c) }
        return u
    }

    /// The Jelly to show next. `shownAt[id]` is the turn number his bubble last appeared (absent = never); `turn` is the current turn.
    /// Score = urgency + waitBonus * turns waited (capped); ties go to the lower id.
    static func pick(_ candidates: [BubbleCandidate], shownAt: [Int: Int], turn: Int) -> Int? {
        var best: (id: Int, score: Float)?
        for c in candidates.sorted(by: { $0.id < $1.id }) {
            let waited = shownAt[c.id].map { min(turn - $0, waitCap) } ?? waitCap
            let s = c.urgency + waitBonus * Float(max(waited, 0))
            if best == nil || s > best!.score + 1e-6 { best = (c.id, s) }
        }
        return best?.id
    }
}

/// The state behind the bubble slot for Jellies 1... (Jelly 0's schedules live in GameCare).
@MainActor
final class BubbleHub {
    private(set) var owner = 0
    var turn = 0
    var shownAt: [Int: Int] = [:]
    var need: [Int: BubbleSchedule] = [:]
    var coat: [Int: CoatBubbleSchedule] = [:]
    /// Head points (world) of Jellies 1...; Jelly 0's is GameCare.headWorld.
    var heads: [Int: SIMD3<Float>] = [:]
    var busyBefore = false
    var hold: Float = 0
    /// Greeting: seconds since it began, hearts still to come per Jelly, and the hearts alive (Jelly id, heart).
    var greetClock: Float = 0
    var greetHearts: [Int: (left: Int, t: Float)] = [:]
    private(set) var hearts: [(id: Int, heart: TouchPlay.Heart)] = []
    private var rng: UInt32 = 0xC0FFEE11

    nonisolated deinit {}

    func setOwner(_ id: Int) { owner = id }
    func spawnHeart(for id: Int, now: Double) {
        hearts.removeAll { now - $0.heart.born > TouchPlay.heartLife }
        func r() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }
        hearts.append((id, TouchPlay.Heart(born: now, drift: (r() - 0.5) * 2, start: (r() - 0.5) * 2, side: hearts.count % 2 == 0 ? -1 : 1)))
    }
    func pruneHearts(now: Double) { if !hearts.isEmpty { hearts.removeAll { now - $0.heart.born > TouchPlay.heartLife } } }
    /// Greeting hearts a Jelly gives: 3, 0.45 s apart (Bob's own are in GameCare).
    static let greetHeartCount = 3
    static let greetHeartGap: Float = 0.45
    /// The others leave for the front a little after one another so it is not three identical hops at once.
    static func greetStagger(_ id: Int) -> Float { 0.7 * Float(id) }
}

extension GameCare {
    /// Head point for the bubble of Jelly `id` (world).
    func bubbleHead(_ id: Int) -> SIMD3<Float> { id == 0 ? headWorld : (bubbleHub.heads[id] ?? headWorld) }
    /// Whose bubble is up (or would be next).
    var bubbleJelly: Int { bubbleHub.owner }
    var bubbleJellyName: String { jelly(bubbleHub.owner)?.name ?? "Bob" }

    /// The pointed-at Jelly lights up (several Jellies only: a one-Jelly game keeps its screen exactly as it was).
    func selectForBubble(_ id: Int) { if jellyCount > 1 { select.highlight(id) } }

    /// A tap on the bubble of Jelly 1...: select him and run the action with his id.
    func tapOtherBubble() -> BubbleAction? {
        let id = bubbleHub.owner
        if bubbleClean, bubbleNeed == nil {
            _ = bubbleHub.coat[id]?.dismiss(); bubbleClean = false
            bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, clean: true)
            selectForBubble(id)
            if canClean { clean(jelly: id) }
            return .clean
        }
        guard let n = bubbleNeed else { return nil }
        let a = n.action
        if a != .comeHere, trayOut || focus.isActive { return nil }
        applyBubble(bubbleHub.need[id]?.dismiss() ?? [], from: id)
        selectForBubble(id)
        if a == .comeHere { comeHere(jelly: id) }
        return a
    }

    /// Once per fixed step (end of tickOthers): heads, who owns the slot, the owner's cycle, the others' hearts.
    func tickBubbles(_ actors: [JellyActor], dt: Float) {
        let hub = bubbleHub
        for a in actors where a.id > 0 { let c = a.sim.centroid(); hub.heads[a.id] = SIMD3(c.x, c.y + BlobShape.H * 0.5, c.z) }
        // turns and the pause between two bubbles (the leaving puff finishes where it started)
        let busy = bubbleNeed != nil || bubbleClean
        if busy && !hub.busyBefore { hub.turn += 1; hub.shownAt[hub.owner] = hub.turn }
        if !busy && hub.busyBefore { hub.hold = 1.2 }
        hub.busyBefore = busy
        hub.hold = max(0, hub.hold - dt)
        // the slot goes to the neediest (rotating) when nobody holds it
        if !busy, hub.hold <= 0 {
            let cs: [BubbleCandidate] = jellies.compactMap { p in
                BubbleRotation.urgency(needs: p.needs, coat: p.coat).map { BubbleCandidate(id: p.id, urgency: $0) }
            }
            if let id = BubbleRotation.pick(cs, shownAt: hub.shownAt, turn: hub.turn), id != hub.owner { hub.setOwner(id) }
        }
        // each other Jelly's schedules run every step; only the owner is unsuppressed (the rest wait, frozen)
        let base = focus.isActive || select.isSelecting || bath.active || race.active
        for p in jellies where p.id > 0 {
            let id = p.id
            let owner = hub.owner == id
            let suppressed = base || !owner
            let famished = NeedKind.allCases.contains { p.needs.tier($0) == .famished }
            let preempt = p.coat == .filthy && !famished
            var ns = hub.need[id] ?? BubbleSchedule(), cs = hub.coat[id] ?? CoatBubbleSchedule()
            let coatSuppressed = suppressed || (ns.visible && !preempt)
            if cs.update(coat: p.coat, dt: dt, suppressed: coatSuppressed), owner {
                bubbleClean = cs.visible
                if !bubbleClean { bubbleEnd = BubbleEnd(serial: bubbleEnd.serial + 1, silent: bath.active, clean: true) }
            }
            let ev = ns.update(wanted: p.needs.wantedNeed, dt: dt, suppressed: suppressed || cs.visible, pinned: false)
            hub.need[id] = ns; hub.coat[id] = cs
            applyBubble(ev, from: id)
        }
        // greeting hearts for Pip and Moss
        hub.greetClock += dt
        let now = CACurrentMediaTime()
        for (id, var g) in hub.greetHearts {
            g.t -= dt
            if g.t <= 0 { g.t = BubbleHub.greetHeartGap; g.left -= 1; hub.spawnHeart(for: id, now: now) }
            hub.greetHearts[id] = g.left > 0 ? g : nil
        }
        hub.pruneHearts(now: now)
    }

    /// A Jelly 1... finished his greeting hop: three hearts, like Bob's.
    func startGreetHearts(_ id: Int) { bubbleHub.greetHearts[id] = (BubbleHub.greetHeartCount, 0); AudioHub.shared.chirp(jelly: id, .happy) }
}

/// The hearts of the other Jellies' greeting: the same hearts as Bob's (TouchHeartsView's look and motion), over their own heads.
struct GreetHeartsView: View {
    let care: GameCare

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { _ in
            if care.bubbleHub.hearts.isEmpty { Color.clear } else { live }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    private var live: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                _ = tl.date
                guard let sym = ctx.resolveSymbol(id: 0), let edge = ctx.resolveSymbol(id: 1) else { return }
                let now = CACurrentMediaTime()
                let H = Float(BlobShape.H)
                for (id, h) in care.bubbleHub.hearts {
                    let a = (now - h.born) / TouchPlay.heartLife
                    guard a >= 0, a < 1 else { continue }
                    let mid = care.bubbleHead(id) - SIMD3(0, H * 0.5, 0)
                    let w = SIMD3<Float>(mid.x + h.side * 0.80, mid.y - 0.64 + 0.8 * H, mid.z)
                    guard let p0 = ThoughtBubbleView.project(w, size: size, focus: care.focus.blend) else { continue }
                    let p = TouchHeartsView.place(h, age: a, anchor: p0, size: size, safeTop: TouchHeartsView.safeTop)
                    var c = ctx
                    c.opacity = TouchHeartsView.opacity(age: a)
                    let s = TouchHeartsView.scale(age: a) * TouchHeartsView.size(of: h) / TouchHeartsView.symbolSize
                    c.translateBy(x: p.x, y: p.y); c.scaleBy(x: s, y: s)
                    TouchHeartsView.drawHeart(&c, edge: edge, fill: sym)
                }
            } symbols: {
                Image(systemName: "heart.fill").font(.system(size: TouchHeartsView.symbolSize, weight: .semibold)).foregroundStyle(TouchHeartsView.pink).tag(0)
                Image(systemName: "heart.fill").font(.system(size: TouchHeartsView.symbolSize, weight: .semibold)).foregroundStyle(TouchHeartsView.edge).tag(1)
            }
        }
    }
}
