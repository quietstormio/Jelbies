//
//  CongaTreatNoSinkTests.swift
//  The treat conga line (congaLine) with three bodies: followers never pass into each other (skin gap with features, every pair, every frame >= -1 cm),
//  and the session is not longer than before (`oldSeconds` = the code of 32883e82, same seeds; within +10%).
//
import XCTest
import simd
@testable import BobV1

@MainActor
final class CongaTreatNoSinkTests: XCTestCase {
    override func setUp() {
        DayClock.shared.forcedHour = 12
        ContactField.reset(); ContactField.enabled = true; FeatureClip.enabled = true
        RoomLayout.apply(RoomCatalog.park)
        GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        RoomLayout.dynamicBoxes = []
    }
    override func tearDown() {
        DayClock.shared.forcedHour = 12
        ContactField.reset(); ContactField.enabled = true; FeatureClip.eggs = []
        RoomLayout.dynamicBoxes = []; RoomLayout.apply(RoomCatalog.home)
        GameCamera.endPark(count: 1); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// Session seconds of the old code, per seed (31, 32, 33).
    static let oldSeconds: [Float] = [11.32, 12.62, 10.93]

    func testTreatCongaNeverCrosses() {
        let layouts: [[SIMD2<Float>]] = [[SIMD2(-2.2, 1.2), SIMD2(0.1, 1.3), SIMD2(2.4, 0.9)], [SIMD2(-2.4, 0.2), SIMD2(-0.6, 2.6), SIMD2(1.9, 1.4)], [SIMD2(-1.0, 3.5), SIMD2(1.6, 3.3), SIMD2(-2.2, 1.2)]]
        for (k, seed) in [UInt64(31), 32, 33].enumerated() {
            let pos = layouts[k]
            let d = FeatureClipTests.Duo(positions: pos, features: [.none, .spines, .daisy], seed: seed)
            d.place(pos); d.live = true
            for _ in 0..<3 { d.tick() }
            for r in d.lab.rigs { r.brain.anticsEnabled = true }
            let lead = d.lab.rigs[0]
            XCTAssertTrue(lead.brain.socialStartGroup(.congaLine, with: d.lab.rigs.dropFirst().map { $0.brain }, lead.sim), "seed \(seed) starts")
            var minGap = Float.infinity, at = "", f = 0
            while f < 60 * 40 {
                d.tick(); f += 1
                let ph = lead.brain.social?.phase ?? -1
                for i in 0..<3 { for j in (i + 1)..<3 {
                    guard let g = ContactField.gap(i, j, features: true) else { continue }
                    if g < minGap { minGap = g; at = "\(i)-\(j) phase \(ph) t=\(Float(f) / 60)" }
                } }
                if !d.lab.anySocial && f > 10 { break }
            }
            let secs = Float(f) / 60
            print(String(format: "CONGATREAT seed %llu %.2fs min %.1f cm (%@)", seed, secs, minGap * 100, at))
            XCTAssertGreaterThanOrEqual(minGap, -0.01, "seed \(seed): no pass-through (\(at))")
            if Self.oldSeconds[k] > 0 { XCTAssertLessThanOrEqual(secs, Self.oldSeconds[k] * 1.1, "seed \(seed): not longer than before") }
        }
    }
}
