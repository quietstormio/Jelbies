//
//  BaseBodyLockTests.swift
//  LOCKED BASE BODY: see docs/BaseBody.md. Fails if anything about Bob's rest body changes. Golden data lives in
//  BobV1Tests/BaseBodyGolden (base_lock.json + half-resolution renders), recorded from the phone build
//  (commit 3499dc0 + pastel colours + Release perf, 2026-10-14). Helpers are in BaseBodyDumpTests.swift.
//
//  Checks:
//   1. hashes of the constants, sim mesh, base render mesh (wave-arm capsules excluded), eye rig, skinned rest pose,
//      palettes and material defaults;
//   2. the Shaders.metal functions that draw the body (fsSoftMatte is compared without its mouth block);
//   3. the wave-arm capsules sit inside the body at rest;
//   4. 20 offscreen renders (4 palettes x front / 3/4 / right / left / back) against the golden images;
//   5. the app's reference-counted classes can be freed (guards the isolated-deinit crash).
//
//  Only a deliberate, user-requested body change may edit the golden files (re-record with BaseBodyDumpTests).
//

import XCTest
import simd
import CryptoKit
import UIKit
@testable import BobV1

private let lockBanner = "BASE BODY CHANGED — see docs/BaseBody.md"

nonisolated struct LockGolden: Decodable {
    var blocks: [String: String]
    var shaderChunks: [String: String]
    var fullResPixelSHA256: [String: String]
    var unlockedShaderChunks: [String]
}

@MainActor
final class BaseBodyLockTests: XCTestCase {

    // MARK: resources

