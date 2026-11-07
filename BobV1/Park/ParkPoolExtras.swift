//
//  ParkPoolExtras.swift
//  More Park friends (2026-11-07, "more variation to friends at the park and more of them"): the stock pool of 16 (ParkPool.generate, untouched so every
//  saved friendship, name and colour stays) plus 32 extra visitors from their OWN seed and their OWN name list. The extras wear things more often and mutate a
//  little more often, so the new faces look varied. The park still shows at most ParkTuning.maxVisitors bodies at once (the soft-body solver is the CPU limit);
//  this only widens who may come, so the same few Jelbies are not met every time.
//

import Foundation

nonisolated extension ParkTuning {
    /// Visitors added after the stock pool (ids poolSize ..< fullPoolSize).
    static let extraCount = 32
    static var fullPoolSize: Int { poolSize + extraCount }
    static let extraSeed: UInt64 = 0x4E7D_2B91_A6C5
    /// The extras dress up more than the stock pool's 45 %, and are a variant colour more often than `mutationRate`.
    static let extraWearChance: Float = 0.70
    static let extraMutationChance: Float = 0.25
}

nonisolated extension ParkWords {
    /// Names of the extra visitors (disjoint from `names`, `ParkNames.spare` and the competition list `RivalNames.all`).
    static let extraNames = ["Acorn", "Bubbles", "Buttons", "Cashew", "Cinder", "Clementine", "Coco", "Dewdrop", "Doodle", "Ember", "Fable", "Freckles",
                             "Ginger", "Gizmo", "Hazel", "Ivy", "Jellybug", "Kiwi", "Lemon", "Mango", "Marshmallow", "Muffin", "Nacho", "Oatmeal",
                             "Pancake", "Pretzel", "Pumpkin", "Raisin", "Sesame", "Sprinkles", "Truffle", "Twinkle"]
}

nonisolated extension ParkPool {
    /// The 32 extra visitors, ids `poolSize` ... `fullPoolSize - 1`. The same on every device. Colours obey `JellyVariantBook.parkEligible` and the species
    /// signature rule (signature = colour.speciesFeature).
    static func extras(seed: UInt64 = ParkTuning.extraSeed) -> [ParkVisitor] {
        var r = ParkRandom(seed)
        var mutations = ParkColour.mutations.filter { JellyVariantBook.parkEligible($0) }
        for i in stride(from: mutations.count - 1, to: 0, by: -1) { mutations.swapAt(i, Int(r.next() % UInt64(i + 1))) }
        var names = ParkWords.extraNames
        for i in stride(from: names.count - 1, to: 0, by: -1) { names.swapAt(i, Int(r.next() % UInt64(i + 1))) }
        var nextMutation = 0
        var out: [ParkVisitor] = []
        for k in 0..<ParkTuning.extraCount {
            let id = ParkTuning.poolSize + k
            let style = ParkStyle.allCases[Int(r.next() % UInt64(ParkStyle.allCases.count))]
            let colour: ParkColour
            if r.unit() < ParkTuning.extraMutationChance, !mutations.isEmpty { colour = mutations[nextMutation % mutations.count]; nextMutation += 1 }
            else { colour = ParkColour.classics[(k + Int(seed % 4)) % 4] }
            let wear: WearLook? = r.unit() < ParkTuning.extraWearChance ? r.pick(wearables) : nil
            let name = names[k % names.count]
            out.append(ParkVisitor(id: id, name: name, colour: colour, signature: colour.speciesFeature, wear: wear, style: style,
                                   blurb: ParkWords.blurb(style, &r), greeting: ParkWords.greeting(name, style, &r)))
        }
        return out
    }

    /// The whole pool the Park draws from: the stock 16 (exactly as `generate` makes them) then the 32 extras, names reconciled against `reserved`
    /// (a player Jelbie's name, a personality word, a colour) and against each other.
    static func all(reserved: Set<String> = []) -> [ParkVisitor] {
        var out = generate(reserved: reserved) + extras()
        ParkNames.reconcile(&out, reserved: reserved.union(ParkNames.reserved(rosterNames: [])))
        return out
    }
}
