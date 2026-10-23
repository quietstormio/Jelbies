//
//  BathJellyTests.swift
//  Clean on whichever Jelly is targeted: the whole flow runs on HIS brain and body, Bob's dirt stays put; each Jelly's soot sits in its own
//  places (same strength); and the labelled screenshots (scratchpad/B3/).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class BathJellyTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let shots = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/B3"

    // MARK: a room of three, headless

    private func makeRoom(_ n: Int = 3) -> (care: GameCare, actors: [JellyActor]) {
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let spots = JellyRoster.spawnSpots(count: n)
        let care = GameCare(jellyCount: n, persistent: false)
        care.bath.sound = SilentSound()
        let actors: [JellyActor] = (0..<n).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.profile = care.jelly($0); a.care = care
            a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
            a.reset(drop: 0.35, shift: n > 1)
            let b = BlobBrain.forGame()
            b.attach(renderMesh: rm, synchronous: true)
            b.autonomy = false
            b.steerID = $0
            care.wireWorld(b, isBob: $0 == 0)
            a.brain = b
            for _ in 0..<200 { a.sim.step() }
            b.currentPose(a.sim)
            return a
        }
        Self.keep += actors
        Self.keep.append(care)
        return (care, actors)
    }

    /// One fixed step of the room, in the stage's order: every brain, Bob's care, the others' care, the bodies.
    private func step(_ care: GameCare, _ actors: [JellyActor]) {
        for a in actors {
            guard let b = a.brain else { continue }
            b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
            a.skinner.jelly.tick(brain: b, sim: a.sim, dt: a.sim.stepDt)
            if a.id == 0 { care.tick(brain: b, renderer: nil, dt: a.sim.stepDt, sim: a.sim) }
        }
        care.tickOthers(actors, dt: actors[0].sim.stepDt)
        JellyParallel.step(actors.map(\.sim))
    }

    private func scrub(_ care: GameCare, _ a: JellyActor, _ t: Float) {
        guard care.bath.acceptsTouch else { return }
        let c = a.sim.centroid()
        let az = sinf(t * 3.1) * 1.3, polar = 1.5 + 0.9 * sinf(t * 1.3)
        let l = SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az)) * 0.62
        care.bath.touch(contact: true, hitLocal: l, world: c + l, speed: 2.5, dt: a.sim.stepDt)
    }

    func testCleanJellyTwoWashesMossAndLeavesBobAlone() {
        let (care, actors) = makeRoom()
        let moss = actors[2], bob = actors[0], pip = actors[1]
        let bobGrime = care.bath.grime
        XCTAssertTrue(bobGrime === care.jelly(0)!.grime)
        bobGrime.dirt = 0.4
        care.jelly(1)!.grime.dirt = 0.3
        care.jelly(2)!.grime.dirt = 0.6
        for _ in 0..<30 { step(care, actors) }
        XCTAssertTrue(care.canClean(jelly: 2))
        XCTAssertFalse(care.canClean(jelly: 9), "nobody by that id")
        let bobDirt = bobGrime.dirt, pipDirt = care.jelly(1)!.grime.dirt
        let mossBefore = moss.floor, bobBefore = bob.floor
        care.clean(jelly: 2)
        XCTAssertTrue(care.bath.active)
        XCTAssertEqual(care.bath.targetID, 2)
        XCTAssertTrue(care.bath.grime === care.jelly(2)!.grime, "the flow washes Moss's grime")
        XCTAssertFalse(care.canClean(jelly: 1), "one clean-up at a time")
        care.cancelClean(jelly: 1)
        XCTAssertTrue(care.bath.active, "a cancel for another Jelly does nothing")

        var t: Float = 0, maxZ: Float = 0, phases: [BathPhase] = [], inTubAt: SIMD2<Float>?
        var soapStyle: Float = -1
        for _ in 0..<(60 * 240) {
            scrub(care, moss, t)
            step(care, actors)
            t += 1.0 / 60
            if phases.last != care.bath.phase { phases.append(care.bath.phase) }
            maxZ = max(maxZ, moss.floor.y)
            if care.bath.phase == .soap, inTubAt == nil { inTubAt = moss.floor; soapStyle = care.renderLook(for: 2).sootStyle }
            XCTAssertEqual(bob.floor.x, bobBefore.x, accuracy: 0.05, "Bob stays where he was"); XCTAssertEqual(bob.floor.y, bobBefore.y, accuracy: 0.05)
            if care.bath.phase == .finish { XCTAssertEqual(care.jelly(0)!.grime.dirt, bobDirt) }
            if t > 3, !care.bath.active { break }
            if care.bath.stageComplete { care.nextCleanStep() }
            if care.bath.phase == .finish, phases.last == .finish, care.bath.wipe == 0 { care.finishClean(jelly: 2) }          // (Done, a step after the finish card showed)
        }
        XCTAssertTrue(phases.contains(.exit) && phases.contains(.soap) && phases.contains(.rinse) && phases.contains(.shine) && phases.contains(.finish), "\(phases)")
        XCTAssertFalse(care.bath.active, "back in the room")
        XCTAssertGreaterThan(maxZ, BathTuning.exitCutZ - 0.5, "Moss ran out toward the camera")
        let spot = try! XCTUnwrap(inTubAt)
        XCTAssertEqual(spot.x, BathFlow.standXZ.x, accuracy: 0.25); XCTAssertEqual(spot.y, BathFlow.standXZ.y, accuracy: 0.25, "Moss stood in the tub")
        XCTAssertEqual(soapStyle, 2, "his own soot placement")
        XCTAssertEqual(care.bath.targetID, 0)
        XCTAssertTrue(care.bath.grime === bobGrime, "Bob's grime is back in the flow")
        XCTAssertEqual(care.jelly(2)!.grime.dirt, 0, "Moss is clean")
        XCTAssertEqual(care.jelly(2)!.grime.sparkle, 1, accuracy: 0.01, "and sparkling")
        XCTAssertEqual(bobGrime.dirt, bobDirt, "Bob's dirt did not change")
        XCTAssertEqual(care.jelly(1)!.grime.dirt, pipDirt, accuracy: 0.002, "nor Pip's")
        XCTAssertEqual(care.jelly(2)!.look.dirt, 0); XCTAssertEqual(care.jelly(2)!.look.sparkle, 1, accuracy: 0.01)
        XCTAssertGreaterThan(simd_distance(moss.floor, BathFlow.standXZ), 0.8, "Moss left the tub")
        XCTAssertLessThan(simd_distance(moss.floor, mossBefore), 2.5, "and is back near where he was: \(moss.floor) vs \(mossBefore)")
        XCTAssertGreaterThan(simd_distance(moss.floor, pip.floor), 0.5); XCTAssertGreaterThan(simd_distance(moss.floor, bob.floor), 0.5)
        XCTAssertFalse(moss.brain!.hurry); XCTAssertTrue(moss.sim.arenaRadius.isFinite, "the fence is back")
        XCTAssertEqual(care.renderLook(for: 0).sootStyle, 0)
        // dirt keeps building per Jelly afterwards
        let after = care.jelly(2)!.grime.dirt
        moss.brain!.request(.goTo(SIMD2(1.5, -1.0)))
        for _ in 0..<(60 * 20) { step(care, actors) }
        XCTAssertGreaterThanOrEqual(care.jelly(2)!.grime.dirt, after)
    }

    func testBobCleanStillBobOnly() {
        let (care, actors) = makeRoom(3)
        care.bath.grime.dirt = 0.5
        for _ in 0..<30 { step(care, actors) }
        care.clean(jelly: 0)
        XCTAssertEqual(care.bath.targetID, 0)
        XCTAssertTrue(care.bath.grime === care.jelly(0)!.grime)
        for _ in 0..<(60 * 6) { step(care, actors); if care.bath.phase == .soap { break } }
        XCTAssertEqual(care.bath.phase, .soap)
        XCTAssertEqual(care.renderLook(for: 0).sootStyle, 0)
        XCTAssertLessThan(simd_distance(actors[0].floor, BathFlow.standXZ), 0.3)
        XCTAssertGreaterThan(simd_distance(actors[2].floor, BathFlow.standXZ), 1.0, "the others did not move")
    }

    // MARK: soot placement

    private func lum(_ i: LockImage, _ p: Int) -> Int { Int(i.bgra[4 * p]) + Int(i.bgra[4 * p + 1]) + Int(i.bgra[4 * p + 2]) }

    func testEachJellysStreaksSitInDifferentPlacesAtSimilarStrength() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.place(SIMD2(0.4, 0.6))
        for (name, cam) in [("front", BathCaptureTests.roomCam(s, focus: 1)), ("back", BathCaptureTests.orbitCam(s, azimuth: .pi)), ("side", BathCaptureTests.orbitCam(s, azimuth: .pi / 2))] {
            var l = BathCaptureTests.sooty(0.7)
            let dry = BathCaptureTests.render(s, look: .dry, camera: cam)
            var imgs: [LockImage] = []
            for st: Float in [0, 1, 2] { l.sootStyle = st; imgs.append(BathCaptureTests.render(s, look: l, camera: cam)) }
            var dark: [Int] = []
            for im in imgs {
                var d = 0
                for p in 0..<(im.w * im.h) { d += max(0, lum(dry, p) - lum(im, p)) }
                dark.append(d)
            }
            let lo = Float(dark.min()!), hi = Float(dark.max()!)
            XCTAssertGreaterThan(lo, 0, name)
            XCTAssertLessThan(hi / lo, 1.6, "\(name): similar strength \(dark)")
            for (a, b) in [(0, 1), (0, 2), (1, 2)] {
                var differ = 0
                for p in 0..<(imgs[a].w * imgs[a].h) where abs(lum(imgs[a], p) - lum(imgs[b], p)) > 12 { differ += 1 }
                XCTAssertGreaterThan(differ, 250, "\(name): style \(a) vs \(b) put streaks elsewhere (\(differ) px)")
            }
        }
    }

    // MARK: screenshots

    private func palette(_ id: Int) -> Palette { JellyRoster.palette(id) ?? PaletteKey.blue.palette }

    func testCaptureB3() throws {
        let dir = URL(fileURLWithPath: Self.shots)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
        for i in 1..<3 { ren.setPalette(palette(i), body: i) }

        func frame(cam: CameraState, looks: [BathLook], hidden: [Bool], bathBody: Int, time: Float = 3.7) -> LockImage {
            ren.bathBody = bathBody
            ren.roomCacheEnabled = false
            for i in 0..<3 { ren.setHidden(hidden[i], body: i); ren.setBathLook(looks[i], body: i) }
            let light = GameCamera.light(centroids: actors.map { $0.sim.centroid() })
            for _ in 0..<2 {
                ren.beginFrame()
                for a in actors { a.skinner.update(x: a.sim.x, index: rm.index, into: ren.dynPointer(body: a.id)) }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0; fp.time = time
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
        func look(_ id: Int, dirt: Float, visible: Bool = false) -> BathLook {
            var l = BathCaptureTests.sooty(dirt, visible: visible); l.sootStyle = Float(id); return l
        }
        let aspect = Float(W) / Float(H)
        let bathCam = BathSet.closeUpCamera(aspect: aspect)
        var panels: [(String, LockImage)] = []

        // 1. Moss in the bathroom, mid-soap (slot 2 is the bath body, the other two hidden)
        let stand = BathFlow.standXZ
        actors[2].sim.teleport(toXZ: stand)
        for _ in 0..<120 { actors[2].sim.step() }
        actors[0].sim.teleport(toXZ: SIMD2(-2, -1)); actors[1].sim.teleport(toXZ: SIMD2(2, -1))
        for _ in 0..<60 { actors[0].sim.step(); actors[1].sim.step() }
        var soap = look(2, dirt: 0.7, visible: true)
        soap.paint(local: SIMD3(0.5, 0.1, 0.5), radius: 0.5, amount: 1)
        soap.paint(local: SIMD3(-0.4, -0.3, 0.6), radius: 0.4, amount: 0.9)
        soap.paint(local: SIMD3(0.0, 0.5, 0.5), radius: 0.3, amount: 0.7)
        soap.tool = .soap
        _ = frame(cam: bathCam, looks: [look(0, dirt: 0.4), look(1, dirt: 0.3), soap], hidden: [true, true, false], bathBody: 2)
        soap.toolAt = ren.surfacePoint(dir: SIMD3(0.3, -0.1, 1)).map { $0 + SIMD3(0, 0.05, 0.2) }
        let mossBath = frame(cam: bathCam, looks: [look(0, dirt: 0.4), look(1, dirt: 0.3), soap], hidden: [true, true, false], bathBody: 2)
        mossBath.png(to: dir.appendingPathComponent("moss_mid_soap.png"))
        try Self.sheet([("Moss in the bath, mid-soap", mossBath)], to: dir.appendingPathComponent("moss_mid_soap_labelled.png"), columns: 1, panelHeight: 1000)

        // 2. Bob, Pip and Moss at equal dirt (0.7), same close-up camera: different streak placements
        for (i, a) in actors.enumerated() { a.sim.teleport(toXZ: GameCamera.callSpot); for _ in 0..<90 { a.sim.step() }; _ = i }
        let cu = GameCamera.camera(aspect: aspect, focus: 1)
        for (id, name) in [(0, "Bob"), (1, "Pip"), (2, "Moss")] {
            var hidden = [true, true, true]; hidden[id] = false
            var looks = [BathLook](repeating: .dry, count: 3); looks[id] = look(id, dirt: 0.7)
            let img = frame(cam: cu, looks: looks, hidden: hidden, bathBody: 0)
            img.png(to: dir.appendingPathComponent("equal_dirt_\(name.lowercased()).png"))
            panels.append(("\(name): dirt 0.7, soot style \(id)", img))
        }
        for (id, name) in [(0, "Bob"), (1, "Pip"), (2, "Moss")] {
            var hidden = [true, true, true]; hidden[id] = false
            var looks = [BathLook](repeating: .dry, count: 3); looks[id] = look(id, dirt: 0.7)
            let img = frame(cam: BathCaptureTests.orbitCam3(actors[id].sim, aspect: aspect, azimuth: 2.5), looks: looks, hidden: hidden, bathBody: 0)
            panels.append(("\(name): rear 3/4, dirt 0.7", img))
        }
        try Self.sheet(panels, to: dir.appendingPathComponent("equal_dirt_labelled.png"), columns: 3, panelHeight: 760)
    }

    static func sheet(_ panels: [(String, LockImage)], to url: URL, columns: Int, panelHeight: CGFloat) throws {
        try BathCaptureTests.sheet(panels, to: url, columns: columns, panelHeight: panelHeight)
    }
}

extension BathCaptureTests {
    /// orbitCam for any body.
    static func orbitCam3(_ sim: SoftBody, aspect: Float, azimuth: Float) -> CameraState {
        let c = sim.centroid()
        let target = SIMD3<Float>(c.x, 0.62, c.z)
        let dist = (1.7 / max(aspect, 0.2)) / (2 * tanf(GameCamera.fovY / 2))
        let el: Float = 0.30
        let eye = target + SIMD3<Float>(sinf(azimuth) * cosf(el), sinf(el), cosf(azimuth) * cosf(el)) * dist
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.3, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye
        cam.fwd = simd_normalize(target - eye)
        return cam
    }
}
