//
//  TrophyCardLooks.swift
//  Three candidate looks for the Trophy Shelf card (owner: "redesign this, make it look better, this is too bland"), behind the developer launch argument
//  `-TrophyCardStyle A|B|C` (DevArgs-gated). With no argument the card is today's card, so nothing changes for players until a look is picked.
//
//    A  Rich rows   gold-cup header, a slim switch row, rows grouped under coloured chips (Races / Shows / Volleyball): medallion, event, place + date, the winner's face.
//    B  Grid        three-column tiles, each trophy standing on a little wooden shelf line, a short caption, the winner's face in the corner.
//    C  By Jelmiko  one block per winner (face, name, count) with a horizontal row of that Jelmiko's trophies; most trophies first.
//
//  Every look: the same content and behaviour as the plain card (title, close, show-in-room switch, tap a trophy to look at it), who won and when, and the
//  trophy pictures are real mini renders of each trophy's own mesh (StoreThumb, cached), in its real colour.
//

import SwiftUI
import UIKit
import simd

enum TrophyCardStyle: String {
    case a = "A", b = "B", c = "C"
    /// nil = today's card.
    static var current: TrophyCardStyle? {
        guard DevArgs.enabled, let s = UserDefaults.standard.string(forKey: "TrophyCardStyle") else { return nil }
        return TrophyCardStyle(rawValue: s.uppercased())
    }
}

// MARK: - what a trophy looks like in a list

enum TrophyKind { case race, show, volley }

struct TrophyEntry: Identifiable {
    var item: TrophyShelfItem
    var id: String { item.id }
    var kind: TrophyKind
    var title: String          // "Jelly Race · Puddle"
    var caption: String        // "Puddle · 1st"
    var place: String          // "1st place"
    var ui: Color              // the trophy's metal / court tint
    var mesh: SIMD3<Float>     // the same, for the mini render
    var placeNumber: Int

    private static func ord(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : "3rd" }
    private static let goldS = SIMD3<Float>(0.97, 0.78, 0.26), silverS = SIMD3<Float>(0.84, 0.87, 0.92), bronzeS = SIMD3<Float>(0.80, 0.52, 0.32)
    private static func metal(_ p: Int) -> SIMD3<Float> { p == 1 ? goldS : p == 2 ? silverS : bronzeS }
    private static let volleyS: [SIMD3<Float>] = [SIMD3(0.93, 0.78, 0.48), SIMD3(0.40, 0.78, 0.84), SIMD3(0.95, 0.52, 0.46), SIMD3(0.32, 0.50, 0.90)]

    static func make(_ it: TrophyShelfItem, spec: TrophyShelfSpec) -> TrophyEntry {
        var kind = TrophyKind.race, title = it.event, caption = it.event, place = "1st place", rgb = goldS, n = 1
        if it.id.hasPrefix("cup."), let t = CourseTier(rawValue: String(it.id.dropFirst(4))), let k = CourseTier.allCases.firstIndex(of: t) {
            n = Int(spec.cups[k]); rgb = metal(n); title = "Jelly Race \u{00B7} \(t.title)"; caption = "\(t.title) \u{00B7} \(ord(n))"; place = "\(ord(n)) place"
        } else if it.id == "contest" {
            kind = .show; n = Int(spec.contest); rgb = metal(n); title = "Jelly Show"; caption = "Show \u{00B7} \(ord(n))"; place = "\(ord(n)) place"
        } else if let k = ["wins5", "wins10", "wins25"].firstIndex(of: it.id) {
            let w = [5, 10, 25][k]; rgb = [bronzeS, silverS, goldS][k]; title = "\(w) race wins"; caption = "\(w) wins"; place = "Jelly Race milestone"
        } else if it.id == "champion" {
            title = "Race Champion"; caption = "Champion"; place = "Won on every course"
        } else if it.id.hasPrefix("volley."), let t = VolleyTier(rawValue: String(it.id.dropFirst(7))), let k = VolleyTier.allCases.firstIndex(of: t) {
            kind = .volley; rgb = volleyS[min(k, 3)]; title = "Beach Volleyball \u{00B7} \(t.title)"; caption = "\(t.title) \u{00B7} 1st"; place = "1st place"
        }
        return TrophyEntry(item: it, kind: kind, title: title, caption: caption, place: place,
                           ui: Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)), mesh: RaceModels.srgb(rgb.x * 0.74, rgb.y * 0.70, rgb.z * 0.66), placeNumber: n)          // (a little deeper than the wall's metal: the lit mini render washes it out)
    }

    /// The trophy's own mesh, rendered small once (StoreThumb caches by key).
    @MainActor var picture: UIImage? {
        guard let m = TrophyShelfGeometry.singleMesh(id: id, color: mesh)?.mesh else { return nil }
        return StoreThumb.image("trophy-\(id)-\(placeNumber)", mesh: m, size: 200, yaw: 0.32, pitch: 0.16, tight: true)
    }
}

