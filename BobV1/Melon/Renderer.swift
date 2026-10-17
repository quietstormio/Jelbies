//
//  Renderer.swift
//  Melon Jelly Metal renderer (port of renderer.js).
//
//  ShaderTypes layout sync: `MelonUniforms` below MUST match `struct Uniforms` in Shaders.metal
//  (5 x float4x4, then 14 x float4; 544 bytes; field order identical). The MSL side has a
//  static_assert on sizeof == 544, the Swift side checks MemoryLayout in MelonRenderer.init.
//  Vertex streams: buffer(1) dynamic pos+normal (stride 24), buffer(2) static rest+mat (stride 16),
//  buffer(0) uniforms. Fragment textures: scene pass 0 shadow / 1 height; jelly pass 0 sceneTex / 1 backTex;
//  post pass 0 hdr.
//

import Metal
import QuartzCore
import simd
import Dispatch

struct MelonUniforms {
    var viewProj = matrix_identity_float4x4
    var view = matrix_identity_float4x4
    var invViewProj = matrix_identity_float4x4
    var lightVP = matrix_identity_float4x4
    var topVP = matrix_identity_float4x4
    var camPos = SIMD4<Float>(repeating: 0)      // xyz, w = time
    var camFwd = SIMD4<Float>(repeating: 0)
    var keyDir = SIMD4<Float>(repeating: 0)      // xyz toward light, w = intensity
    var screen = SIMD4<Float>(repeating: 0)      // w, h, 1/w, 1/h
    var flesh = SIMD4<Float>(repeating: 0)
    var fleshDeep = SIMD4<Float>(repeating: 0)
    var pale = SIMD4<Float>(repeating: 0)
    var skin = SIMD4<Float>(repeating: 0)
    var stripe = SIMD4<Float>(repeating: 0)
    var seed = SIMD4<Float>(repeating: 0)
    var shape = SIMD4<Float>(repeating: 0)       // T, Ro, skinDepth, paleDepth
    var misc = SIMD4<Float>(repeating: 0)        // exposure, meshAlpha, floorY, 0
    var bg = SIMD4<Float>(repeating: 0)
    var shadowTint = SIMD4<Float>(repeating: 0)
}

final class MelonRenderer {
    static let msaa = 4
    static let hdrFormat = MTLPixelFormat.rgba16Float
    static let depthFormat = MTLPixelFormat.depth32Float

    let device: MTLDevice
    let queue: MTLCommandQueue
    let colorPixelFormat: MTLPixelFormat

    /// pos+normal per vertex (6 floats), shared memory, written by the CPU every frame.
    let dynPointer: UnsafeMutablePointer<Float>

    private let mesh: RenderMesh
    private let vertexCount: Int
    private let lineCount: Int
    private let dynBuf: MTLBuffer
    private let staticBuf: MTLBuffer
    private let indexBuf: MTLBuffer
    private let lineIdxBuf: MTLBuffer
    private let particleBuf: MTLBuffer
    private let particleBytes: Int
    private let uboBuf: MTLBuffer
    private let lightBuf: MTLBuffer
    private let topBuf: MTLBuffer
    private var uniforms = MelonUniforms()

    private let shadowSize = 1024
    private let topSize = 512
    private let shadowTex: MTLTexture
    private let topTex: MTLTexture

    private let pDepth: MTLRenderPipelineState
    private let pBackground: MTLRenderPipelineState
    private let pProps: MTLRenderPipelineState
    private let pBack: MTLRenderPipelineState
    private let pCopy: MTLRenderPipelineState
    private let pJelly: MTLRenderPipelineState
    private let pMatte: MTLRenderPipelineState
    private let pEyes: MTLRenderPipelineState
    /// Soft matte look (Bob / blush palette) instead of the glossy translucent jelly.
    private(set) var useMatte = false
    /// The living room (game screen). When set, it replaces the studio backdrop and Bob is drawn into the same pass.
    private(set) var room: RoomRenderer?
    /// 0...1: Bob's mouth (matte body shader). 0 = no mouth at all. The brain sets this each frame.
    var mouthOpen: Float = 0
    /// DEBUG/screenshot override: launch argument -MelonMouth <0...1>.
    private let forcedMouth: Float? = UserDefaults.standard.object(forKey: "MelonMouth") != nil ? Float(UserDefaults.standard.double(forKey: "MelonMouth")) : nil
    private let pLines: MTLRenderPipelineState
    private let pPost: MTLRenderPipelineState
    private let pCacheBlit: MTLRenderPipelineState
    private let pPresent: MTLRenderPipelineState

    private let dsLessWrite: MTLDepthStencilState
    private let dsAlwaysNoWrite: MTLDepthStencilState
    private let dsGreaterWrite: MTLDepthStencilState

    private var width = 0
    private var height = 0
    private var msScene: MTLTexture?
    private var msDepth: MTLTexture?
    private var sceneTex: MTLTexture?
    private var backTex: MTLTexture?
    private var backDepth: MTLTexture?
    private var msHdr: MTLTexture?
    private var hdrTex: MTLTexture?

