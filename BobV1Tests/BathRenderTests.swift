//
//  BathRenderTests.swift
//  The Bath's render side: struct layouts, the dry path staying exactly the old frame, the foam grid, the room cache on show / hide,
//  soot on the skin, surface points riding on the deformed body, and the bath shader reproducing the plain matte look when every control is zero.
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class BathRenderTests: XCTestCase {

    func testStructLayouts() {
        XCTAssertEqual(MemoryLayout<MelonUniforms>.size, 544, "struct Uniforms is locked (BaseBodyLock): the bath rides in MelonBathParams")
        XCTAssertEqual(MemoryLayout<MelonBathParams>.size, 2336)
        XCTAssertEqual(MemoryLayout<MelonBathParams>.stride, 2336)
        XCTAssertEqual(MemoryLayout<MelonBathParams>.offset(of: \.centre), 16)
        XCTAssertEqual(MemoryLayout<MelonBathParams>.offset(of: \.foam), MelonBathParams.foamOffset)
        XCTAssertEqual(MelonBathParams.foamOffset + BathLook.rows * BathLook.cols * 4, MelonBathParams.sootOffset)
        XCTAssertEqual(MemoryLayout<MelonBathParams>.offset(of: \.soot), MelonBathParams.sootOffset)
        XCTAssertEqual(MelonBathParams.sootOffset + BathLook.rows * BathLook.cols * 4, 2336)
        XCTAssertEqual(MemoryLayout<BathSetUniforms>.size, 224)
        XCTAssertEqual(MemoryLayout<RoomVertex>.stride, 48)
    }

    func testFoamGridMapping() {
        // rows: polar from +y; columns: azimuth from +z, increasing toward +x
        XCTAssertEqual(BathLook.cell(for: SIMD3(0, 1, 0.001)) / BathLook.cols, 0)
        XCTAssertEqual(BathLook.cell(for: SIMD3(0, -1, 0.001)) / BathLook.cols, BathLook.rows - 1)
        XCTAssertEqual(BathLook.cell(for: SIMD3(0.001, 0, 1)) % BathLook.cols, 0)
        XCTAssertEqual(BathLook.cell(for: SIMD3(1, 0, -0.01)) % BathLook.cols, BathLook.cols / 4)
        XCTAssertEqual(BathLook.cell(for: SIMD3(0, 0, -1)) % BathLook.cols, BathLook.cols / 2)
        XCTAssertEqual(BathLook.cell(for: SIMD3(2, 2, 2)), BathLook.cell(for: SIMD3(0.3, 0.3, 0.3)), "direction need not be normalised")
        var l = BathLook()
        XCTAssertEqual(l.coverage, 0)
        l.paint(local: SIMD3(1, 0, 0), radius: 0.6, amount: 1)
        XCTAssertGreaterThan(l.foamAt(SIMD3(1, 0, 0)), 0.6)
        XCTAssertEqual(l.foamAt(SIMD3(-1, 0, 0)), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(l.coverage, 0)
        l.rinse(local: SIMD3(1, 0, 0), radius: 0.8, amount: 1)
        XCTAssertEqual(l.coverage, 0, accuracy: 1e-5)
        var all = BathLook(); all.foam = Array(repeating: 1, count: BathLook.rows * BathLook.cols)
        XCTAssertEqual(all.foamAt(SIMD3(0.3, 0.9, -0.2)), 1, accuracy: 1e-5)
    }

    /// The dry path is the plain matte pipeline and the very same pixels as a renderer that never heard of the bath.
    func testDryPathIsPixelIdentical() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.place(SIMD2(0.4, 0.6))
        let before = s.render(cache: false)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matte")
        s.ren.bathLook = .dry
        let dry = s.render(cache: false)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matte")
        XCTAssertEqual(before.maxDiff(dry), 0)
        // all controls zero but visible == false and empty lists: still the old frame
        var zero = BathLook(); zero.sparkle = 0; zero.wet = 0
        s.ren.bathLook = zero
        XCTAssertEqual(before.maxDiff(s.render(cache: false)), 0)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matte")
        // a tool or a spray with nothing else on screen does not switch the body shader
        var t = BathLook(); t.tool = .rinse; t.spray = BathSet.showerNozzle
        s.ren.bathLook = t
        _ = s.render(cache: false)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matte")

        // each control switches the bath shader on and changes pixels
        var wet = BathLook(); wet.wet = 0.8
        var spk = BathLook(); spk.sparkle = 0.3
        var foam = BathLook(); foam.paint(local: SIMD3(0, 0, 1), radius: 0.9, amount: 1)
        for (name, look) in [("wet", wet), ("sparkle", spk), ("foam", foam)] {
            s.ren.bathLook = look
            let img = s.render(cache: false)
            XCTAssertEqual(s.ren.lastBodyPipeline, "matteBath", name)
            XCTAssertGreaterThan(before.maxDiff(img), 8, "\(name) changes Bob")
        }
        // and back to dry restores the exact old frame
        s.ren.bathLook = .dry
        XCTAssertEqual(before.maxDiff(s.render(cache: false)), 0)
    }

    /// The bath skin shader with every control at zero reproduces the original matte look (small GPU rounding allowed).
    func testBathShaderMatchesMatteAtZero() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.place(SIMD2(0.4, 0.6))
        let plain = s.render(cache: false)
        s.ren.forceBathShader = true
        let viaBath = s.render(cache: false)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matteBath")
        s.ren.forceBathShader = false
        let d = GfxDiff(plain, viaBath)
        print("BATHTEST zero-control bath shader vs matte: \(d.summary)")
        XCTAssertLessThanOrEqual(d.maxLevel, 2)
    }

    /// Showing the bath bumps the static version and changes the cache key, so the living room never sticks and the bath never leaks back.
    func testRoomCacheInvalidatedOnShowHide() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.place(SIMD2(0.9, 0.4))
        let room = try XCTUnwrap(s.ren.room)
        _ = s.render(cache: true, frames: 8)
        XCTAssertEqual(s.ren.lastCacheAction, .use, "living room cache is warm")
        let v0 = room.staticVersion
        var l = BathLook(); l.visible = true
        s.ren.bathLook = l
        _ = s.render(cache: true, frames: 1)
        XCTAssertTrue(room.bathVisible)
        XCTAssertGreaterThan(room.staticVersion, v0)
        XCTAssertNotEqual(s.ren.lastCacheAction, .use, "the stale living-room cache must not be used on the first bath frame")
        // the bath is cached like the room once it settles: identical to the uncached bath
        let cached = s.render(cache: true, frames: 8)
        let bathAction = s.ren.lastCacheAction
        print("BATHTEST bath cache action \(bathAction) footprint \(s.ren.lastFootprintShare)")
        let uncached = s.render(cache: false, frames: 1)
        if bathAction == .use { XCTAssertEqual(cached.maxDiff(uncached), 0) }
        let v1 = room.staticVersion
        // back to the living room
        s.ren.bathLook = .dry
        _ = s.render(cache: true, frames: 1)
        XCTAssertFalse(room.bathVisible)
        XCTAssertGreaterThan(room.staticVersion, v1)
        let back = s.render(cache: true, frames: 8)
        XCTAssertEqual(s.ren.lastCacheAction, .use)
        let ref = s.render(cache: false, frames: 1)
        XCTAssertEqual(back.maxDiff(ref), 0, "no bath pixels left in the living room")
        // key logic
        var a = RoomCacheKey(), b = RoomCacheKey(); b.bath = true
        XCTAssertEqual(RoomCacheState.reason(a, b), .bath)
        var st = RoomCacheState()
        for _ in 0..<6 { _ = st.frame(key: a, footprint: 0.1, enabled: true) }
        XCTAssertEqual(st.frame(key: a, footprint: 0.1, enabled: true), .use)
        a.bath = true
        XCTAssertEqual(st.frame(key: a, footprint: 0.1, enabled: true), .bypass(.bath))
    }

    func testBathRoomFillsTheFrame() throws {
        // every pixel of the close-up and of the wide game camera shows the bathroom (no clear colour / void)
        let s = try XCTUnwrap(GfxLabScene(width: 201, height: 437))
        s.place(SIMD2(BathSet.standPoint.x, BathSet.standPoint.z))
        var l = BathLook(); l.visible = true
        for cam in [BathSet.closeUpCamera(aspect: 201.0 / 437.0), GameCamera.camera(aspect: 201.0 / 437.0)] {
            let img = BathCaptureTests.render(s, look: l, camera: cam)
            var dark = 0
            for p in 0..<(img.w * img.h) { if img.bgra[4 * p] < 6 && img.bgra[4 * p + 1] < 6 && img.bgra[4 * p + 2] < 6 { dark += 1 } }
            XCTAssertLessThan(dark, img.w * img.h / 200, "black void in the bathroom frame")
        }
    }

    func testSurfacePointRidesTheBody() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 201, height: 437))
        s.place(SIMD2(0.2, 0.5))
        _ = s.render(cache: false)
        let dir = SIMD3<Float>(0.3, 0.5, 1)
        let p0 = try XCTUnwrap(s.ren.surfacePoint(dir: dir))
        s.shift(SIMD3(0.5, 0, -0.25))
        _ = s.render(cache: false)
        let p1 = try XCTUnwrap(s.ren.surfacePoint(dir: dir))
        XCTAssertEqual(p1.x - p0.x, 0.5, accuracy: 0.02)
        XCTAssertEqual(p1.z - p0.z, -0.25, accuracy: 0.02)
        // the point lies on his surface: within his body radius of the centre line
        XCTAssertLessThan(simd_length(SIMD2(p1.x - s.rig.root.x, p1.z - s.rig.root.y)), 0.9)
    }

    /// Soot: dirt 0 is the original frame (plain matte pipeline, pixel-identical); dirt darkens him toward grey, never tints; washing the grid
    /// brings the colour back; the pattern is the same grid for the same dirt.
    func testSootShowsOnTheSkinAndWashesOff() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 201, height: 437))
        s.place(SIMD2(0.2, 0.5))
        let cam = BathCaptureTests.roomCam(s)
        let dry = BathCaptureTests.render(s, look: .dry, camera: cam)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matte")
        var clean = BathLook(); clean.dirt = 0; clean.soot = BathLook.sootSeed(dirt: 0)
        let still = BathCaptureTests.render(s, look: clean, camera: cam)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matte", "no dirt: the original pipeline")
        XCTAssertEqual(still.maxDiff(dry), 0)
        var prev: Float = 0
        for dirt in [Float(0.2), 0.5, 0.85] {
            var l = BathLook(); l.dirt = dirt; l.soot = BathLook.sootSeed(dirt: dirt)
            XCTAssertEqual(l.soot, BathLook.sootSeed(dirt: dirt), "the seed is stable")
            let img = BathCaptureTests.render(s, look: l, camera: cam)
            XCTAssertEqual(s.ren.lastBodyPipeline, "matteBath")
            // mean luminance of the pixels that changed (Bob) drops with dirt
            var n: Float = 0, darker = 0, lighter = 0
            for p in 0..<(img.w * img.h) {
                let k = 4 * p
                if abs(Int(img.bgra[k]) - Int(dry.bgra[k])) + abs(Int(img.bgra[k + 1]) - Int(dry.bgra[k + 1])) + abs(Int(img.bgra[k + 2]) - Int(dry.bgra[k + 2])) > 3 {
                    n += 1
                    let was = Int(dry.bgra[k]) + Int(dry.bgra[k + 1]) + Int(dry.bgra[k + 2]), now = Int(img.bgra[k]) + Int(img.bgra[k + 1]) + Int(img.bgra[k + 2])
                    if now < was { darker += 1 } else { lighter += 1 }
                }
            }
            XCTAssertGreaterThan(n, 20, "soot shows at dirt \(dirt)")
            XCTAssertGreaterThan(darker, lighter * 3, "soot only darkens at \(dirt)")
            XCTAssertGreaterThanOrEqual(n, prev, "more dirt, more of him covered")
            prev = n
        }
        // washing the soot grid away gives the clean frame back (the dirt scalar alone changes nothing)
        var washed = BathLook(); washed.dirt = 0.85
        let w = BathCaptureTests.render(s, look: washed, camera: cam)
        XCTAssertEqual(s.ren.lastBodyPipeline, "matteBath")
        XCTAssertEqual(w.maxDiff(dry), 0, "no soot left = the same pixels as dry")
    }

    func testDustPuffsOnlyWhenFilthy() {
        let spot: (Int) -> (p: SIMD3<Float>, n: SIMD3<Float>)? = { _ in (SIMD3(0, 1, 1), SIMD3(0, 0, 1)) }
        let o = BathOverlay()
        var l = BathLook(); l.dirt = 0.5; l.soot = BathLook.sootSeed(dirt: 0.5)
        o.compose(look: l, time: 1, sparkleAt: spot)
        XCTAssertTrue(o.isEmpty, "no puffs when merely dirty")
        l.dirt = 0.95; l.soot = BathLook.sootSeed(dirt: 0.95)
        var any = false
        for t in stride(from: Float(0), to: 6, by: 0.3) { o.compose(look: l, time: t, sparkleAt: spot); any = any || !o.isEmpty }
        XCTAssertTrue(any, "a filthy coat sheds dust puffs")
        let quads = o.soup.i.count / 6
        XCTAssertLessThanOrEqual(quads, BathOverlay.maxPuffs, "a low count")
        l.soot = Array(repeating: 0, count: l.soot.count)
        o.compose(look: l, time: 2, sparkleAt: spot)
        XCTAssertTrue(o.isEmpty, "washed clean: no puffs")
    }

    func testToolsBubblesAndSprayDrawSomething() {
        let o = BathOverlay()
        for tool in [BathTool.soap, .shine] {
            var l = BathLook(); l.tool = tool; l.toolAt = SIMD3(0, 1, 2)
            o.compose(look: l, time: 0)
            XCTAssertFalse(o.isEmpty, "\(tool)")
        }
        var none = BathLook(); none.tool = .soap
        o.compose(look: none, time: 0)
        XCTAssertTrue(o.isEmpty, "a tool without a position draws nothing")
        var sp = BathLook(); sp.spray = BathSet.showerNozzle
        o.compose(look: sp, time: 0.4)
        XCTAssertFalse(o.isEmpty)
        var bb = BathLook(); bb.bubbles = [SIMD4(0, 1, 1, 0.1)]
        o.compose(look: bb, time: 0)
        XCTAssertFalse(o.isEmpty)
        // the static set builds and has the stand point inside the basin
        let m = BathModels.buildSet()
        XCTAssertGreaterThan(m.indices.count, 1500)
        XCTAssertEqual(BathSet.standPoint.y, BathModels.waterY)
        XCTAssertEqual(BathSet.standPoint.x, BathModels.basinCentre.x)
    }

    /// A paint at a body-local (hit-frame) point lands on THAT spot in the render: the foam blob's pixel centroid sits near the projection of the
    /// skinned surface point in the same rest direction (flow's `BathLook.centre` frame vs the renderer's `BathSet.bodyCentre` frame).
    func testPaintLandsWhereTheFingerWas() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.clearTray()
        s.place(SIMD2(BathSet.standPoint.x, BathSet.standPoint.z))
        let cam = BathSet.closeUpCamera(aspect: Float(s.W) / Float(s.H))
        let base = BathCaptureTests.render(s, look: BathLook(), camera: cam)
        for d in [SIMD3<Float>(1, 0.1, 0.5), SIMD3<Float>(-1, 0.1, 0.5), SIMD3<Float>(0, 1, 0.8), SIMD3<Float>(0.1, -0.2, 1)] {
            let dn = simd_normalize(d)
            var l = BathLook()
            l.paint(local: BathLook.centre + dn * 0.3, radius: 0.12, amount: 1)    // hit frame: centroid-relative
            let img = BathCaptureTests.render(s, look: l, camera: cam)
            var sx: Float = 0, sy: Float = 0, sw: Float = 0
            for y in 0..<s.H { for x in 0..<s.W {
                let k = 4 * (y * s.W + x)
                let df = (0..<3).reduce(0) { $0 + abs(Int(img.bgra[k + $1]) - Int(base.bgra[k + $1])) }
                if df > 40 { sx += Float(x); sy += Float(y); sw += 1 }
            } }
            XCTAssertGreaterThan(sw, 30, "foam visible for \(d)")
            let p = try XCTUnwrap(s.ren.surfacePoint(dir: dn))
            let c = cam.viewProj * SIMD4<Float>(p, 1)
            let px = (c.x / c.w * 0.5 + 0.5) * Float(s.W), py = (0.5 - c.y / c.w * 0.5) * Float(s.H)
            let ex = abs(sx / max(sw, 1) - px), ey = abs(sy / max(sw, 1) - py)
            print("BATHTEST paint dir \(d): foam centroid (\(sx / max(sw, 1)), \(sy / max(sw, 1))) expected (\(px), \(py)) n=\(sw)")
            XCTAssertLessThan(ex, 0.12 * Float(s.W), "x for \(d)")
            XCTAssertLessThan(ey, 0.06 * Float(s.H), "y for \(d)")
        }
    }
}
