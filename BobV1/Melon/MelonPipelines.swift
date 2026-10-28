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
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var libraries: [ObjectIdentifier: MTLLibrary] = [:]
    nonisolated(unsafe) private static var sets: [String: Pipes] = [:]

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
        return MelonPipelines.Pipes(depth: a, background: b, props: c, back: d, copy: e, jelly: f, matte: mt, eyes: ey, matteBath: mtb, lines: g, post: h, cacheBlit: cb, present: pr, meshVD: meshVD)
    }
}
