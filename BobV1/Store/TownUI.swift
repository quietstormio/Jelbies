//
//  TownUI.swift
//  Places to go: the "Go out" pill, the Town ("Where to?": a little map, the destinations; the player goes alone, the Jellies stay home), the Track panel (Waddle / Focus, prizes,
//  Go race; Train comes next), the Bag sheet (snacks / wear / care with a pink action each, the room-space meter) and the HUD buttons
//  (Drops pill, Bag, Go out, the boost badge).
//

import SwiftUI

// MARK: - HUD pieces of the living room

/// The round "Go out" button (left rail, a cream 48 pt circle like the book, bag and mic): it opens the Town ("Where to?").
struct GoOutButton: View {
    var action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); action()
        } label: {
            Image(systemName: "door.left.hand.open").font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CareMenu.brown).frame(width: HUDTuning.railWidth, height: HUDTuning.railRow).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go out").accessibilityIdentifier("go-out")
        .accessibilityHint("Opens the Town: Jelly Race, Shop, Jelly Show, Jelly Volleyball")
        .accessibilityShowsLargeContentViewer { Label("Go out", systemImage: "door.left.hand.open") }
        .keyboardShortcut("o", modifiers: .command)
    }
}

struct BagButton: View {
    let store: StoreBook
    var action: () -> Void
    var body: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: "bag.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(CareMenu.brown)
                .frame(width: HUDTuning.railWidth, height: HUDTuning.railRow).contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if store.newCount > 0 {
                        Text("\(store.newCount)").font(SK.font(11, .black)).foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20).background(Circle().fill(SK.pinkStrong))
                            .overlay(Circle().strokeBorder(SK.cream, lineWidth: 2)).offset(x: -6, y: 8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.newCount > 0 ? "Bag, \(store.newCount) new" : "Bag").accessibilityIdentifier("bag-button")
        .accessibilityShowsLargeContentViewer { Label("Bag", systemImage: "bag.fill") }
        .keyboardShortcut("b", modifiers: .command)
    }
}

/// Tiny badges for the boosts a Jelly has on (under the top bar).
struct PerkBadgeRow: View {
    let care: GameCare
    var body: some View {
        let j = care.jelly(care.targetJelly) ?? care.jelly(0)
        let list = j?.perks.active ?? []
        HStack(spacing: 5) {
            if !list.isEmpty, let j {
                Text(j.name).font(SK.font(11, .heavy)).foregroundStyle(SK.ink.opacity(0.85))
                ForEach(list, id: \.rawValue) { k in
                    Image(systemName: k.symbol).font(.system(size: 11, weight: .heavy)).foregroundStyle(SK.ink)
                        .frame(width: 24, height: 24).background(Circle().fill(SK.honey))
                        .accessibilityLabel("\(k.title) \(SK.timeLeft(j.perks.remaining(k))) left")
                }
            }
        }
        .padding(.horizontal, list.isEmpty ? 0 : 8).padding(.vertical, list.isEmpty ? 0 : 3)
        .background(Capsule().fill(SK.cream.opacity(list.isEmpty ? 0 : 0.92)))
        .accessibilityIdentifier("perk-badges")
    }
}

// MARK: - Town

enum TownScreen: Equatable { case town, shop, track, studio, condition, friends, volley }

struct TownFlow: View {
    let care: GameCare
    @Binding var screen: TownScreen?
    @State var who: Int
    var goHome: () -> Void
    /// The Café: closes the Town and starts the café trip (the trip itself starts in the game, not on a Town screen).
    var cafe: () -> Void = {}
    /// The Park: closes the Town and opens the picker of who comes along (Park/ParkChrome.swift).
    var park: () -> Void = {}
    /// The Groomer: closes the Town and opens the tier menu (Groomer/GroomChrome.swift).
    var groom: () -> Void = {}
    /// Feed: closes the Town and opens the normal Feed picker in the room (the Condition screen's jar card button).
    var feed: () -> Void = {}
    var drink: () -> Void = {}
    /// The Jelly Spring (the adoption screen): leaves the room for the adoption screen (StartFlow).
    var adopt: () -> Void = { StartFlow.shared.openAdoption() }
    /// The screen the flow opened on: its back button leaves the flow (the Go out button opens the Town, so Track / Store go back to it).
    @State private var root: TownScreen

    init(care: GameCare, screen: Binding<TownScreen?>, who: Int, cafe: @escaping () -> Void = {}, park: @escaping () -> Void = {}, groom: @escaping () -> Void = {}, feed: @escaping () -> Void = {}, drink: @escaping () -> Void = {}, goHome: @escaping () -> Void) {
        self.care = care; self._screen = screen; self._who = State(initialValue: who); self.goHome = goHome; self.cafe = cafe; self.park = park; self.groom = groom; self.feed = feed; self.drink = drink
        self._root = State(initialValue: screen.wrappedValue ?? .town)
    }
    /// Back from the current screen: out of the flow when it is the root, else to `target`.
    private func up(_ target: TownScreen) { if (screen ?? .town) == root { goHome() } else { screen = target } }

    /// The Profile's back button leaves the flow (to the room as it was) when it came from the close-up or from the room; from the Jelly Show lobby it goes back there.
    static func profileBackLeaves(focusActive: Bool, root: TownScreen) -> Bool { focusActive || root == .condition }

    var currentScreen: TownScreen { screen ?? .town }
    func chooseCafe() { goHome(); cafe() }
    func choosePark() { goHome(); park() }
    func chooseGroom() { goHome(); groom() }
    func chooseFeed() { goHome(); feed() }
    func chooseDrink() { goHome(); drink() }
    func chooseCamp() { goHome(); care.requestCamp() }

