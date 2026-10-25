//
//  RoomRenderer.swift
//  Draws the living room (opaque, depth-writing). Integration in MelonRenderer's "scene" pass:
//
//      // after clearing msScene/msDepth, BEFORE seeds/bubbles/jelly (and before the sceneTex resolve):
//      room.encode(e, viewProj: cam.viewProj, camPos: cam.pos, lightViewProj: light.lightVP, shadowTex: shadowTex)
//      // then re-set your own pipeline / depth / cull state (encode changes them; front face stays CCW)
//
//  Pass formats: colorFormat = .rgba16Float (HDR scene), depthFormat = .depth32Float, sampleCount = 4.
//  Output is linear, scene-referred; the post pass tone-maps. Vignette: use roomVignette() in RoomShaders.metal
//  (or multiply by it) in the final composite.
//

import Metal
import simd

struct RoomUniforms {
    var viewProj = matrix_identity_float4x4
    var lightVP = matrix_identity_float4x4
    var camPos = SIMD4<Float>(repeating: 0)
    var keyDir = SIMD4<Float>(repeating: 0)
    var rug = SIMD4<Float>(repeating: 0)
    var bounds = SIMD4<Float>(repeating: 0)
    var fog = SIMD4<Float>(repeating: 0)
    var pal0 = SIMD4<Float>(repeating: 0)
    var pal1 = SIMD4<Float>(repeating: 0)
    var pal2 = SIMD4<Float>(repeating: 0)
    var pal3 = SIMD4<Float>(repeating: 0)
    var pal4 = SIMD4<Float>(repeating: 0)
    var topVP = matrix_identity_float4x4
    var sky0 = SIMD4<Float>(repeating: 0)
    var sky1 = SIMD4<Float>(repeating: 0)
    var keyCol = SIMD4<Float>(1, 0.95, 0.88, 0)
    var ambCol = SIMD4<Float>(1, 1, 1, 1)
    var lamp = SIMD4<Float>(repeating: 0)
    var lampPos = SIMD4<Float>(repeating: 0)
    // appended for the bought rooms (RoomDef): style x floor, y wall, z rug (0 = the living room's); win x = window bottom, y = window height
    var style = SIMD4<Float>(repeating: 0)
    var win = SIMD4<Float>(1.5, 2.8, 0, 0)
}

