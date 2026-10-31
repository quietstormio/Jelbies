//
//  TeddyCaptureTests.swift
//  Not a regression test: renders the Teddy (character 4: light brown, lighter belly, bear ears + puffy pom tail) with the REAL renderer when TEDDY_DIR is set
//  (TEST_RUNNER_TEDDY_DIR): the reference board, the three light-brown options, the turnaround, every hat, the neck / body pieces, the motions.
//  Built on FeatureCaptureTests' rig (same room camera, same one-body-per-pass compositing).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    static let teddyID = JellyRoster.teddyID

    func teddyDir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["TEDDY_DIR"], !d.isEmpty else { throw XCTSkip("TEDDY_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    func teddyTone() {
        if let s = ProcessInfo.processInfo.environment["TEDDY_TONE"], let i = Int(s) { TeddyLook.current = TeddyLook.tones[min(max(i, 0), 2)] }
        TeddyMesh.clearCache(); TeddyFit.clearCache(); FeatureMeshes.clearCache()
    }
    func setTone(_ i: Int) { TeddyLook.current = TeddyLook.tones[i]; TeddyMesh.clearCache(); TeddyFit.clearCache() }

    /// One raw frame of a Teddy: the image, the camera, and the feature slot's carry (rest -> world) for sampling.
    struct TShot { var img: LockImage; var cam: CameraState; var carry: EyeMaskModel.Carry; var fit: FeatureFit }

    func teddyShot(outfit: Outfit = [:], yaw: Float, size: Int = 900, dist: Float = 3.4, lookY: Float = 0.25, lookBack: Float = 0, lift: Float = 0.1, id: Int = 4, seed: UInt64 = 3,
                   prepare: ((SocialTests.Lab, Dressed) -> Void)? = nil) throws -> TShot {
        W = size; H = size
        let c = Char(id: id, outfit: outfit)
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: seed)
        let (ren, target) = try renderer(lab)
        let d = dress(lab, [c])
        prepare?(lab, d)
        let r = lab.rigs[0]
        for _ in 0..<12 { tick(d, 0, r, c) }
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_normalize(fwd)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let cc = pose.centroid
        let cam = Self.lookCamera(target: SIMD3(cc.x - fwd.x * lookBack, cc.y + lookY, cc.z - fwd.z * lookBack), dir: dir, dist: dist, aspect: 1, lift: lift)
        let img = composite(lab, d, [c], ren, target, cam: cam)
        return TShot(img: img, cam: cam, carry: d.feats[0].slot(0)?.carry ?? EyeMaskModel.Carry(), fit: d.feats[0].slot(0)?.fit ?? FeatureFit())
    }

    func px(_ s: TShot, _ rest: SIMD3<Float>) -> (Int, Int) {
        let w = s.carry.world(rest)
        let k = s.cam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
        return (Int((k.x / k.w * 0.5 + 0.5) * Float(s.img.w)), Int((1 - (k.y / k.w * 0.5 + 0.5)) * Float(s.img.h)))
    }
    func rgb(_ s: TShot, _ x: Int, _ y: Int) -> SIMD3<Float> {
        let i = 4 * (min(max(y, 0), s.img.h - 1) * s.img.w + min(max(x, 0), s.img.w - 1))
        return SIMD3(Float(s.img.bgra[i + 2]), Float(s.img.bgra[i + 1]), Float(s.img.bgra[i])) / 255
    }
    /// The median colour of a small window.
    func medianRGB(_ s: TShot, _ x: Int, _ y: Int, r: Int = 6) -> SIMD3<Float> {
        var xs: [Float] = [], ys: [Float] = [], zs: [Float] = []
        for dy in -r...r { for dx in -r...r { let c = rgb(s, x + dx, y + dy); xs.append(c.x); ys.append(c.y); zs.append(c.z) } }
        func med(_ a: [Float]) -> Float { a.sorted()[a.count / 2] }
        return SIMD3(med(xs), med(ys), med(zs))
    }
    func darkest(_ s: TShot, _ x: Int, _ y: Int, r: Int = 14) -> SIMD3<Float> {
        var best = SIMD3<Float>(1, 1, 1), bl: Float = 9
        for dy in -r...r { for dx in -r...r { let c = rgb(s, x + dx, y + dy); let l = lum(c); if l < bl { bl = l; best = c } } }
        return best
    }
    func lin(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }
    func lum(_ c: SIMD3<Float>) -> Float { 0.2126 * lin(c.x) + 0.7152 * lin(c.y) + 0.0722 * lin(c.z) }
    func contrast(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { let x = lum(a), y = lum(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }
    func hex(_ c: SIMD3<Float>) -> String { String(format: "#%02X%02X%02X", Int((c.x * 255).rounded()), Int((c.y * 255).rounded()), Int((c.z * 255).rounded())) }

    func tlabel(_ img: UIImage, _ lines: [String], bar: CGFloat = 0, chips: [SIMD3<Float>] = []) -> UIImage {
        let w = img.size.width, h = img.size.height, b = bar > 0 ? bar : CGFloat(8 + 18 * lines.count)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + b), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + b))
            for (i, t) in lines.enumerated() { (t as NSString).draw(at: CGPoint(x: 8, y: 5 + 18 * CGFloat(i)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: i == 0 ? 15 : 13), .foregroundColor: UIColor.white]) }
            img.draw(in: CGRect(x: 0, y: b, width: w, height: h))
            for (i, c) in chips.enumerated() {
                let r = CGRect(x: w - 14 - CGFloat(chips.count - i) * 62, y: 6, width: 56, height: b - 12)
                UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1).setFill(); UIRectFill(r)
                UIColor.white.setStroke(); UIBezierPath(rect: r).stroke()
            }
        }
    }
    func scaled(_ img: UIImage, _ side: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in img.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
    }
    func tgrid(_ imgs: [UIImage], cols: Int) -> UIImage {
        let cw = imgs.map { $0.size.width }.max() ?? 0, ch = imgs.map { $0.size.height }.max() ?? 0
        let rows = (imgs.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: cw * CGFloat(cols), height: ch * CGFloat(rows)), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw * CGFloat(cols), height: ch * CGFloat(rows)))
            for (i, im) in imgs.enumerated() { im.draw(at: CGPoint(x: CGFloat(i % cols) * cw, y: CGFloat(i / cols) * ch)) }
        }
    }
    func writePNG(_ img: UIImage, _ path: String, maxBytes: Int = 1_900_000) throws {
        var im = img
        var data = im.pngData()!
        var k: CGFloat = 1
        while data.count > maxBytes && k > 0.3 {
            k *= 0.85
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            im = UIGraphicsImageRenderer(size: CGSize(width: img.size.width * k, height: img.size.height * k), format: fmt).image { _ in img.draw(in: CGRect(x: 0, y: 0, width: img.size.width * k, height: img.size.height * k)) }
            data = im.pngData()!
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: 1. the reference next to Teddy + the three light-brown options

    func testTeddyReferenceBoard() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        let refPath = ProcessInfo.processInfo.environment["TEDDY_REF"] ?? "/Users/dmarshall94/.claude/uploads/9cd2e159-911b-4a04-879f-e5e34721a64a/7a76d791-image.png"
        guard let ref = UIImage(contentsOfFile: refPath) else { throw XCTSkip("no reference image") }
        // the reference, cropped square round the body
        let cg = ref.cgImage!
        let crop = CGRect(x: 230, y: 250, width: 900, height: 900).intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let refImg = scaled(UIImage(cgImage: cg.cropping(to: crop)!), 700)
        // Teddy, a similar low 3/4-ish front camera
        var cells: [UIImage] = [tlabel(refImg, ["REFERENCE (pink)"])]
        for (label, yaw) in [("Teddy front", Float(0)), ("Teddy 3/4", Float(0.45))] {
            let s = try teddyShot(yaw: yaw, size: 700, dist: 3.5, lookY: 0.35, lift: 0.04)
            cells.append(tlabel(s.img.uiImage()!, ["\(label) (\(TeddyLook.current.name))"]))
        }
        try writePNG(tgrid(cells, cols: 3), d + "/01_reference_vs_teddy.png")
        // the three options with the eye contrast
        var opts: [UIImage] = []
        var notes = ""
        for i in 0..<3 {
            setTone(i)
            let t = TeddyLook.tones[i]
            let s = try teddyShot(yaw: 0, size: 600, dist: 3.5, lookY: 0.35, lift: 0.04)
            let body = medianRGB(s, px(s, SIMD3(0, 1.05, 0.5)).0, px(s, SIMD3(0, 1.05, 0.5)).1)
            let cheek = medianRGB(s, px(s, SIMD3(-0.36, 0.6, 0.5)).0, px(s, SIMD3(-0.36, 0.6, 0.5)).1, r: 4)
            let belly = medianRGB(s, px(s, SIMD3(0, 0.33, 0.6)).0, px(s, SIMD3(0, 0.33, 0.6)).1)
            let e = px(s, SIMD3(-0.205, 0.82, 0.62))
            let eye = darkest(s, e.0, e.1)
            let eyeSrgb = SIMD3<Float>(0x3A, 0x26, 0x20) / 255
            let cEye = contrast(eye, body), cNom = contrast(eyeSrgb, body)
            let cBelly = contrast(belly, body)
            let line = String(format: "%@  flesh %@  | drawn body %@  belly %@  (belly vs body %.2f:1)  eye %@ vs body %.1f:1", t.name, hex(t.flesh), hex(body), hex(belly), cBelly, hex(eye), cEye)
            notes += line + String(format: "  [nominal eye #3A2620 vs body %.1f:1; cheek %@]\n", cNom, hex(cheek))
            opts.append(tlabel(s.img.uiImage()!, ["Option \(i + 1): \(t.name)  body \(hex(body))  belly \(hex(belly))", String(format: "eye contrast %.1f:1 (WCAG)   belly vs body %.2f:1   chips: body / belly / eye", cEye, cBelly)], chips: [body, belly, eye]))
        }
        setTone(0)
        try writePNG(tgrid(opts, cols: 3), d + "/02_three_tones.png")
        try notes.write(toFile: d + "/tone_numbers.txt", atomically: true, encoding: .utf8)
    }

    // MARK: 2. turnaround

    func testTeddyTurnaround() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        let views: [(String, Float, Float, Float)] = [("front", 0, 0.1, 3.4), ("3/4", 0.75, 0.1, 3.4), ("side", .pi / 2, 0.1, 3.4), ("back", .pi, 0.1, 3.4), ("3/4 back", 2.4, 0.1, 3.4), ("top", .pi * 0.9, 2.6, 3.8)]
        for (name, yaw, lift, dist) in views {
            let s = try teddyShot(yaw: yaw, size: 640, dist: dist, lookY: 0.35, lift: lift)
            cells.append(tlabel(s.img.uiImage()!, ["Teddy \(name)"]))
        }
        try writePNG(tgrid(cells, cols: 3), d + "/03_turnaround.png")
    }

    // MARK: 3. hats and neck pieces

    func testTeddyHats() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        let hats = WearLook.looks(.head)
        var front: [UIImage] = [], back: [UIImage] = [], notes = "hat | ears | slide | pom\n"
        for look in hats {
            let sF = try teddyShot(outfit: [.head: look], yaw: 0.6, size: 460, dist: 3.0, lookY: 0.32, lift: 0.1)
            let sB = try teddyShot(outfit: [.head: look], yaw: 2.5, size: 460, dist: 3.0, lookY: 0.32, lift: 0.1)
            let f = sF.fit
            let state = f.earsHidden ? "ears tucked" : f.earSlide > 0 ? String(format: "ears slid down %.0f deg", f.earSlide) : f.earSlide < 0 ? String(format: "ears nudged in %.0f deg", -f.earSlide) : "ears as is"
            notes += "\(look.art) | \(state) | \(f.earSlide) | pom \(f.pomHidden ? "tucked" : "shown")\n"
            front.append(tlabel(sF.img.uiImage()!, ["\(look.title) - \(state)"], bar: 28))
            back.append(tlabel(sB.img.uiImage()!, ["\(look.title) (back 3/4)"], bar: 28))
        }
        try writePNG(tgrid(front, cols: 5), d + "/04_hats_front34.png")
        try writePNG(tgrid(back, cols: 5), d + "/04_hats_back34.png")
        try notes.write(toFile: d + "/hat_rule_table.txt", atomically: true, encoding: .utf8)
    }

    func testTeddyNeckAndBody() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        let looks = WearLook.looks(.neck) + WearLook.looks(.body)
        var back: [UIImage] = [], notes = "piece | pom\n"
        for look in looks {
            let sB = try teddyShot(outfit: [look.slot: look], yaw: 2.5, size: 420, dist: 3.3, lookY: 0.3, lift: 0.1)
            let sF = try teddyShot(outfit: [look.slot: look], yaw: 0.6, size: 420, dist: 3.3, lookY: 0.3, lift: 0.1)
            notes += "\(look.art) | pom \(sB.fit.pomHidden ? "tucked" : "shown")\n"
            back.append(tlabel(sB.img.uiImage()!, ["\(look.title) - pom \(sB.fit.pomHidden ? "tucked" : "shown")"], bar: 28))
            back.append(tlabel(sF.img.uiImage()!, ["\(look.title) (front 3/4)"], bar: 28))
        }
        try writePNG(tgrid(back, cols: 6), d + "/05_neck_body_pieces.png")
        try notes.write(toFile: d + "/neck_rule_table.txt", atomically: true, encoding: .utf8)
    }

    // MARK: 4. motion

    func testTeddyMotion() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        let only = (ProcessInfo.processInfo.environment["TEDDY_ONLY"] ?? "").split(separator: ",").map(String.init)
        typealias Start = (MotionRig) -> Void
        func walk(_ dx: Float, _ dz: Float, hurry: Bool) -> Start { { r in
            let p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.hurry = hurry
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        func idle(_ k: IdleKind) -> Start { { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(k, r.sim), "idle \(k)") } }
        let scenarios: [(String, Float, Float, Start)] = [
            ("walk", 0.8, 2.4, walk(-3, 0.3, hurry: false)),
            ("run", 0.6, 1.8, walk(-4, 0.3, hurry: true)),
            ("hop", 0.0, 1.6, { r in r.brain.startHopPlay(sim: r.sim) }),
            ("sleep", 0.0, 6.0, { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 500 }),
            ("eat", 0.0, 3.0, { r in r.brain.script = .eat(t: 0, bowl: SIMD2(0, 2), dur: 3.0, drink: false); r.brain.activity = .eating }),
            ("spin", 0.0, 3.0, { r in r.brain.startSpin(sim: r.sim) }),
            ("roll", 0.0, 2.4, { r in r.brain.startRollPlay(sim: r.sim) }),
            ("backflip", 0.0, 2.4, { r in r.brain.startFlip(sim: r.sim) }),
            ("tailspin", 0.0, 4.0, idle(.tail)),
            ("bounce", 0.0, 3.0, idle(.bounce)),
            ("flop", 0.0, 3.0, idle(.flop)),
            ("liedown", 0.0, 4.0, idle(.lieDown)),
            ("shake", 0.0, 2.4, idle(.shake)),
        ]
        var stats = ""
        for (name, warm, secs, start) in scenarios where only.isEmpty || only.contains(name) {
            W = 420; H = 420
            let c = Char(id: 4)
            let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
            let r = lab.rigs[0]
            r.brain.autonomy = false; r.brain.expr.enabled = false
            let dd = dress(lab, [c])
            let (ren, target) = try renderer(lab)
            for _ in 0..<60 { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c) }
            start(r)
            var frames: [[UIImage]] = [[], []]
            var minPomY: Float = 9, minEarY: Float = 9, frame = 0
            let total = Int((warm + secs) * 60)
            for t in 0..<total {
                lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c)
                // numbers: the lowest pom / ear vertex above the floor, from the real emitted mesh
                let sk = skin(r)
                let ff = sk.withUnsafeBufferPointer { p in dd.feats[0].frame { _ in p.baseAddress } }
                if let s = dd.feats[0].slot(0), s.scale > 0.5 {
                    let prep = FeatureMeshes.prepare(.ears, body: WearBody.shared)!
                    var off = 0
                    for (pi, part) in prep.parts.enumerated() {
                        let vis = (s.partScale[part.name] ?? 1) > 0.5
                        for k in 0..<part.count where vis && off + k < ff.vertices.count {
                            let y = ff.vertices[off + k].pos.y - r.sim.floorY
                            if pi == 2 { minPomY = min(minPomY, y) } else { minEarY = min(minEarY, y) }
                        }
                        off += part.count
                    }
                }
                if t >= Int(warm * 60), t % 4 == 0 {
                    let pose = r.sim.bodyPose(iterations: 3)
                    var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
                    fwd = simd_length(fwd) > 0.3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
                    for (ci, yaw) in [Float(0.75), Float(2.4)].enumerated() {
                        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
                        let cam = Self.lookCamera(target: SIMD3(pose.centroid.x, r.sim.floorY + 0.55, pose.centroid.z), dir: dir, dist: 3.9, aspect: 1, lift: 0.18)
                        let img = composite(lab, dd, [c], ren, target, cam: cam)
                        frames[ci].append(tlabel(img.uiImage()!, ["\(name) \(ci == 0 ? "front 3/4" : "back 3/4") f\(frame)"], bar: 26))
                    }
                    frame += 1
                }
            }
            for ci in 0..<2 {
                let n = frames[ci].count
                let pick = (0..<min(8, n)).map { frames[ci][$0 * n / min(8, n)] }
                try writePNG(tgrid(pick, cols: 4), d + "/06_motion_\(name)_\(ci == 0 ? "front" : "back").png")
            }
            stats += String(format: "%@: lowest pom vertex %.3f above the floor, lowest ear vertex %.3f (frames %d)\n", name, minPomY, minEarY, frame)
        }
        try stats.write(toFile: d + "/motion_floor_clearance.txt", atomically: true, encoding: .utf8)
        print(stats)
    }
}
