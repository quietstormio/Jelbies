//
//  GfxUpscaler.swift
//  Thin wrapper over MTLFXSpatialScaler (MetalFX). MetalFX does not exist in the iOS Simulator SDK, so everything is behind
//  `#if canImport(MetalFX) && !targetEnvironment(simulator)`; elsewhere `make` returns nil and the renderer draws natively.
//

import Metal

#if canImport(MetalFX) && !targetEnvironment(simulator)
import MetalFX

nonisolated final class GfxUpscaler {
    static let compiledIn = true
    static func supported(_ device: MTLDevice) -> Bool { MTLFXSpatialScalerDescriptor.supportsDevice(device) }

    let inW: Int, inH: Int, outW: Int, outH: Int
    private let scaler: MTLFXSpatialScaler
    let input: MTLTexture
    let output: MTLTexture

    /// `format` = the drawable's pixel format (post tone-maps into `input`, MetalFX writes `output`, a copy pass presents it).
    static func make(device: MTLDevice, format: MTLPixelFormat, inW: Int, inH: Int, outW: Int, outH: Int) -> GfxUpscaler? {
        guard supported(device) else { return nil }
        let d = MTLFXSpatialScalerDescriptor()
        d.inputWidth = inW; d.inputHeight = inH; d.outputWidth = outW; d.outputHeight = outH
        d.colorTextureFormat = format; d.outputTextureFormat = format
        d.colorProcessingMode = .perceptual            // post writes display-encoded (sRGB OETF) values
        guard let s = d.makeSpatialScaler(device: device) else { return nil }
        let a = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: inW, height: inH, mipmapped: false)
        a.usage = [.renderTarget, .shaderRead]; a.storageMode = .private
        let b = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: outW, height: outH, mipmapped: false)
        b.usage = [.shaderWrite, .shaderRead, .renderTarget]; b.storageMode = .private
        guard let i = device.makeTexture(descriptor: a), let o = device.makeTexture(descriptor: b) else { return nil }
        i.label = "metalfx in"; o.label = "metalfx out"
        return GfxUpscaler(inW, inH, outW, outH, s, i, o)
    }

    private init(_ iw: Int, _ ih: Int, _ ow: Int, _ oh: Int, _ s: MTLFXSpatialScaler, _ i: MTLTexture, _ o: MTLTexture) {
        inW = iw; inH = ih; outW = ow; outH = oh; scaler = s; input = i; output = o
    }

    func encode(_ cmd: MTLCommandBuffer) {
        scaler.colorTexture = input
        scaler.outputTexture = output
        scaler.inputContentWidth = inW; scaler.inputContentHeight = inH
        scaler.encode(commandBuffer: cmd)
    }
}
#else
nonisolated final class GfxUpscaler {
    static let compiledIn = false
    static func supported(_ device: MTLDevice) -> Bool { false }
    let inW = 0, inH = 0, outW = 0, outH = 0
    let input: MTLTexture
    let output: MTLTexture
    static func make(device: MTLDevice, format: MTLPixelFormat, inW: Int, inH: Int, outW: Int, outH: Int) -> GfxUpscaler? { nil }
    private init(_ i: MTLTexture, _ o: MTLTexture) { input = i; output = o }
    func encode(_ cmd: MTLCommandBuffer) {}
}
#endif
