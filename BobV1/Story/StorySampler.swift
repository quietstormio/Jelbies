//
//  StorySampler.swift
//  Once a second per home body: one second of "what he is doing" (the same label the dev `[emotespot]` log line uses), who with, and where, into StoryHabitStore.
//  Called from BlobBrain.tick's deferred block (every path out of the tick), so it runs always, not only with the dev flag. Per tick it costs one Float add and one compare.
//

import Foundation
import simd

extension BlobBrain {
    /// The activity key of this body right now: walk / stand / rest / toy / solo:<kind> / pair:<kind> / group:<kind>.
    var storyActivityKey: String {
        if let s = social { return (s.kind.isGroup ? "group:" : "pair:") + s.kind.rawValue }
        if let k = idleState.kind { return (k == .sleep || k == .sit ? "rest" : "solo:" + k.rawValue) }
        if trackPoint != nil || bubbleLeash != nil { return "toy" }
        return activity == .walking || activity == .coming ? "walk" : "stand"
    }

    /// The steer ids of the others in my social session.
    var storyPartnerSlots: [Int] {
        guard let s = social else { return [] }
        var ids = Set([s.idA, s.idB, s.idC] + s.crewIDs)
        ids.remove(steerID); ids.remove(-1)
        return ids.sorted()
    }

    func storySample(_ dt: Float) {
        emoteSpot.storyT += dt
        guard emoteSpot.storyT >= 1 else { return }
        emoteSpot.storyT -= 1
        if emoteSpot.storyT > 1 { emoteSpot.storyT = 0 }
        guard homeRoom, !volley.active, !race.active else { return }
        let here = SIMD2<Float>(px, pz)
        let area = StorySampling.area(x: px, z: pz, sofaDistance: RoomLayout.sofaDistanceXZ(here), rugDistance: simd_distance(here, RoomLayout.rugCentre), backZ: RoomLayout.minZ, frontZ: -RoomLayout.walls[1].d)
        StoryHabitStore.shared.sample(slot: steerID, activity: storyActivityKey, partnerSlots: storyPartnerSlots, area: area)
    }
}
