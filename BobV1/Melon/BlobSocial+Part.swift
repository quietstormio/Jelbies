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
    static let clear: Float = 0.32
    /// Longest retreat of one step (m).
    static let maxStep: Float = 0.36
    /// How long a parting flag lives after it is set (s).
    static let life: Float = 6
    /// Smallest heading change (rad) of a step that counts as a turn.
    static let minTurn: Float = 0.35
}

extension BlobBrain {
    /// Mark that this brain is parting from `o` now.
    func startParting(from o: BlobBrain) { socialBook.partFrom = o.steerID; socialBook.partUntil = peerClock + PartTuning.life }

    /// The root displacement a turn step of `dyaw` radians takes while parting; nil = a plain turn.
    func partingRetreat(dyaw: Float) -> SIMD2<Float>? {
        guard socialBook.partFrom >= 0 else { return nil }
        guard peerClock < socialBook.partUntil, let o = socialBrain(socialBook.partFrom), o !== self, abs(dyaw) > PartTuning.minTurn else { if peerClock >= socialBook.partUntil { socialBook.partFrom = -1 }; return nil }
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
