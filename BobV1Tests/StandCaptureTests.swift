//
//  StandCaptureTests.swift
//  Not a regression test: contact sheets of every hop-sit piece (hop up, on the seat in motion, hop down) with the REAL renderer and the game camera,
//  when STAND_CAP_DIR is set (TEST_RUNNER_STAND_CAP_DIR). STAND_CAP_TAG names the files (before / after). Characters: 0 Bob, 1 Pip, 2 Moss, 3 Lavender.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class StandCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var dir: String? { ProcessInfo.processInfo.environment["STAND_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }
    var tag: String { ProcessInfo.processInfo.environment["STAND_CAP_TAG"] ?? "run" }
    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { DecorField.shared.clear(); ToyTuning.settle = 5; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    /// One run: `chars` Jelbies each go to the piece; returns cells (hop up, on the seat x3, hop down) cropped round the piece.
    func run(_ kind: DecorKind, chars: [Int], at: SIMD2<Float> = SIMD2(0.2, 0.3), turns: Int? = nil, land: Bool = false, seconds: Float = 30) throws -> [(UIImage, String)] {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let W = land ? 1311 : 603, H = land ? 603 : 1311, S: Float = 1.5
        let pw = Int(Float(W) * S), ph = Int(Float(H) * S)
        let a = Float(W) / Float(H)
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        let starts: [SIMD2<Float>] = chars.count == 1 ? [SIMD2(-1.6, 1.6)] : [SIMD2(-1.8, 1.6), SIMD2(1.7, 1.7)]
        let lab = SocialTests.Lab(n: chars.count, positions: starts, quiet: false, seed: 11)
        SocialTests.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.brain.anticsEnabled = true; r.brain.sleepEnabled = false; r.brain.idleMood = .happy; r.skinner.autoBlink = false
            r.brain.feature = JellyRoster.feature(chars[k])
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        DecorField.shared.set([PlacedDecor(uid: 1, kind: kind, x: at.x, z: at.y, turns: turns)]); DecorField.shared.toys = ToyBook()
        var started = 0
        for r in lab.rigs { if r.brain.decorStart(.decorSit, r.sim, only: kind, uid: 1) { started += 1 } }
        XCTAssertEqual(started, chars.count, "\(kind): everyone found a seat")
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: lab.rigs[0].sim.edges, particleCount: lab.rigs[0].sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: pw, height: ph); ren.roomCacheEnabled = false; ren.dayHourOverride = 12
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pw, height: ph, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        var feats: [FeatureSet] = []
        for _ in chars { let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f); feats.append(f) }
        var cam = GameCamera.camera(aspect: a, focus: 0)
        let sideView = ProcessInfo.processInfo.environment["STAND_CAP_SIDE"] != nil
        if sideView {
            let c = SIMD3<Float>(at.x, 0.9, at.y), eye = c + SIMD3(9.0, 2.2, 5.0)
            cam = CameraState()
            cam.view = M4.lookAt(eye: eye, at: c, up: SIMD3(0, 1, 0))
            cam.viewProj = M4.mul(M4.perspective(fovy: 32 * .pi / 180, aspect: a, near: 0.1, far: 60), cam.view)
            cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(c - eye)
        }

        func frame() -> LockImage {
            ren.room!.setDecorStatic(DecorModels.build(feet: DecorField.shared.feet, field: DecorField.shared, time: 0.4))
            func one(_ only: Int?) -> LockImage {
                let k = only ?? 0
                let light = GameCamera.light(centroids: lab.rigs.map { $0.sim.centroid() })
                ren.beginFrame()
                let r = lab.rigs[k]
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
                if only != nil {
                    var sk = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
                    r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &sk)
                    let ff = sk.withUnsafeBufferPointer { p in feats[k].frame { _ in p.baseAddress } }
                    ren.room!.setWear(opaque: ff, translucent: RoomMesh(), bounds: [])
                } else { ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []) }
                ren.setMouth(0, body: 0)
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0
                let pal = JellyRoster.palette(chars[k]) ?? PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(pw), Float(ph)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
                var px = [UInt8](repeating: 0, count: pw * ph * 4)
                px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: pw * 4, from: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0) }
                return LockImage(w: pw, h: ph, bgra: px)
            }
            _ = one(nil)
            let empty = one(nil)
            var out = empty
            for k in (0..<lab.rigs.count).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z }) {
                let b = one(k)
                for p in 0..<(pw * ph) {
                    var d = 0
                    for c in 0..<3 { d = max(d, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                    if d > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
                }
            }
            return out
        }
        func crop(_ img: LockImage) -> UIImage? {
            let v = cam.viewProj * SIMD4<Float>(at.x, sideView ? 0.9 : 0.55, at.y, 1)
            let cx = (v.x / v.w * 0.5 + 0.5) * Float(pw), cy = (1 - (v.y / v.w * 0.5 + 0.5)) * Float(ph)
            let base: Float = [.swing: 560, .seesaw: 520, .sandbox: 700, .diningset: 600, .loveseat: 560, .cushionpile: 420][kind] ?? 380
            let zoom = Float(ProcessInfo.processInfo.environment["STAND_CAP_ZOOM"] ?? "") ?? 1
            let side = (land ? base * 0.75 : base) * zoom
            let r = CGRect(x: CGFloat(cx - side / 2), y: CGFloat(cy - side * (sideView ? 0.5 : 0.62)), width: CGFloat(side), height: CGFloat(side)).intersection(CGRect(x: 0, y: 0, width: pw, height: ph))
            guard let cg = img.cgImage(), let part = cg.cropping(to: r) else { return nil }
            return UIImage(cgImage: part)
        }

        var cells: [(UIImage, String)] = []
        var seen = Set<String>()
        var settledAt: Float? = nil
        func once(_ k: String) -> Bool { if seen.contains(k) { return false }; seen.insert(k); return true }
        for i in 0..<Int(seconds * 60) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for (k, r) in lab.rigs.enumerated() {
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                feats[k].tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(chars[k]), worn: [], hideAll: false, dt: 1.0 / 60)
            }
            let bs = lab.rigs.map { $0.brain }
            var label: String? = nil
            let t = Float(i) / 60
            let allOn = bs.allSatisfy { $0.idleState.bagStage == 2 && $0.idleState.phase == 2 }
            if allOn { for b in bs { b.idleState.hold = max(b.idleState.hold, 99) } ; if settledAt == nil { settledAt = t } }
            if bs[0].idleState.bagStage == 1, bs[0].idleState.phaseT > 0.13, once("up") { label = "hop up" }
            else if let s = settledAt, allOn {
                if t - s > 0.5, once("m1") { label = "on the seat +0.5s" }
                else if t - s > 1.4, once("m2") { label = "on the seat +1.4s" }
                else if t - s > 2.3, once("m3") { label = "on the seat +2.3s" }
                else if t - s > 3.0 { for b in bs { b.idleState.hold = 0 } }
            }
            if bs.contains(where: { $0.idleState.bagStage == 3 && $0.idleState.phaseT > 0.14 }), once("down") { label = "hop down" }
            if let l = label, let im = crop(frame()) { cells.append((im, l)) }
            if seen.contains("down"), bs.allSatisfy({ $0.idleState.kind == nil }) { break }
        }
        return cells
    }

    func sheet(_ rows: [(String, [(UIImage, String)])], cell: CGFloat = 330, title: String) -> UIImage {
        let cols = rows.map { $0.1.count }.max() ?? 1, bar: CGFloat = 26, head: CGFloat = 44, lab: CGFloat = 0
        let W = cell * CGFloat(cols), H = head + CGFloat(rows.count) * (cell + bar) + lab
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { _ in
            UIColor(white: 0.08, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))
            (title as NSString).draw(at: CGPoint(x: 10, y: 8), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.white])
            for (r, row) in rows.enumerated() {
                let y = head + CGFloat(r) * (cell + bar)
                for (c, cl) in row.1.enumerated() {
                    let x = CGFloat(c) * cell
                    ("\(row.0): \(cl.1)" as NSString).draw(at: CGPoint(x: x + 6, y: y + 4), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
                    cl.0.draw(in: CGRect(x: x, y: y + bar, width: cell, height: cell))
                }
            }
        }
    }
    func save(_ img: UIImage, _ name: String) throws {
        guard let dir else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try img.pngData()?.write(to: URL(fileURLWithPath: dir + "/" + name))
    }

    static let seatPieces: [DecorKind] = [.beanbag, .pouf, .armchair, .loveseat, .diningset, .rockingchair, .swing, .cushionpile, .rockinghorse, .toyrocket, .seesaw, .springrider, .sandbox]

    /// Every seat piece alone with Bob: part A (home furniture) and part B (toys).
    func testCaptureAllSeats() throws {
        guard dir != nil else { throw XCTSkip("STAND_CAP_DIR not set") }
        var rows: [(String, [(UIImage, String)])] = []
        let only = ProcessInfo.processInfo.environment["STAND_CAP_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        for k in Self.seatPieces where only == nil || only!.contains(k.rawValue) {
            let cells = try run(k, chars: [0])
            XCTAssertFalse(cells.isEmpty, "\(k) captured")
            rows.append((k.rawValue, cells))
        }
        for (i, part) in stride(from: 0, to: rows.count, by: 3).enumerated() { try save(sheet(Array(rows[part..<min(part + 3, rows.count)]), cell: 360, title: "Seats alone, Bob, portrait [\(tag)] part \(i + 1)"), "seats\(i + 1)_\(tag).png") }
    }

    /// Two Jelbies at once: Bob + Pip, Moss + Lavender on the swing, the seesaw, the sandbox.
    func testCaptureTwoOnPieces() throws {
        guard dir != nil else { throw XCTSkip("STAND_CAP_DIR not set") }
        var rows: [(String, [(UIImage, String)])] = []
        for k in [DecorKind.swing, .seesaw, .sandbox, .diningset] {
            for pair in [[0, 1], [2, 3]] {
                rows.append(("\(k.rawValue) \(pair.map { JellyRoster.baseNames[$0] }.joined(separator: "+"))", try run(k, chars: pair)))
            }
        }
        try save(sheet(Array(rows.prefix(4)), title: "Two Jelbies [\(tag)] swing, seesaw"), "two1_\(tag).png")
        try save(sheet(Array(rows.dropFirst(4)), title: "Two Jelbies [\(tag)] sandbox, cushion pile, dining"), "two2_\(tag).png")
    }

    /// Each character alone on the pieces where a tail / wings / daisy could meet the seat.
    func testCaptureCharacters() throws {
        guard dir != nil else { throw XCTSkip("STAND_CAP_DIR not set") }
        var rows: [(String, [(UIImage, String)])] = []
        for k in [DecorKind.swing, .pouf, .rockinghorse, .springrider] {
            for c in 1...3 { rows.append(("\(k.rawValue) \(JellyRoster.baseNames[c])", try run(k, chars: [c]))) }
        }
        try save(sheet(Array(rows.prefix(6)), title: "Characters [\(tag)] swing, pouf"), "chars1_\(tag).png")
        try save(sheet(Array(rows.dropFirst(6)), title: "Characters [\(tag)] rocking horse, spring bunny"), "chars2_\(tag).png")
    }

    /// Landscape: a few pieces.
    func testCaptureLandscape() throws {
        guard dir != nil else { throw XCTSkip("STAND_CAP_DIR not set") }
        var rows: [(String, [(UIImage, String)])] = []
        for k in [DecorKind.swing, .seesaw, .pouf, .armchair] { rows.append((k.rawValue, try run(k, chars: k == .swing || k == .seesaw ? [0, 1] : [0], land: true))) }
        try save(sheet(rows, title: "Landscape [\(tag)]"), "land_\(tag).png")
    }
}

