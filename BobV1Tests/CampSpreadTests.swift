//
//  CampSpreadTests.swift
//  camp-yard-r1: six Camp bodies use the whole yard (they do not knot up in the middle). Headless: six brains wired as the stage wires them (SocialTests.Lab) on the Camp floor for three simulated minutes;
//  the mean nearest-neighbour distance (sampled once a second) and the share of the yard's 1 m cells any body has stood in.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CampSpreadTests: XCTestCase {
    override func tearDown() {
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    struct Numbers { var meanNN: Float; var coverage: Float; var cells: Int; var closeShare: Float; var frontShare: Float; var recentCoverage: Float }

    func measure(seed: UInt64, aspect: Float = 0.46, minutes: Float = 3) -> Numbers {
        RoomLayout.apply(RoomCatalog.camp); GameCamera.configureCamp()
        XCTAssertNotNil(GameCamera.refreshRoam(aspect: aspect))
        let lab = SocialTests.Lab(n: 6, positions: CampLayout.spots(count: 6), quiet: false, seed: seed)
        for r in lab.rigs { r.brain.watching = true }          // (the stage's yard: the player is always watching)
        var nn: [Float] = [], seen = Set<Int>(), close = 0, front = 0, bodySamples = 0
        var window: [Set<Int>] = []          // the cells seen in each of the last 60 one-second samples
        let cx0: Float = -3, cx1: Float = 3, cz0: Float = -3.5, cz1: Float = 4.5
        let cols = Int(cx1 - cx0), rows = Int(cz1 - cz0)
        let steps = Int(minutes * 60 * 60)
        for s in 0..<steps {
            lab.tick(watching: false)
            if s % 60 == 0 {
                let p = lab.snapshot.map(\.pos)
                var sum: Float = 0
                for i in p.indices { sum += p.indices.filter { $0 != i }.map { simd_distance(p[i], p[$0]) }.min() ?? 0 }
                nn.append(sum / Float(p.count))
                var now = Set<Int>()
                for (i, q) in p.enumerated() {
                    let c = Int(floorf((q.x - cx0))), r = Int(floorf((q.y - cz0)))
                    if c >= 0, c < cols, r >= 0, r < rows { seen.insert(r * cols + c); now.insert(r * cols + c) }
                    bodySamples += 1
                    if (p.indices.filter { $0 != i }.map { simd_distance(q, p[$0]) }.min() ?? 9) < 1.3 { close += 1 }
                    if q.y > 1.8 { front += 1 }
                }
                window.append(now); if window.count > 60 { window.removeFirst() }
            }
        }
        let recent = window.reduce(into: Set<Int>()) { $0.formUnion($1) }
        return Numbers(meanNN: nn.reduce(0, +) / Float(nn.count), coverage: Float(seen.count) / Float(cols * rows), cells: seen.count, closeShare: Float(close) / Float(bodySamples), frontShare: Float(front) / Float(bodySamples), recentCoverage: Float(recent.count) / Float(cols * rows))
    }

    func testSixBodiesSpreadOverTheYard() {
        var all: [Numbers] = []
        for (seed, aspect) in [(UInt64(11), Float(0.46)), (UInt64(23), Float(2.17))] { let n = measure(seed: seed, aspect: aspect, minutes: 2); all.append(n); print("[campspread] aspect \(aspect) seed \(seed): mean nearest neighbour \(n.meanNN) m, yard cells visited \(n.cells) of 48 = \(n.coverage), share of body-seconds within 1.3 m of another \(n.closeShare), share in the front third (z > 1.8) \(n.frontShare), cells seen in the last minute \(n.recentCoverage)") }
        let nn = all.map(\.meanNN).reduce(0, +) / Float(all.count), cov = all.map(\.coverage).reduce(0, +) / Float(all.count)
        print("[campspread] MEAN over seeds: nearest neighbour \(nn) m, coverage \(cov)")
        XCTAssertGreaterThan(nn, Self.floorNN, "bodies are not a knot")
        XCTAssertGreaterThan(cov, Self.floorCoverage, "bodies visit most of the yard")
        XCTAssertLessThan(all.map(\.closeShare).reduce(0, +) / Float(all.count), Self.ceilClose, "bodies are not in a knot most of the time")
        XCTAssertGreaterThan(all.map(\.frontShare).reduce(0, +) / Float(all.count), Self.floorFront, "the front of the yard is used")
        XCTAssertGreaterThan(all.map(\.recentCoverage).reduce(0, +) / Float(all.count), Self.floorRecent, "a minute of roaming covers a good part of the yard")
    }
    static let floorNN: Float = 1.4, floorCoverage: Float = 0.7, ceilClose: Float = 0.2, floorFront: Float = 0.15, floorRecent: Float = 0.5
}