extension GameCare {
    var trophyEntries: [TrophyEntry] {
        let spec = race.trophies.roomShelf(contestBest: show.progress.bestCup)
        return trophyItems.map { TrophyEntry.make($0, spec: spec) }
    }
    /// The winner's home id (index in `jellies`), nil when he is gone (at the Camp, let go, unknown).
    func trophyWinnerHomeID(_ item: TrophyShelfItem) -> Int? { item.character.flatMap { c in jellies.first { $0.character == c }?.id } }
}

// MARK: - small pieces

private enum TL {
    static let goldDeep = ShowUI.goldDeep, honey = SK.honey
    static let plateInk = Color(red: 0.36, green: 0.24, blue: 0.08)
    static let woodTop = Color(hex: 0xF5CFA8), woodFront = Color(hex: 0xC48B5E)
    static func tint(_ k: TrophyKind) -> Color { k == .race ? SK.sky : k == .show ? ShowUI.lilacPale : SK.honey }          // (tile backgrounds: cool / lilac / honey so a gold cup stands out)
    static func chip(_ k: TrophyKind) -> Color { k == .race ? ShowUI.goldDeep : k == .show ? ShowUI.lilac : SK.sky }
    static func chipName(_ k: TrophyKind) -> String { k == .race ? "Races" : k == .show ? "Shows" : "Volleyball" }
}

/// The winner's whole face (the game's head picture, no clothes), or a neutral silhouette when he is gone.
private struct WinnerFace: View {
    let care: GameCare
    let item: TrophyShelfItem
    var size: CGFloat
    var body: some View {
        Group {
            if let id = care.trophyWinnerHomeID(item) {
                JelbiePortrait(care: care, who: id, size: size, head: true, frameless: true)
            } else {
                ZStack {
                    Circle().fill(SK.pepEmpty)
                    Image(systemName: "person.fill").font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(SK.muted.opacity(0.7))
                }.frame(width: size * 0.86, height: size * 0.86).frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TrophyPic: View {
    let e: TrophyEntry
    var size: CGFloat
    var body: some View {
        Group {
            if let img = e.picture { Image(uiImage: img).resizable().scaledToFit() }
            else { Image(systemName: "trophy.fill").font(.system(size: size * 0.6, weight: .black)).foregroundStyle(e.ui) }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct CloseX: View {
    let care: GameCare
    var body: some View {
        Button { care.closeTrophyCard() } label: {
            Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85)))
        }.buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("trophy-card-close")
    }
}

/// A scroll view that is only as tall as its content, up to `maxHeight`.
private struct FitScroll<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var h: CGFloat = 10
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    content().background(GeometryReader { g in Color.clear.preference(key: FitH.self, value: g.size.height) })
                    Color.clear.frame(height: 1).id("end")
                }
            }
            .task {          // capture aid: -TrophyCardScroll 1 scrolls the list to its end (a screenshot cannot swipe)
                guard DevArgs.enabled, UserDefaults.standard.bool(forKey: "TrophyCardScroll") else { return }
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(nil) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .frame(height: max(10, min(h, maxHeight)))
        .onPreferenceChange(FitH.self) { h = $0 }
    }
}
private struct FitH: PreferenceKey { static var defaultValue: CGFloat = 0; static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) } }

