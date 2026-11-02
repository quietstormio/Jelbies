//
//  EmoteCaptureTests.swift
//  Not a regression test: 6-frame strips of the solo emotes (g-emotes1, 2026-11-02) with the REAL renderer, the wardrobe and the feature layer (wings, daisy, Teddy's ears) in the room.
//  Set EMOTE_STRIP_DIR (TEST_RUNNER_EMOTE_STRIP_DIR) to write them; EMOTE_STRIP_ONLY="hiccup,sig_teddy" filters. Frames are spread over the emote's own time (after the turn to the player).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testEmoteStrips() throws {
        guard let dir = ProcessInfo.processInfo.environment["EMOTE_STRIP_DIR"], !dir.isEmpty else { throw XCTSkip("EMOTE_STRIP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let only = (ProcessInfo.processInfo.environment["EMOTE_STRIP_ONLY"] ?? "").split(separator: ",").map(String.init)
        DayClock.shared.forcedHour = 12
        // (name, kind, character, six moments in seconds from the emote's own start, camera azimuth off the player's view in rad)
        let sig: [Float] = [0.3, 0.6, 1.0, 1.4, 1.8, 2.2]
        let cases: [(String, IdleKind, Int, [Float], Float)] = [
            ("hiccup", .hiccup, 0, [0.15, 0.32, 0.45, 1.3, 1.9, 2.55], 0), ("sneeze", .sneeze, 0, [0.4, 0.95, 1.3, 1.4, 1.8, 2.5], 0),
            ("dizzyWobble", .dizzyWobble, 0, [0.5, 1.0, 1.5, 2.0, 2.6, 3.0], 0), ("politeBow", .politeBow, 0, [0.2, 0.5, 0.9, 1.2, 1.5, 1.9], 0),
            ("bellyDrum", .bellyDrum, 0, [0.3, 0.5, 0.8, 1.1, 1.5, 2.0], 0), ("bellyDrum34", .bellyDrum, 0, [0.5, 0.65, 0.8, 0.95, 1.1, 1.25], 0.7),
            ("sig_bob", .signatureFlourish, 0, sig, 0), ("sig_pip", .signatureFlourish, 1, sig, 0), ("sig_moss", .signatureFlourish, 2, sig, 0),
            ("sig_lavender", .signatureFlourish, 3, sig, 0), ("sig_teddy", .signatureFlourish, 4, sig, 0), ("sig_pearl", .signatureFlourish, 5, sig, 0),
        ]
        for (name, kind, id, times, az) in cases where only.isEmpty || only.contains(name) {
            let chars = [Char(id: id)]
            func pass(frames: [Int]?) throws -> (start: Int, end: Int, tiles: [UIImage]) {
                W = 560; H = 560
                let lab = setUpLab([SIMD2(0.2, 0.6)], chars: chars, seed: 3)
                let r = lab.rigs[0]
                let d = dress(lab, chars)
                let (ren, target) = try renderer(lab)
                r.brain.idleForced = true
                XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(name) did not start")
                var start = -1, end = -1, tiles: [UIImage] = []
                var cam0: CameraState?
                for f in 0..<900 {
                    lab.tick(watching: false)
                    tick(d, 0, r, chars[0])
                    if start < 0, r.brain.idleState.kind == kind, r.brain.idleState.phase >= 1 { start = f }
                    if start >= 0, end < 0, r.brain.idleState.kind == nil { end = f; if frames == nil { break } }
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
            let len = max(probe.end - probe.start, 6)
            let frames = times.map { probe.start + Int($0 * 60) }; _ = len
            let shots = try pass(frames: frames)
            XCTAssertEqual(shots.tiles.count, 6, "\(name): frames \(frames)")
            let row1 = hstack(Array(shots.tiles.prefix(3))), row2 = hstack(Array(shots.tiles.suffix(3)))
            try write(vstack([row1, row2]), dir + "/\(name).png")
            print("EMOTE STRIP \(name): active frames \(probe.start)...\(probe.end) (\(Float(probe.end - probe.start) / 60) s)")
        }
    }
}
