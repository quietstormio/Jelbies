//
//  GameCare+Wear.swift
//  Feeds the wardrobe (Wear/WornSet.swift) with the Jellies' outfits, brains and bodies, and hands its meshes (and the jersey colours) to the renderer.
//  The tick runs once per fixed step after every Jelly's brain; the refresh runs once per frame AFTER the skinning (the surface-bound pieces read this
//  frame's skin, not last frame's).
//

import Foundation
import simd

extension GameCare {
    /// The Circuit role of actor `id` while a race trip is on: the player in his team colour with a number chosen by roster index, the rivals in theirs.
    func wearRole(for id: Int) -> WearRaceRole {
        guard race.active else { return .none }
        if id == race.playerID { return .player(team: WearTeam.player(roster: id), number: WearTeam.playerNumber(roster: id)) }
        guard let k = raceBook.racers.firstIndex(of: id), k > 0 else { return .rival(team: .lavender, number: 0) }
        return .rival(team: WearTeam.rivals[(k - 1) % WearTeam.rivals.count], number: WearTeam.rivalNumbers[(k - 1) % WearTeam.rivalNumbers.count])
    }

    /// Capture aid: -WearForce medal_gold[,backpack_sky] puts those pieces (art ids) on every Jelbie over the saved outfit (screenshots only).
    static let forcedWear: [WearSlot: WearLook] = {
        guard let s = UserDefaults.standard.string(forKey: "WearForce") else { return [:] }
        var o: [WearSlot: WearLook] = [:]
        for id in s.split(separator: ",") { if let l = WearLook.pieces.first(where: { $0.art == String(id) }) { o[l.slot] = l } }
        return o
    }()

    func outfit(_ id: Int) -> [WearSlot: WearLook] {
        if wearOutfitRev != store.revision { wearOutfits = [:]; wearOutfitRev = store.revision }
        if let o = wearOutfits[id] { return o }
        var o = store.outfit(id)
        for (s, l) in Self.forcedWear { o[s] = l }
        wearOutfits[id] = o
        return o
    }

    /// Once per fixed step, after every Jelly has been ticked.
    func tickWear(_ actors: [JellyActor], dt: Float) {
        for a in actors {
            guard let b = a.brain else { continue }
            var role = wearRole(for: a.id)
            var hide = bath.active
            if race.active, raceBook.parked.contains(a.id) { hide = true; role = .none }
            if showHidesWear(a.id) { hide = true; role = .none }          // the show: rival bodies and the parked wear nothing of ours
            let worn = outfit(a.id)
            let sig = worn.map { $0.key.rawValue.hashValue ^ $0.value.rawValue.hashValue }.reduce(0, ^) &+ worn.count
            if let was = outfitSeen[a.id], was != sig, !worn.isEmpty, !hide { b.postEvent(.newOutfit); b.blushBump(hold: 2.4, peak: 0.55) }          // a new outfit: the others admire it
            outfitSeen[a.id] = sig
            wardrobe.tick(id: a.id, brain: b, sim: a.sim, outfit: worn, role: role, hideAll: hide, dt: dt)
            tickFeature(a, brain: b, hideAll: hide, dt: dt)
        }
        wardrobe.stepPuffs(dt: dt)
    }

    /// The posed arm frames of a Jelly (world): the capsule's A, B and r2 while the arm is out, blended from the resting nub by the capsule's own blend.
    func armFrames(_ a: JellyActor) -> [ArmFrameWorld] {
        guard let b = a.brain else { return [ArmFrameWorld(), ArmFrameWorld()] }
        return Self.armFrames(brain: b, sim: a.sim)
    }
    static func armFrames(brain b: BlobBrain, sim: SoftBody) -> [ArmFrameWorld] {
        let pose = sim.bodyPose(iterations: 3)
        let R = simd_float3x3(pose.rotation)
        let sq = sim.attractor.squash, sxz = 1 / sq.squareRoot()
        let M = R * simd_float3x3(diagonal: SIMD3(sxz, sq, sxz))
        func carry(_ p: SIMD3<Float>) -> SIMD3<Float> { pose.centroid + M * (p - sim.restCentroid) }
        let att = sim.attractor
        let RA = simd_float3x3(att.rotation) * simd_float3x3(diagonal: SIMD3(sxz, sq, sxz))
        func attractor(_ p: SIMD3<Float>) -> SIMD3<Float> { att.anchor + RA * (p - sim.restCentroid) }
        let bl = b.armG > 0.0001 ? b.armBlendNow : 0
        let restA = SIMD3<Float>(Float(BobForm.armTop.x), Float(BobForm.armTop.y), Float(BobForm.armTop.z))
        let restB = SIMD3<Float>(Float(BobForm.armTip.x), Float(BobForm.armTip.y), Float(BobForm.armTip.z))
        let restR = Float(BobForm.armTipR)
        var out: [ArmFrameWorld] = []
        for side in 0..<2 {
            let sg: Float = side == 1 ? 1 : -1
            func mir(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x * sg, p.y, p.z) }
            var f = ArmFrameWorld()
            f.a = carry(mir(restA)); f.b = carry(mir(restB)); f.r2 = restR
            if bl > 0 {
                let g = b.armLastGeom[side]
                f.a += (attractor(mir(g.a)) - f.a) * bl
                f.b += (attractor(mir(g.b)) - f.b) * bl
                f.r2 += (g.r2 - restR) * bl
            }
            f.forward = R * SIMD3(0, 0, 1)
            out.append(f)
        }
        return out
    }

    /// After the frame's skinning: the wardrobe (carried by the bodies' poses and skins now) goes to the room, the jersey colours to the body renderer.
    func refreshWear(_ actors: [JellyActor], renderer: MelonRenderer?, time: Float) {
        guard let renderer, let room = renderer.room else { return }
        if wardrobe.body == nil { wardrobe.body = WearBody.shared }
        for a in actors where wardrobe.shown(a.id, .hands) != nil { wardrobe.setArms(a.id, armFrames(a)) }
        for a in actors { renderer.setJersey(wardrobe.jersey(a.id), body: a.id) }
        let active = wardrobe.isActive || features.anyShown
        guard active || wearDrawn else { return }
        var f = wardrobe.frame(theme: room.theme, hidden: room.bathVisible, time: time) { renderer.skinPointer(body: $0) }
        var boxes = wearBoxes(f.opaque, actors.count)
        if features.body == nil { features.body = WearBody.shared }
        let ff = features.frame(hidden: room.bathVisible) { renderer.skinPointer(body: $0) }
        if !ff.vertices.isEmpty {
            let base = UInt32(f.opaque.vertices.count)
            f.opaque.vertices += ff.vertices
            f.opaque.indices += ff.indices.map { $0 + base }
            boxes += features.lastBounds
        }
        room.setWear(opaque: f.opaque, translucent: f.translucent, bounds: boxes)
        wearDrawn = active
    }

    /// One world box per Jelly that wears something (the room cache re-shades them; hats stand above the body's own box).
    private func wearBoxes(_ m: RoomMesh, _ n: Int) -> [(lo: SIMD3<Float>, hi: SIMD3<Float>)] {
        guard !m.vertices.isEmpty else { return [] }
        return wardrobe.lastBounds
    }
}
