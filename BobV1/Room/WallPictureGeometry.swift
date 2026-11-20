//
//  WallPictureGeometry.swift
//  The three meshes of a hung picture, in world space: the frame (the Blender art, scaled uniformly by the picture's height), the picture itself (one quad, material 9,
//  colour rg = uv, drawn with roomPhotoFS) and a soft contact shadow on the wall (blended). They are static: they join the cached room.
//

import Foundation
import simd

nonisolated enum WallPictureGeometry {
    struct Meshes { var frame = RoomMesh(); var photo = RoomMesh(); var shadow = RoomMesh() }
    /// The frame's back stands this far in front of the wall (a hair: no z-fight); the contact shadow lies in between; the picture sits just behind the frame's inner lip.
    static let gap: Float = 0.003, shadowGap: Float = 0.0012
    static let photoDepth: Float = 0.012

    /// The bundled frame art: wallframe_frame_<id>_<shape>.bin (Room/Resources).
    static func art(_ p: WallPicture) -> DecorMeshes.Art? { DecorMeshes.load(p.artID, prefix: "wall") }

    static func build(_ p: WallPicture, art: DecorMeshes.Art?) -> Meshes {
        var m = Meshes()
        let h = p.height, w = p.width, wallZ = RoomLayout.minZ
        // frame
        if let art {
            let b = RoomMeshBuilder()
            for part in art.parts { DecorMeshes.emit(part, into: b, offset: SIMD3(p.x, p.y, wallZ + gap), pose: { v, n, _ in (v * h, n) }) }
            m.frame = b.mesh
        }
        // picture: top-left uv (0, 0)
        do {
            let e: Float = 0.004 * h, z = wallZ + gap + photoDepth * h
            let x0 = p.x - w / 2 - e, x1 = p.x + w / 2 + e, y0 = p.y - h / 2 - e, y1 = p.y + h / 2 + e
            let b = RoomMeshBuilder(); b.material = .photo
            let n = SIMD3<Float>(0, 0, 1)
            let a = b.vertex(SIMD3(x0, y1, z), n, ao: 1, color: SIMD3(0, 0, 0)), bb = b.vertex(SIMD3(x1, y1, z), n, ao: 1, color: SIMD3(1, 0, 0))
            let c = b.vertex(SIMD3(x1, y0, z), n, ao: 1, color: SIMD3(1, 1, 0)), d = b.vertex(SIMD3(x0, y0, z), n, ao: 1, color: SIMD3(0, 1, 0))
            b.quad(a, d, c, bb)
            m.photo = b.mesh
        }
        // contact shadow: a rounded ring around the frame's outer edge fading out, offset down and to the right (the key light is up and to the left)
        do {
            let b = RoomMeshBuilder(); b.material = .plain
            let z = wallZ + shadowGap
            let cx = p.x + 0.03 * h, cy = p.y - 0.05 * h
            let hw = p.outerWidth / 2, hh = p.outerHeight / 2
            let rings: [(e: Float, a: Float)] = [(-0.03, 0.32), (0.02, 0.26), (0.06, 0.15), (0.11, 0.06), (0.17, 0)]
            func loop(_ e: Float, _ a: Float) -> [UInt32] {
                let ex = e * h, r = max(ex, 0.01 * h), arcs = 6
                let iw = hw + ex - r, ih = hh + ex - r
                var ids: [UInt32] = []
                for (sx, sy, a0) in [(Float(1), Float(-1), Float(-90)), (1, 1, 0), (-1, 1, 90), (-1, -1, 180)] {
                    for k in 0..<arcs {
                        let t = (a0 + 90 * Float(k) / Float(arcs - 1)) * .pi / 180
                        ids.append(shadowVertex(b, SIMD3(cx + sx * iw + r * cosf(t), cy + sy * ih + r * sinf(t), z), a))
                    }
                }
                return ids
            }
            let loops = rings.map { loop($0.e, $0.a) }
            let n = loops[0].count
            for i in 1..<n - 1 { b.triangle(loops[0][0], loops[0][i], loops[0][i + 1]) }          // the filled middle (the frame covers it)
            for k in 0..<loops.count - 1 { for i in 0..<n { let j = (i + 1) % n; b.quad(loops[k][i], loops[k][j], loops[k + 1][j], loops[k + 1][i]) } }
            m.shadow = b.mesh
        }
        return m
    }

    private static func shadowVertex(_ b: RoomMeshBuilder, _ p: SIMD3<Float>, _ alpha: Float) -> UInt32 {
        b.mesh.vertices.append(RoomVertex(pos: SIMD4(p, RoomMaterial.plain.rawValue), normal: SIMD4(0, 0, 1, 1), color: SIMD4(0, 0, 0, alpha)))
        return UInt32(b.mesh.vertices.count - 1)
    }
}
