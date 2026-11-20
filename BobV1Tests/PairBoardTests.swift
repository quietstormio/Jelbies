//
//  PairBoardTests.swift
//  Not a regression test: the BEFORE / AFTER boards of the pair-distinct round. TEST_RUNNER_PAIR_OUT=<dir> (skipped without), TEST_RUNNER_PAIR_TAG=before|after, TEST_RUNNER_PAIR_KINDS=a,b (optional).
//  Output: <dir>/<tag>_board.png (the ten side-by-side kinds, five frames each, game camera, cropped around the pair), <dir>/crops/<tag>_<kind>_contact.png (3x of the contact moment),
//  <dir>/<tag>_runs.tsv (seconds, started, min gaps per kind).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class PairBoardTests: XCTestCase {
    static let kinds: [SocialKind] = [.boop, .nuzzle, .sitTogether, .highFive, .cheekSquish, .bellyBounce, .cuddleLean, .swayHug, .whisperGiggle, .hopAlong]

    func testBoard() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["PAIR_OUT"], !dir.isEmpty else { throw XCTSkip("PAIR_OUT not set") }
        let tag = env["PAIR_TAG"] ?? "board"
        let only = Set((env["PAIR_KINDS"] ?? "").split(separator: ",").map(String.init))
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        try FileManager.default.createDirectory(atPath: dir + "/crops", withIntermediateDirectories: true)
        var rows: [(String, [UIImage])] = []
        var tsv = ["kind\tstarted\tseconds\tminSkin_cm\tminArmLevelPerf_cm\tminHeadPerf_cm\ttouches\ttouchGaps_cm"]
        for k in Self.kinds where only.isEmpty || only.contains(k.rawValue) {
            let r = PairProbe.run(kind: k, cast: [0, 1], castName: "Bob+Pip", shootEvery: 10, device: device)
            let f = PairProbe.five(r.shots)
            let title = String(format: "%@ | Bob+Pip | %.1fs | skin %.1f cm | arm-level %.1f cm | head %.1f cm | frames at %@", k.rawValue, r.seconds, r.minSkin * 100, r.minArmLevelPerf * 100, r.minHeadPerf * 100, f.map { String(format: "%.1f", $0.t) }.joined(separator: " "))
            rows.append((title, f.map { $0.image }))
            if let c = PairProbe.contactMoment(r.shots), let cg = c.image.cgImage {
                let cr = CGRect(x: 70, y: 40, width: 200, height: 160)
                if let sub = cg.cropping(to: cr) {
                    let up = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 480), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in UIImage(cgImage: sub).draw(in: CGRect(x: 0, y: 0, width: 600, height: 480)) }
                    try? up.pngData()!.write(to: URL(fileURLWithPath: dir + "/crops/\(tag)_\(k.rawValue)_contact.png"))
                }
            }
            tsv.append("\(k.rawValue)\t\(r.started)\t\(String(format: "%.1f", r.seconds))\t\(String(format: "%.1f", r.minSkin * 100))\t\(String(format: "%.1f", r.minArmLevelPerf * 100))\t\(String(format: "%.1f", r.minHeadPerf * 100))\t\(r.touchGaps.count)\t\(r.touchGaps.map { String(format: "%.1f", $0 * 100) }.joined(separator: ","))")
            XCTAssertTrue(r.started, "\(k) starts")
            PairProbe.tearDownGlobals()
        }
        try PairProbe.board(rows: rows, to: dir + "/\(tag)_board.png", cell: CGSize(width: 340, height: 250))
        try tsv.joined(separator: "\n").write(toFile: dir + "/\(tag)_runs.tsv", atomically: true, encoding: .utf8)
    }
}
