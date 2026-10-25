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

/// Mirrors `BathParams` in BathShaders.metal (fragment buffer 3 of the bath body shader): 146 float4 = 2336 bytes.
/// `MelonUniforms` stays 544 bytes: `struct Uniforms` is part of the locked base body (BaseBodyLock), so the bath controls ride here.
struct MelonBathParams {
    var a = SIMD4<Float>(repeating: 0)          // wet, sparkle, foamOn, dirt
    var centre = SIMD4<Float>(repeating: 0)     // body centre in the rest frame
    var foam: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var soot: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    static let sootOffset = 1184
    static let foamOffset = 32
}

/// One Jelly's GPU state: its skinned vertex stream, its static stream (the wave-arm mat channel is written per body), its own copy of the
/// uniforms (palette and mouth differ per body; the rest is identical) and its bath body-shader parameters (dirt / soot / shine / suds).
final class BodySlot {
    /// Frames in flight: every CPU-written buffer exists `ring` times so the CPU fills frame n+1 while the GPU reads frame n
    /// (Apple, "Synchronizing CPU and GPU work": triple buffering). `MelonRenderer.inflight` has the same count.
    static let ring = 3
    private let dynBufs: [MTLBuffer]
    private let staticBufs: [MTLBuffer]
    private let uboBufs: [MTLBuffer]
    private let bathParamsBufs: [MTLBuffer]
    /// Which copy this frame writes and draws (set by the renderer when it acquires a frame).
    var ring = 0
    var dynBuf: MTLBuffer { dynBufs[ring] }
    var dynPointer: UnsafeMutablePointer<Float> { dynBufs[ring].contents().bindMemory(to: Float.self, capacity: dynFloats) }
    var staticBuf: MTLBuffer { staticBufs[ring] }
    var uboBuf: MTLBuffer { uboBufs[ring] }
    var bathParamsBuf: MTLBuffer { bathParamsBufs[ring] }
    private let dynFloats: Int
    /// CPU master of the static stream (rest xyz + mat); `writeMat` edits it and the copies catch up when their frame comes round.
    var staticMaster: [Float]
    private var staticGen = 1
    private var staticBufGen: [Int]
    /// Called when a frame is acquired on copy `ring`: brings its static stream up to date with the master if `writeMat` changed it.
    func syncStatic() {
        guard staticBufGen[ring] != staticGen else { return }
        staticMaster.withUnsafeBytes { memcpy(staticBufs[ring].contents(), $0.baseAddress!, $0.count) }
        staticBufGen[ring] = staticGen
    }
    /// Marks the master changed (after editing `staticMaster`); the current copy is written through at once.
    func staticChanged() { staticGen += 1; syncStatic() }
    /// 0...1 mouth opening (uniform byte 460).
    var mouthOpen: Float = 0
    /// 0...1 blush (uniform byte 476, `seed.w`, which no shader reads for the body): a soft pink cheek tint, 0 = none (pixel-identical).
    var blush: Float = 0
    /// Not drawn this frame (for example the bath close-up shows Bob alone).
    var hidden = false
    /// This body's colours; nil = the palette the renderer-wide `setUniforms` was given.
    var palette: Palette?
    var bathLook: BathLook = .dry {
        didSet { foamAny = bathLook.foam.contains { $0 > 0.01 }; sootAny = bathLook.dirt > 0.001 || bathLook.soot.contains { $0 > 0.004 } }
    }
    var foamAny = false
    var sootAny = false
    /// The Circuit jersey this body wears (Wear/GfxJersey.metal); nil = the locked body shader.
    var jersey: WearTeam?

    init?(device: MTLDevice, vertexCount nV: Int, staticData st: [Float], label: String) {
        var dyns: [MTLBuffer] = [], sbs: [MTLBuffer] = [], ubs: [MTLBuffer] = [], bpbs: [MTLBuffer] = []
        for k in 0..<Self.ring {
            guard let dyn = device.makeBuffer(length: max(nV * 6 * 4, 16), options: .storageModeShared),
                  let sb = device.makeBuffer(bytes: st, length: max(st.count * 4, 16), options: .storageModeShared),
                  let ub = device.makeBuffer(length: MemoryLayout<MelonUniforms>.stride, options: .storageModeShared),
                  let bpb = device.makeBuffer(length: MemoryLayout<MelonBathParams>.stride, options: .storageModeShared) else { return nil }
            dyn.label = "dynamic vertices" + label + " #\(k)"
            memset(dyn.contents(), 0, dyn.length)
            memset(bpb.contents(), 0, bpb.length)
            memset(ub.contents(), 0, ub.length)
            dyns.append(dyn); sbs.append(sb); ubs.append(ub); bpbs.append(bpb)
        }
        dynBufs = dyns; staticBufs = sbs; uboBufs = ubs; bathParamsBufs = bpbs
        dynFloats = max(nV * 6, 4)
        staticMaster = st
        staticBufGen = [Int](repeating: 1, count: Self.ring)
    }
    nonisolated deinit {}
}

final class MelonRenderer {
    static let msaa = 4
    static let hdrFormat = MTLPixelFormat.rgba16Float
    static let depthFormat = MTLPixelFormat.depth32Float

    let device: MTLDevice
    let queue: MTLCommandQueue
    let colorPixelFormat: MTLPixelFormat

    /// pos+normal per vertex (6 floats), shared memory, written by the CPU every frame. Body 0 (Bob); `dynPointer(body:)` for the others.
    /// Writing acquires this frame's buffer copy (`beginFrame`); read-only users between frames take `skinPointer(body:)`.
    var dynPointer: UnsafeMutablePointer<Float> { waitIfNeeded(); return slots[0].dynPointer }
    /// One entry per Jelly drawn (1 unless the game asked for more): own vertex stream, uniforms (palette, mouth), bath parameters.
    private(set) var slots: [BodySlot] = []
    var bodyCount: Int { slots.count }
    /// The static stream every body starts from (the park adds bodies after launch: Park/MelonController+Park.swift).
    private var baseStatic: [Float] = []
    /// Grows the GPU slots to `n` bodies (never shrinks; extra ones start hidden). False when a buffer could not be made.
    @discardableResult
    func ensureBodies(_ n: Int) -> Bool {
        while slots.count < n {
            guard let slot = BodySlot(device: device, vertexCount: vertexCount, staticData: baseStatic, label: " \(slots.count)") else { return false }
            slot.ring = slots[0].ring
            slot.hidden = true
            slots.append(slot)
        }
        return true
    }
    /// The park is on: its far camera wants the haze pushed out.
    var parkVisible = false
    func dynPointer(body i: Int) -> UnsafeMutablePointer<Float> { waitIfNeeded(); return slots[i].dynPointer }

