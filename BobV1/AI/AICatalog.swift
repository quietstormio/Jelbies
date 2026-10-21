//
//  AICatalog.swift
//  What a voice command may refer to: the Jellies in the room and the things they can act on (foods, drinks, placed decor, toys, wearables).
//  Both tiers of the intent pipeline read it: Tier A lists the ids in its instructions and its output is validated against them; Tier B fuzzy-matches
//  spoken words against the names. Foods and drinks come from `Consumables`. Decor, toys and wearables have no model in this tree yet, so
//  other features plug theirs in through `AICatalogRegistry.providers` (no edit here): until then an object of those kinds is "not here".
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
        var best: (item: CatalogItem, score: Float)?
        for it in pool {
            let words = ([it.id, it.name] + it.aliases).map(VoiceMatcher.normalise).filter { !$0.isEmpty }
            if let h = VoiceMatcher.best(in: tokens, among: words), h.score >= 0.8 {
                if h.score > (best?.score ?? 0) { best = (it, h.score) }
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
}