nonisolated final class RoomRenderer {
    /// Same direction as the jelly's key light (CameraRig.keyDir).
    static let defaultKeyDir = simd_normalize(SIMD3<Float>(-0.5, 0.8, 0.55))

    var theme: RoomTheme { didSet { if theme != oldValue { rebuild() } } }
    /// The room the Jelbies live in (RoomLayout.current): the mesh, palette, window and styles follow it. Off for the standalone preview.
    var followsRoom = true
    private var builtRevision = -1
    /// Rebuilds the room when `RoomLayout.apply` has swapped rooms since the last build. `encode` calls it first; public for tests.
    func ensureBuilt() {
        guard followsRoom, builtRevision != RoomLayout.revision else { return }
        builtRevision = RoomLayout.revision
        let t = RoomLayout.current.theme
        if theme != t { theme = t } else { rebuild() }
    }
    var keyDir = RoomRenderer.defaultKeyDir
    var keyIntensity: Float = 1.6
    /// Depth fog: start, end, max amount. The game camera is ~15 units from the room centre, so it pushes this out.
    var fog = SIMD3<Float>(3, 9, 0.35)
    /// Time of day (DayLight.swift): the window sky, key colour, ambient tint and lamp glow. `DayLight.day` = the room as it was before.
    var daylight = DayLight.day

    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let blendPipeline: MTLRenderPipelineState
    private let blendDepthState: MTLDepthStencilState
    private let dummyShadow: MTLTexture
    /// The shoe paint table the fragment shader reads (Wear/ShoeGPU.swift), bound at fragment buffer 2 wherever the room pipelines run.
    private lazy var shoeTable: MTLBuffer? = ShoeGPU.table.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    // Bath (see Bath/): the bathroom set replaces the living room while `bathVisible`; dirt / tool / bubbles / spray draw over Bob always.
    private var bathOpaquePipeline: MTLRenderPipelineState?
    private var bathBlendPipeline: MTLRenderPipelineState?
    private var bathSetVB: MTLBuffer?, bathSetIB: MTLBuffer?, bathSetIndexCount = 0
    private var bathWaterVB: MTLBuffer?, bathWaterIB: MTLBuffer?, bathWaterIndexCount = 0
    /// Per-frame props over Bob. Three rotating buffers each (the GPU may still read the previous frame's).
    let bathOverlay = BathOverlay()
    private var bathOvVB: [MTLBuffer?] = [nil, nil, nil], bathOvIB: [MTLBuffer?] = [nil, nil, nil]
    private var bathOvCapV = [0, 0, 0], bathOvCapI = [0, 0, 0]
    private var bathOvSlot = 0, bathOvIndexCount = 0
    /// Seconds (drives the water ripple, bubble film and glints). The renderer sets it from the frame time.
    var bathTime: Float = 0
    /// The bathroom is drawn instead of the living room. Changing it bumps `staticVersion`, which invalidates the room cache.
    var bathVisible = false {
        didSet {
            guard bathVisible != oldValue else { return }
            staticVersion &+= 1
            if bathVisible { buildBathMeshes() }
        }
    }
    // Race (Race/RaceModels.swift): the Waddle Sprint track replaces the living room while `raceVisible`. Same pipeline and vertex format as the room.
    private var raceVB: MTLBuffer?, raceIB: MTLBuffer?, raceIndexCount = 0
    /// The track is drawn instead of the living room. Changing it bumps `staticVersion`, which invalidates the room cache.
    var raceVisible = false {
        didSet {
            guard raceVisible != oldValue else { return }
            staticVersion &+= 1
            if raceVisible { buildRaceMeshes() }
        }
    }
    /// The course the track is built for (Race/RaceCourse.swift). A change drops the built track; it is rebuilt for the new course when shown.
    var raceCourse: CourseTier = .puddle {
        didSet {
            guard raceCourse != oldValue else { return }
            raceVB = nil; raceIB = nil; raceIndexCount = 0
            staticVersion &+= 1
            if raceVisible { buildRaceMeshes() }
        }
    }
    // Jelly Show (Show/ShowStage.swift): the stage set replaces the living room while `showVisible`. Same pipeline and vertex format as the room.
    private var showVB: MTLBuffer?, showIB: MTLBuffer?, showIndexCount = 0
    /// The stage is drawn instead of the living room. Changing it bumps `staticVersion`, which invalidates the room cache.
    var showVisible = false {
        didSet {
            guard showVisible != oldValue else { return }
            staticVersion &+= 1
            if showVisible, showVB == nil {
                let m = ShowModels.build()
                showIndexCount = m.indices.count
                showVB = device.makeBuffer(bytes: m.vertices, length: m.vertices.count * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
                showIB = device.makeBuffer(bytes: m.indices, length: m.indices.count * 4, options: .storageModeShared)
                showVB?.label = "show stage vertices"; showIB?.label = "show stage indices"
            }
        }
    }
    private func buildRaceMeshes() {
        guard raceVB == nil else { return }
        let m = RaceModels.build(course: RaceCourse.course(raceCourse))
        raceIndexCount = m.indices.count
        raceVB = device.makeBuffer(bytes: m.vertices, length: m.vertices.count * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        raceIB = device.makeBuffer(bytes: m.indices, length: m.indices.count * 4, options: .storageModeShared)
        raceVB?.label = "race track vertices"; raceIB?.label = "race track indices"
    }
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private(set) var indexCount = 0

    init?(device: MTLDevice, library: MTLLibrary, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat,
          sampleCount: Int, theme: RoomTheme = RoomTheme()) {
        self.device = device
        self.theme = theme
        guard let vs = library.makeFunction(name: "roomVS"), let fs = library.makeFunction(name: "roomFS") else { return nil }
        let vd = MTLVertexDescriptor()
        for i in 0..<3 {
            vd.attributes[i].format = .float4
            vd.attributes[i].offset = i * 16
            vd.attributes[i].bufferIndex = 1
        }
        vd.layouts[1].stride = MemoryLayout<RoomVertex>.stride
        let d = MTLRenderPipelineDescriptor()
        d.label = "room"
        d.vertexFunction = vs; d.fragmentFunction = fs
        d.vertexDescriptor = vd
        d.rasterSampleCount = sampleCount
        d.colorAttachments[0].pixelFormat = colorFormat
        d.depthAttachmentPixelFormat = depthFormat
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        pipeline = p
        // translucent variant (puffs, contact shadows): straight alpha blend, depth-tested, no depth write
        d.label = "room blended"
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].rgbBlendOperation = .add
        d.colorAttachments[0].alphaBlendOperation = .add
        d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let bp = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        blendPipeline = bp
        let bds = MTLDepthStencilDescriptor()
        bds.depthCompareFunction = .less; bds.isDepthWriteEnabled = false
        guard let bdss = device.makeDepthStencilState(descriptor: bds) else { return nil }
        blendDepthState = bdss
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less; ds.isDepthWriteEnabled = true
        guard let dss = device.makeDepthStencilState(descriptor: ds) else { return nil }
        depthState = dss
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false)
        td.usage = .shaderRead; td.storageMode = .private
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        dummyShadow = t
        rebuild()
        makeBathPipelines(library: library, vertexDescriptor: vd, colorFormat: colorFormat, depthFormat: depthFormat, sampleCount: sampleCount)
    }

    private func makeBathPipelines(library: MTLLibrary, vertexDescriptor vd: MTLVertexDescriptor, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat, sampleCount: Int) {
        guard let vs = library.makeFunction(name: "bathVS"), let fs = library.makeFunction(name: "bathFS") else { print("RoomRenderer: bath shaders missing"); return }
        let d = MTLRenderPipelineDescriptor()
        d.label = "bath"
        d.vertexFunction = vs; d.fragmentFunction = fs
        d.vertexDescriptor = vd
        d.rasterSampleCount = sampleCount
        d.colorAttachments[0].pixelFormat = colorFormat
        d.depthAttachmentPixelFormat = depthFormat
        bathOpaquePipeline = try? device.makeRenderPipelineState(descriptor: d)
        d.label = "bath blended"
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].rgbBlendOperation = .add
        d.colorAttachments[0].alphaBlendOperation = .add
        d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        bathBlendPipeline = try? device.makeRenderPipelineState(descriptor: d)
    }

    private func buildBathMeshes() {
        guard bathSetVB == nil else { return }
        let m = BathModels.buildSet(), w = BathModels.buildWater()
        bathSetIndexCount = m.indices.count
        bathSetVB = device.makeBuffer(bytes: m.vertices, length: m.vertices.count * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        bathSetIB = device.makeBuffer(bytes: m.indices, length: m.indices.count * 4, options: .storageModeShared)
        bathWaterIndexCount = w.indices.count
        bathWaterVB = device.makeBuffer(bytes: w.vertices, length: w.vertices.count * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        bathWaterIB = device.makeBuffer(bytes: w.indices, length: w.indices.count * 4, options: .storageModeShared)
        bathSetVB?.label = "bath set"; bathWaterVB?.label = "bath water"
    }

    /// Uploads the overlay soup `bathOverlay` just composed (rotating buffer). Call once per frame, after `bathOverlay.compose`.
    func commitBathOverlay() {
        let s = bathOverlay.soup
        bathOvSlot = (bathOvSlot + 1) % 3
        bathOvIndexCount = s.i.count
        guard bathOvIndexCount > 0 else { return }
        let k = bathOvSlot
        if s.v.count > bathOvCapV[k] {
            bathOvCapV[k] = s.v.count + 2048
            bathOvVB[k] = device.makeBuffer(length: bathOvCapV[k] * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        }
        if s.i.count > bathOvCapI[k] {
            bathOvCapI[k] = s.i.count + 8192
            bathOvIB[k] = device.makeBuffer(length: bathOvCapI[k] * 4, options: .storageModeShared)
        }
        s.v.withUnsafeBytes { bathOvVB[k]?.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        s.i.withUnsafeBytes { bathOvIB[k]?.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    }

    private func makeBathUniforms(viewProj: simd_float4x4, camPos: SIMD3<Float>, lightViewProj: simd_float4x4?, shadow: Bool) -> BathSetUniforms {
        var u = BathSetUniforms()
        u.viewProj = viewProj
        u.lightVP = lightViewProj ?? matrix_identity_float4x4
        u.camPos = SIMD4(camPos, shadow ? 1 : 0)
        u.keyDir = SIMD4(keyDir, 0.85)
        u.misc = SIMD4(bathTime, BathModels.waterY, BathModels.basinCentre.x, BathModels.basinCentre.y)
        u.sky = SIMD4(0.95, 0.94, 0.92, 1) * 0.55
        u.ground = SIMD4(0.78, 0.75, 0.72, 1) * 0.38
        u.fog = SIMD4(0.58, 0.56, 0.53, 0.25)
        return u
    }

    // Movable props (care bowls): a small shared buffer rewritten only when the props change.
    private var propVB: MTLBuffer?, propIB: MTLBuffer?
    private var propIndexCount = 0
    private var propCapV = 0, propCapI = 0
    var props: [RoomProp] = [] {
        didSet {
            guard props != oldValue else { return }
            staticVersion &+= 1
            let m = RoomPropGeometry.build(props: props, theme: theme)
            propIndexCount = m.indices.count
            guard propIndexCount > 0 else { return }
            if m.vertices.count > propCapV {
                propCapV = m.vertices.count + 512
                propVB = device.makeBuffer(length: propCapV * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
            }
            if m.indices.count > propCapI {
                propCapI = m.indices.count + 2048
                propIB = device.makeBuffer(length: propCapI * 4, options: .storageModeShared)
            }
            m.vertices.withUnsafeBytes { propVB?.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            m.indices.withUnsafeBytes { propIB?.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
    }

    // Dining tray (tray, serving, straws, held pieces; opaque) and its translucent extras (puffs, contact shadow, glass).
    // Three rotating buffers each: the mesh may change every frame while the GPU still reads the previous one.
    private struct DynMesh {
        var vb: [MTLBuffer?] = [nil, nil, nil], ib: [MTLBuffer?] = [nil, nil, nil]
        var capV = [0, 0, 0], capI = [0, 0, 0]
        var slot = 0, indexCount = 0
    }
    private var diningOpaque = DynMesh(), diningTranslucent = DynMesh()
    private(set) var diningVertexCount = 0
    /// Bumped whenever the static room pixels can change (geometry rebuild, props). Part of the room cache key.
    private(set) var staticVersion = 0
    /// World AABB of the dining meshes (opaque + translucent), nil when there are none. The room cache re-shades this area every frame.
    var diningBounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)? {
        var out: (lo: SIMD3<Float>, hi: SIMD3<Float>)?
        for b in [trayBounds, maskBounds, decorBounds, gardenBounds] {
            guard let b else { continue }
            out = out.map { (simd_min($0.lo, b.lo), simd_max($0.hi, b.hi)) } ?? b
        }
        return out
    }
    private var trayBounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)?
    /// Sleep eye masks (opaque) and their puffs (translucent): world space, replaced every frame while any is out (SleepMask.swift).
    private var maskOpaque = DynMesh(), maskTranslucent = DynMesh()
    private var maskBounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)?
    // Decor (Room/DecorModels.swift): the resting pieces are part of the cached static room (one buffer, rebuilt when the set or a piece's rest pose
    // changes); a piece that is animating (sat in, booped, rolling) is drawn per frame instead, and its box joins the re-shaded footprint.
    private var decorVB: MTLBuffer?, decorIB: MTLBuffer?, decorIndexCount = 0
    private var decorActive = DynMesh()
    private var decorBounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)?
    // The Garden (Garden/): the plots' plants are part of the cached static room (rebuilt when a stage changes); the butterflies, fireflies, watering can and
    // sparkles are drawn per frame while the garden is the home, and their box joins the re-shaded footprint.
    private var gardenVB: MTLBuffer?, gardenIB: MTLBuffer?, gardenIndexCount = 0
    private var gardenLive = DynMesh()
    private var gardenBounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)?
    /// Worn pieces (hats, glasses, scarves, mitts, ...; opaque) and their poof puffs (translucent): world space, rebuilt every frame while any is worn
    /// (Wear/WornSet.swift). `wearBounds` = one world box per wearing Jelly (hats stand above the body's own box), which the room cache re-shades.
    private var wearOpaque = DynMesh(), wearTranslucent = DynMesh()
    private(set) var wearBounds: [(lo: SIMD3<Float>, hi: SIMD3<Float>)] = []
    /// Worn shoes (opaque, world space, rebuilt every frame while any is worn; ShoeModel.swift). Drawn in the room, on the track and in the bath's absence.
    private var shoeMesh = DynMesh()

    private func upload(_ m: RoomMesh, into d: inout DynMesh) {
        d.slot = (d.slot + 1) % 3
        d.indexCount = m.indices.count
        guard d.indexCount > 0 else { return }
        let s = d.slot
        if m.vertices.count > d.capV[s] {
            d.capV[s] = m.vertices.count + 1024
            d.vb[s] = device.makeBuffer(length: d.capV[s] * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        }
        if m.indices.count > d.capI[s] {
            d.capI[s] = m.indices.count + 4096
            d.ib[s] = device.makeBuffer(length: d.capI[s] * 4, options: .storageModeShared)
        }
        m.vertices.withUnsafeBytes { d.vb[s]?.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        m.indices.withUnsafeBytes { d.ib[s]?.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    }

    /// Replaces the dining meshes (world space). Called only when they changed.
    func setDining(_ f: DiningFrame) {
        upload(f.opaque, into: &diningOpaque)
        upload(f.translucent, into: &diningTranslucent)
        diningVertexCount = f.opaque.vertices.count + f.translucent.vertices.count
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for mesh in [f.opaque, f.translucent] { for v in mesh.vertices {
            let p = SIMD3(v.pos.x, v.pos.y, v.pos.z)
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        } }
        trayBounds = diningVertexCount > 0 ? (lo, hi) : nil
    }

    /// Replaces the resting decor (world space). Invalidates the room cache.
    func setDecorStatic(_ m: RoomMesh) {
        staticVersion &+= 1
        decorIndexCount = m.indices.count
        guard decorIndexCount > 0 else { return }
        decorVB = device.makeBuffer(bytes: m.vertices, length: m.vertices.count * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        decorIB = device.makeBuffer(bytes: m.indices, length: m.indices.count * 4, options: .storageModeShared)
        decorVB?.label = "decor vertices"; decorIB?.label = "decor indices"
    }
    /// Replaces the garden plots' plants (world space). Invalidates the room cache. An empty mesh clears them.
    func setGardenPlants(_ m: RoomMesh) {
        staticVersion &+= 1
        gardenIndexCount = m.indices.count
        guard gardenIndexCount > 0 else { return }
        gardenVB = device.makeBuffer(bytes: m.vertices, length: m.vertices.count * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        gardenIB = device.makeBuffer(bytes: m.indices, length: m.indices.count * 4, options: .storageModeShared)
        gardenVB?.label = "garden plants vertices"; gardenIB?.label = "garden plants indices"
    }
    /// Replaces the garden's moving things (world space, per frame). An empty mesh clears them.
    func setGardenLive(_ m: RoomMesh) {
        upload(m, into: &gardenLive)
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in m.vertices { let p = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        gardenBounds = m.vertices.isEmpty ? nil : (lo, hi)
    }

    /// Replaces the animating decor (world space, per frame). An empty mesh clears it.
    func setDecorActive(_ m: RoomMesh) {
        upload(m, into: &decorActive)
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in m.vertices { let p = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        decorBounds = m.vertices.isEmpty ? nil : (lo, hi)
    }
    var decorActiveVertexCount: Int { decorBounds == nil ? 0 : 1 }

    /// Replaces the worn pieces (world space). Empty meshes clear them.
    func setWear(opaque: RoomMesh, translucent: RoomMesh, bounds: [(lo: SIMD3<Float>, hi: SIMD3<Float>)]) {
        upload(opaque, into: &wearOpaque)
        upload(translucent, into: &wearTranslucent)
        wearBounds = bounds
    }
    var wearVertexCount: Int { wearOpaque.indexCount }

    /// Replaces the worn shoes (world space). An empty mesh clears them.
    func setShoes(_ m: RoomMesh) { upload(m, into: &shoeMesh) }

    /// Replaces the sleep masks / puffs (world space). An empty frame clears them.
    func setMasks(opaque: RoomMesh, translucent: RoomMesh) {
        upload(opaque, into: &maskOpaque)
        upload(translucent, into: &maskTranslucent)
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for mesh in [opaque, translucent] { for v in mesh.vertices {
            let p = SIMD3(v.pos.x, v.pos.y, v.pos.z)
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        } }
        maskBounds = opaque.vertices.count + translucent.vertices.count > 0 ? (lo, hi) : nil
    }

    private func rebuild() {
        staticVersion &+= 1
        let m = RoomGeometry.build(theme: theme)
        indexCount = m.indices.count
        vertexBuffer = device.makeBuffer(bytes: m.vertices, length: m.vertices.count * MemoryLayout<RoomVertex>.stride, options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: m.indices, length: m.indices.count * 4, options: .storageModeShared)
        vertexBuffer?.label = "room vertices"; indexBuffer?.label = "room indices"
    }

    private func makeUniforms(viewProj: simd_float4x4, camPos: SIMD3<Float>, lightViewProj: simd_float4x4?, shadowTex: MTLTexture?,
                              topViewProj: simd_float4x4?) -> RoomUniforms {
        let sw = theme.swatches
        var u = RoomUniforms()
        u.viewProj = viewProj
        u.lightVP = lightViewProj ?? matrix_identity_float4x4
        u.topVP = topViewProj ?? matrix_identity_float4x4
        u.camPos = SIMD4(camPos, (lightViewProj != nil && shadowTex != nil) ? 1 : 0)
        u.keyDir = SIMD4(keyDir, keyIntensity)
        u.rug = SIMD4(RoomLayout.rugCentre.x, RoomLayout.rugCentre.y, RoomLayout.rugRadius, 0)
        u.bounds = SIMD4(RoomLayout.minX, RoomLayout.maxX, RoomLayout.minZ, RoomLayout.maxZ)
        u.fog = SIMD4(fog.x, fog.y, fog.z, 0)
        u.sky0 = daylight.sky0; u.sky1 = daylight.sky1; u.keyCol = daylight.keyCol; u.ambCol = daylight.ambCol
        u.lamp = daylight.lamp; u.lampPos = daylight.lampPos
        if followsRoom {
            let d = RoomLayout.current
            u.lampPos = SIMD4(d.lamp, daylight.lampPos.w)
            u.style = SIMD4(Float(d.floor.rawValue), Float(d.wall.rawValue), Float(d.rug.rawValue), 0)
            u.win = SIMD4(d.windows.y0, d.windows.y1 - d.windows.y0, 0, 0)
        }
        u.pal0 = SIMD4(sw[0], 1); u.pal1 = SIMD4(sw[1], 1); u.pal2 = SIMD4(sw[2], 1); u.pal3 = SIMD4(sw[3], 1); u.pal4 = SIMD4(sw[4], 1)
        return u
    }

    /// Which opaque parts `encode` draws: the static room (+ care props) can be cached, the dining tray is per-frame.
    enum Parts { case all, staticOnly, diningOnly }

    func encode(_ enc: MTLRenderCommandEncoder, viewProj: simd_float4x4, camPos: SIMD3<Float>,
                lightViewProj: simd_float4x4?, shadowTex: MTLTexture?,
                topViewProj: simd_float4x4? = nil, heightTex: MTLTexture? = nil, parts: Parts = .all) {
        ensureBuilt()
        if bathVisible {
            // the bathroom replaces the living room (static: cached like the room); dining pieces do not exist in the bath
            if parts != .diningOnly, let pipe = bathOpaquePipeline, let vb = bathSetVB, let ib = bathSetIB, bathSetIndexCount > 0 {
                var bu = makeBathUniforms(viewProj: viewProj, camPos: camPos, lightViewProj: lightViewProj, shadow: lightViewProj != nil && shadowTex != nil)
                enc.pushDebugGroup("bath")
                enc.setRenderPipelineState(pipe)
                enc.setDepthStencilState(depthState)
                enc.setFrontFacing(.counterClockwise)
                enc.setCullMode(.back)
                enc.setVertexBuffer(vb, offset: 0, index: 1)
                enc.setVertexBytes(&bu, length: MemoryLayout<BathSetUniforms>.stride, index: 0)
                enc.setFragmentBytes(&bu, length: MemoryLayout<BathSetUniforms>.stride, index: 0)
                enc.setFragmentTexture(shadowTex ?? dummyShadow, index: 0)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: bathSetIndexCount, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
                enc.popDebugGroup()
            }
            return
        }
        if raceVisible || showVisible {
            // the track (or the show's stage) replaces the room (static: cached like the room); no props, no dining tray out there
            let onStage = showVisible && !raceVisible
            guard let vb = onStage ? showVB : raceVB, let ib = onStage ? showIB : raceIB, (onStage ? showIndexCount : raceIndexCount) > 0 else { return }
            let indexCount = onStage ? showIndexCount : raceIndexCount
            var u = makeUniforms(viewProj: viewProj, camPos: camPos, lightViewProj: lightViewProj, shadowTex: shadowTex, topViewProj: topViewProj)
            if onStage { u.pal2 = SIMD4(ShowModels.swatch2, 1); u.pal3 = SIMD4(ShowModels.swatch3, 1); u.pal4 = SIMD4(ShowModels.swatch4, 1); u.fog = SIMD4(ShowModels.fog, 0) }
            else { u.pal2 = SIMD4(RaceModels.swatch2, 1); u.pal3 = SIMD4(RaceModels.swatch3, 1); u.pal4 = SIMD4(RaceModels.swatch4, 1) }
            u.lamp.w = 0
            u.style = .zero; u.win = SIMD4(1.5, 2.8, 0, 0)
            enc.pushDebugGroup(onStage ? "show stage" : "race track")
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBuffer(shoeTable, offset: 0, index: 2)
            enc.setDepthStencilState(depthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.back)
            enc.setVertexBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
            enc.setFragmentTexture(shadowTex ?? dummyShadow, index: 0)
            enc.setFragmentTexture(heightTex ?? dummyShadow, index: 1)
            if parts != .diningOnly {
                enc.setVertexBuffer(vb, offset: 0, index: 1)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
            }
            if parts != .staticOnly {          // the racers' shoes and numbered bibs, hats and the rest of what they wear stand on the track too
                for (label, d) in [("shoes", shoeMesh), ("wardrobe", wearOpaque)] where d.indexCount > 0 {
                    guard let dv = d.vb[d.slot], let di = d.ib[d.slot] else { continue }
                    enc.pushDebugGroup(label)
                    enc.setVertexBuffer(dv, offset: 0, index: 1)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: d.indexCount, indexType: .uint32, indexBuffer: di, indexBufferOffset: 0)
                    enc.popDebugGroup()
                }
            }
            enc.popDebugGroup()
            return
        }
        guard let vb = vertexBuffer, let ib = indexBuffer, indexCount > 0 else { return }
        var u = makeUniforms(viewProj: viewProj, camPos: camPos, lightViewProj: lightViewProj, shadowTex: shadowTex, topViewProj: topViewProj)
        enc.pushDebugGroup("room")
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBuffer(shoeTable, offset: 0, index: 2)
        enc.setDepthStencilState(depthState)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setVertexBuffer(vb, offset: 0, index: 1)
        enc.setVertexBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
        enc.setFragmentTexture(shadowTex ?? dummyShadow, index: 0)
        enc.setFragmentTexture(heightTex ?? dummyShadow, index: 1)
        if parts != .diningOnly {
        enc.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
        if propIndexCount > 0, let pv = propVB, let pi = propIB {
            enc.setVertexBuffer(pv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: propIndexCount, indexType: .uint32, indexBuffer: pi, indexBufferOffset: 0)
        }
        if gardenIndexCount > 0, let gv = gardenVB, let gi = gardenIB {
            enc.pushDebugGroup("garden plants")
            enc.setVertexBuffer(gv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: gardenIndexCount, indexType: .uint32, indexBuffer: gi, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        if decorIndexCount > 0, let dv = decorVB, let di = decorIB {
            enc.pushDebugGroup("decor")
            enc.setVertexBuffer(dv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: decorIndexCount, indexType: .uint32, indexBuffer: di, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        }
        if parts != .staticOnly, decorActive.indexCount > 0, let dv = decorActive.vb[decorActive.slot], let di = decorActive.ib[decorActive.slot] {
            enc.pushDebugGroup("decor (animating)")
            enc.setVertexBuffer(dv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: decorActive.indexCount, indexType: .uint32, indexBuffer: di, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        if parts != .staticOnly, gardenLive.indexCount > 0, let gv = gardenLive.vb[gardenLive.slot], let gi = gardenLive.ib[gardenLive.slot] {
            enc.pushDebugGroup("garden live")
            enc.setVertexBuffer(gv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: gardenLive.indexCount, indexType: .uint32, indexBuffer: gi, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        if parts != .staticOnly, diningOpaque.indexCount > 0, let dv = diningOpaque.vb[diningOpaque.slot], let di = diningOpaque.ib[diningOpaque.slot] {
            enc.pushDebugGroup("dining")
            enc.setVertexBuffer(dv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: diningOpaque.indexCount, indexType: .uint32, indexBuffer: di, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        if parts != .staticOnly, maskOpaque.indexCount > 0, let mv = maskOpaque.vb[maskOpaque.slot], let mi = maskOpaque.ib[maskOpaque.slot] {
            enc.pushDebugGroup("sleep mask")
            enc.setVertexBuffer(mv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: maskOpaque.indexCount, indexType: .uint32, indexBuffer: mi, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        if parts != .staticOnly, shoeMesh.indexCount > 0, let sv = shoeMesh.vb[shoeMesh.slot], let si = shoeMesh.ib[shoeMesh.slot] {
            enc.pushDebugGroup("shoes")
            enc.setVertexBuffer(sv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: shoeMesh.indexCount, indexType: .uint32, indexBuffer: si, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        if parts != .staticOnly, wearOpaque.indexCount > 0, let wv = wearOpaque.vb[wearOpaque.slot], let wi = wearOpaque.ib[wearOpaque.slot] {
            enc.pushDebugGroup("wardrobe")
            enc.setVertexBuffer(wv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: wearOpaque.indexCount, indexType: .uint32, indexBuffer: wi, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        enc.popDebugGroup()
    }

    /// Translucent dining pieces (puffs, contact shadows). Call AFTER Bob is drawn, in the same pass, so a puff over his body blends
    /// on top of him. Sets its own pipeline / depth / cull state and buffers.
    func encodeBlended(_ enc: MTLRenderCommandEncoder, viewProj: simd_float4x4, camPos: SIMD3<Float>,
                       lightViewProj: simd_float4x4?, shadowTex: MTLTexture?, topViewProj: simd_float4x4? = nil, heightTex: MTLTexture? = nil) {
        for d in (bathVisible || raceVisible || showVisible) ? [diningTranslucent, wearTranslucent] : [diningTranslucent, maskTranslucent, wearTranslucent] {
        if d.indexCount > 0, let dv = d.vb[d.slot], let di = d.ib[d.slot] {
            var u = makeUniforms(viewProj: viewProj, camPos: camPos, lightViewProj: lightViewProj, shadowTex: shadowTex, topViewProj: topViewProj)
            enc.pushDebugGroup("dining puff")
            enc.setRenderPipelineState(blendPipeline)
            enc.setFragmentBuffer(shoeTable, offset: 0, index: 2)
            enc.setDepthStencilState(blendDepthState)
            enc.setFrontFacing(.counterClockwise)
            enc.setCullMode(.back)
            enc.setVertexBuffer(dv, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
            enc.setFragmentTexture(shadowTex ?? dummyShadow, index: 0)
            enc.setFragmentTexture(heightTex ?? dummyShadow, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: d.indexCount, indexType: .uint32, indexBuffer: di, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        }
        // bath: the water over Bob's ankles, then dirt / tool / bubbles / spray (no shadow lookups: they sit on his own surface)
        guard let pipe = bathBlendPipeline else { return }
        let wantWater = bathVisible && bathWaterIndexCount > 0
        let wantOverlay = bathOvIndexCount > 0
        guard wantWater || wantOverlay else { return }
        var bu = makeBathUniforms(viewProj: viewProj, camPos: camPos, lightViewProj: lightViewProj, shadow: false)
        enc.pushDebugGroup("bath overlay")
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(blendDepthState)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setVertexBytes(&bu, length: MemoryLayout<BathSetUniforms>.stride, index: 0)
        enc.setFragmentBytes(&bu, length: MemoryLayout<BathSetUniforms>.stride, index: 0)
        enc.setFragmentTexture(dummyShadow, index: 0)
        if wantWater, let wv = bathWaterVB, let wi = bathWaterIB {
            enc.setVertexBuffer(wv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: bathWaterIndexCount, indexType: .uint32, indexBuffer: wi, indexBufferOffset: 0)
        }
        if wantOverlay, let ov = bathOvVB[bathOvSlot], let oi = bathOvIB[bathOvSlot] {
            enc.setVertexBuffer(ov, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: bathOvIndexCount, indexType: .uint32, indexBuffer: oi, indexBufferOffset: 0)
        }
        enc.popDebugGroup()
    }

}

/// Mirrors `BathSetU` in BathShaders.metal (2 matrices + 6 float4 = 224 bytes).
struct BathSetUniforms {
    var viewProj = matrix_identity_float4x4
    var lightVP = matrix_identity_float4x4
    var camPos = SIMD4<Float>(repeating: 0)     // xyz, w = shadow map valid
    var keyDir = SIMD4<Float>(repeating: 0)     // xyz toward the light, w = intensity
    var misc = SIMD4<Float>(repeating: 0)       // time, water height, ripple centre x, z
    var sky = SIMD4<Float>(repeating: 0)
    var ground = SIMD4<Float>(repeating: 0)
    var fog = SIMD4<Float>(repeating: 0)
}
