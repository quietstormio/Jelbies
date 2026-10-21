//
//  BaseBodyDumpTests.swift
//  Records (and later re-records) the exact rest body: constants, meshes, palettes, shader text, plus deterministic
//  offscreen renders. Writes to $BOB_GOLDEN_DIR (default: NSTemporaryDirectory()/bob_golden). Uses only APIs that exist
//  in both the phone build and the current repo; env-only knobs live in `LockEnv`.
//
//  Env (pass to xcodebuild as SIMCTL_CHILD_<NAME>):
//    BOB_GOLDEN_DIR  output directory
//    BOB_RENDER_DIR  sub directory name for renders (default "renders")
//    BOB_FIT         "az,el,zoom;az,el,zoom;..." extra Baby-blue candidate cameras (fit tooling)
//

import XCTest
import simd
import Metal
import UIKit
import CryptoKit
@testable import BobV1

// MARK: - Adapter: the only place that touches app API (identical in both trees as of phase 1)

nonisolated enum LockEnv {
    static var outDir: URL {
        let p = ProcessInfo.processInfo.environment["BOB_GOLDEN_DIR"] ?? (NSTemporaryDirectory() + "bob_golden")
        let u = URL(fileURLWithPath: p, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var renderDirName: String { ProcessInfo.processInfo.environment["BOB_RENDER_DIR"] ?? "renders" }
    static var fit: String? { ProcessInfo.processInfo.environment["BOB_FIT"] }
}

// MARK: - Block writer (hash over raw little-endian bytes, JSON carries the bit patterns)

nonisolated final class LockBlock {
    let name: String
    private var bytes = Data()
    private(set) var json: [String: Any] = [:]
    init(_ name: String) { self.name = name }

    private func key(_ k: String) { bytes.append(Data(k.utf8)); bytes.append(0) }
    func f(_ k: String, _ v: [Float]) {
        key(k)
        var bits = [UInt32](); bits.reserveCapacity(v.count)
        for x in v { let b = x.bitPattern.littleEndian; bits.append(b); withUnsafeBytes(of: b) { bytes.append(contentsOf: $0) } }
        var e: [String: Any] = ["type": "f32", "count": v.count, "bits": bits]
        if v.count <= 64 { e["values"] = v.map { Double($0) } }
        json[k] = e
    }
    func d(_ k: String, _ v: [Double]) {
        key(k)
        var bits = [UInt64](); bits.reserveCapacity(v.count)
        for x in v { let b = x.bitPattern.littleEndian; bits.append(b); withUnsafeBytes(of: b) { bytes.append(contentsOf: $0) } }
        var e: [String: Any] = ["type": "f64", "count": v.count, "bits": bits.map { String($0, radix: 16) }]
        if v.count <= 64 { e["values"] = v }
        json[k] = e
    }
    func i(_ k: String, _ v: [Int]) {
        key(k)
        for x in v { withUnsafeBytes(of: Int64(x).littleEndian) { bytes.append(contentsOf: $0) } }
        json[k] = ["type": "int", "count": v.count, "values": v] as [String: Any]
    }
    func s(_ k: String, _ v: String) {
        key(k); bytes.append(Data(v.utf8)); bytes.append(0)
        json[k] = ["type": "string", "value": v] as [String: Any]
    }
    func f3(_ k: String, _ v: SIMD3<Float>) { f(k, [v.x, v.y, v.z]) }
    func d3(_ k: String, _ v: SIMD3<Double>) { d(k, [v.x, v.y, v.z]) }
    var sha256: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    var document: [String: Any] { ["block": name, "sha256": sha256, "byteCount": bytes.count, "fields": json] }
}

nonisolated func lockSHA(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

// MARK: - Shader text chunks

nonisolated enum ShaderChunks {
    /// Removes the mouth block (`float mo = u.stripe.w;` + the `if (...) { ... }` that follows) and the blush block (`float bl = u.seed.w;` + its `if`) from fsSoftMatte's text.
    /// Both decals only exist while their uniform is above zero, so the shader is pixel-identical to the locked one without them (2026-10-20: the blush is a user-approved addition).
    static func stripMouth(_ t: String) -> String {
        func strip(_ marker: String, _ t: String) -> String {
            guard let r = t.range(of: marker), let open = t.range(of: "{", range: r.upperBound..<t.endIndex) else { return t }
            var depth = 0, i = open.lowerBound
            while i < t.endIndex {
                if t[i] == "{" { depth += 1 } else if t[i] == "}" { depth -= 1; if depth == 0 { break } }
                i = t.index(after: i)
            }
            guard i < t.endIndex else { return t }
            var out = t
            out.removeSubrange(r.lowerBound...i)
            return out
        }
        return strip("float bl = u.seed.w;", strip("float mo = u.stripe.w;", t))
    }
    /// Top-level definitions of the .metal file keyed by name, each hashed after comment stripping + whitespace folding.
    static func hashes(of text: String) -> [String: String] {
        var t = text
        while let r = t.range(of: "/*"), let e = t.range(of: "*/", range: r.upperBound..<t.endIndex) { t.removeSubrange(r.lowerBound..<e.upperBound) }
        t = t.split(separator: "\n", omittingEmptySubsequences: false).map { l -> String in
            if let r = l.range(of: "//") { return String(l[l.startIndex..<r.lowerBound]) }
            return String(l)
        }.joined(separator: "\n")
        var out: [String: String] = [:]
        var depth = 0, start = t.startIndex, headerEnd: String.Index? = nil
        var i = t.startIndex
        var counter = 0
        while i < t.endIndex {
            let c = t[i]
            if c == "{" { if depth == 0 { headerEnd = i }; depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0, let he = headerEnd {
                    let header = String(t[start..<he]).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    let body = String(t[start...i]).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    var name = header
                    if let p = header.firstIndex(of: "(") {
                        let pre = header[header.startIndex..<p].split(separator: " ")
                        name = String(pre.last ?? "?")
                    }
                    if out[name] != nil { counter += 1; name += "#\(counter)" }
                    out[name] = lockSHA(body)
                    start = t.index(after: i)
                }
            } else if c == ";" && depth == 0 {
                start = t.index(after: i)   // top-level declaration without a body (using, constants)
            }
            i = t.index(after: i)
        }
        return out
    }
}

// MARK: - Offscreen render helpers

nonisolated struct LockImage {
    var w: Int, h: Int
    var bgra: [UInt8]
    func maxDiff(_ o: LockImage) -> Int {
        var m = 0
        for k in 0..<bgra.count { m = max(m, abs(Int(bgra[k]) - Int(o.bgra[k]))) }
        return m
    }
    /// The pixels as a CGImage, copied while the backing array is alive. (The old pattern let the CGContext escape `withUnsafeMutableBytes`
    /// and drew it afterwards; under -O the array's lifetime ends at its last use, so large frames came out black.)
    func cgImage() -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        var data = bgra
        return data.withUnsafeMutableBytes { p -> CGImage? in
            let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            return ctx?.makeImage()
        }
    }
    func png(to url: URL) {
        guard let cg = cgImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
    func uiImage() -> UIImage? {
        guard let cg = cgImage() else { return nil }
        return UIImage(cgImage: cg)
    }
}

nonisolated struct LockView {
    var name: String
    var azimuth: Float
    var elevation: Float
    var zoom: Float
}

/// The phone-matching 3/4 view (fitted against docs/reference/locked_body_phone.png).
nonisolated let lockThreeQuarter = LockView(name: "threeq", azimuth: 0.79, elevation: 0.08, zoom: 1.0)

nonisolated let lockViews: [LockView] = [
    LockView(name: "front", azimuth: 0.056, elevation: 0.123, zoom: 1),          // CameraRig defaults (studio front)
    lockThreeQuarter,
    LockView(name: "right", azimuth: -Float.pi / 2, elevation: 0.123, zoom: 1),  // camera on Bob's right (-x) side
    LockView(name: "left", azimuth: Float.pi / 2, elevation: 0.123, zoom: 1),    // camera on Bob's left (+x) side
    LockView(name: "back", azimuth: Float.pi, elevation: 0.123, zoom: 1),
]

/// (file tag, key) in the order Blush, Pink, Butter, Baby blue.
nonisolated let lockPalettes: [(String, PaletteKey)] = [("blush", .blush), ("pink", .pink), ("butter", .yellow), ("babyblue", .blue)]

/// Stage size as on the phone: 440 x 480 pt at 3x.
nonisolated let lockPoints = CGSize(width: 440, height: 480)
nonisolated let lockScale = 3
nonisolated var lockPixelW: Int { Int(lockPoints.width) * lockScale }
nonisolated var lockPixelH: Int { Int(lockPoints.height) * lockScale }

@MainActor
final class LockScene {
    let sm: SimMesh, rm: RenderMesh
    let body: SoftBody
    let skinner: Skinner
    let renderer: MelonRenderer
    let target: MTLTexture
    let dyn: [Float]

    init?(settledSteps: Int = 0) {
        let ap = BlobAppearance.berry
        sm = buildSimMesh(appearance: ap)
        rm = buildRenderMesh(appearance: ap)
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        body = SoftBody(mesh: sm, firmness: 0.95, damping: 0.45)
        skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                          eyes: buildEyeRig(render: rm, sim: sm, appearance: ap),
                          antennae: buildAntennaRig(render: rm, sim: sm))
        skinner.autoBlink = false          // never tickBlink: eyes stay at height 1
        guard let device = MTLCreateSystemDefaultDevice(),
              let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: body.edges, particleCount: body.n)
        else { return nil }
        renderer = r
        r.resize(width: lockPixelW, height: lockPixelH)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: lockPixelW, height: lockPixelH, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        target = t
        if settledSteps == 0 { body.reset(drop: 0) } else { body.reset(drop: 0.35); for _ in 0..<settledSteps { body.step() } }
        dyn = []
    }

    func render(_ v: LockView, palette: PaletteKey) -> LockImage {
        var rig = CameraRig()
        rig.azimuth = v.azimuth; rig.elevation = v.elevation; rig.zoom = v.zoom
        let cam = rig.camera(viewSize: lockPoints, safeRect: CameraRig.fullSafeRect(lockPoints))
        let light = rig.light(centroid: body.centroid())
        renderer.beginFrame()
        skinner.update(x: body.x, index: rm.index, into: renderer.dynPointer)
        var fp = FrameParams()
        fp.time = 0
        fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
        fp.exposure = 1
        fp.meshAlpha = 0
        let pal = palette.palette
        fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
        renderer.setUniforms(camera: cam, light: light, palette: pal, params: fp,
                             viewSize: SIMD2<Float>(Float(lockPixelW), Float(lockPixelH)))
        let cmd = renderer.queue.makeCommandBuffer()!
        renderer.draw(to: target, commandBuffer: cmd, showMesh: false)
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: lockPixelW * lockPixelH * 4)
        px.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: lockPixelW * 4, from: MTLRegionMake2D(0, 0, lockPixelW, lockPixelH), mipmapLevel: 0)
        }
        return LockImage(w: lockPixelW, h: lockPixelH, bgra: px)
    }
}


