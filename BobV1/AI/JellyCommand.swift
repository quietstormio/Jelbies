//
//  JellyCommand.swift
//  One natural voice command, understood: who it is for, what to do, with what and with whom. Produced by either tier (the rule parser or the
//  on-device model) and VALIDATED against the live catalog before anything runs: a Jelly name that is not in the room, a food / decor / wearable
//  id that is not owned or placed, or a partner that is not here is rejected (the Jelly gives his confused "?" instead).
//  `RawCommand` is the model's unvalidated answer (plain strings) so the FoundationModels types never leave TierA.swift.
//

import Foundation

/// Everything a Jelly can be asked for. `JellyAction.supportedNow` gates what the room can carry out (everything, since checkpoint 7c: decor, the
/// wardrobe and the Track); an action whose object is missing ("go to the beanbag" with none placed) gets a "No beanbag in the room" line.
nonisolated enum JellyAction: Equatable, Sendable, Hashable {
    case come, stop, stopFighting, praise, scold, play
    /// A learned trick (sit, jacks, run, flip, look, and the store pages spin, hop, roll; come is `.come`).
    case trick(VoiceTrick)
    /// Bedtime: the legacy "goodnight" (yawn, cuddle pile, tucked in).
    case feed, drink, sleep, clean
    /// "Wake up" / "good morning": the sleepers wake (the named one, or everyone).
    case wake
    /// Go to / sit on a piece of decor (`object` = its id).
    case goTo
    /// Put on a wearable (`object` = its id).
    case wear
    /// Play with another Jelly (`partner`), optionally with a toy (`object`).
    case playWith
    case race, train
    /// "Who's hungry / thirsty / wants love?"
    case whoIs(NeedKind)
    case none

    /// The persisted / model id.
    var key: String {
        switch self {
        case .come: return "come"; case .stop: return "stop"; case .stopFighting: return "stopFighting"; case .praise: return "praise"
        case .scold: return "scold"; case .play: return "play"; case .trick(let t): return t.rawValue
        case .feed: return "feed"; case .drink: return "drink"; case .sleep: return "sleep"; case .clean: return "clean"; case .wake: return "wake"
        case .goTo: return "goTo"; case .wear: return "wear"; case .playWith: return "playWith"; case .race: return "race"; case .train: return "train"
        case .whoIs(.hunger): return "whoIsHungry"; case .whoIs(.thirst): return "whoIsThirsty"; case .whoIs(.attention): return "whoWantsLove"
        case .none: return "none"
        }
    }
    init?(key: String) {
        switch key {
        case "come": self = .come; case "stop": self = .stop; case "stopFighting": self = .stopFighting; case "praise": self = .praise
        case "scold": self = .scold; case "play": self = .play; case "feed": self = .feed; case "drink": self = .drink
        case "wake": self = .wake; case "sleep": self = .sleep; case "clean": self = .clean; case "goTo": self = .goTo; case "wear": self = .wear; case "playWith": self = .playWith
        case "race": self = .race; case "train": self = .train; case "whoIsHungry": self = .whoIs(.hunger); case "whoIsThirsty": self = .whoIs(.thirst)
        case "whoWantsLove": self = .whoIs(.attention); case "none": self = .none
        case "jumpingJacks": self = .trick(.jacks)
        default: if let t = VoiceTrick(rawValue: key), t != .come { self = .trick(t) } else { return nil }
        }
    }
    static let allKeys: [String] = ["come", "stop", "stopFighting", "praise", "scold", "play", "sit", "jacks", "run", "flip", "look", "spin", "hop", "roll", "feed", "drink",
                                    "sleep", "wake", "clean", "goTo", "wear", "playWith", "race", "train", "whoIsHungry", "whoIsThirsty", "whoWantsLove", "none"]

    /// The object kinds this action takes (nil = none; `.playWith` takes an optional toy; "go to" takes furniture or a toy).
    var objectKinds: Set<CatalogItem.Kind>? {
        switch self {
        case .feed: return [.food]; case .drink: return [.drink]; case .goTo: return [.decor, .toy]; case .wear: return [.wearable]; case .playWith: return [.toy]
        default: return nil
        }
    }
    /// The object is required for the command to mean anything (go WHERE, wear WHAT).
    var needsObject: Bool { self == .goTo || self == .wear }
    var needsPartner: Bool { self == .playWith }

    /// What this room can carry out today (everything since checkpoint 7c; kept as the gate for actions a future branch parses before it runs them).
    var supportedNow: Bool { true }
    /// The HUD's word for it.
    var title: String {
        switch self {
        case .come: return "come here"; case .stop: return "stop"; case .stopFighting: return "stop fighting"; case .praise: return "good job"
        case .scold: return "no"; case .play: return "play"; case .trick(let t): return t.title.lowercased()
        case .feed: return "eat"; case .drink: return "drink"; case .sleep: return "sleep"; case .wake: return "wake up"; case .clean: return "bath time"
        case .goTo: return "go to"; case .wear: return "put on"; case .playWith: return "play with"; case .race: return "race"; case .train: return "train"
        case .whoIs(.hunger): return "who's hungry?"; case .whoIs(.thirst): return "who's thirsty?"; case .whoIs(.attention): return "who wants love?"
        case .none: return "?"
        }
    }
}

