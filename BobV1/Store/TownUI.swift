//
//  TownUI.swift
//  Places to go: the "Go out" pill, the Town ("Where to?": a little map, the destinations; the player goes alone, the Jellies stay home), the Track panel (Waddle / Focus, prizes,
//  Go race; Train comes next), the Bag sheet (boosts on now, snacks / wear / care with a pink action each, the room-space meter) and the HUD buttons
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
            Image(systemName: "door.left.hand.open").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(SK.ink).frame(width: 48, height: 48)
                .background(Circle().fill(SK.cream).shadow(color: SK.shadow.opacity(0.22), radius: 6, y: 2))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go out").accessibilityIdentifier("go-out")
    }
}

struct BagButton: View {
    let store: StoreBook
    var action: () -> Void
    var body: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: "bag.fill").font(.system(size: 19, weight: .heavy)).foregroundStyle(SK.ink)
                .frame(width: 48, height: 48)
                .background(Circle().fill(SK.cream).shadow(color: SK.shadow.opacity(0.22), radius: 6, y: 2))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if store.newCount > 0 {
                        Text("\(store.newCount)").font(SK.font(11, .black)).foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20).background(Circle().fill(SK.pink))
                            .overlay(Circle().strokeBorder(SK.cream, lineWidth: 2)).offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.newCount > 0 ? "Bag, \(store.newCount) new" : "Bag").accessibilityIdentifier("bag-button")
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
                Text(j.name).font(SK.font(11, .heavy)).foregroundStyle(SK.ink.opacity(0.8))
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

enum TownScreen: Equatable { case town, shop, track, studio, condition, show }

struct TownFlow: View {
    let care: GameCare
    @Binding var screen: TownScreen?
    @State var who: Int
    var goHome: () -> Void
    /// The Café: closes the Town and starts the café trip (the trip itself starts in the game, not on a Town screen).
    var cafe: () -> Void = {}
    /// The screen the flow opened on: its back button leaves the flow (the Go out button opens the Town, so Track / Store go back to it).
    @State private var root: TownScreen

    init(care: GameCare, screen: Binding<TownScreen?>, who: Int, cafe: @escaping () -> Void = {}, goHome: @escaping () -> Void) {
        self.care = care; self._screen = screen; self._who = State(initialValue: who); self.goHome = goHome; self.cafe = cafe
        self._root = State(initialValue: screen.wrappedValue ?? .town)
    }
    /// Back from the current screen: out of the flow when it is the root, else to `target`.
    private func up(_ target: TownScreen) { if (screen ?? .town) == root { goHome() } else { screen = target } }

    var currentScreen: TownScreen { screen ?? .town }
    func chooseCafe() { goHome(); cafe() }

    var body: some View {
        ZStack {
            switch screen ?? .town {
            case .town: TownView(care: care, go: { screen = $0 }, cafe: chooseCafe, home: goHome)
            case .shop: ShopScreen(care: care, who: who, back: { up(.town) }, goHome: goHome)
            case .track: TrackPanel(care: care, who: $who, back: { up(.town) }, race: { goHome(); care.startRace(jelly: who) }, train: { goHome(); care.startDrill(jelly: who) })
            case .studio: StudioScreen(care: care, who: $who, back: { up(.town) }, card: { screen = .condition }, show: { screen = .show },
                                       practise: { d in goHome(); care.startDancePractice(jelly: who, dance: d) })
            case .condition: ConditionScreen(care: care, who: $who, back: { if care.focus.isActive { goHome() } else { up(.studio) } }, show: { screen = .show }, bath: { goHome(); care.clean(jelly: who) })
            case .show: ShowLobby(care: care, who: $who, back: { up(.studio) }, card: { screen = .condition }, start: { r in goHome(); care.startShow(jelly: who, rank: r) })
            }
        }
        .transition(.opacity)
    }
}

