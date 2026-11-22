//
//  TrophyCase.swift
//  The trophy case's two player-facing pieces (trophy-case-r1):
//
//    SETTINGS   double-tap the case on the wall: a small card with "Show trophy case in the room" (on by default, saved in TrophyBook) and the list of trophies.
//               Off: the shelf is not drawn; the same switch sits at the top of the Trophies sheet and in Settings, so it can always be turned back on.
//    ENGRAVING  tap a trophy on the shelf (or its row in the card): the camera eases in on it and an engraved plate shows the Jelmiko's name, the event and the date.
//               The dates are written at the win (JelbieTrophies.won); a win from before that shows "Won earlier".
//
//  Nothing here changes how trophies are earned.
//

import SwiftUI
import simd

/// What the plate says about one trophy on the shelf.
nonisolated struct TrophyShelfItem: Equatable, Sendable, Identifiable {
    var id: String          // "cup.<tier>", "contest", "wins5" / "wins10" / "wins25" / "champion", "volley.<tier>"
    var event: String       // "Jelly Race (Puddle) \u{2013} 1st"
    var character: Int?     // who won it (nil: not known)
    var date: Date?         // nil: won before dates were kept

    static func dateText(_ d: Date?) -> String {
        guard let d else { return "Won earlier" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

extension TrophyBook {
    private static func ord(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : "3rd" }

    /// Every trophy drawn on the wall shelf for `spec`, with who won it and when (the same rules as `roomShelf`: the best place over every Jelmiko).
    /// `contestWho` = the Jelmiko holding the best Show cup (ShowProgress.bestCupCharacter).
    func shelfItems(spec: TrophyShelfSpec, contestWho: Int?) -> [TrophyShelfItem] {
        let books = shelves.compactMap { k, v in Int(k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        func earliest(_ key: String, among who: [Int]) -> (Int?, Date?) {
            var best: (Int, Date)?
            for (c, s) in books where who.contains(c) { if let d = s.won?[key], best == nil || d < best!.1 { best = (c, d) } }
            return (best?.0 ?? who.first, best?.1)
        }
        var out: [TrophyShelfItem] = []
        for (k, t) in CourseTier.allCases.enumerated() where spec.cups[k] != 0 {
            let p = Int(spec.cups[k])
            let holders = books.filter { $0.1.bestRace(t) == p }.map(\.0)
            let (c, d) = earliest("race.\(t.rawValue).\(p)", among: holders)
            out.append(TrophyShelfItem(id: "cup.\(t.rawValue)", event: "Jelly Race (\(t.title)) \u{2013} \(Self.ord(p))", character: c, date: d))
        }
        if spec.contest != 0 {
            let p = Int(spec.contest)
            var d: Date?
            if let w = contestWho, let s = shelves["\(w)"]?.won { d = ShowRank.allCases.compactMap { s["show.\($0.rawValue).\(p)"] }.min() }
            out.append(TrophyShelfItem(id: "contest", event: "Jelly Show \u{2013} \(Self.ord(p))", character: contestWho, date: d))
        }
        for (k, t) in [Trophy.wins5, .wins10, .wins25, .champion].enumerated() where spec.milestones[k] {
            let holders = books.filter { $0.1.has(t) }.map(\.0)
            let (c, d) = earliest("trophy.\(t.id)", among: holders)
            out.append(TrophyShelfItem(id: t.id, event: "Jelly Race \u{2013} \(t.title)", character: c, date: d))
        }
        for (k, t) in VolleyTier.allCases.enumerated() where spec.volley[k] {
            let holders = books.filter { $0.1.volleyWon(t) > 0 }.map(\.0)
            let (c, d) = earliest("volley.\(t.rawValue)", among: holders)
            out.append(TrophyShelfItem(id: "volley.\(t.rawValue)", event: "Beach Volleyball (\(t.title)) \u{2013} 1st", character: c, date: d))
        }
        return out
    }
}

extension ShowProgress {
    /// The Jelmiko with the best Show cup (lowest placing; the lowest id on a tie), nil when none.
    var bestCupCharacter: Int? {
        saved.trophies.compactMap { k, v in v.cups.values.min().flatMap { m in Int(k).map { ($0, m) } } }.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.first?.0
    }
}

// MARK: - Shelf positions (wall units)

extension TrophyShelfGeometry {
    struct Slot: Equatable { var id: String; var x: Float; var y: Float }
    /// Where each trophy of `spec` stands on the wall (the middle of the cup), the same slots `add` draws them in. Empty when the room has no shelf.
    static func slots(_ spec: TrophyShelfSpec, def: RoomDef = RoomLayout.current) -> [Slot] {
        guard !spec.isEmpty, let sp = spot(def) else { return [] }
        let upperY = sp.y + 0.62, volleyY = upperY + 0.62, lift: Float = 0.11
        var out: [Slot] = []
        let slot = sp.width / Float(spec.cups.count)
        for (k, t) in CourseTier.allCases.enumerated() where spec.cups[k] != 0 { out.append(Slot(id: "cup.\(t.rawValue)", x: sp.x - sp.width / 2 + slot * (Float(k) + 0.5), y: sp.y + lift)) }
        let slot2 = sp.width / 5
        func x2(_ k: Int) -> Float { sp.x - sp.width / 2 + slot2 * (Float(k) + 0.5) }
        if spec.contest != 0 { out.append(Slot(id: "contest", x: x2(0), y: upperY + 0.2)) }
        for (k, t) in [Trophy.wins5, .wins10, .wins25, .champion].enumerated() where spec.milestones[k] { out.append(Slot(id: t.id, x: x2(k + 1), y: upperY + lift)) }
        let slot3 = sp.width / Float(spec.volley.count)
        for (k, t) in VolleyTier.allCases.enumerated() where spec.volley[k] { out.append(Slot(id: "volley.\(t.rawValue)", x: sp.x - sp.width / 2 + slot3 * (Float(k) + 0.5), y: volleyY + lift)) }
        return out
    }
    /// The case's whole face on the wall (all planks): a double tap anywhere on it opens the card.
    static func faceRect(_ spec: TrophyShelfSpec, def: RoomDef = RoomLayout.current) -> (x0: Float, x1: Float, y0: Float, y1: Float)? {
        guard !spec.isEmpty, let sp = spot(def) else { return nil }
        let top = (spec.volley.contains(true) ? sp.y + 1.24 : sp.y + 0.62) + 0.34
        return (sp.x - sp.width / 2, sp.x + sp.width / 2, sp.y - 0.12, top)
    }
}

// MARK: - Camera

extension GameCamera {
    /// 0 = the room camera, 1 = looking at one trophy (eased by `GameCare.tickTrophyFocus`; like `wallEditBlend`, global so the finger maths follow it).
    nonisolated(unsafe) static var trophyBlend: Float = 0
    /// The wall point (x, y) the trophy view looks at.
    nonisolated(unsafe) static var trophyAt = SIMD2<Float>(0, 3)
    /// Straight at the wall, close enough that a cup fills a good part of the screen; the cup sits above the middle so the plate has room below.
    static func trophyPose(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let visibleH: Float = 2.6          // (the height of wall in view; the width follows the aspect)
        let d = visibleH * 0.5 / tanf(fovY / 2)
        let drop: Float = visibleH * (aspect > 1 ? 0.16 : 0.2)
        let t = SIMD3<Float>(trophyAt.x, trophyAt.y - drop, RoomLayout.minZ)
        return (t + SIMD3(0, 0, d), t)
    }
}

// MARK: - State

extension GameCare {
    /// The wall case as it is drawn: nothing when the player hid it.
    var shownTrophySpec: TrophyShelfSpec {
        race.trophies.caseVisible ? race.trophies.roomShelf(contestBest: show.progress.bestCup) : TrophyShelfSpec()
    }
    var trophyItems: [TrophyShelfItem] { race.trophies.shelfItems(spec: race.trophies.roomShelf(contestBest: show.progress.bestCup), contestWho: show.progress.bestCupCharacter) }
    var trophyFocused: TrophyShelfItem? { trophyFocusID.flatMap { id in trophyItems.first { $0.id == id } } }
    /// "Jelmiko name" for a plate: the Jelmiko's own name while he is home; "A Jelmiko" when he is not on the roster any more or the win predates records.
    func trophyWinnerName(_ item: TrophyShelfItem) -> String {
        guard let c = item.character else { return "A Jelmiko" }
        return jellies.first { $0.character == c }?.name ?? "A Jelmiko"
    }

    func openTrophyCard() { guard !trophyCardOpen else { return }; AudioHub.shared.uiTap(); trophyCardOpen = true; A11yEvents.say("Trophy case settings", .normal) }
    func closeTrophyCard() { trophyCardOpen = false; trophyFocusID = nil }
    func setTrophyCase(visible: Bool) {
        race.trophies.setCaseVisible(visible)
        if !visible { trophyFocusID = nil }
    }
    func focusTrophy(_ id: String) {
        guard race.trophies.caseVisible, let s = TrophyShelfGeometry.slots(race.trophies.roomShelf(contestBest: show.progress.bestCup)).first(where: { $0.id == id }) else { return }
        GameCamera.trophyAt = SIMD2(s.x, s.y)
        trophyFocusID = id
        AudioHub.shared.uiTap()
        if let it = trophyFocused { A11yEvents.say("\(trophyWinnerName(it)). \(it.event). \(TrophyShelfItem.dateText(it.date))", .normal) }
    }
    func unfocusTrophy() { trophyFocusID = nil }

    /// Once per fixed step: eases the camera toward the focused trophy and back.
    func tickTrophyFocus(dt: Float) {
        let target: Float = trophyFocusID != nil ? 1 : 0
        guard trophyFocusT != target else { return }
        let step = dt / 0.5
        trophyFocusT = target > trophyFocusT ? min(trophyFocusT + step, 1) : max(trophyFocusT - step, 0)
        GameCamera.trophyBlend = trophyFocusT * trophyFocusT * (3 - 2 * trophyFocusT)
    }

    /// Where a tap on the wall lands on the case: a trophy (its id), or just the case's face (`face`), else nothing. `ndc`/`invViewProj` are from the frame on screen.
    func trophyHit(wall w: SIMD2<Float>) -> (item: String?, face: Bool) {
        let spec = race.trophies.roomShelf(contestBest: show.progress.bestCup)
        guard race.trophies.caseVisible, let f = TrophyShelfGeometry.faceRect(spec), w.x >= f.x0 - 0.05, w.x <= f.x1 + 0.05, w.y >= f.y0, w.y <= f.y1 else { return (nil, false) }
        let hit = TrophyShelfGeometry.slots(spec).filter { abs($0.x - w.x) < 0.12 && abs($0.y - w.y) < 0.2 }.min { simd_distance(SIMD2($0.x, $0.y), w) < simd_distance(SIMD2($1.x, $1.y), w) }
        return (hit?.id, true)
    }
}

// MARK: - Screens

/// The card (double tap on the case) and the plate (a focused trophy). Transparent to touches except the card, the plate and the focus view's "Back".
struct TrophyCaseOverlay: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }

    var body: some View {
        GeometryReader { g in
            ZStack {
                if let item = care.trophyFocused {
                    Color.clear.contentShape(Rectangle()).onTapGesture { care.unfocusTrophy() }
                        .accessibilityHidden(true)
                    plate(item).frame(maxWidth: 360)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottomLeading : .bottom)
                        .padding(.horizontal, 16).padding(.bottom, compact ? 16 : 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if care.trophyCardOpen {
                    card.frame(maxWidth: compact ? 340 : 420)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .trailing : .bottom)
                        .padding(.horizontal, 12).padding(.top, compact ? 12 : 0).padding(.bottom, compact ? 12 : 110)
                        .transition(.move(edge: compact ? .trailing : .bottom).combined(with: .opacity))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.25), value: care.trophyCardOpen)
            .animation(.easeInOut(duration: 0.25), value: care.trophyFocusID)
        }
        .allowsHitTesting(care.trophyCardOpen || care.trophyFocusID != nil)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trophy case").font(SK.font(22, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { care.closeTrophyCard() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85)))
                }.buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("trophy-card-close")
            }
            TrophyCaseToggle(care: care)
            let items = care.trophyItems
            if !items.isEmpty {
                Text("Tap a trophy to look at it").font(SK.font(12, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(items) { it in
                            Button { care.focusTrophy(it.id) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trophy.fill").font(.system(size: 14, weight: .black)).foregroundStyle(ShowUI.goldDeep).accessibilityHidden(true)
                                    Text(it.event).font(SK.font(13, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9).frame(minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.8)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(it.event), \(care.trophyWinnerName(it)), \(TrophyShelfItem.dateText(it.date))")
                            .accessibilityHint("Looks at the trophy")
                            .accessibilityIdentifier("trophy-row-\(it.id)")
                        }
                    }
                }
                .frame(maxHeight: compact ? 110 : 150)
                .disabled(!care.race.trophies.caseVisible)
                .opacity(care.race.trophies.caseVisible ? 1 : 0.45)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 12, y: 4))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trophy-card")
        .accessibilityAction(.escape) { care.closeTrophyCard() }
    }

    /// The engraved brass plate.
    private func plate(_ item: TrophyShelfItem) -> some View {
        let name = care.trophyWinnerName(item), date = TrophyShelfItem.dateText(item.date)
        let brass = Color(red: 0.80, green: 0.62, blue: 0.28), dark = Color(red: 0.36, green: 0.24, blue: 0.08)
        return VStack(spacing: 10) {
            VStack(spacing: 6) {
                Text(name).font(SK.font(24, .black)).foregroundStyle(dark)
                Text(item.event).font(SK.font(16, .heavy)).foregroundStyle(dark).multilineTextAlignment(.center)
                Rectangle().fill(dark.opacity(0.35)).frame(height: 1).padding(.horizontal, 24)
                Text(date).font(SK.font(15, .bold)).foregroundStyle(dark.opacity(0.85))
            }
            .shadow(color: .white.opacity(0.55), radius: 0, x: 0, y: 1)          // (the engraved look: a light edge under dark letters)
            .padding(.horizontal, 22).padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [brass.opacity(0.95), Color(red: 0.93, green: 0.80, blue: 0.48), brass], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(dark.opacity(0.5), lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Engraved plate. \(name). \(item.event). \(date)")
            .accessibilityIdentifier("trophy-plate")
            Button { care.unfocusTrophy() } label: {
                Text("Back").font(SK.font(16, .black)).foregroundStyle(SK.ink).padding(.horizontal, 28).frame(minHeight: 44).background(Capsule().fill(SK.cream))
            }.buttonStyle(.plain).accessibilityIdentifier("trophy-plate-back")
        }
    }
}

/// "Show trophy case in the room": the switch, on the card, in the Trophies sheet and in Settings.
struct TrophyCaseToggle: View {
    let care: GameCare
    var body: some View {
        Toggle(isOn: Binding(get: { care.race.trophies.caseVisible }, set: { care.setTrophyCase(visible: $0) })) {
            Text("Show trophy case in the room").font(SK.font(15, .black)).foregroundStyle(SK.ink)
        }
        .tint(SK.sky)
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.8)))
        .accessibilityIdentifier("trophy-case-toggle")
    }
}
