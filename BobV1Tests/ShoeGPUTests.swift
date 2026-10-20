//
//  ShoeGPUTests.swift
//  The per-pixel shoe paint: the spec table and the vertices that feed it (the fragment shader itself is judged by the captures).
//

import XCTest
import simd
@testable import BobV1

final class ShoeGPUTests: XCTestCase {
    func testTableHasEveryLookWithItsLayers() {
        XCTAssertEqual(ShoeGPU.table.count, WearLook.shoes.count * ShoeGPU.lookStride)
        for (i, look) in WearLook.shoes.enumerated() {
            let n = Int(ShoeGPU.table[i * ShoeGPU.lookStride].w)
            XCTAssertEqual(n, min(ShoePaint.style(look)?.layers.count ?? 0, ShoeGPU.maxLayers), "\(look)")
            XCTAssertGreaterThan(n, 4)
            XCTAssertLessThanOrEqual(ShoePaint.style(look)?.layers.count ?? 0, ShoeGPU.maxLayers, "\(look): raise maxLayers")
        }
    }

    func testGpuVerticesCarryCoordinatesLookAndBody() {
        let bean = FootBean.localF
        for look in WearLook.shoes {
            let body = SIMD3<Float>(0.2, 0.4, 0.8)
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.buildShell(look, bean: bean, floorY: -10, body: body, time: 0.3, gpuPaint: true, into: b)
            XCTAssertEqual(b.mesh.vertices.count, FootBean.vertexCount + ShoeModel.sub.mids.count)
            for v in b.mesh.vertices {
                XCTAssertEqual(v.pos.w, ShoeGPU.material(look))
                XCTAssertTrue((0...1).contains(v.color.x) && (0...1).contains(v.color.y) && (0...1).contains(v.color.z), "\(look): paint coordinates in 0...1")
            }
            // the body colour round-trips through the 3 sRGB bytes
            let p = Int(b.mesh.vertices[0].normal.w)
            func dec(_ x: Int) -> Float { let c = Float(x) / 255; return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
            XCTAssertEqual(dec((p >> 16) & 255), body.x, accuracy: 0.01)
            XCTAssertEqual(dec((p >> 8) & 255), body.y, accuracy: 0.01)
            XCTAssertEqual(dec(p & 255), body.z, accuracy: 0.01)
        }
    }

    /// The shell geometry is the same whichever way it is painted (attachment is unchanged).
    func testGeometryIsIdenticalToTheVertexPaintedShell() {
        let bean = FootBean.localF
        let a = RoomMeshBuilder(), b = RoomMeshBuilder()
        ShoeModel.buildShell(.sneakerMint, bean: bean, floorY: -10, into: a)
        ShoeModel.buildShell(.sneakerMint, bean: bean, floorY: -10, gpuPaint: true, into: b)
        XCTAssertEqual(a.mesh.indices, b.mesh.indices)
        for (x, y) in zip(a.mesh.vertices, b.mesh.vertices) { XCTAssertEqual(x.pos.x, y.pos.x); XCTAssertEqual(x.pos.y, y.pos.y); XCTAssertEqual(x.pos.z, y.pos.z) }
    }
}
