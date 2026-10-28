#!/usr/bin/env python3
"""Bind the Blender-modelled shoes to the Jelbie foot bean and write BobV1/Wear/Resources/shoe_<case>.bin.

usage: convert_shoe_art.py <foot_bean.json> <shoe_json_dir> <out_resources_dir>
  foot_bean.json   written by the ShoeDumpTests test (SHOE_DUMP_DIR): the bean's rest shape in foot-local space (sole plane y = 0, toe +z) with the
                   same smooth vertex normals the app computes (ShoeModel.normals)
  shoe_json_dir    <case>.json per shoe, written by tools/shoes/model_shoes.py (Blender): pos, nrm, col (linear rgb), flag, ao, idx
Re-runnable: everything is derived from the inputs.

Every shoe vertex is stored as (bean triangle, barycentric b1, b2, signed distance d along the interpolated bean normal) such that
    rest position = P(b) + d * N(b),  P(b) = sum b_i * bean_i,  N(b) = normalize(sum b_i * n_i)
(solved per vertex, so the shoe reproduces exactly at rest). At run time the same formula is evaluated on the DEFORMED bean (the walking, hopping,
lifted-ball foot), so the shoe is attached to the foot bean by construction in every move. The shoe vertex normals are rotated with the bean normal.

bin layout (little endian): u32 magic 'SHO1', u32 vertexCount, u32 indexCount, u32 sparkleCount,
  vertexCount x { u32 tri, f32 b1, f32 b2, f32 d, f32 nx, ny, nz (rest shoe normal), f32 r, g, b (linear), f32 ao, f32 flag } (48 bytes),
  indexCount x u16, sparkleCount x u32 (vertex ids a glitter twinkle may sit on).
flag: 0 plain, 1 glow (light-up lamp: cycles cyan / pink), 2 sparkle anchor.
"""
import json, struct, sys, os
import numpy as np


def closest_points(P, V, T):
    """Closest point on triangle soup for each query point (vectorised Ericson). Returns tri index, point, (b0, b1, b2)."""
    A, B, C = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    best_d = np.full(len(P), 1e9)
    best_t = np.zeros(len(P), dtype=np.int64)
    best_b = np.zeros((len(P), 3))
    for s in range(0, len(P), 256):
        p = P[s:s + 256][:, None, :]
        ab, ac, ap = (B - A)[None], (C - A)[None], p - A[None]
        d1 = (ab * ap).sum(-1); d2 = (ac * ap).sum(-1)
        bp = p - B[None]
        d3 = (ab * bp).sum(-1); d4 = (ac * bp).sum(-1)
        cp = p - C[None]
        d5 = (ab * cp).sum(-1); d6 = (ac * cp).sum(-1)
        vc = d1 * d4 - d3 * d2; vb = d5 * d2 - d1 * d6; va = d3 * d6 - d5 * d4
        den = va + vb + vc
        den = np.where(np.abs(den) < 1e-18, 1e-18, den)
        # interior default
        v = vb / den; w = vc / den
        bary = np.stack([1 - v - w, v, w], -1)
        # clamp into the triangle by projecting onto the nearest edge/vertex (iterative clamp is enough for these small triangles)
        bary = np.clip(bary, 0, None)
        bary /= np.maximum(bary.sum(-1, keepdims=True), 1e-12)
        # refine by checking the three edges' closest points explicitly
        def edge(a, b):
            e = b - a
            t = np.clip(((p - a[None]) * e[None]).sum(-1) / np.maximum((e * e).sum(-1)[None], 1e-18), 0, 1)
            return t
        cand_pts, cand_b = [], []
        pt = (bary[..., 0:1] * A[None] + bary[..., 1:2] * B[None] + bary[..., 2:3] * C[None])
        cand_pts.append(pt); cand_b.append(bary)
        for (ia, ib, ea, eb) in ((0, 1, A, B), (1, 2, B, C), (2, 0, C, A)):
            t = edge(ea, eb)
            q = ea[None] + (eb - ea)[None] * t[..., None]
            b = np.zeros(t.shape + (3,)); b[..., ia] = 1 - t; b[..., ib] = t
            cand_pts.append(q); cand_b.append(b)
        dists = np.stack([((p - q) ** 2).sum(-1) for q in cand_pts], 0)   # 4, n, tris
        # the interior candidate is only valid when the unclamped barycentrics were inside
        inside = ((vb / den >= 0) & (vc / den >= 0) & (vb / den + vc / den <= 1))
        dists[0] = np.where(inside, dists[0], 1e9)
        k = dists.argmin(0)
        dmin = dists.min(0)
        ti = dmin.argmin(1)
        for i in range(len(ti)):
            kk = k[i, ti[i]]
            best_d[s + i] = dmin[i, ti[i]]; best_t[s + i] = ti[i]; best_b[s + i] = cand_b[kk][i, ti[i]]
    pts = (best_b[:, 0:1] * A[best_t] + best_b[:, 1:2] * B[best_t] + best_b[:, 2:3] * C[best_t])
    return best_t, pts, best_b


def bind(bean, pos):
    V = np.array(bean["pos"]); Nn = np.array(bean["nrm"]); T = np.array(bean["tris"]).reshape(-1, 3)
    tri, x, b = closest_points(pos, V, T)
    for _ in range(14):
        N = (b[:, 0:1] * Nn[T[tri, 0]] + b[:, 1:2] * Nn[T[tri, 1]] + b[:, 2:3] * Nn[T[tri, 2]])
        N /= np.linalg.norm(N, axis=1, keepdims=True)
        r = pos - x
        d = (r * N).sum(1, keepdims=True)
        tang = r - d * N                          # what the offset along the normal misses
        if np.abs(tang).max() < 2e-5: break
        tri, x, b = closest_points(x + tang, V, T)
    N = (b[:, 0:1] * Nn[T[tri, 0]] + b[:, 1:2] * Nn[T[tri, 1]] + b[:, 2:3] * Nn[T[tri, 2]])
    N /= np.linalg.norm(N, axis=1, keepdims=True)
    d = ((pos - x) * N).sum(1)
    rec = x + d[:, None] * N
    return tri, b, d, np.linalg.norm(rec - pos, axis=1)


def main():
    bean = json.load(open(sys.argv[1]))
    src, out = sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    for f in sorted(os.listdir(src)):
        if not f.endswith(".json"): continue
        name = f[:-5]
        j = json.load(open(os.path.join(src, f)))
        pos = np.array(j["pos"]); nrm = np.array(j["nrm"]); col = np.array(j["col"]); ao = np.array(j["ao"]); flag = np.array(j["flag"])
        idx = np.array(j["idx"], dtype=np.int64)
        assert len(pos) < 65536
        tri, b, d, err = bind(bean, pos)
        spark = [i for i in range(len(pos)) if flag[i] == 2]
        data = struct.pack("<4I", 0x314F4853, len(pos), len(idx), len(spark))
        for i in range(len(pos)):
            data += struct.pack("<I11f", int(tri[i]), b[i, 1], b[i, 2], d[i], *nrm[i], *col[i], ao[i], float(flag[i]))
        data += struct.pack("<%dH" % len(idx), *idx) + struct.pack("<%dI" % len(spark), *spark)
        open(os.path.join(out, "shoe_%s.bin" % name), "wb").write(data)
        print("%-16s %5d verts %5d tris  bind err max %.5f mean %.6f  |d| max %.3f  %d bytes" % (name, len(pos), len(idx) // 3, err.max(), err.mean(), np.abs(d).max(), len(data)))


main()
