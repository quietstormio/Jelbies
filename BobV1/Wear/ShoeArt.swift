//
//  ShoeArt.swift
//  The modelled shoes. Each shoe is a Blender model (tools/shoes/model_shoes.py) bound to the foot bean by tools/shoes/convert_shoe_art.py into
//  Resources/shoe_<look>.bin: every shoe vertex is stored as (bean triangle, barycentric b1, b2, distance d along the bean's interpolated normal), so
//      position = sum b_i * bean_i  +  d * normalize(sum b_i * normal_i)
//  evaluated on the bean that is DRAWN (walking, hopping, the lifted ball, sitting, sleeping, a cartwheel ...) puts the shoe exactly where the foot is:
//  attached by construction, with no slot of its own and nothing the body has to know. The shoe's own normals are stored in the bean's frame at that spot
//  (the interpolated normal and ring tangent) and turn with it, twist included, so the shading follows the squash and the turns. Layout of the bin: see convert_shoe_art.py.
//
//  Light-up sneakers: vertices flagged 1 are the lamp (cyan <-> pink, emissive). Glitter shoes: vertices flagged 2 are the sequins (they twinkle).
//

import simd
import Foundation

nonisolated final class ShoeArt: @unchecked Sendable {
    struct Vtx {
        var i0: UInt32, i1: UInt32, i2: UInt32
        var b1: Float, b2: Float, d: Float
        var flag: Float, phase: Float
        var simple = false            // the shoe normal is the bean's own (within 4 degrees): no frame needed
        var nl: SIMD3<Float>          // the shoe vertex normal at rest in the bean's frame there: (along the ring tangent, along the bean normal, the third axis)
        var col: SIMD3<Float>
    }
    let verts: [Vtx]
    let indices: [UInt32], flipped: [UInt32]
    let animated: Bool
    /// The bean vertices whose ring tangent some shoe vertex needs (the ones with a normal that is not the bean's own): the rest are never computed.
    let needT: [Int]
    /// The farthest any modelled shoe vertex stands from the bean surface (the bound distance; the converter's report and ShoeTests keep it honest), plus the bean's own vertex spacing.
    static let maxReach: Float = 0.10

    private static let cyan = OKLab.srgbToLinear(SIMD3(0.25, 0.92, 1.0)), pink = OKLab.srgbToLinear(SIMD3(1.0, 0.45, 0.78))
    /// Tests / captures only: draw the old procedural shell instead (the before / after of the store sweep, the fallback's own tests).
    nonisolated(unsafe) static var forceProcedural = false
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [WearLook: ShoeArt] = [:]
    private final class Token {}

    /// The art of a shoe look (nil when there is none: the fallback shell is used).
    static func art(_ look: WearLook) -> ShoeArt? {
        if forceProcedural { return nil }
        lock.lock(); defer { lock.unlock() }
        if let a = cache[look] { return a }
        let name = "shoe_\(look.rawValue)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin") ?? Bundle(for: Token.self).url(forResource: name, withExtension: "bin"),
              let d = try? Data(contentsOf: url), let a = ShoeArt(data: d) else { return nil }
        cache[look] = a
        return a
    }
    static func hasArt(_ look: WearLook) -> Bool { art(look) != nil }
    /// Does the shoe change on its own (the lamp cycles, the sequins twinkle), so it is rebuilt every frame?
    static func isAnimated(_ look: WearLook) -> Bool { art(look)?.animated ?? (look == .sneakerLightup || look == .glitterShoes) }

    init?(data d: Data) {
        guard d.count >= 16 else { return nil }
        func u32(_ o: Int) -> UInt32 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) } }
        func f32(_ o: Int) -> Float { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float.self) } }
        guard u32(0) == 0x314F_4853 else { return nil }
        let nv = Int(u32(4)), ni = Int(u32(8)), ns = Int(u32(12))
        guard d.count == 16 + nv * 48 + ni * 2 + ns * 4 else { return nil }
        let tris = ShoeModel.tris
        let rest = FootBean.localF, rn = ShoeModel.normals(rest), rt = Self.tangents(rest, rn)
        var out = [Vtx](); out.reserveCapacity(nv)
        var group: Float = -1, prevSpark = false, anim = false
        for i in 0..<nv {
            let o = 16 + i * 48
            let t = Int(u32(o)) * 3
            guard t + 2 < tris.count else { return nil }
            let b1 = f32(o + 4), b2 = f32(o + 8), b0 = 1 - b1 - b2
            let i0 = tris[t], i1 = tris[t + 1], i2 = tris[t + 2]
            let n0 = simd_normalize(rn[Int(i0)] * b0 + rn[Int(i1)] * b1 + rn[Int(i2)] * b2)
            let (t0, bt0) = Self.frame(n0, rt[Int(i0)] * b0 + rt[Int(i1)] * b1 + rt[Int(i2)] * b2)
            let ns = SIMD3<Float>(f32(o + 16), f32(o + 20), f32(o + 24))
            let flag = f32(o + 44)
            if flag == 2 { if !prevSpark { group += 1 }; prevSpark = true } else { prevSpark = false }
            if flag != 0 { anim = true }
            let nlv = SIMD3(simd_dot(ns, t0), simd_dot(ns, n0), simd_dot(ns, bt0))
            out.append(Vtx(i0: i0, i1: i1, i2: i2, b1: b1, b2: b2, d: f32(o + 12), flag: flag, phase: group,
                           simple: nlv.y > 0.998, nl: nlv, col: SIMD3(f32(o + 28), f32(o + 32), f32(o + 36))))
        }
        var idx = [UInt32](); idx.reserveCapacity(ni)
        for k in 0..<ni { idx.append(UInt32(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16 + nv * 48 + k * 2, as: UInt16.self) })) }
        var fl = idx
        var k = 0
        while k + 2 < fl.count { fl.swapAt(k + 1, k + 2); k += 3 }
        verts = out; indices = idx; flipped = fl; animated = anim
        var need = Set<Int>()
        for v in out where !v.simple { need.insert(Int(v.i0)); need.insert(Int(v.i1)); need.insert(Int(v.i2)) }
        needT = need.sorted()
    }

    /// The bean's tangent along its ring at vertex i (perpendicular to the normal): with the normal it is the frame the shoe's normals ride in.
    @inline(__always) static func tangent(_ i: Int, _ w: UnsafeBufferPointer<SIMD3<Float>>, _ n: SIMD3<Float>) -> SIMD3<Float> {
        let a = FootBean.around, last = FootBean.vertexCount - 1
        var t: SIMD3<Float>
        if i == 0 { t = w[1] - w[0] }
        else if i == last { t = w[last - a] - w[last] }
        else {
            let r = (i - 1) / a, j = (i - 1) % a, base = 1 + a * r
            t = w[base + (j + 1) % a] - w[base + (j + a - 1) % a]
        }
        t -= n * simd_dot(t, n)
        let l2 = simd_length_squared(t)
        return l2 > 1e-14 ? t / l2.squareRoot() : simd_normalize(simd_cross(n, abs(n.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)))
    }
    static func tangents(_ w: [SIMD3<Float>], _ n: [SIMD3<Float>]) -> [SIMD3<Float>] {
        w.withUnsafeBufferPointer { wp in w.indices.map { tangent($0, wp, n[$0]) } }
    }
    /// An orthonormal frame (tangent, third axis) from a normal and a rough tangent.
    @inline(__always) static func frame(_ n: SIMD3<Float>, _ rough: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        var t = rough - n * simd_dot(rough, n)
        let l2 = simd_length_squared(t)
        t = l2 > 1e-14 ? t / l2.squareRoot() : simd_normalize(simd_cross(n, abs(n.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)))
        return (t, simd_cross(n, t))
    }

    /// The shoe of one foot as a world-space mesh on the foot bean `w` (its 418 world vertices), appended to `b`.
    func build(bean w: [SIMD3<Float>], time: Float, side: Int, into b: RoomMeshBuilder) {
        guard w.count == FootBean.vertexCount else { return }
        let (bn, flip) = ShoeModel.normalsAndFlip(w)
        var bt = [SIMD3<Float>](repeating: .zero, count: w.count)
        w.withUnsafeBufferPointer { wp in for i in needT { bt[i] = Self.tangent(i, wp, bn[i]) } }
        let hand: Float = flip ? -1 : 1          // a mirrored foot: the frame's third axis points the other way round
        let ph = 0.5 + 0.5 * sinf(time * 2.6)             // the lamp cycles cyan <-> pink
        let lamp = Self.cyan + (Self.pink - Self.cyan) * ph
        let base = UInt32(b.mesh.vertices.count)
        var out = [RoomVertex](unsafeUninitializedCapacity: verts.count) { buf, n in
            w.withUnsafeBufferPointer { wp in
                bn.withUnsafeBufferPointer { np in bt.withUnsafeBufferPointer { tp in
                    verts.withUnsafeBufferPointer { vp in
                        for k in 0..<vp.count {
                            let v = vp[k]
                            let b0 = 1 - v.b1 - v.b2
                            let ns = simd_normalize(np[Int(v.i0)] * b0 + np[Int(v.i1)] * v.b1 + np[Int(v.i2)] * v.b2)
                            let p = wp[Int(v.i0)] * b0 + wp[Int(v.i1)] * v.b1 + wp[Int(v.i2)] * v.b2 + ns * v.d
                            // the shoe normal carried in the bean's frame here (normal + ring tangent): turns, twists and squashes with the foot
                            var nn = ns
                            if !v.simple {
                                let (tg, bg) = Self.frame(ns, tp[Int(v.i0)] * b0 + tp[Int(v.i1)] * v.b1 + tp[Int(v.i2)] * v.b2)
                                nn = tg * v.nl.x + ns * v.nl.y + bg * (v.nl.z * hand)
                                nn = simd_length_squared(nn) > 1e-12 ? simd_normalize(nn) : ns
                            }
                            var col = v.col, ao: Float = 1
                            if v.flag == 1 { col = lamp; ao = 1 + (0.65 + 0.35 * ph) }
                            else if v.flag == 2 {
                                let tw = 0.5 + 0.5 * sinf(time * 4.2 + v.phase * 1.7 + Float(side))
                                col = v.col + (SIMD3<Float>(repeating: 1) - v.col) * (tw * tw)
                                ao = 1 + 0.9 * tw * tw
                            }
                            buf[k] = RoomVertex(pos: SIMD4(p, 0), normal: SIMD4(nn, ao), color: SIMD4(col, 1))
                        }
                    }
                } }
            }
            n = verts.count
        }
        b.mesh.vertices.append(contentsOf: out)
        out = []
        let ix = flip ? flipped : indices
        b.mesh.indices.reserveCapacity(b.mesh.indices.count + ix.count)
        for i in ix { b.mesh.indices.append(base + i) }
    }
}