struct WhoRow: View {
    let care: GameCare
    @Binding var who: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(care.jellies, id: \.id) { j in
                let t = JellyRoster.tint(j.character)
                Button { AudioHub.shared.uiTap(); who = j.id } label: {
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
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
    var home: () -> Void
    @Environment(\.verticalSizeClass) private var vsc

    var body: some View {
        VStack(spacing: vsc == .compact ? 8 : 14) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); home() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "house.fill").font(.system(size: 15, weight: .heavy))
                        Text("Home").font(SK.font(15, .heavy))
                    }
                    .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().fill(Color.white.opacity(0.85)))
                }
                .buttonStyle(.plain).accessibilityIdentifier("town-home")
                Spacer()
                DropsPill(wallet: care.bath.wallet)
            }
            if vsc == .compact {
                // a phone on its side: the title and the map on the left, the places on the right (scrolling if they must)
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 10) {
                        Text("Where to?").font(SK.font(30, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, alignment: .leading)
                        MapStrip().frame(maxHeight: 150)
                        Spacer(minLength: 0)
                    }
                    ScrollView { destinations.padding(.bottom, 12) }.scrollBounceBehavior(.basedOnSize)
                }
            } else {
                Text("Where to?").font(SK.font(34, .black)).foregroundStyle(SK.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MapStrip().frame(height: 118)
                destinations
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .background(SK.cream.ignoresSafeArea())
        .accessibilityElement(children: .contain).accessibilityIdentifier("town-screen")
    }

    private var destinations: some View {
        VStack(spacing: 10) {
            destination("Shop", "Snacks, shoes, tricks and more", "bag.fill", SK.pink, id: "town-shop") { go(.shop) }
            destination("Track", "Race for Drops", "flag.checkered", SK.sky, id: "town-track") { go(.track) }
            destination("Studio", "Dress up, dance, the Jelly Show", "sparkles", SK.honey, id: "town-studio") { go(.studio) }
            destination("Café", "Treats out with the gang", "cup.and.saucer.fill", SK.mint, id: "town-cafe") { cafe() }
        }
    }

    private func destination(_ title: String, _ sub: String, _ symbol: String, _ color: Color, id: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 24, weight: .heavy)).foregroundStyle(SK.ink)
                    .frame(width: 62, height: 62).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.opacity(enabled ? 1 : 0.5)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SK.font(22, .black)).foregroundStyle(SK.ink)
                    Text(sub).font(SK.font(13, .bold)).foregroundStyle(SK.muted)
                }
                Spacer()
                Image(systemName: enabled ? "chevron.right" : "lock.fill").font(.system(size: 15, weight: .black)).foregroundStyle(SK.muted)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 80)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card).shadow(color: SK.shadow.opacity(0.10), radius: 5, y: 2))
            .opacity(enabled ? 1 : 0.7)
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier(id)
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
                place("flag.checkered", "Track", SK.cream, x: w * 0.86, y: h * 0.52)
                place("sparkles", "Studio", SK.honey, x: w * 0.68, y: h * 0.30)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityHidden(true)
    }
    private func place(_ symbol: String, _ label: String, _ color: Color, x: CGFloat, y: CGFloat) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 17, weight: .heavy)).foregroundStyle(SK.ink)
                .frame(width: 40, height: 40).background(Circle().fill(color)).overlay(Circle().strokeBorder(.white, lineWidth: 2))
            Text(label).font(SK.font(11, .black)).foregroundStyle(SK.ink)
        }
        .position(x: x, y: y)
    }
}

// MARK: - Track