// MARK: - Base view of the render mesh (drops the wave-arm capsules, which the phone build did not have)

nonisolated struct LockCapsules {
    var firstVertex: [Int]
    var vertsPer: Int
    var indexFirst: Int, indexCount: Int
    var vertexRange: Range<Int> { firstVertex[0]..<(firstVertex[1] + vertsPer) }
}

/// Adapter: `RenderMesh.armCapsule` exists only in the current tree, so it is read by reflection (nil in the phone build).
func lockCapsules(_ rm: RenderMesh) -> LockCapsules? {
    for c in Mirror(reflecting: rm).children where c.label == "armCapsule" {
        let opt = Mirror(reflecting: c.value)
        guard opt.displayStyle == .optional, let some = opt.children.first?.value else { return nil }
        var fv: [Int] = [], ifirst = 0, icount = 0
        for ch in Mirror(reflecting: some).children {
            switch ch.label {
            case "firstVertex": fv = (ch.value as? [Int]) ?? []
            case "indexFirst": ifirst = (ch.value as? Int) ?? 0
            case "indexCount": icount = (ch.value as? Int) ?? 0
            default: break
            }
        }
        guard fv.count == 2 else { return nil }
        return LockCapsules(firstVertex: fv, vertsPer: fv[1] - fv[0], indexFirst: ifirst, indexCount: icount)
    }
    return nil
}

