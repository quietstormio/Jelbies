//
//  MelonPipelines.swift
//  The jelly renderer's fixed render pipeline states, built once per process. MelonRenderer.init takes them from here; the launch intro calls
//  `warm()` on a background thread so the shaders are compiled before the room is built (Metal compiles on the calling thread, ~0.4 s).
//  A second caller waits for the first instead of compiling again.
//

import Metal

nonisolated enum MelonPipelines {
    struct Pipes: @unchecked Sendable {
        let depth, background, props, back, copy, jelly, matte, eyes, matteBath, lines, post, cacheBlit, present: MTLRenderPipelineState
        let meshVD: MTLVertexDescriptor
        /// Tier-0 species-specialised matte body pipelines (GfxBodyFast.metal), keyed like MelonRenderer.fastMattePipeline: none / belly / belly+Teddy.
        let matteSpec: [Int: MTLRenderPipelineState]
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var libraries: [ObjectIdentifier: MTLLibrary] = [:]
    nonisolated(unsafe) private static var sets: [String: Pipes] = [:]

    nonisolated(unsafe) private static var noiseTex: [ObjectIdentifier: MTLTexture] = [:]
    /// 64^3 tiling lattice of the body shader's hash (r16Float), the source of -FibreLUT's value noise; one per device, made once (the launch warm-up calls it).
    static func fibreNoise(_ device: MTLDevice) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        if let t = noiseTex[ObjectIdentifier(device)] { return t }
        let n = 64
        let d = MTLTextureDescriptor()
        d.textureType = .type3D; d.pixelFormat = .r16Float; d.width = n; d.height = n; d.depth = n
        d.usage = .shaderRead; d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.label = "fibre noise lattice"
        func fract(_ x: Float) -> Float { x - x.rounded(.down) }
        var px = [Float16](repeating: 0, count: n * n * n)
        for z in 0..<n { for y in 0..<n { for x in 0..<n {
            // the shader's hash3 (Shaders.metal) at the lattice point
            var q = SIMD3<Float>(fract(Float(x) * 0.1031), fract(Float(y) * 0.1031), fract(Float(z) * 0.1031))
            let dd = q.x * (q.y + 33.33) + q.y * (q.z + 33.33) + q.z * (q.x + 33.33)
            q += SIMD3<Float>(repeating: dd)
            px[(z * n + y) * n + x] = Float16(fract((q.x + q.y) * q.z))
        } } }
        px.withUnsafeBytes { t.replace(region: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0, withBytes: $0.baseAddress!, bytesPerRow: n * 2, bytesPerImage: n * n * 2) }
        noiseTex[ObjectIdentifier(device)] = t
        return t
    }

    /// The app's default shader library for `device` (one per device, shared).
    static func library(_ device: MTLDevice) -> MTLLibrary? {
        lock.lock(); defer { lock.unlock() }
        if let l = libraries[ObjectIdentifier(device)] { return l }
        guard let l = device.makeDefaultLibrary() else { return nil }
        libraries[ObjectIdentifier(device)] = l
        return l
    }

    /// The pipeline set for the screen's colour format, compiled on first request.
    static func set(device: MTLDevice, library: MTLLibrary, colorPixelFormat: MTLPixelFormat) -> Pipes? {
        let key = "\(ObjectIdentifier(device).hashValue)/\(colorPixelFormat.rawValue)"
        lock.lock(); defer { lock.unlock() }          // held while compiling: a caller that arrives meanwhile waits for the result
        if let s = sets[key] { return s }
        guard let s = build(device: device, library: library, colorPixelFormat: colorPixelFormat) else { return nil }
        sets[key] = s
        return s
    }

    /// Compiles the pipelines the game screen uses (the on-screen format is bgra8Unorm). Call off the main thread.
    static func warm(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let lib = library(device) else { return }
        LaunchTiming.span("warm: pipelines") { _ = set(device: device, library: lib, colorPixelFormat: .bgra8Unorm) }
    }

    private static func build(device: MTLDevice, library: MTLLibrary, colorPixelFormat: MTLPixelFormat) -> Pipes? {
        // ── vertex descriptors ──
        let posVD = MTLVertexDescriptor()
        posVD.attributes[0].format = .float3; posVD.attributes[0].offset = 0; posVD.attributes[0].bufferIndex = 1
        posVD.layouts[1].stride = 24

        let meshVD = MTLVertexDescriptor()
        meshVD.attributes[0].format = .float3; meshVD.attributes[0].offset = 0; meshVD.attributes[0].bufferIndex = 1
        meshVD.attributes[1].format = .float3; meshVD.attributes[1].offset = 12; meshVD.attributes[1].bufferIndex = 1
        meshVD.attributes[2].format = .float3; meshVD.attributes[2].offset = 0; meshVD.attributes[2].bufferIndex = 2
        meshVD.attributes[3].format = .float; meshVD.attributes[3].offset = 12; meshVD.attributes[3].bufferIndex = 2
        meshVD.layouts[1].stride = 24
        meshVD.layouts[2].stride = 16

        let lineVD = MTLVertexDescriptor()
        lineVD.attributes[0].format = .float3; lineVD.attributes[0].offset = 0; lineVD.attributes[0].bufferIndex = 1
        lineVD.layouts[1].stride = 12

        // ── pipelines ──
        func make(_ label: String, vs: String, fs: String?, vd: MTLVertexDescriptor?, color: MTLPixelFormat?,
                  depth: Bool, samples: Int, blend: Bool = false) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.label = label
            guard let v = library.makeFunction(name: vs) else { print("MelonRenderer: missing function \(vs)"); return nil }
            d.vertexFunction = v
            if let fs {
                guard let f = library.makeFunction(name: fs) else { print("MelonRenderer: missing function \(fs)"); return nil }
                d.fragmentFunction = f
            }
            d.vertexDescriptor = vd
            if let color {
                d.colorAttachments[0].pixelFormat = color
                if blend {
                    let c = d.colorAttachments[0]!
                    c.isBlendingEnabled = true
                    c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
                    c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
                    c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
            }
            if depth { d.depthAttachmentPixelFormat = MelonRenderer.depthFormat }
            d.rasterSampleCount = samples
            do { return try device.makeRenderPipelineState(descriptor: d) }
            catch { print("MelonRenderer: pipeline \(label) failed: \(error)"); return nil }
        }
        let hdr = MelonRenderer.hdrFormat, ms = MelonRenderer.msaa
        guard let a = make("depth", vs: "depthVS", fs: nil, vd: posVD, color: nil, depth: true, samples: 1),
              let b = make("background", vs: "sceneVsFull", fs: "fsBackground", vd: nil, color: hdr, depth: true, samples: ms),
              let c = make("props", vs: "vsMesh", fs: "fsProps", vd: meshVD, color: hdr, depth: true, samples: ms),
              let d = make("back", vs: "backVS", fs: "backFS", vd: posVD, color: .r32Float, depth: true, samples: 1),
              let e = make("copy", vs: "mainVsFull", fs: "fsCopy", vd: nil, color: hdr, depth: true, samples: ms),
              let f = make("jelly", vs: "vsJelly", fs: "fsJelly", vd: meshVD, color: hdr, depth: true, samples: ms),
              let mt = make("matte", vs: "vsJelly", fs: "fsSoftMatte", vd: meshVD, color: hdr, depth: true, samples: ms),
              let ey = make("eyes", vs: "vsMesh", fs: "fsEyesMatte", vd: meshVD, color: hdr, depth: true, samples: ms),
              let mtb = MelonRenderer.makeBathVariant(device: device, library: library, vd: meshVD, mask: 15),
              let g = make("lines", vs: "vsLine", fs: "fsLine", vd: lineVD, color: hdr, depth: true, samples: ms, blend: true),
              let h = make("post", vs: "postVS", fs: "postFS", vd: nil, color: colorPixelFormat, depth: false, samples: 1)
        else { return nil }
        func makeGfx(_ label: String, fs: String, color: MTLPixelFormat, depth: Bool, samples: Int) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.label = label
            d.vertexFunction = library.makeFunction(name: "gfxFullVS"); d.fragmentFunction = library.makeFunction(name: fs)
            guard d.vertexFunction != nil, d.fragmentFunction != nil else { print("MelonRenderer: missing gfx function \(fs)"); return nil }
            d.colorAttachments[0].pixelFormat = color
            if depth { d.depthAttachmentPixelFormat = MelonRenderer.depthFormat }
            d.rasterSampleCount = samples
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let cb = makeGfx("room cache blit", fs: "gfxCacheFS", color: hdr, depth: true, samples: ms),
              let pr = makeGfx("present", fs: "gfxPresentFS", color: colorPixelFormat, depth: false, samples: 1)
        else { return nil }
        var spec: [Int: MTLRenderPipelineState] = [:]
        for fibre in [1, 0] {          // 1 = the app's default noise (the lattice texture), 0 = the exact ALU noise (-FibreLUT 0, tests)
            for (bl, td) in [(false, false), (true, false), (true, true)] {
                if let sp = makeMatteSpec(device: device, library: library, vd: meshVD, tier: 0, belly: bl, teddy: td, probe: 0, fibre: fibre) { spec[(bl ? 10 : 0) + (td ? 20 : 0) + 1000 * fibre] = sp }
            }
        }
        return MelonPipelines.Pipes(depth: a, background: b, props: c, back: d, copy: e, jelly: f, matte: mt, eyes: ey, matteBath: mtb, lines: g, post: h, cacheBlit: cb, present: pr, meshVD: meshVD, matteSpec: spec)
    }

    /// The matte body pipeline of fsSoftMatteFast: `tier` 0 = the locked maths (pixel-identical), 1...3 = the opt-in cheaper tiers; `belly` / `teddy`
    /// compile the lighter-front and Teddy ear / pom blocks in or out (a body whose BlueBelly mode is 0 needs neither); `probe` is the measurement mode.
    static func makeMatteSpec(device: MTLDevice, library: MTLLibrary, vd: MTLVertexDescriptor, tier: Int, belly: Bool, teddy: Bool, probe: Int, fibre: Int = 0) -> MTLRenderPipelineState? {
        let cv = MTLFunctionConstantValues()
        var t = Int32(tier), bl = belly, td = teddy, pr = Int32(probe)
        cv.setConstantValue(&t, type: .int, index: 0)
        cv.setConstantValue(&bl, type: .bool, index: 1)
        cv.setConstantValue(&td, type: .bool, index: 2)
        cv.setConstantValue(&pr, type: .int, index: 3)
        var fm = Int32(fibre)
        cv.setConstantValue(&fm, type: .int, index: 4)
        guard let fs = try? library.makeFunction(name: "fsSoftMatteFast", constantValues: cv), let vs = library.makeFunction(name: "vsJelly") else {
            print("MelonRenderer: fsSoftMatteFast tier \(tier) unavailable"); return nil
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = "matte fast \(tier)\(belly ? " belly" : "")\(teddy ? " teddy" : "")"
        d.vertexFunction = vs; d.fragmentFunction = fs
        d.vertexDescriptor = vd
        d.colorAttachments[0].pixelFormat = MelonRenderer.hdrFormat
        d.depthAttachmentPixelFormat = MelonRenderer.depthFormat
        d.rasterSampleCount = MelonRenderer.msaa
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { print("MelonRenderer: matte fast \(tier) pipeline failed"); return nil }
        return p
    }
}
