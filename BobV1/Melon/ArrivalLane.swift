//
//  ArrivalLane.swift
//  arrival-lane-r1 (owner 11-28: "ensure no blocking when a new Jelmiko runs in ... ensure ones I already have aren't near left side so the new one can run in without having to stop").
//  A bought Jelmiko comes in from off the left edge at the depth of his spot, so his run is one straight horizontal strip: the LANE. Behind the launch curtain the housemates standing in it (or on his
//  spot) are put on free floor to the right / centre (`GameCare.planArrival`, the spot is chosen so as few as possible have to move), and until he has finished running in nobody may pick a goal in the
//  lane or a leg across it (`BlobBrain.crowdGoalFree`, `MoveCrowd.arrivalLane`). Placement + a temporary reservation only: the walk, the gait and the crowding rules are untouched.
//  Switch: `ArrivalLane.on` (DevArgs `-ArrivalLane 0` or env ARRIVALLANE=0 = the old arrival, for a before / after measurement).
//

import Foundation
import simd

nonisolated struct ArrivalLaneShape: Equatable {
    /// Depth of the strip (his entry z = his spot's z) and the spot's x (the strip ends a margin past it).
    var z: Float
    var spotX: Float
    /// Half width of the strip, and how far past the spot it reaches (one body gap + a little).
    static let margin: Float = 1.7
    func contains(_ p: SIMD2<Float>) -> Bool { abs(p.y - z) < Self.margin && p.x < spotX + Self.margin }
    /// A straight leg a -> b that touches the lane.
    func crosses(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
        for i in 0...12 { if contains(a + (b - a) * (Float(i) / 12)) { return true } }
        return false
    }
}

nonisolated enum ArrivalLane {
    private static let env = ProcessInfo.processInfo.environment
    static var on: Bool = {
        if let e = env["ARRIVALLANE"] { return e != "0" }
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "ArrivalLane") else { return true }
        return !["0", "no", "false", "off"].contains(v.lowercased())
    }()
    /// Capture aid (simulator / dev builds only): `-ArrivalLab worst` or `rand:<seed>` puts the housemates there just before the arrival is planned; `-ArrivalLog 1` logs his speed each step.
    static var lab: String? { DevArgs.enabled ? UserDefaults.standard.string(forKey: "ArrivalLab") : nil }
    static var logOn: Bool { DevArgs.enabled && UserDefaults.standard.integer(forKey: "ArrivalLog") != 0 }
    /// The lane that is reserved right now (nil = none): read by `BlobBrain.crowdGoalFree`.
    nonisolated(unsafe) static var active: ArrivalLaneShape?
    nonisolated(unsafe) static var violations = 0
}

extension BlobBrain {
    /// A goal in the reserved lane, or a leg from here across it (a body that is in the lane already may leave it).
    func arrivalLaneBlocks(_ p: SIMD2<Float>) -> Bool {
        guard let l = ArrivalLane.active else { return false }
        if l.contains(p) { return true }
        let here = position
        return !l.contains(here) && l.crosses(here, p)
    }
}

extension GameCare {
    private func laneGridFloor(_ b: BlobBrain, x: ClosedRange<Float>, step: Float = 0.5) -> [SIMD2<Float>] {
        let c = GameCamera.arenaCenter, r = GameCamera.arenaRadius
        let rf = b.roamProvider?()
        var out: [SIMD2<Float>] = []
        var zz = c.y - r + 0.3
        while zz <= c.y + r - 0.3 {
            var xx = x.lowerBound
            while xx <= x.upperBound {
                let p = SIMD2<Float>(xx, zz)
                if simd_distance(p, c) < r - 0.4, simd_distance(b.fixed(p), p) < 0.1, rf?.stopOK(p) ?? true { out.append(p) }
                xx += step
            }
            zz += step
        }
        return out
    }

    /// Where the newcomer's spot is and who has to step aside (`moves`: housemate id -> a free spot on the right / centre). `legacy` is where the old code would have put his spot.
    func planArrival(_ others: [JellyActor], using ref: BlobBrain, legacy: SIMD2<Float>) -> (target: SIMD2<Float>, lane: ArrivalLaneShape, moves: [(JellyActor, SIMD2<Float>)]) {
        let c = GameCamera.arenaCenter
        let movable = others.filter { $0.brain != nil && $0.brain?.held != true && $0.brain?.commanded != true && $0.brain?.social == nil }
        let fixedOnes = others.filter { o in !movable.contains { $0 === o } }
        func displaced(_ T: SIMD2<Float>, _ l: ArrivalLaneShape) -> [JellyActor] {
            movable.filter { a in
                if l.contains(a.floor) || simd_distance(a.floor, T) < MoveCrowd.gap + 0.2 { return true }
                if case .walk(let goal, _)? = a.brain.map({ $0.script }) { return l.contains(goal) || l.crosses(a.floor, goal) }
                return false
            }
        }
        // his spot: the free candidate with the fewest housemates to move, then the nearest to where the old rule would put him
        var best: (SIMD2<Float>, Float)?
        for p in laneGridFloor(ref, x: (c.x - 1.5)...(c.x + 2.0)) {
            let l = ArrivalLaneShape(z: p.y, spotX: p.x)
            if fixedOnes.contains(where: { l.contains($0.floor) || simd_distance($0.floor, p) < MoveCrowd.gap + 0.2 }) { continue }
            let cost = Float(displaced(p, l).count) * 10 + simd_distance(p, legacy)
            if best == nil || cost < best!.1 { best = (p, cost) }
        }
        if ArrivalLane.lab == "worstmove" { best = (legacy, 0) }          // (lab: keep the old spot so the placement path is exercised)
        let target = best?.0 ?? legacy
        let lane = ArrivalLaneShape(z: target.y, spotX: target.x)
        // free floor for the ones who step aside: right / centre, outside the lane, off his spot, off each other and the ones who stay
        var taken = others.filter { o in !displaced(target, lane).contains { $0 === o } }.map(\.floor) + [target]
        var moves: [(JellyActor, SIMD2<Float>)] = []
        for a in displaced(target, lane).sorted(by: { $0.floor.x < $1.floor.x }) {
            if let p = arrivalSpot(for: a, lane: lane, target: target, ref: ref, taken: taken) { moves.append((a, p)); taken.append(p) }
        }
        return (target, lane, moves)
    }

