//
//  BathSootFirstSmearTests.swift
//  Each Jelbie's FIRST dirty spot differs (placement seed = id + 1). Mirrors the shader's bFaceStart rotation and renders seeds 1-3 close up.
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class BathSootFirstSmearTests: XCTestCase {
    static let starts: [Float] = [0.05, 0.26, 0.30, 0.34, 0.40, 0.42]
    /// Mirror of `bFaceStart` in BathShaders.metal.
    static func start(_ j: Int, seed: Float) -> Float {
        let shift = Int((seed + 0.5).rounded(.down) * 5) % 6
        return starts[(j + shift) % 6]
    }
    /// Face smear (0-based, shader order: right cheek, left cheek, chin, brow, right eye, left eye) that shows first.
    static func firstSmear(seed: Float) -> Int { (0..<6).min { start($0, seed: seed) < start($1, seed: seed) }! }

    func testFirstSmearDiffersPerSeedMath() {
        XCTAssertEqual(BathLook.sootSeed(jelly: 0), 1)
        XCTAssertEqual((1...6).map { Self.firstSmear(seed: Float($0)) }, [1, 2, 3, 4, 5, 0], "left cheek, chin, brow, right eye, left eye, right cheek")
        XCTAssertEqual(Set((1...3).map { Self.firstSmear(seed: Float($0)) }).count, 3)
    }

    func testRenderedFirstSmearDiffersAndSavesCloseUps() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.place(SIMD2(0.4, 0.6))
        let dir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/5a467ba3-0e07-4f0a-81a4-9f51bd9e9c14/scratchpad/dirtcheck"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cam = BathCaptureTests.roomCam(s, focus: 1)
        for d: Float in [0.15, 0.4] {
            var imgs: [LockImage] = []
            for seed: Float in [1, 2, 3] {
                var l = BathCaptureTests.sooty(d); l.sootStyle = seed
                let im = BathCaptureTests.render(s, look: l, camera: cam)
                im.png(to: URL(fileURLWithPath: dir).appendingPathComponent("seed\(Int(seed))_dirt\(Int(d * 100)).png"))
                imgs.append(im)
            }
            XCTAssertNotEqual(Self.fnvOf(imgs[0]), Self.fnvOf(imgs[1])); XCTAssertNotEqual(Self.fnvOf(imgs[1]), Self.fnvOf(imgs[2])); XCTAssertNotEqual(Self.fnvOf(imgs[0]), Self.fnvOf(imgs[2]))
        }
    }
    static func fnvOf(_ i: LockImage) -> String { BathSootSeedZeroTests.fnv(i) }
}