/// Who a command is for.
nonisolated enum JellyWho: Equatable, Sendable, Hashable {
    /// Nobody named: the selected Jelly.
    case selected
    case jellies([Int])
    case everyone
    var asVoiceTarget: VoiceTarget {
        switch self { case .selected: return .selected; case .everyone: return .everyone; case .jellies(let ids): return ids.count == 1 ? .jelly(ids[0]) : .everyone }
    }
}

nonisolated struct JellyCommand: Equatable, Sendable, Hashable {
    enum Source: String, Sendable { case rules, model }
    var who: JellyWho = .selected
    var action: JellyAction
    /// A validated catalog id (food, drink, decor, toy, wearable).
    var object: String? = nil
    var partner: Int? = nil
    var source: Source = .rules
    /// The spoken object words when nothing in the catalog matched ("beanbag", "pirate hat"): the feedback names what is missing.
    var unknownObject: String? = nil

    var isActionable: Bool { action != .none && !(action.needsObject && object == nil) && !(action.needsPartner && partner == nil) }

    /// "Pip: go to sleep", "Everyone: come eat" (the HUD line).
    func summary(names: (Int) -> String) -> String {
        let who: String
        switch self.who {
        case .selected: who = ""
        case .everyone: who = "Everyone: "
        case .jellies(let ids): who = ids.map(names).joined(separator: " & ") + ": "
        }
        var what = action == .playWith ? "play" : action.title
        if let o = object { what += " " + Self.objectName(o).lowercased() }
        else if let u = unknownObject { what += " \(u)" }
        if let p = partner { what += " with \(names(p))" }
        return who + what
    }
}

extension JellyCommand {
    /// The spoken name of a catalog id: a food, a store item (a wearable), a decor kind, else the id itself.
    static func objectName(_ id: String) -> String {
        if let c = Consumables.with(id: id) { return c.name }
        if let it = StoreCatalog.item(id) { return it.name }
        if let k = DecorKind(storeID: id) { return k.title }
        return id.replacingOccurrences(of: "_", with: " ")
    }
}

/// The model's answer before validation: names and ids as it wrote them.
nonisolated struct RawCommand: Equatable, Sendable {
    var targets: [String] = []
    var action: String = "none"
    var object: String = ""
    var partner: String = ""
}

@MainActor
enum CommandValidation {
    /// Checks a raw answer against the catalog. Unknown Jelly names, unknown object ids (or an object of the wrong kind) and unknown partners are
    /// rejected (nil). Unknown actions are `.none` (the caller falls back). `"everyone"` / `"all"` as a target means everyone.
    static func validate(_ raw: RawCommand, catalog: AICatalog, names: JellyNames? = nil) -> JellyCommand? {
        let action = JellyAction(key: raw.action.trimmingCharacters(in: .whitespaces)) ?? .none
        var cmd = JellyCommand(action: action, source: .model)
        // targets
        let ts = raw.targets.map { VoiceMatcher.normalise($0) }.filter { !$0.isEmpty }
        if ts.contains(where: { ["everyone", "everybody", "all", "all of them", "you all"].contains($0) }) { cmd.who = .everyone }
        else if !ts.isEmpty {
            var ids: [Int] = []
            for t in ts {
                guard let id = resolveJelly(t, catalog: catalog, names: names) else { return nil }
                if !ids.contains(id) { ids.append(id) }
            }
            cmd.who = .jellies(ids)
        }
        // object
        let obj = VoiceMatcher.normalise(raw.object)
        if !obj.isEmpty, !["none", "nil", "null", "nothing"].contains(obj) {
            let kinds = action.objectKinds
            guard let it = catalog.item(id: obj) ?? catalog.match(obj.split(separator: " ").map(String.init), kinds: kinds) else { return nil }
            if let k = kinds, !k.contains(it.kind) { return nil }
            cmd.object = it.id
        }
        // partner
        let p = VoiceMatcher.normalise(raw.partner)
        if !p.isEmpty, !["none", "nil", "null"].contains(p) {
            guard let id = resolveJelly(p, catalog: catalog, names: names) else { return nil }
            cmd.partner = id
        }
        if action.needsObject, cmd.object == nil { return nil }
        if action.needsPartner, cmd.partner == nil { return nil }
        return cmd
    }

    static func resolveJelly(_ word: String, catalog: AICatalog, names: JellyNames?) -> Int? {
        if let j = catalog.jelly(named: word) { return j.id }
        if let n = names, let h = n.resolve(tokens: word.split(separator: " ").map(String.init)).first, catalog.jellyIDs.contains(h.id) { return h.id }
        return nil
    }
}
