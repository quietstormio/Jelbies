//
//  BlobSocial+Part.swift
//  PARTING from a partner you stand skin to skin with (squabble's step apart, tag's run-off, the end of a high five / spin hug ...). A turn in place at touching distance swings the whole
//  skin (the feet midpoint and the body 23...29 cm sideways) about the fixed root into the partner, and the keepApart wall never sees it (it only moves roots). So while a brain is
//  "parting" from a partner whose skin is within `Part.clear` of his, every turn step he takes carries a retreat along the line away from the partner in its own root displacement
//  (BlobBrain.startStep): the turn becomes a back-step that opens the gap by the swing, in the move itself. Once the skins are clear the turn is a plain turn.
//
import Foundation
import simd

enum PartTuning {
    /// Skin gap (m) the turn needs around the partner before it may swing in place.
    static let clear: Float = 0.36
    /// Longest retreat of one step (m).
    static let maxStep: Float = 0.40
    /// How long a parting flag lives after it is set (s).
    static let life: Float = 6
    /// Smallest heading change (rad) of a step that counts as a turn.
    static let minTurn: Float = 0.35
    /// Sessions whose own choreography turns / circles at contact (the guard is only the explicit parting there).
    static let circling: Set<SocialKind> = [.spinHug, .tag, .littleRace, .leapfrog, .peekaboo, .mirrorDance]
}

extension BlobBrain {
    /// Mark that this brain is parting from `o` now.
    func startParting(from o: BlobBrain) { socialBook.partFrom = o.steerID; socialBook.partUntil = peerClock + PartTuning.life }

    /// The root displacement a turn step of `dyaw` radians takes while parting; nil = a plain turn.
    func partingRetreat(dyaw: Float) -> SIMD2<Float>? {
        guard abs(dyaw) > PartTuning.minTurn else { return nil }
        if let w = pressTurnWarp(dyaw: dyaw) { return w }
        var other: BlobBrain?
        if socialBook.partFrom >= 0 {
            if peerClock < socialBook.partUntil { other = socialBrain(socialBook.partFrom) } else { socialBook.partFrom = -1 }
        }
        // (inside a close pair session every turn in place at contact guards the partner too - backToBack's turn away, the squaring up of a high five ... - except the moves whose
        //  choreography IS the circling: ringAround, spinHug's pursuit, the runners)
        if other == nil, let s = social, s.end == nil, s.closeOK, !s.kind.isGroup, !PartTuning.circling.contains(s.kind) { other = s.a === self ? s.b : s.a }
        guard let o = other, o !== self else { return nil }
        let d = position - o.position, L = simd_length(d)
        guard L > 1e-3 else { return nil }
        let u = d / L
        // the skin gap: the drawn bodies (features included); without profiles the root distance against the close standing gap
        let gap = ContactField.gap(steerID, o.steerID, features: true) ?? (L - peerGap * SocialTuning.closeGapFactor)
        if gap >= PartTuning.clear { return nil }
        let want = min(PartTuning.maxStep, PartTuning.clear - gap + 0.02)
        let cand = position + u * want
        let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
        let got = SIMD2(rv.x, rv.z) - position
        return simd_dot(got, u) > 0.3 * want ? got : nil
    }
}

extension BlobBrain {
    /// Sessions whose own turn in place happens at contact and must keep the skins where they are: the turn step carries the root displacement that cancels the change of the support reach toward the partner.
    static let pressTurnKinds: Set<SocialKind> = [.backToBack]

    /// Motion warp for a turn at contact (backToBack's square-up: side by side, then each turns 90 degrees to put his back to the partner's). The skin's reach toward the partner changes with the heading
    /// (the body is wider than it is deep), so a plain turn in place opens the gap by the difference (measured 13 cm). The step that does the turn moves the root along the partner axis by exactly that
    /// difference - the reach after the turn is the profile's reach at the direction the turn brings round - so the skins stay where they were, in the move itself. Nil = a plain turn.
    func pressTurnWarp(dyaw: Float) -> SIMD2<Float>? {
        guard PeakTuning.enabled, PeakTuning.warpOn, ContactField.enabled, let s = social, s.end == nil, Self.pressTurnKinds.contains(s.kind), s.phase == 2, scriptIsNone,
              let o = s.a === self ? s.b : s.a, o !== self else { return nil }
        let d = o.position - position, L = simd_length(d)
        guard L > 1e-3 else { return nil }
        let u = d / L
        let back = rotXZ(u, -dyaw)
        guard let before = ContactField.supportExt(steerID, u), let after = ContactField.supportExt(steerID, back) else { return nil }
        let delta = max(-PartTuning.maxStep, min(PartTuning.maxStep, before - after))          // + : the reach shrinks (the gap would open): close in by it; - : it grows: back off by it
        if PeakTuning.log { print(String(format: "[peak] turnWarp %d dyaw=%.0fdeg reach %.3f -> %.3f move=%.3f", steerID, dyaw * 57.3, before, after, delta)) }
        guard abs(delta) > 0.006 else { return nil }
        let cand = position + u * delta
        let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
        let got = SIMD2(rv.x, rv.z) - position
        return simd_dot(got, u) * (delta > 0 ? 1 : -1) > 0.3 * abs(delta) ? got : nil
    }
}