/// The render mesh without capsule vertices / triangles, vertex numbers compacted. Identity on the phone build.
struct LockBase {
    let caps: LockCapsules?
    let keep: [Int]            // original vertex numbers that remain
    let map: [Int]             // original -> base (-1 = capsule)
    let index: [UInt32]
    let body: (first: Int, count: Int), seeds: (first: Int, count: Int), bubbles: (first: Int, count: Int)
    let vertexCount: Int

    init(_ rm: RenderMesh) {
        caps = lockCapsules(rm)
        var keep: [Int] = [], map = [Int](repeating: -1, count: rm.vertexCount)
        let skip = caps?.vertexRange ?? 0..<0
        for v in 0..<rm.vertexCount where !skip.contains(v) { map[v] = keep.count; keep.append(v) }
        self.keep = keep; self.map = map
        var idx: [UInt32] = []
        let ci = caps?.indexFirst ?? Int.max, cc = caps?.indexCount ?? 0
        var t = 0
        while t < rm.index.count {
            if !(t >= ci && t < ci + cc) { for k in 0..<3 { idx.append(UInt32(map[Int(rm.index[t + k])])) } }
            t += 3
        }
        index = idx
        func shift(_ r: (first: Int, count: Int)) -> (first: Int, count: Int) {
            (r.first >= ci + cc ? r.first - cc : r.first, r.count - (r.first <= ci && r.first + r.count >= ci + cc ? cc : 0))
        }
        body = shift(rm.body); seeds = shift(rm.seeds); bubbles = shift(rm.bubbles)
        vertexCount = keep.count
    }
    func pick(_ a: [Float], stride: Int) -> [Float] {
        var o = [Float](); o.reserveCapacity(keep.count * stride)
        for v in keep { for k in 0..<stride { o.append(a[stride * v + k]) } }
        return o
    }
    func remap(_ v: [Int32]) -> [Int] { v.map { map[Int($0)] } }
}