    private let mesh: RenderMesh
    private let vertexCount: Int
    private let lineCount: Int
    private var dynBuf: MTLBuffer { slots[0].dynBuf }
    private var staticBuf: MTLBuffer { slots[0].staticBuf }
    private let indexBuf: MTLBuffer
    private let lineIdxBuf: MTLBuffer
    private var particleBuf: MTLBuffer { particleBufs[ring] }
    private let particleBufs: [MTLBuffer]
    private let particleBytes: Int
    private var uboBuf: MTLBuffer { slots[0].uboBuf }
    private var lightBuf: MTLBuffer { lightBufs[ring] }
    private var topBuf: MTLBuffer { topBufs[ring] }
    private let lightBufs: [MTLBuffer]
    private let topBufs: [MTLBuffer]
    /// The buffer copy this frame writes / draws (0..<BodySlot.ring); advanced each time a frame is acquired.
    private(set) var ring = 0
    private var uniforms = MelonUniforms()

    private let shadowSize: Int
    private let topSize = 512
    private let shadowTex: MTLTexture
    private let topTex: MTLTexture
    /// 16-bit shadow / height maps and their depth pipeline (gfxOpt.shadowDepth16), made on first use.
    private var shadowTex16: MTLTexture?, topTex16: MTLTexture?, pDepth16: MTLRenderPipelineState?
    /// Shadow / height format used by the last frame (tests / env log).
    private(set) var lastShadowFormat = MTLPixelFormat.depth32Float

    private let pDepth: MTLRenderPipelineState
    private let pBackground: MTLRenderPipelineState
    private let pProps: MTLRenderPipelineState
    private let pBack: MTLRenderPipelineState
    private let pCopy: MTLRenderPipelineState
    private let pJelly: MTLRenderPipelineState
    private let pMatte: MTLRenderPipelineState
    private let pEyes: MTLRenderPipelineState
    /// Bob's matte skin with suds / wet / sparkle (BathShaders.metal). Only used while the BathLook asks for one of them; dry = `pMatte`.
    private let pMatteBath: MTLRenderPipelineState
    /// fsSoftMatteBath specialised by function constants, keyed by the soot/foam/wet/sparkle mask (gfxOpt.bathVariants); 15 = pMatteBath.
    private var pMatteBathVariants: [Int: MTLRenderPipelineState] = [:]
    /// Soft matte look (Bob / blush palette) instead of the glossy translucent jelly.
    private(set) var useMatte = false
    /// The living room (game screen). When set, it replaces the studio backdrop and Bob is drawn into the same pass.
    private(set) var room: RoomRenderer?
    /// 0...1: Bob's mouth (matte body shader). 0 = no mouth at all. The brain sets this each frame. Body 0; `slots[i].mouthOpen` for the others.
    var mouthOpen: Float { get { slots[0].mouthOpen } set { slots[0].mouthOpen = newValue } }
    /// DEBUG/screenshot override: launch argument -MelonMouth <0...1>.
    private let forcedMouth: Float? = UserDefaults.standard.object(forKey: "MelonMouth") != nil ? Float(UserDefaults.standard.double(forKey: "MelonMouth")) : nil
    /// DEBUG/screenshot override: launch argument -MelonBlush <0...1>.
    private let forcedBlush: Float? = UserDefaults.standard.object(forKey: "MelonBlush") != nil ? Float(UserDefaults.standard.double(forKey: "MelonBlush")) : nil
    /// What the bath does to Bob's look this frame (suds, soot, wet, sparkle, held tool, spray, bubbles, bathroom on/off).
    /// `.dry` (the default) draws exactly the pre-bath frame. The stage sets this once per frame.
    var bathLook: BathLook { get { slots[bathBody].bathLook } set { slots[bathBody].bathLook = newValue } }
    /// The body the bath close-up is about (props, sparkles, the bathroom switch follow it): Bob (0) unless another Jelly is being washed.
    var bathBody = 0 { didSet { if bathBody < 0 || bathBody >= slots.count { bathBody = 0 } } }
    private var bathFoamAny: Bool { slots[bathBody].foamAny }
    private var bathSootAny: Bool { slots[bathBody].sootAny }
    /// Test hook: draw Bob with the bath shader even when every control is zero (to compare it with the original).
    var forceBathShader = false
    /// Which body pipeline the last frame used ("matte" or "matteBath").
    private(set) var lastBodyPipeline = "matte"
    private var bodyVerts: [Int32] = []
    private var surfaceVertex = -1
    private var surfaceDirKey = SIMD3<Float>.zero
    private var sparkleVerts: [Int] = []
    private let pLines: MTLRenderPipelineState
    private let pPost: MTLRenderPipelineState
    private let pCacheBlit: MTLRenderPipelineState
    private let pPresent: MTLRenderPipelineState
    /// GPU-side options (GfxSavings.swift: GfxOpt). Memoryless targets / draw order are pixel-identical; `fastMatteTier` > 0 is a visible opt-in.
    var gfxOpt = GfxOpt()
    private let library: MTLLibrary
    private let meshVD: MTLVertexDescriptor
    /// fsSoftMatteFast pipelines by tier (GfxBodyFast.metal), built on first use.
    private var pMatteFast: [Int: MTLRenderPipelineState] = [:]
    /// The jersey body pipeline (Wear/GfxJersey.metal) and its per-vertex egg flags; built on first use.
    private var pJersey: MTLRenderPipelineState?
    private var eggFlagBuf: MTLBuffer?
    private(set) var jerseyDraws = 0
    /// Whether the current MSAA / depth targets are memoryless (game pass, no PerfPasses, device supports it).
    private(set) var targetsMemoryless = false
    /// The body draw order of the last frame (slot indices), for tests.
    private(set) var lastBodyOrder: [Int] = []

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