    var body: some View {
        ZStack {
            switch screen ?? .town {
            case .town: TownView(care: care, go: { screen = $0 }, cafe: chooseCafe, park: choosePark, groom: chooseGroom, adopt: adopt, camp: chooseCamp, home: goHome).tipScreen("town")
            case .shop: ShopScreen(care: care, who: who, back: { up(.town) }, goHome: goHome).tipScreen("shop")
            case .track: TrackPanel(care: care, who: $who, back: { up(.town) }, shop: { screen = .shop }, race: { goHome(); care.startRace(jelly: who) }).tipScreen("race")
            case .studio: StudioScreen(care: care, who: $who, back: { up(.town) }, card: { screen = .condition }, show: { goHome(); care.startShow(jelly: who, rank: care.show.progress.chosen) }).tipScreen("show")
            // Back: from the close-up (focus) or from the room (roster card / name header: the flow's root is .condition) it leaves the flow and the room is as it was; from the Jelly Show lobby it goes back there.
            case .condition: ProfileScreen(care: care, who: $who, back: { if TownFlow.profileBackLeaves(focusActive: care.focus.isActive, root: root) { goHome() } else { up(.studio) } }, show: { screen = .studio }, bath: { goHome(); care.requestClean(jelly: who) }, feed: chooseFeed, drink: chooseDrink).tipScreen("trophies")
            case .volley: VolleyLobby(care: care, who: $who, back: { up(.town) }, park: choosePark, shop: { screen = .shop }, play: { t in goHome(); care.volley.book.chosen = t; care.startVolley(jelly: who, mode: .match(t)) }).tipScreen("volley")
            case .friends: FriendsScreen(care: care, back: { up(.town) }, goHome: goHome)
            }
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)          // VoiceOver stays inside the Town: the HUD and the Jelbies behind it are not reachable
        .showWardrobeGuard(care: care, screen: screen, who: who)          // show-wardrobe-r1: Dress up is a show outfit; the everyday one comes back on every way out
        .onAppear { HeadPortraitCache.shared.prewarm(care: care) }          // the stage is paused behind the Town: draw every lobby picture now (one at a time, see prewarm)
        .onDisappear { HeadPortraitCache.shared.cancelPrewarm() }
        .simultaneousGesture(TapGesture().onEnded { HeadPortraitCache.shared.cancelPrewarm() })          // a tap: the player is busy, no more hitches from the warm-up
    }
}

