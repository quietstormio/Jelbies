//
//  DiningLineupTests.swift
//  The group lineup is decisive: each diner is given ONE place at the start (never reassigned), walks to it without shuffling, and the tray is out
//  within a bounded time, from the usual start and from wherever the Jellies happened to be wandering.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DiningLineupTests: XCTestCase {
    struct Result { var time: Float; var places: [[Int]]; var detour: Float; var maxRetarget: Int }

    /// `wanderFor`: seconds the other Jellies wander before the serving is asked for (scatters them over the room).
    private func lineup(drink: Bool, wanderFor: Float = 0) -> Result {
        let r = DiningJellyTests.Room(count: 3, wander: wanderFor > 0)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        r.run(max(1, wanderFor))
        for a in r.actors { a.brain?.autonomy = false }
        r.run(0.5)
        let startAt = r.actors.map { $0.floor }
        if drink { r.care.drink() } else { r.care.feed() }
        var seen: [[Int]] = []
        var servedAt: Float?
        var path = [Float](repeating: 0, count: 3), last = startAt
        let t0 = r.t
        r.run(30) {
            let p = r.care.group.placeOf
            if !p.isEmpty, seen.last != p { seen.append(p) }
            for i in 0..<3 { let f = r.actors[i].floor; path[i] += simd_distance(f, last[i]); last[i] = f }
            if r.care.group.state == .serving { servedAt = servedAt ?? r.t; return true }
            return false
        }
        // path walked / straight distance to his approach point (1 = dead straight; a shuffle or detour pushes it up)
        var worst: Float = 0
        if r.care.group.placeOf.count == 3 {
            for i in 0..<3 { let d = max(simd_distance(startAt[i], r.care.group.approachPoint(blob: i)), 0.5); worst = max(worst, path[i] / d) }
        }
        return Result(time: (servedAt ?? 99) - t0, places: seen, detour: worst, maxRetarget: 0)
    }

    private func check(_ name: String, _ l: Result, limit: Float) {
        print("LINEUP \(name) time=\(l.time) detour=\(l.detour) places=\(l.places)")
        XCTAssertEqual(l.places.count, 1, "\(name): nobody is reassigned after the first assignment: \(l.places)")
        XCTAssertLessThan(l.time, limit, "\(name): lineup took \(l.time)s")
        XCTAssertLessThan(l.detour, 3.0, "\(name): walked \(l.detour)x the straight way")
    }

    func testDrinkLineupIsQuickAndNobodyIsReassigned() { check("drink", lineup(drink: true), limit: 8) }
    func testFoodLineupIsQuickAndNobodyIsReassigned() { check("food", lineup(drink: false), limit: 8) }
    func testScatteredJelliesLineUpQuickly() {
        for w: Float in [6, 13, 21] {
            check("drink@\(w)", lineup(drink: true, wanderFor: w), limit: 14)
            check("food@\(w)", lineup(drink: false, wanderFor: w), limit: 14)
        }
    }
}