    /// Frames in flight (triple buffering): the CPU only waits when the GPU is `BodySlot.ring` frames behind.
    private let inflight = DispatchSemaphore(value: BodySlot.ring)
    /// GPU time per frame (from MTLCommandBuffer gpuStart/EndTime), accumulated off-thread; read via `takeGPUStats()`.
    private let gpuTimes = GPUTimeAccumulator()

    /// Returns (average GPU ms per frame, frames) since the last call, then resets. (0, 0) if none completed.
    func takeGPUStats() -> (avgMs: Double, frames: Int) { gpuTimes.take() }
    /// Last completed frame's GPU ms (feeds the adaptive render scaler).
    var lastGPUMs: Double { gpuTimes.lastMs }
    private var frameOwned = false

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat, mesh: RenderMesh, simEdges: [UInt32], particleCount: Int, game: Bool = false, bodyCount: Int = 1, shadowSizeOverride: Int? = nil) {
        guard MemoryLayout<MelonUniforms>.size == 544, MemoryLayout<MelonUniforms>.stride == 544 else {
            print("MelonRenderer: MelonUniforms layout is \(MemoryLayout<MelonUniforms>.size) bytes, expected 544")
            return nil
        }
        guard MemoryLayout<MelonBathParams>.size == 2336, MemoryLayout<MelonBathParams>.stride == 2336 else {
            print("MelonRenderer: MelonBathParams layout is \(MemoryLayout<MelonBathParams>.size) bytes, expected 2336")
            return nil
        }
        guard let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else {
            print("MelonRenderer: no command queue / default library")
            return nil
        }
        self.device = device
        self.queue = queue
        self.library = library
        self.colorPixelFormat = colorPixelFormat
        self.mesh = mesh
        let nV = mesh.vertexCount
        self.vertexCount = nV

        // ── buffers ──
        shadowSize = shadowSizeOverride ?? (bodyCount > 1 ? 2048 : 1024)         // the shadow box covers the whole arena with several Jellies: keep the texel size near the single-body one

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
        guard let ib = device.makeBuffer(bytes: mesh.index, length: max(mesh.index.count * 4, 16), options: .storageModeShared)
        else { return nil }
        indexBuf = ib
        lineCount = simEdges.count
        guard let lb = simEdges.isEmpty
                ? device.makeBuffer(length: 16, options: .storageModeShared)
                : device.makeBuffer(bytes: simEdges, length: simEdges.count * 4, options: .storageModeShared)
        else { return nil }
        lineIdxBuf = lb
        particleBytes = particleCount * 12
        var pbs: [MTLBuffer] = [], lbs: [MTLBuffer] = [], tbs: [MTLBuffer] = []
        for _ in 0..<BodySlot.ring {
            guard let pb = device.makeBuffer(length: max(particleBytes, 16), options: .storageModeShared),
                  let lightB = device.makeBuffer(length: 64, options: .storageModeShared),
                  let topB = device.makeBuffer(length: 64, options: .storageModeShared)
            else { return nil }
            pbs.append(pb); lbs.append(lightB); tbs.append(topB)
        }
        particleBufs = pbs; lightBufs = lbs; topBufs = tbs
        // one GPU slot per Jelly: own vertex stream, wave-arm mat stream, uniforms (palette / mouth) and bath parameters (dirt, soot, shine)
        var made: [BodySlot] = []
        for i in 0..<max(1, bodyCount) {
            guard let slot = BodySlot(device: device, vertexCount: nV, staticData: st, label: i == 0 ? "" : " \(i)") else { return nil }
            made.append(slot)
        }
        slots = made
        baseStatic = st

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
        self.meshVD = meshVD

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
              let mtb = Self.makeBathVariant(device: device, library: library, vd: meshVD, mask: 15),
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
        pMatteBath = mtb
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

    /// Memoryless MSAA / depth targets are possible: game pass (the studio path stores and reloads msDepth), no PerfPasses (stores / reloads
    /// the MSAA colour and depth), and an Apple-family GPU.
    private var wantMemoryless: Bool { gfxOpt.memorylessMSAA && room != nil && !perfPasses && device.supportsFamily(.apple2) }

    /// (Re)creates the screen-sized targets. No-op when the size (and the memoryless choice) is unchanged.
    func resize(width w: Int, height h: Int) {
        let w = max(1, w), h = max(1, h)
        let memoryless = wantMemoryless
        if w == width && h == height && memoryless == targetsMemoryless && msScene != nil { return }
        width = w; height = h
        targetRebuilds += 1
        func tex(_ fmt: MTLPixelFormat, samples: Int, usage: MTLTextureUsage, _ label: String, memoryless: Bool = false) -> MTLTexture? {
            let d = MTLTextureDescriptor()
            d.pixelFormat = fmt; d.width = w; d.height = h
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = usage
            d.storageMode = memoryless ? .memoryless : .private
            let t = device.makeTexture(descriptor: d)
            t?.label = label
            return t
        }
        let rt: MTLTextureUsage = [.renderTarget]
        let rtr: MTLTextureUsage = [.renderTarget, .shaderRead]
        let ms = Self.msaa
        // the game pass only ever clears + resolves msScene and clears + discards msDepth: tile memory only (no RAM, no bandwidth)
        msScene = tex(Self.hdrFormat, samples: ms, usage: rt, "msScene", memoryless: memoryless)
        msDepth = tex(Self.depthFormat, samples: ms, usage: rt, "msDepth", memoryless: memoryless)
        if memoryless && (msScene == nil || msDepth == nil) {        // not supported after all: plain private targets
            msScene = tex(Self.hdrFormat, samples: ms, usage: rt, "msScene")
            msDepth = tex(Self.depthFormat, samples: ms, usage: rt, "msDepth")
            targetsMemoryless = false
        } else {
            targetsMemoryless = memoryless
        }
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
        u.shape = params.shape
        Self.applyPalette(&u, palette)
        u.misc = SIMD4(params.exposure, params.meshAlpha, 0, palette.marking)
        u.bg = SIMD4(params.bg, 1)
        uniforms = u
        // Writes target shared buffers the GPU may still be reading from the previous frame; call beginFrame() first.
        waitIfNeeded()
        uboBuf.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<MelonUniforms>.stride)
        // Jelly Circuit: body 0 wears a rival's colours on the track (nil = the palette above, i.e. Bob's)
        if let pal = slots[0].palette { var ub = u; Self.applyPalette(&ub, pal); ub.misc.w = pal.marking; uboBuf.contents().copyMemory(from: &ub, byteCount: MemoryLayout<MelonUniforms>.stride) }
        // the other Jellies: the same frame uniforms with their own colours (the mouth byte is written per body in encodeFrame)
        for slot in slots.dropFirst() {
            var ub = u
            if let pal = slot.palette { Self.applyPalette(&ub, pal); ub.misc.w = pal.marking }
            slot.uboBuf.contents().copyMemory(from: &ub, byteCount: MemoryLayout<MelonUniforms>.stride)
        }
        lightBuf.contents().copyMemory(from: &uniforms.lightVP, byteCount: 64)
        topBuf.contents().copyMemory(from: &uniforms.topVP, byteCount: 64)
    }

    /// The palette-dependent uniform fields (everything a body's colour reads).
    private static func applyPalette(_ u: inout MelonUniforms, _ palette: Palette) {
        u.flesh = SIMD4(palette.flesh, 1)
        u.fleshDeep = SIMD4(palette.fleshDeep, 1)
        u.pale = SIMD4(palette.pale, 1)
        u.skin = SIMD4(palette.skin, 1)
        u.stripe = SIMD4(palette.stripe, 1)
        u.seed = SIMD4(palette.seed, 1)
        u.shape = SIMD4(palette.extra, palette.bodyHeight)   // white-tone fleshDeep (shape is unused by the Bob shader)
        u.shadowTint = SIMD4(palette.shadowTint, palette.matte ? 2 : 1)
    }

    /// Sets the colours of Jelly `i` (body 0 defaults to the palette given to `setUniforms`; set it when a character other than Bob is in slot 0).
    func setPalette(_ palette: Palette, body i: Int) { if i >= 0, i < slots.count { slots[i].palette = palette } }
    /// Jelly Circuit: a body wears a rival's colours on the track (any body, Bob's too) and its own again with nil (`own` = the roster colours, nil for Bob).
    func setRacePalette(_ palette: Palette?, own: Palette?, body i: Int) { if i < slots.count { slots[i].palette = palette ?? own } }
    /// The race track is drawn instead of the living room (the stage sets it each frame from the race flow).
    var raceVisible = false
    /// The course the track is built for (Race/RaceCourse.swift); the stage sets it with `raceVisible`.
    var raceCourse: CourseTier = .puddle
    /// What the room's wall trophy shelf shows (Trophies/); empty = no shelf.
    var trophyShelf = TrophyShelfSpec()
    /// The Jelly Show's stage set is drawn instead of the room (Show/ShowStage.swift).
    var showVisible = false
    /// The jersey band colour of a body (nil = none: the locked body shader draws him).
    func setJersey(_ team: WearTeam?, body i: Int) { if i < slots.count { slots[i].jersey = team } }
    func setHidden(_ hidden: Bool, body i: Int) { if i < slots.count { slots[i].hidden = hidden } }
    func setBathLook(_ look: BathLook, body i: Int) { if i < slots.count { slots[i].bathLook = look } }
    func setMouth(_ m: Float, body i: Int) { if i < slots.count { slots[i].mouthOpen = m } }
    func setBlush(_ b: Float, body i: Int) { if i < slots.count { slots[i].blush = b } }
    /// Test / capture access: the blush a body is drawn with this frame.
    func blush(body i: Int) -> Float { i < slots.count ? slots[i].blush : 0 }

    /// `p` points at particleCount * 3 floats.
    func uploadParticles(_ p: UnsafePointer<Float>) {
        waitIfNeeded()
        memcpy(particleBuf.contents(), p, particleBytes)
    }

    /// Writes (or, with `values == nil`, restores the baked) mat channel of the given render vertices in the static stream.
    /// Call after `beginFrame()` (the buffer is shared with the GPU).
    func writeMat(_ vertices: [Int32], values: [Float]?, body: Int = 0) {
        waitIfNeeded()
        let slot = slots[body]
        slot.staticMaster.withUnsafeMutableBufferPointer { p in
            if let values {
                for (k, v) in vertices.enumerated() { p[4 * Int(v) + 3] = values[k] }
            } else {
                for v in vertices { p[4 * Int(v) + 3] = mesh.mat[Int(v)] }
            }
        }
        slot.staticChanged()
    }

    /// Blocks until the previous frame's GPU work finished, so `dynPointer`, uniforms and particles are safe to
    /// write. Call once per frame before writing `dynPointer`. setUniforms / uploadParticles / draw call it
    /// implicitly if you did not (the dynPointer writes then race with the GPU).
    func beginFrame() { waitIfNeeded() }

    private func waitIfNeeded() {
        if frameOwned { return }
        _ = inflight.wait(timeout: .now() + 1.0)
        frameOwned = true
        // next copy of every per-frame buffer; the GPU may still be reading the previous two
        ring = (ring + 1) % BodySlot.ring
        for slot in slots { slot.ring = ring; slot.syncStatic() }
    }

    /// The most recently skinned vertex stream of body `i` (pos + normal, 6 floats per vertex), for CPU readers (picking, outlines) between frames.
    /// Unlike `dynPointer(body:)` it does not acquire a frame.
    func skinPointer(body i: Int) -> UnsafePointer<Float> { UnsafePointer(slots[i].dynPointer) }

    // MARK: bath

    /// Writes the bath body-shader parameters (only when something changed; the frame is owned, so the GPU is not reading the buffer).
    private func uploadBathParams(_ slot: BodySlot) {
        let look = slot.bathLook
        let a = SIMD4<Float>(look.wet, look.sparkle, slot.foamAny ? 1 : 0, look.dirt)
        let p = slot.bathParamsBuf.contents()                 // this frame's copy (ring): written whole, ~2.3 KB
        p.storeBytes(of: a, toByteOffset: 0, as: SIMD4<Float>.self)
        p.storeBytes(of: SIMD4<Float>(BathSet.bodyCentre, look.sootStyle), toByteOffset: 16, as: SIMD4<Float>.self)      // .w = this Jelly's soot placement (0 = Bob)
        let nf = min(look.foam.count, BathLook.rows * BathLook.cols)
        look.foam.withUnsafeBytes { src in memcpy(p + MelonBathParams.foamOffset, src.baseAddress!, nf * MemoryLayout<Float>.size) }
        let ns = min(look.soot.count, BathLook.rows * BathLook.cols)
        look.soot.withUnsafeBytes { src in memcpy(p + MelonBathParams.sootOffset, src.baseAddress!, ns * MemoryLayout<Float>.size) }
    }
    /// The body-shader (suds / soot / wet / sparkle) is used for this Jelly this frame.
    private func usesBathShader(_ slot: BodySlot) -> Bool {
        forceBathShader || slot.bathLook.wet > 0.001 || slot.bathLook.sparkle > 0.001 || slot.foamAny || slot.sootAny
    }

    /// Deformed surface point and normal for a body direction: the base-body render vertex whose REST direction (from the body centre) is
    /// closest, read from this frame's skinned positions, so it rides with walks, squishes and jiggles.
    private func surfaceAttach(_ dir: SIMD3<Float>) -> (p: SIMD3<Float>, n: SIMD3<Float>)? {
        ensureBodyVerts()
        if surfaceVertex < 0 || surfaceDirKey != dir {
            let d = simd_length(dir) > 1e-6 ? simd_normalize(dir) : SIMD3<Float>(0, 0, 1)
            let c = BathSet.bodyCentre
            var best = -2 as Float, bv = -1
            for v32 in bodyVerts {
                let v = Int(v32)
                let r = SIMD3<Float>(mesh.rest[3 * v], mesh.rest[3 * v + 1], mesh.rest[3 * v + 2]) - c
                let l = simd_length(r)
                if l < 1e-5 { continue }
                let s = simd_dot(r / l, d)
                if s > best { best = s; bv = v }
            }
            guard bv >= 0 else { return nil }
            surfaceVertex = bv; surfaceDirKey = dir
        }
        let q = slots[bathBody].dynPointer + 6 * surfaceVertex
        return (SIMD3(q[0], q[1], q[2]), SIMD3(q[3], q[4], q[5]))
    }

    private func ensureBodyVerts() {
        guard bodyVerts.isEmpty else { return }
        let end = mesh.armCapsule.map { $0.indexFirst } ?? (mesh.body.first + mesh.body.count)
        var seen = Set<Int32>()
        var i = mesh.body.first
        while i < end { seen.insert(Int32(mesh.index[i])); i += 1 }
        bodyVerts = seen.sorted()
    }

    /// Skinned surface point / normal at one of `BathOverlay.sparkleSpots` evenly spread directions (floating sparkles spawn there).
    private func sparkleSpot(_ i: Int) -> (p: SIMD3<Float>, n: SIMD3<Float>)? {
        ensureBodyVerts()
        if sparkleVerts.isEmpty {
            let n = BathOverlay.sparkleSpots, c = BathSet.bodyCentre
            for k in 0..<n {
                let y = 1 - 2 * (Float(k) + 0.5) / Float(n), rr = (1 - y * y).squareRoot(), a = Float(k) * 2.39996323
                let d = SIMD3<Float>(rr * sinf(a), y, rr * cosf(a))
                var best: Float = -2; var bv = bodyVerts.first.map { Int($0) } ?? 0
                for v32 in bodyVerts {
                    let v = Int(v32)
                    let r = SIMD3<Float>(mesh.rest[3 * v], mesh.rest[3 * v + 1], mesh.rest[3 * v + 2]) - c
                    let l = simd_length(r)
                    if l < 1e-5 { continue }
                    let s = simd_dot(r / l, d)
                    if s > best { best = s; bv = v }
                }
                sparkleVerts.append(bv)
            }
        }
        guard i < sparkleVerts.count else { return nil }
        let q = slots[bathBody].dynPointer + 6 * sparkleVerts[i]
        return (SIMD3(q[0], q[1], q[2]), SIMD3(q[3], q[4], q[5]))
    }

    /// World point on Bob's current (skinned) surface in rest direction `dir` from his body centre (tools use it to find where to press).
    func surfacePoint(dir: SIMD3<Float>) -> SIMD3<Float>? { surfaceAttach(dir)?.p }

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
    /// Capture / test aid: draw the room at this hour instead of the DayClock's.
    var dayHourOverride: Double?
    /// 0...1: the sleepers are tucked in (the stage sets it): the lamp dims and the quilt over the cuddle pile fades in.
    /// The quilt RoomProp is parked (tuck-in stays as lamp dim + room darken). Flip to bring it back.
    static let showQuilt = false
    var tuckAmount: Float = 0
    /// Where the quilt lies (centre x, z; half size x, z): the sleepers' pile. Set by the stage.
    var quiltSpot: (centre: SIMD2<Float>, half: SIMD2<Float>)?
    private func quiltProps(_ t: Float) -> [RoomProp] {
        guard let q = quiltSpot else { return [] }
        return [RoomProp(kind: .quilt, pos: q.centre, scale: t, half: q.half)]
    }
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
    private func bobBounds(_ body: Int = 0) -> (lo: SIMD3<Float>, hi: SIMD3<Float>) {
        var x0 = Float.infinity, y0 = Float.infinity, z0 = Float.infinity, x1 = -Float.infinity, y1 = -Float.infinity, z1 = -Float.infinity
        slots[body].dynPointer.withMemoryRebound(to: Float.self, capacity: vertexCount * 6) { p in
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

    // MARK: GPU options (GfxOpt)

    /// Visible slots, nearest body first when `gfxOpt.frontToBack` (distance from the camera to the centre of the skinned AABB), else in slot order.
    private func bodyOrder(camPos: SIMD3<Float>) -> [Int] {
        let visible = slots.indices.filter { !slots[$0].hidden }
        guard gfxOpt.frontToBack, visible.count > 1 else { return visible }
        let dist = visible.map { i -> Float in let b = bobBounds(i); return simd_length((b.lo + b.hi) * 0.5 - camPos) }
        return zip(visible, dist).sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// mask 15: the plain fsSoftMatteBath (the bit-exact reference BathSootSeedZeroTests hashes). Otherwise fsSoftMatteBathSpec with the
    /// soot (1) / foam (2) / wet (4) / sparkle (8) blocks compiled in per `mask` (a specialised build folds a few ulps differently).
    private static func makeBathVariant(device: MTLDevice, library: MTLLibrary, vd: MTLVertexDescriptor, mask: Int) -> MTLRenderPipelineState? {
        let fsOpt: MTLFunction?
        if mask == 15 {
            fsOpt = library.makeFunction(name: "fsSoftMatteBath")
        } else {
            let cv = MTLFunctionConstantValues()
            for bit in 0..<4 { var on = (mask >> bit) & 1 == 1; cv.setConstantValue(&on, type: .bool, index: bit) }
            fsOpt = try? library.makeFunction(name: "fsSoftMatteBathSpec", constantValues: cv)
        }
        guard let fs = fsOpt, let vs = library.makeFunction(name: "vsJelly") else {
            print("MelonRenderer: fsSoftMatteBath variant \(mask) unavailable"); return nil
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = "matte bath \(mask)"
        d.vertexFunction = vs; d.fragmentFunction = fs
        d.vertexDescriptor = vd
        d.colorAttachments[0].pixelFormat = hdrFormat
        d.depthAttachmentPixelFormat = depthFormat
        d.rasterSampleCount = msaa
        do { return try device.makeRenderPipelineState(descriptor: d) } catch { print("MelonRenderer: matte bath \(mask) failed: \(error)"); return nil }
    }

    /// The bath body pipeline for this slot's look: specialised when `gfxOpt.bathVariants`, else the all-in-one shader.
    private func bathPipeline(_ slot: BodySlot) -> MTLRenderPipelineState {
        guard gfxOpt.bathVariants else { return pMatteBath }
        let l = slot.bathLook
        let mask = (slot.sootAny ? 1 : 0) | (slot.foamAny ? 2 : 0) | (l.wet > 0.001 ? 4 : 0) | (l.sparkle > 0.001 ? 8 : 0)
        if mask == 15 { return pMatteBath }
        if let p = pMatteBathVariants[mask] { return p }
        let p = Self.makeBathVariant(device: device, library: library, vd: meshVD, mask: mask) ?? pMatteBath
        pMatteBathVariants[mask] = p
        return p
    }

    /// Shadow / height depth maps and the depth-only pipeline for this frame (16-bit when `gfxOpt.shadowDepth16`, made on first use).
    private func shadowMaps() -> (shadow: MTLTexture, top: MTLTexture, pipeline: MTLRenderPipelineState, format: MTLPixelFormat) {
        guard gfxOpt.shadowDepth16 else { return (shadowTex, topTex, pDepth, Self.depthFormat) }
        if shadowTex16 == nil || topTex16 == nil || pDepth16 == nil {
            func depthMap(_ size: Int, _ label: String) -> MTLTexture? {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth16Unorm, width: size, height: size, mipmapped: false)
                d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
                let t = device.makeTexture(descriptor: d); t?.label = label; return t
            }
            let pd = MTLRenderPipelineDescriptor()
            pd.label = "depth16"
            pd.vertexFunction = library.makeFunction(name: "depthVS")
            let posVD = MTLVertexDescriptor()
            posVD.attributes[0].format = .float3; posVD.attributes[0].offset = 0; posVD.attributes[0].bufferIndex = 1
            posVD.layouts[1].stride = 24
            pd.vertexDescriptor = posVD
            pd.depthAttachmentPixelFormat = .depth16Unorm
            pd.rasterSampleCount = 1
            shadowTex16 = depthMap(shadowSize, "shadow map 16"); topTex16 = depthMap(topSize, "height map 16")
            pDepth16 = try? device.makeRenderPipelineState(descriptor: pd)
        }
        guard let s = shadowTex16, let t = topTex16, let p = pDepth16 else { return (shadowTex, topTex, pDepth, Self.depthFormat) }
        return (s, t, p, .depth16Unorm)
    }

    /// The opt-in cheaper matte body pipeline for `tier` (1...3), built once (function constant `fastTier`). nil -> the locked shader is used.
    private func fastMattePipeline(tier: Int) -> MTLRenderPipelineState? {
        if let p = pMatteFast[tier] { return p }
        let cv = MTLFunctionConstantValues()
        var t = Int32(tier)
        cv.setConstantValue(&t, type: .int, index: 0)
        guard let fs = try? library.makeFunction(name: "fsSoftMatteFast", constantValues: cv), let vs = library.makeFunction(name: "vsJelly") else {
            print("MelonRenderer: fsSoftMatteFast tier \(tier) unavailable"); return nil
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = "matte fast \(tier)"
        d.vertexFunction = vs; d.fragmentFunction = fs
        d.vertexDescriptor = meshVD
        d.colorAttachments[0].pixelFormat = Self.hdrFormat
        d.depthAttachmentPixelFormat = Self.depthFormat
        d.rasterSampleCount = Self.msaa
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { print("MelonRenderer: matte fast \(tier) pipeline failed"); return nil }
        pMatteFast[tier] = p
        return p
    }

    // MARK: jersey (Wear/GfxJersey.metal)

    private func jerseyPipeline() -> MTLRenderPipelineState? {
        if let p = pJersey { return p }
        guard let vs = library.makeFunction(name: "vsJellyJersey"), let fs = library.makeFunction(name: "fsSoftMatteJersey") else { print("MelonRenderer: jersey shader unavailable"); return nil }
        let d = MTLRenderPipelineDescriptor()
        d.label = "matte jersey"
        d.vertexFunction = vs; d.fragmentFunction = fs
        d.vertexDescriptor = meshVD
        d.colorAttachments[0].pixelFormat = Self.hdrFormat
        d.depthAttachmentPixelFormat = Self.depthFormat
        d.rasterSampleCount = Self.msaa
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { print("MelonRenderer: jersey pipeline failed"); return nil }
        pJersey = p
        return p
    }
    /// One byte per render vertex: 1 for the egg, 0 for the arm capsules and foot beans (they share the mesh; their rest y overlaps the band).
    private func eggFlags() -> MTLBuffer? {
        if let b = eggFlagBuf { return b }
        var f = [UInt8](repeating: 1, count: mesh.vertexCount)
        if let info = mesh.armCapsule {
            for side in [-1, 1] {
                let a = info.first(side: side), e = info.beanFirst(side: side) + FootBean.vertexCount
                for i in a..<min(e, f.count) { f[i] = 0 }
            }
        }
        eggFlagBuf = device.makeBuffer(bytes: f, length: max(f.count, 1), options: .storageModeShared)
        eggFlagBuf?.label = "jersey egg flags"
        return eggFlagBuf
    }
    /// Shader parameters of a team's band: cloth and trim, with the shadow side of each.
    static func jerseyParams(_ t: WearTeam) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let c = t.linear, cr = WearTeam.creamLinear
        return (SIMD4(c, 1), SIMD4(c * 0.56, 1), SIMD4(cr, 1), SIMD4(cr * 0.62, 1), SIMD4(0.22, 0.51, 0.008, 0.03))
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
        if width > 0 && wantMemoryless != targetsMemoryless { resize(width: width, height: height) }     // gfxOpt changed since the targets were made
        guard let msScene, let msDepth, let sceneTex, let backTex, let backDepth, let msHdr, let hdrTex else { return false }
        waitIfNeeded()
        // mouthOpen rides in `stripe.w` (byte 460 of MelonUniforms); written here so it is always current for this frame.
        for (i, slot) in slots.enumerated() {
            slot.uboBuf.contents().storeBytes(of: min(max(forcedMouth ?? slot.mouthOpen, 0), 1), toByteOffset: 460, as: Float.self)
            slot.uboBuf.contents().storeBytes(of: min(max(forcedBlush ?? slot.blush, 0), 1), toByteOffset: 476, as: Float.self)          // seed.w
            _ = i
        }
        let m = mesh
        let bodyAndSeeds = m.body.count + m.seeds.count
        let tri = MTLPrimitiveType.triangle

        // shadow map + top-down height map (32-bit, or 16-bit with gfxOpt.shadowDepth16; the locals shadow the stored 32-bit maps below)
        let (shadowTex, topTex, pDepthNow, shadowFormat) = shadowMaps()
        lastShadowFormat = shadowFormat
        for (tex, mbuf, label) in [(shadowTex, lightBuf, "shadow"), (topTex, topBuf, "height")] {
            let rp = MTLRenderPassDescriptor()
            rp.depthAttachment.texture = tex
            rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 1
            rp.depthAttachment.storeAction = .store
            guard let e = cmd.makeRenderCommandEncoder(descriptor: rp) else { return false }
            e.label = label
            e.setRenderPipelineState(pDepthNow)
            e.setDepthStencilState(dsLessWrite)
            e.setCullMode(.none)
            e.setFrontFacing(.counterClockwise)
            e.setDepthBias(2, slopeScale: 2, clamp: 0)
            e.setVertexBuffer(mbuf, offset: 0, index: 0)
            for slot in slots where !slot.hidden {
                e.setVertexBuffer(slot.dynBuf, offset: 0, index: 1)
                e.drawIndexedPrimitives(type: tri, indexCount: bodyAndSeeds, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: 0)
            }
            e.endEncoding()
            split(&cmd, label)
        }

        // Game: the room and Bob share one MSAA pass that resolves straight to hdrTex (matte Bob needs no scene copy / back faces).
        if let room {
            room.raceCourse = raceCourse
            room.raceVisible = raceVisible
            room.showVisible = showVisible
            room.fog = raceVisible ? SIMD3(45, 150, 0.5) : parkVisible ? SIMD3(34, 90, 0.3) : SIMD3(14, 32, 0.3)
            let tuckQ = (tuckAmount * 10).rounded() / 10          // quantised: the room cache is rebuilt per step of the dim, not per frame
            room.daylight = (dayHourOverride.map { DayLight.at(hour: $0) } ?? DayLight.at(hour: DayClock.shared.displayHour)).tucked(tuckQ)
            room.props = ((Self.showQuilt && tuckQ > 0.05) ? quiltProps(tuckQ) : []) + (trophyShelf.isEmpty ? [] : [RoomProp(kind: .shelf, pos: .zero, level: Float(RoomLayout.revision & 0xFFFF), shelf: trophyShelf)])          // (level = the room's layout revision: the shelf hangs between THIS room's windows)
            // ---- bath: bathroom on/off, props over Bob, body shader parameters ----
            room.bathVisible = bathLook.visible
            room.bathTime = uniforms.camPos.w
            let vw = uniforms.view
            room.bathOverlay.compose(look: bathLook, time: uniforms.camPos.w,
                                     camRight: SIMD3(vw.columns.0.x, vw.columns.1.x, vw.columns.2.x), camUp: SIMD3(vw.columns.0.y, vw.columns.1.y, vw.columns.2.y),
                                     sparkleAt: { [self] i in sparkleSpot(i) })
            room.commitBathOverlay()
            let bodyBath = usesBathShader(slots[bathBody])
            for slot in slots where !slot.hidden && usesBathShader(slot) { uploadBathParams(slot) }
            lastBodyPipeline = bodyBath ? "matteBath" : (gfxOpt.fastMatteTier > 0 ? "matteFast\(gfxOpt.fastMatteTier)" : "matte")

            room.keyDir = SIMD3(uniforms.keyDir.x, uniforms.keyDir.y, uniforms.keyDir.z)
            let camPos3 = SIMD3<Float>(uniforms.camPos.x, uniforms.camPos.y, uniforms.camPos.z)
            let fullPx = Double(width * height)

            // Room cache: decide before the main pass (a build is its own pass, first).
            var action = RoomCacheAction.bypass(.disabled)
            var scissor: MTLScissorRect?                  // the box around every footprint
            var scissors: [MTLScissorRect] = []           // the footprints themselves (disjoint)
            if roomCacheEnabled {
                // One Jelly: one footprint with the tray / bath pieces folded in (the original single rect). Several: one footprint per visible
                // Jelly (Bob's with the bath pieces) plus the tray's, merged where they touch, so spread-out Jellies keep the saving.
                var rects: [RoomFootprint.Rect] = []
                func footprint(_ lo0: SIMD3<Float>, _ hi0: SIMD3<Float>) -> RoomFootprint.Rect {
                    RoomFootprint.rect(min: lo0, max: hi0, shadowDir: GameCamera.shadowDir, viewProj: uniforms.viewProj, width: width, height: height)
                }
                var (lo, hi) = bobBounds(bathBody)
                let single = slots.count == 1
                if single, let d = room.diningBounds { lo = simd_min(lo, d.lo); hi = simd_max(hi, d.hi) }
                if single { for w in room.wearBounds { lo = simd_min(lo, w.lo); hi = simd_max(hi, w.hi) } }
                if let b = room.bathOverlay.bounds { lo = simd_min(lo, b.lo); hi = simd_max(hi, b.hi) }
                if room.bathVisible {       // the water disc is drawn inside the footprint too
                    let c = BathModels.basinCentre, r = BathModels.waterR
                    lo = simd_min(lo, SIMD3(c.x - r, 0, c.y - r)); hi = simd_max(hi, SIMD3(c.x + r, BathModels.waterY, c.y + r))
                }
                rects.append(footprint(lo, hi))
                if !single {
                    for i in 0..<slots.count where i != bathBody && !slots[i].hidden { let b = bobBounds(i); rects.append(footprint(b.lo, b.hi)) }
                    if let d = room.diningBounds { rects.append(footprint(d.lo, d.hi)) }
                    for w in room.wearBounds { rects.append(footprint(w.lo, w.hi)) }
                    rects = RoomFootprint.mergeOverlapping(rects)
                }
                let rect = rects[0]
                let share = single ? RoomFootprint.share(rect, width: width, height: height)
                                   : Float(rects.reduce(0) { $0 + $1.area }) / Float(Swift.max(width * height, 1))
                room.ensureBuilt()      // a swapped room (RoomLayout.apply) bumps staticVersion before the key is read
                var key = RoomCacheKey()
                key.viewProj = uniforms.viewProj; key.camPos = camPos3; key.width = width; key.height = height
                key.themeTint = room.theme.tint; key.propsVersion = room.staticVersion
                key.keyDir = room.keyDir; key.keyIntensity = room.keyIntensity; key.fog = room.fog; key.daylight = room.daylight
                key.bath = room.bathVisible
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
                if action == .use || action == .build {
                    scissors = rects.map { MTLScissorRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
                    let x0 = rects.map(\.x).min()!, y0 = rects.map(\.y).min()!
                    let x1 = rects.map { $0.x + $0.w }.max()!, y1 = rects.map { $0.y + $0.h }.max()!
                    scissor = MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                }
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
                roomPixelsShaded += Double(scissors.reduce(0) { $0 + $1.width * $1.height })
                // Cached colour only OUTSIDE the footprint (four scissored strips), so the pixels inside see exactly the old draw sequence
                // (a full-screen underlay changed the resolve of a few of Bob's edge pixels by 1-3 levels).
                e.pushDebugGroup("room cache")
                e.setRenderPipelineState(pCacheBlit)
                e.setDepthStencilState(dsAlwaysNoWrite)
                e.setCullMode(.none)
                e.setFragmentTexture(cacheTex, index: 0)
                let strips: [MTLScissorRect]
                if scissors.count == 1 {
                    strips = [MTLScissorRect(x: 0, y: 0, width: width, height: sc.y),
                              MTLScissorRect(x: 0, y: sc.y + sc.height, width: width, height: height - sc.y - sc.height),
                              MTLScissorRect(x: 0, y: sc.y, width: sc.x, height: sc.height),
                              MTLScissorRect(x: sc.x + sc.width, y: sc.y, width: width - sc.x - sc.width, height: sc.height)]
                } else {
                    strips = RoomFootprint.complement(of: scissors.map { RoomFootprint.Rect(x: $0.x, y: $0.y, w: $0.width, h: $0.height) }, width: width, height: height)
                        .map { MTLScissorRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
                }
                for r in strips where r.width > 0 && r.height > 0 {
                    e.setScissorRect(r)
                    e.drawPrimitives(type: tri, vertexStart: 0, vertexCount: 3)
                }
                e.popDebugGroup()
                for fp in scissors {
                    e.setScissorRect(fp)
                    room.encode(e, viewProj: uniforms.viewProj, camPos: camPos3, lightViewProj: uniforms.lightVP, shadowTex: shadowTex,
                                topViewProj: uniforms.topVP, heightTex: topTex, parts: .staticOnly)
                    room.encode(e, viewProj: uniforms.viewProj, camPos: camPos3, lightViewProj: uniforms.lightVP, shadowTex: shadowTex,
                                topViewProj: uniforms.topVP, heightTex: topTex, parts: .diningOnly)
                }
                e.setScissorRect(sc)
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
            e.setDepthStencilState(dsLessWrite)
            e.setCullMode(.back)
            let order = bodyOrder(camPos: camPos3)
            lastBodyOrder = order
            let fast = gfxOpt.fastMatteTier > 0 ? fastMattePipeline(tier: gfxOpt.fastMatteTier) : nil
            for bi in order {                            // each Jelly: its own vertex stream, colours / mouth and bath look
                let slot = slots[bi]
                e.setVertexBuffer(slot.uboBuf, offset: 0, index: 0)
                e.setFragmentBuffer(slot.uboBuf, offset: 0, index: 0)
                e.setVertexBuffer(slot.dynBuf, offset: 0, index: 1)
                e.setVertexBuffer(slot.staticBuf, offset: 0, index: 2)
                if usesBathShader(slot) {
                    e.setRenderPipelineState(bathPipeline(slot))
                    e.setFragmentBuffer(slot.bathParamsBuf, offset: 0, index: 3)
                } else if let team = slot.jersey, let jp = jerseyPipeline(), let flags = eggFlags() {
                    e.setRenderPipelineState(jp)
                    e.setVertexBuffer(flags, offset: 0, index: 3)
                    var par = Self.jerseyParams(team)
                    e.setFragmentBytes(&par, length: MemoryLayout.size(ofValue: par), index: 1)
                    jerseyDraws += 1
                } else {
                    e.setRenderPipelineState(fast ?? pMatte)
                }
                e.drawIndexedPrimitives(type: tri, indexCount: m.body.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.body.first * 4)
                if m.seeds.count > 0 {
                    e.setRenderPipelineState(pEyes)
                    e.drawIndexedPrimitives(type: tri, indexCount: m.seeds.count, indexType: .uint32, indexBuffer: indexBuf, indexBufferOffset: m.seeds.first * 4)
                }
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
