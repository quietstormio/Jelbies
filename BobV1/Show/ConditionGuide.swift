//
//  ConditionGuide.swift
//  The words and lists behind the Condition screen (the jelly jars): which foods fill a jar, what the Glow row says, what each jar's card says,
//  and the card itself (a small sheet opened by tapping a jar). Display only: nothing here changes a stat, a score, a decay or a food value.
//

import SwiftUI

@MainActor
enum ConditionGuide {
    // MARK: words

    /// The plain line under the title.
    static let subtitle = "Food fills the jars. Fuller jars score higher in the Jelly Show."
    static let drainLine = "Jars slowly drain, so feed before a show."
    static let glowCaption = "A bath right before the show adds points."
    /// The Glow 0...5 as a word: 0 none, 1 to 3 a little, 4 to 5 full.
    static func glowWord(of5 n: Int) -> String { n <= 0 ? "none" : n <= 3 ? "a little" : "full" }
    static func glowWord(_ glow: Float) -> String { glowWord(of5: ShowUI.glowOf5(glow)) }
    /// The small tag over a jar for today's theme: the main style "Today", the second one "Helps today".
    static func todayTag(_ t: WearTag, theme: ShowTheme?) -> String? {
        guard let theme else { return nil }
        return t == theme.main ? "Today" : t == theme.friend ? "Helps today" : nil
    }
    /// "Sweet foods and drinks fill this jar."
    static func styleLine(_ key: ConditionKey) -> String { "\(key.title) foods and drinks fill this jar." }
    static func rivalsLine(_ rank: ShowRank) -> String { "Rivals in \(rank.title) are about here." }
    static func jarLabel(_ tag: WearTag, number: Int, today: String?, grew: Bool) -> String {
        "\(tag.title) \(number)\(today.map { ", \($0)" } ?? "")\(grew ? ", just grew" : ""), double tap for foods that fill it"
    }

    // MARK: foods that fill a jar

    struct Filler: Identifiable {
        var item: StoreItem
        var gain: Float
        var count: Int          // in the Bag (0 = not owned: the Shop sells it)
        var isDrink: Bool { item.kind == .drink }
        var owned: Bool { count > 0 }
        var id: String { item.id }
    }
    /// The Shop foods and drinks that raise this jar, the biggest gain first.
    static func allFoods(raising key: ConditionKey) -> [(item: StoreItem, gain: Float)] {
        StoreCatalog.items.compactMap { it in
            guard let f = it.food, let c = Consumables.with(id: f), let g = c.condition[key], g > 0 else { return nil }
            return (it, g)
        }
        .sorted { $0.gain != $1.gain ? $0.gain > $1.gain : $0.item.name < $1.item.name }
    }
    /// What the jar card lists: every food and drink the player owns that raises the jar first, then up to `shopMax` in all they do not own (marked with the Shop).
    static func fillers(raising key: ConditionKey, count: (String) -> Int, shopMax: Int = 3) -> [Filler] {
        let all = allFoods(raising: key).map { Filler(item: $0.item, gain: $0.gain, count: count($0.item.id)) }
        return all.filter(\.owned) + Array(all.filter { !$0.owned }.prefix(shopMax))
    }
    /// The last meals that filled this jar, newest first.
    static func meals(filling key: ConditionKey, in meals: [MealEntry], max n: Int = 3) -> [MealEntry] {
        Array(meals.filter { ($0.gains[key.rawValue] ?? 0) > 0 }.prefix(n))
    }
}

/// The jar card: one style, what fills it, the Feed button, the last meals that filled it.
struct ConditionJarCard: View {
    let care: GameCare
    var who: Int
    var tag: WearTag
    var feed: (() -> Void)?
    var drink: (() -> Void)?
    var close: () -> Void

    var body: some View {
        let key = tag.condition
        let list = ConditionGuide.fillers(raising: key, count: { care.store.count($0) })
        let meals = ConditionGuide.meals(filling: key, in: care.jelly(who)?.stats.meals ?? [])
        let target = ShowUI.target(after: care.show.progress.unlockedRanks)
        let feedOK = feed != nil && HUDMenu.enabled(.feed, .group, care: care)
        let drinkOK = drink != nil && HUDMenu.enabled(.drink, .group, care: care)
        let ownsDrink = list.contains { $0.owned && $0.isDrink }
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TagChip(tag: tag, size: 18)
                    Spacer()
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                        .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("jarcard-close")
                }
                Text(ConditionGuide.styleLine(key)).font(SK.font(15, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
                if let target { Text(ConditionGuide.rivalsLine(target.rank)).font(SK.font(12, .bold)).foregroundStyle(ShowUI.goldText).fixedSize(horizontal: false, vertical: true) }
                Text("Fills it").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
                VStack(spacing: 8) {
                    ForEach(list) { f in
                        HStack(spacing: 10) {
                            ItemArt(item: f.item, size: 44)
                            Text(f.item.name).font(SK.font(15, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
                            if f.isDrink { Image(systemName: HUDMenu.symbol(.drink)).font(.system(size: 14, weight: .heavy)).foregroundStyle(SK.skyDeep).accessibilityLabel("Drink") }
                            Spacer(minLength: 4)
                            if f.owned { Text("x\(f.count)").font(SK.font(13, .heavy)).foregroundStyle(SK.muted) }
                            else {
                                HStack(spacing: 4) { Image(systemName: "bag.fill").font(.system(size: 11, weight: .black)); Text("Shop").font(SK.font(12, .black)) }
                                    .foregroundStyle(SK.ink).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(SK.honey.opacity(0.9)))
                            }
                        }
                        .padding(8).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(f.owned ? 0.85 : 0.5)))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("jarcard-food-\(f.item.id)")
                    }
                }
                HStack(spacing: 10) {
                    ShowCTA(title: "Feed", symbol: "fork.knife", enabled: feedOK, id: "jarcard-feed", height: 52) { feed?() }
                    if ownsDrink { ShowCTA(title: "Drink", symbol: HUDMenu.symbol(.drink), enabled: drinkOK, id: "jarcard-drink", height: 52) { drink?() } }
                }
                if !meals.isEmpty {
                    Text("Last meals").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
                    ForEach(Array(meals.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 6) {
                            Text("\(m.food) +\(max(1, Int(((m.gains[key.rawValue] ?? 0) * 100).rounded())))").font(SK.font(12, .heavy)).foregroundStyle(SK.ink)
                            Spacer(minLength: 4)
                            (Text(m.date, style: .relative) + Text(" ago")).font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("jarcard-\(tag.rawValue)")
    }
}

extension WearTag: Identifiable { var id: String { rawValue } }