    private let inflight = DispatchSemaphore(value: 1)
    /// GPU time per frame (from MTLCommandBuffer gpuStart/EndTime), accumulated off-thread; read via `takeGPUStats()`.
    private let gpuTimes = GPUTimeAccumulator()

    /// Returns (average GPU ms per frame, frames) since the last call, then resets. (0, 0) if none completed.
    func takeGPUStats() -> (avgMs: Double, frames: Int) { gpuTimes.take() }
    /// Last completed frame's GPU ms (feeds the adaptive render scaler).
    var lastGPUMs: Double { gpuTimes.lastMs }
    private var frameOwned = false

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat, mesh: RenderMesh, simEdges: [UInt32], particleCount: Int, game: Bool = false) {
        guard MemoryLayout<MelonUniforms>.size == 544, MemoryLayout<MelonUniforms>.stride == 544 else {
            print("MelonRenderer: MelonUniforms layout is \(MemoryLayout<MelonUniforms>.size) bytes, expected 544")
            return nil
        }
        guard let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else {
            print("MelonRenderer: no command queue / default library")
            return nil
        }
        self.device = device
        self.queue = queue
        self.colorPixelFormat = colorPixelFormat
        self.mesh = mesh
        let nV = mesh.vertexCount
        self.vertexCount = nV

        // ── buffers ──
        guard let dyn = device.makeBuffer(length: max(nV * 6 * 4, 16), options: .storageModeShared) else { return nil }
        dyn.label = "dynamic vertices"
        dynBuf = dyn
        dynPointer = dyn.contents().bindMemory(to: Float.self, capacity: max(nV * 6, 4))
        memset(dyn.contents(), 0, dyn.length)

        var st = [Float](repeating: 0, count: nV * 4)
        for i in 0..<nV {
            st[4 * i] = mesh.rest[3 * i]; st[4 * i + 1] = mesh.rest[3 * i + 1]; st[4 * i + 2] = mesh.rest[3 * i + 2]
            st[4 * i + 3] = mesh.mat[i]
        }
        // wave-arm capsules: the crinkle texture coordinate is the matching point on the REST arm cone (the position stream
        // holds their hidden shape), so the texture rides with the arm.
        if let cap = mesh.armCapsule {
            for (si, sigma) in [-1.0, 1.0].enumerated() {
                let pts = ArmCapsule.restStream(sigma: sigma)
                for (i, p) in pts.enumerated() {
                    let v = cap.firstVertex[si] + i
                    st[4 * v] = Float(p.x); st[4 * v + 1] = Float(p.y); st[4 * v + 2] = Float(p.z)
                }
                // the foot bean of the same side follows the arm capsule inside the block
                for (i, p) in FootBean.restStream(sigma: sigma).enumerated() {
                    let v = cap.beanFirst(side: si == 0 ? -1 : 1) + i
                    st[4 * v] = Float(p.x); st[4 * v + 1] = Float(p.y); st[4 * v + 2] = Float(p.z)
                }
            }
        }
        guard let sb = device.makeBuffer(bytes: st, length: max(st.count * 4, 16), options: .storageModeShared),
              let ib = device.makeBuffer(bytes: mesh.index, length: max(mesh.index.count * 4, 16), options: .storageModeShared)
        else { return nil }
        staticBuf = sb; indexBuf = ib
        lineCount = simEdges.count
        guard let lb = simEdges.isEmpty
                ? device.makeBuffer(length: 16, options: .storageModeShared)
                : device.makeBuffer(bytes: simEdges, length: simEdges.count * 4, options: .storageModeShared)
        else { return nil }
        lineIdxBuf = lb
        particleBytes = particleCount * 12
        guard let pb = device.makeBuffer(length: max(particleBytes, 16), options: .storageModeShared),
              let ub = device.makeBuffer(length: MemoryLayout<MelonUniforms>.stride, options: .storageModeShared),
              let lightB = device.makeBuffer(length: 64, options: .storageModeShared),
              let topB = device.makeBuffer(length: 64, options: .storageModeShared)
        else { return nil }
        particleBuf = pb; uboBuf = ub; lightBuf = lightB; topBuf = topB

        // ── fixed textures ──
        func depthMap(_ size: Int, _ label: String) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.depthFormat, width: size, height: size, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            let t = device.makeTexture(descriptor: d)
            t?.label = label
            return t
        }
        guard let sh = depthMap(shadowSize, "shadow map"), let tp = depthMap(topSize, "height map") else { return nil }
        shadowTex = sh; topTex = tp

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
            if depth { d.depthAttachmentPixelFormat = Self.depthFormat }
            d.rasterSampleCount = samples
            do { return try device.makeRenderPipelineState(descriptor: d) }
            catch { print("MelonRenderer: pipeline \(label) failed: \(error)"); return nil }
        }
        let hdr = Self.hdrFormat, ms = Self.msaa
        guard let a = make("depth", vs: "depthVS", fs: nil, vd: posVD, color: nil, depth: true, samples: 1),
              let b = make("background", vs: "sceneVsFull", fs: "fsBackground", vd: nil, color: hdr, depth: true, samples: ms),
              let c = make("props", vs: "vsMesh", fs: "fsProps", vd: meshVD, color: hdr, depth: true, samples: ms),
              let d = make("back", vs: "backVS", fs: "backFS", vd: posVD, color: .r32Float, depth: true, samples: 1),
              let e = make("copy", vs: "mainVsFull", fs: "fsCopy", vd: nil, color: hdr, depth: true, samples: ms),
              let f = make("jelly", vs: "vsJelly", fs: "fsJelly", vd: meshVD, color: hdr, depth: true, samples: ms),
              let mt = make("matte", vs: "vsJelly", fs: "fsSoftMatte", vd: meshVD, color: hdr, depth: true, samples: ms),
              let ey = make("eyes", vs: "vsMesh", fs: "fsEyesMatte", vd: meshVD, color: hdr, depth: true, samples: ms),
              let g = make("lines", vs: "vsLine", fs: "fsLine", vd: lineVD, color: hdr, depth: true, samples: ms, blend: true),
              let h = make("post", vs: "postVS", fs: "postFS", vd: nil, color: colorPixelFormat, depth: false, samples: 1)
        else { return nil }
        func makeGfx(_ label: String, fs: String, color: MTLPixelFormat, depth: Bool, samples: Int) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.label = label
            d.vertexFunction = library.makeFunction(name: "gfxFullVS"); d.fragmentFunction = library.makeFunction(name: fs)
            guard d.vertexFunction != nil, d.fragmentFunction != nil else { print("MelonRenderer: missing gfx function \(fs)"); return nil }
            d.colorAttachments[0].pixelFormat = color
            if depth { d.depthAttachmentPixelFormat = Self.depthFormat }
            d.rasterSampleCount = samples
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let cb = makeGfx("room cache blit", fs: "gfxCacheFS", color: hdr, depth: true, samples: ms),
              let pr = makeGfx("present", fs: "gfxPresentFS", color: colorPixelFormat, depth: false, samples: 1)
        else { return nil }
        pCacheBlit = cb; pPresent = pr
        pDepth = a; pBackground = b; pProps = c; pBack = d; pCopy = e; pJelly = f; pMatte = mt; pEyes = ey; pLines = g; pPost = h

        func ds(_ fn: MTLCompareFunction, _ write: Bool) -> MTLDepthStencilState? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = fn; d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)
        }
        guard let s1 = ds(.less, true), let s2 = ds(.always, false), let s3 = ds(.greater, true) else { return nil }
        dsLessWrite = s1; dsAlwaysNoWrite = s2; dsGreaterWrite = s3
        if game {
            room = RoomRenderer(device: device, library: library, colorFormat: Self.hdrFormat, depthFormat: Self.depthFormat, sampleCount: Self.msaa)
            if room == nil { print("MelonRenderer: room renderer failed; falling back to the studio backdrop") }
        }
    }

    // Not isolated: with default MainActor isolation Swift 6.2 makes deinit an isolated deinit (swift_task_deinitOnExecutor), which
    // aborts on the iOS 26.2 runtime ("pointer being freed was not allocated") when the last release is outside a task.
    nonisolated deinit {}

    // MARK: resize

    /// (Re)creates the screen-sized targets. No-op when the size is unchanged.
    func resize(width w: Int, height h: Int) {
        let w = max(1, w), h = max(1, h)
        if w == width && h == height { return }
        width = w; height = h
        targetRebuilds += 1
        func tex(_ fmt: MTLPixelFormat, samples: Int, usage: MTLTextureUsage, _ label: String) -> MTLTexture? {
            let d = MTLTextureDescriptor()
            d.pixelFormat = fmt; d.width = w; d.height = h
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = usage
            d.storageMode = .private
            let t = device.makeTexture(descriptor: d)
            t?.label = label
            return t
        }
        let rt: MTLTextureUsage = [.renderTarget]
        let rtr: MTLTextureUsage = [.renderTarget, .shaderRead]
        let ms = Self.msaa
        msScene = tex(Self.hdrFormat, samples: ms, usage: rt, "msScene")
        msDepth = tex(Self.depthFormat, samples: ms, usage: rt, "msDepth")
        sceneTex = tex(Self.hdrFormat, samples: 1, usage: rtr, "sceneTex")
        backTex = tex(.r32Float, samples: 1, usage: rtr, "backTex")
        backDepth = tex(Self.depthFormat, samples: 1, usage: rt, "backDepth")
        msHdr = tex(Self.hdrFormat, samples: ms, usage: rt, "msHdr")
        hdrTex = tex(Self.hdrFormat, samples: 1, usage: rtr, "hdrTex")
    }

    // MARK: per-frame inputs

    func setUniforms(camera: CameraState, light: LightState, palette: Palette, params: FrameParams, viewSize: SIMD2<Float>) {
        var u = MelonUniforms()
        u.viewProj = camera.viewProj; u.view = camera.view; u.invViewProj = camera.invViewProj
        u.lightVP = light.lightVP; u.topVP = light.topVP
        u.camPos = SIMD4(camera.pos, params.time)
        u.camFwd = SIMD4(camera.fwd, 0)
        u.keyDir = SIMD4(light.dir, light.intensity)
        u.screen = SIMD4(viewSize.x, viewSize.y, 1 / viewSize.x, 1 / viewSize.y)
        useMatte = palette.matte
        u.flesh = SIMD4(palette.flesh, 1)
        u.fleshDeep = SIMD4(palette.fleshDeep, 1)
        u.pale = SIMD4(palette.pale, 1)
        u.skin = SIMD4(palette.skin, 1)
        u.stripe = SIMD4(palette.stripe, 1)
        u.seed = SIMD4(palette.seed, 1)
        u.shape = params.shape
        u.shape = SIMD4(palette.extra, palette.bodyHeight)   // white-tone fleshDeep (shape is unused by the Bob shader)
        u.misc = SIMD4(params.exposure, params.meshAlpha, 0, palette.marking)
        u.bg = SIMD4(params.bg, 1)
        u.shadowTint = SIMD4(palette.shadowTint, palette.matte ? 2 : 1)
        uniforms = u
        // Writes target shared buffers the GPU may still be reading from the previous frame; call beginFrame() first.
        waitIfNeeded()
        uboBuf.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<MelonUniforms>.stride)
        lightBuf.contents().copyMemory(from: &uniforms.lightVP, byteCount: 64)
        topBuf.contents().copyMemory(from: &uniforms.topVP, byteCount: 64)
    }

    /// `p` points at particleCount * 3 floats.
    func uploadParticles(_ p: UnsafePointer<Float>) {
        waitIfNeeded()
        memcpy(particleBuf.contents(), p, particleBytes)
    }

    /// Writes (or, with `values == nil`, restores the baked) mat channel of the given render vertices in the static stream.
    /// Call after `beginFrame()` (the buffer is shared with the GPU).
    func writeMat(_ vertices: [Int32], values: [Float]?) {
        waitIfNeeded()
        let p = staticBuf.contents().bindMemory(to: Float.self, capacity: vertexCount * 4)
        if let values {
            for (k, v) in vertices.enumerated() { p[4 * Int(v) + 3] = values[k] }
        } else {
            for v in vertices { p[4 * Int(v) + 3] = mesh.mat[Int(v)] }
        }
    }

    /// Blocks until the previous frame's GPU work finished, so `dynPointer`, uniforms and particles are safe to
    /// write. Call once per frame before writing `dynPointer`. setUniforms / uploadParticles / draw call it
    /// implicitly if you did not (the dynPointer writes then race with the GPU).
    func beginFrame() { waitIfNeeded() }

    private func waitIfNeeded() {
        if frameOwned { return }
        _ = inflight.wait(timeout: .now() + 1.0)
        frameOwned = true
    }

    // MARK: draw

    func draw(drawable: CAMetalDrawable, showMesh: Bool) {
        guard var cmd = queue.makeCommandBuffer() else { releaseFrame(); return }
        cmd.label = "melon frame"
        guard encodeFrame(&cmd, target: drawable.texture, showMesh: showMesh) else { releaseFrame(); return }
        cmd.present(drawable)
        commit(cmd)
    }

    /// Offscreen variant (tests): renders to `target` (must be colorPixelFormat) and commits `cmd`.
    func draw(to target: MTLTexture, commandBuffer: MTLCommandBuffer, showMesh: Bool) {
        var cmd = commandBuffer
        guard encodeFrame(&cmd, target: target, showMesh: showMesh) else { releaseFrame(); return }
        commit(cmd)
    }

    private func releaseFrame() {
        if frameOwned { frameOwned = false; inflight.signal() }
    }

    private func commit(_ cmd: MTLCommandBuffer) {
        let sem = inflight
        let gt = gpuTimes
        let box = frameBox, pt = passTimes
        frameBox = nil
        cmd.addCompletedHandler { c in
            let t = c.gpuEndTime - c.gpuStartTime
            if let box { pt.add("post", t); gt.add(box.add(t)) } else { gt.add(t) }
            sem.signal()
        }
        frameOwned = false
        cmd.commit()
    }

    // MARK: per-pass GPU timing (launch argument -PerfPasses 1; separate command buffers per pass, same pixels)

    /// Diagnostics only: shadow / height / room / Bob / post are committed as separate command buffers so each gets its own gpuStart/EndTime.
    let perfPasses = UserDefaults.standard.bool(forKey: "PerfPasses")
    private let passTimes = PassTimeAccumulator()
    private var frameBox: FrameTimeBox?
    /// "label=ms ..." for the passes since the last call (empty unless -PerfPasses 1).
    func takePassStats() -> String { passTimes.takeDescription() }
    // MARK: static-room cache (GfxSavings.swift)

    /// Cache the static room's resolved colour and re-shade only the footprint of Bob / his shadow / the tray. The stage sets this from
    /// `-RoomCache`; the offscreen `draw(to:)` path used by the golden tests only uses it when a test turns it on.
    var roomCacheEnabled = false
    private var roomCacheState = RoomCacheState()
    private var roomCacheTex: MTLTexture?
    private(set) var lastCacheAction = RoomCacheAction.bypass(.disabled)
    /// Share of the viewport re-shaded on the last frame (1 = the whole room).
    private(set) var lastFootprintShare: Float = 1
    private(set) var lastFootprintRect: MTLScissorRect?
    /// Room pixels shaded vs what the old path would shade (summed over frames since the last `resetRoomCacheCounters`).
    private(set) var roomPixelsShaded: Double = 0, roomPixelsBaseline: Double = 0
    var roomCacheSummary: String { roomCacheState.summary }
    var roomCacheHitRate: Double { roomCacheState.hitRate }
    func resetRoomCacheCounters() { roomCacheState.resetCounters(); roomPixelsShaded = 0; roomPixelsBaseline = 0 }
    /// Test hook: forget the cache.
    func invalidateRoomCache() { roomCacheState.invalidate() }

    /// World AABB of the vertices Bob is drawn with this frame (CPU copy in the shared dynamic buffer; call after waitIfNeeded).
    private func bobBounds() -> (lo: SIMD3<Float>, hi: SIMD3<Float>) {
        var x0 = Float.infinity, y0 = Float.infinity, z0 = Float.infinity, x1 = -Float.infinity, y1 = -Float.infinity, z1 = -Float.infinity
        dynPointer.withMemoryRebound(to: Float.self, capacity: vertexCount * 6) { p in
            var i = 0
            let n = vertexCount * 6
            while i < n {
                let x = p[i], y = p[i + 1], z = p[i + 2]
                if x < x0 { x0 = x }; if x > x1 { x1 = x }
                if y < y0 { y0 = y }; if y > y1 { y1 = y }
                if z < z0 { z0 = z }; if z > z1 { z1 = z }
                i += 6
            }
        }
        return (SIMD3(x0, y0, z0), SIMD3(x1, y1, z1))
    }

    // MARK: MetalFX spatial upscaling (GfxUpscaler.swift)

    /// When on and the target (drawable) is larger than the render size set by `resize`, post renders at render size and MetalFX upscales
    /// to the target. Off: the old path (the OS scales a smaller drawable). `-MetalFX 1`; never on in the simulator (no MetalFX there).
    var metalFXEnabled = false
    private var upscaler: GfxUpscaler?
    private(set) var upscaledFrames = 0
    /// "off" / "on 804x1748->1206x2622" / "unavailable (simulator)" for the env log.
    var metalFXState: String {
        if !metalFXEnabled { return "off" }
        if !GfxUpscaler.compiledIn { return "unavailable (no MetalFX in this SDK / simulator)" }
        if !GfxUpscaler.supported(device) { return "unavailable (device unsupported)" }
        if let u = upscaler { return "on \(u.inW)x\(u.inH)->\(u.outW)x\(u.outH), \(upscaledFrames) frames" }
        return "on (native size, not scaling)"
    }

    /// Render-target (re)creations since launch: a steady value while idle / entering focus means no per-frame target churn.
    private(set) var targetRebuilds = 0

    /// Ends the current command buffer (recording `label`'s GPU time) and continues in a fresh one. No-op unless perfPasses.
    private func split(_ cmd: inout MTLCommandBuffer, _ label: String) {
        guard perfPasses, let next = queue.makeCommandBuffer() else { return }
        let box = frameBox ?? FrameTimeBox()
        frameBox = box
        let pt = passTimes
        cmd.addCompletedHandler { c in
            let t = c.gpuEndTime - c.gpuStartTime
            pt.add(label, t); _ = box.add(t)
        }
        cmd.commit()
        cmd = next
    }

    private func encodeFrame(_ cmd: inout MTLCommandBuffer, target: MTLTexture, showMesh: Bool) -> Bool {
        guard let msScene, let msDepth, let sceneTex, let backTex, let backDepth, let msHdr, let hdrTex else { return false }
        waitIfNeeded()
        // mouthOpen rides in `stripe.w` (byte 460 of MelonUniforms); written here so it is always current for this frame.
        uboBuf.contents().storeBytes(of: min(max(forcedMouth ?? mouthOpen, 0), 1), toByteOffset: 460, as: Float.self)
        let m = mesh
        let bodyAndSeeds = m.body.count + m.seeds.count
        let tri = MTLPrimitiveType.triangle

        // shadow map + top-down height map
        for (tex, mbuf, label) in [(shadowTex, lightBuf, "shadow"), (topTex, topBuf, "height")] {
            let rp = MTLRenderPassDescriptor()
            rp.depthAttachment.texture = tex
            rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 1
            rp.depthAttachment.storeAction = .store
            guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
            e.label = label
            e.setRenderPipelineState(pDepth)
            e.setDepthStencilState(dsLessWrite)
            e.setCullMode(.none)
            e.setFrontFacing(.counterClockwise)
            e.setDepthBias(2, slopeScale: 2, clamp: 0)
            e.setVertexBuffer(mbuf, offset: 0, index: 0)
            e.setVertexBuffer(dynBuf, offset: 0, index: 1)
            e.drawIndexedPrimitives(type: tri, indexCount: bodyAndSeeds, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: 0)
            e.endEncoding()
            split(&cmd, label)
        }

        // Game: the room and Bob share one MSAA pass that resolves straight to hdrTex (matte Bob needs no scene copy / back faces).
        if let room {
            room.fog = SIMD3(14, 32, 0.3)
            room.keyDir = SIMD3(uniforms.keyDir.x, uniforms.keyDir.y, uniforms.keyDir.z)
            let camPos3 = SIMD3<Float>(uniforms.camPos.x, uniforms.camPos.y, uniforms.camPos.z)
            let fullPx = Double(width * height)

            // Room cache: decide before the main pass (a build is its own pass, first).
            var action = RoomCacheAction.bypass(.disabled)
            var scissor: MTLScissorRect?
            if roomCacheEnabled {
                var (lo, hi) = bobBounds()
                if let d = room.diningBounds { lo = simd_min(lo, d.lo); hi = simd_max(hi, d.hi) }
                let rect = RoomFootprint.rect(min: lo, max: hi, shadowDir: GameCamera.shadowDir, viewProj: uniforms.viewProj, width: width, height: height)
                let share = RoomFootprint.share(rect, width: width, height: height)
                var key = RoomCacheKey()
                key.viewProj = uniforms.viewProj; key.camPos = camPos3; key.width = width; key.height = height
                key.themeTint = room.theme.tint; key.propsVersion = room.staticVersion
                key.keyDir = room.keyDir; key.keyIntensity = room.keyIntensity; key.fog = room.fog
                action = roomCacheState.frame(key: key, footprint: share, enabled: true)
                if action == .build {
                    if roomCacheTex == nil || roomCacheTex!.width != width || roomCacheTex!.height != height {
                        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdrFormat, width: width, height: height, mipmapped: false)
                        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
                        roomCacheTex = device.makeTexture(descriptor: d)
                        roomCacheTex?.label = "room cache"
                    }
                    if let cacheTex = roomCacheTex {
                        // the same room render the old path does, minus Bob-dependent shading (no shadow map / contact AO: camPos.w = 0)
                        let crp = MTLRenderPassDescriptor()
                        let cca = crp.colorAttachments[0]!
                        cca.texture = msScene; cca.resolveTexture = cacheTex
                        cca.loadAction = .clear; cca.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                        cca.storeAction = .multisampleResolve
                        crp.depthAttachment.texture = msDepth
                        crp.depthAttachment.loadAction = .clear; crp.depthAttachment.clearDepth = 1
                        crp.depthAttachment.storeAction = .dontCare
                        guard let ce = cmd.makeRenderCommandEncoder(descriptor: crp) else { return false }
                        ce.label = "room cache build"
                        room.encode(ce, viewProj: uniforms.viewProj, camPos: camPos3, lightViewProj: nil, shadowTex: nil, parts: .staticOnly)
                        ce.endEncoding()
                        split(&cmd, "roomcache")
                        roomPixelsShaded += fullPx      // the one-off build cost
                    } else { action = .bypass(.disabled) }
                }
                if action == .use || action == .build { scissor = MTLScissorRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h) }
                lastFootprintShare = (action == .use || action == .build) ? share : 1
                lastFootprintRect = scissor
            }
            lastCacheAction = action
            roomPixelsBaseline += fullPx

            let rp = MTLRenderPassDescriptor()
            let ca = rp.colorAttachments[0]!
            ca.texture = msScene; ca.resolveTexture = hdrTex
            ca.loadAction = .clear; ca.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            ca.storeAction = perfPasses ? .storeAndMultisampleResolve : .multisampleResolve
            rp.depthAttachment.texture = msDepth
            rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 1
            rp.depthAttachment.storeAction = perfPasses ? .store : .dontCare
            guard var e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
            e.label = perfPasses ? "room" : "room + bob"
            if let sc = scissor, let cacheTex = roomCacheTex {
                roomPixelsShaded += Double(sc.width * sc.height)
                // Cached colour only OUTSIDE the footprint (four scissored strips), so the pixels inside see exactly the old draw sequence
                // (a full-screen underlay changed the resolve of a few of Bob's edge pixels by 1-3 levels).
                e.pushDebugGroup("room cache")
                e.setRenderPipelineState(pCacheBlit)
                e.setDepthStencilState(dsAlwaysNoWrite)
                e.setCullMode(.none)
                e.setFragmentTexture(cacheTex, index: 0)
                let strips = [MTLScissorRect(x: 0, y: 0, width: width, height: sc.y),
                              MTLScissorRect(x: 0, y: sc.y + sc.height, width: width, height: height - sc.y - sc.height),
                              MTLScissorRect(x: 0, y: sc.y, width: sc.x, height: sc.height),
                              MTLScissorRect(x: sc.x + sc.width, y: sc.y, width: width - sc.x - sc.width, height: sc.height)]
                for r in strips where r.width > 0 && r.height > 0 {
                    e.setScissorRect(r)
                    e.drawPrimitives(type: tri, vertexStart: 0, vertexCount: 3)
                }
                e.popDebugGroup()
                e.setScissorRect(sc)
                room.encode(e, viewProj: uniforms.viewProj, camPos: camPos3, lightViewProj: uniforms.lightVP, shadowTex: shadowTex,
                            topViewProj: uniforms.topVP, heightTex: topTex, parts: .staticOnly)
                room.encode(e, viewProj: uniforms.viewProj, camPos: camPos3, lightViewProj: uniforms.lightVP, shadowTex: shadowTex,
                            topViewProj: uniforms.topVP, heightTex: topTex, parts: .diningOnly)
            } else {
                roomPixelsShaded += fullPx
                room.encode(e, viewProj: uniforms.viewProj, camPos: camPos3, lightViewProj: uniforms.lightVP, shadowTex: shadowTex,
                            topViewProj: uniforms.topVP, heightTex: topTex)
            }
            if perfPasses {      // diagnostics: Bob in his own pass / command buffer (load the room's MSAA colour + depth back)
                e.endEncoding()
                split(&cmd, "room")
                ca.loadAction = .load; ca.storeAction = .multisampleResolve
                rp.depthAttachment.loadAction = .load; rp.depthAttachment.storeAction = .dontCare
                guard let e2 = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
                e2.label = "bob"
                if let sc = scissor { e2.setScissorRect(sc) }
                e = e2
            }
            e.setFrontFacing(.counterClockwise)
            e.setVertexBuffer(uboBuf, offset: 0, index: 0)
            e.setFragmentBuffer(uboBuf, offset: 0, index: 0)
            e.setDepthStencilState(dsLessWrite)
            e.setCullMode(.back)
            e.setVertexBuffer(dynBuf, offset: 0, index: 1)
            e.setVertexBuffer(staticBuf, offset: 0, index: 2)
            e.setRenderPipelineState(pMatte)
            e.drawIndexedPrimitives(type: tri, indexCount: m.body.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.body.first * 4)
            if m.seeds.count > 0 {
                e.setRenderPipelineState(pEyes)
                e.drawIndexedPrimitives(type: tri, indexCount: m.seeds.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.seeds.first * 4)
            }
            // translucent room pieces (dining puffs, contact shadows) blend over Bob; sets its own state (not part of the body path)
            room.encodeBlended(e, viewProj: uniforms.viewProj, camPos: SIMD3(uniforms.camPos.x, uniforms.camPos.y, uniforms.camPos.z), lightViewProj: uniforms.lightVP,
                               shadowTex: shadowTex, topViewProj: uniforms.topVP, heightTex: topTex)
            e.endEncoding()
            split(&cmd, "bob")
            encodePostOrUpscale(cmd, target: target, hdrTex: hdrTex)
            return true
        }

        // scene: floor + seeds + bubbles (MSAA, resolved to sceneTex)
        do {
            let rp = MTLRenderPassDescriptor()
            let ca = rp.colorAttachments[0]!
            ca.texture = msScene; ca.resolveTexture = sceneTex
            ca.loadAction = .clear; ca.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1000)
            ca.storeAction = .multisampleResolve
            rp.depthAttachment.texture = msDepth
            rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 1
            rp.depthAttachment.storeAction = .store
            guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
            e.label = "scene"
            e.setFrontFacing(.counterClockwise)
            e.setVertexBuffer(uboBuf, offset: 0, index: 0)
            e.setFragmentBuffer(uboBuf, offset: 0, index: 0)
            e.setFragmentTexture(shadowTex, index: 0)
            e.setFragmentTexture(topTex, index: 1)
            e.setRenderPipelineState(pBackground)
            e.setDepthStencilState(dsAlwaysNoWrite)
            e.setCullMode(.none)
            e.drawPrimitives(type: tri, vertexStart: 0, vertexCount: 3)
            e.setRenderPipelineState(pProps)
            e.setDepthStencilState(dsLessWrite)
            e.setCullMode(.back)
            e.setVertexBuffer(dynBuf, offset: 0, index: 1)
            e.setVertexBuffer(staticBuf, offset: 0, index: 2)
            if m.seeds.count > 0 && !useMatte { e.drawIndexedPrimitives(type: tri, indexCount: m.seeds.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.seeds.first * 4) }
            if m.bubbles.count > 0 { e.drawIndexedPrimitives(type: tri, indexCount: m.bubbles.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.bubbles.first * 4) }
            e.endEncoding()
        }

        // farthest back-face depth
        do {
            let rp = MTLRenderPassDescriptor()
            let ca = rp.colorAttachments[0]!
            ca.texture = backTex; ca.loadAction = .clear; ca.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            ca.storeAction = .store
            rp.depthAttachment.texture = backDepth
            rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 0
            rp.depthAttachment.storeAction = .dontCare
            guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
            e.label = "back faces"
            e.setRenderPipelineState(pBack)
            e.setDepthStencilState(dsGreaterWrite)
            e.setFrontFacing(.counterClockwise)
            e.setCullMode(.front)
            e.setVertexBuffer(uboBuf, offset: 0, index: 0)
            e.setFragmentBuffer(uboBuf, offset: 0, index: 0)
            e.setVertexBuffer(dynBuf, offset: 0, index: 1)
            e.drawIndexedPrimitives(type: tri, indexCount: m.body.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.body.first * 4)
            e.endEncoding()
        }

        // jelly (+ optional mesh overlay), depth loaded from the scene pass
        do {
            let rp = MTLRenderPassDescriptor()
            let ca = rp.colorAttachments[0]!
            ca.texture = msHdr; ca.resolveTexture = hdrTex
            ca.loadAction = .clear; ca.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            ca.storeAction = .multisampleResolve
            rp.depthAttachment.texture = msDepth
            rp.depthAttachment.loadAction = .load
            rp.depthAttachment.storeAction = .dontCare
            guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
            e.label = "jelly"
            e.setFrontFacing(.counterClockwise)
            e.setVertexBuffer(uboBuf, offset: 0, index: 0)
            e.setFragmentBuffer(uboBuf, offset: 0, index: 0)
            e.setFragmentTexture(sceneTex, index: 0)
            e.setFragmentTexture(backTex, index: 1)
            e.setRenderPipelineState(pCopy)
            e.setDepthStencilState(dsAlwaysNoWrite)
            e.setCullMode(.none)
            e.drawPrimitives(type: tri, vertexStart: 0, vertexCount: 3)
            e.setRenderPipelineState(useMatte ? pMatte : pJelly)
            e.setDepthStencilState(dsLessWrite)
            e.setCullMode(.back)
            e.setVertexBuffer(dynBuf, offset: 0, index: 1)
            e.setVertexBuffer(staticBuf, offset: 0, index: 2)
            e.drawIndexedPrimitives(type: tri, indexCount: m.body.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.body.first * 4)
            if useMatte && m.seeds.count > 0 {
                e.setRenderPipelineState(pEyes)
                e.drawIndexedPrimitives(type: tri, indexCount: m.seeds.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.seeds.first * 4)
            }
            if showMesh && lineCount > 0 {
                e.setRenderPipelineState(pLines)
                e.setDepthStencilState(dsAlwaysNoWrite)
                e.setCullMode(.none)
                e.setVertexBuffer(particleBuf, offset: 0, index: 1)
                e.drawIndexedPrimitives(type: .line, indexCount: lineCount, indexType: .uint32, indexBuffer: lineIdxBuf, indexBufferOffset: 0)
            }
            e.endEncoding()
        }

        encodePostOrUpscale(cmd, target: target, hdrTex: hdrTex)
        return true
    }

    /// Post (tone map) straight into `target`, or - with MetalFX on and a bigger target - into a render-size texture that is upscaled and presented.
    private func encodePostOrUpscale(_ cmd: MTLCommandBuffer, target: MTLTexture, hdrTex: MTLTexture) {
        guard metalFXEnabled, GfxUpscaler.compiledIn, target.width > width || target.height > height else {
            encodePost(cmd, target: target, hdrTex: hdrTex); return
        }
        if upscaler == nil || upscaler!.inW != width || upscaler!.inH != height || upscaler!.outW != target.width || upscaler!.outH != target.height {
            upscaler = GfxUpscaler.make(device: device, format: target.pixelFormat, inW: width, inH: height, outW: target.width, outH: target.height)
            targetRebuilds += 1
        }
        guard let up = upscaler else { encodePost(cmd, target: target, hdrTex: hdrTex); return }
        encodePost(cmd, target: up.input, hdrTex: hdrTex)
        up.encode(cmd)
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return }
        e.label = "metalfx present"
        e.setRenderPipelineState(pPresent)
        e.setFragmentTexture(up.output, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
        upscaledFrames += 1
    }

    private func encodePost(_ cmd: MTLCommandBuffer, target: MTLTexture, hdrTex: MTLTexture) {
        // tone map
        do {
            let rp = MTLRenderPassDescriptor()
            let ca = rp.colorAttachments[0]!
            ca.texture = target; ca.loadAction = .clear; ca.clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
            ca.storeAction = .store
            guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return }
            e.label = "post"
            e.setRenderPipelineState(pPost)
            e.setFragmentBuffer(uboBuf, offset: 0, index: 0)
            e.setFragmentTexture(hdrTex, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }
    }
}

