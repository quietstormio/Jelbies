//
//  EmotesBatch2CaptureTests.swift
//  Not a regression test: 6-frame strips of the batch-2 solo / player-cued emotes (g-emotes3) with the REAL renderer (like EmoteCaptureTests). EMOTE_STRIP_DIR / EMOTE_STRIP_ONLY as there.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testEmoteStripsBatch2() throws {
        guard let dir = ProcessInfo.processInfo.environment["EMOTE_STRIP_DIR"], !dir.isEmpty else { throw XCTSkip("EMOTE_STRIP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let only = (ProcessInfo.processInfo.environment["EMOTE_STRIP_ONLY"] ?? "").split(separator: ",").map(String.init)
        // (name, kind, character, six moments in seconds from the emote's active phase, camera azimuth in rad, night)
        let cases: [(String, IdleKind, Int, [Float], Float, Bool)] = [
            ("stargazing", .stargazing, 0, [0.4, 1.2, 2.4, 3.6, 4.8, 6.0], 0, true), ("stargazing_pip", .stargazing, 1, [0.4, 1.2, 2.4, 3.6, 4.8, 6.0], 0, true),
            ("proudStrut", .proudStrut, 0, [0.3, 0.7, 1.2, 2.0, 3.0, 3.9], 0, false), ("proudStrut_pip", .proudStrut, 1, [0.3, 0.7, 1.2, 2.0, 3.0, 3.9], 0, false),
            ("proudStrut34", .proudStrut, 0, [0.5, 0.65, 0.8, 0.95, 1.1, 1.25], 0.7, false),
            ("floorNapFlop", .floorNapFlop, 0, [0.1, 0.25, 0.45, 1.5, 3.0, 4.5], 0, false), ("floorNapFlop34", .floorNapFlop, 0, [0.1, 0.25, 0.45, 1.5, 3.0, 4.5], 0.8, false),
            ("floorNapFlop_teddy", .floorNapFlop, 4, [0.1, 0.25, 0.45, 1.5, 3.0, 4.5], 0, false), ("floorNapFlop_pip", .floorNapFlop, 1, [0.1, 0.25, 0.45, 1.5, 3.0, 4.5], 0.5, false),
            ("tapTilt", .tapTilt, 0, [0.1, 0.4, 0.7, 1.0, 1.5, 2.0], 0, false), ("welcomeWiggle", .welcomeWiggle, 0, [0.1, 0.3, 0.6, 0.9, 1.3, 1.7], 0, false),
            ("checkIn", .checkIn, 0, [0.2, 0.6, 1.0, 1.5, 2.2, 2.9], 0, false),
        ]
        for (name, kind, id, times, az, night) in cases where only.isEmpty || only.contains(name) {
            let chars = [Char(id: id)]
            func pass(frames: [Int]?) throws -> (start: Int, end: Int, tiles: [UIImage]) {
                W = 560; H = 560
                DayClock.shared.forcedHour = night ? 21 : 12
                let lab = setUpLab([SIMD2(0.2, 0.6)], chars: chars, seed: 3)
                let r = lab.rigs[0]
                let d = dress(lab, chars)
                let (ren, target) = try renderer(lab)
                r.brain.idleForced = true
                if night { r.brain.idleNight = 1 }
                r.brain.treat2.tapPoint = SIMD2(2.2, 1.0)
                XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(name) did not start")
                var start = -1, end = -1, tiles: [UIImage] = []
                var cam0: CameraState?
                for f in 0..<1200 {
                    lab.tick(watching: false)
                    if night { r.brain.idleNight = 1 }
                    tick(d, 0, r, chars[0])
                    if start < 0, r.brain.idleState.kind == kind, r.brain.idleState.phase >= 1, !r.brain.idleState.windowGo { start = f }
                    if start >= 0, end < 0, r.brain.idleState.kind == nil || (kind == .proudStrut && r.brain.idleState.kind == .joy && false) { end = f; if frames == nil { break } }
                    if let frames, frames.contains(f) {
                        let cc = r.sim.centroid()
                        if cam0 == nil {
                            let cp = GameCamera.camera(aspect: 1, focus: 0).pos
                            var dir = SIMD3<Float>(cp.x - cc.x, 0, cp.z - cc.z); dir = simd_normalize(dir); dir = SIMD3(dir.x * cosf(az) + dir.z * sinf(az), 0, -dir.x * sinf(az) + dir.z * cosf(az))
                            cam0 = Self.lookCamera(target: SIMD3(cc.x, cc.y + 0.25, cc.z), dir: dir, dist: 3.4, aspect: 1, lift: 0.12)
                        }
                        let img = composite(lab, d, chars, ren, target, cam: cam0)
                        tiles.append(labelled(img.uiImage()!, String(format: "%@  t=%.2fs", name, Float(f - start) / 60)))
                    }
                    if r.brain.idleState.kind == nil && start >= 0 { break }
                }
                return (start, end, tiles)
            }
            let probe = try pass(frames: nil)
            XCTAssertGreaterThan(probe.start, -1, "\(name): never reached its active phase")
            let frames = times.map { probe.start + Int($0 * 60) }
            let shots = try pass(frames: frames)
            XCTAssertEqual(shots.tiles.count, 6, "\(name): frames \(frames)")
            let row1 = hstack(Array(shots.tiles.prefix(3))), row2 = hstack(Array(shots.tiles.suffix(3)))
            try write(vstack([row1, row2]), dir + "/\(name).png")
            print("EMOTE STRIP \(name): active frames \(probe.start)...\(probe.end) (\(Float(probe.end - probe.start) / 60) s)")
        }
        DayClock.shared.forcedHour = nil
    }
}
