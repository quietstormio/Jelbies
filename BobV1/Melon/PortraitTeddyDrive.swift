//
//  PortraitTeddyDrive.swift
//  What Teddy's / Panda's body-mesh ears + pom do in a LOBBY PORTRAIT. The ears are body vertices scaled by the skinner's `teddyEarScale` / `teddyPomScale`, which the live brain feeds
//  from the live FeatureSet (a hat tucks them with a fade, taking it off pops them back). The portrait used to skin the body with those LIVE scales, so a portrait drawn right after
//  a hat came off (or while the stage was paused behind the Bag / Town) showed the ears still tucked, and the cache kept that picture. The portrait now skins with the scales of its
//  own throwaway FeatureSet (the worn set it is about to draw), and the live brain's values are put back untouched.
//

import Foundation

struct TeddyDrive: Equatable {
    var body = false, ear: Float = 1, pom: Float = 1, sway = SIMD2<Float>.zero

    @MainActor init(_ b: BlobBrain) { body = b.teddyBody; ear = b.teddyEarScale; pom = b.teddyPomScale; sway = b.teddySway }
    init() {}
    @MainActor func apply(to b: BlobBrain) { b.teddyBody = body; b.teddyEarScale = ear; b.teddyPomScale = pom; b.teddySway = sway }
    @MainActor func apply(to s: Skinner) { s.teddyEarScale = ear; s.teddyPomScale = pom; s.teddySway = sway }

    /// Ticks the throwaway `fs` once for `worn` and returns the ear / pom drive it produced, leaving the brain's live drive as it was.
    @MainActor static func portrait(fs: FeatureSet, id: Int, brain: BlobBrain, sim: SoftBody, feature: JellyFeature, worn: [String]) -> TeddyDrive {
        let live = TeddyDrive(brain)
        fs.tick(id: id, brain: brain, sim: sim, feature: feature, worn: worn, hideAll: false, dt: 1.0 / 60)
        let mine = TeddyDrive(brain)
        live.apply(to: brain)
        return mine
    }
}
