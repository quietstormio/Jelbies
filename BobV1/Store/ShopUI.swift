//
//  ShopUI.swift
//  The Shop: a full screen with a pink wavy header, tabs (Snacks / Care / Wear / Tricks / Furniture / Toys), two-column item cards
//  (picture, perk chip, price, owned count) and a bottom sheet per item (what it does, condition chips, quantity, Buy).
//  Drops are earned only; there is no purchase of Drops anywhere.
//

import SwiftUI

enum ShopTab: String, CaseIterable, Identifiable {
    case snacks = "Snacks", care = "Care", wear = "Wear", tricks = "Tricks", furniture = "Furniture", toys = "Toys", rooms = "Rooms"
    var id: String { rawValue }
    var kinds: [StoreKind] {
        switch self {
        case .snacks: return [.food, .treat]; case .care: return [.supply]; case .wear: return [.shoes, .wear]; case .tricks: return [.trickPage]; case .furniture, .toys: return [.decor]; case .rooms: return [.room]
        }
    }
    var items: [StoreItem] {
        switch self {
        case .furniture: return StoreCatalog.decorItems(.furniture)
        case .toys: return StoreCatalog.decorItems(.toys)
        default: return kinds.flatMap { StoreCatalog.items($0) }.filter { !$0.awarded }
        }
    }
    /// The tab named by the `-StoreTab` capture aid ("decor" = furniture).
    static func named(_ s: String?) -> ShopTab? { let n = (s ?? "").capitalized; return ShopTab(rawValue: n == "Decor" ? "Furniture" : n) }
    /// Tabs with goods in them.
    static var shown: [ShopTab] { allCases.filter { !$0.items.isEmpty } }
}

struct ShopScreen: View {
    let care: GameCare
    var who: Int
    var back: () -> Void
    var goHome: () -> Void = {}          // leaves the Town / Shop (a room move starts its fade at once)
    @State private var tab: ShopTab = ShopTab.named(UserDefaults.standard.string(forKey: "StoreTab")) ?? .snacks          // (-StoreTab decor: capture aid)
    @Environment(\.verticalSizeClass) private var vsc          // .compact = a phone on its side
    private var wide: Bool { vsc == .compact }
    @Environment(\.dynamicTypeSize) private var dts
    /// The Wear tab's slot filter (nil = all).
    @State private var wearSlot: WearSlot? = WearSlot(rawValue: UserDefaults.standard.string(forKey: "StoreSlot") ?? "")          // (-StoreSlot head: capture aid)
    private var shown: [StoreItem] { tab == .wear ? tab.items.filter { wearSlot == nil || $0.wear?.slot == wearSlot } : tab.items }
    @State private var selected: StoreItem? = UserDefaults.standard.string(forKey: "StoreOpen") == "item" ? StoreCatalog.item(UserDefaults.standard.string(forKey: "StoreItem") ?? "sushi") : nil

    private var book: StoreBook { care.store }

