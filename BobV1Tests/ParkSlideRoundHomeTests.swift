//
//  ParkSlideRoundHomeTests.swift
//  park-slide-r2, item 3 identity check: a seeded home lab of three, 60 sim-s, prints a position checksum (run on the base build and on the head build: the same digits).
//

import XCTest
import simd
@testable import BobV1

extension ParkSlideRoundTests {
    func testHomeLabPositionChecksum() {
        _ = OnePieceInvariantTests.configured
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        DecorField.shared.clear()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .slide, x: 1.0, z: -0.2, turns: nil)])
        let lab = SocialTests.Lab(n: 3, positions: [SIMD2(-1.2, 0.2), SIMD2(0.2, 1.0), SIMD2(1.2, 2.0)], quiet: false, seed: 11)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.idleMood = .happy }
        var sum: UInt64 = 1469598103934665603
        var samples = 0
        for i in 0..<(60 * 60) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            if i % 30 == 0 {
                for r in lab.rigs {
                    let p = r.brain.position
                    sum = (sum ^ UInt64(p.x.bitPattern)) &* 1099511628211
                    sum = (sum ^ UInt64(p.y.bitPattern)) &* 1099511628211
                    samples += 1
                }
            }
        }
        let end = lab.rigs.map { String(format: "(%.4f,%.4f)", $0.brain.position.x, $0.brain.position.y) }.joined(separator: " ")
        print("PSR HOMESUM checksum \(sum) samples \(samples) end \(end)")
        XCTAssertGreaterThan(samples, 100)
        DecorField.shared.clear()
    }
}