// MARK: - Block builder (shared by the dump and BaseBodyLockTests)

@MainActor
func lockBuildBlocks(writeTo out: URL?) throws -> [String: String] {
        var hashes: [String: String] = [:]
        func emit(_ b: LockBlock) throws {
        if let out { let data = try JSONSerialization.data(withJSONObject: b.document, options: [.sortedKeys]); try data.write(to: out.appendingPathComponent("\(b.name).json")) }
        hashes[b.name] = b.sha256
    }

        // ---- constants_form: BobForm + proportions + shape
        let c = LockBlock("constants_form")
        c.d("lift", [BobForm.lift]); c.d("bodyH", [BobForm.bodyH]); c.d("top", [BobForm.top])
        c.d("halfW", [BobForm.halfW]); c.d("halfD", [BobForm.halfD])
        c.d("front", [BobForm.front.tw, BobForm.front.ratio, BobForm.front.pb, BobForm.front.pt])
        c.d("side", [BobForm.side.tw, BobForm.side.ratio, BobForm.side.pb, BobForm.side.pt])
        c.d3("armC", BobForm.armC); c.d("armTilt", [BobForm.armTilt])
        c.d3("armUp", BobForm.armUp); c.d3("armPerp", BobForm.armPerp); c.d3("armSemi", BobForm.armSemi)
        c.d3("armTop", BobForm.armTop); c.d3("armTip", BobForm.armTip)
        c.d("armTopR", [BobForm.armTopR]); c.d("armTipR", [BobForm.armTipR]); c.d("armFlatten", [BobForm.armFlatten])
        c.d("foot", [BobForm.footX, BobForm.footZ, BobForm.footCY, BobForm.footExp]); c.d3("footRadii", BobForm.footRadii)
        c.d("bellyRise", [BobForm.bellyRise])
        c.d("blends", [BobForm.armBlend, BobForm.armTipBlend, BobForm.footBlend])
        c.d("face", [BobForm.eyeX, BobForm.eyeY, BobForm.eyeHalfW, BobForm.eyeHalfH, BobForm.browY, BobForm.browHalfLen, BobForm.browHalfThick])
        let p = BlobProportions.standard
        c.f("proportions", [p.height, p.radius, p.widestT, p.baseRatio, p.bottomExp, p.topExp,
                            p.eyeT, p.eyeSpacingFrac, p.eyeRX, p.eyeRY, p.eyeBump,
                            p.browT, p.browHalfLen, p.browHalfThick, Float(p.browLines), p.browGap,
                            p.armT, p.armAzimuth, p.armOut, p.armLength, p.armWidth, p.armThick,
                            p.footAzimuth, p.footOut, p.footLength, p.footWidth, p.footHeight])
        c.f("blobShape", [BlobShape.H, BlobShape.R, BlobShape.baseR, Shape.T, Shape.Ro, Shape.skin, Shape.pale, Shape.baseR])
        c.f("eyeColorSRGB", [BlobShape.eyeColorSRGB.x, BlobShape.eyeColorSRGB.y, BlobShape.eyeColorSRGB.z])
        c.f("closedHeight", [Skinner.closedHeight])
        // SDF probe: the form sampled on a fixed lattice (catches refactors that keep constants but change the surface)
        var probe: [Double] = []
        for ix in 0..<17 { for iy in 0..<25 { for iz in 0..<17 {
            let q = SIMD3<Double>(-0.8 + 1.6 * Double(ix) / 16, -0.05 + 1.5 * Double(iy) / 24, -0.8 + 1.6 * Double(iz) / 16)
            probe.append(BobForm.sdf(q))
        } } }
        c.d("sdfProbe17x25x17", probe)
        var prof: [Double] = []
        for k in 0...256 { let t = Double(k) / 256; prof += [BobForm.halfWidth(t: t), BobForm.halfDepth(t: t)] }
        c.d("halfWidthDepthLUT257", prof)
        try emit(c)

        // ---- sim mesh
        let ap = BlobAppearance.berry
        let sm = buildSimMesh(appearance: ap)
        let rm = buildRenderMesh(appearance: ap)
        let s = LockBlock("sim_mesh")
        s.f("rest", sm.rest); s.i("tets", sm.tets.map { Int($0) }); s.i("region", sm.region.map { Int($0) })
        s.i("n2_layers", [sm.n2, sm.layers])
        s.i("appendages", sm.appendages.flatMap { a in [a.kind == .arm ? 0 : 1, a.side, a.particles.count] + a.particles })
        try emit(s)

        // ---- render mesh
        let r = LockBlock("render_mesh")
        let base = LockBase(rm)
        r.f("rest", base.pick(rm.rest, stride: 3)); r.f("restNormal", base.pick(rm.restNormal, stride: 3)); r.f("mat", base.pick(rm.mat, stride: 1))
        r.i("index", base.index.map { Int($0) })
        r.i("ranges", [base.body.first, base.body.count, base.seeds.first, base.seeds.count, base.bubbles.first, base.bubbles.count, rm.seedCount, base.vertexCount])
        try emit(r)

        // ---- embedding + eye rig
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let rig = buildEyeRig(render: rm, sim: sm, appearance: ap)
        let e = LockBlock("eye_rig")
        e.i("eyeL", base.remap(rig.eye[0])); e.i("eyeR", base.remap(rig.eye[1]))
        e.i("glintL", base.remap(rig.glint[0])); e.i("glintR", base.remap(rig.glint[1]))
        e.i("browL", base.remap(rig.brow[0])); e.i("browR", base.remap(rig.brow[1]))
        e.i("anchorTet", rig.anchorTet.map { Int($0) }); e.f("anchorW", rig.anchorW)
        e.i("embedTetOf", base.keep.map { Int(emb.tetOf[$0]) }); e.f("embedW", base.pick(emb.w, stride: 4))
        try emit(e)

        // ---- skinned rest pose (what the renderer draws at rest: positions + vertex normals)
        let body = SoftBody(mesh: sm, firmness: 0.95, damping: 0.45)
        body.reset(drop: 0)
        let skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount, eyes: rig,
                              antennae: buildAntennaRig(render: rm, sim: sm))
        var dyn = [Float](repeating: 0, count: rm.vertexCount * 6)
        dyn.withUnsafeMutableBufferPointer { skinner.update(x: body.x, index: rm.index, into: $0.baseAddress!) }
        let k = LockBlock("skinned_rest")
        k.f("dyn_pos_normal", base.pick(dyn, stride: 6))
        k.f("simX_after_reset0", body.x)
        k.f("centroid", [body.centroid().x, body.centroid().y, body.centroid().z])
        try emit(k)

        // ---- palettes (post-processed, as the shader receives them) + backgrounds
        let pl = LockBlock("palettes")
        for (tag, key) in lockPalettes {
            let q = key.palette
            pl.s("\(tag).name", q.name)
            pl.f3("\(tag).flesh", q.flesh); pl.f3("\(tag).fleshDeep", q.fleshDeep); pl.f3("\(tag).pale", q.pale)
            pl.f3("\(tag).skin", q.skin); pl.f3("\(tag).stripe", q.stripe); pl.f3("\(tag).seed", q.seed)
            pl.f3("\(tag).shadowTint", q.shadowTint); pl.f3("\(tag).uiFlesh", q.uiFlesh); pl.f3("\(tag).extra", q.extra)
            pl.f("\(tag).marking_bodyHeight_matte", [q.marking, q.bodyHeight, q.matte ? 1 : 0])
        }
        pl.s("keys", PaletteKey.allCases.map { $0.rawValue }.joined(separator: ","))
        pl.f3("melonCreamLinear", melonCreamLinear); pl.f3("melonBackgroundLinear", melonBackgroundLinear)
        try emit(pl)

        // ---- material / firmness / defaults as the app launches
        let model = MelonModel()
        let m = LockBlock("material_and_defaults")
        m.d("firmness_damping", [model.firmness, model.damping])
        m.s("defaultPalette", model.palette.rawValue)
        m.s("defaultBreed", model.appearance.breed.rawValue)
        m.i("appearanceIsBerryDefault", [model.appearance == BlobAppearance.berry ? 1 : 0])
        m.f("softBody", [body.stepDt, Float(body.substeps), body.gravity, body.friction, body.floorY, body.maxSpeed, body.firmness, body.damping])
        m.f("bobScale", [bobScaleCm, bobDensity, body.totalRestVolume * powf(bobScaleCm, 3) * bobDensity])
        m.f("frameParamsDefault", [FrameParams().exposure, FrameParams().meshAlpha, FrameParams().shape.x, FrameParams().shape.y, FrameParams().shape.z, FrameParams().shape.w])
        m.i("uniformsStride_msaa", [MemoryLayout<MelonUniforms>.stride, MelonRenderer.msaa])
        m.i("counts", [body.n, body.nT, body.nE])
        try emit(m)

        // ---- shader source chunks (matte look + crinkle live in Shaders.metal; not reachable from Swift)
        let metalURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("BobV1/Melon/Shaders.metal")
        let text = try String(contentsOf: metalURL, encoding: .utf8)
        let chunks = ShaderChunks.hashes(of: text)
        let sh = LockBlock("shader_chunks")
        for (name, h) in chunks.sorted(by: { $0.key < $1.key }) { sh.s(name, h) }
        try emit(sh)
        // same chunks with the mouth block removed from fsSoftMatte (identity on the phone build): the lock compares these
        let sh2 = LockBlock("shader_chunks_nomouth")
        for (name, h) in ShaderChunks.hashes(of: ShaderChunks.stripMouth(text)).sorted(by: { $0.key < $1.key }) { sh2.s(name, h) }
        try emit(sh2)
        XCTAssertNotNil(chunks["fsSoftMatte"]); XCTAssertNotNil(chunks["fsEyesMatte"]); XCTAssertNotNil(chunks["postFS"])
        XCTAssertNotNil(chunks["vsJelly"])

        // ---- camera / light framing (separate block so "framing changed" is distinguishable from "body changed")
        let cam = LockBlock("camera_framing")
        cam.f("rig", [CameraRig.defaultAzimuth, CameraRig.defaultElevation, CameraRig.fov, CameraRig.referenceAzimuth])
        cam.f3("home", CameraRig.home); cam.f3("restCentroid", CameraRig.restCentroid); cam.f3("keyDir", CameraRig.keyDir)
        let rg = CameraRig()
        let cs = rg.camera(viewSize: lockPoints, safeRect: CameraRig.fullSafeRect(lockPoints))
        func flat(_ mm: simd_float4x4) -> [Float] { [mm.columns.0, mm.columns.1, mm.columns.2, mm.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] } }
        cam.f("front_viewProj_440x480", flat(cs.viewProj))
        let lt = rg.light(centroid: body.centroid())
        cam.f("front_light", [lt.dir.x, lt.dir.y, lt.dir.z, lt.intensity] + flat(lt.lightVP) + flat(lt.topVP))
        try emit(cam)

        // ---- manifest
        if let out {
        let manifest: [String: Any] = ["blocks": hashes, "renderPixels": [lockPixelW, lockPixelH],
                                       "viewsFile": "see BaseBodyDumpTests.swift lockViews",
                                       "views": lockViews.map { ["name": $0.name, "az": Double($0.azimuth), "el": Double($0.elevation), "zoom": Double($0.zoom)] }]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted]).write(to: out.appendingPathComponent("manifest.json"))
        for (k, v) in hashes.sorted(by: { $0.key < $1.key }) { print("LOCKHASH \(k) \(v)") }
        }
        return hashes
}


