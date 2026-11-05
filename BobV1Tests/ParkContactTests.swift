//
//  ParkContactTests.swift
//  The ring / circle / group touching emotes in the PARK's geometry (2026-11-04, r4-park-fix): the park's open play floor (GameCamera.configurePark: no roaming polygon, a rect
//  -3.5...3.5 x -3.4...4.5, no walls near the cast), its colliders (spring rider, sandbox, bench, pond) and a visitor with wings / a daisy beside the Jelbie.
//  Real-app park captures showed a body of a circle dance / group hug FLUNG across the park (4 m away, bodies 2.5 m apart in the hold) where the room's walls had hidden the same push.
//  Every frame: the ring members stay within the ring of the session (+ one hop), nobody ends up a visitor-length away, feet stay attached.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkContactTests: XCTestCase {
    override func setUp() {
        ContactField.reset(); ContactField.enabled = true; FeatureClip.enabled = true
        RoomLayout.apply(RoomCatalog.park)
        GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        // the park's solid toys near the play floor (ParkToys: spring rider (2.7, 1.2) half 0.5 x 0.55, sandbox (2.9, -1.5) half 1.25 x 0.9)
        RoomLayout.dynamicBoxes = [.init(centre: SIMD2(2.7, 1.2), half: SIMD2(0.5, 0.55), height: 0.95), .init(centre: SIMD2(2.9, -1.5), half: SIMD2(1.25, 0.9), height: 0.22)]
    }
    override func tearDown() {
        ContactField.reset(); ContactField.enabled = true; FeatureClip.eggs = []
        RoomLayout.dynamicBoxes = []; RoomLayout.apply(RoomCatalog.home)
        GameCamera.endPark(count: 1); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// The demo's park cast: the Jelbie + two visitors (wings, daisy) spread across the play floor as the app's capture places them.
    private func group(_ kind: SocialKind, features: [JellyFeature] = [.none, .wings, .daisy]) -> (worst: Float, minGap: Float, holdMed: [Float], ok: Bool, d: FeatureClipTests.Duo) {
        let n = features.count
        let pos: [SIMD2<Float>] = n == 2 ? [SIMD2(-1.3, 1.2), SIMD2(1.3, 1.25)] : [SIMD2(-1.8, 1.2), SIMD2(0.1, 1.3), SIMD2(1.3, 0.8)]
        let d = FeatureClipTests.Duo(positions: pos, features: features, seed: 31)
        d.place(pos)
        d.live = true
        for _ in 0..<3 { d.tick() }
        for r in d.lab.rigs { r.brain.anticsEnabled = true }
        let lead = d.lab.rigs[0]
        let ok = n > 2 ? lead.brain.socialStartGroup(kind, with: d.lab.rigs.dropFirst().map { $0.brain }, lead.sim) : lead.brain.socialStart(kind, with: d.lab.rigs[1].brain, lead.sim)
        XCTAssertTrue(ok, "\(kind) starts in the park")
        var worst: Float = 0, minGap: Float = .infinity
        var hold: [[Float]] = Array(repeating: [], count: n * n)
        var home0: SIMD2<Float>?, ringR: Float = 0
        var f = 0
        while f < 60 * 40 {
            d.tick(); f += 1
            if let s = lead.brain.social { if home0 == nil { home0 = s.home0; ringR = s.ringR } }
            if let h = home0, let ph = lead.brain.social?.phase, ph >= 2 {          // (the hold: the walk-in is not the ring yet)
                for r in d.lab.rigs { worst = max(worst, simd_distance(r.brain.position, h) - ringR) }
            }
            for i in 0..<n { for j in (i + 1)..<n { if let g = ContactField.gap(i, j, features: true) { minGap = min(minGap, g); if lead.brain.social?.phase == 2 { hold[i * n + j].append(g) } } } }
            if !d.lab.anySocial && f > 10 { break }
        }
        let med = (0..<n).flatMap { i in ((i + 1)..<n).map { j -> Float in let v = hold[i * n + j].sorted(); return v.isEmpty ? .nan : v[v.count / 2] } }
        MotionLog.write(String(format: "PARKCONTACT %@ x%d: ended=%d at %.1f s, farthest member beyond the ring %.2f m, min gap %.1f cm, hold medians (cm) %@", kind.rawValue, n, d.lab.anySocial ? 0 : 1, Float(f) / 60, worst, minGap * 100, "\(med.map { Int($0 * 100) })"))
        return (worst, minGap, med, !d.lab.anySocial, d)
    }

    func testCircleDanceInThePark() {
        let r = group(.circleDance)
        XCTAssertTrue(r.ok, "the circle dance ends by itself")
        XCTAssertLessThan(r.worst, 0.9, "nobody is carried out of the ring (the real-app park capture: 4 m out, hold 2.2 - 2.8 m)")
        XCTAssertTrue(r.holdMed.allSatisfy { $0 < 0.6 }, "the ring is closed in the hold (medians \(r.holdMed))")
        r.d.lab.checkAll("park circleDance", plainBound: 0.03)
    }
    func testGroupHugInThePark() {
        let r = group(.groupHug)
        XCTAssertTrue(r.ok, "the group hug ends by itself")
        XCTAssertLessThan(r.worst, 0.5, "nobody is carried out of the ring")
        XCTAssertTrue(r.holdMed.allSatisfy { $0 < 0.6 }, "the huddle is closed in the hold (medians \(r.holdMed))")
        r.d.lab.checkAll("park groupHug", plainBound: 0.03)
    }
    func testRingAroundInThePark() {
        let r = group(.ringAround, features: [.none, .wings])
        XCTAssertTrue(r.ok, "the ring dance ends by itself")
        r.d.lab.checkAll("park ringAround", plainBound: 0.03)
    }
}