    /// Free floor right / centre, outside the lane, off his spot, off each other and the ones who stay; nearest to where `a` is.
    func arrivalSpot(for a: JellyActor, lane: ArrivalLaneShape, target: SIMD2<Float>, ref: BlobBrain, taken: [SIMD2<Float>]) -> SIMD2<Float>? {
        let c = GameCamera.arenaCenter
        var cand = laneGridFloor(ref, x: (c.x - 0.5)...(c.x + GameCamera.arenaRadius), step: 0.4).filter { !lane.contains($0) }
        if cand.isEmpty { cand = laneGridFloor(ref, x: (c.x - GameCamera.arenaRadius)...(c.x + GameCamera.arenaRadius), step: 0.4).filter { !lane.contains($0) } }
        for clear in [MoveCrowd.gap + 0.2, 1.2, 0.8] {
            let ok = cand.filter { p in !taken.contains { simd_distance($0, p) < clear } }
            if let p = ok.min(by: { simd_distance($0, a.floor) < simd_distance($1, a.floor) }) { return p }
        }
        return nil
    }

    /// Just before he runs: anybody (awake, free) who is in the lane after all (a long hold, a walk that began late) is sent out of it. True = wait a beat.
    func arrivalClearCheck(_ others: [JellyActor], target: SIMD2<Float>) -> Bool {
        guard let lane = ArrivalLane.active, let ref = others.first?.brain else { return false }
        var taken = others.map(\.floor) + [target]
        var waiting = false
        for a in others {
            guard let b = a.brain, !b.isSleeping, !b.held, !b.commanded, b.social == nil else { continue }
            var inWay = lane.contains(a.floor)
            if case .walk(let goal, _) = b.script, lane.contains(goal) || lane.crosses(a.floor, goal) { inWay = true }
            guard inWay else { continue }
            waiting = true
            if let p = arrivalSpot(for: a, lane: lane, target: target, ref: ref, taken: taken) {
                taken.append(p)
                b.requestNow(.goTo(p))
            }
        }
        return waiting
    }

    /// Behind the curtain: the housemates step aside (placed, they are not seen), the lane is reserved until he has run in.
    func applyArrivalPlan(_ plan: (target: SIMD2<Float>, lane: ArrivalLaneShape, moves: [(JellyActor, SIMD2<Float>)])) {
        ArrivalLane.active = plan.lane
        ArrivalLane.violations = 0
        for (a, p) in plan.moves {
            if a.brain?.isSleeping == true { rehomeAsleep(a, at: p) } else { rehome(a, at: p) }
            NSLog("[arrlane] housemate %d placed (%.1f,%.1f)", a.id, p.x, p.y)
        }
    }

    func endArrivalLane() { ArrivalLane.active = nil }

    /// Dev lab: housemates put where the case says (worst = both in the lane, left of where the old rule puts his spot).
    func arrivalLabPlace(_ others: [JellyActor]) {
        guard let spec = ArrivalLane.lab, let ref = others.first?.brain else { return }
        let c = GameCamera.arenaCenter
        var spots: [SIMD2<Float>] = []
        if spec == "worst" { return }          // (placed after his spot is known: `arrivalLabWorst`)
        else if spec.hasPrefix("rand:"), let seed = UInt64(spec.dropFirst(5)) {
            var s = seed &* 6364136223846793005 &+ 1442695040888963407
            func rnd() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 33) & 0xFFFFFF) / Float(0xFFFFFF) }
            let grid = laneGridFloor(ref, x: (c.x - 3)...(c.x + 3), step: 0.5)
            for _ in others { spots.append(grid.isEmpty ? c : grid[Int(rnd() * Float(grid.count - 1))]) }
        }
        for (a, p) in zip(others, spots) { if a.brain?.isSleeping == true { rehomeAsleep(a, at: p) } else { rehome(a, at: p) } }
        NSLog("[arrlane] lab %@ housemates %@", spec, others.map { String(format: "%d(%.1f,%.1f)", $0.id, $0.floor.x, $0.floor.y) }.joined(separator: " "))
    }

    /// Worst case: the old rule has put his spot at `t`; the housemates stand in the strip he runs along, just left of it.
    func arrivalLabWorst(_ others: [JellyActor], target t: SIMD2<Float>) {
        guard ArrivalLane.lab == "worst" || ArrivalLane.lab == "worstmove", let ref = others.first?.brain else { return }
        let want = [SIMD2<Float>(t.x - 1.0, t.y + 0.2), SIMD2(t.x - 1.0, t.y - 1.0)]
        for (a, p) in zip(others, want) { rehome(a, at: ref.fixed(p)) }
        NSLog("[arrlane] lab worst target=(%.1f,%.1f) housemates %@", t.x, t.y, others.map { String(format: "%d(%.1f,%.1f)", $0.id, $0.floor.x, $0.floor.y) }.joined(separator: " "))
    }
}