struct WhoRow: View {
    let care: GameCare
    @Binding var who: Int
    /// The Profile: each pill carries the Jelmiko's small head picture instead of the plain colour dot.
    var heads = false
    var body: some View {
        HStack(spacing: 8) {
            ForEach(care.jellies, id: \.id) { j in
                let t = JellyRoster.tint(j.character)
                Button { AudioHub.shared.uiTap(); who = j.id } label: {
                    HStack(spacing: 7) {
                        if heads {
                            JelbiePortrait(care: care, who: j.id, size: 30, head: true, frameless: true).accessibilityHidden(true)
                        } else {
                            Circle().fill(Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                        }
                        Text(j.name).font(SK.font(15, .heavy)).foregroundStyle(SK.ink)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Capsule().fill(who == j.id ? SK.honey : Color.white.opacity(0.8)))
                    .overlay(Capsule().strokeBorder(who == j.id ? SK.honeyDeep : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("who-\(j.id)").accessibilityLabel(j.name).accessibilityAddTraits(who == j.id ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

struct TownView: View {
    let care: GameCare
    var go: (TownScreen) -> Void
    var cafe: () -> Void = {}
    var park: () -> Void = {}
    var groom: () -> Void = {}
    var adopt: () -> Void = {}
    var camp: () -> Void = {}
    var home: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("townCategory") private var categoryRaw = TownCategory.all.rawValue

    enum TownCategory: String, CaseIterable {
        case all = "All", play = "Play", shops = "Shops", friends = "Friends"
    }

    private struct Place: Identifiable {
        let id: String, title: String, sub: String, symbol: String, color: Color
        let cats: Set<TownCategory>
        var enabled = true
        var tag: String? = nil          // a small pill above the title (the Spring's "Mutation Available")
        let action: () -> Void
    }

    private var category: TownCategory { TownCategory(rawValue: categoryRaw) ?? .all }

    private var places: [Place] {
        let visit = care.guestStatusText() ?? "Invite a friend over"
        let atHome = JellyRoster.savedIDs().count
        let campCount = JellyCamp.saved().count
        let open = SpringStates.townEnabled(home: atHome, camp: campCount)          // closed only when home AND Jelmiko Camp are full
        return [
            Place(id: "town-shop", title: "Shop", sub: "Food, shoes, tricks", symbol: "bag.fill", color: SK.pink, cats: [.shops]) { go(.shop) },
            Place(id: "town-track", title: "Jelly Race", sub: "Race for JellyCoins", symbol: "flag.checkered", color: SK.sky, cats: [.play]) { go(.track) },
            Place(id: "town-studio", title: "Jelly Show", sub: "Dress up and dance", symbol: "sparkles", color: SK.honey, cats: [.play]) { go(.studio) },
            Place(id: "town-cafe", title: "Café", sub: care.isBedtimeHours ? TownRefusals.closedSub : care.cafeNobodyHungry ? "Nobody's hungry \u{00B7} drinks only" : "Treats with the gang", symbol: "cup.and.saucer.fill", color: SK.mint, cats: [.shops]) { cafe() },
            Place(id: "town-park", title: "Park", sub: care.isBedtimeHours ? TownRefusals.closedSub : "Play with visitors", symbol: "tree.fill", color: SK.sky, cats: [.play, .friends]) { park() },
            Place(id: "town-groom", title: "Jelly Spa", sub: care.groomGuestBlocker ?? (care.isBedtimeHours ? TownRefusals.closedSub : "Bubbles and clean-up"), symbol: "bubbles.and.sparkles.fill", color: SK.pink, cats: [.shops], enabled: care.groomGuestBlocker == nil) {
                if let why = care.groomGuestBlocker { AudioHub.shared.play(.notEnough); GameMessageCenter.shared.refuse(why) } else { groom() }          // a friend is coming or here: the Jelly Wash stays closed (the tile says why)
            },
            Place(id: "town-friends", title: "Friends", sub: visit, symbol: "person.2.fill", color: SK.mint, cats: [.friends]) { go(.friends) },
            Place(id: "town-beach", title: "Jelly Volleyball", sub: "Bump and spike", symbol: UIImage(systemName: "figure.volleyball") != nil ? "figure.volleyball" : "sportscourt.fill", color: SK.honey, cats: [.play]) { go(.volley) },
            Place(id: "town-camp", title: "Jelmiko Camp", sub: CampUI.townSub(count: campCount), symbol: "tent.fill", color: SK.mint, cats: [.friends]) { camp() },
            Place(id: "town-adopt", title: "Jelly Spring", sub: SpringStates.townSub(home: atHome, camp: campCount), symbol: "drop.fill", color: SK.sky, cats: [.friends], enabled: open,
                  tag: TownTag.mutationAvailable(day: JellyVariantBook.dayKey(), home: atHome, camp: campCount) ? "Mutation Available" : nil) { if !open { AudioHub.shared.play(.notEnough); GameMessageCenter.shared.refuse(TownRefusals.springFull) } else { adopt() } },
        ]
    }

    /// The island node's place (same destination and filter categories as its tile), nil when the chip filter hides it.
    private func island(_ node: String) -> Place? {
        let id = ["shop": "town-shop", "track": "town-track", "studio": "town-studio", "cafe": "town-cafe", "park": "town-park", "groom": "town-groom"][node]
        return shown.first { $0.id == id }
    }

    private var shown: [Place] { category == .all ? places : places.filter { $0.cats.contains(category) } }

    var body: some View {
        if PadLayout.isPad {
            // iPad: the column is centred in the real window width and sits below the status bar (the window's own top inset, in case the host ignores it)
            GeometryReader { geo in
                let top = max(geo.safeAreaInsets.top, Self.windowTopInset)
                content.frame(maxWidth: 900)
                    .padding(.horizontal, 16).padding(.top, 8 + top)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .background(SK.cream.ignoresSafeArea())
            }
            .ignoresSafeArea()
            .accessibilityElement(children: .contain).accessibilityIdentifier("town-screen")
        } else {
            content.padding(.horizontal, 16).padding(.top, 8)
                .background(SK.cream.ignoresSafeArea())
                .accessibilityElement(children: .contain).accessibilityIdentifier("town-screen")
        }
    }

    private static var windowTopInset: CGFloat {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        return w?.safeAreaInsets.top ?? 0
    }

    /// Capture aid (simulator, dev arguments only): `-TownScroll bottom` scrolls the Town to its last row so the lower tiles can be photographed.
    private func devScrollBottom(_ proxy: ScrollViewProxy) async {
        #if targetEnvironment(simulator)
        guard DevArgs.enabled, UserDefaults.standard.string(forKey: "TownScroll") == "bottom" else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        proxy.scrollTo("town-bottom", anchor: .bottom)
        #endif
    }

    private var content: some View {
        let compact = vsc == .compact
        return VStack(spacing: compact ? 6 : 10) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); home() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "house.fill").font(.system(size: 15, weight: .heavy))
                        Text("Home").font(SK.font(15, .heavy))
                    }
                    .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().fill(Color.white.opacity(0.85)))
                }
                .buttonStyle(.plain).accessibilityIdentifier("town-home")
                Text("Where to?").font(SK.font(compact ? 24 : 28, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                DropsPill(wallet: care.bath.wallet)
            }
            chips
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    AroundTownIsland(active: { island($0) != nil }, go: { island($0)?.action() }, home: home)
                        .frame(maxWidth: PadLayout.isPad ? 760 : 520)
                    LazyVGrid(columns: gridColumns(compact: compact), spacing: 12) {
                        ForEach(shown) { p in tile(p, compact: compact) }
                    }
                    Color.clear.frame(height: 1).id("town-bottom")
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .task { await devScrollBottom(proxy) }
            }
        }
    }

    /// iPhone: 4 columns on its side, else 2 (as before). iPad: as many ~190 pt tiles as fit the capped column.
    private func gridColumns(compact: Bool) -> [GridItem] {
        if PadLayout.isPad { return [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 12)] }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 4 : 2)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(TownCategory.allCases, id: \.self) { c in
                let on = category == c
                Button {
                    AudioHub.shared.uiTap()
                    if reduceMotion { categoryRaw = c.rawValue } else { withAnimation(.easeInOut(duration: 0.25)) { categoryRaw = c.rawValue } }
                } label: {
                    Text(c.rawValue).font(SK.font(15, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(on ? SK.honey : Color.clear))
                        .overlay(Capsule().strokeBorder(on ? SK.honeyDeep : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain).accessibilityIdentifier("town-chip-\(c.rawValue.lowercased())")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3).background(Capsule().fill(Color.white.opacity(0.8)))
    }

    private func tile(_ p: Place, compact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return Button { AudioHub.shared.uiTap(); p.action() } label: {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack(alignment: .topLeading) {
                        SK.card
                        if !reduceTransparency {
                            // a sneak peek of the place: low-opacity picture under a cream wash (decorative)
                            Image("town_preview_" + p.id.replacingOccurrences(of: "town-", with: ""))
                                .resizable().scaledToFill().opacity(0.4).accessibilityHidden(true)
                            LinearGradient(stops: [.init(color: SK.cream.opacity(0.15), location: 0), .init(color: SK.cream.opacity(0.35), location: 0.5), .init(color: SK.cream.opacity(0.92), location: 0.78), .init(color: SK.cream.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Image(systemName: p.symbol).font(.system(size: 22, weight: .heavy)).foregroundStyle(SK.ink)
                                .frame(width: 46, height: 46).background(Circle().fill(p.color.opacity(0.9)))
                            Spacer(minLength: 4)
                            if let tag = p.tag { MutationPill(text: tag).padding(.bottom, 5).accessibilityIdentifier("town-mutation-tag") }
                            Text(p.title).font(SK.font(compact ? 16 : 20, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                            Text(p.sub).font(SK.font(compact ? 11 : 13, .bold)).foregroundStyle(SK.ink.opacity(0.85)).lineLimit(2).minimumScaleFactor(0.8)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .clipShape(shape)
                .background(shape.fill(SK.card).shadow(color: SK.shadow.opacity(0.10), radius: 5, y: 2))
                .contentShape(shape)
        }
        .buttonStyle(TownTilePress())
        .accessibilityElement(children: .ignore).accessibilityLabel("\(p.title), \(p.sub)").accessibilityAddTraits(.isButton).accessibilityHint(p.enabled ? "" : "Closed for now")
        .opacity(p.enabled ? 1 : 0.55)
        .accessibilityIdentifier(p.id)
    }
}

/// When the Jelly Spring's Where-to card carries the "Mutation Available" pill: a rare colour is on offer today (`JellyVariantBook.rareOnOffer`, the same answer the pick page's "Rare" tag comes from) and the Spring can sell (home OR Jelmiko Camp has room: `SpringStates.townEnabled`).
/// The Town's closed-door lines (the tile says it before the tap; the tap says why on the message bar).
enum TownRefusals {
    /// The small line under a place's name while the game already knows it is closed (the Spa, the Café and the Park close at night).
    static let closedSub = "Closed until morning"
    static let springFull = "The Jelly Spring has no room right now. Home and Camp are full."
}

nonisolated enum TownTag {
    static func mutationAvailable(day: Int, home: Int, camp: Int) -> Bool { SpringStates.townEnabled(home: home, camp: camp) && JellyVariantBook.rareOnOffer(dayKey: day) }
}

/// "✦ Mutation Available": a honey pill, 26 pt high, white 1.5 pt border (the owner's design A).
private struct MutationPill: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Text("\u{2726}").font(SK.font(13, .black))
            Text(text).font(SK.font(14, .black)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color(hex: 0x4D331F))
        .padding(.horizontal, 11).frame(height: 26)
        .background(Capsule().fill(Color(hex: 0xFFD65C)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
    }
}

private struct TownTilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A small illustrated map: sky, hills, a path, the shop, the track and home. (UI art only.)
struct MapStrip: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: [SK.sky.opacity(0.75), Color(hex: 0xCFE8F2)], startPoint: .top, endPoint: .bottom)
                Ellipse().fill(SK.mint).frame(width: w * 0.9, height: h * 0.9).offset(x: -w * 0.25, y: h * 0.45)
                Ellipse().fill(Color(hex: 0x86C99B)).frame(width: w * 0.8, height: h * 0.8).offset(x: w * 0.3, y: h * 0.5)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.14, y: h * 0.82))
                    p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.74), control1: CGPoint(x: w * 0.25, y: h * 0.62), control2: CGPoint(x: w * 0.38, y: h * 0.9))
                    p.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.78), control1: CGPoint(x: w * 0.62, y: h * 0.6), control2: CGPoint(x: w * 0.74, y: h * 0.95))
                }
                .stroke(Color(hex: 0xF3DDB0), style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [1, 12]))
                place("house.fill", "Home", SK.honeyDeep, x: w * 0.14, y: h * 0.52)
                place("bag.fill", "Shop", SK.pink, x: w * 0.5, y: h * 0.46)
                place("flag.checkered", "Jelly Race", SK.cream, x: w * 0.86, y: h * 0.52)
                place("sparkles", "Jelly Show", SK.honey, x: w * 0.68, y: h * 0.30)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityHidden(true)
    }
    private func place(_ symbol: String, _ label: String, _ color: Color, x: CGFloat, y: CGFloat) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 17, weight: .heavy)).foregroundStyle(SK.ink)
                .frame(width: 44, height: 44).background(Circle().fill(color)).overlay(Circle().strokeBorder(.white, lineWidth: 2))
            Text(label).font(SK.font(11, .black)).foregroundStyle(SK.ink)
        }
        .position(x: x, y: y)
    }
}

