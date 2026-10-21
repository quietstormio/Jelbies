//
//  GameCare+Features.swift
//  The character features in the game: once per fixed step (after the wardrobe, so the fit reads what the Jelly SHOWS now) the feature set is
//  ticked with the worn art ids; the fit feeds back to the brain (folded wings, the flap limit) and to the wardrobe (the hat variant Moss's daisy
//  sits on). The meshes go to the room with the wardrobe's (GameCare+Wear.refreshWear).
//

import Foundation
import simd

extension GameCare {
    /// The wearable art ids Jelly `id` shows now (the hide rules applied; the Circuit bib counts as a bib).
    func wornArt(_ id: Int) -> [String] {
        var out: [String] = []
        for s in WearSlot.allCases where s != .feet { if let l = wardrobe.shown(id, s), !l.art.isEmpty { out.append(l.art) } }
        if let s = wardrobe.slot(id), s.bib != nil, !out.contains("bib_sky"), !out.contains("bib_pink") { out.append("bib_sky") }
        return out
    }

    func tickFeature(_ a: JellyActor, brain b: BlobBrain, hideAll: Bool, dt: Float) {
        let f = a.profile?.feature ?? JellyRoster.feature(slot: a.id)
        b.feature = f
        b.trainingLock = voice.nickLesson != nil || voice.teachPrompt != nil
        features.tick(id: a.id, brain: b, sim: a.sim, feature: f, worn: wornArt(a.id), hideAll: hideAll, dt: dt)
        if let s = features.slot(a.id) {
            b.wingsFolded = f == .wings && s.fit.folded
            b.wingFlapLimit = f == .wings ? s.fit.flapMax : 75
            wardrobe.setArtOverride(a.id, s.fit.hatVariant)
        }
    }
}