// MARK: - Tests

@MainActor
final class BaseBodyDumpTests: XCTestCase {

    private func write(_ b: LockBlock, into dir: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: b.document, options: [.sortedKeys])
        try data.write(to: dir.appendingPathComponent("\(b.name).json"))
    }

    func testDumpBaseBody() throws {
        _ = try lockBuildBlocks(writeTo: LockEnv.outDir)
    }

    func testRenderGoldens() throws {
        let out = LockEnv.outDir.appendingPathComponent(LockEnv.renderDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Optional fit candidates (Baby blue)
        if let fit = LockEnv.fit {
            let sc = try XCTUnwrap(LockScene())
            for (n, part) in fit.split(separator: ";").enumerated() {
                let v = part.split(separator: ",").compactMap { Float($0) }
                guard v.count == 3 else { continue }
                let img = sc.render(LockView(name: "fit", azimuth: v[0], elevation: v[1], zoom: v[2]), palette: .blue)
                img.png(to: out.appendingPathComponent(String(format: "fit_%02d_az%.2f_el%.2f_z%.2f.png", n, v[0], v[1], v[2])))
            }
            return
        }

        let a = try XCTUnwrap(LockScene())
        var first: [String: LockImage] = [:]
        for (tag, key) in lockPalettes { for v in lockViews {
            let img = a.render(v, palette: key)
            first["\(tag)_\(v.name)"] = img
            img.png(to: out.appendingPathComponent("\(tag)_\(v.name).png"))
        } }
        // second pass: a brand-new device-side renderer, scene and textures
        let b = try XCTUnwrap(LockScene())
        var maxDiff = 0
        var perImage: [String: Int] = [:]
        for (tag, key) in lockPalettes { for v in lockViews {
            let img = b.render(v, palette: key)
            let d = img.maxDiff(first["\(tag)_\(v.name)"]!)
            perImage["\(tag)_\(v.name)"] = d
            maxDiff = max(maxDiff, d)
        } }
        // same renderer, repeated frames too
        let rep = a.render(lockViews[0], palette: .blue).maxDiff(first["babyblue_front"]!)
        print("LOCKDET inProcessFreshRenderer maxPixelDiff=\(maxDiff) sameRendererRepeat=\(rep)")
        let det: [String: Any] = ["maxPixelDiffFreshRenderer": maxDiff, "sameRendererRepeat": rep, "perImage": perImage,
                                  "images": first.count, "width": lockPixelW, "height": lockPixelH]
        try JSONSerialization.data(withJSONObject: det, options: [.sortedKeys, .prettyPrinted])
            .write(to: out.appendingPathComponent("determinism_in_process.json"))
        XCTAssertLessThanOrEqual(maxDiff, 1)

        // settled variant (phone comparison only; NOT part of the golden set)
        if let st = LockScene(settledSteps: 240) {
            st.render(lockThreeQuarter, palette: .blue).png(to: out.appendingPathComponent("extra_settled240_threeq_babyblue.png"))
        }

        // contact sheet: rows = palettes (Blush, Pink, Butter, Baby blue), columns = front, threeq, right, left, back
        let tw = 330, th = 360, pad = 8, lab = 22
        let W = pad + lockViews.count * (tw + pad), H = pad + lockPalettes.count * (th + lab + pad)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            UIColor(white: 0.85, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            for (r, (tag, _)) in lockPalettes.enumerated() { for (c, v) in lockViews.enumerated() {
                let x = pad + c * (tw + pad), y = pad + r * (th + lab + pad)
                ("\(tag) / \(v.name)" as NSString).draw(at: CGPoint(x: x, y: y + 2), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black])
                first["\(tag)_\(v.name)"]!.uiImage()?.draw(in: CGRect(x: x, y: y + lab, width: tw, height: th))   // 1320x1440 -> 330x360: uniform 1/4
            } }
        }
        try sheet.pngData()!.write(to: LockEnv.outDir.appendingPathComponent("sheet.png"))
    }
}