struct TrackPanel: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var race: () -> Void
    /// "Train": the picked Jelly practises Rhythm Steps alone on the track (Training/).
    var train: () -> Void = {}
    /// The Train button and the Pep bar show (training exists).
    static let trainingExists = true
    /// The course picked for the next race (Race/CoursePicker.swift sets it through GameCare.chooseCourse).
    var courseTier: CourseTier { care.race.courseTier }
    @Environment(\.verticalSizeClass) private var vsc

    var body: some View {
        let prof = care.jelly(who)
        let compact = vsc == .compact
        VStack(spacing: compact ? 8 : 14) {
            HStack(spacing: 10) {
                Button { AudioHub.shared.uiTap(); back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85)))
                }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("track-back")
                Text("Track").font(SK.font(30, .black)).foregroundStyle(SK.ink)
                Spacer()
                DropsPill(wallet: care.bath.wallet)
            }
            ScrollView {
                if compact {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 10) {
                            raceCard
                            courseCard
                            prizes
                        }
                        statCard(prof)
                    }
                } else {
                    VStack(spacing: 14) {
                        raceCard
                        courseCard
                        statCard(prof)
                        prizes
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 12) {
                if Self.trainingExists {
                    Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); train() } label: {
                        HStack(spacing: 8) { Image(systemName: "figure.walk").font(.system(size: 18, weight: .heavy)); Text("Train").font(SK.font(19, .black)).lineLimit(1) }
                            .foregroundStyle(blocker == nil ? SK.ink : SK.muted).frame(maxWidth: .infinity, minHeight: compact ? 48 : 58)
                            .background(Capsule().fill(Color.white.opacity(0.9)))
                            .overlay(Capsule().strokeBorder(blocker == nil ? SK.ink : SK.muted.opacity(0.4), lineWidth: 3))
                    }
                    .buttonStyle(.plain).disabled(blocker != nil).accessibilityIdentifier("track-train")
                }
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); race() } label: {
                    HStack(spacing: 8) { Image(systemName: "flag.checkered").font(.system(size: 18, weight: .heavy)); Text("Go race").font(SK.font(20, .black)) }
                        .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: compact ? 48 : 58)
                        .background(Capsule().fill(blocker == nil ? SK.pink : SK.muted.opacity(0.5)))
                }
                .buttonStyle(.plain).disabled(blocker != nil).accessibilityIdentifier("track-race")
            }
            if let why = blocker { Text(why).font(SK.font(12, .bold)).foregroundStyle(SK.muted).accessibilityIdentifier("track-why") }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(SK.cream.ignoresSafeArea())
        .accessibilityElement(children: .contain).accessibilityIdentifier("track-screen")
    }

    private func statCard(_ prof: JellyProfile?) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(prof?.name ?? "Bob") races").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                        Text("Class: \(courseTier.className) (\(courseTier.title))").font(SK.font(13, .bold)).foregroundStyle(SK.muted).accessibilityIdentifier("track-class")
                    }
                    Spacer()
                    if care.jellies.count > 1 { Text("Switch").font(SK.font(11, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase) }
                }
                if care.jellies.count > 1 { WhoRow(care: care, who: $who) }
                bar("Waddle", prof?.stats.waddle ?? 0, "Longer steps, quicker feet", SK.pink)
                bar("Focus", prof?.stats.focus ?? 0, "Fewer look-arounds", SK.sky)
                if Self.trainingExists, let st = prof?.stats { pep(st) }
                if let p = prof, !p.perks.raceBoost.isNone {
                    HStack(spacing: 6) {
                        ForEach(p.perks.active.filter(\.raceOnly), id: \.rawValue) { PerkChip(kind: $0, left: p.perks.remaining($0)) }
                        Text("for the next race").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    private var blocker: String? { care.raceBlocker(jelly: who) }

    /// Pep: three pips (full value practice sessions left today) and the note.
    private func pep(_ st: JellyStats) -> some View {
        let left = st.pepLeft
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Pep").font(SK.font(15, .heavy)).foregroundStyle(SK.ink).frame(width: 52, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(0..<TrainingTuning.fullSessions, id: \.self) { i in
                        Capsule().fill(i < left ? SK.mint : Color(hex: 0xE6D8C6)).frame(height: 14)
                    }
                }
                Text("\(left)/\(TrainingTuning.fullSessions)").font(SK.font(14, .black)).foregroundStyle(SK.ink).monospacedDigit().frame(width: 34, alignment: .trailing)
            }
            Text("Pep refills overnight. Practice after that still helps, just less.").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("track-pep")
    }

    /// The race itself: its name, the field and how it is played.
    private var raceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "flag.checkered").font(.system(size: 26, weight: .heavy)).foregroundStyle(SK.ink)
                .frame(width: 62, height: 62).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SK.sky))
            VStack(alignment: .leading, spacing: 3) {
                Text("Waddle Sprint").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                Text("You and two rivals on the \(courseTier.title). Tap the two foot buttons to waddle faster.").font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
        .accessibilityElement(children: .combine)
    }

    /// The course picker (Race/CoursePicker.swift): the four courses, their shapes, locks and classes.
    private var courseCard: some View {
        CoursePicker(care: care)
            .padding(12).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    /// The prizes of the picked course.
    private var prizes: some View {
        HStack(spacing: 10) {
            prize("1st", RaceTuning.drops(place: 1, tier: courseTier)); prize("2nd", RaceTuning.drops(place: 2, tier: courseTier)); prize("3rd", RaceTuning.drops(place: 3, tier: courseTier))
        }
        .accessibilityIdentifier("track-prizes")
    }

    private func bar(_ name: String, _ v: Float, _ sub: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(name).font(SK.font(15, .heavy)).foregroundStyle(SK.ink); Spacer(); Text("\(Int((v * 100).rounded()))").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit() }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(SK.ink.opacity(0.1))
                    Capsule().fill(c).frame(width: max(14, g.size.width * CGFloat(min(max(v, 0), 1))))
                }
            }.frame(height: 14)
            Text(sub).font(SK.font(11, .bold)).foregroundStyle(SK.muted)
        }
        .accessibilityElement(children: .combine)
    }
    private func prize(_ place: String, _ n: Int) -> some View {
        VStack(spacing: 4) {
            Text(place).font(SK.font(13, .heavy)).foregroundStyle(SK.muted)
            HStack(spacing: 4) { Image(systemName: "drop.fill").font(.system(size: 13, weight: .black)).foregroundStyle(SK.sky); Text("\(n)").font(SK.font(20, .black)).foregroundStyle(SK.ink) }
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(place == "1st" ? SK.honey : SK.card))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bag

struct BagSheet: View {
    let care: GameCare
    @State var who: Int
    var close: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @State private var tab: BagTab

    /// `tab`: the tab to open on (Dress / Play / Decor from the HUD); nil = the `-StoreTab` capture arg, else Snacks.
    init(care: GameCare, who: Int, tab: BagTab? = nil, close: @escaping () -> Void) {
        self.care = care; self._who = State(initialValue: who); self.close = close
        self._tab = State(initialValue: tab ?? BagTab(rawValue: { let n = (UserDefaults.standard.string(forKey: "StoreTab") ?? "").capitalized; return n == "Decor" ? "Furniture" : n }()) ?? .snacks)          // (-StoreTab decor: capture aid)
    }

    enum BagTab: String, CaseIterable, Identifiable { case snacks = "Snacks", wear = "Wear", furniture = "Furniture", toys = "Toys", care = "Care", rooms = "Rooms"; var id: String { rawValue }; var isDecor: Bool { self == .furniture || self == .toys } }
    private var book: StoreBook { care.store }

    private var tabs: [BagTab] { BagTab.allCases }
    private func entries(_ t: BagTab) -> [StoreItem] {
        switch t {
        case .snacks: return StoreCatalog.items.filter { $0.food != nil && book.count($0.id) > 0 }
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

    var body: some View {
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
                boosts
                WhoRow(care: care, who: $who)
                ScrollViewReader { proxy in ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                    ForEach(tabs) { t in
                        Button { AudioHub.shared.play(.pageTurn); tab = t } label: {
                            Text("\(t.rawValue) \(count(t))").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(1).fixedSize()
                                .padding(.horizontal, 12).frame(minHeight: 44).background(Capsule().fill(t == tab ? SK.honey : Color.white.opacity(0.8)))
                        }.buttonStyle(.plain).accessibilityIdentifier("bag-tab-\(t.rawValue.lowercased())").id(t)
                    }
                }.onAppear { proxy.scrollTo(tab, anchor: .center) } } }
                let list = entries(tab)
                if tab == .wear { SlotChips(slot: $wearSlot, slots: WearSlot.allCases.filter { s in StoreCatalog.items.contains { $0.wear?.slot == s && book.owns($0) } }, idPrefix: "bag-slot-") }
                if tab.isDecor, !book.placedDecor.isEmpty {
                    Button { AudioHub.shared.uiTap(); close(); care.beginArrange() } label: {
                        HStack(spacing: 8) { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 15, weight: .heavy)); Text("Arrange the room").font(SK.font(15, .black)) }
                            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 48).background(Capsule().fill(SK.honey))
                    }.buttonStyle(.plain).accessibilityIdentifier("bag-arrange")
                }
                if list.isEmpty, tab != .rooms {
                    Text(tab == .snacks ? "No snacks yet. The Shop has plenty." : tab == .furniture ? "No furniture yet. Beanbags, sofas and more are in the Shop." : tab == .toys ? "No toys yet. Balls, ducks and more are in the Shop." : "Nothing here yet.").font(SK.font(14, .bold)).foregroundStyle(SK.muted)
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
        .onAppear { book.markSeen() }
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
                    Image(systemName: "house.fill").font(.system(size: 24, weight: .heavy)).foregroundStyle(SK.ink.opacity(0.8))
                        .frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SK.honey.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.title).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                        Text(d.blurb).font(SK.font(12, .semibold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if here {
                        Text("Home now").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 40)
                            .background(Capsule().fill(SK.mint.opacity(0.85))).accessibilityIdentifier("bag-room-here-\(d.id.rawValue)")
                    } else {
                        pink("Move in", enabled: true) {
                            if let why = care.switchRoom(d.id) { roomRefusal = why.message } else { close() }
                        }.accessibilityIdentifier("bag-room-movein-\(d.id.rawValue)")
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card))
                .accessibilityIdentifier("bag-room-\(d.id.rawValue)")
            }
        }
    }

    private var boosts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boosts on now").font(SK.font(12, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
            let rows = care.perkRows.filter { !$0.perks.isEmpty }
            if rows.isEmpty {
                Text("None. A snack can give one.").font(SK.font(13, .bold)).foregroundStyle(SK.muted)
            }
            ForEach(rows, id: \.id) { r in
                HStack(alignment: .top, spacing: 8) {
                    Text(r.name).font(SK.font(14, .black)).foregroundStyle(SK.ink).frame(width: 42, alignment: .leading)
                    FlowChips(items: r.perks.map { ($0.kind, $0.left) })
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SK.card))
        .accessibilityIdentifier("bag-boosts")
    }

    private func row(_ item: StoreItem) -> some View {
        HStack(spacing: 12) {
            ItemArt(item: item, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                if let w = item.wear { Text(book.worn(who, w.slot) == w ? "Wearing" : "Owned").font(SK.font(12, .bold)).foregroundStyle(SK.muted) }
                else if item.kind == .decor {
                    let placed = book.placedCount(item.id)
                    Text("x\(book.count(item.id))" + (placed > 0 ? " \u{00B7} \(placed) in the room" : "") + " \u{00B7} \(item.roomUnits) spot\(item.roomUnits == 1 ? "" : "s")").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
                    if let why = book.placeBlocker(item), book.unplaced(item.id) > 0 { Text(why).font(SK.font(11, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true) }
                }
                else { Text("x\(book.count(item.id))").font(SK.font(13, .heavy)).foregroundStyle(SK.muted) }
                if let p = item.perk { PerkChip(kind: p) }
            }
            Spacer(minLength: 0)
            actionButton(item)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card))
        .accessibilityIdentifier("bag-row-\(item.id)")
    }

    @ViewBuilder
    private func actionButton(_ item: StoreItem) -> some View {
        switch item.kind {
        case .food, .treat:
            pink("Feed", enabled: !care.trayOut && !care.bath.active && !care.race.active) {
                close(); care.feedSnack(item.id, jelly: who)
            }
        case .shoes, .wear:
            let slot = item.wear?.slot ?? .feet
            let wearing = book.worn(who, slot) == item.wear
            pink(wearing ? "Take off" : "Wear", enabled: true) {
                if wearing { book.takeOff(slot, from: who) }
                else if let w = item.wear, book.wear(w, on: who) { AudioHub.shared.play(.shoeOn); care.jelly(who)?.stats.nudge([.cool: 0.02]) }
            }
        case .supply:
            pink("Use", enabled: care.canClean(jelly: who)) { close(); care.useSupply(item.id, on: who) }
        case .decor:
            VStack(spacing: 6) {
                pink("Place", enabled: book.canPlace(item)) { close(); care.placeDecor(item.id) }
                if book.placedCount(item.id) > 0 {
                    Button {
                        AudioHub.shared.uiTap()
                        if let p = book.placedDecor.last(where: { $0.kind.storeID == item.id }) { care.putAwayDecor(p.uid) }
                    } label: {
                        Text("Put away").font(SK.font(14, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minWidth: 84, minHeight: 40)
                            .background(Capsule().fill(Color.white.opacity(0.9)))
                    }.buttonStyle(.plain).accessibilityIdentifier("bag-action-put-away-\(item.id)")
                }
            }
        default:
            EmptyView()
        }
    }

    private func pink(_ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); action() } label: {
            Text(title).font(SK.font(16, .black)).foregroundStyle(.white).padding(.horizontal, 18).frame(minWidth: 84, minHeight: 46)
                .background(Capsule().fill(enabled ? SK.pink : SK.muted.opacity(0.45)))
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(title).accessibilityIdentifier("bag-action-\(title.lowercased())")
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

/// Chips that wrap onto more lines.
struct FlowChips: View {
    let items: [(PerkKind, TimeInterval)]
    var body: some View {
        FlowLayout(spacing: 6) { ForEach(items, id: \.0.rawValue) { PerkChip(kind: $0.0, left: $0.1) } }
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
            .foregroundStyle(SK.ink).padding(.horizontal, 12).frame(minHeight: 40)
            .background(Capsule().fill(on ? SK.honey : Color.white.opacity(0.8)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("\(idPrefix)\(id)").accessibilityAddTraits(on ? .isSelected : [])
    }
}