// MARK: - Track

/// The Track lobby, to the lobby mockups: the five courses in a carousel, the Runner card (pick the runner, Waddle and Focus), and a pinned Train / Go race bar.
/// The pieces are in Lobby/LobbyKit.swift; the course cards in Race/CoursePicker.swift.
struct TrackPanel: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    /// To the Shop (the Upgrade sheet's "Shop ›").
    var shop: (() -> Void)? = nil
    var race: () -> Void
    /// The course picked for the next race (Race/CoursePicker.swift sets it through GameCare.chooseCourse).
    var courseTier: CourseTier { care.race.courseTier }
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var howOpen = false
    @State private var upgradeOpen = false
    @State private var hint = LobbyHint()

    private var compact: Bool { vsc == .compact }
    private var blocker: String? { care.raceBlocker(jelly: who) }

    var body: some View {
        let prof = care.jelly(who)
        ZStack {
            LobbyScreen(header: AnyView(LobbyHeader(title: "Jelly Race", wallet: care.bath.wallet, backID: "track-back", helpID: "track-help", back: back, help: { setHow(true) })),
                        why: blocker, whyID: "track-why") {
                CoursePicker(care: care, runner: prof?.character ?? who, bleed: !compact, hint: hint)
            } right: {
                runnerCard(prof).padding(.top, compact ? 0 : 12)
            } bar: {
                LobbyBottomBar(playID: "track-race", playTitle: "Go race", playIcon: .flag, blocked: blocker != nil, why: blocker, upgradeID: "track-upgrade",
                               upgradePoints: prof.map { care.upgrades.points(.race, character: $0.character) } ?? 0, upgrade: { setUpgrade(true) }, play: race)
            }
            .accessibilityHidden(howOpen || upgradeOpen)
            if upgradeOpen, let p = prof {
                UpgradeSheet(care: care, who: p.id, config: upgradeConfig(p), buy: { buySkill($0, p) }, pick: { pickPower($0, p) },
                             shop: shop.map { go in { setUpgrade(false); go() } }, done: { setUpgrade(false) })
                    .environment(\.lobbyTheme, .cream)
                    .zIndex(1)
            }
            if howOpen {
                LobbyHowSheet(rows: RaceHelp.rows, close: { setHow(false) })
                .zIndex(1)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("track-screen")
        .onAppear {          // capture aids: -LobbyAuto trackHow / trackUpgrade
            let a = UserDefaults.standard.string(forKey: "LobbyAuto")
            if a == "trackHow" { howOpen = true } else if a == "trackUpgrade" { upgradeOpen = true }
        }
    }

    /// 3 -> "three" (the How to play copy).
    static func words(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .spellOut; f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func setUpgrade(_ on: Bool) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { upgradeOpen = on } }

    // MARK: Upgrade (Upgrade/UpgradeSheet.swift)

    private func upgradeConfig(_ p: JellyProfile) -> UpgradeConfig {
        let book = care.upgrades
        _ = book.revision          // (the sheet redraws when points or the choice change)
        let skills = RaceSkill.allCases.map { s -> UpgradeSkillInfo in
            let lv = book.level(s, stats: p.stats)
            return UpgradeSkillInfo(id: s.rawValue, title: s.title, blurb: s.blurb, symbols: s == .speed ? ["shoe.fill", "shoeprints.fill", "figure.run"] : ["scope", "target"],
                                    tint: s == .speed ? SK.pink.opacity(0.4) : SK.sky.opacity(0.4), level: lv, cost: UpgradeTuning.cost(level: lv))
        }
        return UpgradeConfig(gameWord: "Jelly Race", heroName: p.name, winLine: "Win = \(UpgradeTuning.racePoints(place: 1)) points", points: book.points(.race, character: p.character),
                             backdrop: Color(hex: 0xBFE3B4), podium: Color(hex: 0x8FC47F), skills: skills, tiles: powerTiles(), selectedTile: chosenTile(p))
    }

    /// The race-boost foods the Bag has (the Shop's 3D picture, with how many); with none, Donut and Sandwich greyed.
    private func powerTiles() -> [UpgradePowerTile] {
        func tile(_ item: StoreItem, _ n: Int) -> UpgradePowerTile {
            UpgradePowerTile(id: item.id, name: item.name, tag: n > 0 ? "\(item.perk == .zoomies ? "Faster" : "Steadier") \u{00B7} \u{00D7}\(n)" : "Get in Shop", item: item, count: n)
        }
        let owned = StoreCatalog.items.filter { $0.food != nil && ($0.perk == .zoomies || $0.perk == .focus) && care.store.count($0.id) > 0 }
        let foods = owned.isEmpty ? ["donut", "sandwich"].compactMap { StoreCatalog.item($0) }.map { tile($0, 0) } : owned.map { tile($0, care.store.count($0.id)) }
        return [UpgradePowerTile(id: UpgradePowerTile.noneID, name: "None", tag: "No boost", item: nil, count: 0)] + foods
    }

    private func chosenTile(_ p: JellyProfile) -> String {
        if let c = care.upgrades.chosen(.race, character: p.character), care.store.count(c) > 0 { return c }
        return UpgradePowerTile.noneID
    }

    private func buySkill(_ id: String, _ p: JellyProfile) -> Bool {
        guard let s = RaceSkill(rawValue: id) else { return false }
        return care.upgrades.buy(s, stats: p.stats, character: p.character)
    }

    /// True when a food (not None) is now chosen.
    private func pickPower(_ id: String, _ p: JellyProfile) -> Bool {
        if id == UpgradePowerTile.noneID { care.upgrades.choose(nil, .race, character: p.character); return false }
        care.upgrades.choose(id, .race, character: p.character)
        return true
    }

    private func setHow(_ on: Bool) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { howOpen = on } }

    /// The shared picker row and stats card: pick the runner, then his Waddle and Focus.
    private func runnerCard(_ prof: JellyProfile?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LobbyJelbiePicker(care: care, title: "Runner", selected: [who], selectCount: 1, id: "track-picker",
                              wonCount: { care.race.trophies.shelf(character: $0.character).raceRibbons(care.race.courseTier)[0] },
                              grandChampion: { care.race.trophies.shelf(character: $0.character).wonEveryCourse }) { who = $0 }
                .padding(.bottom, 6)
            LobbyStatsCard(title: "Jelly Race stats", groups: [LobbyStatGroup(id: "track-stats", rows: [
                LobbyStatRow(label: "Speed", value: prof?.stats.waddle ?? 0, color: SK.pink),
                LobbyStatRow(label: "Focus", value: prof?.stats.focus ?? 0, color: SK.sky),
            ])], id: "track-runner", trailing: {
                HStack(spacing: 6) {
                    if let p = prof, care.race.trophies.shelf(character: p.character).wonEveryCourse { GrandChampionPill() }
                    Text(prof?.name ?? "").font(SK.font(14, .heavy)).foregroundStyle(SK.muted).lineLimit(1)
                }
            }, footer: {
                if let p = prof, !p.perks.raceBoost.isNone {
                    FlowLayout(spacing: 6) {
                        ForEach(p.perks.active.filter(\.raceOnly), id: \.rawValue) { PerkChip(kind: $0, left: p.perks.remaining($0)) }
                        Text("for the next race").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
                    }
                }
            })
        }
    }
}

