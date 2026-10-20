//
//  JellyProfile.swift
//  Everything a Jelly KEEPS (as opposed to the soft body, brain and mesh he is drawn with, which are the stage's `JellyActor`):
//  name, colour, needs, dirt / sparkle, the look the renderer draws that dirt with, and his book of learned words.
//  Jelly 0 wraps the objects GameCare / BathFlow / VoiceCoordinator already own; Jellies 1 and 2 own theirs. All persist under their id (JellyKeys).
//

import Foundation
import Observation
import simd

@MainActor
final class JellyProfile: Identifiable {
    let id: Int
    let name: String
    let needs: BlobNeeds
    let grime: BlobGrime
    /// His book of learned words. Only Jelly 0's is used by the voice coordinator in phase A; 1 and 2 keep an idle book under their own key.
    let training: VoiceTraining
    /// What he is good at (waddle for racing, focus): persisted under his id (JellyStats.swift).
    let stats: JellyStats
    /// Timed perks from store food and supplies (Store/Perks.swift), persisted under his id.
    let perks: JellyPerks
    /// What the room draws on his body: dirt, soot, shine (no suds / wet: the clean-up is Bob-only for now). Jelly 0's look lives in BathFlow.
    private(set) var look = BathLook()
    @ObservationIgnored private var sootSeededFor: Float = -1
    @ObservationIgnored private var lastPos: SIMD2<Float>?

    nonisolated deinit {}

    /// Jelly 0: wraps the existing objects.
    init(id: Int, name: String, needs: BlobNeeds, grime: BlobGrime, training: VoiceTraining, stats: JellyStats? = nil, perks: JellyPerks? = nil) {
        self.id = id; self.name = name; self.needs = needs; self.grime = grime; self.training = training
        self.perks = perks ?? JellyPerks(key: JellyKeys.perks(id))
        grime.perks = self.perks
        self.stats = stats ?? JellyStats(key: JellyKeys.stats(id), seedWaddle: StatTuning.seedWaddle(careLevels: NeedKind.allCases.map { needs.level($0) }))
        refreshLook(force: true)
    }

    /// Jellies 1 and 2 (or any id): their own state under their own keys. `persists: false` makes an in-memory Jelly (tests).
    convenience init(id: Int, name: String, persists: Bool = true, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        let fresh = defaults.object(forKey: JellyKeys.needs(id)) == nil
        let needs = BlobNeeds(defaults: defaults, key: JellyKeys.needs(id), now: now, persists: persists)
        if fresh, id > 0 {          // a first launch for this Jelly: they differ, so the roster shows who wants what (Pip is thirsty, Moss wants love)
            for k in NeedKind.allCases { needs.set(k, NeedsTuning.seedOthers) }
            needs.set(NeedKind(rawValue: id % 3) ?? .thirst, NeedsTuning.seedHunger)
            if persists { needs.save() }
        }
        let grime = BlobGrime(persists: persists, seed: 0xB47B &+ UInt32(id) &* 7919, defaults: defaults, key: JellyKeys.grime(id), now: now)
        let training = VoiceTraining(defaults: defaults, key: JellyKeys.words(id), name: name, persists: persists)
        let stats = JellyStats(persists: persists, defaults: defaults, key: JellyKeys.stats(id),
                               seedWaddle: StatTuning.seedWaddle(careLevels: NeedKind.allCases.map { needs.level($0) }))
        self.init(id: id, name: name, needs: needs, grime: grime, training: training, stats: stats, perks: JellyPerks(persists: persists, defaults: defaults, key: JellyKeys.perks(id), now: now))
    }

    var coat: BlobGrime.CoatTier { grime.coat }

    /// One fixed sim step: needs drain, dirt builds with the floor he covered, the look follows the dirt.
    func step(dt: Float, position: SIMD2<Float>, exerting: Bool, drainScale: Float = 1) {
        let travelled = lastPos.map { simd_distance($0, position) } ?? 0
        lastPos = position
        perks.step(dt: dt)
        needs.step(dt: dt, exerting: exerting, drainScale: drainScale, perkDrain: perks.cache.drain)
        grime.step(dt: dt, travelled: travelled < 1 ? travelled : 0, exerting: exerting)      // a jump of a metre in one step is a teleport, not a walk
        refreshLook(force: false)
    }

    /// Keeps `look` in step with the grime (soot is re-seeded only when the dirt moved enough to matter).
    func refreshLook(force: Bool) {
        look.sparkle = grime.sparkle
        look.dirt = grime.dirt
        if force || abs(grime.dirt - sootSeededFor) > BathTuning.sootReseed || (grime.dirt == 0) != (sootSeededFor == 0) {
            look.soot = BathLook.sootSeed(dirt: grime.dirt); sootSeededFor = grime.dirt
        }
    }

    // MARK: time away (every Jelly, one path)

    func leftActive(at t: Date? = nil) { needs.leaveActive(at: t); grime.leaveActive(at: t) }
    /// Applies the time away to needs and dirt; returns the seconds applied.
    @discardableResult
    func returnedActive(at t: Date? = nil) -> TimeInterval {
        let a = needs.returnActive(at: t)
        let g = grime.returnActive(at: t)
        refreshLook(force: false)
        return max(a, g)
    }
    var lastAway: TimeInterval { max(needs.lastAway, grime.lastAway) }
}
