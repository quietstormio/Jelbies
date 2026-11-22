//
//  TrophyShelfCard.swift
//  The Trophy Shelf card (double tap the shelf on the wall; the owner picked this "grid" look from three): a title with the trophy count, the show-in-room switch,
//  and a three-column grid of tiles. Each tile = a trophy standing on a little wooden shelf line (a real mini render of the trophy's own mesh, in its real
//  colour), a short caption, the date text the engraved plate uses, and the winner's small face in the corner. Tap a tile to look at the trophy (the camera
//  eases in, the gold outline and the engraved plate appear: Trophies/TrophyCase.swift).
//
//  Portrait: sits above the left button column. Landscape: a wider card at the right, clear of the coin pill and the paw button's column.
//  VoiceOver: each tile reads "event, winner, date". Dynamic Type: two columns at the accessibility sizes, captions wrap / shrink.
//

import SwiftUI
import UIKit
import simd

// MARK: - what a trophy looks like on a tile

enum TrophyKind { case race, show, volley }

struct TrophyEntry: Identifiable {
    var item: TrophyShelfItem
    var id: String { item.id }
    var kind: TrophyKind
    var caption: String        // "Puddle · 1st"
    var ui: Color              // the trophy's metal / court tint
    var mesh: SIMD3<Float>     // the same, for the mini render
    var placeNumber: Int

    private static func ord(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : "3rd" }
    private static let goldS = SIMD3<Float>(0.97, 0.78, 0.26), silverS = SIMD3<Float>(0.84, 0.87, 0.92), bronzeS = SIMD3<Float>(0.80, 0.52, 0.32)
    private static func metal(_ p: Int) -> SIMD3<Float> { p == 1 ? goldS : p == 2 ? silverS : bronzeS }
    private static let volleyS: [SIMD3<Float>] = [SIMD3(0.93, 0.78, 0.48), SIMD3(0.40, 0.78, 0.84), SIMD3(0.95, 0.52, 0.46), SIMD3(0.32, 0.50, 0.90)]

    /// The colour to hand the mini render so it SHOWS the wall's metal: StoreThumb lights its vertex colours as linear light (it applies a 1/2.2 power to a mesh's colours
    /// and SceneKit then encodes the lit result for the screen), so a wall colour passed as is comes out pale and khaki. Handing it the colour's linear value raised to 2.2 shows it true.
    static func renderColour(_ srgb: SIMD3<Float>) -> SIMD3<Float> {
        let lin = RaceModels.srgb(srgb.x, srgb.y, srgb.z)
        return SIMD3(powf(lin.x, 2.2), powf(lin.y, 2.2), powf(lin.z, 2.2))
    }

    static func make(_ it: TrophyShelfItem, spec: TrophyShelfSpec) -> TrophyEntry {
        var kind = TrophyKind.race, caption = it.event, rgb = goldS, n = 1
        if it.id.hasPrefix("cup."), let t = CourseTier(rawValue: String(it.id.dropFirst(4))), let k = CourseTier.allCases.firstIndex(of: t) {
            n = Int(spec.cups[k]); rgb = metal(n); caption = "\(t.title) \u{00B7} \(ord(n))"
        } else if it.id == "contest" {
            kind = .show; n = Int(spec.contest); rgb = metal(n); caption = "Show \u{00B7} \(ord(n))"
        } else if let k = ["wins5", "wins10", "wins25"].firstIndex(of: it.id) {
            rgb = [bronzeS, silverS, goldS][k]; caption = "\([5, 10, 25][k]) wins"
        } else if it.id == "champion" {
            caption = "Champion"
        } else if it.id.hasPrefix("volley."), let t = VolleyTier(rawValue: String(it.id.dropFirst(7))), let k = VolleyTier.allCases.firstIndex(of: t) {
            kind = .volley; rgb = volleyS[min(k, 3)]; caption = "\(t.title) \u{00B7} 1st"
        }
        return TrophyEntry(item: it, kind: kind, caption: caption, ui: Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)),
                           mesh: Self.renderColour(rgb), placeNumber: n)
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
    /// Tile backgrounds: cool for races, lilac for the Show, honey for volleyball, so a gold or silver cup stands out.
    static func tint(_ k: TrophyKind) -> Color { k == .race ? SK.sky : k == .show ? ShowUI.lilacPale : SK.honey }
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