/// The show-in-room switch, one text and one identifier in every look.
private struct ShelfSwitch: View {
    let care: GameCare
    var icon: Bool = true
    var size: CGFloat = 14
    var tint: Color = SK.sky
    var body: some View {
        Toggle(isOn: Binding(get: { care.race.trophies.caseVisible }, set: { care.setTrophyCase(visible: $0) })) {
            HStack(spacing: 8) {
                if icon { Image(systemName: care.race.trophies.caseVisible ? "eye.fill" : "eye.slash.fill").font(.system(size: size + 2, weight: .black)).foregroundStyle(TL.goldDeep).accessibilityHidden(true) }
                Text("Show trophy shelf in the room").font(SK.font(size, .black)).foregroundStyle(SK.ink)
            }
        }
        .tint(tint)
        .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.8)))
        .accessibilityIdentifier("trophy-case-toggle")
    }
}

private func countText(_ n: Int) -> String { n == 1 ? "1 trophy" : "\(n) trophies" }

private func rowLabel(_ care: GameCare, _ e: TrophyEntry) -> String { "\(e.item.event), \(care.trophyWinnerName(e.item)), \(e.item.dateLine)" }

// MARK: - the card

struct TrophyCardLook: View {
    let care: GameCare
    let style: TrophyCardStyle
    var compact: Bool
    var maxListHeight: CGFloat

    var body: some View {
        let entries = care.trophyEntries
        VStack(alignment: .leading, spacing: 10) {
            header(entries)
            ShelfSwitch(care: care, icon: style != .b, size: style == .b ? 13 : 14, tint: style == .a ? TL.goldDeep : SK.sky)
            if !entries.isEmpty {
                FitScroll(maxHeight: maxListHeight) {
                    switch style {
                    case .a: rich(entries)
                    case .b: grid(entries)
                    case .c: byJelmiko(entries)
                    }
                }
                .disabled(!care.race.trophies.caseVisible)
                .opacity(care.race.trophies.caseVisible ? 1 : 0.45)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 12, y: 4))
        .overlay(alignment: .top) { Capsule().fill(LinearGradient(colors: [TL.honey, TL.goldDeep], startPoint: .leading, endPoint: .trailing)).frame(width: 64, height: 5).padding(.top, 7).accessibilityHidden(true) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trophy-card")
        .accessibilityAction(.escape) { care.closeTrophyCard() }
    }

    // MARK: header

    @ViewBuilder private func header(_ entries: [TrophyEntry]) -> some View {
        let n = entries.count
        let winners = Set(entries.map { $0.item.character ?? -1 }).count
        HStack(spacing: 10) {
            if style == .a {
                ZStack {
                    Circle().fill(LinearGradient(colors: [TL.honey, TL.goldDeep], startPoint: .top, endPoint: .bottom))
                    Image(systemName: "trophy.fill").font(.system(size: 20, weight: .black)).foregroundStyle(TL.plateInk)
                }.frame(width: 42, height: 42).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Trophy Shelf").font(SK.font(style == .b ? 24 : 22, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                if style == .a { Text(n == 0 ? "No trophies yet" : countText(n)).font(SK.font(13, .bold)).foregroundStyle(SK.muted) }
                if style == .c { Text(n == 0 ? "No trophies yet" : "\(countText(n)) \u{00B7} \(winners == 1 ? "1 Jelmiko" : "\(winners) Jelmiko")").font(SK.font(13, .bold)).foregroundStyle(SK.muted) }
            }
            if style == .b && n > 0 {
                Text("\(n)").font(SK.font(15, .black)).foregroundStyle(TL.plateInk).padding(.horizontal, 10).frame(minHeight: 26)
                    .background(Capsule().fill(LinearGradient(colors: [TL.honey, TL.goldDeep], startPoint: .top, endPoint: .bottom)))
                    .accessibilityLabel(countText(n))
            }
            Spacer(minLength: 4)
            CloseX(care: care)
        }
    }

    // MARK: A

    private func rich(_ entries: [TrophyEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([TrophyKind.race, .show, .volley], id: \.self) { k in
                let rows = entries.filter { $0.kind == k }
                if !rows.isEmpty {
                    Text(TL.chipName(k)).font(SK.font(11, .black)).textCase(.uppercase).foregroundStyle(k == .volley ? TL.plateInk : TL.plateInk).tracking(0.6)
                        .padding(.horizontal, 10).frame(minHeight: 22).background(Capsule().fill(TL.chip(k).opacity(0.55)))
                        .padding(.top, k == .race ? 0 : 4).accessibilityAddTraits(.isHeader)
                    ForEach(rows) { richRow($0) }
                }
            }
        }
    }

    private func richRow(_ e: TrophyEntry) -> some View {
        Button { care.focusTrophy(e.id) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.white, TL.tint(e.kind).opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(e.ui, lineWidth: 3)
                    TrophyPic(e: e, size: 40)
                }.frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).font(SK.font(15, .black)).foregroundStyle(SK.ink).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(e.place) \u{00B7} \(e.item.dateLine)").font(SK.font(12, .bold)).foregroundStyle(SK.muted).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 2)
                VStack(spacing: 0) {
                    WinnerFace(care: care, item: e.item, size: 40)
                    Text(care.trophyWinnerName(e.item)).font(SK.font(10, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 52)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(SK.muted.opacity(0.55)).accessibilityHidden(true)
            }
            .padding(.horizontal, 10).padding(.vertical, 7).frame(minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.85)))
            .overlay(alignment: .leading) { Capsule().fill(e.ui).frame(width: 4).padding(.vertical, 14).padding(.leading, 2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowLabel(care, e)).accessibilityHint("Looks at the trophy")
        .accessibilityIdentifier("trophy-row-\(e.id)")
    }