    var body: some View {
        VStack(spacing: 0) {
            header
            if tab == .wear {
                SlotChips(slot: $wearSlot, slots: WearSlot.allCases.filter { s in ShopTab.wear.items.contains { $0.wear?.slot == s } }, idPrefix: "shop-slot-")
                    .padding(.horizontal, 16).padding(.top, 8)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dts.isAccessibilitySize ? 1 : (wide ? 4 : 2)), spacing: 12) {
                    ForEach(shown) { item in card(item) }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(SK.cream.ignoresSafeArea())
        .accessibilityIdentifier("shop-screen")
        .sheet(item: $selected) { item in
            ItemSheet(care: care, item: item, who: who, goHome: goHome) { selected = nil }
                .presentationDetents(wide ? [.large] : [.height(560), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(SK.cream)
        }
        .onAppear { AudioHub.shared.play(.storeOpen) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(SK.ink)
                        .dtWell()
                }
                .buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("shop-back")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Shop").font(SK.font(28, .semibold)).foregroundStyle(DT.ink)
                    Text("Spend your Drops on goodies").font(SK.font(12, .medium)).foregroundStyle(DT.ink2)
                }
                Spacer()
                DropsPill(wallet: care.bath.wallet)
            }
            .padding(.horizontal, 16).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShopTab.shown) { t in
                        Button {
                            if t != tab { AudioHub.shared.play(.pageTurn); withAnimation(.easeInOut(duration: 0.15)) { tab = t } }
                        } label: {
                            Text(t.rawValue).font(SK.font(15, .semibold)).foregroundStyle(t == tab ? DT.accent : DT.ink)
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .dtChip(selected: t == tab)
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("shop-tab-\(t.rawValue.lowercased())")
                        .accessibilityAddTraits(t == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 14)
        }
        .background(DT.paper.ignoresSafeArea(edges: [.top, .horizontal]))
        .overlay(alignment: .bottom) { DT.line.frame(height: 1) }
        .padding(.bottom, 4)
    }

    private func card(_ item: StoreItem) -> some View {
        let owned = book.owned(item)
        let afford = care.bath.wallet.count >= item.price
        return Button {
            AudioHub.shared.uiTap(); selected = item
        } label: {
            VStack(spacing: 8) {
                ItemArt(item: item, size: wide ? 84 : 104)
                Text(item.name).font(SK.font(15, .semibold)).foregroundStyle(SK.ink).jLine(1, scale: 0.8)
                if let p = item.perk { PerkChip(kind: p) }
                else if item.kind == .room { Text("New room").font(SK.font(11, .semibold)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(DT.fill)) }
                else if item.kind == .decor { Text(item.roomUnits == 1 ? "1 spot" : "\(item.roomUnits) spots").font(SK.font(11, .semibold)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(DT.fill)) }
                else { Text(item.isWearable ? (item.wear?.tags.prefix(2).map { $0.rawValue.capitalized }.joined(separator: " \u{00B7} ") ?? "Just for looks") : item.kind == .trickPage ? "New trick" : " ").font(SK.font(11, .bold)).foregroundStyle(SK.muted).padding(.vertical, 4) }
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(afford ? SK.sky : SK.muted.opacity(0.6))
                        Text("\(item.price)").font(SK.font(15, .semibold)).foregroundStyle(afford ? SK.ink : SK.muted)
                    }
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(Capsule().fill(DT.card))
                    Spacer(minLength: 0)
                    if owned > 0 {
                        Text(item.unique ? "Owned" : "owned x\(owned)").font(SK.font(11, .semibold)).foregroundStyle(SK.muted)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card).shadow(color: SK.shadow.opacity(0.10), radius: 5, y: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shop-item-\(item.id)")
        .accessibilityLabel("\(item.name), \(item.price) Drops\(owned > 0 ? ", owned \(owned)" : "")")
    }
}

/// The bottom sheet of one item.
struct ItemSheet: View {
    let care: GameCare
    let item: StoreItem
    var who: Int
    var goHome: () -> Void = {}
    var close: () -> Void
    @State private var refusal: String?
    @State private var qty = 1
    @State private var bought = 0
    @Environment(\.verticalSizeClass) private var vsc

    private var book: StoreBook { care.store }
    private var wallet: DropsWallet { care.bath.wallet }
    private var total: Int { item.price * (item.unique ? 1 : qty) }
    private var left: Int { wallet.count - total }

    var body: some View {
        Group {
            if vsc == .compact {
                // a phone on its side: the picture and name on the left, what it does and the Buy on the right, all of it scrolling if it must
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 8) {
                        ItemPicture(care: care, item: item, who: who, size: 150).padding(.top, 10)
                        Text(item.name).font(SK.font(22, .semibold)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
                        Text(item.description).font(SK.font(13, .semibold)).foregroundStyle(SK.muted).multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 260)
                    ScrollView {
                        VStack(spacing: 12) {
                            effectCard
                            buySection
                        }
                        .padding(.top, 14).padding(.bottom, 16)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 14) {
                    ItemPicture(care: care, item: item, who: who, size: 230).padding(.top, 14)
                    Text(item.name).font(SK.font(26, .semibold)).foregroundStyle(SK.ink)
                    Text(item.description).font(SK.font(15, .semibold)).foregroundStyle(SK.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
                    effectCard.padding(.horizontal, 16)
                    Spacer(minLength: 0)
                    buySection
                }
            }
        }
        .accessibilityIdentifier("item-sheet")
    }

    private var effectCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What it does").font(SK.font(12, .semibold)).foregroundStyle(SK.muted).textCase(.uppercase)
            HStack(spacing: 10) {
                Image(systemName: effectSymbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(SK.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(SK.honey))
                VStack(alignment: .leading, spacing: 2) {
                    Text(effectTitle).font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
                    Text(effectBlurb).font(SK.font(12, .semibold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !conditions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(conditions, id: \.0.rawValue) { k, v in
                        Text("\(k.title) +\(SK.points(v))").font(SK.font(12, .semibold)).foregroundStyle(SK.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(SK.mint.opacity(0.75)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.card))
    }

    private var buySection: some View {
        VStack(spacing: 12) {
            if !item.unique {
                HStack(spacing: 18) {
                    stepper("minus") { qty = max(1, qty - 1) }.disabled(qty <= 1)
                    Text("\(qty)").font(SK.font(24, .semibold)).foregroundStyle(SK.ink).frame(minWidth: 40).monospacedDigit()
                    stepper("plus") { if wallet.count >= item.price * (qty + 1), qty < 9 { qty += 1 } else { AudioHub.shared.play(.notEnough) } }
                }
            }
            buyButton.padding(.horizontal, vsc == .compact ? 0 : 16)
            if item.kind == .room, let r = item.room, book.owns(item), book.currentRoom != r {
                Button {
                    AudioHub.shared.uiTap()
                    if let b = care.switchRoom(r) { refusal = b.message } else { close(); goHome() }
                } label: {
                    Text("Move in now").font(SK.font(18, .semibold)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(SK.honey))
                }
                .buttonStyle(.plain).padding(.horizontal, vsc == .compact ? 0 : 16)
                .accessibilityLabel("Move in to \(item.name)")
                .accessibilityIdentifier("item-movein")
            }
            if let refusal {
                Text(refusal).font(SK.font(14, .semibold)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(SK.honey.opacity(0.9)))
                    .accessibilityIdentifier("item-movein-refusal")
            }
            Text(footer).font(SK.font(12, .bold)).foregroundStyle(SK.muted).padding(.bottom, 10)
        }
    }

    private func stepper(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(SK.ink)
                .frame(width: 48, height: 48).background(Circle().fill(DT.card))
        }.buttonStyle(.plain).accessibilityLabel(symbol == "plus" ? "More \(item.name)" : "Fewer \(item.name)").accessibilityValue("\(qty)").accessibilityIdentifier("item-qty-\(symbol)")
    }

    private var buyButton: some View {
        let owned = item.unique && book.owns(item)
        let can = !owned && left >= 0
        return Button {
            var ok = 0
            for _ in 0..<(item.unique ? 1 : qty) where book.buy(item.id) == .bought { ok += 1 }
            if ok > 0 {
                AudioHub.shared.play(.buyCoins); AudioHub.shared.play(.unwrap, volume: 0.8)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                bought += ok; qty = 1
                if item.unique, item.kind != .room { close() }
            } else { AudioHub.shared.play(.notEnough) }
        } label: {
            HStack(spacing: 8) {
                if owned { Text("You have it").font(SK.font(18, .semibold)) }
                else if left < 0 { Text("Need \(-left) more Drops").font(SK.font(18, .semibold)) }
                else {
                    Text("Buy for").font(SK.font(18, .semibold))
                    Image(systemName: "drop.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(SK.honey)
                    Text("\(total)").font(SK.font(18, .semibold))
                }
            }
            .foregroundStyle(SK.cream).frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(can ? SK.ink : SK.muted.opacity(0.55)))
        }
        .buttonStyle(.plain).disabled(!can)
        .accessibilityLabel(owned ? "\(item.name), you have it" : left < 0 ? "Buy \(item.name), need \(-left) more Drops" : "Buy \(item.unique ? "" : "\(qty) ")\(item.name) for \(total) Drops")
        .accessibilityIdentifier("item-buy")
    }

    private var footer: String {
        if item.kind == .room && book.owns(item) { return "Live there from Rooms" }
        if item.unique && book.owns(item) { return "In your Bag" }
        if left < 0 { return "Win races to earn more Drops" }
        let dest = item.kind == .room ? "Live there from Rooms" : item.isWearable ? "Wear it from your Bag" : item.kind == .decor ? "Place it from your Bag" : item.kind == .trickPage ? "Unlocks in the trick book" : "goes to your Bag"
        return "You'll have \(left) Drops left \u{00B7} \(dest)"
    }

    private var conditions: [(ConditionKey, Float)] {
        guard let f = item.food, let c = Consumables.with(id: f) else { return [] }
        return c.condition.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
    private var effectSymbol: String {
        if let p = item.perk { return p.symbol }
        if item.kind == .decor { return "chair.lounge.fill" }
        if item.kind == .room { return "house.fill" }
        return item.wear.map { $0.slot.symbol } ?? "book.fill"
    }
    private var effectTitle: String {
        if let p = item.perk { return "\(p.title) \u{00B7} \(durationText(p))" }
        if item.isWearable { return "Looks only" }
        if item.kind == .decor { return item.roomUnits == 1 ? "Takes 1 spot" : "Takes \(item.roomUnits) spots" }
        if item.kind == .room { return "A new room to live in" }
        return item.trick.map { "Unlocks \($0.title)" } ?? "Goodies"
    }
    private var effectBlurb: String {
        if let p = item.perk { return p.blurb }
        if let w = item.wear { return w.isShoe ? "No effect on speed. Shows in the room and on the track." : "No effect on anything but looks. Wear it from your Bag, one piece per spot." }
        if item.kind == .room { return "Your Jelbies move in and the room keeps its own furniture." }
        if item.kind == .decor { return "Your room has \(StoreTuning.roomCapacity) spots; \(book.roomUnitsUsed) used. Place it from your Bag, then drag it where you like." }
        return "Teach it with your own word in the trick book."
    }
    private func durationText(_ p: PerkKind) -> String { SK.timeLeft(p.duration) }
}


/// The item sheet's picture. A wearable is shown ON the selected Jelly (the fitting room: the game renderer draws him wearing it before you buy);
/// the small corner picture is the piece alone. Everything else shows its normal art.
struct ItemPicture: View {
    let care: GameCare
    let item: StoreItem
    var who: Int
    var size: CGFloat
    @State private var fitted: UIImage?
    @State private var tried = false

    var body: some View {
        if let look = item.wear {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).fill(SK.sky.opacity(0.22))
                if let fitted {
                    Image(uiImage: fitted).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
                        .accessibilityIdentifier("fitting-image")
                } else if tried {
                    ItemArt(item: item, size: size * 0.8).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if fitted != nil { ItemArt(item: item, size: size * 0.3).padding(8) }
                VStack {
                    HStack {
                        Text("On \(care.jelly(who)?.name ?? "him")").font(SK.font(12, .semibold)).foregroundStyle(SK.ink)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(DT.card))
                        Spacer()
                    }
                    Spacer()
                }.padding(8)
            }
            .frame(width: size, height: size)
            .accessibilityIdentifier("fitting-room")
            .task(id: look) {
                // the stage may not be up yet (a shop opened at launch): ask again a few times
                try? await Task.sleep(nanoseconds: 700_000_000)
                for _ in 0..<40 {
                    await Task.yield()
                    if let img = care.fittingProvider?(look, who) { fitted = img; break }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }
                }
                tried = true
            }
        } else {
            ItemArt(item: item, size: size)
        }
    }
}
