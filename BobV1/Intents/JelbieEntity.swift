//
//  JelbieEntity.swift
//  The Jelbies as Siri / Shortcuts know them (AppEntity): id, name, colour, read from the roster the game last published to the App Group
//  (JellySnapshot), and none before the game has ever run. Matching by name is loose ("bob", "Pip").
//  Never touches GameCare / Metal: intents may run with the app in the background.
//

import AppIntents
import Foundation

nonisolated struct JelbieEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Jelbie")
    static let defaultQuery = JelbieQuery()

    var id: Int
    var name: String
    var color: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(JelbieEntity.colorWord(color)) Jelbie")
    }

    static func colorWord(_ c: String) -> String {
        switch c { case "blue": return "Blue"; case "yellow": return "Yellow"; case "green": return "Green"; case "purple", "lavender": return "Lavender"; case "teddy": return "Brown"; case "pearl": return "White"; case "panda": return "Black and white"; default: return c.capitalized }
    }
}

/// Where the entities come from: the snapshot (names the player sees); none before the game has ever published one.
nonisolated enum JelbieRoster {
    /// The Jelbies in the room right now (from the shared snapshot) or none.
    /// `count` / `roster` are kept for source compatibility and no longer used.
    static func current(directory: URL? = JellyShare.containerURL, count: Int = JellyRoster.maxCount, roster: [Int] = JellyRoster.launchIDs()) -> [JelbieEntity] {
        if let snap = JellySnapshot.read(from: directory), !snap.jellies.isEmpty {
            return snap.jellies.sorted { $0.id < $1.id }.map { JelbieEntity(id: $0.id, name: $0.name, color: $0.color) }
        }
        return []          // no snapshot (fresh install, the game never run): no Jelbies yet, so the Shortcuts picker offers none (it used to offer Bob / Pip / Moss)
    }
    /// SPECIES id -> colour name (Bob blue, Pip yellow, Moss green, Lavender lavender), the same as WidgetBridge.colorName (which is main-actor bound).
    static func colorName(_ id: Int) -> String { ["blue", "yellow", "green", "lavender", "teddy", "pearl", "panda"][min(max(id, 0), 6)] }
    /// A loose name match: case-insensitive, prefix or contained ("bob", "Bobby" -> Bob).
    static func match(_ text: String, in list: [JelbieEntity]) -> [JelbieEntity] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return list }
        return list.filter { e in
            let n = e.name.lowercased()
            return n == t || n.hasPrefix(t) || t.hasPrefix(n) || t.contains(n)
        }
    }
}

nonisolated struct JelbieQuery: EntityQuery, EntityStringQuery, Sendable {
    init() {}
    func entities(for identifiers: [Int]) async throws -> [JelbieEntity] {
        JelbieRoster.current().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [JelbieEntity] { JelbieRoster.current() }
    func entities(matching string: String) async throws -> [JelbieEntity] { JelbieRoster.match(string, in: JelbieRoster.current()) }
}
