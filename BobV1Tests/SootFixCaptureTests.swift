//
//  SootFixCaptureTests.swift
//  Before/after for the soot cost fix: renders dirty Bob, Pip and Moss (own soot placement) at true phone proportion. The first run
//  stores the frames as references (scratchpad/sootref); later runs diff against them and write a labelled before/after sheet.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class SootFixCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let dir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/sootref"

    func testSootBeforeAfter() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        let W = 603, H = 1311
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let actors: [JellyActor] = (0..<3).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: .zero)
            a.reset(drop: 0.35, shift: false)
            for _ in 0..<300 { a.sim.step() }
            a.skinner.autoBlink = false
            return a
        }
        let ren = try XCTUnwrap(MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: actors[0].sim.edges, particleCount: actors[0].sim.n, game: true, bodyCount: 3))
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        Self.keep += actors; Self.keep.append(ren)
        for i in 1..<3 { ren.setPalette(JellyRoster.palette(i) ?? PaletteKey.blue.palette, body: i) }
        for a in actors { a.sim.teleport(toXZ: GameCamera.callSpot); for _ in 0..<90 { a.sim.step() } }
        let aspect = Float(W) / Float(H)

        func frame(cam: CameraState, show: Int, dirt: Float) -> LockImage {
            ren.roomCacheEnabled = false
            for i in 0..<3 {
                ren.setHidden(i != show, body: i)
                var l = BathLook(); l.dirt = dirt; l.soot = BathLook.sootSeed(dirt: dirt); l.sootStyle = Float(i)
                ren.setBathLook(l, body: i)
            }
            let light = GameCamera.light(centroids: actors.map { $0.sim.centroid() })
            for _ in 0..<2 {
                ren.beginFrame()
                for a in actors { a.skinner.update(x: a.sim.x, index: rm.index, into: ren.dynPointer(body: a.id)) }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7
                let pal = PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
            }
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        let cu = GameCamera.camera(aspect: aspect, focus: 1)
        var jobs: [(String, String, LockImage)] = []
        for (i, name) in ["Bob", "Pip", "Moss"].enumerated() {
            for d: Float in [0.5, 0.9] { jobs.append(("\(name.lowercased())_\(Int(d * 100))", "\(name) dirt \(d)", frame(cam: cu, show: i, dirt: d))) }
        }
        var before: [(String, LockImage)] = [], after: [(String, LockImage)] = []
        var report: [String] = []
        for (key, label, img) in jobs {
            let path = Self.dir + "/\(key).bgra"
            if let d = fm.contents(atPath: path) {
                let ref = LockImage(w: W, h: H, bgra: [UInt8](d))
                var differing = 0, maxd = 0
                for p in 0..<(W * H) {
                    let m = (0..<4).map { abs(Int(ref.bgra[4 * p + $0]) - Int(img.bgra[4 * p + $0])) }.max()!
                    if m > 0 { differing += 1; maxd = max(maxd, m) }
                }
                report.append("\(key): \(differing) px differ (\(String(format: "%.4f", Double(differing) / Double(W * H) * 100))%), max level \(maxd)")
                before.append(("BEFORE " + label, ref)); after.append(("AFTER " + label, img))
            } else {
                fm.createFile(atPath: path, contents: Data(img.bgra))
                report.append("\(key): reference stored")
            }
        }
        let text = report.joined(separator: "\n")
        print("SOOTDIFF\n" + text); NSLog("SOOTDIFF %@", text)
        try text.write(toFile: Self.dir + "/report.txt", atomically: true, encoding: .utf8)
        if !before.isEmpty {
            let pick = [1, 3, 5]
            let panels = pick.map { before[$0] } + pick.map { after[$0] }
            try BathJellyTests.sheet(panels, to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/sootfix.png"), columns: 3, panelHeight: 1000)
        }
    }
}
