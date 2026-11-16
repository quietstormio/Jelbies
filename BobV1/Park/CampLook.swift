//
//  CampLook.swift
//  The look of a Camp creature on the yard stage (camp-yard-r1 Y3 / Y4). A Camp body is a park-style visitor body; the creature's look is COPIED into a `CampCreature` value when the body appears
//  (species palette or Jelly Spring variant, feature, wing / spike tint, panda ink, what it wears, name, voice species) and the yard only ever reads that copy: a purge of the creature's save while the
//  body is on screen (the goodbye walk) cannot change it. Built from the SAME functions the room uses for a creature at home (JellyRoster.feature / palette / species / nameOf, WhiteWing, JellyVariants).
//

import Foundation
import simd

struct CampCreature {
    let id: Int                          // the instance id (every save key)
    let species: Int
    let name: String
    let palette: Palette?                // nil = Bob's own colour (JellyPalettes.park(.blue) on the yard stage)
    let feature: JellyFeature
    let whiteWing: Bool                  // Pearl's wing tint
    let spikeTint: SIMD3<Float>?         // Amber variant's spikes (Pip's spines only)
    let panda: Bool                      // Panda's ink
    let worn: [WearSlot: WearLook]

    /// The look of instance `id` as the room builds it for a creature at home (`GameCare.tickFeature`, `JellyRoster.palette`), with `worn` = its saved outfit.
    @MainActor static func make(instance id: Int, name: String? = nil, palette: Palette?? = nil, worn: [WearSlot: WearLook]) -> CampCreature {
        let f = JellyRoster.feature(id)
        return CampCreature(id: id, species: JellyRoster.species(id), name: name ?? JellyRoster.nameOf(id), palette: palette ?? JellyRoster.palette(id), feature: f,
                            whiteWing: WhiteWing.hasLook(id), spikeTint: f == .spines ? JellyVariantBook.spikeTint(for: JellyVariants.active(id)) : nil,
                            panda: JellyRoster.species(id) == JellyRoster.pandaID, worn: worn)
    }
}

/// What the yard stage keeps while a visit lasts: the copied looks by BODY id, and the stage's spawn closure.
@MainActor
final class CampBook {
    static let shared = CampBook()
    /// body id -> the look copied when the body appeared.
    var bodies: [Int: CampCreature] = [:]
    /// Made by the stage (MelonController.campSpawn): bodies for the creatures on the spots, ids continuing after the roster.
    var spawn: (([CampCreature], [SIMD2<Float>]) -> [JellyActor])?
    nonisolated deinit {}
}

enum CampLayout {
    /// (x as a share of the half width, z as a share of the depth) for six.
    static let slots: [(Float, Float)] = [(-0.35, 0.62), (0.40, 0.72), (0.0, 0.46), (-0.60, 0.26), (0.62, 0.30), (0.0, 0.88)]

    /// Spread over the yard's play floor (the roam floor of the Camp camera): never more than six, inside the floor, apart from each other.
    static func spots(count: Int) -> [SIMD2<Float>] {
        (0..<min(max(count, 0), JellyCamp.cap)).map { k in
            let s = slots[k]
            guard let f = GameCamera.roamFloor else { return SIMD2(s.0 * 3, -2 + s.1 * 5) }
            let z = f.minZ + s.1 * (f.maxZ - f.minZ)
            let q = GameCamera.constrain(SIMD3(s.0 * f.halfWidth(at: z), 0, z), radius: 0.8)
            return SIMD2(q.x, q.z)
        }
    }
}

extension GameCare {
    /// Who is at Camp, as looks to copy. The seam of the visit (tests replace it): the save's Camp list, or, in a simulator capture with `-CampSeed n` and nobody at Camp, n made-up creatures of mixed species.
    @MainActor static var campSource: () -> [CampCreature] = { campCreatures() }

    /// The Camp creatures of the save in `d`, as looks to copy (in the simulator, dressed by `-CampLooks`).
    @MainActor static func campCreatures(_ d: UserDefaults = .standard) -> [CampCreature] {
        let real = JellyCamp.members(d).map { CampCreature.make(instance: $0.id, name: $0.name, palette: .some($0.palette), worn: $0.worn) }
        #if targetEnvironment(simulator)
        return campLooksApplied(real)
        #else
        return real
        #endif
    }

    #if targetEnvironment(simulator)
    /// `-CampLooks "0:beanieHoney+bandanaMint+wristbandsSky+hightopRed;2:beaniePink"` (captures only, simulator only, in memory, never saved): dresses the Camp creature at that index in the yard's list
    /// (look names are `WearLook` raw values). The creatures themselves come from the core's `-CampSeed <n>`.
    @MainActor static func campLooksApplied(_ list: [CampCreature], arg: String? = UserDefaults.standard.string(forKey: "CampLooks")) -> [CampCreature] {
        guard let arg else { return list }
        var out = list
        for part in arg.split(separator: ";") {
            let kv = part.split(separator: ":")
            guard kv.count == 2, let k = Int(kv[0]), out.indices.contains(k) else { continue }
            var worn = out[k].worn
            for name in kv[1].split(separator: "+") { if let look = WearLook(rawValue: String(name)), let slot = WearGenerated.rows.first(where: { $0.look == look })?.slot { worn[slot] = look } }
            let c = out[k]
            out[k] = CampCreature(id: c.id, species: c.species, name: c.name, palette: c.palette, feature: c.feature, whiteWing: c.whiteWing, spikeTint: c.spikeTint, panda: c.panda, worn: worn)
        }
        return out
    }
    #endif
}
