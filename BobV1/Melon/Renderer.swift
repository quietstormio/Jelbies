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
        guard let cmd = queue.makeCommandBuffer() else { releaseFrame(); return }
        cmd.label = "melon frame"
        guard encodeFrame(cmd, target: drawable.texture, showMesh: showMesh) else { releaseFrame(); return }
        cmd.present(drawable)
        commit(cmd)
    }

    /// Offscreen variant (tests): renders to `target` (must be colorPixelFormat) and commits `cmd`.
    func draw(to target: MTLTexture, commandBuffer cmd: MTLCommandBuffer, showMesh: Bool) {
        guard encodeFrame(cmd, target: target, showMesh: showMesh) else { releaseFrame(); return }
        commit(cmd)
    }

    private func releaseFrame() {
        if frameOwned { frameOwned = false; inflight.signal() }
    }

    private func commit(_ cmd: MTLCommandBuffer) {
        let sem = inflight
        let gt = gpuTimes
        cmd.addCompletedHandler { c in
            gt.add(c.gpuEndTime - c.gpuStartTime)
            sem.signal()
        }
        frameOwned = false
        cmd.commit()
    }

    private func encodeFrame(_ cmd: MTLCommandBuffer, target: MTLTexture, showMesh: Bool) -> Bool {
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
        }

        // Game: the room and Bob share one MSAA pass that resolves straight to hdrTex (matte Bob needs no scene copy / back faces).
        if let room {
            let rp = MTLRenderPassDescriptor()
            let ca = rp.colorAttachments[0]!
            ca.texture = msScene; ca.resolveTexture = hdrTex
            ca.loadAction = .clear; ca.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            ca.storeAction = .multisampleResolve
            rp.depthAttachment.texture = msDepth
            rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 1
            rp.depthAttachment.storeAction = .dontCare
            guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
            e.label = "room + bob"
            room.fog = SIMD3(14, 32, 0.3)
            room.keyDir = SIMD3(uniforms.keyDir.x, uniforms.keyDir.y, uniforms.keyDir.z)
            room.encode(e, viewProj: uniforms.viewProj, camPos: SIMD3(uniforms.camPos.x, uniforms.camPos.y, uniforms.camPos.z), lightViewProj: uniforms.lightVP, shadowTex: shadowTex,
                        topViewProj: uniforms.topVP, heightTex: topTex)
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
            encodePost(cmd, target: target, hdrTex: hdrTex)
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

        encodePost(cmd, target: target, hdrTex: hdrTex)
        return true
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

/// Thread-safe sum of GPU frame times (written from the Metal completion handler, read on the main thread).
nonisolated final class GPUTimeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0.0
    private var count = 0
    func add(_ seconds: Double) {
        guard seconds > 0 else { return }
        lock.lock(); total += seconds; count += 1; lock.unlock()
    }
    func take() -> (avgMs: Double, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        let r = count > 0 ? (total / Double(count) * 1000, count) : (0, 0)
        total = 0; count = 0
        return r
    }
}
