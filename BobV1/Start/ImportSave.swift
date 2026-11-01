//
//  ImportSave.swift
//  `-ImportSave 1` (device-safe, one-shot): brings an OLD save's room back into the CURRENT game. Reads <app container>/Documents/import_save.plist (a
//  UserDefaults plist pushed with `devicectl device copy to`); a missing file does nothing. The current game keeps its identity and progress (roster,
//  JellyCoins, needs, stats, perks, grime, words, circuit, park, guests, flags); the old one's room layout (StoreBook `placedAt` + `stash` + `room` +
//  `nextDecorUID`), owned rooms / decor / wearables / pages, theme, town tab and audio settings are merged in.
//

import Foundation

nonisolated enum ImportSave {
    static let argKey = "ImportSave", appliedKey = "ImportSave.applied"
    static let fileName = "import_save.plist"
    /// Plain settings copied over when the old plist has them.
    static let settingKeys = ["ThemeColor.v1", "townCategory", "Audio.musicOn", "Audio.musicVolume", "Audio.sfxOn", "Audio.sfxVolume"]

    struct Report {
        var applied = false
        var lines: [String] = []
        var dropped: [String] = []
        var summary: String { "[import] " + lines.joined(separator: "; ") + (dropped.isEmpty ? "" : " | dropped: " + dropped.joined(separator: ", ")) }
    }

    static var defaultURL: URL { URL.documentsDirectory.appending(path: fileName) }

    /// The launch hook. `arg` is the `-ImportSave` value (nil = not passed). 0 re-arms. Returns the report (applied == false when it did nothing).
    @discardableResult
    static func apply(arg: Int?, url: URL = defaultURL, defaults d: UserDefaults = .standard) -> Report {
        guard let arg else { return Report() }
        if arg == 0 { d.removeObject(forKey: appliedKey); return Report() }
        guard d.string(forKey: appliedKey) != "1" else { return Report() }
        guard let data = try? Data(contentsOf: url),
              let old = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            NSLog("[import] no readable %@ at %@; nothing done", fileName, url.path)
            return Report()
        }
        let r = merge(old: old, into: d)
        d.set("1", forKey: appliedKey)
        NSLog("%@", r.summary)
        return r
    }

    static func merge(old: [String: Any], into d: UserDefaults) -> Report {
        var r = Report(); r.applied = true
        var settings = 0
        for k in settingKeys { if let v = old[k] { d.set(v, forKey: k); settings += 1 } }
        r.lines.append("settings \(settings)/\(settingKeys.count)")

        // StoreBook: parse the old JSON loosely so an unknown id drops one entry, not the whole save.
        guard let oldData = old[StoreBook.key] as? Data,
              let oj = (try? JSONSerialization.jsonObject(with: oldData)) as? [String: Any] else {
            r.lines.append("no StoreBook in the old save"); return r
        }
        var s = (d.data(forKey: StoreBook.key)).flatMap { try? JSONDecoder().decode(StoreBook.Saved.self, from: $0) } ?? StoreBook.Saved()

        // Ownership: max per catalogue id (consumables are never summed), unknown ids dropped.
        var counts = 0
        for (k, v) in (oj["counts"] as? [String: Any]) ?? [:] {
            guard let n = (v as? NSNumber)?.intValue else { continue }
            guard StoreCatalog.item(k) != nil else { r.dropped.append("item:\(k)"); continue }
            if n > (s.counts[k] ?? 0) { s.counts[k] = n; counts += 1 }
        }
        let wear = ((oj["wearables"] as? [String]) ?? []).filter { WearLook(rawValue: $0) != nil }
        let wearNew = wear.filter { !s.wearables.contains($0) }
        s.wearables += wearNew
        let awardNew = ((oj["awarded"] as? [String]) ?? []).filter { !(s.awarded ?? []).contains($0) }
        s.awarded = (s.awarded ?? []) + awardNew
        let pageNew = ((oj["pages"] as? [String]) ?? []).filter { !s.pages.contains($0) }
        s.pages += pageNew
        var rooms = s.rooms ?? []
        for id in (oj["rooms"] as? [String]) ?? [] {
            if RoomID(rawValue: id) == nil { r.dropped.append("room:\(id)") } else if !rooms.contains(id) { rooms.append(id) }
        }
        s.rooms = rooms.isEmpty ? nil : rooms

        // Layout.
        func decode(_ any: Any?, room: String) -> [PlacedDecor] {
            var out: [PlacedDecor] = []
            for e in (any as? [[String: Any]]) ?? [] {
                guard let kind = e["kind"] as? String, DecorKind(rawValue: kind) != nil,
                      let pd = (try? JSONSerialization.data(withJSONObject: e)).flatMap({ try? JSONDecoder().decode(PlacedDecor.self, from: $0) })
                else { r.dropped.append("placement:\(room)/\((e["kind"] as? String) ?? "?")"); continue }
                out.append(pd)
            }
            return out
        }
        let placed = decode(oj["placedAt"], room: "current")
        var stash: [String: [PlacedDecor]] = [:]
        for (room, list) in (oj["stash"] as? [String: Any]) ?? [:] {
            guard RoomID(rawValue: room) != nil else { r.dropped.append("stashroom:\(room)"); continue }
            let l = decode(list, room: room); if !l.isEmpty { stash[room] = l }
        }
        s.placedAt = placed
        s.stash = stash.isEmpty ? nil : stash
        let oldRoom = oj["room"] as? String
        s.room = (oldRoom.flatMap { RoomID(rawValue: $0) } != nil && rooms.contains(oldRoom!)) ? oldRoom : nil
        let all = placed + stash.values.flatMap { $0 }
        s.nextDecorUID = max(s.nextDecorUID ?? 1, (oj["nextDecorUID"] as? NSNumber)?.intValue ?? 1, (all.map(\.uid).max() ?? 0) + 1)
        // Everything placed must be owned.
        var topped = 0
        for (id, n) in Dictionary(grouping: all, by: { $0.kind.storeID }).mapValues(\.count) where (s.counts[id] ?? 0) < n { s.counts[id] = n; topped += 1 }

        if let out = try? JSONEncoder().encode(s) { d.set(out, forKey: StoreBook.key) }
        r.lines.append("placed \(placed.count) in room \(s.room ?? "home")")
        r.lines.append("stashed \(stash.values.reduce(0) { $0 + $1.count }) in \(stash.count) other rooms")
        r.lines.append("rooms owned +\(rooms.count) (\(rooms.joined(separator: ",")))")
        r.lines.append("items raised \(counts) (+\(topped) to cover placed)")
        r.lines.append("wearables +\(wearNew.count), awarded +\(awardNew.count), pages +\(pageNew.count)")
        return r
    }
}
