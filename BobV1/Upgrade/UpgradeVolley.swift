//
//  UpgradeVolley.swift
//  The Volleyball side of the Upgrade menu (the generic sheet is Upgrade/UpgradeSheet.swift; the Track's twin is in Store/TownUI.swift): the config the Volleyball lobby hands the sheet
//  (four skills from VolleyStats, the Bag's zoomies / focus foods as the "next match" power-up) and the buy / pick answers.
//

import SwiftUI

extension GameCare {
    private static let volleySymbols: [VolleyStatKind: [String]] = [
        .speed: ["figure.run", "hare.fill"], .power: ["bolt.fill", "flame.fill"], .hops: ["arrow.up.circle.fill", "figure.jumprope"], .timing: ["timer", "scope"],
    ]
    private static func volleyTint(_ k: VolleyStatKind) -> Color {
        switch k { case .speed: return SK.sky; case .power: return SK.pink; case .hops: return SK.mint; case .timing: return SK.honeyDeep }
    }

    /// `p` = the Jelbie shown; `first` = the lobby's first pick (the team is `first` + his partner).
    func volleyUpgradeConfig(_ p: JellyProfile, team first: JellyProfile) -> UpgradeConfig {
        let book = upgrades
        _ = book.revision          // (the sheet redraws when points or the choice change)
        let st = volley.book.stats(character: p.character)
        let skills = VolleyStatKind.allCases.map { k -> UpgradeSkillInfo in
            let lv = book.level(k, stats: st)
            return UpgradeSkillInfo(id: k.rawValue, title: k.title, blurb: k.blurb, symbols: Self.volleySymbols[k] ?? [], tint: Self.volleyTint(k).opacity(0.4), level: lv, cost: UpgradeTuning.cost(level: lv))
        }
        var c = UpgradeConfig(gameWord: "Jelly Volleyball", heroName: p.name, winLine: "Win = \(UpgradeTuning.volleyPoints(win: true)) points", points: book.points(.volley, character: p.character),
                              backdrop: Color(hex: 0xBFE4EE), podium: Color(hex: 0xE6CC8C), skills: skills, tiles: volleyPowerTiles(), selectedTile: volleyChosenTile(p))
        // the team switcher: the first pick and his partner, each with his own points; none when the team is one Jelbie
        let team = [first] + [volleyPartner(for: first.id)].compactMap { $0 }
        c.chips = team.count > 1 ? team.map { UpgradeChip(id: $0.id, name: $0.name, points: book.points(.volley, character: $0.character)) } : []
        c.powerHeading = "Power-up for the next match"
        c.sand = Color(hex: 0xF3DFA8)
        c.heroHeight = 165
        return c
    }

    /// The zoomies (Speed) and focus (Timing) foods the Bag has, with how many; with none, Donut and Sandwich greyed.
    private func volleyPowerTiles() -> [UpgradePowerTile] {
        func tile(_ item: StoreItem, _ n: Int) -> UpgradePowerTile {
            UpgradePowerTile(id: item.id, name: item.name, tag: n > 0 ? "\(item.perk == .zoomies ? "Speed" : "Timing") \u{00B7} \u{00D7}\(n)" : "Get in Shop", item: item, count: n)
        }
        let owned = StoreCatalog.items.filter { $0.food != nil && ($0.perk == .zoomies || $0.perk == .focus) && store.count($0.id) > 0 }
        let foods = owned.isEmpty ? ["donut", "sandwich"].compactMap { StoreCatalog.item($0) }.map { tile($0, 0) } : owned.map { tile($0, store.count($0.id)) }
        return [UpgradePowerTile(id: UpgradePowerTile.noneID, name: "None", tag: "No boost", item: nil, count: 0)] + foods
    }

    private func volleyChosenTile(_ p: JellyProfile) -> String {
        if let c = upgrades.chosen(.volley, character: p.character), store.count(c) > 0 { return c }
        return UpgradePowerTile.noneID
    }

    func volleyBuySkill(_ id: String, _ p: JellyProfile) -> Bool {
        guard let k = VolleyStatKind(rawValue: id) else { return false }
        return upgrades.buy(k, volley: volley.book, character: p.character)
    }

    /// True when a food (not None) is now chosen.
    func volleyPickPower(_ id: String, _ p: JellyProfile) -> Bool {
        if id == UpgradePowerTile.noneID { upgrades.choose(nil, .volley, character: p.character); return false }
        upgrades.choose(id, .volley, character: p.character)
        return true
    }
}
