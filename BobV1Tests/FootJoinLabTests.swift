//
//  FootJoinLabTests.swift
//  Lab (temporary, not committed): the foot-piece / belly join while the pieces are out. Renders low close-ups with toggles and measures the crossing line.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class FootJoinLabTests: XCTestCase {
    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/feet/lab"
    static var tag: String { ProcessInfo.processInfo.environment["LAB_TAG"] ?? "x" }
    static func log(_ s: String) {
        print(s)
        let p = out + "/lab_\(tag).txt"
        if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); h.closeFile() } else { FileManager.default.createFile(atPath: p, contents: (s + "\n").data(using: .utf8)) }
    }

    /// The crossing line of the body skin with foot piece `s` (world): per crossing point its polar angle about the piece axis, its axial height, and the angle between the two surfaces there.
    static func crossing(_ r: MotionRig, _ s: Int) -> (pts: [(th: Float, h: Float, ang: Float)], saw: Float, p50: Float, p10: Float) {
        let rm = MotionRig.renderMesh
        let d = r.dyn
        @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
        @inline(__always) func N(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v + 3], d[6 * v + 4], d[6 * v + 5]) }
        let f = Int(r.bean[s][0]), nB = FootBean.vertexCount
        let sole = P(f), top = P(f + nB - 1)
        let a = simd_normalize(sole - top)
        let tmp: SIMD3<Float> = abs(a.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let e1 = simd_normalize(simd_cross(a, tmp)), e2 = simd_cross(a, e1)
        var c = SIMD3<Float>.zero
        for j in 0..<FootBean.around { c += P(f + 1 + FootBean.around * Skinner.collarRing + j) }
        c /= Float(FootBean.around)
        // the piece's triangles
        let bt = FootBean.triangles(firstVertex: f)
        func inside(_ p: SIMD3<Float>) -> Bool {
            // ray along a fixed odd direction, parity of hits
            let dir = simd_normalize(SIMD3<Float>(0.31, 0.17, 0.93))
            var hits = 0
            var t = 0
            while t < bt.count {
                let A = P(Int(bt[t])), B = P(Int(bt[t + 1])), C = P(Int(bt[t + 2])); t += 3
                let e1 = B - A, e2 = C - A, pv = simd_cross(dir, e2), det = simd_dot(e1, pv)
                if abs(det) < 1e-12 { continue }
                let inv = 1 / det, tv = p - A, u = simd_dot(tv, pv) * inv
                if u < 0 || u > 1 { continue }
                let qv = simd_cross(tv, e1), v = simd_dot(dir, qv) * inv
                if v < 0 || u + v > 1 { continue }
                if simd_dot(e2, qv) * inv > 0 { hits += 1 }
            }
            return hits % 2 == 1
        }
        // visible body skin near the piece (not the embedded foot's own cup: that one is retracted and hidden)
        var cup = Set<Int32>()
        for (k, v) in r.skinner.retractVertices.enumerated() where r.skinner.retractSide[k] >= 0 && r.skinner.retractWeight[k] > 0.5 { cup.insert(v) }
        let bodyEnd = rm.armCapsule?.firstVertex[0] ?? rm.vertexCount
        var near = [Bool](repeating: false, count: bodyEnd), ins = [Int8](repeating: -1, count: bodyEnd)
        for v in 0..<bodyEnd where !cup.contains(Int32(v)) && simd_distance(P(v), c) < 0.32 { near[v] = true }
        func isIn(_ v: Int) -> Bool { if ins[v] < 0 { ins[v] = inside(P(v)) ? 1 : 0 }; return ins[v] == 1 }
        var pts: [(th: Float, h: Float, ang: Float)] = []
        var seen = Set<Int>()
        let limit = rm.armCapsule?.indexFirst ?? rm.index.count
        var t = 0
        while t < limit {
            let tri = [Int(rm.index[t]), Int(rm.index[t + 1]), Int(rm.index[t + 2])]; t += 3
            guard tri.allSatisfy({ $0 < bodyEnd && near[$0] }) else { continue }
            let fn = simd_normalize(simd_cross(P(tri[1]) - P(tri[0]), P(tri[2]) - P(tri[0])))
            for k in 0..<3 {
                let v0 = tri[k], v1 = tri[(k + 1) % 3]
                let key = min(v0, v1) * 1_000_000 + max(v0, v1)
                if seen.contains(key) { continue }
                let i0 = isIn(v0), i1 = isIn(v1)
                guard i0 != i1 else { continue }
                seen.insert(key)
                var lo = P(i0 ? v1 : v0), hi = P(i0 ? v0 : v1)          // lo outside, hi inside
                for _ in 0..<10 { let m = (lo + hi) / 2; if inside(m) { hi = m } else { lo = m } }
                let x = (lo + hi) / 2, u = x - c
                // the piece's normal at the crossing: nearest piece vertex
                var bestD = Float.infinity, bn = SIMD3<Float>(0, 0, 0)
                for i in 0..<nB { let dd = simd_distance_squared(P(f + i), x); if dd < bestD { bestD = dd; bn = N(f + i) } }
                let cosA = abs(simd_dot(simd_normalize(bn), fn))
                pts.append((atan2f(simd_dot(u, e2), simd_dot(u, e1)), simd_dot(u, a), acosf(min(1, cosA)) * 180 / .pi))
            }
        }
        pts.sort { $0.th < $1.th }
        // sawtooth: the largest deviation of the crossing height from its neighbours' mean within +-12 deg (circular)
        var saw: Float = 0
        for p in pts {
            var sum: Float = 0, n: Float = 0
            for q in pts {
                var dth = q.th - p.th; while dth > .pi { dth -= 2 * .pi }; while dth < -.pi { dth += 2 * .pi }
                if abs(dth) <= 12 * .pi / 180 { sum += q.h; n += 1 }
            }
            if n >= 3 { saw = max(saw, abs(p.h - sum / n)) }
        }
        let angs = pts.map(\.ang).sorted()
        let p50 = angs.isEmpty ? 0 : angs[angs.count / 2], p10 = angs.isEmpty ? 0 : angs[angs.count / 10]
        return (pts, saw, p50, p10)
    }

    func testJoinLab() throws {
        let vs = (ProcessInfo.processInfo.environment["LAB_VARIANTS"] ?? "").split(separator: ",").map(String.init)
        if vs.isEmpty { try lab(""); return }
        for v in vs {
            let p = v.split(separator: ":").compactMap { Float(String($0)) }
            Skinner.collarK = p[0]; Skinner.collarIn = p[1]; if p.count > 2 { Skinner.collarInFade = p[2] }
            try lab("_" + v.replacingOccurrences(of: ":", with: "-"))
        }
        Skinner.collarK = 0.07; Skinner.collarIn = 0.03; Skinner.collarInFade = 0.07
    }

    func lab(_ vtag: String) throws {
        try FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no metal") }
        let rm = MotionRig.renderMesh
        let W = 1200, H = 1200
        for (mname, start) in [("sway2", { (r: MotionRig) in r.brain.idleForced = true; _ = r.brain.idleStart(.sway, r.sim) }), ("look", { (r: MotionRig) in r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim) }),
                               ("sway", { (r: MotionRig) in r.brain.idleForced = true; _ = r.brain.idleStart(.sway, r.sim) }),
                               ("walk", { (r: MotionRig) in r.brain.request(.goTo(SIMD2(1.6, 0.4))) }),
                               ("bounce", { (r: MotionRig) in r.brain.idleForced = true; _ = r.brain.idleStart(.bounce, r.sim) })] as [(String, (MotionRig) -> Void)] {
            for char in [0] {
                let r = MotionRig(game: true, settle: 0.5)
                r.skinner.autoBlink = false
                r.brain.feature = JellyRoster.feature(char)
                r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
                guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: r.sim.edges, particleCount: r.sim.n) else { throw XCTSkip("no renderer") }
                ren.resize(width: W, height: H)
                let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
                td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
                let tex = device.makeTexture(descriptor: td)!
                func draw(_ s: Int, _ name: String) {
                    r.render()
                    let c = r.sim.centroid()
                    var foot = SIMD3<Float>.zero
                    for id in r.bean[s] { let o = 6 * Int(id); foot += SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2]) }
                    foot /= Float(r.bean[s].count)
                    var out = SIMD3(foot.x - c.x, 0, foot.z - c.z); out = simd_length(out) > 1e-3 ? simd_normalize(out) : SIMD3(0, 0, 1)
                    let at = foot + SIMD3(0, 0.08, 0)
                    let dir = simd_normalize(out + SIMD3(0, 0.35, 0))
                    let eye = at + dir * 1.5
                    var cam = CameraState()
                    cam.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
                    cam.viewProj = M4.mul(M4.perspective(fovy: 30 * .pi / 180, aspect: 1, near: 0.05, far: 60), cam.view)
                    cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(at - eye)
                    ren.beginFrame()
                    r.dyn.withUnsafeBufferPointer { b in ren.dynPointer.update(from: b.baseAddress!, count: b.count) }
                    var fp = FrameParams()
                    fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                    fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7
                    let pal = JellyRoster.palette(char) ?? PaletteKey.blue.palette
                    fp.bg = melonBackgroundLinear
                    var rig = CameraRig(); rig.target = c
                    ren.setUniforms(camera: cam, light: rig.light(centroid: c), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
                    let cmd = ren.queue.makeCommandBuffer()!
                    ren.draw(to: tex, commandBuffer: cmd, showMesh: false)
                    cmd.waitUntilCompleted()
                    var px = [UInt8](repeating: 0, count: W * H * 4)
                    px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
                    LockImage(w: W, h: H, bgra: px).png(to: URL(fileURLWithPath: Self.out + "/\(Self.tag)_\(name).png"))
                }
                start(r)
                var shots = 0, frame = 0, firstOut = -1, airShots = 0, liftShots = 0
                var worstSaw: Float = 0, worstP10: Float = 180, sumP50: Float = 0, nP50: Float = 0, beanFrames = 0
                while frame < 60 * 5 && (shots < 2 || airShots < 2) {
                    r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); frame += 1
                    guard r.skinner.beansActive, r.skinner.beanBlend > 0.95 else { continue }
                    if firstOut < 0 { firstOut = frame }
                    let airNow = (0..<2).allSatisfy { k in (r.skinner.beanPos[k].map(\.y).min() ?? 0) - r.sim.floorY > 0.03 }
                    let cl = (0..<2).map { k in (r.skinner.beanPos[k].map(\.y).min() ?? 0) - r.sim.floorY }
                    if liftShots < 3 && frame % 4 == 0, let lifted = (0..<2).first(where: { cl[$0] > 0.025 && cl[1 - $0] < 0.005 }) {
                        r.render(); draw(lifted, "\(mname)_c\(char)_lift\(liftShots)\(vtag)")
                        Skinner.collarCrossing = false; r.render(); draw(lifted, "\(mname)_c\(char)_lift\(liftShots)\(vtag)_old"); Skinner.collarCrossing = true
                        Self.log(String(format: "[lift%@] %@ shot %d foot %d clearance %.3f", vtag, mname, liftShots, lifted, cl[lifted]))
                        liftShots += 1
                    }
                    if airNow && airShots < 2 && frame % 5 == 0 {
                        r.render()
                        let l0 = FootJoinLineTests.line(r, 1)
                        draw(1, "\(mname)_c\(char)_air\(airShots)\(vtag)")
                        Skinner.collarAirFade = false
                        r.render(); let l1 = FootJoinLineTests.line(r, 1)
                        draw(1, "\(mname)_c\(char)_air\(airShots)\(vtag)_collarInAir")
                        Skinner.collarAirFade = true
                        Self.log(String(format: "[air%@] %@ c%d shot %d: fade %.2f | faded: saw %.2f cm p10 %.1f deg | collar kept: saw %.2f cm p10 %.1f deg", vtag, mname, char, airShots, r.skinner.collarFade, l0.saw * 100, l0.p10, l1.saw * 100, l1.p10))
                        airShots += 1
                    }
                    r.render()
                    let grounded = (0..<2).allSatisfy { k in (r.skinner.beanPos[k].map(\.y).min() ?? 0) - r.sim.floorY < 0.01 }
                    if frame % 4 == 0 && grounded {
                        beanFrames += 1
                        for s in 0..<2 {
                            let m = Self.crossing(r, s)
                            if m.saw > worstSaw + 0.01 && m.saw > 0.03 {
                                draw(s, "\(mname)_c\(char)_worst\(vtag)")
                                let txt = m.pts.map { String(format: "%.1f %.2f %.0f", $0.th * 180 / .pi, $0.h * 100, $0.ang) }.joined(separator: "\n")
                                try? txt.write(toFile: Self.out + "/\(Self.tag)_\(mname)_c\(char)_worst\(vtag)_s\(s).txt", atomically: true, encoding: .utf8)
                            }
                            worstSaw = max(worstSaw, m.saw); worstP10 = min(worstP10, m.p10); sumP50 += m.p50; nP50 += 1
                        }
                    }
                    if ((shots == 0 && frame - firstOut >= 20) || (shots == 1 && frame - firstOut >= 50)) && grounded {
                        let nm = "\(mname)_c\(char)_\(shots)\(vtag)"
                        draw(1, nm)
                        if shots == 0 {
                            r.skinner.collarEnabled = false; draw(1, nm + "_nocollar"); r.skinner.collarEnabled = true
                            Skinner.dbgNoRetract = true; draw(1, nm + "_noretract"); Skinner.dbgNoRetract = false
                            r.skinner.joinEnabled = false; draw(1, nm + "_nojoin"); r.skinner.joinEnabled = true
                        }
                        shots += 1
                    }
                }
                Self.log(String(format: "[footjoin%@] %@ char %d: grounded bean frames %d | sawtooth max %.2f cm | crossing angle p10 %.1f deg, mean p50 %.1f deg", vtag, mname, char, beanFrames, worstSaw * 100, worstP10, nP50 > 0 ? sumP50 / nP50 : 0))
            }
        }
    }
}