// MARK: - Bag

struct BagSheet: View {
    let care: GameCare
    @Environment(\.dynamicTypeSize) private var typeSize
    @State var who: Int
    var close: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @State private var tab: BagTab
    /// What the last Wear did when it had to move a copy from another Jelmiko.
    @State private var wearNote: String?
    /// The item the Sell card is asking about (nil = no card).
    @State private var sellAsk: StoreItem?

    /// `tab`: the tab to open on (Dress / Play / Decor from the HUD); nil = the `-StoreTab` capture arg, else Food.
    init(care: GameCare, who: Int, tab: BagTab? = nil, close: @escaping () -> Void) {
        self.care = care; self._who = State(initialValue: who); self.close = close; self.fromHUD = tab != nil
        let asked: BagTab = tab ?? BagTab(rawValue: { let n = (UserDefaults.standard.string(forKey: "StoreTab") ?? "").capitalized; return n == "Decor" ? "Furniture" : n }()) ?? .food          // (-StoreTab decor: capture aid)
        // 2026-11-15 (the user's ask: "Remove Furniture section"): the Shop sells no furniture, so the Furniture tab exists only while the player owns a piece.
        // A Bag asked to open on it (the HUD's Decor button) opens on Toys when there is none.
        let ownsFurniture = StoreCatalog.decorItems(.furniture).contains { care.store.count($0.id) > 0 }
        self._tab = State(initialValue: asked == .furniture && !ownsFurniture ? .toys : asked)
    }

    enum BagTab: String, CaseIterable, Identifiable { case food = "Food", wear = "Wear", furniture = "Furniture", toys = "Toys", care = "Care", rooms = "Rooms"; var id: String { rawValue }; var isDecor: Bool { self == .furniture || self == .toys } }
    private var book: StoreBook { care.store }

    /// The tabs listed: Furniture only while the player owns a piece (the Shop no longer sells any, 2026-11-15).
    private var tabs: [BagTab] { Self.visibleTabs(book: book) }
    static func visibleTabs(book: StoreBook) -> [BagTab] { BagTab.allCases.filter { $0 != .furniture || !StoreCatalog.decorItems(.furniture).filter { book.count($0.id) > 0 }.isEmpty } }
    /// The "Arrange the room" button (move or put away placed pieces) shows on the Furniture and Toys tabs while anything is placed. Reached from the suitcase Bag, not from the paw menu.
    static func offersArrange(tab: BagTab, book: StoreBook) -> Bool { tab.isDecor && !book.placedDecor.isEmpty }
    private func entries(_ t: BagTab) -> [StoreItem] {
        switch t {
        case .food: return StoreCatalog.items.filter { $0.food != nil && book.count($0.id) > 0 }
        case .wear: return StoreCatalog.items.filter { $0.isWearable && book.owns($0) && (wearSlot == nil || $0.wear?.slot == wearSlot) }
        case .furniture: return StoreCatalog.decorItems(.furniture).filter { book.count($0.id) > 0 }
        case .toys: return StoreCatalog.decorItems(.toys).filter { book.count($0.id) > 0 }
        case .care: return StoreCatalog.items(.supply).filter { book.count($0.id) > 0 }
        case .rooms: return []
        }
    }
    @State private var wearSlot: WearSlot?
    private var ownedRooms: [RoomDef] { RoomCatalog.all.filter { book.ownsRoom($0.id) || care.roomID == $0.id } }
    @State private var roomRefusal: String?
    private func count(_ t: BagTab) -> Int { t == .rooms ? ownedRooms.count : t == .wear ? StoreCatalog.items.filter { $0.isWearable && book.owns($0) }.count : entries(t).reduce(0) { $0 + book.count($1.id) } }

