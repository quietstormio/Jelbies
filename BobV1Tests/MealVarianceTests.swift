//
//  MealVarianceTests.swift
//  Meal variance (feeding-old-r1, 2026-11-18): the three diners do not eat in lockstep. Each has his own start delay, pace and pauses (timing), and each bite plays a variant
//  (chew / after-bite / finish, or the gulp variants of a drink) that no neighbour plays at the same moment. The whole meal stays within +20 % of the lockstep one.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealVarianceTests: XCTestCase {
    private var savedHour: Double?
    private var savedPick: (([SIMD2<Float>]) -> SIMD2<Float>?)?
    override func setUp() {
        savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12
        DiningGroup.homeSeats = 3; DiningGroup.varianceSeed = 424242
        savedPick = DiningSpot.pickOpen; DiningSpot.pickOpen = { $0.first }          // (the same tray spot every run)
    }
    override func tearDown() {
        DayClock.shared.forcedHour = savedHour; DiningGroup.variance = true; DiningGroup.varianceSeed = nil
        if let savedPick { DiningSpot.pickOpen = savedPick }
    }

    struct Take { var chomps: [Int: [Float]] = [:]; var end: Float = 0; var chewSets: [Int: Set<Int>] = [:]; var afterSets: [Int: Set<Int>] = [:]; var clashes = 0; var overlapTicks = 0 }

    private func take(drink: Bool, variance: Bool) -> Take {
        DiningGroup.variance = variance
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for i in 0..<3 { r.care.needs(for: i).set(drink ? .thirst : .hunger, 0.1) }
        r.run(1)
        let t0 = r.t
        if drink { r.care.drink("water") } else { r.care.feed("berries") }
        var tk = Take()
        var wasLanded = [Bool](repeating: false, count: 3), lastK = [Int](repeating: 0, count: 3)
        r.run(120) {
            var inChew: [(id: Int, c: Int, a: Int)] = []
            for a in r.actors {
                guard let b = a.brain, case .dine = b.job ?? .goTo(.zero) else {
                    if let b = a.brain, case .sip = b.job ?? .goTo(.zero) { self.sample(b, a.id, drink: true, r, &tk, &wasLanded, &lastK, &inChew) }
                    continue
                }
                self.sample(b, a.id, drink: false, r, &tk, &wasLanded, &lastK, &inChew)
            }
            if inChew.count > 1 {
                tk.overlapTicks += 1
                for x in 0..<inChew.count { for y in (x + 1)..<inChew.count where inChew[x].c == inChew[y].c || (!drink && inChew[x].a == inChew[y].a) { tk.clashes += 1 } }
            }
            return r.t > t0 + 2 && !r.care.trayOut
        }
        tk.end = r.t - t0
        return tk
    }
    private func sample(_ b: BlobBrain, _ id: Int, drink: Bool, _ r: DiningJellyTests.Room, _ tk: inout Take, _ wasLanded: inout [Bool], _ lastK: inout [Int], _ inChew: inout [(id: Int, c: Int, a: Int)]) {
        if drink {
            if b.dine.k != lastK[id] { tk.chomps[id, default: []].append(r.t); lastK[id] = b.dine.k }          // (a gulp k change)
        } else {
            if b.dine.landed && !wasLanded[id] { tk.chomps[id, default: []].append(r.t) }          // (the bite lands in the mouth: the chomp moment, rising edge)
            wasLanded[id] = b.dine.landed
        }
        XCTAssertFalse(b.armCapsuleOut && b.armPathActive, "no double arm")
        if b.dine.phase == .chew {
            inChew.append((id, b.dine.chewV, b.dine.afterV))
            tk.chewSets[id, default: []].insert(b.dine.chewV); tk.afterSets[id, default: []].insert(b.dine.afterV)
        }
    }

    private func check(drink: Bool) {
        let lock = take(drink: drink, variance: false)
        let v = take(drink: drink, variance: true)
        XCTAssertEqual(v.chomps.count, 3, "three diners chomped \(v.chomps)")
        // each pair: the k-th chomp moments differ by >= 0.12 s on average, and not within 0.05 s on more than 1 of the bites
        for (a, b) in [(0, 1), (0, 2), (1, 2)] {
            guard let ta = v.chomps[a], let tb = v.chomps[b] else { continue }
            let n = min(ta.count, tb.count, 3)
            XCTAssertGreaterThan(n, 0)
            let d = (0..<n).map { abs(ta[$0] - tb[$0]) }
            XCTAssertGreaterThanOrEqual(d.reduce(0, +) / Float(max(n, 1)), 0.25, "pair \(a)-\(b) average gap \(d)")
            XCTAssertGreaterThanOrEqual(abs(ta[0] - tb[0]), 0.25, "pair \(a)-\(b) FIRST chomp / gulp moments \(ta[0]) \(tb[0])")
            XCTAssertLessThanOrEqual(d.filter { $0 < 0.05 }.count, 1, "pair \(a)-\(b) within 0.05 s on \(d.filter { $0 < 0.05 }.count) bites: \(d)")
        }
        XCTAssertLessThanOrEqual(v.end, lock.end * 1.2, "meal end \(v.end) vs lockstep \(lock.end)")
        XCTAssertEqual(v.clashes, 0, "two neighbours played the same variant at the same moment (\(v.overlapTicks) overlapping ticks)")
        for id in 0..<3 {
            XCTAssertGreaterThanOrEqual(v.chewSets[id]?.count ?? 0, 2, "diner \(id) used \(v.chewSets[id] ?? []) chew variants")
            if !drink { XCTAssertGreaterThanOrEqual(v.afterSets[id]?.count ?? 0, 2, "diner \(id) used \(v.afterSets[id] ?? []) after-bite variants") }
        }
        // the lockstep take (variance off) is what it was: all variants 0
        for id in 0..<3 { XCTAssertEqual(lock.chewSets[id] ?? [0], [0]); XCTAssertEqual(lock.afterSets[id] ?? [0], [0]) }
    }

    func testFoodChompsAreVariedAndNeighboursNeverMatch() { check(drink: false) }

    /// The late middle from the front (the meal1b case): diner 0 starts at z 6 and is given the middle place behind the tray; the others stand at their ends. The tray does not pop while he is on his way:
    /// he stands at his place when it pops, all three eat WITH each other (nobody starts after another has been released), and nobody touches the tray box.
    func testLateMiddleFromTheFrontReachesHisPlaceBeforeTheTray() {
        DiningGroup.variance = true
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
        r.run(1)
        let pts: [SIMD2<Float>] = [SIMD2(0, 6), SIMD2(-1.5, -0.5), SIMD2(1.5, -0.5)]
        for (k, a) in r.actors.enumerated() { a.brain?.abortScript(a.sim, a.skinner); a.sim.teleport(toXZ: pts[k]); a.brain?.currentPose(a.sim) }
        r.run(0.5)
        let t0 = r.t
        r.care.feed("berries")
        var popT: Float?, standDistAtPop: Float = 9
        var firstEat = [Float?](repeating: nil, count: 3), released = [Float?](repeating: nil, count: 3)
        r.run(60) {
            if popT == nil, r.care.dining.isPresent, r.care.group.isActive {
                popT = r.t - t0
                // diner 0's distance to his own stand (the middle one) the moment the tray is out
                if let st = r.care.dining.places.indices.map({ r.care.dining.places[$0].stand }).min(by: { abs($0.x - r.actors[0].floor.x) < abs($1.x - r.actors[0].floor.x) }) { standDistAtPop = simd_distance(r.actors[0].floor, st) }
            }
            for a in r.actors {
                if firstEat[a.id] == nil, a.brain?.activity == .eating { firstEat[a.id] = r.t - t0 }
                if released[a.id] == nil, firstEat[a.id] != nil, !r.care.group.isHolding(a.id) { released[a.id] = r.t - t0 }
            }
            return r.t > t0 + 2 && !r.care.trayOut
        }
        XCTAssertNotNil(popT, "the tray came out")
        XCTAssertLessThan(standDistAtPop, 0.5, "the late diner stood at (or at his place's end of) his walk when the tray popped: \(standDistAtPop)")
        XCTAssertTrue(firstEat.allSatisfy { $0 != nil }, "all three ate \(firstEat)")
        let lastStart = firstEat.compactMap { $0 }.max() ?? 0
        let firstRelease = released.compactMap { $0 }.min() ?? 99
        XCTAssertLessThan(lastStart, firstRelease, "everybody ate with the others: the last started at \(lastStart), the first was released at \(firstRelease)")
        XCTAssertEqual(r.care.group.inBoxTicks, 0, "nobody touched the tray box")
    }
    func testDrinkGulpsAreVariedAndNeighboursNeverMatch() { check(drink: true) }
}
