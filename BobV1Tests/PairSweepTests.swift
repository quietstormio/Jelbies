//
//  PairSweepTests.swift
//  Not a regression test: the diagnosis sweeps of the pair-distinct round (TEST_RUNNER_PAIR_OUT=<dir>; skipped without). One build answers several "what if" questions about hopAlong / jumpTurns / highFive by running the
//  variants one after the other through the real brains: <dir>/sweep_five.tsv, sweep_hop.tsv, trace_<kind>_<cast>_<variant>.tsv (a row per frame: time, phase, the two roots, yaws, states, skin / body / arm gaps in cm).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PairSweepTests: XCTestCase {
    static let casts = PairDistinctTests.casts
    override func setUp() { super.setUp(); PairProbe.setUpGlobals() }
    override func tearDown() { PairProbe.tearDownGlobals(); super.tearDown() }
    static var out: String? { let d = ProcessInfo.processInfo.environment["PAIR_OUT"] ?? ""; return d.isEmpty ? nil : d }
    static func cm(_ f: Float) -> String { f >= 8 ? "-" : String(format: "%.1f", f * 100) }

    func testSweepHighFive() throws {
        guard let dir = Self.out else { throw XCTSkip("PAIR_OUT not set") }
        let saved = HighFiveTuning.turnIn
        defer { HighFiveTuning.turnIn = saved }
        var rows = ["turnIn\tcast\tcontactGap_cm\tworstSkin_cm\ttouchGaps_cm\tworstAt"]
        for turn: Float in [0.45, 0.30, 0.15, 0.0] { for c in Self.casts {
            HighFiveTuning.turnIn = turn
            let r = PairProbe.run(kind: .highFive, cast: c.1, castName: c.0, maxSec: 30, trace: c.0 == "Pip+Teddy" || c.0 == "Bob+Teddy")
            PairProbe.tearDownGlobals()
            let w = r.samples.min { $0.skin < $1.skin }
            rows.append("\(turn)\t\(c.0)\t\(Self.cm(r.minSkinPerf))\t\(Self.cm(r.minSkin))\t\(r.touchGaps.map { Self.cm($0) }.joined(separator: ","))\t\(w.map { String(format: "t%.1f/ph%d", $0.t, $0.phase) } ?? "-")")
            if !r.trace.isEmpty { try? (["t\tphase\taX\taZ\tbX\tbZ\taYaw\tbYaw\taState\tbState\tskin_cm\tbody_cm\tarm_cm"] + r.trace).joined(separator: "\n").write(toFile: dir + "/trace_highFive_\(c.0)_turn\(turn).tsv", atomically: true, encoding: .utf8) }
        } }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try rows.joined(separator: "\n").write(toFile: dir + "/sweep_five.tsv", atomically: true, encoding: .utf8)
    }

    func testSweepHop() throws {
        guard let dir = Self.out else { throw XCTSkip("PAIR_OUT not set") }
        let (sa, sd, sj) = (Pair2Tuning.armsIn, Pair2Tuning.hopDist, Pair2Tuning.jumpBase)
        defer { Pair2Tuning.armsIn = sa; Pair2Tuning.hopDist = sd; Pair2Tuning.jumpBase = sj }
        var rows = ["kind\tarmsIn\tdist\tcast\tclosest_cm\tworstSkin_cm\tbody_cm\tarm_cm\ttouchGaps_cm\tworstAt"]
        for kind in [SocialKind.hopAlong, .jumpTurns] { for arms in [true, false] { for dist: Float in [0.45, 0.30] { for c in Self.casts {
            Pair2Tuning.armsIn = arms; Pair2Tuning.hopDist = dist; Pair2Tuning.jumpBase = dist - 0.1
            let tr = c.0 == "Bob+Teddy" || c.0 == "Teddy+Pearl"
            let r = PairProbe.run(kind: kind, cast: c.1, castName: c.0, maxSec: 30, trace: tr)
            PairProbe.tearDownGlobals()
            let w = r.samples.min { $0.skin < $1.skin }
            rows.append("\(kind.rawValue)\t\(arms)\t\(dist)\t\(c.0)\t\(Self.cm(r.minSkinPerf))\t\(Self.cm(r.minSkin))\t\(Self.cm(r.minBody))\t\(Self.cm(r.samples.map { $0.armArm }.min() ?? 9))\t\(r.touchGaps.map { Self.cm($0) }.joined(separator: ","))\t\(w.map { String(format: "t%.1f/ph%d", $0.t, $0.phase) } ?? "-")")
            if tr { try? (["t\tphase\taX\taZ\tbX\tbZ\taYaw\tbYaw\taState\tbState\tskin_cm\tbody_cm\tarm_cm"] + r.trace).joined(separator: "\n").write(toFile: dir + "/trace_\(kind.rawValue)_\(c.0)_arms\(arms)_d\(dist).tsv", atomically: true, encoding: .utf8) }
        } } } }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try rows.joined(separator: "\n").write(toFile: dir + "/sweep_hop.tsv", atomically: true, encoding: .utf8)
    }
}