    /// Opened by the HUD's Dress / Decor rows (a tab was asked for): the first-time tip for that tab.
    private let fromHUD: Bool
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Bag").font(SK.font(30, .black)).foregroundStyle(SK.ink)
                    Spacer()
                    DropsPill(wallet: care.bath.wallet)
                    Button { close() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85)))
                    }.buttonStyle(.plain).accessibilityLabel("Close bag").accessibilityIdentifier("bag-close")
                }
                .background { if fromHUD, tab == .wear { TipAnchor("dress", delay: 0.4) } }
                LobbyJelbiePicker(care: care, title: "Who is it for?", selected: [who], emptyLabel: "Empty slot", portraitCap: vsc == .compact ? 84 : 140, sideBySide: vsc == .compact, showNote: false, pick: { who = $0 })
                if HUDLayout.isPad, typeSize < .xxxLarge {          // iPad (larger type falls back to the scrolling row below so labels never truncate): all six tabs share the card's width (no clipped "Ro" at the edge); the label shrinks a touch if it must
                    HStack(spacing: 6) {
                        ForEach(tabs) { t in
                            Button { AudioHub.shared.play(.pageTurn); tab = t } label: {
                                Text("\(t.rawValue) \(count(t))").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6)
                                    .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(t == tab ? SK.honey : Color.white.opacity(0.8)))
                            }.buttonStyle(.plain).accessibilityIdentifier("bag-tab-\(t.rawValue.lowercased())")
                        }
                    }
                } else {
                    ScrollViewReader { proxy in ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                    ForEach(tabs) { t in
                        Button { AudioHub.shared.play(.pageTurn); tab = t } label: {
                            Text("\(t.rawValue) \(count(t))").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(1).fixedSize()
                                .padding(.horizontal, 12).frame(minHeight: 44).background(Capsule().fill(t == tab ? SK.honey : Color.white.opacity(0.8)))
                        }.buttonStyle(.plain).accessibilityIdentifier("bag-tab-\(t.rawValue.lowercased())").id(t)
                    }
                }.onAppear { proxy.scrollTo(tab, anchor: .center) } } }
                }
                let list = entries(tab)
                if tab == .wear { SlotChips(slot: $wearSlot, slots: WearSlot.allCases.filter { s in StoreCatalog.items.contains { $0.wear?.slot == s && book.owns($0) } }, idPrefix: "bag-slot-") }
                if tab == .wear, let note = wearNote {
                    Text(note).font(SK.font(13, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SK.honey.opacity(0.9))).accessibilityIdentifier("bag-wear-note")
                }
                if Self.offersArrange(tab: tab, book: book) {
                    Button { AudioHub.shared.uiTap(); close(); care.beginArrange() } label: {
                        HStack(spacing: 8) { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 15, weight: .heavy)); Text("Arrange the room").font(SK.font(15, .black)) }
                            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 48).background(Capsule().fill(SK.honey))
                    }.buttonStyle(.plain).accessibilityIdentifier("bag-arrange")
                }
                if list.isEmpty, tab != .rooms {
                    Text(tab == .food ? "No food yet. The Shop has plenty." : tab == .furniture ? "No furniture here." : tab == .toys ? "No toys yet. Balls, drums and more are in the Shop." : "Nothing here yet.").font(SK.font(14, .bold)).foregroundStyle(SK.muted)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                if tab == .rooms { roomsList } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: vsc == .compact ? 2 : 1), spacing: 10) {
                        ForEach(list) { row($0) }
                    }
                    roomMeter
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SK.cream.ignoresSafeArea())
        .accessibilityIdentifier("bag-sheet")
        .overlay { sellCard }
        .onAppear {
            book.markSeen()
            if DevArgs.enabled, UserDefaults.standard.string(forKey: "BagScroll") == "frames" {          // (capture aid: -BagScroll frames)
                Task { try? await Task.sleep(nanoseconds: 600_000_000); withAnimation { proxy.scrollTo("bag-frames", anchor: .top) } }
            }
        }
        }
    }

    /// The rooms the player owns (the home room and the bought ones): choosing one moves the Jelbies in (the same `care.switchRoom` the old picker used).
    private var roomsList: some View {
        VStack(spacing: 10) {
            if let roomRefusal {
                Text(roomRefusal).font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(SK.honey.opacity(0.9)))
                    .accessibilityIdentifier("bag-room-refusal")
            }
            ForEach(ownedRooms, id: \.id) { d in
                let here = care.roomID == d.id
                HStack(spacing: 12) {
                    Image(systemName: "house.fill").font(.system(size: 24, weight: .heavy)).foregroundStyle(SK.ink.opacity(0.85))
                        .frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SK.honey.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.title).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                        Text(d.blurb).font(SK.font(12, .semibold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if here {
                        Text("Home now").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Capsule().fill(SK.mint.opacity(0.85))).accessibilityIdentifier("bag-room-here-\(d.id.rawValue)")
                    } else {
                        pink("Move in", enabled: true) {
                            if let why = care.switchRoom(d.id) { roomRefusal = why.message } else { close() }
                        }.accessibilityLabel("Move in to \(d.title)").accessibilityIdentifier("bag-room-movein-\(d.id.rawValue)")
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card))
                .accessibilityIdentifier("bag-room-\(d.id.rawValue)")
            }
            framesList
        }
    }

    /// The picture frames the player owns (bought in the Shop's Rooms tab): "Hang a picture" opens the album to pick the photo, then the wall editor.
    @ViewBuilder private var framesList: some View {
        let owned = book.ownedWallFrames
        if !owned.isEmpty {
            Text("Picture frames").font(SK.font(18, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                .accessibilityAddTraits(.isHeader).id("bag-frames").accessibilityIdentifier("bag-frames-header")
            ForEach(owned, id: \.self) { f in
                if let item = StoreCatalog.item("frame-\(f.rawValue)") {
                    let hang = pink("Hang a picture", enabled: true) {
                        close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { care.wallAlbumOpen = true }
                    }.accessibilityLabel("Hang a picture in the \(item.name) frame").accessibilityHint("Opens your album to pick a photo, then the wall editor.")
                    .accessibilityIdentifier("bag-hang-\(f.rawValue)")
                    let info = HStack(spacing: 12) {
                        ItemArt(item: item, size: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                            Text(book.wallPicture?.frame == f ? "On the wall" : "Owned").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    Group {
                        if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 10) { info; hang.frame(maxWidth: .infinity) } }
                        else { HStack(spacing: 12) { info; hang } }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bag-frame-\(f.rawValue)")
                }
            }
        }
    }

    /// The Wear row's second line: wearing it, a free copy ("Owned", with "x2" when there are several), or who has every copy.
    private func wearStatus(_ w: WearLook) -> String {
        let n = book.copies(w), x = n > 1 ? " \u{00B7} x\(n)" : ""
        if book.worn(who, w.slot) == w { return "Wearing" + x }
        if book.freeCopies(w) > 0 { return "Owned" + x }
        let names = book.wearerCharacters(w).map { c in care.jellies.first { $0.character == c }?.name ?? JellyRoster.nameOf(c) }
        return names.isEmpty ? "Owned" + x : "Worn by \(names.joined(separator: " and "))" + x + " \u{00B7} Wear moves it"
    }

    private func row(_ item: StoreItem) -> some View {
        HStack(spacing: 12) {
            ItemArt(item: item, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                if let w = item.wear { Text(wearStatus(w)).font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("bag-wear-status-\(item.id)") }
                else if item.kind == .decor, item.decor?.isPlayOnly == true { Text("x\(book.count(item.id))").font(SK.font(13, .heavy)).foregroundStyle(SK.muted) }          // (the soccer net: owned, comes out in Play, nothing to place)
                else if item.kind == .decor {
                    let placed = book.placedCount(item.id)
                    Text("x\(book.count(item.id))" + (placed > 0 ? " \u{00B7} \(placed) in the room" : "") + " \u{00B7} \(item.roomUnits) spot\(item.roomUnits == 1 ? "" : "s")").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                    if let why = book.placeBlocker(item), book.unplaced(item.id) > 0 { Text(why).font(SK.font(11, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true) }
                }
                else { Text("x\(book.count(item.id))").font(SK.font(13, .heavy)).foregroundStyle(SK.muted) }
                if let p = item.perk { PerkChip(kind: p) }
                if let f = item.food, let j = care.jelly(who), j.traits?.snack == f {          // the picked favourite snack of the Jelbie it is for (a small heart; an extra heart when he eats it)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(SK.pink)
                        Text("\(j.name)'s favourite").font(SK.font(12, .heavy)).foregroundStyle(SK.ink.opacity(0.75))
                    }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("bag-favourite-\(item.id)")
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                actionButton(item)
                sellButton(item)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card))
        .accessibilityIdentifier("bag-row-\(item.id)")
    }

    @ViewBuilder
    private func actionButton(_ item: StoreItem) -> some View {
        switch item.kind {
        case .food, .treat, .drink:
            pink(item.kind == .drink ? "Give" : "Feed", item, enabled: !care.trayOut && !care.bath.active && !care.race.active) {
                close(); care.feedSnack(item.id, jelly: who)
            }
        case .shoes, .wear:
            let slot = item.wear?.slot ?? .feet
            let wearing = book.worn(who, slot) == item.wear
            pink(wearing ? "Take off" : "Wear", item, enabled: true) {
                if wearing { book.takeOff(slot, from: who); wearNote = nil }
                else if let w = item.wear {
                    // every copy is on someone: the copy worn longest moves here, and the note says so
                    let from = book.wearVictim(w, for: who).map { c in care.jellies.first { $0.character == c }?.name ?? JellyRoster.nameOf(c) }
                    if book.wear(w, on: who) {
                        wearNote = from.map { "\(book.copies(w) > 1 ? "All \(book.copies(w)) \(item.name) were" : "The \(item.name) was") worn, so \($0)'s moved to \(care.jelly(who)?.name ?? "this Jelmiko"). Buy another in the Shop for both." }
                        AudioHub.shared.play(.shoeOn); care.jelly(who)?.stats.nudge([.cool: 0.02])
                    }
                }
            }
        case .supply:
            pink("Use", item, enabled: care.canClean(jelly: who)) { close(); care.useSupply(item.id, on: who) }
        case .decor where item.decor?.isPlayOnly == true:
            EmptyView()
        case .decor:
            VStack(spacing: 6) {
                pink("Place", item, enabled: book.canPlace(item)) { close(); care.placeDecor(item.id) }
                if book.placedCount(item.id) > 0 {
                    Button {
                        AudioHub.shared.uiTap()
                        if let p = book.placedDecor.last(where: { $0.kind.storeID == item.id }) { care.putAwayDecor(p.uid) }
                    } label: {
                        Text("Put away").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minWidth: 84, minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.9)))
                    }.buttonStyle(.plain).accessibilityLabel("Put away \(item.name)").accessibilityIdentifier("bag-action-put-away-\(item.id)")
                }
            }
        default:
            EmptyView()
        }
    }

    /// The Sell button under the row's main action ("Sell +9"), or a disabled "Worn" / "In the room".
    @ViewBuilder
    private func sellButton(_ item: StoreItem) -> some View {
        switch book.sellState(item) {
        case .sellable(let pay):
            Button { AudioHub.shared.uiTap(); sellAsk = item } label: {
                Text("Sell +\(pay)").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).frame(minWidth: 84, minHeight: 44).background(Capsule().fill(Color.white.opacity(0.9)))
            }.buttonStyle(.plain).accessibilityLabel("Sell \(item.name) for \(pay) JellyCoins").accessibilityIdentifier("bag-sell-\(item.id)")
        case .worn:
            disabledSell("Worn", item)
        case .inRoom:
            disabledSell("In the room", item)
        case .no:
            EmptyView()
        }
    }
    private func disabledSell(_ text: String, _ item: StoreItem) -> some View {
        Text(text).font(SK.font(14, .heavy)).foregroundStyle(SK.muted).lineLimit(1).fixedSize()
            .padding(.horizontal, 14).frame(minWidth: 84, minHeight: 44).background(Capsule().fill(SK.muted.opacity(0.15)))
            .accessibilityLabel(text == "Worn" ? "\(item.name) is worn, so it cannot be sold" : "\(item.name) is in the room, so it cannot be sold").accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("bag-sell-blocked-\(item.id)")
    }

    /// "Sell Sushi roll?" over a dimmed Bag; a tap outside is Keep.
    @ViewBuilder
    private var sellCard: some View {
        if let item = sellAsk {
            let pay = StoreBook.sellPrice(item)
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { AudioHub.shared.uiTap(); sellAsk = nil }.accessibilityHidden(true)
                VStack(spacing: 14) {
                    Text("Sell \(item.name)?").font(SK.font(22, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text("You get \(pay) JellyCoin\(pay == 1 ? "" : "s").").font(SK.font(16, .semibold)).foregroundStyle(SK.ink.opacity(0.8)).multilineTextAlignment(.center)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { keepButton; sellConfirm(item) }
                        VStack(spacing: 10) { sellConfirm(item); keepButton }
                    }
                }
                .padding(20).frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0xFFFDF8))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(hex: 0x4D331F).opacity(0.10), lineWidth: 1))
                        .shadow(color: Color(hex: 0x5A3A2A).opacity(0.3), radius: 10, y: 4)
                )
                .padding(24)
                .accessibilityElement(children: .contain).accessibilityIdentifier("sell-card")
            }
            .transition(.opacity)
        }
    }
    private var keepButton: some View {
        Button { AudioHub.shared.uiTap(); sellAsk = nil } label: {
            Text("Keep").font(SK.font(17, .heavy)).foregroundStyle(SK.ink).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 22).frame(minWidth: 96, minHeight: 44).background(Capsule().fill(SK.honey)).contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("sell-keep")
    }
    private func sellConfirm(_ item: StoreItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.snappy) { _ = book.sell(item.id); sellAsk = nil }
        } label: {
            Text("Sell").font(SK.font(17, .black)).foregroundStyle(.white).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 22).frame(minWidth: 96, minHeight: 44).background(Capsule().fill(SK.pinkStrong)).contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel("Sell \(item.name)").accessibilityIdentifier("sell-confirm")
    }

    private func pink(_ title: String, _ item: StoreItem? = nil, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        let who = care.jelly(who)?.name
        let spoken: String = {
            guard let item else { return title }
            switch title {
            case "Feed": return who.map { "Feed \(item.name) to \($0)" } ?? "Feed \(item.name)"
            case "Wear": return who.map { "Wear \(item.name) on \($0)" } ?? "Wear \(item.name)"
            case "Take off": return who.map { "Take \(item.name) off \($0)" } ?? "Take off \(item.name)"
            case "Use": return who.map { "Use \(item.name) on \($0)" } ?? "Use \(item.name)"
            default: return "\(title) \(item.name)"
            }
        }()
        return Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); action() } label: {
            Text(title).font(SK.font(16, .black)).foregroundStyle(.white).padding(.horizontal, 18).frame(minWidth: 84, minHeight: 46)
                .background(Capsule().fill(enabled ? SK.pinkStrong : SK.muted.opacity(0.45)))
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(spoken).accessibilityIdentifier("bag-action-\(title.lowercased())")
    }

    private var roomMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Room space").font(SK.font(14, .black)).foregroundStyle(SK.ink)
                Spacer()
                Text("\(book.roomUnitsUsed) of \(StoreTuning.roomCapacity) spots").font(SK.font(13, .heavy)).foregroundStyle(SK.muted)
            }
            HStack(spacing: 4) {
                ForEach(0..<StoreTuning.roomCapacity, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4).fill(i < book.roomUnitsUsed ? SK.pink : SK.ink.opacity(0.12)).frame(height: 10)
                }
            }
            Text(book.beanbagPlaced ? "Big things take 2 spots. Beanbag on: love drains 15% slower." : "Big things take 2 spots").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.card))
        .accessibilityElement(children: .combine).accessibilityIdentifier("bag-room-meter")
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, w), height: y + rowH)
    }
    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = r.minX, y = r.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > r.maxX, x > r.minX { x = r.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

/// Sub-filter chips by wear slot (the Shop's and the Bag's Wear tab): "All" plus one chip per slot that has goods.
struct SlotChips: View {
    @Binding var slot: WearSlot?
    var slots: [WearSlot]
    var idPrefix: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", symbol: "square.grid.2x2.fill", on: slot == nil, id: "all") { slot = nil }
                ForEach(slots, id: \.rawValue) { s in chip(s.title, symbol: s.symbol, on: slot == s, id: s.rawValue) { slot = s } }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityIdentifier("\(idPrefix)chips")
    }
    private func chip(_ title: String, symbol: String, on: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); withAnimation(.easeInOut(duration: 0.12)) { action() } } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .heavy))
                Text(title).font(SK.font(13, .heavy))
            }
            .foregroundStyle(SK.ink).padding(.horizontal, 12).frame(minHeight: 44)
            .background(Capsule().fill(on ? SK.honey : Color.white.opacity(0.8)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("\(idPrefix)\(id)").accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// show-wardrobe-r1: the Jelly Show lobby's wardrobe rule. Opening the Studio (or picking another Jelmiko in it) remembers the everyday outfit before Dress up can change it;
/// leaving the Studio for anywhere but the Show-ready card (its Profile), picking someone else, or closing the Town gives it back. Enter Jelly Show keeps it until he is home.
private struct ShowWardrobeGuard: ViewModifier {
    let care: GameCare
    let screen: TownScreen?
    let who: Int
    func body(content: Content) -> some View {
        content
            .onAppear { if screen == .studio { care.showWardrobeReady(who) } }
            .onChange(of: screen) { _, now in
                if now == .studio { care.showWardrobeReady(who) } else if now != .condition { care.showWardrobeLeaveLobby() }
            }
            .onChange(of: who) { _, now in
                care.showWardrobeLeaveLobby()
                if screen == .studio { care.showWardrobeReady(now) }
            }
            .onDisappear { care.showWardrobeLeaveLobby() }
    }
}
extension View {
    func showWardrobeGuard(care: GameCare, screen: TownScreen?, who: Int) -> some View { modifier(ShowWardrobeGuard(care: care, screen: screen, who: who)) }
}
