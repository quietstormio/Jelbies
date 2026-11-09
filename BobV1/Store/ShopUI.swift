//
//  ShopUI.swift
//  The Shop: a full screen with a pink wavy header, tabs (Food / Care / Wear / Tricks / Furniture / Toys), two-column item cards
//  (picture, perk chip, price, owned count) and a bottom sheet per item (what it does, condition chips, quantity, Buy).
//  Drops are earned only; there is no purchase of Drops anywhere.
//

import SwiftUI

enum ShopTab: String, CaseIterable, Identifiable {
    case food = "Food", drinks = "Drinks", care = "Care", wear = "Wear", tricks = "Tricks", furniture = "Furniture", toys = "Toys", rooms = "Rooms"
    var id: String { rawValue }
    var kinds: [StoreKind] {
        switch self {
        case .food: return [.food, .treat]; case .drinks: return [.drink]; case .care: return [.supply]; case .wear: return [.shoes, .wear]; case .tricks: return [.trickPage]; case .furniture: return [.decor]; case .toys: return [.decor, .toy]; case .rooms: return [.room]
        }
    }
    var items: [StoreItem] {
        switch self {
        case .furniture: return StoreCatalog.decorItems(.furniture)
        case .toys: return StoreCatalog.decorItems(.toys) + StoreCatalog.items(.toy)
        default: return kinds.flatMap { StoreCatalog.items($0) }.filter { !$0.awarded }
        }
    }
    /// A tab the next Shop opening starts on (the Play picker's "no toys yet" button sets it; the Shop takes it once).
    nonisolated(unsafe) static var pending: ShopTab?
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
    @State private var tab: ShopTab = ShopTab.named(UserDefaults.standard.string(forKey: "StoreTab")) ?? .food          // (-StoreTab decor: capture aid)
    @Environment(\.verticalSizeClass) private var vsc          // .compact = a phone on its side
    private var wide: Bool { vsc == .compact }
    @Environment(\.dynamicTypeSize) private var dts
    /// iPad only: the grid's width (columns follow it) and the scale of the card art, text and tabs (1 on iPhone, so the phone is unchanged).
    @State private var gridSize = CGSize(width: 820, height: 1180)
    private let pad = PadLayout.isPad
    private var sc: CGFloat { pad ? 1.35 : 1 }
    private var columnCount: Int {
        if dts.isAccessibilitySize { return 1 }
        if pad { return max(3, Int(gridSize.width / 230)) }          // portrait 3-4, landscape 5
        return wide ? 4 : 2
    }
    /// The Wear tab's slot filter (nil = all).
    @State private var wearSlot: WearSlot? = WearSlot(rawValue: UserDefaults.standard.string(forKey: "StoreSlot") ?? "")          // (-StoreSlot head: capture aid)
    private var shown: [StoreItem] { tab == .wear ? tab.items.filter { wearSlot == nil || $0.wear?.slot == wearSlot } : tab.items }
    @State private var selected: StoreItem? = UserDefaults.standard.string(forKey: "StoreOpen") == "item" ? StoreCatalog.item(UserDefaults.standard.string(forKey: "StoreItem") ?? "sushi") : nil

    @State private var boughtToast: String?

    private var book: StoreBook { care.store }

