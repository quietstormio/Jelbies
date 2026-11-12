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

// MARK: - stage 3

extension FeatureCaptureTests {
    /// Stage 3 (trick plan): 12-frame strips of the moonwalk, back bounce, headstand and the repaired hula on blue Bob, yellow Pip (tail) and winged Lavender, each from the
    /// game camera and a three-quarter camera (az 0.8), tiles 300 px. Writes `s3_<name><STRIP_TAG>.png` and `s3_all_blue<STRIP_TAG>.png` (the game-camera blue rows, 6 tiles a
    /// row). Env: EMOTE_STRIP_DIR, EMOTE_STRIP_ONLY, EMOTE_STRIP_CHARS ("0,1,3"), STRIP_TAG, and the tuning knobs MW_HEELUP, MW_STRIDE, MW_LEAN, HULA_COUNTER, HULA_R0,
    /// HULA_R1, ACRO_HEAD_PITCH, ACRO_KICK (prototype tuning without a rebuild).
    func testStageThreeTrickStrips() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["EMOTE_STRIP_DIR"], !dir.isEmpty else { throw XCTSkip("EMOTE_STRIP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func knob(_ k: String) -> Float? { env[k].flatMap { Float($0) } }
        if let v = knob("MW_HEELUP") { MoonwalkTuning.heelUp = v }; if let v = knob("MW_STRIDE") { MoonwalkTuning.stride = v }; if let v = knob("MW_LEAN") { MoonwalkTuning.lean = v }
        if let v = knob("HULA_COUNTER") { HulaTuning.counter = v }; if let v = knob("HULA_R0") { HulaTuning.r0 = v }; if let v = knob("HULA_R1") { HulaTuning.r1 = v }
        if let v = knob("ACRO_HEAD_PITCH") { AcroTuning.headPitch = v }; if let v = knob("ACRO_HEAD_TURN") { AcroTuning.headTurnOff = v }; if let v = knob("ACRO_HEAD_SPLAY") { AcroTuning.headSplay = v }; if let v = knob("ACRO_KICK") { AcroTuning.kick = v }
        let tag = env["STRIP_TAG"] ?? ""
        let only = (env["EMOTE_STRIP_ONLY"] ?? "").split(separator: ",").map(String.init)
        let chars = (env["EMOTE_STRIP_CHARS"] ?? "0,1,3").split(separator: ",").compactMap { Int($0) }
        DayClock.shared.forcedHour = 12
        let hula = Swift.stride(from: 1.0, through: 3.25, by: 0.25).map { HulaTuning.time(forCycles: Float($0)) } + [HulaTuning.swing + HulaTuning.settle + 0.12, HulaTuning.swing + HulaTuning.settle + 0.32]
        let cases: [(String, IdleKind, Bool, [Float])] = [
            ("moonwalk", .moonwalk, false, [0.15, 0.45, 0.60, 0.75, 0.90, 1.05, 1.25, 1.55, 1.85, 2.45, 2.85, 3.9]),
            ("moonwalk_fail", .moonwalk, true, [0.15, 0.45, 0.70, 0.95, 1.10, 1.25, 1.40, 1.55, 1.75, 2.0, 2.4, 3.0]),
            ("backBounce", .backBounce, false, [0.15, 0.30, 0.45, 0.58, 0.75, 0.88, 1.10, 1.30, 1.50, 1.65, 1.85, 2.05]),
            ("backBounce_fail", .backBounce, true, [0.15, 0.45, 0.75, 1.10, 1.30, 1.55, 1.80, 2.05, 2.30, 2.55, 2.80, 3.10]),
            ("headstand", .headstand, false, [0.15, 0.40, 0.60, 0.80, 1.00, 1.25, 1.50, 1.75, 2.10, 2.30, 2.50, 2.75]),
            ("headstand_fail", .headstand, true, [0.40, 0.80, 1.10, 1.40, 1.60, 1.80, 2.00, 2.30, 2.60, 2.90, 3.20, 3.45]),
            ("hula", .hula, false, hula),
        ]
        var blueRows: [UIImage] = []
        for (name, kind, fail, times) in cases where only.isEmpty || only.contains(name) {
            func pass(_ id: Int, az: Float, frames: [Int]?) throws -> (start: Int, end: Int, tiles: [UIImage]) {
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
                for f in 0..<1600 {
                    lab.tick(watching: false)
                    tick(d, 0, r, ch[0])
                    if start < 0, r.brain.idleState.kind == kind, r.brain.idleState.phase >= 1 { start = f }
                    if start >= 0, end < 0, r.brain.idleState.kind == nil { end = f; if frames == nil { break } }
                    if let frames, frames.contains(f) {
                        let cc = r.sim.centroid()
                        if cam0 == nil {
                            let cp = GameCamera.camera(aspect: 1, focus: 0).pos
                            var dir = SIMD3<Float>(cp.x - cc.x, 0, cp.z - cc.z); dir = simd_normalize(dir)
                            // the three-quarter camera swings round toward the side his face is on (the move turns him off the camera)
                            let face = SIMD3<Float>(sinf(r.brain.yaw), 0, cosf(r.brain.yaw))
                            func rot(_ a: Float) -> SIMD3<Float> { SIMD3(dir.x * cosf(a) + dir.z * sinf(a), 0, -dir.x * sinf(a) + dir.z * cosf(a)) }
                            if az != 0 { let side = kind == .moonwalk; dir = (simd_dot(rot(az), face) >= simd_dot(rot(-az), face)) != side ? rot(az) : rot(-az) }          // (the moonwalk's: toward his side, the glide across the picture)
                            cam0 = Self.lookCamera(target: SIMD3(cc.x, cc.y + 0.25, cc.z), dir: dir, dist: 3.7, aspect: 1, lift: 0.12)
                        }
                        let img = composite(lab, d, ch, ren, target, cam: cam0)
                        let small = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in img.uiImage()!.draw(in: CGRect(x: 0, y: 0, width: 300, height: 300)) }
                        tiles.append(labelled(small, String(format: "%@ #%d%@ t=%.2fs", name, id, az == 0 ? "" : " 3/4", Float(f - start) / 60)))
                    }
                    if r.brain.idleState.kind == nil && start >= 0 && frames != nil && f > (frames?.last ?? 0) { break }
                }
                return (start, end, tiles)
            }
            var rows: [UIImage] = []
            for id in chars {
                let probe = try pass(id, az: 0, frames: nil)
                XCTAssertGreaterThan(probe.start, -1, "\(name) #\(id): never reached its active phase")
                let frames = times.map { probe.start + Int($0 * 60) }
                for az: Float in [0, 0.8] {
                    let shots = try pass(id, az: az, frames: frames)
                    XCTAssertEqual(shots.tiles.count, times.count, "\(name) #\(id): frames \(frames)")
                    rows.append(hstack(shots.tiles))
                    if id == 0, az == 0, !name.hasSuffix("_fail") { blueRows.append(hstack(Array(shots.tiles.prefix(6)))); blueRows.append(hstack(Array(shots.tiles.dropFirst(6)))) }
                }
                print("TRICK STRIP \(name) #\(id): active \(Float(probe.end - probe.start) / 60) s")
            }
            try write(vstack(rows), dir + "/s3_\(name)\(tag).png")
        }
        if !blueRows.isEmpty { try write(vstack(blueRows), dir + "/s3_all_blue\(tag).png") }
    }
}
