import XCTest
import Metal
import simd
import ImageIO
import UniformTypeIdentifiers
@testable import BobV1

final class RoomTests: XCTestCase {
    func testPaletteMonotonicAndInGamut() {
        for tint in [RoomTheme.defaultTint, SIMD3<Float>(0.3, 0.6, 0.9), SIMD3<Float>(0.5, 0.5, 0.5)] {
            let t = RoomTheme(tint: tint)
            var prevL: Float = -1
            for i in 0..<5 {
                let c = t.swatch(i)
                XCTAssert(c.x >= 0 && c.y >= 0 && c.z >= 0 && c.x <= 1.0001 && c.y <= 1.0001 && c.z <= 1.0001, "swatch \(i) out of gamut \(c)")
                let L = OKLab.fromLinear(c).x
                XCTAssertGreaterThan(L, prevL)
                XCTAssertEqual(L, RoomTheme.lightness[i], accuracy: 0.01)
                prevL = L
            }
        }
        let lab = SIMD3<Float>(0.7, 0.05, -0.03)
        let back = OKLab.fromLinear(OKLab.toLinear(lab))
        XCTAssertLessThan(simd_length(back - lab), 1e-3)
    }

    func testMeshValidity() {
        let m = RoomGeometry.build(theme: RoomTheme())
        XCTAssertGreaterThan(m.vertices.count, 1000)
        XCTAssertEqual(m.indices.count % 3, 0)
        for v in m.vertices {
            XCTAssert(v.pos.x.isFinite && v.pos.y.isFinite && v.pos.z.isFinite)
            let n = SIMD3(v.normal.x, v.normal.y, v.normal.z)
            XCTAssertEqual(simd_length(n), 1, accuracy: 1e-3)
            XCTAssert(v.normal.w >= 0 && v.normal.w <= 1)
            XCTAssert(v.color.x.isFinite)
        }
        var badWinding = 0
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let i = (0..<3).map { Int(m.indices[t + $0]) }
            XCTAssert(i.allSatisfy { $0 < m.vertices.count })
            let p = i.map { SIMD3(m.vertices[$0].pos.x, m.vertices[$0].pos.y, m.vertices[$0].pos.z) }
            let g = simd_cross(p[1] - p[0], p[2] - p[0])
            let n = i.reduce(SIMD3<Float>(repeating: 0)) { $0 + SIMD3(m.vertices[$1].normal.x, m.vertices[$1].normal.y, m.vertices[$1].normal.z) }
            if simd_dot(g, n) <= 0 { badWinding += 1 }
        }
        XCTAssertEqual(badWinding, 0)
    }

    func testLayout() {
        XCTAssertEqual(RoomLayout.floorY, 0)
        for w in RoomLayout.walls { XCTAssertEqual(simd_length(w.normal), 1, accuracy: 1e-6) }
        // rug fits in room and clear of the sofa
        let r = RoomLayout.rugRadius
        XCTAssertGreaterThan(RoomLayout.rugCentre.x - r, RoomLayout.minX)
        XCTAssertLessThan(RoomLayout.rugCentre.x + r, RoomLayout.maxX)
        XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(SIMD2(0, -r)), 0.3)
        // a blob pushed into the sofa / wall / plant ends up outside them
        let R: Float = 0.8
        for start in [SIMD3<Float>(0, 0.6, -3.5), SIMD3<Float>(-9, 0.6, 0), SIMD3<Float>(-4.2, 0.6, -4.2), SIMD3<Float>(3.7, 0.6, -4.0)] {
            let p = RoomLayout.resolve(position: start, radius: R)
            XCTAssertGreaterThanOrEqual(p.x, RoomLayout.minX + R - 1e-3)
            XCTAssertGreaterThanOrEqual(p.z, RoomLayout.minZ + R - 1e-3)
            XCTAssertGreaterThanOrEqual(RoomLayout.sofaDistanceXZ(SIMD2(p.x, p.z)), R - 1e-2)
            for c in RoomLayout.cylinders { XCTAssertGreaterThanOrEqual(simd_length(SIMD2(p.x, p.z) - c.centre), c.radius + R - 1e-2) }
        }
        let inside = SIMD3<Float>(1, 0.6, 0.5)
        XCTAssertEqual(RoomLayout.resolve(position: inside, radius: R), inside)
        let cam = RoomCamera.make(aspect: 0.46)
        XCTAssert(cam.eye.y > 2 && cam.eye.z > 5)
    }

    /// Renders the room offscreen and writes a PNG for eyeballing.
    func testRenderScreenshot() throws {
        let dev = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let lib = try XCTUnwrap(dev.makeDefaultLibrary(bundle: Bundle(for: RoomRenderer.self)))
        let color = MTLPixelFormat.rgba8Unorm_srgb
        let room = try XCTUnwrap(RoomRenderer(device: dev, library: lib, colorFormat: color, depthFormat: .depth32Float, sampleCount: 4))
        for (name, w, h) in [("room", 780, 1688), ("room_land", 1600, 900)] {
            func tex(_ f: MTLPixelFormat, _ ms: Bool, _ usage: MTLTextureUsage) -> MTLTexture {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
                d.usage = usage; d.storageMode = .private
                if ms { d.textureType = .type2DMultisample; d.sampleCount = 4 }
                return dev.makeTexture(descriptor: d)!
            }
            let msC = tex(color, true, .renderTarget), msD = tex(.depth32Float, true, .renderTarget)
            let rd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: color, width: w, height: h, mipmapped: false)
            rd.usage = [.renderTarget, .shaderRead]; rd.storageMode = .shared
            let resolve = dev.makeTexture(descriptor: rd)!
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = msC; rp.colorAttachments[0].resolveTexture = resolve
            rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
            rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rp.depthAttachment.texture = msD; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 1
            rp.depthAttachment.storeAction = .dontCare
            let q = dev.makeCommandQueue()!
            let cmd = q.makeCommandBuffer()!
            let enc = cmd.makeRenderCommandEncoder(descriptor: rp)!
            let cam = RoomCamera.viewProj(aspect: Float(w) / Float(h))
            room.encode(enc, viewProj: cam.viewProj, camPos: cam.eye, lightViewProj: nil, shadowTex: nil)
            enc.endEncoding()
            cmd.commit(); cmd.waitUntilCompleted()
            XCTAssertEqual(cmd.status, .completed, "\(String(describing: cmd.error))")

            var px = [UInt8](repeating: 0, count: w * h * 4)
            resolve.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let img = ctx.makeImage()!
            let url = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/\(name).png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, img, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }
}
