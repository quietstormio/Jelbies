//
//  ParkNames.swift
//  Visitor names stay unique (2026-11-05). The cause of "the same friend twice" on the Friends page: the seeded pool has 16 different names, but the optional
//  on-device writer (ParkBook.warmUp) used to rewrite a name with whatever the model answered, with no check against the other visitors, the player's Jelbies
//  ("Pip") or the personality words it was prompted with ("Zippy"), so two records could end up with one name. Here: the reserved set, fresh names, and the
//  idempotent migration that reconciles an existing save (merge true twins, rename the others). Pure values; ParkBook applies it on load.
//

import Foundation

nonisolated enum ParkNames {
    /// The comparison key: trimmed, lower case.
    static func key(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Names no visitor may take: the player species / roster Jelbies (`rosterNames`: the base names and any the player typed), the personality words
    /// ("Zippy", "Mellow", "Silly", "Easygoing") and the colour names.
    static func reserved(rosterNames: [String]) -> Set<String> {
        var s = Set(rosterNames.map(key).filter { !$0.isEmpty })
        for st in ParkStyle.allCases { s.insert(key(st.word)) }
        for c in ParkColour.allCases { s.insert(key(c.title)) }
        return s
    }

    /// More hand-written names, used when the model's name or a twin's name has to be replaced.
    static let spare = ["Maple", "Rafi", "Gus", "Hazel", "Ziggy", "Willow", "Cosmo", "Peanut", "Lulu", "Basil", "Fern", "Toffee", "Ripley", "Mabel", "Pixel",
                        "Skipper", "Moxie", "Beep", "Cricket", "Jellybean", "Nutmeg", "Opal", "Quill", "Rosie", "Sparky", "Tofu", "Umi", "Velvet", "Wiggle", "Yarrow"]

    /// A name not in `taken` (and not reserved): the hand-written lists first, then numbered.
    static func fresh(avoiding taken: Set<String>, seed: Int = 0) -> String {
        let all = ParkWords.names + spare
        for i in 0..<all.count {
            let n = all[(i + seed) % all.count]
            if !taken.contains(key(n)) { return n }
        }
        var k = 2
        while taken.contains(key("Friend \(k)")) { k += 1 }
        return "Friend \(k)"
    }

    /// True when the visitor with this name would break the rules against `others`.
    static func isFree(_ name: String, taken: Set<String>) -> Bool {
        let k = key(name)
        return !k.isEmpty && !taken.contains(k)
    }

    /// The migration. Returns true when anything changed. Idempotent: a second run on its own output changes nothing.
    ///  1. a visitor named like a player Jelbie / personality word / colour is renamed (it keeps its friendship);
    ///  2. a later visitor with the SAME name AND colour as an earlier one is a true twin: its friendship is folded into the earlier one (max level points per
    ///     character, lastSeen max, introduced if either) and it is marked `mergedInto` (the id stays, ids are pool indices);
    ///  3. a later visitor that merely shares a name gets a fresh unique name (its friendship is kept).
    @discardableResult
    static func reconcile(_ vs: inout [ParkVisitor], reserved: Set<String>) -> Bool {
        var changed = false
        var taken = reserved
        var holder: [String: Int] = [:]          // name key -> index in `vs` of the visitor that keeps it
        for i in vs.indices where vs[i].mergedInto == nil {
            let k = key(vs[i].name)
            if !k.isEmpty, !reserved.contains(k), let h = holder[k] {
                if vs[h].colour == vs[i].colour {          // a true twin
                    for (c, p) in vs[i].friendship { vs[h].friendship[c] = max(vs[h].friendship[c] ?? 0, p) }
                    vs[h].lastSeen = max(vs[h].lastSeen, vs[i].lastSeen)
                    vs[h].introduced = vs[h].introduced || vs[i].introduced
                    vs[i].mergedInto = vs[h].id
                    changed = true
                    continue
                }
            }
            if k.isEmpty || taken.contains(k) {          // reserved, or shares a name with a different visitor
                // (the names of every other active visitor count as taken, so the new one is unique against later ones too)
                var all = taken
                for j in vs.indices where j != i && vs[j].mergedInto == nil { all.insert(key(vs[j].name)) }
                let n = fresh(avoiding: all, seed: vs[i].id)
                vs[i].name = n; vs[i].levelLines = [:]
                changed = true
                taken.insert(key(n)); holder[key(n)] = i
            } else {
                taken.insert(k); holder[k] = i
            }
        }
        return changed
    }
}
