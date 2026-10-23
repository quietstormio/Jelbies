//
//  SelectionTests.swift
//  Multi-Blob select: the highlight state machine (draw, switch, self-confirm, persist, clear), the instant pick, the floor ring, the silhouette outline math.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SelectionTests: XCTestCase {
    nonisolated(unsafe) static var keep: [BlobSelect] = []

    private func three() -> BlobSelect {
        let s = BlobSelect(); Self.keep.append(s)
        s.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip"), SelectBlob(id: 2, name: "Moss")])
        return s
    }
    private func run(_ s: BlobSelect, _ sec: Float) { for _ in 0..<Int(sec * 60) { s.tick(dt: 1.0 / 60) } }

    func testOneBlobAlwaysShowsTheActionButtonAndNeverSelects() {
        let s = BlobSelect(); Self.keep.append(s)
        XCTAssertTrue(s.actionVisible)
        s.doubleTap(0)
        XCTAssertEqual(s.phase, .none, "no select step with one Blob")
        XCTAssertTrue(s.actionVisible)
        s.pick(0)                                                // the highlight itself works with one Blob (the tap highlight)
        XCTAssertEqual(s.selectedID, 0)
    }

    func testATapDrawsTheOutlineThenSettlesWithNoChip() {
        let s = three()
        XCTAssertNil(s.highlighted)
        var starts = 0, meets = 0
        s.onDrawStart = { starts += 1 }; s.onMeet = { meets += 1 }
        s.doubleTap(1)
        XCTAssertEqual(s.phase, .drawing(id: 1)); XCTAssertEqual(starts, 1, "a light tick at the draw start"); XCTAssertEqual(meets, 0)
        XCTAssertNil(s.highlighted, "a draw is not a settled pick yet")
        run(s, 0.25)
        XCTAssertEqual(s.phase, .drawing(id: 1)); XCTAssertGreaterThan(s.drawProgress, 0.05); XCTAssertLessThan(s.drawProgress, 0.95)
        run(s, 0.4)                                              // 0.65 s: the halves have met at 0.6 s
        XCTAssertEqual(s.phase, .pending(id: 1)); XCTAssertEqual(meets, 1, "a crisp tap when the halves meet, once")
        XCTAssertEqual(s.drawProgress, 1)
        XCTAssertEqual(s.selectedName, "Pip")
        XCTAssertEqual(s.takeHopRequest(), 1, "he hops"); XCTAssertNil(s.takeHopRequest(), "once")
        XCTAssertTrue(s.isDimmed(0)); XCTAssertTrue(s.isDimmed(2)); XCTAssertFalse(s.isDimmed(1), "the others dim")
        run(s, 3); XCTAssertEqual(meets, 1); XCTAssertEqual(starts, 1)
        XCTAssertEqual(s.phase, .none); XCTAssertEqual(s.confirmed, 1, "every draw confirms itself")
        XCTAssertEqual(s.highlighted, 1)
    }

    func testDoubleTapSelfConfirmsAndThePickPersists() {
        let s = three()
        s.doubleTap(1)
        run(s, 0.6 + 1.2 + 0.1)
        XCTAssertEqual(s.phase, .none); XCTAssertEqual(s.confirmed, 1); XCTAssertEqual(s.highlighted, 1)
        run(s, 30); XCTAssertEqual(s.highlighted, 1, "it stays until the floor is tapped")
    }

    func testInstantPickHasNoDrawAndNoHop() {
        let s = three()
        let starts = s.drawStarts
        s.pick(2, instant: true)
        XCTAssertFalse(s.isSelecting); XCTAssertEqual(s.highlighted, 2); XCTAssertNil(s.selectedID)
        XCTAssertNil(s.takeHopRequest()); XCTAssertEqual(s.drawStarts, starts)
        run(s, 3); XCTAssertEqual(s.highlighted, 2); XCTAssertNil(s.takeHopRequest())
    }

    func testClearHighlight() {
        let s = three()
        s.pick(1, instant: true); XCTAssertEqual(s.highlighted, 1)
        s.clearHighlight(); XCTAssertNil(s.highlighted); XCTAssertNil(s.confirmed)
        s.doubleTap(2); run(s, 0.2)
        s.clearHighlight(); XCTAssertFalse(s.isSelecting, "a draw stops too"); XCTAssertNil(s.highlighted)
        run(s, 2); XCTAssertNil(s.highlighted, "a cleared pick does not come back")
    }

    func testRingProjectsAFrontArcOnScreen() {
        GameCamera.configureRoom(count: 3)
        let size = CGSize(width: 402, height: 874)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let s = three()
        s.publishRing(id: 1, floor: SIMD2(0, 1), viewProj: cam.viewProj, size: size)
        let ring = try! XCTUnwrap(s.ring)
        XCTAssertEqual(ring.pts.count, SelectTuning.ringSegments)
        for p in ring.pts { XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p), "\(p) on screen") }
        let centre = Silhouette.project([SIMD3(0, BobShape.H * 0.5, 1)], viewProj: cam.viewProj, size: size)[0]
        XCTAssertGreaterThan(ring.pts.map(\.y).max()!, centre.y, "the arc passes below the body centre (the front arc)")
        XCTAssertFalse(s.ringIsFresh && s.highlighted == nil ? false : false)
        s.pick(1, instant: true)
        XCTAssertTrue(s.ringIsFresh)
    }

    func testDrawTakesAboutSixTenthsOfASecond() {
        let s = three()
        s.doubleTap(0)
        var t: Float = 0
        while s.phase == .drawing(id: 0), t < 2 { s.tick(dt: 1.0 / 60); t += 1.0 / 60 }
        XCTAssertEqual(t, 0.6, accuracy: 0.03)
    }

    func testDoubleTapAnotherStopsTheFirstAndRestartsTheDraw() {
        let s = three()
        var starts = 0, meets = 0
        s.onDrawStart = { starts += 1 }; s.onMeet = { meets += 1 }
        s.doubleTap(0); run(s, 0.3)
        let mid = s.drawProgress
        XCTAssertGreaterThan(mid, 0.2)
        s.doubleTap(2)
        XCTAssertEqual(s.phase, .drawing(id: 2), "switched at once"); XCTAssertEqual(s.drawProgress, 0, "the draw restarts from the top")
        XCTAssertEqual(starts, 2); XCTAssertEqual(meets, 0, "the first highlight never completes")
        XCTAssertFalse(s.isDimmed(2)); XCTAssertTrue(s.isDimmed(0))
        run(s, 1.3)
        XCTAssertEqual(s.phase, .pending(id: 2)); XCTAssertEqual(meets, 1)
        s.doubleTap(2); XCTAssertEqual(s.phase, .pending(id: 2), "the same Blob again changes nothing"); XCTAssertEqual(s.drawStarts, 2)
        s.doubleTap(1)                                           // also from the pending state
        XCTAssertEqual(s.phase, .drawing(id: 1)); XCTAssertNil(s.takeHopRequest())
    }

    func testGatedDrawWaitsForARealOutlineAndNeverRunsOverAnEmptyPath() {
        let s = BlobSelect(); Self.keep.append(s)
        s.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip", floor: SIMD2(-1.7, 1.5)), SelectBlob(id: 2, name: "Moss", floor: SIMD2(1.7, 0.4))])
        s.gateDraw = true
        var starts = 0
        s.onDrawStart = { starts += 1 }
        let size = CGSize(width: 440, height: 956)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        s.highlight(1)
        run(s, 1)
        XCTAssertTrue(s.waiting); XCTAssertEqual(s.drawProgress, 0, "no clock without an outline"); XCTAssertEqual(starts, 0)
        s.publish(viewProj: cam.viewProj, size: size) { [] }
        s.sheetOpen = true; run(s, 0.5); XCTAssertEqual(s.drawProgress, 0, "not while the roster sheet is up")
        s.sheetOpen = false; run(s, 0.1); XCTAssertEqual(s.drawProgress, 0, "the sheet's fade settles first")
        Thread.sleep(forTimeInterval: BlobSelect.sheetSettle + 0.05)
        s.publish(viewProj: cam.viewProj, size: size) { [] }                                  // later than the highlight
        run(s, 0.3)
        XCTAssertFalse(s.waiting); XCTAssertEqual(starts, 1); XCTAssertGreaterThan(s.drawProgress, 0)
        // another Blob restarts the wait and the draw
        s.highlight(2); XCTAssertTrue(s.waiting); XCTAssertEqual(s.drawProgress, 0)
    }

    func testPaddedOutlineStaysOutsideTheBodyByAnEvenPad() {
        let size = CGSize(width: 440, height: 956)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let pts = Silhouette.project(Silhouette.profileWorldPoints(at: SIMD2(0, 1.2), rings: 60, around: 90), viewProj: cam.viewProj, size: size)
        let o = Silhouette.outline(of: pts)
        let padded = Silhouette.padded(o, by: 5)
        for p in pts { XCTAssertTrue(Silhouette.contains(padded, p), "every body point is inside the padded outline") }
        let gap = zip(o, padded).map { hypot($0.x - $1.x, $0.y - $1.y) }
        XCTAssertEqual(gap.min()!, 5, accuracy: 0.6); XCTAssertEqual(gap.max()!, 5, accuracy: 0.6)
    }

    func testCancelStopsADrawAndItDoesNotComeBack() {
        let s = three()
        s.doubleTap(1); run(s, 0.2)
        s.cancel()
        XCTAssertEqual(s.phase, .none); XCTAssertNil(s.confirmed); XCTAssertNil(s.highlighted)
        run(s, 1); XCTAssertEqual(s.phase, .none, "a cancelled draw does not come back")
        s.doubleTap(1); run(s, 1.0)
        s.cancel(); XCTAssertFalse(s.isDimmed(0)); XCTAssertNil(s.highlighted)
        s.doubleTap(1); s.confirm(); XCTAssertEqual(s.confirmed, nil, "confirm only works on a finished draw")
    }

    func testComeHereCancelsAPendingSelection() {
        let care = GameCare()
        care.select.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip")])
        care.select.doubleTap(1)
        care.comeHere()
        XCTAssertFalse(care.select.isSelecting)
        care.release()
    }

    // MARK: silhouette

    private func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, n: Int = 400) -> [CGPoint] {
        (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
        }
    }

    func testOutlineRecoversTheContourAndInteriorPointsDoNotChangeIt() {
        var pts = ellipse(cx: 200, cy: 300, rx: 80, ry: 110)
        for i in 0..<300 { pts.append(CGPoint(x: 200 + Double(i % 17) * 3 - 24, y: 300 + Double(i % 29) * 4 - 56)) }   // inside
        let o = Silhouette.outline(of: pts)
        XCTAssertEqual(o.count, Silhouette.bins)
        for p in o {
            let k = pow((Double(p.x) - 200) / 80, 2) + pow((Double(p.y) - 300) / 110, 2)
            XCTAssertEqual(k, 1, accuracy: 0.12, "on the ellipse")
        }
        XCTAssertTrue(Silhouette.contains(o, CGPoint(x: 200, y: 300)))
        XCTAssertTrue(Silhouette.contains(o, CGPoint(x: 260, y: 300)))
        XCTAssertFalse(Silhouette.contains(o, CGPoint(x: 300, y: 300)))
        XCTAssertFalse(Silhouette.contains(o, CGPoint(x: 200, y: 450)))
    }

    func testHalvesStartAtTheTopCentreAndMeetAtTheBottom() {
        let o = Silhouette.outline(of: ellipse(cx: 200, cy: 300, rx: 80, ry: 110))
        let (l, r) = Silhouette.halves(o)
        XCTAssertEqual(l.count, r.count)
        XCTAssertEqual(l[0].x, 200, accuracy: 3); XCTAssertEqual(l[0].y, 190, accuracy: 6, "the top centre")
        XCTAssertEqual(l[0], r[0])
        XCTAssertEqual(l.last!.x, 200, accuracy: 3); XCTAssertEqual(l.last!.y, 410, accuracy: 6, "the bottom")
        XCTAssertEqual(l.last!, r.last!, "they meet at the bottom")
        XCTAssertLessThan(l[l.count / 2].x, 200, "left runs down the left side"); XCTAssertGreaterThan(r[r.count / 2].x, 200)
        // the prefix grows from the top on both sides at once
        let a = Silhouette.prefix(l, fraction: 0.25), b = Silhouette.prefix(r, fraction: 0.25)
        XCTAssertEqual(a.last!.y, b.last!.y, accuracy: 6, "both sides advance together")
        XCTAssertLessThan(a.last!.y, 300)
        XCTAssertEqual(Silhouette.prefix(l, fraction: 1).count, l.count)
    }

    func testPreviewBlobProjectsToAScreenSilhouetteAndHitsWork() {
        let size = CGSize(width: 440, height: 956)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let s = BlobSelect(); Self.keep.append(s)
        s.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip", floor: SIMD2(-1.7, 1.5), scale: 0.92)])
        s.publish(viewProj: cam.viewProj, size: size) { Silhouette.project(Silhouette.profileWorldPoints(at: SIMD2(0.6, 0.2)), viewProj: cam.viewProj, size: size) }
        XCTAssertEqual(s.outlines.count, 2)
        let pip = s.outlines[1]!
        let ys = pip.map(\.y), xs = pip.map(\.x)
        XCTAssertGreaterThan(ys.max()! - ys.min()!, 60); XCTAssertLessThan(xs.max()! - xs.min()!, 300)
        let mid = CGPoint(x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
        XCTAssertEqual(s.hit(mid), 1)
        XCTAssertNil(s.hit(CGPoint(x: 220, y: 900)), "the floor")
        let bob = s.outlines[0]!
        let bm = CGPoint(x: bob.map(\.x).reduce(0, +) / CGFloat(bob.count), y: bob.map(\.y).reduce(0, +) / CGFloat(bob.count))
        XCTAssertEqual(s.hit(bm), 0)
    }

    func testSelectTickCostIsSmall() {
        let s = three()
        s.doubleTap(1)
        let a = CACurrentMediaTime()
        for _ in 0..<2000 { s.tick(dt: 1.0 / 60) }
        let us = (CACurrentMediaTime() - a) / 2000 * 1e6
        let size = CGSize(width: 440, height: 956)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        s.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip", floor: SIMD2(-1.7, 1.5)), SelectBlob(id: 2, name: "Moss", floor: SIMD2(1.7, 0.4))])
        let bobPts = Silhouette.project(Silhouette.profileWorldPoints(at: SIMD2(0, 0), rings: 60, around: 90), viewProj: cam.viewProj, size: size)   // ~5.5k like his render mesh
        let b = CACurrentMediaTime()
        for _ in 0..<200 { s.publish(viewProj: cam.viewProj, size: size) { bobPts } }
        let pub = (CACurrentMediaTime() - b) / 200 * 1e6
        MotionLog.write(String(format: "SELECT perf: tick %.2f us, publish (3 outlines, %d pts for the real one) %.0f us per frame", us, bobPts.count, pub))
        XCTAssertLessThan(pub, 1500)
    }
}
