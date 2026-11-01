import XCTest
import simd
@testable import BobV1

/// The route planner's probe budget (BlobBrain.planRoute): routes round obstacles are still found, and a search never exceeds its probe budget.
final class PlannerBudgetTests: XCTestCase {
    /// A brain on a floor with round keep-out discs (resolve pushes a point out of any disc, like the room's obstacles).
    private func brain(discs: [(c: SIMD2<Float>, r: Float)]) -> BlobBrain {
        let b = BlobBrain()
        b.resolve = { p, fp in
            var q = SIMD2(p.x, p.z)
            for d in discs { let v = q - d.c, L = simd_length(v); if L < d.r + fp { q = d.c + (L > 1e-4 ? v / L : SIMD2(1, 0)) * (d.r + fp) } }
            return SIMD3(q.x, p.y, q.y)
        }
        return b
    }

    private func routeIsClear(_ b: BlobBrain, _ a: SIMD2<Float>, _ goal: SIMD2<Float>, _ r: [SIMD2<Float>]) -> Bool {
        var p = a
        for q in r + [goal] { if !b.legClear(p, q, margin: b.steerMargin) { return false }; p = q }
        return true
    }

    func testRoutesAroundObstaclesStillFoundWithinBudget() {
        // (a Jelbie's keep-out is footprint 0.55 + margin round each disc: these are furniture-sized obstacles for a 3 m walk)
        let layouts: [[(c: SIMD2<Float>, r: Float)]] = [
            [(SIMD2(0, 0), 0.1)],
            [(SIMD2(0, 0), 0.1), (SIMD2(0.5, 0.3), 0.1)],
            [(SIMD2(0, 0.1), 0.15), (SIMD2(-0.7, 0), 0.1)],
            [(SIMD2(0.2, 0), 0.2)],
        ]
        var misses = 0
        defer { XCTAssertLessThanOrEqual(misses, 1, "at most one of four layouts may need more than the per-search budget") }
        for (i, discs) in layouts.enumerated() {
            let b = brain(discs: discs)
            let a = SIMD2<Float>(-1.5, 0), goal = SIMD2<Float>(1.5, 0)
            BlobBrain.stepProbeBudget = BlobBrain.probesPerStep
            let r = b.planRoute(a, goal, depth: 2)
            let saved = BlobBrain.probesPerSearch; BlobBrain.probesPerSearch = 1_000_000; BlobBrain.stepProbeBudget = 1_000_000
            let b2 = brain(discs: discs); let unlimited = b2.planRoute(a, goal, depth: 2); let usedUnlimited = b2.probeCount
            BlobBrain.probesPerSearch = saved
            print("PLANNER layout \(i): budgeted \(r.map { "\($0.count) corners" } ?? "nil") in \(b.probeCount) probes; unlimited \(unlimited.map { "\($0.count) corners" } ?? "nil") in \(usedUnlimited) probes")
            // a layout is only allowed to miss its route when the unlimited search itself needed more probes than the budget (the search is cut, the Jelbie tries again later)
            if r == nil { XCTAssertGreaterThan(usedUnlimited, BlobBrain.probesPerSearch, "layout \(i): no route although the budget was enough"); misses += 1 }
            if let r { XCTAssertTrue(routeIsClear(b, a, goal, r), "layout \(i): every leg of the route is clear") }
            XCTAssertLessThanOrEqual(b.probeCount, BlobBrain.probesPerSearch + 300, "layout \(i): search stayed near its budget")
        }
        BlobBrain.stepProbeBudget = Int.max / 2
    }

    func testBlockedSearchIsCutShort() {
        let b = brain(discs: [(SIMD2(0, 0), 50)])          // a wall of floor: no way round
        BlobBrain.stepProbeBudget = BlobBrain.probesPerStep
        let r = b.planRoute(SIMD2(-60, 0), SIMD2(60, 0), depth: 2)
        XCTAssertNil(r)
        XCTAssertLessThan(b.probeCount, 2 * BlobBrain.probesPerSearch, "a hopeless search is cut at its budget (was thousands of probes)")
        BlobBrain.stepProbeBudget = Int.max / 2
    }
}
