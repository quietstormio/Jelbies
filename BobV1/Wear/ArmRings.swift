//
//  ArmRings.swift
//  The arm as the renderer DRAWS it, read back from the skinned vertex stream: every mode (rest nub, keyframed wave / dining / held-up arm, walking capsule) puts the arm's
//  revolve (`ArmCapsule`: a pole at the tip, `tipRings` rings on the tip sphere, `rootRings` rings on the root sphere, a pole at the root) into the skin. The two rings where the
//  shaft leaves the spheres give the axis and the radius by angle (the arm is flattened in z); the poles give the sphere centres. Wear fits its bands to this, so a band
//  cannot drift from the arm the player sees (the rigid body fit is 10+ cm off the skin when the body is flopped / sitting / squashed).
//  `inflate` = how far the revolve is shrunk (hidden under the skin at rest, grown by the wave) so the rings are read as the arm's visible surface.
//

import simd

nonisolated struct ArmRings: Sendable {
    var U = SIMD3<Float>(0, 1, 0)                // tip -> root (toward the shoulder)
    var B = SIMD3<Float>.zero                    // tip sphere centre
    var L: Float = 0                             // |A - B|
    var e1 = SIMD3<Float>(1, 0, 0), e2 = SIMD3<Float>(0, 0, 1)
    private(set) var s: [Float] = []             // axial position of each ring centre from B
    private(set) var rho: [Float] = []           // ring radius by angle: ring * around + j

    static func fit(skin d: UnsafePointer<Float>, first: Int, inflate: Float, r1: Float, r2: Float, length: Float) -> ArmRings? {
        let n = ArmCapsule.around, K = ArmCapsule.ringCount, T = ArmCapsule.tipRings
        @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
        @inline(__always) func idx(_ k: Int, _ j: Int) -> Int { first + 1 + n * k + j }
        func centre(_ k: Int) -> SIMD3<Float> { var c = SIMD3<Float>.zero; for j in 0..<n { c += P(idx(k, j)) }; return c / Float(n) }
        let cs = (0..<K).map(centre)
        let tipPole = P(first), rootPole = P(first + ArmCapsule.vertexCount - 1)
        let u0 = rootPole - tipPole                          // the poles sit R2 beyond the tip and R1 beyond the root: a stable axis even when the arm is shorter than it is wide
        guard simd_length(u0) > 1e-5, u0.x.isFinite else { return nil }
        var r = ArmRings()
        r.U = simd_normalize(u0)
        let U = r.U
        // The tip centre B and the length L along the axis: the measured pole-to-pole span (the body's squash scales it) shared out by the model's proportions
        // (tip sphere r2 beyond B, root sphere r1 beyond A, hidden / grown by `inflate`). Sphere-fitting the rings would be wrong in a squashed, sitting body.
        let rd2 = max(r2 - inflate, 0.001), rd1 = max(r1 - inflate, 0.001)
        let span = simd_length(u0), whole = max(length, 0) + rd1 + rd2
        r.B = tipPole + U * (span * rd2 / whole)
        r.L = span * max(length, 0) / whole
        let v0 = P(idx(T - 1, 0)) - cs[T - 1]
        r.e1 = simd_normalize(v0 - U * simd_dot(v0, U)); r.e2 = simd_cross(U, r.e1)
        if simd_dot(P(idx(T - 1, n / 4)) - cs[T - 1], r.e2) < 0 { r.e2 = -r.e2 }          // (e2 only names the direction the ring index runs)
        r.s.reserveCapacity(K); r.rho.reserveCapacity(K * n)
        for k in 0..<K {
            r.s.append(simd_dot(cs[k] - r.B, U))
            for j in 0..<n { let v = P(idx(k, j)) - cs[k]; r.rho.append(simd_length(v - U * simd_dot(v, U)) + inflate) }
        }
        guard r.s[0] < r.s[K - 1] else { return nil }
        return r
    }

    /// The arm's skin radius at axial distance `a` from B (toward the shoulder) and angle `th` about the axis (e1 = 0).
    func radius(at a: Float, theta th: Float) -> Float {
        let n = ArmCapsule.around
        var k = 0
        while k < s.count - 2 && s[k + 1] < a { k += 1 }
        let u = min(max((a - s[k]) / max(s[k + 1] - s[k], 1e-6), 0), 1)
        var jf = th / (2 * .pi) * Float(n); jf -= (jf / Float(n)).rounded(.down) * Float(n)
        let j0 = Int(jf) % n, j1 = (j0 + 1) % n, w = jf - Float(Int(jf))
        @inline(__always) func ring(_ kk: Int) -> Float { rho[kk * n + j0] * (1 - w) + rho[kk * n + j1] * w }
        return ring(k) * (1 - u) + ring(k + 1) * u
    }
}