    // MARK: B

    private func grid(_ entries: [TrophyEntry]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(entries) { e in
                Button { care.focusTrophy(e.id) } label: {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            TrophyPic(e: e, size: 66)
                            Capsule().fill(LinearGradient(colors: [TL.woodTop, TL.woodFront], startPoint: .top, endPoint: .bottom)).frame(height: 7).padding(.horizontal, 4)
                                .shadow(color: SK.shadow.opacity(0.25), radius: 1.5, y: 1.5)
                            Text(e.caption).font(SK.font(12, .black)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center).padding(.top, 5)
                                .frame(minHeight: 30)
                        }
                        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
                        WinnerFace(care: care, item: e.item, size: 30).padding(3)
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 132)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [TL.tint(e.kind).opacity(0.7), TL.tint(e.kind).opacity(0.32)], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowLabel(care, e)).accessibilityHint("Looks at the trophy")
                .accessibilityIdentifier("trophy-row-\(e.id)")
            }
        }
    }

    // MARK: C

    private func byJelmiko(_ entries: [TrophyEntry]) -> some View {
        let groups = Dictionary(grouping: entries) { $0.item.character ?? -1 }
            .map { (who: $0.key, rows: $0.value) }
            .sorted { ($0.rows.count, -$0.who) > ($1.rows.count, -$1.who) }
        let blockTints = [SK.honey, SK.pink, SK.mint, SK.sky]
        return VStack(spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.who) { (i, g) in
                let first = g.rows[0].item
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        WinnerFace(care: care, item: first, size: 52)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(care.trophyWinnerName(first)).font(SK.font(19, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                            Text(countText(g.rows.count)).font(SK.font(13, .bold)).foregroundStyle(SK.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(g.rows) { chipView($0) } }.padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(blockTints[i % blockTints.count].opacity(0.30)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func chipView(_ e: TrophyEntry) -> some View {
        Button { care.focusTrophy(e.id) } label: {
            VStack(spacing: 3) {
                TrophyPic(e: e, size: 50).frame(width: 66, height: 60)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [.white, TL.tint(e.kind).opacity(0.55)], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(e.ui, lineWidth: 2.5))
                Text(e.caption.replacingOccurrences(of: " \u{00B7} ", with: "\n")).font(SK.font(10, .heavy)).foregroundStyle(SK.ink).lineLimit(2).multilineTextAlignment(.center).frame(width: 68, height: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowLabel(care, e)).accessibilityHint("Looks at the trophy")
        .accessibilityIdentifier("trophy-row-\(e.id)")
    }
}

extension TrophyKind: Hashable {}
