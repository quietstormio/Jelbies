//
//  TeddyOverlayTests.swift
//  Revision-2 matching of the ears to the reference image (TEDDY_DIR set), in numbers:
//  reference (measured on the 1408 px image): scale = 607 px per body unit (the two eye centres 250 px apart = 0.41 u; eye line 318 px under the head top = 0.5258 u),
//  head top y 372, axis x 715; right ear centre (915, 430) radius 77; left ear centre (525, 430) radius 77.
//  => ear radius 0.127 u, centre 0.32 u out from the axis, 0.095 u under the head top, on the head outline as seen from the front.
//  testTeddyOverlay renders our front view at that same scale and writes the numbers + a side-by-side with the reference's measured circles drawn on both.
//  testTeddyEarMatch calibrates the ear's draw colour against the body pixels next to it.
//

import XCTest
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    /// Half-width of the egg's front outline (max |x| over z) at height y.
    func outlineHalfWidth(_ y: Float) -> Float {
        var best: Float = 0
        for zi in -40...40 {
            let z = Double(zi) * 0.02
            var lo = 0.0, hi = 1.2
            for _ in 0..<40 { let m = 0.5 * (lo + hi); if BobForm.bodySDF(SIMD3(m, Double(y), z)) < 0 { lo = m } else { hi = m } }
            best = max(best, Float(lo))
        }
        return best
    }

    func testTeddyOverlay() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        var out = ""
        let s = try teddyShot(yaw: 0, size: 1000, dist: 3.5, lookY: 0.35, lift: 0.0)
        // our scale: px per unit from the eye separation (eyes at x = +-0.205 per the rig; measure the projected 0.41 u)
        let a = px(s, SIMD3(-0.205, 0.82, 0.6)), b = px(s, SIMD3(0.205, 0.82, 0.6))
        let top = px(s, SIMD3(0, 1.3458, 0))
        let scale = Float(b.0 - a.0) / 0.41
        out += String(format: "ours: %.0f px/u (eyes 0.41 u apart = %d px); head top at px y %d\n", scale, b.0 - a.0, top.1)
        out += String(format: "outline half-width at y 1.255: %.3f (reference ear centre 0.32), at y 1.21: %.3f, at 1.30: %.3f\n", outlineHalfWidth(1.255), outlineHalfWidth(1.21), outlineHalfWidth(1.30))
        // solve the ear's rest centre + radius so its PROJECTED circle equals the reference's (perspective makes the rest numbers larger than the image ones)
        let targetX = 0.32 * scale, targetDY = 0.095 * scale, targetR = 0.127 * scale
        for it in 0..<5 {
            let sh = try teddyShot(yaw: 0, size: 1000, dist: 3.5, lookY: 0.35, lift: 0.0)
            let tp = px(sh, SIMD3(0, 1.3458, 0))
            let h = TeddyMesh.earHome, c = px(sh, h), e = px(sh, h + SIMD3(TeddyMesh.earRadius, 0, 0))
            let offX = Float(c.0 - tp.0), offY = Float(c.1 - tp.1), pr = Float(abs(e.0 - c.0))
            out += String(format: "iter %d: home (%.3f, %.3f, %.3f) r %.3f -> projected offset (%.0f, %.0f) r %.0f px; target (%.0f, %.0f) r %.0f\n", it, h.x, h.y, h.z, TeddyMesh.earRadius, offX, offY, pr, targetX, targetDY, targetR)
            TeddyMesh.earHome.x *= targetX / max(offX, 1)
            TeddyMesh.earHome.y -= (targetDY - offY) / scale * 0.9
            TeddyMesh.earRadius *= targetR / max(pr, 1)
            TeddyMesh.clearCache()
        }
        let home = TeddyMesh.earHome
        out += String(format: "SOLVED earHome (%.3f, %.3f, %.3f) earRadius %.3f; outline half-width at that y: %.3f\n", home.x, home.y, home.z, TeddyMesh.earRadius, outlineHalfWidth(home.y))
        try out.write(toFile: d + "/ear_overlay_numbers.txt", atomically: true, encoding: .utf8)
        print(out)
        // overlay: reference measured circles on our render, ours on the reference
        let ui = s.img.uiImage()!
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let s2 = try teddyShot(yaw: 0, size: 1000, dist: 3.5, lookY: 0.35, lift: 0.0)
        let ui2 = s2.img.uiImage()!
        let ours = UIGraphicsImageRenderer(size: ui.size, format: fmt).image { ctx in
            ui2.draw(at: .zero)
            UIColor.green.setStroke()
            for sgn: CGFloat in [-1, 1] {
                let cx = CGFloat(top.0) + sgn * CGFloat(0.32 * scale), cy = CGFloat(top.1) + CGFloat(0.095 * scale), r = CGFloat(0.127 * scale)
                let p = UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)); p.lineWidth = 3; p.stroke()
            }
        }
        try writePNG(tlabel(ours, ["Teddy front, same scale as the reference; green = the reference's measured ear circles"]), d + "/ear_overlay_ours.png")
    }

    /// The ear's drawn colour against the body: samples the ear's outer-lobe pixels (above the head line, facing the camera) and the forehead, prints the per-channel gain.
    func testTeddyEarMatch() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        var out = ""
        for i in 0..<3 {
            setTone(i)
            TeddyLook.earGain = SIMD3(1, 1, 1); TeddyMesh.clearCache()
            for _ in 0..<2 {
                let s = try teddyShot(yaw: 0, size: 1000, dist: 3.5, lookY: 0.35, lift: 0.0)
                let prep = TeddyMesh.prepare(slide: 0, body: WearBody.shared)
                var acc = SIMD3<Float>.zero, n: Float = 0
                let ear = prep.parts[0]
                for k in ear.first..<(ear.first + ear.count) {
                    let v = prep.rest[k]
                    guard prep.nrm[k].z > 0.7, v.y > TeddyMesh.earHome.y + 0.5 * TeddyMesh.earRadius else { continue }
                    let p = px(s, v)
                    acc += rgb(s, p.0, p.1); n += 1
                }
                let earRGB = n > 0 ? acc / n : SIMD3(0, 0, 0)
                let f = px(s, SIMD3(0, 1.0, 0.5))
                let body = medianRGB(s, f.0, f.1)
                let gain = SIMD3(body.x / max(earRGB.x, 0.01), body.y / max(earRGB.y, 0.01), body.z / max(earRGB.z, 0.01))
                out += String(format: "%@: ear px %@ (%d samples) body %@ -> gain (%.3f, %.3f, %.3f)\n", TeddyLook.current.name, hex(earRGB), Int(n), hex(body), gain.x, gain.y, gain.z)
                TeddyLook.earGain *= gain; TeddyMesh.clearCache()
            }
            out += String(format: "  => earGain (%.3f, %.3f, %.3f)\n", TeddyLook.earGain.x, TeddyLook.earGain.y, TeddyLook.earGain.z)
        }
        try out.write(toFile: d + "/ear_match_numbers.txt", atomically: true, encoding: .utf8)
        print(out)
    }
}