    private static var goldenDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("BaseBodyGolden", isDirectory: true)
    }

    /// Test bundle resource first, then the source folder (same files).
    private func resource(_ name: String, _ ext: String) throws -> URL {
        if let u = Bundle(for: BaseBodyLockTests.self).url(forResource: name, withExtension: ext) { return u }
        let u = Self.goldenDir.appendingPathComponent("\(name).\(ext)")
        guard FileManager.default.fileExists(atPath: u.path) else { throw XCTSkip("missing golden resource \(name).\(ext)") }
        return u
    }

    private func golden() throws -> LockGolden {
        try JSONDecoder().decode(LockGolden.self, from: Data(contentsOf: resource("base_lock", "json")))
    }

    // MARK: 1. hashes

    func testBaseBodyHashes() throws {
        let g = try golden()
        let now = try lockBuildBlocks(writeTo: nil)
        XCTAssertFalse(g.blocks.isEmpty)
        for (name, expected) in g.blocks.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(now[name], expected, "\(lockBanner): block '\(name)' differs from the phone build")
        }
    }

    // MARK: 2. shader

    func testBodyShaderFunctionsUnchanged() throws {
        let g = try golden()
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("BobV1/Melon/Shaders.metal")
        let text = try String(contentsOf: url, encoding: .utf8)
        let now = ShaderChunks.hashes(of: ShaderChunks.stripMouth(text))
        for (name, expected) in g.shaderChunks.sorted(by: { $0.key < $1.key }) where !g.unlockedShaderChunks.contains(name) {
            XCTAssertEqual(now[name], expected, "\(lockBanner): Shaders.metal '\(name)' changed (fsSoftMatte is compared without the mouth block)")
        }
    }

    // MARK: 3. capsules hidden at rest

    func testWaveCapsulesInsideBodyAtRest() throws {
        let ap = BlobAppearance.berry
        let sm = buildSimMesh(appearance: ap), rm = buildRenderMesh(appearance: ap)
        guard let caps = lockCapsules(rm) else { return }   // phone build: no capsules
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let rig = buildEyeRig(render: rm, sim: sm, appearance: ap)
        let body = SoftBody(mesh: sm, firmness: 0.95, damping: 0.45)
        body.reset(drop: 0)
        let skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount, eyes: rig, antennae: buildAntennaRig(render: rm, sim: sm))
        var dyn = [Float](repeating: 0, count: rm.vertexCount * 6)
        dyn.withUnsafeMutableBufferPointer { skinner.update(x: body.x, index: rm.index, into: $0.baseAddress!) }
        var worstRest = -Double.infinity, worstSkinned = -Double.infinity
        for v in caps.vertexRange {
            let p = SIMD3<Double>(Double(rm.rest[3 * v]), Double(rm.rest[3 * v + 1]), Double(rm.rest[3 * v + 2]))
            let q = SIMD3<Double>(Double(dyn[6 * v]), Double(dyn[6 * v + 1]), Double(dyn[6 * v + 2]))
            worstRest = max(worstRest, BobForm.sdf(p)); worstSkinned = max(worstSkinned, BobForm.sdf(q))
        }
        XCTAssertLessThan(worstRest, -0.01, "\(lockBanner): a wave-arm capsule vertex pokes out of the body at rest (rest mesh)")
        XCTAssertLessThan(worstSkinned, -0.01, "\(lockBanner): a wave-arm capsule vertex pokes out of the body at rest (skinned)")
        // capsule triangles must touch capsule vertices only (so base vertex normals cannot change)
        var t = caps.indexFirst
        while t < caps.indexFirst + caps.indexCount {
            for k in 0..<3 { XCTAssertTrue(caps.vertexRange.contains(Int(rm.index[t + k])), "\(lockBanner): capsule triangle uses a body vertex") }
            t += 3
        }
        print("LOCKCAPS worst sdf rest \(worstRest) skinned \(worstSkinned)")
    }

    // MARK: 4. renders

    private func halfGolden(_ name: String) throws -> (w: Int, h: Int, px: [UInt8]) {
        let url = try resource("\(name)_half", "png")
        guard let ui = UIImage(contentsOfFile: url.path), let cg = ui.cgImage else { throw XCTSkip("cannot decode \(name)_half.png") }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = px.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        }
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, px)
    }

    func testGoldenRendersUnchanged() throws {
        let g = try golden()
        let scene = try XCTUnwrap(LockScene())
        var worstOverall = 0
        for (tag, key) in lockPalettes { for v in lockViews {
            let name = "\(tag)_\(v.name)"
            let img = scene.render(v, palette: key)
            let half = try halfGolden(name)
            XCTAssertEqual(half.w * 2, img.w, name); XCTAssertEqual(half.h * 2, img.h, name)
            // 2x2 box downsample of the fresh render vs the stored half-resolution golden
            var worst = 0
            for y in 0..<half.h { for x in 0..<half.w { for c in 0..<3 {
                var sum = 0
                for dy in 0..<2 { for dx in 0..<2 { sum += Int(img.bgra[((2 * y + dy) * img.w + 2 * x + dx) * 4 + c]) } }
                worst = max(worst, abs((sum + 2) / 4 - Int(half.px[(y * half.w + x) * 4 + c])))
            } } }
            worstOverall = max(worstOverall, worst)
            XCTAssertLessThanOrEqual(worst, 2, "\(lockBanner): render '\(name)' differs from the golden image (max level diff \(worst))")
            let sha = SHA256.hash(data: Data(img.bgra)).map { String(format: "%02x", $0) }.joined()
            if sha != g.fullResPixelSHA256[name] {
                // Half-res within tolerance but not bit-identical: GPU / OS rendering drift, not a body change.
                print("LOCKNOTE \(name): full-res SHA differs from the recording (half-res diff \(worst))")
            }
        } }
        print("LOCKRENDER worst half-res level diff \(worstOverall) over 20 images")
    }

    // MARK: 5. lifetimes (guards the Swift 6.2 isolated-deinit abort: "pointer being freed was not allocated")

    func testAppClassesCanBeFreed() throws {
        var model: MelonModel? = MelonModel(); model = nil
        var care: GameCare? = GameCare(); care = nil
        var brain: BlobBrain? = BlobBrain(); brain = nil
        var scene: LockScene? = try XCTUnwrap(LockScene())     // SoftBody, Skinner, MelonRenderer
        _ = scene?.render(lockViews[0], palette: .blush)
        scene = nil
        var controller: MelonController? = MelonController(model: MelonModel()); controller = nil
        XCTAssertNil(model); XCTAssertNil(care); XCTAssertNil(brain); XCTAssertNil(scene); XCTAssertNil(controller)
    }
}
