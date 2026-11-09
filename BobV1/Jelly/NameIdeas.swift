//
//  NameIdeas.swift
//  The naming step's "Ideas:" chips: a curated, kid-safe list of cute names per species (about 12 each, matching the species' vibe). The three chips for a candidate are
//  deterministic (species + candidate index), never a name already used at home (case-insensitive), and the first one is always `JellyRoster.suggestedName`.
//

import Foundation

nonisolated enum NameIdeas {
    /// By species id (JellyRoster: 0 Blueberry, 1 Lemon Drop, 2 Matcha, 3 Taro, 4 Teddy, 5 Pearl, 6 Panda). Every name is 12 letters or fewer (the name field's limit).
    static let pool: [Int: [String]] = [
        0: ["Bob", "Bloop", "Drizzle", "Pebble", "Misty", "Dewdrop", "Skye", "Bubbles", "Marlin", "Indigo", "Puddle", "Waves"],
        1: ["Pip", "Sunny", "Butter", "Nugget", "Honey", "Daisy", "Sunbeam", "Biscuit", "Goldie", "Zest", "Muffin", "Peaches"],
        2: ["Moss", "Fern", "Clover", "Sprout", "Pickle", "Basil", "Olive", "Mochi", "Sage", "Willow", "Minty", "Pea"],
        3: ["Lavender", "Lilac", "Twinkle", "Dreamy", "Orchid", "Violet", "Wisp", "Luna", "Starlight", "Plum", "Fluff", "Breeze"],
        4: ["Teddy", "Cocoa", "Biscuit", "Honey", "Cookie", "Peanut", "Mocha", "Toffee", "Maple", "Cinnamon", "Waffle", "Cuddles"],
        5: ["Pearl", "Shimmer", "Opal", "Glimmer", "Sparkle", "Moonbeam", "Shelly", "Marble", "Coral", "Glow", "Tinsel", "Bubbly"],
        6: ["Panda", "Bamboo", "Domino", "Oreo", "Patches", "Pogo", "Bao", "Button", "Inky", "Tofu", "Dotty", "Zigzag"],
    ]

    /// Three ideas for candidate `index` (0...2) of `species`: the suggested name first, then two from the species' list (a different pair for each candidate).
    static func ideas(species: Int, index: Int, taken: [String]) -> [String] {
        let sp = min(max(species, 0), JellyRoster.knownCount - 1)
        let used = Set(taken.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var out = [JellyRoster.suggestedName(species: sp, taken: taken)]
        let list = pool[sp] ?? []
        let n = list.count
        guard n > 0 else { return out }
        let start = 1 + min(max(index, 0), 2) * 3          // 1, 4, 7 (entry 0 is the base name, already first)
        var k = 0
        while out.count < 3, k < n * 2 {
            let name = list[(start + k) % n]
            k += 1
            if used.contains(name.lowercased()) || out.contains(where: { $0.lowercased() == name.lowercased() }) { continue }
            out.append(name)
        }
        return out
    }
}
