//
//  TrickStripTests.swift
//  Not a regression test: the stage-2 trick sheets (trick plan): for each trick an 8-frame strip on three Jelbies (blue Bob, yellow Pip with the tail, winged Lavender),
//  from the game camera, tiles 300 px wide. Set EMOTE_STRIP_DIR (TEST_RUNNER_EMOTE_STRIP_DIR) to write `s2_<name>.png`; EMOTE_STRIP_ONLY="hula,corkscrew" filters.
//  Frame times are seconds from the move's own start (after the turn to the camera).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testStageTwoTrickStrips() throws {
        guard let dir = ProcessInfo.processInfo.environment["EMOTE_STRIP_DIR"], !dir.isEmpty else { throw XCTSkip("EMOTE_STRIP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let only = (ProcessInfo.processInfo.environment["EMOTE_STRIP_ONLY"] ?? "").split(separator: ",").map(String.init)
        DayClock.shared.forcedHour = 12
        let hula = [0.0, 0.25, 0.5, 0.75, 2.0, 2.5, 3.5, 4.5].map { HulaTuning.time(forCycles: Float($0)) }
        let hulaFail = [0.5, 1.5, 3.0, 5.0].map { HulaTuning.time(forCycles: Float($0), fail: true) } + [2.3, 2.6, 3.0, 3.6]
        // (sheet, kind, fail, eight moments, camera azimuth off the player's view in rad)
        let cases: [(String, IdleKind, Bool, [Float], Float)] = [
            ("hula", .hula, false, hula, 0), ("hula_fail", .hula, true, hulaFail, 0),
            ("superSpring", .superSpring, false, [0.05, 0.25, 0.42, 0.55, 0.68, 0.85, 1.05, 1.45], 0), ("superSpring_fail", .superSpring, true, [0.05, 0.25, 0.42, 0.52, 0.62, 0.78, 0.95, 1.3], 0),
            ("corkscrew", .corkscrew, false, [0.03, 0.18, 0.30, 0.42, 0.52, 0.62, 0.78, 1.15], 0), ("corkscrew_fail", .corkscrew, true, [0.03, 0.18, 0.30, 0.42, 0.52, 0.62, 0.80, 1.4], 0),
            ("oneLegSpin", .oneLegSpin, false, [0.10, 0.30, 0.55, 0.80, 1.05, 1.30, 1.70, 2.10], 0), ("oneLegSpin_az07", .oneLegSpin, false, [0.10, 0.30, 0.55, 0.80, 1.05, 1.30, 1.70, 2.10], 0.7),
            ("oneLegSpin_fail", .oneLegSpin, true, [0.10, 0.30, 0.55, 0.80, 1.00, 1.25, 1.55, 2.00], 0),
        ]
        let chars = [0, 1, 3]
        for (name, kind, fail, times, az) in cases where only.isEmpty || only.contains(name) {
            func pass(_ id: Int, frames: [Int]?) throws -> (start: Int, end: Int, tiles: [UIImage]) {
                W = 560; H = 560
                let ch = [Char(id: id)]
                let lab = setUpLab([SIMD2(0.2, 0.6)], chars: ch, seed: 3)
                let r = lab.rigs[0]
                let d = dress(lab, ch)
                let (ren, target) = try renderer(lab)
                r.brain.idleForced = true
                r.brain.commanded = true
                r.brain.idleState.trickFailNext = fail
                XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(name) did not start")
                var start = -1, end = -1, tiles: [UIImage] = []
                var cam0: CameraState?
                for f in 0..<1200 {
                    lab.tick(watching: false)
                    tick(d, 0, r, ch[0])
                    if start < 0, r.brain.idleState.kind == kind, r.brain.idleState.phase >= 1 { start = f }
                    if start >= 0, end < 0, r.brain.idleState.kind == nil { end = f; if frames == nil { break } }
                    if let frames, frames.contains(f) {
                        let cc = r.sim.centroid()
                        if cam0 == nil {
                            let cp = GameCamera.camera(aspect: 1, focus: 0).pos
                            var dir = SIMD3<Float>(cp.x - cc.x, 0, cp.z - cc.z); dir = simd_normalize(dir); dir = SIMD3(dir.x * cosf(az) + dir.z * sinf(az), 0, -dir.x * sinf(az) + dir.z * cosf(az))
                            cam0 = Self.lookCamera(target: SIMD3(cc.x, cc.y + 0.25, cc.z), dir: dir, dist: 3.7, aspect: 1, lift: 0.12)
                        }
                        let img = composite(lab, d, ch, ren, target, cam: cam0)
                        let small = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in img.uiImage()!.draw(in: CGRect(x: 0, y: 0, width: 300, height: 300)) }
                        tiles.append(labelled(small, String(format: "%@ #%d  t=%.2fs", name, id, Float(f - start) / 60)))
                    }
                    if r.brain.idleState.kind == nil && start >= 0 && frames != nil && f > (frames?.last ?? 0) { break }
                }
                return (start, end, tiles)
            }
            var rows: [UIImage] = []
            for id in chars {
                let probe = try pass(id, frames: nil)
                XCTAssertGreaterThan(probe.start, -1, "\(name) #\(id): never reached its active phase")
                let frames = times.map { probe.start + Int($0 * 60) }
                let shots = try pass(id, frames: frames)
                XCTAssertEqual(shots.tiles.count, times.count, "\(name) #\(id): frames \(frames)")
                rows.append(hstack(shots.tiles))
                print("TRICK STRIP \(name) #\(id): active \(Float(probe.end - probe.start) / 60) s")
            }
            try write(vstack(rows), dir + "/s2_\(name).png")
        }
    }
}
