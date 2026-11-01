//
//  OnePieceBoardTests.swift
//  Not a regression test: the proof board of the one-piece feet (2026-10-31). Run it once with ONEPIECE_BEFORE=1 (the e4062d6 join) and once without, same
//  deterministic moves, same frames; files land in ONEPIECE_BOARD_DIR/<name>_<before|after>.png. Everything is rendered with the game renderer in the room of
//  three Jelbies at the real game camera, shoes through the room's shoe mesh, like LegsGameCamCaptureTests.
//  Env: TEST_RUNNER_ONEPIECE_BOARD_DIR (required), TEST_RUNNER_ONEPIECE_BEFORE=1, TEST_RUNNER_ONEPIECE_CASES="a,b" (name parts).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class OnePieceBoardTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias Pacing = OnePieceInvariantTests.Pacing

    enum Pick { case tilted(Int), beans(Int), consecutive(Int, around: Int), standing }

    struct Spec {
        let name: String
        let char: Int
        var shoes = false
        var pacing: Pacing = .hz60
        var start: (MotionRig) -> Bool
        var pick: Pick
        var seconds: Float = 5
        var cams: [Cam] = [.side, .front]
        var dist: Float = 8.0
        var closeUp = false
        var each: ((MotionRig) -> Void)? = nil
    }
    enum Cam { case side, front, game }

    static func specs() -> [Spec] {
        func idle(_ k: IdleKind) -> (MotionRig) -> Bool { { r in r.brain.idleForced = true; return r.brain.idleStart(k, r.sim) } }
        func volley(_ dive: Bool) -> (MotionRig) -> Bool { { r in
            let c = r.root
            r.brain.volleyBegin(sim: r.sim, skinner: r.skinner, x: c.x, z: c.y, side: -1)
            for _ in 0..<30 { r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false); r.sim.step() }
            if dive { r.brain.volleyDive(sim: r.sim, dir: -1) } else { r.brain.volleyJump(sim: r.sim, dx: 0.3, apex: 0.45) }
            return true } }
        var out: [Spec] = []
        for (cn, c) in [("Bob", 0), ("Teddy", 4)] {
            out.append(Spec(name: "01_flip_\(cn)", char: c, start: { $0.brain.startFlip(sim: $0.sim); return true }, pick: .tilted(8), seconds: 3))
            out.append(Spec(name: "01_faceplant_\(cn)", char: c, start: { $0.brain.startFlip(sim: $0.sim, fail: true); return true }, pick: .tilted(8), seconds: 4))
            out.append(Spec(name: "01_volleyDive_\(cn)", char: c, start: volley(true), pick: .tilted(8), seconds: 2.5))
            out.append(Spec(name: "01_hop_\(cn)", char: c, start: { $0.brain.startHopPlay(sim: $0.sim); return true }, pick: .beans(8), seconds: 3))
            out.append(Spec(name: "01_walk_\(cn)", char: c, start: { $0.brain.request(.goTo(SIMD2(1.6, 0.4))); return true }, pick: .beans(8), seconds: 6))
            // 02 close-ups of a foot root: standing, mid-roll, mid-flip (one row each: standing + the tilted frames)
            out.append(Spec(name: "02_close_standing_\(cn)", char: c, start: { _ in true }, pick: .standing, seconds: 0.3, cams: [.side, .front], dist: 3.2, closeUp: true))
            out.append(Spec(name: "02_close_flip_\(cn)", char: c, start: { $0.brain.startFlip(sim: $0.sim); return true }, pick: .tilted(6), seconds: 3, cams: [.side, .front], dist: 3.2, closeUp: true))
            // 03 shoes in walk / roll / flip
            out.append(Spec(name: "03_shoes_walk_\(cn)", char: c, shoes: true, start: { $0.brain.request(.goTo(SIMD2(1.6, 0.4))); return true }, pick: .beans(6), seconds: 6))
            out.append(Spec(name: "03_shoes_flip_\(cn)", char: c, shoes: true, start: { $0.brain.startFlip(sim: $0.sim); return true }, pick: .tilted(8), seconds: 3))
        }
        // 04 hitch pacing: consecutive frames around the roll's peak tilt
        for p in [Pacing.alt12, .burst30] {
            out.append(Spec(name: "04_hitch_\(p.name)_flip_Teddy", char: 4, pacing: p, start: { $0.brain.startFlip(sim: $0.sim); return true }, pick: .consecutive(8, around: 0), seconds: 4))
        }
        // 05 the user's phone frame: Teddy mid side-roll in the room, game camera at the photo's framing, full-resolution crop
        out.append(Spec(name: "05_phoneframe_flip_Teddy", char: 4, start: { $0.brain.startFlip(sim: $0.sim); return true }, pick: .tilted(6), seconds: 3, cams: [.game], dist: 0))
        return out
    }

    func testBoard() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["ONEPIECE_BOARD_DIR"], !dir.isEmpty else { throw XCTSkip("ONEPIECE_BOARD_DIR not set") }
        _ = OnePieceInvariantTests.configured
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let only = (env["ONEPIECE_CASES"] ?? "").split(separator: ",").map(String.init)
        for sp in Self.specs() where only.isEmpty || only.contains(where: { sp.name.contains($0) }) { try capture(sp, dir: dir, device: device) }
    }

    /// The scene: the mover (character `sp.char`) at the front spot, two others behind. Returns the rigs and the feature set.
    @MainActor final class Scene {
        var rigs: [MotionRig] = []
        let feats = FeatureSet()
        var order: [Int] = []
    }

    func makeScene(_ sp: Spec) -> Scene {
        let sc = Scene()
        let rm = MotionRig.renderMesh
        var ids = [0, 5, 4]
        if sp.char == 0 { ids = [0, 5, 4] } else { ids = [sp.char, sp.char == 5 ? 0 : 5, sp.char == 0 ? 4 : 0] }
        if sp.char != 0 && !ids.contains(0) { ids[2] = 0 }
        sc.order = ids
        let spots = JellyRoster.spawnSpots(count: 3)
        for (k, id) in ids.enumerated() {
            let r = MotionRig(game: true, settle: 0.5); Self.keep.append(r)
            r.renderSamples = false; r.skinner.autoBlink = false
            r.brain.feature = JellyRoster.feature(id)
            r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            if OnePieceInvariantTests.before { r.skinner.joinEnabled = false; r.skinner.collarEnabled = false }
            r.sim.teleport(toXZ: spots[k]); for _ in 0..<90 { r.sim.step() }
            r.brain.currentPose(r.sim)
            sc.rigs.append(r)
        }
        WearBody.install(rm)
        sc.feats.body = WearBody.shared; Self.keep.append(sc.feats)
        return sc
    }

    func capture(_ sp: Spec, dir: String, device: MTLDevice) throws {
        let W = 1320, H = 2868
        let mode = OnePieceInvariantTests.before ? "before" : "after"
        let rm = MotionRig.renderMesh
        let pickCount: Int
        switch sp.pick { case .tilted(let n), .beans(let n), .consecutive(let n, _): pickCount = n; case .standing: pickCount = 1 }
        // pass 1: which frames to take; pass 2: render them (the run is deterministic)
        var chosen: [Int] = []
        for pass in 0..<2 {
            let sc = makeScene(sp)
            let me = sc.rigs[0]
            me.brain.shoesWorn = sp.shoes
            me.brain.seed = 11
            me.brain.peers = { [unowned a = sc.rigs[1], b = sc.rigs[2]] in [(id: 1, pos: a.root), (id: 2, pos: b.root)] }
            me.brain.steerID = 0; me.brain.peerGap = 0.9
            guard sp.start(me) else { XCTFail("\(sp.name) did not start"); Self.keep.removeAll(); return }
            var ren: MelonRenderer? = nil, tex: MTLTexture? = nil
            if pass == 1 {
                guard let rr = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: me.sim.edges, particleCount: me.sim.n, game: true, bodyCount: 3), rr.room != nil else { throw XCTSkip("no renderer") }
                rr.roomCacheEnabled = false
                rr.resize(width: W, height: H)
                for (k, id) in sc.order.enumerated() { rr.setPalette(JellyRoster.palette(id) ?? PaletteKey.blue.palette, body: k) }
                let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
                td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
                tex = device.makeTexture(descriptor: td)!; ren = rr
            }
            let camG = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            func render(_ cam: CameraState) -> LockImage {
                let ren = ren!, tex = tex!
                ren.beginFrame()
                for (k, r) in sc.rigs.enumerated() { r.skinner.update(x: r.sim.x, index: rm.index, into: ren.dynPointer(body: k)) }
                for k in sc.rigs.indices { sc.feats.syncCarry(k, sim: sc.rigs[k].sim) }
                let ff = sc.feats.frame(hidden: false) { ren.skinPointer(body: $0) }
                ren.room!.setWear(opaque: ff, translucent: RoomMesh(), bounds: [])
                if sp.shoes {
                    let beans = GameCare.footBeans(brain: me.brain, sim: me.sim, skinner: me.skinner, drawn: ren.skinPointer(body: 0))
                    let b = RoomMeshBuilder(); b.material = .plain
                    if let beans { for s in 0..<2 { ShoeModel.buildShell(WearLook.shoes[0], bean: beans[s], floorY: me.sim.floorY, body: SIMD3(0.35, 0.5, 0.9), time: 0, gpuPaint: true, side: s, into: b) } }
                    ren.room!.setShoes(b.mesh)
                }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7
                let pal = JellyRoster.palette(sc.order[0]) ?? PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: GameCamera.light(centroids: sc.rigs.map { $0.sim.centroid() }), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: tex, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
                var px = [UInt8](repeating: 0, count: W * H * 4)
                px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
                return LockImage(w: W, h: H, bgra: px)
            }
            func camera(_ kind: Cam, at: SIMD3<Float>, axis: SIMD3<Float>? = nil) -> CameraState {
                if kind == .game { return camG }
                var dirv: SIMD3<Float> = kind == .front ? simd_normalize(camG.pos - at) : simd_normalize(SIMD3(5.9, 0.5, 0.3))
                if let a = axis {
                    // foot close-ups: the peg in profile (perpendicular to its axis and to the vertical) / looking down its axis from outside, a little from above
                    if kind == .side { let c = simd_cross(a, SIMD3(0, 1, 0)); dirv = simd_length(c) > 0.2 ? simd_normalize(c) : SIMD3(1, 0, 0); if dirv.x < 0 { dirv = -dirv } }
                    else { dirv = simd_normalize(a + SIMD3(0, 0.6, 0)) }
                }
                let eye = at + dirv * sp.dist
                var cam = CameraState()
                cam.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
                cam.viewProj = M4.mul(M4.perspective(fovy: 32 * .pi / 180, aspect: Float(W) / Float(H), near: 0.05, far: 60), cam.view)
                cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(at - eye)
                return cam
            }
            let stepDt = me.sim.stepDt
            var acc: Float = 0, t: Float = 0, frame = 0
            var tilts: [Float] = [], beanFlags: [Bool] = []
            var cells: [Cam: [(LockImage, String)]] = [:]
            while t < sp.seconds || sp.pick.isStanding && frame < 1 {
                let dt = sp.pacing.dt(frame: frame, step: stepDt)
                acc += dt
                var steps = 0
                while acc >= stepDt && steps < 2 {
                    for (k, r) in sc.rigs.enumerated() {
                        r.brain.tick(sim: r.sim, skinner: r.skinner, dt: stepDt, touched: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: stepDt)
                        sc.feats.tick(id: k, brain: r.brain, sim: r.sim, feature: r.brain.feature, worn: [], hideAll: false, dt: stepDt)
                        if let sl = sc.feats.slot(k) { r.brain.wingsFolded = sl.fit.folded; r.brain.wingFlapLimit = sl.fit.flapMax }
                        if k == 0 { sp.each?(r) }
                    }
                    for r in sc.rigs { r.sim.step() }
                    t += stepDt; acc -= stepDt; steps += 1
                }
                if steps == 2 { acc = min(acc, stepDt) }
                if steps > 0 { for r in sc.rigs { r.brain.refitBeans(r.sim, r.skinner) } }
                for r in sc.rigs { r.skinner.tickBlink(dt: dt) }
                frame += 1
                if pass == 0 {
                    me.render()
                    tilts.append(me.sim.bodyPose(iterations: 4).tilt); beanFlags.append(me.skinner.beansActive && me.skinner.beanBlend > 0.95)
                } else if chosen.contains(frame - 1) {
                    me.render()
                    let c = me.sim.centroid()
                    // the camera target: the body centre (medium) or the foot root (close-up: the middle of the beans / the embedded feet)
                    var at = SIMD3<Float>(c.x, max(0.5, c.y), c.z)
                    var axis: SIMD3<Float>? = nil
                    if sp.closeUp {
                        let ids: [Int32] = me.skinner.beansActive && me.skinner.beanBlend > 0.5 ? me.bean[1] : me.core[1]
                        var p = SIMD3<Float>.zero
                        for id in ids { let o = 6 * Int(id); p += SIMD3(me.dyn[o], me.dyn[o + 1], me.dyn[o + 2]) }
                        at = p / Float(max(1, ids.count))
                        let d = at - c
                        axis = simd_length(d) > 1e-3 ? simd_normalize(d) : SIMD3(0, -1, 0)
                    }
                    let m = LegsDrawnAuditTests.measure(me, shoes: false)
                    let tilt = me.sim.bodyPose(iterations: 4).tilt
                    let lbl = String(format: "f%d %.2fs tilt %.2f %@", frame - 1, t, tilt, m.beans ? "pieces" : "pads")
                    for cam in sp.cams {
                        let cm = camera(cam, at: at, axis: axis)
                        let img = render(cm)
                        let pt = cam == .game ? c : at
                        let clip = cm.viewProj * SIMD4<Float>(pt.x, pt.y, pt.z, 1)
                        let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(W)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(H))
                        let tile = LegsGameCamCaptureTests.crop(img, cx: sx, cy: sy, size: cam == .game ? 700 : 1320)
                        cells[cam, default: []].append((tile, lbl))
                    }
                }
                if pass == 0 && sp.pick.isStanding && frame >= 1 { break }
            }
            if pass == 0 {
                switch sp.pick {
                case .standing: chosen = [frame - 1]
                case .tilted(let n):
                    let idx = tilts.indices.filter { tilts[$0] > 0.8 }
                    chosen = Self.spread(idx.isEmpty ? Array(tilts.indices) : idx, n)
                case .beans(let n):
                    let idx = beanFlags.indices.filter { beanFlags[$0] }
                    chosen = Self.spread(idx.isEmpty ? Array(tilts.indices) : idx, n)
                case .consecutive(let n, _):
                    let peak = tilts.indices.max { tilts[$0] < tilts[$1] } ?? 0
                    chosen = Array(max(0, peak - n / 2)..<min(tilts.count, max(0, peak - n / 2) + n))
                }
                _ = pickCount
            } else {
                for cam in sp.cams {
                    guard let cs = cells[cam], !cs.isEmpty else { continue }
                    let nm = cam == .side ? "side" : cam == .front ? "front" : "game"
                    LegsGameCamCaptureTests.sheet(cs, cols: min(4, cs.count), tile: 560, title: "\(sp.name) \(mode)\(sp.shoes ? " +shoes" : "") \(sp.pacing.name) - \(nm)", to: dir + "/\(sp.name)_\(nm)_\(mode).png")
                }
            }
            Self.keep.removeAll()
        }
    }

    static func spread(_ idx: [Int], _ n: Int) -> [Int] {
        guard idx.count > n else { return idx }
        return (0..<n).map { idx[$0 * (idx.count - 1) / (n - 1)] }
    }
}

extension OnePieceBoardTests.Pick {
    var isStanding: Bool { if case .standing = self { return true }; return false }
}
