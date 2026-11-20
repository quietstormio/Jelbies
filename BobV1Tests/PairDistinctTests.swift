//
//  PairDistinctTests.swift
//  Pins the pair-distinct round (2026-11-19): the side-by-side pair emotes no longer all read as "two bodies standing arm to arm".
//    lean kinds (nuzzle, cheekSquish, cuddleLean, swayHug, whisperGiggle, bellyBounce): the upper bodies are what meet - the pair's least skin gap in the performance is inside the touch band (never below -1 cm, reaching
//        <= +0.5 cm), and the drawn ARMS never come within 3 cm of the partner (they are tucked in front);
//    sitTogether: clear space the whole time (the skins never meet, never overlap);
//    hopAlong: the pair really TRAVELS (its middle moves >= 0.9 m) and the skins never overlap;
//    (highFive is NOT here: it was left as on the branch base - see the commit that reverts the V; HighFiveContactTests covers it.)
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
    static let allKinds: [SocialKind] = [.boop, .nuzzle, .sitTogether, .highFive, .cheekSquish, .bellyBounce, .cuddleLean, .swayHug, .whisperGiggle, .hopAlong] + SocialKind.newPair
    nonisolated(unsafe) static var rows: [String] = []

    override func setUp() { super.setUp(); PairProbe.setUpGlobals() }
    override func tearDown() { PairProbe.tearDownGlobals(); super.tearDown() }

    func probe(_ k: SocialKind, _ c: (String, [Int]), seed: UInt64 = 31, flip: Bool = false) -> PairProbe.Result {
        let r = PairProbe.run(kind: k, cast: c.1, castName: (seed == 31 ? c.0 : "\(c.0)#\(seed)") + (flip ? "/flip" : ""), maxSec: 45, seed: seed, flip: flip)
        PairProbe.tearDownGlobals()
        return r
    }
    static func cm(_ f: Float) -> String { f >= 8 ? "-" : String(format: "%.1f", f * 100) }

    func row(_ r: PairProbe.Result) -> String {
        let ph = r.perf
        let travel = ph.isEmpty ? 0 : (ph.map { $0.sepRoot }.max() ?? 0) - (ph.map { $0.sepRoot }.min() ?? 0)
        let worst = r.samples.min { $0.skin < $1.skin }
        let at = worst.map { String(format: "t%.1f/ph%d", $0.t, $0.phase) } ?? "-"
        return [r.kind, r.cast, "\(r.started)", "\(r.completed)", String(format: "%.1f", r.seconds), Self.cm(r.minSkinPerf), Self.cm(r.minSkin), Self.cm(r.minBody), Self.cm(r.minArmArmPerf), Self.cm(r.minArmLevelPerf), Self.cm(r.minHeadPerf),
                String(format: "%.0f", travel * 100), r.touchGaps.map { Self.cm($0) }.joined(separator: ","), r.sounds.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
                r.haps.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","), "\(r.hearts)", at].joined(separator: "\t")
    }
    static let header = ["kind", "cast", "started", "completed", "sec", "contactGap_cm", "worstSkin_cm", "bodyOnly_cm", "armGap_cm", "armLevel_cm", "headLevel_cm", "sepRange_cm", "touchGaps_cm", "sounds", "haptics", "hearts", "worstAt"].joined(separator: "\t")

    private func flush(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["PAIR_OUT"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? ([Self.header] + Self.rows).joined(separator: "\n").write(toFile: dir + "/\(name).tsv", atomically: true, encoding: .utf8)
    }

    // MARK: the reshapes that stay

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

    /// Never overlapping, never touching: at the closest moment the skins are >= 8 cm apart, and never more than ~25 cm apart there (it reads as hopping TOGETHER).
    func testHopAlongStaysApartAndTogether() {
        for c in Self.casts {
            let r = probe(.hopAlong, c)
            Self.rows.append(row(r))
            XCTAssertTrue(r.started && r.completed, "hopAlong \(c.0): runs to its end")
            XCTAssertGreaterThanOrEqual(r.minSkin, 0.08, "hopAlong \(c.0): the closest moment is >= 8 cm")
            XCTAssertLessThanOrEqual(r.minSkinPerf, 0.25, "hopAlong \(c.0): and <= ~25 cm")
            XCTAssertGreaterThan(r.sounds["jump"] ?? 0, 0, "hopAlong \(c.0): the hop sound plays")
        }
        flush("table_hop")
    }

    /// whisperGiggle: no contact - a clear gap of >= 4 cm at every frame; the laugh (chirps) and the hearts stay.
    func testWhisperGiggleIsAClearGapV() {
        for c in Self.casts {
            let r = probe(.whisperGiggle, c)
            Self.rows.append(row(r))
            XCTAssertTrue(r.started && r.completed, "whisper \(c.0): runs to its end")
            XCTAssertGreaterThanOrEqual(r.minSkin, 0.04, "whisper \(c.0): skins >= 4 cm apart at every frame")
            XCTAssertGreaterThan(r.chirps, 1, "whisper \(c.0): the giggle chirps are played")
            XCTAssertGreaterThan(r.hearts, 0, "whisper \(c.0): the hearts stay")
        }
        flush("table_whisper")
    }

    // MARK: the four new kinds

    func testNewPairKindsKeepAClearGap() {
        for k in SocialKind.newPair { for c in Self.casts {
            let r = probe(k, c)
            Self.rows.append(row(r))
            let tag = "\(k.rawValue) \(c.0)"
            XCTAssertTrue(r.started && r.completed, "\(tag): runs to its end")
            XCTAssertGreaterThanOrEqual(r.minSkin, 0, "\(tag): the skins never touch or overlap")
            XCTAssertGreaterThan(r.chirps + (r.sounds["jump"] ?? 0) + (r.sounds["wobble"] ?? 0), 1, "\(tag): its sounds are PLAYED")
            XCTAssertGreaterThan(r.hearts, 0, "\(tag): the hearts")
            XCTAssertGreaterThan(r.seconds, 4, "\(tag): not a blink"); XCTAssertLessThan(r.seconds, 22, "\(tag): in line with the other pair emotes")
        } }
        flush("table_new")
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
