//
//  BodySeparationTests.swift
//  2026-11-01: two Jelbies are two bodies (SoftBody+Separation.swift + MelonStage.keepApart's hard floor). Two bodies driven into each other
//  (head on, one into a standing one, both shoved to half the gap) must never sink into each other: surface gap >= -1 cm, roots >= the gap.
//  The surface gap is measured on the PARTICLES, independent of the proxy: along the line between the bodies, per 10 cm height bin, the nearest
//  particle of B minus the farthest of A (negative = interpenetration). BODYSEP_OUT=<dir> writes the worst-frame render (before = separation off).
//

import XCTest
import simd
import Metal
@testable import BobV1

@MainActor
final class BodySeparationTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias Rig = MotionRig

    /// Body-surface distance of two bodies along their centre line (negative = sunk into each other).
    static func surfaceGap(_ a: SoftBody, _ b: SoftBody) -> Float {
        let ca = a.centroid(), cb = b.centroid()
        var u = SIMD2(cb.x - ca.x, cb.z - ca.z); let L = simd_length(u)
        guard L > 1e-4 else { return -1 }
        u /= L; let pv = SIMD2(-u.y, u.x)
        var maxA = [Float](repeating: -.infinity, count: 16), minB = [Float](repeating: .infinity, count: 16)
        func bin(_ y: Float) -> Int { max(0, min(15, Int((y - a.floorY) / 0.1))) }
        for i in 0..<a.n {
            let p = SIMD2(a.x[3 * i] - ca.x, a.x[3 * i + 2] - ca.z)
            guard abs(simd_dot(p, pv)) < 0.12 else { continue }
            let k = bin(a.x[3 * i + 1]); maxA[k] = max(maxA[k], simd_dot(p, u))
        }
        for i in 0..<b.n {
            let p = SIMD2(b.x[3 * i] - ca.x, b.x[3 * i + 2] - ca.z)
            guard abs(simd_dot(p, pv)) < 0.12 else { continue }
            let k = bin(b.x[3 * i + 1]); minB[k] = min(minB[k], simd_dot(p, u))
        }
        var g = Float.infinity
        for k in 0..<16 where maxA[k].isFinite && minB[k].isFinite { g = min(g, minB[k] - maxA[k]) }
        return g.isFinite ? g : 9
    }

    struct Result { var tail: [Float] = []; var minGap = Float.infinity; var minRoot = Float.infinity; var worstStep = 0; var worstX: [[Float]] = [] }

    enum Scenario: String, CaseIterable { case headOn, walkIntoStanding, shoved }

    /// Two game rigs wired like the room (peer snapshot + keepApart); runs the scenario; `renderAt`: also calls back with the rigs at that step.
    func run(_ sc: Scenario, seconds: Float = 9, from: Int = 60, onWorst: ((MotionRig, MotionRig) -> Void)? = nil) -> Result {
        let rigs = (0..<2).map { _ in MotionRig(game: true, settle: 0.5) }
        Self.keep += rigs
        let gap = MelonController.jellyGap
        let start: [SIMD2<Float>] = sc == .shoved ? [SIMD2(-gap * 0.25, 0), SIMD2(gap * 0.25, 0)] : (sc == .headOn ? [SIMD2(-2.2, 0), SIMD2(2.2, 0)] : [SIMD2(-3, 0), SIMD2(0.4, 0)])
        for (i, r) in rigs.enumerated() {
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: start[i])
            for _ in 0..<90 { r.sim.step() }
            r.brain.currentPose(r.sim); r.brain.autonomy = sc == .shoved          // (the shoved pair: the stage's makeRoom walks the free one aside)
            if sc == .shoved { r.brain.seed = UInt64(5 + i) }
            r.brain.steerID = i; r.brain.peerGap = gap
            r.renderSamples = false
        }
        var snapshot: [(pos: SIMD2<Float>, walking: Bool)] = []
        func snap() { snapshot = rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: $0.brain.activity == .walking || $0.brain.activity == .coming) } }
        snap()
        for (i, r) in rigs.enumerated() {
            let floorRules = r.brain.resolve
            r.brain.resolve = { p, rad in floorRules(MelonController.keepApart(floorRules(p, rad), id: i, peers: snapshot), rad) }
            r.brain.peers = { snapshot.enumerated().filter { $0.offset != i }.map { (id: $0.element.walking ? $0.offset : Int.max / 2, pos: $0.element.pos) } }
        }
        switch sc {
        case .headOn: rigs[0].brain.request(.goTo(start[1])); rigs[1].brain.request(.goTo(start[0]))
        case .walkIntoStanding: rigs[0].brain.request(.goTo(start[1]))
        case .shoved: break
        }
        var res = Result()
        let sims = rigs.map(\.sim)
        let steps = Int(seconds * 60)
        var cooldown: [Float] = [0, 0], aside: Float = 0, lastShot: Float = 0.1
        for f in 0..<steps {
            snap()
            aside += 1.0 / 60
            if aside >= 0.25 { MelonController.makeRoom(snapshot: snapshot, brains: rigs.map { $0.brain }, cooldown: &cooldown, dt: aside); aside = 0 }
            for r in rigs { r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false); r.t += r.sim.stepDt }
            JellyParallel.step(sims, all: sims)
            for r in rigs { r.brain.refitBeans(r.sim, r.skinner) }
            if f >= from {          // (the shove starts overlapped by construction: the first second is the settle)
                let g = Self.surfaceGap(sims[0], sims[1])
                let d = simd_distance(GameCare.floorPos(rigs[0].brain, sims[0]), GameCare.floorPos(rigs[1].brain, sims[1]))
                if sc != .shoved || f >= 60 * 5 { res.minRoot = min(res.minRoot, d) }          // (the shoved pair starts inside the gap by construction: judged after 5 s)
                if f >= steps - 60 { res.tail.append(g) }
                if g < res.minGap { res.minGap = g; res.worstStep = f; if g < lastShot - 0.03 { lastShot = g; onWorst?(rigs[0], rigs[1]) } }          // (capture aid: the worst frame so far)
            }
        }
        return res
    }

    func testBodiesNeverSinkIntoEachOther() {
        var lines: [String] = []
        for before in [true, false] {
            BodySeparation.enabled = !before
            for sc in Scenario.allCases {
                let r = run(sc)
                lines.append(String(format: "BODYSEP %@ %@: min surface gap %.3f m at step %d, min root distance %.3f (gap %.2f), last-second gap range %.3f..%.3f", before ? "before" : "after", sc.rawValue, r.minGap, r.worstStep, r.minRoot, MelonController.jellyGap, r.tail.min() ?? 0, r.tail.max() ?? 0))
                if !before {
                    XCTAssertGreaterThanOrEqual(r.minGap, -0.01, "\(sc): bodies sank into each other")
                    XCTAssertGreaterThanOrEqual(r.minRoot, MelonController.jellyGap - 0.02, "\(sc): roots closer than the gap")
                }
            }
        }
        BodySeparation.enabled = true
        lines.forEach { MotionLog.write($0); print($0) }
    }

    /// Three bodies stepped together: the separation adds < 0.3 ms per step, close together or apart.
    func testStepCostWithThreeBodies() {
        let rigs = (0..<3).map { _ in MotionRig(game: true, settle: 0.5) }
        Self.keep += rigs
        let sims = rigs.map(\.sim)
        func cost(_ on: Bool, spots: [SIMD2<Float>]) -> Double {
            BodySeparation.enabled = on
            for (r, s) in zip(rigs, spots) { r.sim.teleport(toXZ: s); for _ in 0..<60 { r.sim.step() } }
            var best = Double.infinity
            for _ in 0..<5 {
                let t0 = CACurrentMediaTime()
                for _ in 0..<120 { JellyParallel.step(sims, all: sims) }
                best = min(best, (CACurrentMediaTime() - t0) / 120)
            }
            return best * 1000
        }
        let g = MelonController.jellyGap
        for (name, spots) in [("apart", [SIMD2<Float>(-3, 0), SIMD2(0, 0), SIMD2(3, 0)]), ("pressed", [SIMD2<Float>(-g * 0.6, 0), SIMD2(g * 0.6, 0), SIMD2(0, g * 0.7)])] {
            let off = cost(false, spots: spots), on = cost(true, spots: spots)
            let line = String(format: "BODYSEP step cost (3 bodies, %@): off %.3f ms, on %.3f ms, +%.3f ms", name, off, on, on - off)
            MotionLog.write(line); print(line)
            XCTAssertLessThan(on - off, 0.3, line)
        }
        BodySeparation.enabled = true
    }

    func testCaptureWorstFrame() throws {
        guard let dir = ProcessInfo.processInfo.environment["BODYSEP_OUT"], !dir.isEmpty else { throw XCTSkip("BODYSEP_OUT not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let rm = MotionRig.renderMesh
        let W = 1320, H = 1600
        var shared: (MelonRenderer, MTLTexture)? = nil          // (one renderer for all the shots)
        for before in [true, false] {
            BodySeparation.enabled = !before
            for sc in Scenario.allCases {
                _ = run(sc, from: sc == .shoved ? 12 : 60) { a, b in
                    if shared == nil {
                        guard let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: a.sim.edges, particleCount: a.sim.n, game: true, bodyCount: 2), r.room != nil else { return }
                        r.roomCacheEnabled = false
                        r.resize(width: W, height: H)
                        r.setPalette(JellyRoster.palette(0) ?? PaletteKey.blue.palette, body: 0)
                        r.setPalette(JellyRoster.palette(4) ?? PaletteKey.blue.palette, body: 1)
                        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
                        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
                        shared = (r, device.makeTexture(descriptor: td)!)
                    }
                    let ren = shared!.0, tex = shared!.1
                    ren.beginFrame()
                    for (k, r) in [a, b].enumerated() { r.skinner.update(x: r.sim.x, index: rm.index, into: ren.dynPointer(body: k)) }
                    ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: [])
                    let ca = a.sim.centroid(), cb = b.sim.centroid()
                    let at = SIMD3((ca.x + cb.x) / 2, 0.55, (ca.z + cb.z) / 2)
                    let camG = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
                    let eye = at + simd_normalize(camG.pos - at) * 5.2
                    var cam = CameraState()
                    cam.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
                    cam.viewProj = M4.mul(M4.perspective(fovy: 32 * .pi / 180, aspect: Float(W) / Float(H), near: 0.05, far: 60), cam.view)
                    cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(at - eye)
                    var fp = FrameParams()
                    fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                    fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7
                    let pal = JellyRoster.palette(0) ?? PaletteKey.blue.palette
                    fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                    ren.setUniforms(camera: cam, light: GameCamera.light(centroids: [ca, cb]), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
                    let cmd = ren.queue.makeCommandBuffer()!
                    ren.draw(to: tex, commandBuffer: cmd, showMesh: false)
                    cmd.waitUntilCompleted()
                    var px = [UInt8](repeating: 0, count: W * H * 4)
                    px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
                    LockImage(w: W, h: H, bgra: px).png(to: URL(fileURLWithPath: dir + "/\(before ? "before" : "after")_\(sc.rawValue).png"))
                }
            }
        }
        BodySeparation.enabled = true
    }
}
