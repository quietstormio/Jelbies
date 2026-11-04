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
    static let circling: Set<SocialKind> = [.ringAround, .spinHug, .tag, .littleRace, .leapfrog, .peekaboo, .mirrorDance]
}

extension BlobBrain {
    /// Mark that this brain is parting from `o` now.
    func startParting(from o: BlobBrain) { socialBook.partFrom = o.steerID; socialBook.partUntil = peerClock + PartTuning.life }

    /// The root displacement a turn step of `dyaw` radians takes while parting; nil = a plain turn.
    func partingRetreat(dyaw: Float) -> SIMD2<Float>? {
        guard abs(dyaw) > PartTuning.minTurn else { return nil }
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
