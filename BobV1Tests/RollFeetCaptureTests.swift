//
//  RollFeetCaptureTests.swift
//  Not a regression test: when ROLL_FEET_CAP_DIR is set (TEST_RUNNER_ROLL_FEET_CAP_DIR) it writes frame strips of the rolls with the real game
//  renderer (room, game camera), bare and in shoes, with the drawn-foot measurement of each frame in the label and in the motion log.
//  User, 2026-10-21 (phone): "When he rolled randomly his feet came off again."
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class RollFeetCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func dir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["ROLL_FEET_CAP_DIR"], !d.isEmpty else { throw XCTSkip("ROLL_FEET_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    private func sheet(_ rows: [(String, [(String, LockImage)])], cw: Int, to path: String, cols: Int) throws {
        let ch = rows.flatMap { $0.1 }.map { Int(Double(cw) * Double($0.1.h) / Double($0.1.w)) }.max() ?? cw
        let labelH = 30, pad = 6, cellLabel = 30
        let sw = cols * (cw + pad) + pad
        var heights: [Int] = []
        for r in rows { heights.append(((r.1.count + cols - 1) / cols) * (ch + cellLabel + pad) + labelH) }
        let sh = heights.reduce(0, +) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            var y = pad
            for (ri, row) in rows.enumerated() {
                (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y + 6)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
                for (c, cell) in row.1.enumerated() {
                    let cx = pad + (c % cols) * (cw + pad), cy = y + labelH + (c / cols) * (ch + cellLabel + pad)
                    (cell.0 as NSString).draw(in: CGRect(x: cx + 2, y: cy, width: cw, height: cellLabel), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor(white: 0.85, alpha: 1)])
                    if let ui = cell.1.uiImage() { ui.draw(in: CGRect(x: cx, y: cy + cellLabel, width: cw, height: Int(Double(cw) * Double(cell.1.h) / Double(cell.1.w)))) }
                }
                y += heights[ri]
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: path))
    }

    /// One roll, rendered through the game renderer. `midWalk`: the rollTrip started by the walk's own hook; else the idle `.roll` antic from standing.
    private func strip(midWalk: Bool, shoes: Bool, seconds: Float, every: Int, device: MTLDevice, target: MTLTexture, Wc: Int, Hc: Int, C: Int) throws -> [(String, LockImage)] {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.skinner.autoBlink = false
        r.brain.seed = 11; r.brain.idleMood = .happy; r.brain.anticsEnabled = true; r.brain.autonomy = true
        r.brain.restTimer = 1e6; r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6
        r.brain.expr.pickTimer = 1e6
        r.brain.shoesWorn = shoes
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: Wc, height: Hc)
        let cam = GameCamera.camera(aspect: Float(Wc) / Float(Hc), focus: 0)
        r.sim.teleport(toXZ: SIMD2(-0.4, -0.5))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        var started = false
        if midWalk {
            guard let goal = r.brain.pickRunGoal(from: r.root, minD: 3.0, maxD: 4.4) else { throw XCTSkip("no goal") }
            r.brain.script = .walk(target: goal, then: .none); r.brain.activity = .walking
            r.brain.scriptT = 0; r.brain.leg = LegState()
            r.run(0.1)
            r.brain.leg.kind = .rollTrip; r.brain.leg.wants = true; r.brain.leg.rolled = false; r.brain.leg.trigger = 0.5; r.brain.leg.from = r.brain.position
            r.run(4.0, until: { r.brain.idleState.kind == .rollTrip })
            started = r.brain.idleState.kind == .rollTrip
        } else {
            r.run(1.0)
            r.brain.idleForced = true
            started = r.brain.idleStart(.roll, r.sim)
        }
        XCTAssertTrue(started, "roll started (midWalk \(midWalk) shoes \(shoes))")
        var out: [(String, LockImage)] = []
        var i = 0, t0: Float = 0
        let total = Int(seconds * 60)
        let tag = "\(midWalk ? "rollTrip" : "roll")\(shoes ? "+shoes" : "")"
        while i < total {
            r.tick()
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            if i % every == 0 {
                ren.beginFrame()
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                ren.setMouth(r.brain.mouthOpen, body: 0); ren.setBlush(r.brain.blushNow, body: 0)
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0
                let pal = PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                let light = GameCamera.light(centroid: r.sim.centroid())
                ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(Wc), Float(Hc)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
                var px = [UInt8](repeating: 0, count: Wc * Hc * 4)
                px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: Wc * 4, from: MTLRegionMake2D(0, 0, Wc, Hc), mipmapLevel: 0) }
                let c = r.sim.centroid()
                let clip = cam.viewProj * SIMD4<Float>(c.x, 0.45, c.z, 1)
                let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(Wc)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(Hc))
                let x0 = max(0, min(Wc - C, sx - C / 2)), y0 = max(0, min(Hc - C, sy - C / 2))
                var o = [UInt8](repeating: 0, count: C * C * 4)
                for y in 0..<C { for x in 0..<(C * 4) { o[y * C * 4 + x] = px[(y0 + y) * Wc * 4 + x0 * 4 + x] } }
                // the drawn foot this frame (beans if out, else the embedded foot), in the fitted body frame
                let f = FeetAttachTests.drawnFootFrame(r)
                let m = String(format: "%@ %.2fs %@ ph=%@ beans=%d bG=%.2f | rise %.3f ch %.3f rad %.3f ovl %.3f", tag, t0, "\(r.brain.idleState.kind.map { $0.rawValue } ?? "-")", "\(r.brain.gait.phase)", r.skinner.beansActive ? 1 : 0, r.brain.beanG, f.soleRise, f.centreHeight, f.radius, f.overlap)
                MotionLog.write("ROLLFEET " + m)
                out.append((String(format: "%.2fs %@ beans %d\nrise %.2f ch %.2f rad %.2f ovl %.3f", t0, "\(r.brain.gait.phase)", r.skinner.beansActive ? 1 : 0, f.soleRise, f.centreHeight, f.radius, f.overlap), LockImage(w: C, h: C, bgra: o)))
            }
            i += 1; t0 += 1.0 / 60
            if r.brain.idleState.kind == nil, i > 20, out.count >= 4 { break }
        }
        return out
    }

    /// The rows the stricter embedded-foot check flags: the frames with the largest embedded-foot overlap of each, rendered so they can be judged by eye.
    func testWorstFrames() throws {
        let d = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let names = (ProcessInfo.processInfo.environment["ROLL_FEET_WORST"] ?? "antic: roll,flourish: roll along the leg,sleep: roll onto the back and up again,belly slide,flip").split(separator: ",").map(String.init)
        let Wc = 1080, Hc = 1920, C = 420
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Wc, height: Hc, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: Float(Wc) / Float(Hc))
        defer { DecorField.shared.clear() }
        var rows: [(String, [(String, LockImage)])] = []
        for name in names {
            guard let m = FeetAttachTests.moves.first(where: { $0.name == name }) else { XCTFail("no move \(name)"); continue }
            let r = MotionRig(game: m.game); Self.keep.append(r)
            r.renderSamples = false
            guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
            ren.resize(width: Wc, height: Hc)
            let cam = GameCamera.camera(aspect: Float(Wc) / Float(Hc), focus: 0)
            m.start(r)
            var shots: [(Float, String, LockImage)] = []
            var clock: Float = 0, lastShot: Float = -1
            r.run(m.seconds) {
                m.each?(r)
                clock += 1.0 / 60
                if m.name.hasPrefix("soccer") { DecorField.shared.tick(dt: 1.0 / 60) }
                let beans = r.skinner.beansActive && r.skinner.beanBlend > 0.05
                let f = FeetAttachTests.drawnFootFrame(r)
                // the frames worth looking at: the embedded foot more than 0.5 cm out, at most every 0.1 s, plus one in four seconds of context
                let interesting = !beans && f.overlap > 0.005 && clock - lastShot >= 0.1
                let context = clock - lastShot >= 4.0
                guard interesting || context else { return }
                lastShot = clock
                ren.beginFrame()
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                ren.setMouth(r.brain.mouthOpen, body: 0); ren.setBlush(r.brain.blushNow, body: 0)
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0
                let pal = PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: GameCamera.light(centroid: r.sim.centroid()), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(Wc), Float(Hc)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
                var px = [UInt8](repeating: 0, count: Wc * Hc * 4)
                px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: Wc * 4, from: MTLRegionMake2D(0, 0, Wc, Hc), mipmapLevel: 0) }
                let c = r.sim.centroid()
                let clip = cam.viewProj * SIMD4<Float>(c.x, 0.45, c.z, 1)
                let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(Wc)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(Hc))
                let x0 = max(0, min(Wc - C, sx - C / 2)), y0 = max(0, min(Hc - C, sy - C / 2))
                var o = [UInt8](repeating: 0, count: C * C * 4)
                for y in 0..<C { for x in 0..<(C * 4) { o[y * C * 4 + x] = px[(y0 + y) * Wc * 4 + x0 * 4 + x] } }
                shots.append((f.overlap, String(format: "%.2fs %@ %@ beans %d\nrise %.2f ch %.2f rad %.2f ovl %.3f", clock, "\(r.brain.idleState.kind.map { $0.rawValue } ?? "-")", "\(r.brain.gait.phase)", beans ? 1 : 0, f.soleRise, f.centreHeight, f.radius, f.overlap), LockImage(w: C, h: C, bgra: o)))
            }
            // the 9 worst by overlap, shown in time order
            let keep = shots.sorted { $0.0 > $1.0 }.prefix(9).sorted { $0.1 < $1.1 }
            rows.append((name, keep.map { ($0.1, $0.2) }))
            MotionLog.write("ROLLFEET worst \(name): \(shots.count) shots, top overlaps \(shots.map { $0.0 }.sorted(by: >).prefix(5).map { String(format: "%.3f", $0) })")
        }
        try sheet(rows, cw: 180, to: d + "/worst_sheet.png", cols: 9)
    }

    func testRollStrips() throws {
        let d = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let Wc = 1080, Hc = 1920, C = 420
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Wc, height: Hc, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: Float(Wc) / Float(Hc))
        var rows: [(String, [(String, LockImage)])] = []
        for (label, mid, shoes) in [("rollTrip mid-walk, bare", true, false), ("rollTrip mid-walk, shoes on (beans always out)", true, true), ("idle roll, bare", false, false), ("idle roll, shoes on", false, true)] {
            let s = try strip(midWalk: mid, shoes: shoes, seconds: 2.6, every: 6, device: device, target: target, Wc: Wc, Hc: Hc, C: C)
            rows.append((label, s))
            for (ci, c) in s.enumerated() { c.1.png(to: URL(fileURLWithPath: d + "/\(mid ? "rollTrip" : "roll")\(shoes ? "_shoes" : "")_\(String(format: "%02d", ci)).png")) }
        }
        try sheet(rows, cw: 180, to: d + "/roll_sheet.png", cols: 9)
    }
}
