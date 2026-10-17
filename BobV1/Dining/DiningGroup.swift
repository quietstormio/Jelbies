//
//  DiningGroup.swift
//  The meal for 2 or 3 Blobs: the same rule as one Blob (GameCare.serveWanted), for everyone at once.
//
//  The visible floor beside the 1.56 (N=2/3: 17 % wider) tray is a corridor ~0.2 u wide, so no Blob can pass the tray or each other there.
//  Instead the tray waits: every Blob first walks (no tray out) to the approach point 0.25 behind HIS place, then everybody rests `popSettle`,
//  then the tray pops and each steps forward to his place. Places are handed out in x order (left Blob -> left place), so the approach paths
//  never cross each other. Only targets / ordering / timing: the walk itself is untouched.
//
//  The game has one real Blob today; this driver is what GameCare will use when more than one brain is on the stage (tests wire N brains).
//

import Foundation
import simd

@MainActor
final class DiningGroup {
    enum State { case idle, approaching, serving }

    let dining = DiningSet()
    private(set) var state: State = .idle
    private(set) var n = 0
    private var serving: Consumable = Consumables.berries
    private var brains: [BlobBrain] = []
    private var floor: (Int) -> SIMD2<Float> = { _ in .zero }
    private var origin = DiningSpot.preferred
    /// place index of Blob i
    private(set) var placeOf: [Int] = []
    private var finished: [Bool] = []
    private var requested = false
    private var settle: Float = 0
    private var age: Float = 0
    private var idle: [Float] = []
    private var walkRetries: [Int] = []
    private var mealRetries: [Int] = []
    /// Re-serves used (a displaced Blob: the tray poofs, everybody re-forms behind it, it pops again). Bounded like GameCare.
    private(set) var reserves = 0
    private(set) var gaveUp = false
    private var hooked = false
    var isActive: Bool { state != .idle }

    nonisolated deinit {}

    private var stands: [SIMD2<Float>] { // the tray-less stand of each place (eating / sipping offset included)
        let layout = DiningLayout.make(n: n)
        return layout.places.map { p in
            var s = origin + p.rel
            s.y += serving.eatStyle == .sip ? GameCare.sipCloser : GameCare.eatCloser
            return s
        }
    }
    /// Where Blob `i` first walks to: 0.25 behind his own place.
    func approachPoint(blob i: Int) -> SIMD2<Float> {
        let s = stands[placeOf[i]]
        return SIMD2(s.x, s.y - GameCare.approachBack)
    }

    func start(_ c: Consumable, brains bs: [BlobBrain], floor f: @escaping (Int) -> SIMD2<Float>) {
        guard state == .idle, dining.phase == .absent, !bs.isEmpty else { return }
        brains = Array(bs.prefix(3)); n = brains.count; serving = c; floor = f
        origin = DiningSpot.choose(bob: SIMD2(99, 99), layout: DiningLayout.make(n: n))
        // x order -> place order (no crossing)
        let blobsByX = brains.indices.sorted { f($0).x < f($1).x }
        let placesByX = DiningLayout.make(n: n).places.indices.sorted { DiningLayout.make(n: n).places[$0].rel.x < DiningLayout.make(n: n).places[$1].rel.x }
        placeOf = [Int](repeating: 0, count: n)
        for (k, b) in blobsByX.enumerated() { placeOf[b] = placesByX[k] }
        finished = [Bool](repeating: false, count: n)
        idle = [Float](repeating: 0, count: n); walkRetries = [Int](repeating: 0, count: n); mealRetries = [Int](repeating: 0, count: n)
        reserves = 0; gaveUp = false; age = 0
        if !hooked {
            hooked = true
            for (i, b) in brains.enumerated() {
                b.onFinished = { [weak self] r in
                    switch r { case .dine, .sip: self?.finished[i] = true; default: break }
                }
                let base = b.resolve
                b.resolve = { [weak self] p, r in
                    let rr = r - (self?.serving.eatStyle == .sip ? GameCare.sipCloser * 1.5 : 0)
                    let q = base(p, rr)
                    return self?.dining.obstacle(q, radius: rr * RoomLayout.lowPropRadiusScale) ?? q
                }
            }
        }
        beginApproach()
    }

    private func beginApproach() {
        state = .approaching; requested = false; settle = 0
        for i in brains.indices { idle[i] = 0; walkRetries[i] = 0 }
        for i in brains.indices { brains[i].requestNow(.goTo(approachPoint(blob: i))) }
        requested = true
    }

    private func isIdle(_ b: BlobBrain) -> Bool { b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace }
    /// He is at (or behind) his place's line and close to his approach point.
    private func ready(_ i: Int) -> Bool {
        let a = approachPoint(blob: i), f = floor(i)
        return f.y <= stands[placeOf[i]].y + GameCare.popTolerance && simd_distance(f, a) < 0.45
    }

    private func end() {
        dining.despawn(); state = .idle; requested = false
    }

    func tick(dt: Float) {
        defer { dining.update(dt: dt) }
        guard state != .idle else { return }
        age += dt
        if age > GameCare.mealTimeout { end(); gaveUp = true; return }
        switch state {
        case .approaching:
            if brains.indices.allSatisfy({ ready($0) }) {
                if brains.allSatisfy({ isIdle($0) }) { settle += dt } else { settle = 0 }
                if settle >= GameCare.popSettle, dining.phase == .absent, dining.spawn(serving: serving, n: n, bobAt: SIMD2(99, 99), forcedOrigin: origin) {
                    state = .serving
                    for i in brains.indices {
                        idle[i] = 0
                        brains[i].dineHooks = GameCare.hooks(for: serving, tray: dining, place: placeOf[i])
                        brains[i].requestNow(GameCare.mealRequest(serving, tray: dining, place: placeOf[i]))
                    }
                }
                return
            }
            settle = 0
            // anybody stuck idle away from his approach point is sent again, a few times; then the meal is given up
            for i in brains.indices where !ready(i) && isIdle(brains[i]) {
                idle[i] += dt
                if idle[i] > 0.8 {
                    idle[i] = 0
                    if walkRetries[i] < 3 { walkRetries[i] += 1; brains[i].requestNow(.goTo(approachPoint(blob: i))) } else { end(); gaveUp = true; return }
                }
            }
        case .serving:
            if finished.allSatisfy({ $0 }) { end(); return }
            for i in brains.indices where !finished[i] {
                guard isIdle(brains[i]) else { idle[i] = 0; continue }
                idle[i] += dt
                guard idle[i] > 0.8 else { continue }
                idle[i] = 0
                let st = dining.places[placeOf[i]].stand
                if floor(i).y > st.y + GameCare.popTolerance + 0.05 {
                    // displaced in front of his place (the tray is between): everybody re-forms behind the tray, bounded
                    if reserves < GameCare.maxReserves { reserves += 1; dining.despawn(); finished = [Bool](repeating: false, count: n); beginApproach() } else { end(); gaveUp = true }
                    return
                } else if mealRetries[i] < GameCare.maxReserves {
                    mealRetries[i] += 1
                    brains[i].dineHooks = GameCare.hooks(for: serving, tray: dining, place: placeOf[i])
                    brains[i].requestNow(GameCare.mealRequest(serving, tray: dining, place: placeOf[i]))
                } else { end(); gaveUp = true; return }
            }
        case .idle: break
        }
    }
}