/// Sums the GPU time of one frame's command buffers when the frame is split into passes (-PerfPasses 1).
nonisolated final class FrameTimeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0.0
    func add(_ t: Double) -> Double { lock.lock(); defer { lock.unlock() }; total += t; return total }
}

/// Per-pass GPU time (ms) since the last read, keyed by pass label.
nonisolated final class PassTimeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var sums: [String: (Double, Int)] = [:]
    func add(_ label: String, _ seconds: Double) {
        lock.lock(); let s = sums[label] ?? (0, 0); sums[label] = (s.0 + seconds, s.1 + 1); lock.unlock()
    }
    func takeDescription() -> String {
        lock.lock(); defer { lock.unlock() }
        let order = ["shadow", "height", "roomcache", "room", "bob", "post"]
        let out = order.compactMap { k in sums[k].map { String(format: "%@ %.2f", k, $0.0 / Double(max($0.1, 1)) * 1000) } }
        sums = [:]
        return out.joined(separator: ", ")
    }
}

/// Thread-safe sum of GPU frame times (written from the Metal completion handler, read on the main thread).
nonisolated final class GPUTimeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0.0
    private var count = 0
    func add(_ seconds: Double) {
        guard seconds > 0 else { return }
        lock.lock(); total += seconds; count += 1; lastSeconds = seconds; lock.unlock()
    }
    private var lastSeconds = 0.0
    /// Most recent completed frame's GPU time in ms (0 until one completes).
    var lastMs: Double { lock.lock(); defer { lock.unlock() }; return lastSeconds * 1000 }
    func take() -> (avgMs: Double, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        let r = count > 0 ? (total / Double(count) * 1000, count) : (0, 0)
        total = 0; count = 0
        return r
    }
}