    var body: some View {
        VStack(spacing: 0) {
            header
            if tab == .wear {
                SlotChips(slot: $wearSlot, slots: WearSlot.allCases.filter { s in ShopTab.wear.items.contains { $0.wear?.slot == s } }, idPrefix: "shop-slot-")
                    .padding(.horizontal, 16).padding(.top, 8)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount), spacing: 12) {
                    ForEach(shown) { item in card(item) }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { if pad { gridSize = $0 } }
        }
        .overlay(alignment: .bottom) {
            if let boughtToast {
                Text(boughtToast).font(SK.font(15, .heavy)).foregroundStyle(SK.cream)
                    .padding(.horizontal, 18).padding(.vertical, 10).background(Capsule().fill(SK.ink))
                    .padding(.bottom, 24).transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("shop-bought-toast")
            }
        }
        .background(SK.cream.ignoresSafeArea())
        .accessibilityIdentifier("shop-screen")
        .sheet(item: $selected) { item in
            ItemSheet(care: care, item: item, who: who, goHome: goHome, close: { selected = nil }, onBought: { msg in
                selected = ShopSelection.afterBuy(selected, bought: true)
                withAnimation(.spring(duration: 0.35)) { boughtToast = msg }
                Task { try? await Task.sleep(for: .seconds(2.2)); withAnimation { boughtToast = nil } }
            })
                .presentationDetents(wide ? [.large] : [.height(560), .large])
                .padSheetSizing()          // iPad: a centred page-sized card (the detents are ignored there); no-op on iPhone
                .presentationDragIndicator(.visible)
                .presentationBackground(SK.cream)
        }
        .onAppear { AudioHub.shared.play(.storeOpen); if let t = ShopTab.pending { ShopTab.pending = nil; tab = t } }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(SK.cream))
                }
                .buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("shop-back")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Shop").font(SK.font(28, .black)).foregroundStyle(.white)
                    Text("Spend your JellyCoins on goodies").font(SK.font(12, .bold)).foregroundStyle(.white.opacity(0.9))
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
                            Text(t.rawValue).font(SK.font(pad ? 20 : 15, .heavy)).foregroundStyle(SK.ink)
                                .padding(.horizontal, pad ? 26 : 16).frame(minHeight: pad ? 56 : 44)
                                .background(Capsule().fill(t == tab ? SK.honey : SK.cream.opacity(0.92)))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("shop-tab-\(t.rawValue.lowercased())")
                        .accessibilityAddTraits(t == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 26)          // the wave's crests reach 14 pt above the header's bottom edge (WavyBottom): 12 pt of clear pink stays under the tabs
        }
        .background(SK.pinkStrong.clipShape(WavyBottom()).ignoresSafeArea(edges: [.top, .horizontal]))
        .padding(.bottom, 4)
    }

    private func card(_ item: StoreItem) -> some View {
        let owned = book.owned(item)
        let afford = care.bath.wallet.count >= item.price
        return Button {
            AudioHub.shared.uiTap(); selected = item
        } label: {
            VStack(spacing: 8 * sc) {
                ItemArt(item: item, size: pad ? 150 : (wide ? 84 : 104))
                Text(item.name).font(SK.font(15 * sc, .heavy)).foregroundStyle(SK.ink).jLine(1, scale: 0.8)
                if let p = item.perk { PerkChip(kind: p) }
                else if item.kind == .room { Text("New room").font(SK.font(11 * sc, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(SK.mint.opacity(0.8))) }
                else if item.kind == .decor { Text(item.roomUnits == 1 ? "1 spot" : "\(item.roomUnits) spots").font(SK.font(11 * sc, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(SK.mint.opacity(0.8))) }
                else if item.kind == .trickPage {
                    VStack(spacing: 3) {
                        if let t = item.trick {
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { k in Image(systemName: k < ShowTrickInfo.difficulty(t) ? "star.fill" : "star").font(.system(size: 11 * sc, weight: .black)).foregroundStyle(k < ShowTrickInfo.difficulty(t) ? ShowUI.goldDeep : SK.muted.opacity(0.5)) }
                            }
                        }
                        Text(item.scope?.tag ?? "New trick").font(SK.font(11 * sc, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(SK.mint.opacity(0.8)))
                    }
                }
                else { Text(item.isWearable ? (item.wear?.tags.prefix(2).map { $0.rawValue.capitalized }.joined(separator: " \u{00B7} ") ?? "Just for looks") : " ").font(SK.font(11 * sc, .bold)).foregroundStyle(SK.muted).padding(.vertical, 4) }
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        JellyCoinIcon(size: 17 * sc).opacity(afford ? 1 : 0.5)
                        Text("\(item.price)").font(SK.font(15 * sc, .black)).foregroundStyle(afford ? SK.ink : SK.muted)
                    }
                    .padding(.horizontal, 10).frame(minHeight: 44 * sc)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
                    Spacer(minLength: 0)
                    if owned > 0 {
                        Text(item.unique ? "Owned" : "owned x\(owned)").font(SK.font(11 * sc, .heavy)).foregroundStyle(SK.muted)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card).shadow(color: SK.shadow.opacity(0.10), radius: 5, y: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shop-item-\(item.id)")
        .accessibilityLabel("\(item.name), \(item.price) JellyCoins\(owned > 0 ? ", owned \(owned)" : "")")
    }
}

/// What the shop's selection does around a purchase: a successful Buy puts the player back on the grid (sheet closed); a failed one keeps the sheet.
enum ShopSelection {
    static func afterBuy(_ selected: StoreItem?, bought: Bool) -> StoreItem? { bought ? nil : selected }
    /// Buys `qty` (1 for once-only goods); returns how many went through.
    /// A per-Jelbie trick goes to `character` (the one picked in the sheet).
    @MainActor static func purchase(_ item: StoreItem, qty: Int, book: StoreBook, character: Int? = nil) -> Int {
        if item.kind == .trickPage, let t = item.trick { return book.buyTrick(t, for: character) == .bought ? 1 : 0 }
        var ok = 0
        for _ in 0..<(item.unique ? 1 : qty) where book.buy(item.id) == .bought { ok += 1 }
        return ok
    }
}

/// The bottom sheet of one item.
struct ItemSheet: View {
    let care: GameCare
    let item: StoreItem
    var who: Int
    var goHome: () -> Void = {}
    var close: () -> Void
    var onBought: (String) -> Void = { _ in }
    @State private var refusal: String?
    @State private var qty = 1
    @State private var bought = 0
    @Environment(\.verticalSizeClass) private var vsc

    private var book: StoreBook { care.store }
    private var wallet: DropsWallet { care.bath.wallet }
    /// A trick (Store/TrickCatalog.swift): for one Jelbie (pick who) or for everyone.
    private var isTrick: Bool { item.kind == .trickPage }
    private var isPerJelbieTrick: Bool { isTrick && item.scope == .perJelbie }
    @State private var forSlot: Int?
    /// Jelbies who already know this trick (checked in the picker, not pickable).
    private var knowers: Set<Int> { guard let t = item.trick else { return [] }; return Set(care.jellies.filter { book.knows(t, character: $0.character) }.map(\.id)) }
    /// The Jelbie it is for: the one picked, else the selected one if he does not know it yet, else the first who does not.
    private var targetSlot: Int? {
        if let f = forSlot, !knowers.contains(f) { return f }
        if care.jelly(who) != nil, !knowers.contains(who) { return who }
        return care.jellies.first { !knowers.contains($0.id) }?.id
    }
    private var targetCharacter: Int? { targetSlot.flatMap { care.jelly($0)?.character } }
    private var ownedNow: Bool { isPerJelbieTrick ? targetSlot == nil : item.unique && book.owns(item) }
    private var total: Int { item.price * (item.unique ? 1 : qty) }
    private var left: Int { wallet.count - total }

    var body: some View {
        Group {
            if vsc == .compact {
                // a phone on its side: the picture and name on the left, what it does and the Buy on the right, all of it scrolling if it must
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 8) {
                        ItemPicture(care: care, item: item, who: who, size: 150).padding(.top, 10)
                        Text(item.name).font(SK.font(22, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
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
            } else if HUDLayout.isPad {
                // iPad: the picture, name and effect scroll; the quantity / who-for / Buy are pinned in a footer outside the scroll so the Buy is always on screen
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 12) {
                            ItemPicture(care: care, item: item, who: who, size: isTrick ? 68 : 130).padding(.top, 34)
                            Text(item.name).font(SK.font(26, .black)).foregroundStyle(SK.ink)
                            Text(item.description).font(SK.font(15, .semibold)).foregroundStyle(SK.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
                            effectCard.padding(.horizontal, 16)
                        }
                        .padding(.bottom, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.visible)
                    .scrollIndicatorsFlash(onAppear: true)
                    .mask(alignment: .top) {
                        VStack(spacing: 0) { Rectangle(); LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom).frame(height: 18) }
                    }
                    buySection.padding(.top, 8).padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 14) {
                    ItemPicture(care: care, item: item, who: who, size: isTrick ? 110 : 230).padding(.top, 14)
                    Text(item.name).font(SK.font(26, .black)).foregroundStyle(SK.ink)
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
            Text("What it does").font(SK.font(12, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
            HStack(spacing: 10) {
                Image(systemName: effectSymbol).font(.system(size: 18, weight: .heavy)).foregroundStyle(SK.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(SK.honey))
                VStack(alignment: .leading, spacing: 2) {
                    Text(effectTitle).font(SK.font(15, .heavy)).foregroundStyle(SK.ink)
                    Text(effectBlurb).font(SK.font(12, .semibold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !conditions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(conditions, id: \.0.rawValue) { k, v in
                        Text("\(k.title) +\(SK.points(v))").font(SK.font(12, .heavy)).foregroundStyle(SK.ink)
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
                    Text("\(qty)").font(SK.font(24, .black)).foregroundStyle(SK.ink).frame(minWidth: 40).monospacedDigit()
                    stepper("plus") { if wallet.count >= item.price * (qty + 1), qty < 9 { qty += 1 } else { AudioHub.shared.play(.notEnough) } }
                }
            }
            if isPerJelbieTrick {
                LobbyJelbiePicker(care: care, title: "Who is it for?", selected: targetSlot.map { [$0] } ?? [], emptyLabel: "Empty slot", portraitCap: vsc == .compact ? 58 : 84, showNote: false, checked: knowers, pick: { forSlot = $0 })
                    .padding(.horizontal, vsc == .compact ? 0 : 16)
            } else if isTrick {
                Label("For all your Jelbies", systemImage: "person.3.fill").font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(SK.mint.opacity(0.8))).accessibilityIdentifier("item-scope-everyone")
            }
            buyButton.padding(.horizontal, vsc == .compact ? 0 : 16)
            if item.kind == .room, let r = item.room, book.owns(item), book.currentRoom != r {
                Button {
                    AudioHub.shared.uiTap()
                    if let b = care.switchRoom(r) { refusal = b.message } else { close(); goHome() }
                } label: {
                    Text("Move in now").font(SK.font(18, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(SK.honey))
                }
                .buttonStyle(.plain).padding(.horizontal, vsc == .compact ? 0 : 16)
                .accessibilityLabel("Move in to \(item.name)")
                .accessibilityIdentifier("item-movein")
            }
            if let refusal {
                Text(refusal).font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(SK.honey.opacity(0.9)))
                    .accessibilityIdentifier("item-movein-refusal")
            }
            Text(footer).font(SK.font(12, .bold)).foregroundStyle(SK.muted).padding(.bottom, 10)
        }
    }

    private func stepper(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .black)).foregroundStyle(SK.ink)
                .frame(width: 48, height: 48).background(Circle().fill(Color.white.opacity(0.9)))
        }.buttonStyle(.plain).accessibilityLabel(symbol == "plus" ? "More \(item.name)" : "Fewer \(item.name)").accessibilityValue("\(qty)").accessibilityIdentifier("item-qty-\(symbol)")
    }

    private var buyButton: some View {
        let owned = ownedNow
        let can = !owned && left >= 0
        return Button {
            let ok = ShopSelection.purchase(item, qty: qty, book: book, character: targetCharacter)
            if ok > 0 {
                AudioHub.shared.play(.unwrap, volume: 0.8)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                bought += ok; qty = 1
                onBought(boughtMessage(ok))
            } else { AudioHub.shared.play(.notEnough) }
        } label: {
            HStack(spacing: 8) {
                if owned { Text("You have it").font(SK.font(18, .black)) }
                else if left < 0 { Text("Need \(-left) more JellyCoins").font(SK.font(18, .black)) }
                else {
                    Text("Buy for").font(SK.font(18, .black))
                    JellyCoinIcon(size: 22)
                    Text("\(total)").font(SK.font(18, .black))
                }
            }
            .foregroundStyle(SK.cream).frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(can ? SK.ink : SK.muted.opacity(0.55)))
        }
        .buttonStyle(.plain).disabled(!can)
        .accessibilityLabel(owned ? "\(item.name), you have it" : left < 0 ? "Buy \(item.name), need \(-left) more JellyCoins" : "Buy \(item.unique ? "" : "\(qty) ")\(item.name) for \(total) JellyCoins")
        .accessibilityIdentifier("item-buy")
    }

    private var footer: String {
        if item.kind == .room && book.owns(item) { return "Live there from Rooms" }
        if item.kind == .trickPage {
            if ownedNow { return "Yours already" }
            if left < 0 { return "Win a Jelly Race to earn more JellyCoins" }
            return "You'll have \(left) JellyCoins left \u{00B7} \(item.scope == .everyone ? "Every Jelbie knows it at once" : "Ready at once")"
        }
        if item.unique && book.owns(item) { return "In your Bag" }
        if left < 0 { return "Win a Jelly Race to earn more JellyCoins" }
        let dest = item.kind == .room ? "Live there from Rooms" : item.isWearable ? "Wear it from your Bag" : item.kind == .decor ? "Place it from your Bag" : "goes to your Bag"
        return "You'll have \(left) JellyCoins left \u{00B7} \(dest)"
    }

    private var boughtMessage: (Int) -> String { { n in
        let what = n > 1 ? "\(n) \(item.name)" : item.name
        if item.kind == .room { return "\(what) is yours \u{00B7} live there from Rooms" }
        if item.kind == .trickPage { return "\(what) unlocked" }
        return "\(what) added to your Bag"
    } }

    private var conditions: [(ConditionKey, Float)] {
        guard let f = item.food, let c = Consumables.with(id: f) else { return [] }
        return c.condition.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
    private var effectSymbol: String {
        if let p = item.perk { return p.symbol }
        if item.kind == .decor { return "chair.lounge.fill" }
        if item.kind == .room { return "house.fill" }
        if item.kind == .toy { return "wand.and.stars" }
        if item.food != nil { return item.kind == .drink ? "drop.fill" : "fork.knife" }
        if item.id == TrickCatalog.earsID { return "ear.fill" }
        return item.wear.map { $0.slot.symbol } ?? "book.fill"
    }
    private var effectTitle: String {
        if let p = item.perk { return "\(p.title) \u{00B7} \(durationText(p))" }
        if item.isWearable { return "Looks only" }
        if item.kind == .decor { return item.roomUnits == 1 ? "Takes 1 spot" : "Takes \(item.roomUnits) spots" }
        if item.kind == .room { return "A new room to live in" }
        if item.kind == .toy { return "A toy to play with" }
        if let c = item.food.flatMap({ Consumables.with(id: $0) }) { return c.kind == .drink ? "Quenches thirst" : "Fills the tummy" }
        if item.id == TrickCatalog.earsID { return "Music Ears \u{00B7} \(TrickScope.everyone.tag)" }
        if let t = item.trick, let d = TrickCatalog.def(t) { return "\(d.name) \u{00B7} \(String(repeating: "\u{2605}", count: d.stars)) \u{00B7} \(d.scope.tag)" }
        return "Goodies"
    }
    private var effectBlurb: String {
        if let p = item.perk { return p.blurb }
        if let w = item.wear { return w.isShoe ? "No effect on speed. Shows in the room and in the Jelly Race." : "No effect on anything but looks. Wear it from your Bag, one piece per spot." }
        if item.kind == .room { return "Your Jelbies move in and the room keeps its own furniture." }
        if item.kind == .decor { return "Your room has \(StoreTuning.roomCapacity) spots; \(book.roomUnitsUsed) used. Place it from your Bag, then drag it where you like." }
        if item.kind == .toy { return "Pick it from Play and the Jelbies join in." }
        if item.food != nil { return item.description }
        if item.id == TrickCatalog.earsID { return "Dancing to your music and hearing claps, whistles and laughs. The microphone is on only while Ears is switched on (Sound panel)." }
        if item.kind == .trickPage { return item.scope == .everyone ? "Bought once: every Jelbie knows it, adopted ones too. Say it in the room, or pick it in the Jelly Show." : "Only the Jelbie you pick learns it. Say it in the room, or pick it in the Jelly Show." }
        return item.description
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
                        Text("On \(care.jelly(who)?.name ?? "your Jelbie")").font(SK.font(12, .heavy)).foregroundStyle(SK.ink)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(SK.cream.opacity(0.92)))
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
