//
//  TailCarry.swift
//  hold-wear-r1: Pip's tail while he is LIFTED (held, thrown, mid-air above hop height). The long tail normally lies on the floor (Skinner.applyTail blends its low part onto a
//  heading-only frame at floor height); a lifted body must carry the whole tail on its full rotation frame instead. `tailFloorWeight` is 1 (exactly the old look) while the body
//  stands on the floor or hops, and eases to 0 over a lift range above that. The range depends on how the body is turned: upright (the hops, which can lift the egg ~0.27 m
//  and keep the tail trailing on the floor as they always did) it starts higher than for a tipped body (only a finger or a throw lifts a tipped body: a tipped body on the
//  floor has its lowest egg vertex at about 0).
//

import simd

extension Skinner {
    /// A/B switch (TailCarryTests): false = the tail always lies on the floor (the look before this change). The app never sets it.
    nonisolated(unsafe) static var tailCarryWhenLifted = true
    /// Lift (world y of the lowest egg vertex: 0.04 ... 0.05 standing, -0.04 ... 0.08 walking, up to 0.27 at the top of a hop or jump) over which the tail eases from lying on
    /// the floor (above `from`, weight 1 below) to being carried (weight 0 at `to`). Upright body / tipped body.
    static let tailLiftUpright: (from: Float, to: Float) = (0.34, 0.46)
    static let tailLiftTipped: (from: Float, to: Float) = (0.10, 0.30)
    /// The body counts as tipped below this up-axis height (smoothly: tipped at `tipLow`, upright at `tipHigh`).
    static let tailTipLow: Float = 0.55, tailTipHigh: Float = 0.85
    /// Test read-outs of the last call (lowest egg y seen inside `applyTail`, the weight): see TailCarryTests.
    nonisolated(unsafe) static var dbgTailLift: Float = 0
    nonisolated(unsafe) static var dbgTailWeightMin: Float = 1
    nonisolated(unsafe) static var dbgTailLiftMax: Float = -9

    /// Lowest vertex of the body egg (the render mesh before the arm / foot / tail blocks), world y.
    func eggMinY(_ dyn: UnsafeMutablePointer<Float>) -> Float {
        let n = bodyVertexLimit >= 0 ? min(bodyVertexLimit, vertexCount) : 0
        var m = Float.infinity
        var v = 0
        while v < n { m = min(m, dyn[6 * v + 1]); v += 1 }
        return m
    }

    /// 1 = the tail lies on the floor (standing, walking, hopping), 0 = carried on the body's full frame. `upY` = the height of the body's up axis (1 upright, -1 upside down).
    func tailFloorWeight(_ dyn: UnsafeMutablePointer<Float>, upY: Float) -> Float {
        guard Self.tailCarryWhenLifted, bodyVertexLimit > 0 else { return 1 }
        let lift = eggMinY(dyn)
        let tip = 1 - simd_smoothstep(Self.tailTipLow, Self.tailTipHigh, upY)
        let a = Self.tailLiftUpright, b = Self.tailLiftTipped
        let from = a.from + (b.from - a.from) * tip, to = a.to + (b.to - a.to) * tip
        Self.dbgTailLift = lift; Self.dbgTailLiftMax = max(Self.dbgTailLiftMax, lift)
        let w: Float = lift <= from ? 1 : 1 - simd_smoothstep(from, to, lift)
        Self.dbgTailWeightMin = min(Self.dbgTailWeightMin, w)
        return w
    }
}
