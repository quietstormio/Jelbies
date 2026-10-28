//
//  ShoeDumpTests.swift
//  Dev tool (skipped unless SHOE_DUMP_DIR is set): writes the foot bean's rest shape (foot-local: sole plane y = 0, footprint centre at the origin, toe +z)
//  as foot_bean.json for tools/shoes/convert_shoe_art.py (the Blender shoe modelling and the shoe -> bean binding both need it). Also the store-thumbnail
//  before / after sheet (SHOE_THUMB_DIR) and the per-frame cost of the shoes, old shell vs modelled (SHOE_PERF=1).
//

import XCTest
import simd
import UIKit
import QuartzCore
@testable import BobV1

@MainActor
final class ShoeDumpTests: XCTestCase {
    func testDumpFootBean() throws {
        guard let d = ProcessInfo.processInfo.environment["SHOE_DUMP_DIR"], !d.isEmpty else { throw XCTSkip("SHOE_DUMP_DIR not set") }
        let p = FootBean.localF
        let n = ShoeModel.normals(p)
        let inside: [Double] = FootBean.local.pos.map { q in BobForm.sdf(SIMD3(BobForm.footX + q.x, q.y, BobForm.footZ + q.z)) }
        let ball = FootBean.ballF
        let obj: [String: Any] = [
            "pos": p.map { [Double($0.x), Double($0.y), Double($0.z)] },
            "nrm": n.map { [Double($0.x), Double($0.y), Double($0.z)] },
            "ball": ball.map { [Double($0.x), Double($0.y), Double($0.z)] },
            "bodySDF": inside,
            "tris": FootBean.triangles(firstVertex: 0).map { Int($0) },
            "around": FootBean.around, "rings": FootBean.rings,
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        try data.write(to: URL(fileURLWithPath: d + "/foot_bean.json"))
    }

    /// The shop thumbnails of the nine shoes: BEFORE (the procedural dome on a whole bean, as the shop drew it) above AFTER (the modelled pair).
    func testCaptureShoeThumbnails() throws {
        guard let d = ProcessInfo.processInfo.environment["SHOE_THUMB_DIR"], !d.isEmpty else { throw XCTSkip("SHOE_THUMB_DIR not set") }
        let side: CGFloat = 300
        func oldMesh(_ look: WearLook) -> RoomMesh {
            let b = RoomMeshBuilder(); b.material = .plain
            let bean = FootBean.localF
            let n = ShoeModel.normals(bean)
            let base = UInt32(b.mesh.vertices.count)
            let body = OKLab.srgbToLinear(SIMD3(0.50, 0.68, 0.95))
            for i in bean.indices { b.vertex(bean[i], n[i], ao: 1, color: body) }
            var t = 0
            while t + 2 < ShoeModel.tris.count { b.triangle(base + ShoeModel.tris[t], base + ShoeModel.tris[t + 1], base + ShoeModel.tris[t + 2]); t += 3 }
            ShoeArt.forceProcedural = true; defer { ShoeArt.forceProcedural = false }
            ShoeModel.build(look, bean: bean, floorY: -10, time: 1.3, side: 0, into: b)
            return b.mesh
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let looks = WearLook.shoes
        let bar: CGFloat = 36
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: side * CGFloat(looks.count), height: (side + bar) * 2), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side * CGFloat(looks.count), height: (side + bar) * 2))
            for (k, look) in looks.enumerated() {
                for row in 0..<2 {
                    let mesh = row == 0 ? oldMesh(look) : StoreThumb.shoeMesh(look)
                    let (yaw, pitch): (Float, Float) = row == 0 ? (0.6, 0.25) : (0.55, 0.36)
                    let img = StoreThumb.image("shoe4-\(row)-\(look.rawValue)", mesh: mesh, size: side, yaw: yaw, pitch: pitch)
                    let x = side * CGFloat(k), y = (side + bar) * CGFloat(row)
                    UIColor(red: 0.93, green: 0.86, blue: 0.76, alpha: 1).setFill(); ctx.fill(CGRect(x: x, y: y + bar, width: side, height: side))
                    img?.draw(in: CGRect(x: x, y: y + bar, width: side, height: side))
                    ("\(row == 0 ? "BEFORE" : "AFTER") \(look.title)" as NSString).draw(at: CGPoint(x: x + 8, y: y + 8), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white])
                }
            }
        }
        try sheet.pngData()!.write(to: URL(fileURLWithPath: d + "/shoes4_thumbs_before_after.png"))
        // one big AFTER thumbnail per shoe too (the store card is small; these show the detail)
        for look in looks {
            if let big = StoreThumb.image("shoe4-big-\(look.rawValue)", mesh: StoreThumb.shoeMesh(look), size: 600, yaw: 0.55, pitch: 0.36) {
                let out = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: fmt).image { ctx in
                    UIColor(red: 0.93, green: 0.86, blue: 0.76, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600)); big.draw(at: .zero)
                }
                try out.pngData()!.write(to: URL(fileURLWithPath: d + "/shoes4_thumb_\(look.rawValue).png"))
            }
        }
    }

    /// The cost of the shoes: building the six feet of three wearers every frame (the worst case: all of them moving), old procedural shell vs the modelled shoes.
    func testShoePerformanceOldVsModelled() throws {
        guard ProcessInfo.processInfo.environment["SHOE_PERF"] == "1" else { throw XCTSkip("SHOE_PERF not set") }
        let bean = FootBean.localF.map { SIMD3($0.x + 0.3, $0.y, $0.z) }
        func run(_ procedural: Bool, _ look: WearLook) -> (ms: Double, verts: Int, tris: Int) {
            ShoeArt.forceProcedural = procedural; defer { ShoeArt.forceProcedural = false }
            var verts = 0, tris = 0
            let n = 600
            for _ in 0..<30 { let b = RoomMeshBuilder(); b.material = .plain; ShoeModel.build(look, bean: bean, floorY: 0, time: 0, side: 0, gpuPaint: true, into: b) }
            let t0 = CACurrentMediaTime()
            for k in 0..<n {
                for s in 0..<2 {
                    let b = RoomMeshBuilder(); b.material = .plain
                    ShoeModel.build(look, bean: bean, floorY: 0, time: Float(k) * 0.016, side: s, gpuPaint: true, into: b)
                    verts = b.mesh.vertices.count; tris = b.mesh.indices.count / 3
                }
            }
            return ((CACurrentMediaTime() - t0) * 1000 / Double(n), verts, tris)
        }
        var total = (old: 0.0, new: 0.0)
        for look in WearLook.shoes {
            let o = run(true, look), m = run(false, look)
            print("SHOEPERF \(look.rawValue): old shell \(o.verts) verts \(o.tris) tris \(String(format: "%.4f", o.ms)) ms per pair; modelled \(m.verts) verts \(m.tris) tris \(String(format: "%.4f", m.ms)) ms per pair")
            total.old += o.ms; total.new += m.ms
        }
        print("SHOEPERF mean per pair: old \(String(format: "%.4f", total.old / 9)) ms, modelled \(String(format: "%.4f", total.new / 9)) ms")
    }
}
