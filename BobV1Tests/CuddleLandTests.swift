import XCTest
import simd
@testable import BobV1

/// The landscape cuddle close-up (2026-11-22): closer on a phone on its side; portrait, a square window and tablets exactly as before.
final class CuddleLandTests: XCTestCase {
    func testPortraitAndSquareAndTabletUnchanged() {
        for a: Float in [0.46, 0.56, 0.75, 1.0, 1.33, 1.5] {
            let rows = GameCamera.focusRowSpots(count: 3)
            let n = GameCamera.focusPose(aspect: a, spots: rows), o = GameCamera.focusPose(aspect: a, spots: rows, closeUp: false)
            XCTAssertEqual(n.eye, o.eye, "aspect \(a) eye"); XCTAssertEqual(n.target, o.target, "aspect \(a) target")
            let n1 = GameCamera.focusPose(aspect: a), o1 = GameCamera.focusPose(aspect: a, closeUp: false)
            XCTAssertEqual(n1.eye, o1.eye); XCTAssertEqual(n1.target, o1.target)
        }
    }
    func testPhoneLandscapeFillsTheWidth() {
        let a: Float = 2.17
        for n in 1...3 {
            let spots = GameCamera.focusRowSpots(count: n)
            let rows = GameCamera.projectRow(spots: spots, aspect: a), new = GameCamera.focusPose(aspect: a, spots: spots), old = GameCamera.focusPose(aspect: a, spots: spots, closeUp: false)
            XCTAssertLessThan(simd_distance(new.eye, new.target), simd_distance(old.eye, old.target), "closer than before (\(n))")
            // project with the NEW pose
            let vp = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: a, near: 0.3, far: 60), M4.lookAt(eye: new.eye, at: new.target, up: SIMD3(0, 1, 0)))
            func scr(_ w: SIMD3<Float>) -> SIMD2<Float> { let c = vp * SIMD4<Float>(w.x, w.y, w.z, 1); return SIMD2(c.x / c.w * 0.5 + 0.5, 0.5 - c.y / c.w * 0.5) }
            var lo: Float = 9, hi: Float = -9, tall: Float = 0
            for s in spots {
                let l = scr(SIMD3(s.x - BobShape.R, 0.5, s.y)).x, r = scr(SIMD3(s.x + BobShape.R, 0.5, s.y)).x
                lo = min(lo, l); hi = max(hi, r)
                tall = max(tall, scr(SIMD3(s.x, 0, s.y)).y - scr(SIMD3(s.x, BobShape.H, s.y)).y)
            }
            XCTAssertLessThanOrEqual(tall, 0.62, "tallest body \(n)")
            if n == 3 { XCTAssertGreaterThan(hi - lo, 0.5); XCTAssertLessThan(hi - lo, 0.7) }
            _ = rows
        }
    }
}
