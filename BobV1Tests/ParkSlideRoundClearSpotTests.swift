//
//  ParkSlideRoundClearSpotTests.swift
//  park-slide-r2, T3: `ParkClearSpot` (BobV1/Park/ParkClearSpot.swift) and the pickers that use it (zoomies goal, trot from standing, group hug ring). Same lab as ParkSlideRoundTests.
//

import XCTest
import simd
@testable import BobV1

extension ParkSlideRoundTests {
    /// `ParkClearSpot`: a point inside a solid park piece (slide, seesaw, flower bed, bench, pond) comes out clear, on the roam floor; a clear point comes back EXACTLY unchanged (hopscotch is flat: not solid); at home all.
    func testParkTargetsStayOutOfSolidPieces() {
        for (aname, aspect) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
            let lab = parkLab(n: 1, seed: 3, aspect: aspect)
            let fp = lab.rigs[0].brain.footprint
            print("PSR T3 \(aname) pieces: " + DecorField.shared.feet.map { "\($0.kind) uid \($0.uid) solid \($0.spec.solid) at \($0.centre)" }.joined(separator: "; "))
            var moved = 0, same = 0, worstMove: Float = 0, stillBlocked = 0, offFloor = 0, clearMoved = 0
            var x: Float = -6
            while x <= 6 {
                var z: Float = -5
                while z <= 4.6 {
                    let p = SIMD2<Float>(x, z)
                    if let rf = GameCamera.roamFloor, z < rf.minZ || z > rf.maxZ || abs(x) > rf.halfWidth(at: z) { z += 0.1; continue }          // (the grid is the roam floor: a pick is never off it)
                    let q = ParkClearSpot.clear(p, radius: fp)
                    if q == p { same += 1 }
                    else {
                        moved += 1
                        worstMove = max(worstMove, simd_distance(p, q))
                        if !ParkClearSpot.blocked(p, radius: fp) { clearMoved += 1 }
                        if ParkClearSpot.blocked(q, radius: fp) { stillBlocked += 1 }
                        let c = GameCamera.constrain(SIMD3(q.x, 0, q.y), radius: fp, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: nil)
                        if simd_distance(SIMD2(c.x, c.z), q) > 0.02 { offFloor += 1 }
                    }
                    z += 0.1
                }
                x += 0.1
            }
            print("PSR T3 \(aname) grid: unchanged \(same), moved \(moved), biggest move \(worstMove), clear points that moved \(clearMoved), moved points still blocked \(stillBlocked), off the roam floor after \(offFloor)")
            XCTAssertEqual(clearMoved, 0, "\(aname): a clear point is returned unchanged")
            XCTAssertEqual(stillBlocked, 0, "\(aname): every moved point comes out clear")
            XCTAssertEqual(offFloor, 0, "\(aname): every moved point is on the roam floor")
            XCTAssertGreaterThan(moved, 100, "\(aname): the pieces block some floor")
            let sl = DecorField.shared.foot(ParkToys.slideUID)!, ss = DecorField.shared.foot(ParkToys.seesawUID)!
            let named: [(String, SIMD2<Float>)] = [("slide centre", sl.centre), ("slide (2.62,-0.50)", SIMD2(2.62, -0.50)), ("slide (2.71,0.40)", SIMD2(2.71, 0.40)), ("slide (3.86,-0.75)", SIMD2(3.86, -0.75)), ("seesaw centre", ss.centre), ("flower bed", SIMD2(-3.5, -4.35)), ("bench", SIMD2(0, -4.55)), ("pond", SIMD2(3.5, -4.2))]
            for (name, p) in named {
                let q = ParkClearSpot.clear(p, radius: fp)
                print("PSR T3 \(aname) \(name): raw \(p) -> used \(q) (moved \(simd_distance(p, q)))")
                XCTAssertNotEqual(q, p, "\(aname) \(name) is inside a solid piece and moves")
                XCTAssertFalse(ParkClearSpot.blocked(q, radius: fp), "\(aname) \(name): the used point is clear")
            }
            // the hopscotch court (flat, a keep-out for the helper); seesaw AND court are both there now
            print("PSR T3 \(aname) keep-outs the helper sees: " + ParkClearSpot.keepOuts().joined(separator: "; "))
            XCTAssertNotNil(DecorField.shared.foot(ParkToys.hopscotchUID), "the court stands in the park")
            if let hf = DecorField.shared.foot(ParkToys.hopscotchUID) {
                let q = ParkClearSpot.clear(hf.centre, radius: fp)
                print("PSR T3 \(aname) court centre \(hf.centre) -> \(q) (solid \(hf.spec.solid))")
                XCTAssertNotEqual(q, hf.centre, "a point in the middle of the court moves out of it")
                XCTAssertGreaterThanOrEqual(hf.distance(q), 0, "and ends outside the court")
                XCTAssertFalse(ParkClearSpot.blocked(q, radius: fp))
            }
        }
        // home: every point unchanged
        RoomLayout.apply(RoomCatalog.home); GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: Self.portrait)
        DecorField.shared.clear(); DecorField.shared.set([PlacedDecor(uid: 7, kind: .slide, x: 1.0, z: -0.2, turns: nil)])
        var changed = 0, tested = 0
        var hx: Float = -3
        while hx <= 3 { var hz: Float = -2; while hz <= 3 { let p = SIMD2<Float>(hx, hz); tested += 1; if ParkClearSpot.clear(p, radius: 0.55) != p { changed += 1 }; hz += 0.1 }; hx += 0.1 }
        print("PSR T3 home: \(tested) points, changed \(changed)")
        XCTAssertEqual(changed, 0, "at home every point is returned unchanged")
    }

    /// The three pickers, with a raw target forced inside the slide: the target they end with is outside it.
    func testForcedTargetsEndOutsideTheSlide() {
        for (aname, aspect) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
            // zoomies run with a goal inside the slide
            do {
                let lab = parkLab(n: 1, seed: 4, aspect: aspect)
                let sl = DecorField.shared.foot(ParkToys.slideUID)!, bx = box(sl)
                let r = lab.rigs[0], b = r.brain
                place(r, SIMD2(0.6, 1.0)); for _ in 0..<5 { lab.tick(watching: false) }
                let raw = SIMD2<Float>(2.62, -0.50)
                XCTAssertGreaterThan(insideDepth(bx, raw), 0.2)
                let ok = b.idleStart(.zoomies, r.sim, goal: raw)
                let used = b.idleState.target
                print("PSR T3 \(aname) zoomies: started \(ok) raw \(raw) -> used \(used) (depth inside the box \(insideDepth(bx, used)), blocked \(ParkClearSpot.blocked(used, radius: b.footprint)))")
                XCTAssertTrue(ok)
                XCTAssertEqual(insideDepth(bx, used), 0, "\(aname): the zoomies goal is outside the slide")
                XCTAssertFalse(ParkClearSpot.blocked(used, radius: b.footprint), "\(aname): the zoomies goal is clear")
                b.abortAll(r.sim, r.skinner)
            }
            // trot from standing, facing the slide
            do {
                let lab = parkLab(n: 1, seed: 4, aspect: aspect)
                let sl = DecorField.shared.foot(ParkToys.slideUID)!, bx = box(sl)
                let r = lab.rigs[0], b = r.brain
                place(r, SIMD2(0.9, 1.0)); for _ in 0..<5 { lab.tick(watching: false) }
                b.yaw = .pi / 2
                let raw = b.position + SIMD2(sinf(b.yaw), cosf(b.yaw)) * 2.2
                XCTAssertGreaterThan(insideDepth(bx, raw), 0.3)
                let ok = b.flourishStart(.trot, resume: nil, r.sim, r.skinner)
                let used = b.idleState.target
                print("PSR T3 \(aname) trot: started \(ok) raw \(raw) -> used \(used) (depth inside the box \(insideDepth(bx, used)))")
                XCTAssertTrue(ok)
                XCTAssertEqual(insideDepth(bx, used), 0, "\(aname): the trot goal is outside the slide")
                b.abortAll(r.sim, r.skinner)
            }
            // group hug: three bodies on the slide's left, the ring and its centre stay clear of it
            do {
                let lab = parkLab(n: 3, seed: 4, aspect: aspect, starts: [SIMD2(1.2, -0.2), SIMD2(1.2, 0.6), SIMD2(0.5, 0.2)])
                let sl = DecorField.shared.foot(ParkToys.slideUID)!, bx = box(sl)
                for r in lab.rigs { r.brain.restTimer = 1e6 }
                let b = lab.rigs[0].brain
                let ok = b.socialStartGroup(.groupHug, with: [lab.rigs[1].brain, lab.rigs[2].brain], lab.rigs[0].sim)
                var worst: Float = 0
                var c = SIMD2<Float>.zero
                if let s = b.social {
                    c = s.home0
                    for (_, p) in s.slotSpot { worst = max(worst, insideDepth(bx, p)) }
                    worst = max(worst, insideDepth(bx, s.home0))
                }
                print("PSR T3 \(aname) groupHug: started \(ok) centre \(c) ring r \(String(describing: b.social?.ringR)) deepest ring spot / centre inside the box \(worst)")
                XCTAssertTrue(ok)
                XCTAssertEqual(worst, 0, "\(aname): the hug's ring is outside the slide")
                for r in lab.rigs { r.brain.abortAll(r.sim, r.skinner) }
            }
        }
    }
}
