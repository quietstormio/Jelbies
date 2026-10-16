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
}

nonisolated final class RoomRenderer {
    /// Same direction as the jelly's key light (CameraRig.keyDir).
    static let defaultKeyDir = simd_normalize(SIMD3<Float>(-0.5, 0.8, 0.55))

    var theme: RoomTheme { didSet { if theme != oldValue { rebuild() } } }
    var keyDir = RoomRenderer.defaultKeyDir
    var keyIntensity: Float = 1.6
    /// Depth fog: start, end, max amount. The game camera is ~15 units from the room centre, so it pushes this out.
    var fog = SIMD3<Float>(3, 9, 0.35)

    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let blendPipeline: MTLRenderPipelineState
    private let blendDepthState: MTLDepthStencilState
    private let dummyShadow: MTLTexture
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
    }

    // Movable props (care bowls): a small shared buffer rewritten only when the props change.
    private var propVB: MTLBuffer?, propIB: MTLBuffer?
    private var propIndexCount = 0
    private var propCapV = 0, propCapI = 0
    var props: [RoomProp] = [] {
        didSet {
            guard props != oldValue else { return }
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
    }

    private func rebuild() {
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
        u.pal0 = SIMD4(sw[0], 1); u.pal1 = SIMD4(sw[1], 1); u.pal2 = SIMD4(sw[2], 1); u.pal3 = SIMD4(sw[3], 1); u.pal4 = SIMD4(sw[4], 1)
        return u
    }

    func encode(_ enc: MTLRenderCommandEncoder, viewProj: simd_float4x4, camPos: SIMD3<Float>,
                lightViewProj: simd_float4x4?, shadowTex: MTLTexture?,
                topViewProj: simd_float4x4? = nil, heightTex: MTLTexture? = nil) {
        guard let vb = vertexBuffer, let ib = indexBuffer, indexCount > 0 else { return }
        var u = makeUniforms(viewProj: viewProj, camPos: camPos, lightViewProj: lightViewProj, shadowTex: shadowTex, topViewProj: topViewProj)
        enc.pushDebugGroup("room")
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depthState)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setVertexBuffer(vb, offset: 0, index: 1)
        enc.setVertexBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
        enc.setFragmentTexture(shadowTex ?? dummyShadow, index: 0)
        enc.setFragmentTexture(heightTex ?? dummyShadow, index: 1)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
        if propIndexCount > 0, let pv = propVB, let pi = propIB {
            enc.setVertexBuffer(pv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: propIndexCount, indexType: .uint32, indexBuffer: pi, indexBufferOffset: 0)
        }
        if diningOpaque.indexCount > 0, let dv = diningOpaque.vb[diningOpaque.slot], let di = diningOpaque.ib[diningOpaque.slot] {
            enc.pushDebugGroup("dining")
            enc.setVertexBuffer(dv, offset: 0, index: 1)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: diningOpaque.indexCount, indexType: .uint32, indexBuffer: di, indexBufferOffset: 0)
            enc.popDebugGroup()
        }
        enc.popDebugGroup()
    }

    /// Translucent dining pieces (puffs, contact shadows). Call AFTER Bob is drawn, in the same pass, so a puff over his body blends
    /// on top of him. Sets its own pipeline / depth / cull state and buffers.
    func encodeBlended(_ enc: MTLRenderCommandEncoder, viewProj: simd_float4x4, camPos: SIMD3<Float>,
                       lightViewProj: simd_float4x4?, shadowTex: MTLTexture?, topViewProj: simd_float4x4? = nil, heightTex: MTLTexture? = nil) {
        guard diningTranslucent.indexCount > 0, let dv = diningTranslucent.vb[diningTranslucent.slot], let di = diningTranslucent.ib[diningTranslucent.slot] else { return }
        var u = makeUniforms(viewProj: viewProj, camPos: camPos, lightViewProj: lightViewProj, shadowTex: shadowTex, topViewProj: topViewProj)
        enc.pushDebugGroup("dining puff")
        enc.setRenderPipelineState(blendPipeline)
        enc.setDepthStencilState(blendDepthState)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setVertexBuffer(dv, offset: 0, index: 1)
        enc.setVertexBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<RoomUniforms>.stride, index: 0)
        enc.setFragmentTexture(shadowTex ?? dummyShadow, index: 0)
        enc.setFragmentTexture(heightTex ?? dummyShadow, index: 1)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: diningTranslucent.indexCount, indexType: .uint32, indexBuffer: di, indexBufferOffset: 0)
        enc.popDebugGroup()
    }

}