// MARK: - the card

struct TrophyShelfCard: View {
    let care: GameCare
    var compact: Bool          // landscape (compact height)
    var maxListHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let entries = care.trophyEntries
        let big = typeSize.isAccessibilitySize, inline = compact && !big          // (landscape: the switch sits beside the title, so more of the grid shows)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Trophy Shelf").font(SK.font(24, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.6).accessibilityAddTraits(.isHeader)
                if !entries.isEmpty {
                    Text("\(entries.count)").font(SK.font(15, .black)).foregroundStyle(TL.plateInk).padding(.horizontal, 10).frame(minHeight: 26)
                        .background(Capsule().fill(LinearGradient(colors: [TL.honey, TL.goldDeep], startPoint: .top, endPoint: .bottom)))
                        .accessibilityLabel(entries.count == 1 ? "1 trophy" : "\(entries.count) trophies")
                }
                if inline { shelfSwitch }
                Spacer(minLength: 4)
                Button { care.closeTrophyCard() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85)))
                }.buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("trophy-card-close")
            }
            if !inline { shelfSwitch }
            if !entries.isEmpty {
                FitScroll(maxHeight: big ? maxListHeight - 110 : maxListHeight) { grid(entries, big: big) }
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

    private var shelfSwitch: some View {
        Toggle(isOn: Binding(get: { care.race.trophies.caseVisible }, set: { care.setTrophyCase(visible: $0) })) {
            Text("Show trophy shelf in the room").font(SK.font(13, .black)).foregroundStyle(SK.ink).lineLimit(compact && !typeSize.isAccessibilitySize ? 1 : nil).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
        }
        .tint(SK.sky)
        .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.8)))
        .accessibilityIdentifier("trophy-case-toggle")
    }

    @ViewBuilder private func grid(_ entries: [TrophyEntry], big: Bool) -> some View {
        let cols = big ? 2 : compact ? 4 : 3
        if entries.count < cols {          // one or two trophies: centred, not lost in a corner
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(entries) { tile($0, big: big).frame(width: 118) }
                Spacer(minLength: 0)
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                ForEach(entries) { tile($0, big: big) }
            }
        }
    }

    private func tile(_ e: TrophyEntry, big: Bool) -> some View {
        let pic: CGFloat = compact ? 46 : 64, face: CGFloat = compact ? 26 : 30
        return Button { care.focusTrophy(e.id) } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    TrophyPic(e: e, size: pic)
                    Capsule().fill(LinearGradient(colors: [TL.woodTop, TL.woodFront], startPoint: .top, endPoint: .bottom)).frame(height: 7).padding(.horizontal, 4)
                        .shadow(color: SK.shadow.opacity(0.25), radius: 1.5, y: 1.5)
                    Text(e.caption).font(SK.font(12, .black)).foregroundStyle(SK.ink).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center).padding(.top, 5)
                        .frame(minHeight: compact ? 16 : 30, alignment: .top)
                    Text(e.item.dateLine).font(SK.font(10, .bold)).foregroundStyle(SK.muted).lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
                        .frame(minHeight: 26, alignment: .top)
                }
                .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
                WinnerFace(care: care, item: e.item, size: face).padding(3)
            }
            .frame(maxWidth: .infinity).frame(minHeight: compact ? 120 : 152)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [TL.tint(e.kind).opacity(0.7), TL.tint(e.kind).opacity(0.32)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.item.event), \(care.trophyWinnerName(e.item)), \(e.item.dateLine)").accessibilityHint("Looks at the trophy")
        .accessibilityIdentifier("trophy-row-\(e.id)")
    }
}
