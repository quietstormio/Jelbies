//
//  AICatalog.swift
//  What a voice command may refer to: the Jellies in the room and the things they can act on (foods, drinks, placed decor, toys, wearables).
//  Both tiers of the intent pipeline read it: Tier A lists the ids in its instructions and its output is validated against them; Tier B fuzzy-matches
//  spoken words against the names. Foods and drinks come from `Consumables` (store foods only while the bag has some); decor and toys are the pieces
//  PLACED in the room (one entry per kind; the Jelly picks the nearest free one); wearables are the looks the player OWNS (StoreBook). Tests add
//  extra items through `AICatalogRegistry.providers`.
//

import Foundation

nonisolated struct CatalogItem: Equatable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable { case food, drink, decor, toy, wearable }
    let id: String
    let name: String
    let kind: Kind
    /// Extra spoken forms ("hat" for "pirate hat", "bean bag" for "beanbag").
    var aliases: [String] = []
}

/// Who and what the command system knows right now.
nonisolated struct AICatalog: Equatable, Sendable {
    struct Jelly: Equatable, Sendable, Hashable { let id: Int; let name: String }
    var jellies: [Jelly]
    var items: [CatalogItem]

    func item(id: String) -> CatalogItem? { items.first { $0.id == id } }
    func items(of kind: CatalogItem.Kind) -> [CatalogItem] { items.filter { $0.kind == kind } }
    func jelly(named n: String) -> Jelly? { let k = VoiceMatcher.normalise(n); return jellies.first { VoiceMatcher.normalise($0.name) == k } }
    var jellyIDs: [Int] { jellies.map(\.id) }

    /// Best item for spoken tokens (exact / fuzzy against id, name and aliases, whole phrase and token pairs); nil when nothing is close.
    /// `kinds` narrows the search (a "put on" verb only wants wearables).
    func match(_ tokens: [String], kinds: Set<CatalogItem.Kind>? = nil) -> CatalogItem? {
        guard !tokens.isEmpty else { return nil }
        let pool = items.filter { kinds?.contains($0.kind) ?? true }
        // Stricter than the trick matcher: an object is only "heard" exactly, or with ONE edit in a word of 5+ letters ("pizzas", "berrys").
        // The loose rule (two edits, or one in a short word) made "what" a hat, "think" a drink and "weather" water.
        let cands = VoiceMatcher.candidates(tokens)
        var best: (item: CatalogItem, score: Float)?
        for it in pool {
            let words = ([it.id, it.name] + it.aliases).map(VoiceMatcher.normalise).filter { !$0.isEmpty }
            for w in words {
                for c in cands {
                    let s = VoiceMatcher.score(heard: c, stored: w)
                    guard s == 1 || (s >= 0.9 && w.count >= 5) else { continue }
                    if s > (best?.score ?? 0) { best = (it, s) }
                }
            }
        }
        return best?.item
    }

    /// Short id list for the model's instructions (names in brackets when they differ from the id).
    func promptList(of kind: CatalogItem.Kind) -> String {
        items(of: kind).map { $0.name.lowercased() == $0.id ? $0.id : "\($0.id) (\($0.name))" }.joined(separator: ", ")
    }
}

/// Other features (store, wardrobe, room decor) add their items here at launch; the catalog is rebuilt on every command.
nonisolated enum AICatalogRegistry {
    nonisolated(unsafe) static var providers: [@Sendable () -> [CatalogItem]] = []

    /// Foods and drinks from the dining catalogue plus every registered provider's items.
    static func items() -> [CatalogItem] {
        var out: [CatalogItem] = Consumables.all.map {
            CatalogItem(id: $0.id, name: $0.name, kind: $0.kind == .food ? .food : .drink, aliases: Self.foodAliases[$0.id] ?? [])
        }
        for p in providers { out += p() }
        var seen: Set<String> = []
        return out.filter { seen.insert($0.id).inserted }
    }
    static let foodAliases: [String: [String]] = ["berries": ["berry", "fruit"], "pizza": ["slice"], "water": ["drink"], "soda": ["pop", "fizzy"]]

    static func catalog(jellies: [(id: Int, name: String)]) -> AICatalog {
        AICatalog(jellies: jellies.map { AICatalog.Jelly(id: $0.id, name: $0.name) }, items: items())
    }

    /// The live room: free foods plus store foods in the bag, placed decor and toys, owned wearables, then the providers' items.
    @MainActor static func catalog(jellies: [(id: Int, name: String)], store: StoreBook) -> AICatalog {
        var out: [CatalogItem] = Consumables.all.filter { !$0.stored || store.count(food: $0.id) > 0 }.map {
            CatalogItem(id: $0.id, name: $0.name, kind: $0.kind == .food ? .food : .drink, aliases: Self.foodAliases[$0.id] ?? [])
        }
        var kinds: [DecorKind] = []
        for p in store.placedDecor where !kinds.contains(p.kind) { kinds.append(p.kind) }
        out += kinds.map { CatalogItem(id: $0.storeID, name: $0.title, kind: $0.category == .toys ? .toy : .decor, aliases: Self.decorAliases[$0] ?? []) }
        for it in StoreCatalog.items where it.isWearable {
            guard let look = it.wear, store.ownsLook(look) else { continue }
            var al: [String] = []
            if let last = it.name.split(separator: " ").last.map({ String($0).lowercased() }), last != it.name.lowercased() { al.append(last) }
            if it.kind == .shoes { al.append("shoes") }
            out.append(CatalogItem(id: it.id, name: it.name, kind: .wearable, aliases: al))
        }
        for p in providers { out += p() }
        var seen: Set<String> = []
        return AICatalog(jellies: jellies.map { AICatalog.Jelly(id: $0.id, name: $0.name) }, items: out.filter { seen.insert($0.id).inserted })
    }

    /// Spoken forms of the decor (the id is "decor-beanbag", the name "Beanbag").
    static let decorAliases: [DecorKind: [String]] = [
        .beanbag: ["bean bag", "bag"], .cushion: ["cushion", "pillow"], .plant: ["plant"], .ball: ["ball"], .rug: ["rug"], .toybox: ["toy box", "box", "toys"],
        .nightlight: ["night light", "light"], .bouncymat: ["mat", "bouncy mat", "trampoline"], .loveseat: ["sofa", "couch", "seat"], .petbed: ["bed", "pet bed"],
        .pouf: ["pouffe", "stool"], .rockingchair: ["rocking chair", "rocker", "chair"], .armchair: ["arm chair", "chair"], .swing: ["swing"],
        .diningset: ["table", "dining table", "dining set"], .bookshelf: ["shelf", "bookcase", "books"], .wardrobe: ["closet"], .divider: ["divider", "screen"],
        .floorlamp: ["lamp", "floor lamp"], .slide: ["slide"], .monstera: ["monstera", "big plant"], .duck: ["duck", "ducky"], .blocks: ["blocks", "tower"],
        .spintop: ["top", "spinning top"], .toycar: ["car", "toy car"], .yarnball: ["yarn", "wool", "yarn ball"], .drum: ["drum"], .soccerball: ["football", "soccer ball", "soccer"], .minigoal: ["goal", "mini goal", "net"],
    ]
}