extension StandCaptureTests {
    /// Prints each seat piece's parts' bounds (authored units, before the piece's scale) next to its seat points.
    func testDumpSeatBounds() throws {
        var out = ""
        for k in Self.seatPieces {
            guard let art = DecorMeshes.loaded[k] else { out += "\(k): parametric (no art)\n"; continue }
            out += "\(k) scale \(k.scale)/\(k.scaleX) sit \(k.sitPoints)\n"
            for p in art.parts {
                var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
                for v in p.positions { lo = simd_min(lo, v); hi = simd_max(hi, v) }
                out += String(format: "   %@ lo (%.2f %.2f %.2f) hi (%.2f %.2f %.2f)\n", p.name, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z)
            }
        }
        if let art = DecorMeshes.loaded[.swing] {
            for p in art.parts where p.name == "seat" {
                var xs = Set<Int>()
                for v in p.positions where v.y > 1.2 { xs.insert(Int((v.x * 20).rounded())) }
                out += "swing rope-height x (1/20): \(xs.sorted())\n"
            }
        }
        for k in [DecorKind.pouf, .cushionpile, .rockinghorse, .toyrocket] {
            guard let art = DecorMeshes.loaded[k] else { continue }
            out += "\(k) top surface (max y) by x, |z|<0.15:\n  "
            for xi in stride(from: -0.9, through: 0.9, by: 0.1) {
                var m: Float = -9
                for p in art.parts { for v in p.positions where abs(v.x - Float(xi)) < 0.06 && abs(v.z) < 0.15 { m = max(m, v.y) } }
                out += String(format: "%.1f:%.2f ", xi, m)
            }
            out += "\n"
        }
        try out.write(toFile: (dir ?? "/tmp") + "/bounds.txt", atomically: true, encoding: .utf8)
    }
}
