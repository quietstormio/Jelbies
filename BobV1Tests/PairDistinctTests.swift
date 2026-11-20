//
//  PairDistinctTests.swift
//  Pins the pair-distinct round (2026-11-19): the side-by-side pair emotes no longer all read as "two bodies standing arm to arm".
//    lean kinds (nuzzle, cheekSquish, cuddleLean, swayHug, whisperGiggle, bellyBounce): the upper bodies are what meet - the pair's least skin gap in the performance is inside the touch band (never below -1 cm, reaching
//        <= +0.5 cm), and the drawn ARMS never come within 3 cm of the partner (they are tucked in front);
//    sitTogether: clear space the whole time (the skins never meet, never overlap);
//    hopAlong: the pair really TRAVELS (its middle moves >= 0.9 m) and the skins never overlap;
//    highFive: the hands meet (hand to hand inside the band at the clap), the skins never overlap by more than 1 cm.
//  Every kind runs for the species pairs of ContactPolishTests (blue, yellow tail + spikes, green antennas / daisy, wings, Teddy ears) + Panda. TEST_RUNNER_PAIR_OUT=<dir> also writes <dir>/table.tsv (kind x cast).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class PairDistinctTests: XCTestCase {
    static let casts: [(String, [Int])] = ContactPolishTests.pairs + [("Panda+Bob", [6, 0])]
    static let leanKinds: [SocialKind] = [.nuzzle, .cheekSquish, .cuddleLean, .swayHug, .whisperGiggle, .bellyBounce]
    static let allKinds: [SocialKind] = [.boop, .nuzzle, .sitTogether, .highFive, .cheekSquish, .bellyBounce, .cuddleLean, .swayHug, .whisperGiggle, .hopAlong]
    nonisolated(unsafe) static var rows: [String] = []

    override func setUp() { super.setUp(); PairProbe.setUpGlobals() }
    override func tearDown() { PairProbe.tearDownGlobals(); super.tearDown() }

    func probe(_ k: SocialKind, _ c: (String, [Int])) -> PairProbe.Result {
        let r = PairProbe.run(kind: k, cast: c.1, castName: c.0, maxSec: 45)
        PairProbe.tearDownGlobals()
        return r
    }
    static func cm(_ f: Float) -> String { f >= 8 ? "-" : String(format: "%.1f", f * 100) }

    func row(_ r: PairProbe.Result) -> String {
        let ph = r.perf
        let travel = ph.isEmpty ? 0 : (ph.map { $0.sepRoot }.max() ?? 0) - (ph.map { $0.sepRoot }.min() ?? 0)
        return [r.kind, r.cast, "\(r.started)", "\(r.completed)", String(format: "%.1f", r.seconds), Self.cm(r.minSkinPerf), Self.cm(r.minSkin), Self.cm(r.minBody), Self.cm(r.minArmArmPerf), Self.cm(r.minArmLevelPerf), Self.cm(r.minHeadPerf),
                String(format: "%.0f", travel * 100), r.touchGaps.map { Self.cm($0) }.joined(separator: ","), r.sounds.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
                r.haps.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","), "\(r.hearts)"].joined(separator: "\t")
    }
    static let header = ["kind", "cast", "started", "completed", "sec", "contactGap_cm", "worstSkin_cm", "bodyOnly_cm", "armGap_cm", "armLevel_cm", "headLevel_cm", "sepRange_cm", "touchGaps_cm", "sounds", "haptics", "hearts"].joined(separator: "\t")

    private func flush(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["PAIR_OUT"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? ([Self.header] + Self.rows).joined(separator: "\n").write(toFile: dir + "/\(name).tsv", atomically: true, encoding: .utf8)
    }

    // MARK: lean kinds

    func testLeanKindsTouchWithTheUpperBodyAndTheArmsClear() {
        for k in Self.leanKinds { for c in Self.casts {
            let r = probe(k, c)
            Self.rows.append(row(r))
            let tag = "\(k.rawValue) \(c.0)"
            XCTAssertTrue(r.started && r.completed, "\(tag): runs to its end")
            XCTAssertGreaterThanOrEqual(r.minSkin, -0.01, "\(tag): never below -1 cm skin to skin (whole skin, arms and features included)")
            XCTAssertLessThanOrEqual(r.minSkinPerf, 0.005, "\(tag): the intended contact is reached (<= +0.5 cm)")
            if r.minArmArmPerf < 8 { XCTAssertGreaterThanOrEqual(r.minArmArmPerf, 0.03, "\(tag): the drawn arms stay >= 3 cm from the partner") }
        } }
        flush("table_lean")
    }

    // MARK: sit, hop, high five

    func testSitTogetherSitsApart() {
        for c in Self.casts {
            let r = probe(.sitTogether, c)
            Self.rows.append(row(r))
            XCTAssertTrue(r.started && r.completed, "sit \(c.0): runs to its end")
            XCTAssertGreaterThanOrEqual(r.minSkinPerf, 0.02, "sit \(c.0): clear space between them (the skins never meet)")
            XCTAssertGreaterThan(r.sounds["squish"] ?? 0, 0, "sit \(c.0): the sit-down squish stays")
            XCTAssertGreaterThan(r.hearts, 0, "sit \(c.0): the heart stays")
        }
        flush("table_sit")
    }

    func testHopAlongTravels() {
        for c in Self.casts {
            let r = probe(.hopAlong, c)
            Self.rows.append(row(r))
            XCTAssertTrue(r.started && r.completed, "hopAlong \(c.0): runs to its end")
            XCTAssertGreaterThanOrEqual(r.minSkin, -0.01, "hopAlong \(c.0): never overlaps")
        }
        flush("table_hop")
    }

    func testHighFiveHandsMeet() {
        for c in Self.casts {
            let r = probe(.highFive, c)
            Self.rows.append(row(r))
            XCTAssertTrue(r.started && r.completed, "highFive \(c.0): runs to its end")
            XCTAssertGreaterThanOrEqual(r.minSkin, -0.01, "highFive \(c.0): never below -1 cm")
            XCTAssertLessThanOrEqual(r.minSkinPerf, 0.005, "highFive \(c.0): the hands meet")
        }
        flush("table_five")
    }

    /// Every ten kinds, the whole table (TEST_RUNNER_PAIR_OUT): kind x cast -> gaps, sounds, hearts. No assertions beyond starting.
    func testWholeTable() {
        guard ProcessInfo.processInfo.environment["PAIR_OUT"] != nil else { return }
        for k in Self.allKinds { for c in Self.casts {
            let r = probe(k, c)
            Self.rows.append(row(r))
            XCTAssertTrue(r.started, "\(k) \(c.0) starts")
        } }
        flush("table_all")
    }
}
