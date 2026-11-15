//
//  CharSheetCaptureTests.swift
//  Not a regression test: front / back / side stills of every character (bare, at rest) with the REAL renderer when CHAR_DIR is set
//  (TEST_RUNNER_CHAR_DIR). Built on PandaCaptureTests' pandaStill rig, with the phone build's jelly look and the stage's per-frame body flags.
//  Per view two pictures from ONE pose: <id>_<name>_<view>.png = cutout (transparent background, alpha = coverage), <id>_<name>_<view>_room.png = in the room.
//  Also writes meta.txt (look profile + camera per picture).
//

import XCTest
import Metal
import simd
import UIKit
import ImageIO
@testable import BobV1

extension FeatureCaptureTests {
    /// Same set-up as `pandaStill`, plus the flags the real stage / GameCare set on a home actor, then two draws of the same pose (cutout, room).
    func charSheetStill(id: Int, yaw: Float, size: Int, dist: Float, lookY: Float, lift: Float, warm: Int) throws -> (cut: LockImage, room: LockImage, cam: CameraState) {
        W = size; H = size
        let c = Char(id: id, outfit: [:])
        let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
        let r = lab.rigs[0]
        r.brain.autonomy = false; r.brain.expr.enabled = false
        let (ren, target) = try renderer(lab)
        ren.matteSpec = true
        // the stage's per-frame flags (MelonStage.swift ~1201-1203) and GameCare.tickFeature (GameCare+Features.swift:23)
        r.skinner.legBlendShoes = r.brain.shoesWorn
        r.brain.armBlendSpecies = true
        r.brain.pandaInk = id == JellyRoster.pandaID
        // dress(), by hand, so the feature tints (GameCare.tickFeature) are set before the first feature tick
        let d = Dressed()
        let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
        let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
        f.setWingTint(0, WhiteWing.hasLook(id) ? WhiteWing.wingTint : nil)
        f.setSpikeTint(0, JellyRoster.feature(id) == .spines ? JellyVariantBook.spikeTint(for: JellyVariants.active(id)) : nil)
        d.worn.append(w); d.feats.append(f)
        for _ in 0..<3 { tick(d, 0, r, c) }
        for _ in 0..<warm { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(d, 0, r, c) }
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_length(fwd) > 0.3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let cc = pose.centroid
        let cam = Self.lookCamera(target: SIMD3(cc.x, cc.y + lookY, cc.z), dir: dir, dist: dist, aspect: 1, lift: lift)
        // the stage hands the skinner's leg / arm blend tables to the renderer after skinning (MelonStage.swift:1209); composite skins itself but never sets them
        func skinAndBlend() {
            ren.beginFrame()
            for _ in 0..<2 { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer) }
            ren.setLegBlend(r.skinner.legBlend, body: 0); ren.setWaveBlend(r.skinner.waveBlend, body: 0)
        }
        skinAndBlend()
        ren.cutout = true
        let cut = composite(lab, d, [c], ren, target, cam: cam)
        skinAndBlend()          // (no sim tick in between: the pose is the same; this only refreshes the blend tables from the same state)
        ren.cutout = false
        let room = composite(lab, d, [c], ren, target, cam: cam)
        return (cut, room, cam)
    }

    /// PNG with alpha from a BGRA buffer that holds PREMULTIPLIED colour (what the cut-out post step returns: rgb * cov, cov). ImageIO stores it straight.
    func charSheetWritePNG(_ img: LockImage, _ path: String) throws {
        var data = img.bgra
        let cg: CGImage? = data.withUnsafeMutableBytes { p -> CGImage? in
            CGContext(data: p.baseAddress, width: img.w, height: img.h, bitsPerComponent: 8, bytesPerRow: img.w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
        }
        guard let cg, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { throw XCTSkip("png encode failed: \(path)") }
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest), "png written: \(path)")
    }

    func testCharSheetViews() throws {
        guard let d = ProcessInfo.processInfo.environment["CHAR_DIR"], !d.isEmpty else { throw XCTSkip("CHAR_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        // the phone build's look (JellyLook.phoneTest = (1, true)), set explicitly and put back
        let was = (JellyLook.level, JellyLook.all); JellyLook.level = 1; JellyLook.all = true
        let wasHour = DayClock.shared.forcedHour
        defer { JellyLook.level = was.0; JellyLook.all = was.1; DayClock.shared.forcedHour = wasHour }
        DayClock.shared.forcedHour = 12
        let env = ProcessInfo.processInfo.environment
        let sideYaw = Float(env["CHAR_SIDE_YAW"] ?? "") ?? (-.pi / 2)
        let dist = Float(env["CHAR_DIST"] ?? "") ?? 3.9
        let lookY = Float(env["CHAR_LOOKY"] ?? "") ?? 0.5
        let lift = Float(env["CHAR_LIFT"] ?? "") ?? 0.2
        let only = env["CHAR_ONLY"].flatMap { Int($0) }
        var meta = "id name view jellyKind profileSpecies style level neon(soft,deepen) | yaw dist lookY lift fovY camPos(x,y,z) | JellyLook.level all\n"
        for id in 0..<JellyRoster.knownCount where only == nil || only == id {
            let name = JellyRoster.baseNames[id].lowercased()
            let pal = JellyRoster.palette(id) ?? PaletteKey.blue.palette
            let spID = pal.jellySpecies
            let prof = JellyLook.profile(forFlesh: SIMD4(pal.flesh, 1), speciesID: spID)
            let kind = JellyLook.kind(flesh: SIMD4(pal.flesh, 1), bellyMode: 0, speciesID: spID)
            for (vn, yaw) in [("front", Float(0)), ("back", Float.pi), ("side", sideYaw)] {
                let s = try charSheetStill(id: id, yaw: yaw, size: 768, dist: dist, lookY: lookY, lift: lift, warm: 150)
                try charSheetWritePNG(s.cut, d + "/\(id)_\(name)_\(vn).png")
                try charSheetWritePNG(s.room, d + "/\(id)_\(name)_\(vn)_room.png")
                meta += "\(id) \(name) \(vn) kind=\(kind) species=\(spID)/\(prof.species) style=\(prof.style) level=\(prof.level) neon=\(prof.neon.soft),\(prof.neon.deepen) | yaw=\(yaw) dist=\(dist) lookY=\(lookY) lift=\(lift) fovY=\(GameCamera.fovY) cam=\(s.cam.pos.x),\(s.cam.pos.y),\(s.cam.pos.z) | level=\(JellyLook.level) all=\(JellyLook.all)\n"
            }
        }
        try meta.write(toFile: d + "/meta.txt", atomically: true, encoding: .utf8)
    }
}
