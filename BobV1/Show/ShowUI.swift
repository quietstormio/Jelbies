//
//  ShowUI.swift
//  The Jelly Show's places (the approved mockups Studio.dc.html, Condition.dc.html, Show.dc.html), reached from the Town:
//    StudioScreen      the stage card with the Jelbie and his slot chips, the Show-ready bars, Dress up / Practise dance / Enter Jelly Show.
//    ConditionScreen   the "Jelly Jars": five jars of stat-coloured jelly with numbers, a gold next-rank line, a +1 droplet on jars that just
//                      grew, the Glow pill with a Bath button, Food diary and Trophies as row buttons, "See today's Jelly Show".
//    ShowLobby         today's theme poster and tomorrow's teaser, the rank picker with locks, the three rivals, the prizes, the Ready check, Start show.
//  Plus the shared pieces: the Jelbie portrait, the stat chip, the wardrobe sheet (owned wearables, tap to wear), the dance picker.
//  Everything lays out both ways: portrait stacks, a phone on its side puts the stage / poster beside the cards.
//

import SwiftUI

// MARK: - palette and small pieces

enum ShowUI {
    static let hall = Color(hex: 0x3B2E4F), stage = Color(hex: 0x4E3D68), platform = Color(hex: 0x6B5487), curtain = Color(hex: 0xC25A78)
    static let light = Color(hex: 0xFFF3C9), gold = Color(hex: 0xFFE07A), goldDeep = Color(hex: 0xF2B530), lilac = Color(hex: 0x9C8AB5), lilacPale = Color(hex: 0xCDBFE0), mist = Color(hex: 0xE2D6F0)
    static let sand = Color(hex: 0xEADFC8), bar = DT.fill, brownGold = Color(hex: 0x6B4A00), goldText = Color(hex: 0x8A6A12)
    static func tag(_ t: WearTag) -> Color { Color(hex: t.hex) }
    static func ordinal(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : p == 3 ? "3rd" : "\(p)th" }
    /// A stat 0...1 as the jar's number (0...100).
    static func pts(_ v: Float) -> Int { Int((min(max(v, 0), 1) * 100).rounded()) }
    static func glowOf5(_ g: Float) -> Int { Int((min(max(g, 0), 1) * 5).rounded()) }
    /// The next rank's rivals reach about here in their main stat (the gold dashed line on the jars).
    static func target(after unlocked: [ShowRank]) -> (rank: ShowRank, level: Float)? {
        guard let next = ShowRank.allCases.first(where: { !unlocked.contains($0) }) else { return nil }
        return (next, ShowRivalSource.base(next).main)
    }
    static let weekday: [String] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    /// "Tuesday's theme" for a day key.
    static func dayName(_ dayKey: Int) -> String { weekday[((ShowSchedule.dayOrdinal(dayKey) + 4) % 7 + 7) % 7] }
}

/// A round dark card header: back, a title (cream on the dark hall) and a trailing view.
struct ShowHeader<Trailing: View>: View {
    var title: String
    var kicker: String? = nil
    var light = true
    var backID: String
    var back: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 10) {
            Button { AudioHub.shared.uiTap(); back() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(SK.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(DT.card))
            }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier(backID)
            VStack(alignment: .leading, spacing: 0) {
                if let k = kicker { Text(k).font(SK.font(12, .semibold)).foregroundStyle(ShowUI.gold).tracking(0.5) }
                Text(title).font(SK.font(24, .semibold)).foregroundStyle(light ? SK.cream : SK.ink).jLine(1, scale: 0.7)
            }
            Spacer(minLength: 4)
            trailing()
        }
    }
}

/// The Jelbie as he is now, rendered by the game (a static picture; the stage is paused behind the Town).
struct JelbiePortrait: View {
    let care: GameCare
    var who: Int
    var size: CGFloat
    var border: Color = ShowUI.light
    @State private var image: UIImage?
    @State private var tried = false
    var body: some View {
        ZStack {
            Circle().fill(ShowUI.platform)
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle()) }
            else if tried { Circle().fill(Color(red: Double(JellyRoster.tint(care.jelly(who)?.character ?? who).x), green: Double(JellyRoster.tint(care.jelly(who)?.character ?? who).y), blue: Double(JellyRoster.tint(care.jelly(who)?.character ?? who).z))).padding(size * 0.2) }
            else { ProgressView().tint(.white) }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(border, lineWidth: 4))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .accessibilityLabel("\(care.jelly(who)?.name ?? "Jelbie")")
        .accessibilityIdentifier("jelbie-portrait")
        .task(id: "\(who)-\(care.store.revision)") {
            image = nil; tried = false
            try? await Task.sleep(nanoseconds: 350_000_000)
            for _ in 0..<40 {
                await Task.yield()
                if let img = care.portraitProvider?(who) { image = img; return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
            }
            tried = true
        }
    }
}

/// A rival as the mockups draw her: a blob silhouette in her colour with a highlight.
struct RivalBlob: View {
    var tint: SIMD3<Float>
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Ellipse().fill(Color(red: Double(tint.x), green: Double(tint.y), blue: Double(tint.z))).frame(width: size, height: size * 0.92)
            Ellipse().fill(.white.opacity(0.5)).frame(width: size * 0.22, height: size * 0.12).rotationEffect(.degrees(-25)).offset(x: -size * 0.16, y: -size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A stat chip ("Sparkly") in the stat's colour.
struct TagChip: View {
    var tag: WearTag
    var prefix = ""
    var size: CGFloat = 13
    var body: some View {
        Text(prefix + tag.title).font(SK.font(size, .semibold)).foregroundStyle(SK.ink)
            .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(ShowUI.tag(tag)))
    }
}

/// A horizontal bar with a name, a fill and a note.
struct ShowBar: View {
    var name: String
    var value: Float
    var color: Color
    var note: String = ""
    var score: Int? = nil
    var nameWidth: CGFloat = 56
    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(SK.font(15, .semibold)).foregroundStyle(SK.ink).frame(width: nameWidth, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(ShowUI.bar)
                    Capsule().fill(color).frame(width: max(6, g.size.width * CGFloat(min(max(value, 0), 1))))
                }
            }.frame(height: 12)
            if let score { Text("\(score)").font(SK.font(15, .semibold)).foregroundStyle(SK.ink).monospacedDigit().frame(width: 30, alignment: .trailing) }
            if !note.isEmpty { Text(note).font(SK.font(11, .semibold)).foregroundStyle(SK.muted).frame(width: 104, alignment: .leading).jLine(2, scale: 0.8) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(score.map { "\($0)" } ?? "\(Int((value * 100).rounded()))"). \(note)")
    }
}

/// The big yellow call-to-action.
struct ShowCTA: View {
    var title: String
    var symbol: String? = nil
    var enabled = true
    var id: String
    var height: CGFloat = 60
    var action: () -> Void
    var body: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); action() } label: {
            HStack(spacing: 8) {
                if let s = symbol { Image(systemName: s).font(.system(size: 20, weight: .semibold)) }
                Text(title).font(SK.font(20, .semibold)).jLine(1, scale: 0.7)
            }
            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(enabled ? ShowUI.gold : SK.muted.opacity(0.4)))
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier(id)
    }
}

// MARK: - the wardrobe sheet (Dress up / the Look round's wardrobe)

/// Owned wearables as tap-to-wear cards, the theme's matches edged in gold. One card per look; the worn one of a slot is marked.
struct WardrobeStrip: View {
    let care: GameCare
    var who: Int
    var theme: ShowTheme
    var slots: [WearSlot]? = nil          // nil = every slot
    var onChange: () -> Void = {}
    private var looks: [WearLook] {
        StoreCatalog.items.filter { $0.isWearable && care.store.owns($0) }.compactMap(\.wear).filter { slots?.contains($0.slot) ?? true }
            .sorted { theme.match($0.tags) > theme.match($1.tags) }
    }
    var body: some View {
        let list = looks
        if list.isEmpty {
            Text("Nothing to wear yet. The Shop has hats, bows and shoes.").font(SK.font(13, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, minHeight: 60)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(list, id: \.rawValue) { look in
                        let worn = care.store.worn(who, look.slot) == look
                        let other = worn ? nil : care.store.wearer(look, among: care.jellies.count).flatMap { $0 != who ? care.jelly($0)?.name : nil }
                        let m = theme.match(look.tags)
                        Button {
                            AudioHub.shared.play(.shoeOn)
                            if worn { care.store.takeOff(look.slot, from: who) } else if care.store.wear(look, on: who) { care.jelly(who)?.stats.nudge([.cool: 0.02]) }
                            onChange()
                        } label: {
                            VStack(spacing: 3) {
                                if let item = StoreCatalog.item(wearing: look) { ItemArt(item: item, size: 34) } else { Image(systemName: look.slot.symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(SK.ink) }
                                Text(look.title).font(SK.font(11, .semibold)).foregroundStyle(SK.ink).jLine(1, scale: 0.7)
                                if let t = look.tags.first(where: { $0 == theme.main }) ?? look.tags.first(where: { $0 == theme.friend }) ?? look.tags.first { TagChip(tag: t, size: 10) }
                                Text(worn ? "Wearing" : other.map { "On \($0)" } ?? look.slot.title).font(SK.font(10, .semibold)).foregroundStyle(worn ? ShowUI.brownGold : SK.muted).jLine(1, scale: 0.7)
                            }
                            .padding(.horizontal, 4).frame(width: 78, height: 102)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(worn ? ShowUI.gold.opacity(0.35) : .white))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(m >= 1 ? ShowUI.gold : m >= 0.5 ? Color(hex: 0xF4D98C) : ShowUI.bar, lineWidth: 2))
                            .shadow(color: ShowUI.gold.opacity(m >= 1 ? 0.9 : m >= 0.5 ? 0.45 : 0), radius: m >= 1 ? 8 : 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(look.title), \(look.tags.map(\.title).joined(separator: " ")), \(worn ? "worn" : "not worn")\(other.map { ", worn by \($0)" } ?? "")")
                        .accessibilityIdentifier("wardrobe-\(look.rawValue)")
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 6)
            }
        }
    }
}

/// The slot chips round the Jelbie: what he wears in each scored slot (gold edge = matches the theme's main stat, half gold = the friend).
struct SlotChip: View {
    var slot: WearSlot
    var look: WearLook?
    var theme: ShowTheme
    var caption = true
    var action: (() -> Void)? = nil
    var body: some View {
        let m = look.map { theme.match($0.tags) } ?? 0
        VStack(spacing: 2) {
            Button { AudioHub.shared.uiTap(); action?() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(look == nil ? Color.clear : SK.cream)
                    if look == nil { Text("+").font(SK.font(22, .semibold)).foregroundStyle(ShowUI.lilacPale) }
                    else if let l = look, let item = StoreCatalog.item(wearing: l) { ItemArt(item: item, size: 32) }
                    else { Image(systemName: slot.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(SK.ink) }
                }
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(look == nil ? ShowUI.lilac : m >= 1 ? ShowUI.gold : m >= 0.5 ? Color(hex: 0xF4D98C) : ShowUI.lilac, style: StrokeStyle(lineWidth: 2, dash: look == nil ? [5, 4] : [])))
                .shadow(color: ShowUI.gold.opacity(m >= 1 ? 0.85 : m >= 0.5 ? 0.45 : 0), radius: m >= 1 ? 9 : 5)
            }
            .buttonStyle(.plain).disabled(action == nil)
            if caption { Text(slot.title.replacingOccurrences(of: "Faces", with: "Face").replacingOccurrences(of: "Hats", with: "Head").replacingOccurrences(of: "Shoes", with: "Feet").replacingOccurrences(of: "Necks", with: "Neck").replacingOccurrences(of: "Bodies", with: "Body")).font(SK.font(11, .semibold)).foregroundStyle(m >= 1 ? ShowUI.gold : ShowUI.mist) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.title) slot: \(look?.title ?? "empty")\(m >= 1 ? ", matches \(theme.main.title)" : m >= 0.5 ? ", matches friend stat \(theme.friend.title)" : "")")
        .accessibilityIdentifier("slot-\(slot.rawValue)")
    }
}

// MARK: - Studio

struct StudioScreen: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var card: () -> Void
    var show: () -> Void
    var practise: (DanceID) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @State private var wardrobeOpen = false
    @State private var danceOpen = false
    private var compact: Bool { vsc == .compact }
    private var day: Int { GameCare.showDay }
    private var theme: ShowTheme { ShowSchedule.theme(dayKey: day) }
    private var rank: ShowRank { care.show.progress.chosen }

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            ShowHeader(title: "Studio", backID: "studio-back", back: back) { DropsPill(wallet: care.bath.wallet) }
            if compact {
                HStack(alignment: .top, spacing: 12) {
                    stageCard.frame(maxWidth: .infinity)
                    VStack(spacing: 10) { readyCard; buttons }.frame(maxWidth: .infinity)
                }
            } else {
                stageCard.frame(height: 300)
                readyCard
                Spacer(minLength: 0)
                buttons
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(ShowUI.hall.ignoresSafeArea())
        .accessibilityIdentifier("studio-screen")
        .sheet(isPresented: $wardrobeOpen) {
            WardrobeSheet(care: care, who: who, theme: theme, rank: rank) { wardrobeOpen = false }
                .presentationDetents(compact ? [.large] : [.medium, .large]).presentationBackground(SK.cream)
        }
        .sheet(isPresented: $danceOpen) {
            DancePicker(care: care, who: who) { danceOpen = false; practise($0) } close: { danceOpen = false }
                .presentationDetents(compact ? [.large] : [.medium]).presentationBackground(SK.cream)
        }
    }

    /// The stage card: the Jelbie under a spotlight, the day's theme, his slot chips either side.
    private var stageCard: some View {
        let outfit = care.store.outfit(who)
        let slots = rank.slotOrder
        let left = Array(slots.prefix((slots.count + 1) / 2)), right = Array(slots.dropFirst((slots.count + 1) / 2))
        return ZStack {
            StageBackdrop()
            HStack(spacing: 0) {
                VStack(spacing: 10) { ForEach(left, id: \.rawValue) { s in SlotChip(slot: s, look: outfit[s], theme: theme, caption: false) { wardrobeOpen = true } } }.frame(width: 56)
                Spacer(minLength: 0)
                JelbiePortrait(care: care, who: who, size: compact ? 118 : 140)
                Spacer(minLength: 0)
                VStack(spacing: 10) { ForEach(right, id: \.rawValue) { s in SlotChip(slot: s, look: outfit[s], theme: theme, caption: false) { wardrobeOpen = true } } }.frame(width: 56)
            }
            .padding(.horizontal, 16)
            VStack {
                Text("\(ShowUI.dayName(day))'s theme: \(theme.main.title)").font(SK.font(14, .semibold)).foregroundStyle(ShowUI.brownGold).jLine(1, scale: 0.7)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(ShowUI.light))
                    .accessibilityIdentifier("studio-theme")
                Spacer()
                HStack(alignment: .bottom) {
                    Text("Gold edge = matches \(theme.main.title)").font(SK.font(13, .semibold)).foregroundStyle(ShowUI.gold).jLine(1, scale: 0.7)
                    if care.jellies.count > 1 { Spacer(minLength: 6); whoChips }
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 230 : 300)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain).accessibilityIdentifier("studio-stage")
    }

    private var whoChips: some View {
        HStack(spacing: 6) {
            ForEach(care.jellies, id: \.id) { j in
                let t = JellyRoster.tint(j.character)
                Button { AudioHub.shared.uiTap(); who = j.id } label: {
                    Circle().fill(Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))).frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(who == j.id ? ShowUI.gold : .white.opacity(0.6), lineWidth: who == j.id ? 3 : 1.5))
                }
                .buttonStyle(.plain).accessibilityLabel(j.name).accessibilityIdentifier("studio-who-\(j.id)").accessibilityAddTraits(who == j.id ? .isSelected : [])
            }
        }
        .padding(6).background(Capsule().fill(.black.opacity(0.25)))
    }

    /// "Show ready": Look / Shine / Diet / Dance, each with a word on what to do.
    private var readyCard: some View {
        let p = care.jelly(who)
        let outfit = care.store.outfit(who)
        let worn = rank.slotOrder.compactMap { outfit[$0] }
        let match = worn.filter { theme.match($0.tags) >= 1 }.count
        let sum = worn.reduce(0) { $0 + theme.match($1.tags) }
        let glow = p?.grime.sparkle ?? 0
        let main = p?.stats.condition(theme.main.condition) ?? 0, friend = p?.stats.condition(theme.friend.condition) ?? 0
        let dances = p?.stats.knownDances.count ?? 0
        let skill = p?.stats.bestDance.map { p!.stats.proficiency($0) } ?? 0
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Show ready").font(SK.font(17, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Button { AudioHub.shared.uiTap(); card() } label: { Text("\(p?.name ?? "Bob")'s card \u{203A}").font(SK.font(14, .semibold)).foregroundStyle(SK.muted).frame(minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("studio-card")
            }
            ShowBar(name: "Look", value: min(1, sum / Float(rank.slots)), color: SK.pink, note: "\(match) of \(rank.slots) match theme", nameWidth: 64)
            ShowBar(name: "Shine", value: glow, color: SK.sky, note: glow > 0.8 ? "Bathed recently" : glow > 0.3 ? "Glow \(ShowUI.glowOf5(glow)) of 5" : "A Clean would help", nameWidth: 64)
            ShowBar(name: "Diet", value: 0.7 * main + 0.3 * friend, color: SK.mint, note: "\(theme.main.title) \(ShowUI.pts(main)) \u{00B7} \(theme.friend.title) \(ShowUI.pts(friend))", nameWidth: 64)
            ShowBar(name: "Dance", value: skill, color: Color(hex: 0xB58BDB), note: dances == 0 ? "No dance yet" : "\(dances) dance\(dances == 1 ? "" : "s") learned", nameWidth: 64)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DT.card))
        .accessibilityElement(children: .contain).accessibilityIdentifier("studio-ready")
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                pill("Dress up", id: "studio-dress") { wardrobeOpen = true }
                pill("Practise dance", id: "studio-dance") { danceOpen = true }
            }
            ShowCTA(title: "Enter Jelly Show \u{00B7} \(rank.title) rank", enabled: care.showBlocker(jelly: who) == nil, id: "studio-show") { show() }
            if let why = care.showBlocker(jelly: who) { Text(why).font(SK.font(12, .bold)).foregroundStyle(ShowUI.lilacPale) }
        }
    }
    private func pill(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            Text(title).font(SK.font(17, .semibold)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 54).background(Capsule().fill(DT.card))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

/// The stage as a flat picture (the cards' backdrop): a spotlight cone, the platform, two curtains and a few stars.
struct StageBackdrop: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                ShowUI.stage
                Path { p in p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w * 0.22, y: h)); p.addLine(to: CGPoint(x: w * 0.78, y: h)); p.closeSubpath() }.fill(ShowUI.light.opacity(0.16))
                Ellipse().fill(ShowUI.platform).frame(width: w * 0.67, height: h * 0.16).position(x: w / 2, y: h * 0.87)
                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: w * 0.14, y: 0)); p.addCurve(to: CGPoint(x: w * 0.14, y: h), control1: CGPoint(x: w * 0.12, y: h * 0.2), control2: CGPoint(x: w * 0.12, y: h * 0.67)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath() }.fill(ShowUI.curtain)
                Path { p in p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w * 0.86, y: 0)); p.addCurve(to: CGPoint(x: w * 0.86, y: h), control1: CGPoint(x: w * 0.88, y: h * 0.2), control2: CGPoint(x: w * 0.88, y: h * 0.67)); p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath() }.fill(ShowUI.curtain)
                ForEach(Array([(0.2, 0.13, 2.0), (0.81, 0.2, 2.5), (0.7, 0.09, 1.8), (0.32, 0.28, 1.6)].enumerated()), id: \.offset) { _, s in
                    Circle().fill(ShowUI.light).frame(width: s.2 * 1.6, height: s.2 * 1.6).position(x: w * s.0, y: h * s.1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Dress up: the whole owned wardrobe by slot (the scored slots first), tap to wear / take off. The Studio's and the Look round's.
struct WardrobeSheet: View {
    let care: GameCare
    var who: Int
    var theme: ShowTheme
    var rank: ShowRank
    var close: () -> Void
    @State private var slot: WearSlot?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Dress up").font(SK.font(26, .semibold)).foregroundStyle(SK.ink)
                    Spacer()
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                        .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("wardrobe-close")
                }
                HStack(spacing: 6) {
                    Text("\(theme.title):").font(SK.font(13, .semibold)).foregroundStyle(SK.muted)
                    TagChip(tag: theme.main); TagChip(tag: theme.friend, prefix: "+ friend: ")
                    Spacer()
                }
                Text("\(rank.title) rank scores \(rank.slots) slots: \(rank.slotOrder.map { $0.title }.joined(separator: ", ")). Gold = matches \(theme.main.title).").font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                SlotChips(slot: $slot, slots: WearSlot.allCases.filter { s in StoreCatalog.items.contains { $0.wear?.slot == s && care.store.owns($0) } }, idPrefix: "wardrobe-slot-")
                WardrobeStrip(care: care, who: who, theme: theme, slots: slot.map { [$0] })
                let outfit = care.store.outfit(who)
                HStack(spacing: 10) {
                    ForEach(rank.slotOrder, id: \.rawValue) { s in SlotChip(slot: s, look: outfit[s], theme: theme) { if let l = outfit[s] { care.store.takeOff(l.slot, from: who) } } }
                    Spacer()
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ShowUI.stage))
                Text("Tap a worn slot to take it off.").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("wardrobe-sheet")
    }
}

/// Practise dance: the dances, which are open, how well he knows each; tap one to start the drill.
struct DancePicker: View {
    let care: GameCare
    var who: Int
    var start: (DanceID) -> Void
    var close: () -> Void
    var body: some View {
        let st = care.jelly(who)?.stats
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Practise dance").font(SK.font(26, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                    .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("dance-close")
            }
            Text("Tap the feet on the beat of the studio music. Dance skill is 30% of the Dance round.").font(SK.font(13, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(DanceID.allCases, id: \.rawValue) { d in
                let open = st?.danceOpen(d) ?? (d == .sway), skill = st?.proficiency(d) ?? 0
                Button { if open { start(d) } else { AudioHub.shared.play(.notEnough) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: open ? "music.note" : "lock.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(SK.ink)
                            .frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(open ? Color(hex: 0xB58BDB) : SK.muted.opacity(0.3)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.title).font(SK.font(18, .semibold)).foregroundStyle(SK.ink)
                            Text(open ? d.blurb : "Opens when \(d.opensAfter?.dance.title ?? "") is half learned").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
                            GeometryReader { g in
                                ZStack(alignment: .leading) { Capsule().fill(ShowUI.bar); Capsule().fill(Color(hex: 0xB58BDB)).frame(width: max(4, g.size.width * CGFloat(skill))) }
                            }.frame(height: 8)
                        }
                        Text(skill > 0 ? "\(ShowUI.pts(skill))%" : "new").font(SK.font(15, .semibold)).foregroundStyle(SK.ink).monospacedDigit()
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(open ? 0.85 : 0.5)))
                }
                .buttonStyle(.plain).accessibilityIdentifier("dance-\(d.rawValue)").accessibilityLabel("\(d.title), \(open ? "\(ShowUI.pts(skill)) percent" : "locked")")
            }
            if let st { Text("Pep left today: \(st.pepLeft) of \(TrainingTuning.fullSessions). Practice after that still helps, just less.").font(SK.font(11, .bold)).foregroundStyle(SK.muted) }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityIdentifier("dance-picker")
    }
}

// MARK: - Condition (the Jelly Jars)

struct ConditionScreen: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var show: () -> Void
    var bath: (() -> Void)? = nil
    @Environment(\.verticalSizeClass) private var vsc
    @State private var diaryOpen = false
    @State private var trophiesOpen = false
    /// The jars fill from 0 to their level over 0.6 s when the card appears (and from the previous level after a meal).
    @State private var grown = false
    private var compact: Bool { vsc == .compact }

    var body: some View {
        let p = care.jelly(who)
        VStack(spacing: compact ? 8 : 12) {
            ShowHeader(title: "Condition", light: false, backID: "condition-back", back: back) { EmptyView() }
            if care.jellies.count > 1 { WhoRow(care: care, who: $who) }
            if compact {
                HStack(alignment: .top, spacing: 12) {
                    jars(p).frame(maxWidth: .infinity)
                    VStack(spacing: 10) {
                        rows(p)
                        Spacer(minLength: 0)
                        ShowCTA(title: "See today's Jelly Show", id: "condition-show", height: 54) { show() }
                    }
                    .frame(width: 300)
                }
            } else {
                jars(p)
                rows(p)
                Spacer(minLength: 0)
                ShowCTA(title: "See today's Jelly Show", id: "condition-show", height: 56) { show() }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(ShowUI.sand.ignoresSafeArea())
        .accessibilityIdentifier("condition-screen")
        .onAppear { grown = false; withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.15)) { grown = true } }
        .onChange(of: who) { _, _ in grown = false; withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.1)) { grown = true } }
        .sheet(isPresented: $diaryOpen) { FoodDiarySheet(care: care, who: who) { diaryOpen = false }.presentationDetents([.medium, .large]).presentationBackground(SK.cream) }
        .sheet(isPresented: $trophiesOpen) { TrophiesSheet(care: care, who: who) { trophiesOpen = false }.presentationDetents([.medium, .large]).presentationBackground(SK.cream) }
    }

    /// The last meal within half an hour: what it raised ("+1" droplets) and its name ("Just fed").
    private func lastMeal(_ p: JellyProfile?) -> MealEntry? {
        guard let m = p?.stats.meals.first, Date().timeIntervalSince(m.date) < 1800 else { return nil }
        return m
    }

    private func jars(_ p: JellyProfile?) -> some View {
        let name = p?.name ?? "Bob"
        let meal = lastMeal(p)
        let glow = p?.grime.sparkle ?? 0
        let levels = WearTag.jarOrder.map { p?.stats.condition($0.condition) ?? 0 }
        let strongest = WearTag.jarOrder[levels.indices.max { levels[$0] < levels[$1] } ?? 0], weakest = WearTag.jarOrder[levels.indices.min { levels[$0] < levels[$1] } ?? 0]
        let target = ShowUI.target(after: care.show.progress.unlockedRanks)
        return VStack(spacing: 8) {
            HStack {
                Text("\(name)'s jelly jars").font(SK.font(18, .semibold)).foregroundStyle(SK.ink)
                Spacer()
            }
            HStack {
                if let meal { Text("Just fed: \(meal.food)").font(SK.font(13, .semibold)).foregroundStyle(ShowUI.brownGold).padding(.horizontal, 12).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xFFE7A8))).accessibilityIdentifier("condition-fed") }
                Spacer()
                Button { AudioHub.shared.uiTap(); bath?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(SK.skyDeep)
                        Text("Glow \(ShowUI.glowOf5(glow))/5").font(SK.font(14, .semibold)).foregroundStyle(Color(hex: 0x2F6F8C))
                        Text("Bath").font(SK.font(12, .semibold)).foregroundStyle(Color(hex: 0x2F6F8C)).padding(.horizontal, 10).frame(height: 28).background(Capsule().fill(.white))
                    }
                    .padding(.leading, 12).padding(.trailing, 6).frame(height: 44).background(Capsule().fill(Color(hex: 0xDDEFF6)))
                }
                .buttonStyle(.plain).disabled(bath == nil || !care.canClean(jelly: who))
                .accessibilityLabel("Glow \(ShowUI.glowOf5(glow)) of 5. Tap to bathe").accessibilityIdentifier("condition-glow")
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(WearTag.jarOrder.enumerated()), id: \.offset) { i, t in
                    let v = levels[i]
                    let gain = meal?.gains[t.condition.rawValue] ?? 0
                    JellyJar(tag: t, level: grown ? v : max(0, v - gain), previous: max(0, v - gain), grew: gain > 0.004 && grown, target: target?.level, number: ShowUI.pts(v))
                        .accessibilityIdentifier("jar-\(t.rawValue)")
                }
            }
            .frame(maxHeight: compact ? 190 : 270)
            HStack(spacing: 8) {
                ForEach(WearTag.jarOrder, id: \.rawValue) { t in
                    Text(t.title).font(SK.font(13, .semibold)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 28).background(Capsule().fill(ShowUI.tag(t)))
                }
            }
            VStack(spacing: 2) {
                Text("Strongest: \(strongest.title) \u{00B7} Weakest: \(weakest.title)").font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
                if let target { Text("Gold dashed line: \(target.rank.title) target").font(SK.font(12, .bold)).foregroundStyle(ShowUI.goldText) }
                else { Text("Every rank is open. Keep him fed and shiny!").font(SK.font(12, .bold)).foregroundStyle(ShowUI.goldText) }
            }
            .accessibilityIdentifier("condition-summary")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(DT.card))
        .accessibilityElement(children: .contain).accessibilityIdentifier("condition-jars")
    }

    private func rows(_ p: JellyProfile?) -> some View {
        let t = care.show.progress.trophies(character: p?.character ?? who)
        let ribbons = care.race.trophies.shelf(character: p?.character ?? who).raceRibbonCount          // (race ribbons: Trophies/)
        return VStack(spacing: 8) {
            row("Food diary", note: "Last \(min(p?.stats.meals.count ?? 0, JellyStats.mealsKept)) meal\(p?.stats.meals.count == 1 ? "" : "s")", id: "condition-diary") { diaryOpen = true }
            row("Trophies", note: "\(t.cupCount) cup\(t.cupCount == 1 ? "" : "s") \u{00B7} \(t.rosettes.count) rosette\(t.rosettes.count == 1 ? "" : "s") \u{00B7} \(ribbons) ribbon\(ribbons == 1 ? "" : "s")", id: "condition-trophies") { trophiesOpen = true }
        }
    }
    private func row(_ title: String, note: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            HStack(spacing: 8) {
                Text(title).font(SK.font(16, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Text(note).font(SK.font(13, .semibold)).foregroundStyle(SK.muted)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(SK.ink).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(Capsule().fill(DT.card))
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

/// One jelly jar: a glass with a lid, jelly of the stat's colour wobbling at `level`, a paler band for what the last meal added, a gold dashed line
/// at the next rank's target, a "+1" droplet when it just grew, the number plate.
struct JellyJar: View {
    var tag: WearTag
    var level: Float
    var previous: Float
    var grew: Bool
    var target: Float?
    var number: Int
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let top = h * 0.095, bottom = h * 0.97, inner = bottom - top
            let y = bottom - inner * CGFloat(min(max(level, 0), 1))
            let yp = bottom - inner * CGFloat(min(max(previous, 0), 1))
            let c = ShowUI.tag(tag)
            ZStack(alignment: .top) {
                // glass
                RoundedRectangle(cornerRadius: w * 0.26, style: .continuous).fill(.white.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.26, style: .continuous).strokeBorder(Color(hex: 0xB9D3DC), lineWidth: 3))
                    .frame(width: w * 0.9, height: bottom - top).offset(y: top)
                // jelly
                JellyFill(top: y, bottom: bottom, width: w * 0.86, radius: w * 0.24).fill(c).offset(x: w * 0.07)
                if grew, yp > y + 1 { JellyFill(top: y, bottom: yp + 3, width: w * 0.86, radius: w * 0.1).fill(.white.opacity(0.5)).offset(x: w * 0.07) }
                // shine
                Path { p in p.move(to: CGPoint(x: w * 0.2, y: y + 7)); p.addQuadCurve(to: CGPoint(x: w * 0.4, y: y + 4), control: CGPoint(x: w * 0.25, y: y + 3)) }
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Path { p in p.move(to: CGPoint(x: w * 0.17, y: top + h * 0.08)); p.addLine(to: CGPoint(x: w * 0.17, y: top + h * 0.5)) }
                    .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // the next rank's line
                if let target {
                    let yt = bottom - inner * CGFloat(target)
                    Path { p in p.move(to: CGPoint(x: w * 0.1, y: yt)); p.addLine(to: CGPoint(x: w * 0.9, y: yt)) }
                        .stroke(Color(hex: 0xC98A12).opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                }
                // lid
                RoundedRectangle(cornerRadius: w * 0.14, style: .continuous).fill(c).overlay(RoundedRectangle(cornerRadius: w * 0.14, style: .continuous).strokeBorder(SK.ink.opacity(0.35), lineWidth: 1.5))
                    .frame(width: w * 0.8, height: h * 0.08).offset(y: h * 0.01)
                // "+1" droplet
                if grew {
                    VStack(spacing: 2) {
                        Image(systemName: "drop.fill").font(.system(size: w * 0.3, weight: .semibold)).foregroundStyle(c).overlay(Image(systemName: "drop").font(.system(size: w * 0.3, weight: .semibold)).foregroundStyle(SK.ink))
                        Text("+\(max(1, Int(((level - previous) * 100).rounded())))").font(SK.font(11, .semibold)).foregroundStyle(ShowUI.gold)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(SK.ink))
                    }
                    .offset(y: max(top + h * 0.1, y - w * 0.95))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
                }
                // number plate
                Text("\(number)").font(SK.font(w * 0.34, .semibold)).foregroundStyle(SK.ink).monospacedDigit()
                    .frame(width: w * 0.72, height: h * 0.12)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0xFBF6EA)).overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SK.ink.opacity(0.3), lineWidth: 1.5)))
                    .offset(y: bottom - h * 0.17)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tag.title) \(number)\(grew ? ", just grew" : "")")
    }
}

/// The jelly in a jar: a rounded block with a soft wobble on its top edge.
struct JellyFill: SwiftUI.Shape {
    var top: CGFloat, bottom: CGFloat, width: CGFloat, radius: CGFloat
    var animatableData: CGFloat { get { top } set { top = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard bottom - top > 2 else { return p }
        let x0: CGFloat = 0, x1 = width
        let r = min(radius, (bottom - top) / 2)
        p.move(to: CGPoint(x: x0, y: top + 3))
        p.addQuadCurve(to: CGPoint(x: width * 0.5, y: top + 1), control: CGPoint(x: width * 0.3, y: top - 3))
        p.addQuadCurve(to: CGPoint(x: x1, y: top + 3), control: CGPoint(x: width * 0.72, y: top + 4))
        p.addLine(to: CGPoint(x: x1, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: x1 - r, y: bottom), control: CGPoint(x: x1, y: bottom))
        p.addLine(to: CGPoint(x: x0 + r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: x0, y: bottom - r), control: CGPoint(x: x0, y: bottom))
        p.closeSubpath()
        return p
    }
}

/// The food diary: the last eight meals, newest first, with what each raised.
struct FoodDiarySheet: View {
    let care: GameCare
    var who: Int
    var close: () -> Void
    var body: some View {
        let meals = care.jelly(who)?.stats.meals ?? []
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Food diary").font(SK.font(26, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                    .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("diary-close")
            }
            if meals.isEmpty { Text("Nothing eaten from the bag yet. Store foods fill his jars: sushi is Sparkly, donuts are Sweet.").font(SK.font(14, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(meals.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 10) {
                            Image(systemName: "fork.knife").font(.system(size: 16, weight: .semibold)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0xFFE7A8)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.food).font(SK.font(16, .semibold)).foregroundStyle(SK.ink)
                                HStack(spacing: 4) {
                                    ForEach(m.gains.sorted { $0.value > $1.value }, id: \.key) { k, v in
                                        if let key = ConditionKey(rawValue: k) { Text("+\(max(1, Int((v * 100).rounded()))) \(key.title)").font(SK.font(11, .semibold)).foregroundStyle(SK.ink).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(ShowUI.tag(key.tag))) }
                                    }
                                }
                            }
                            Spacer()
                            Text(m.date, style: .relative).font(SK.font(12, .semibold)).foregroundStyle(SK.muted) + Text(" ago").font(SK.font(12, .semibold)).foregroundStyle(SK.muted)
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.8)))
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        .accessibilityIdentifier("diary-sheet")
    }
}

/// The trophy shelf: a cup per rank (bronze / silver / gold for the best placing), a rosette per theme stat won, and the stickers.
struct TrophiesSheet: View {
    let care: GameCare
    var who: Int
    var close: () -> Void
    var body: some View {
        let t = care.show.progress.trophies(character: care.jelly(who)?.character ?? who)
        ScrollView(showsIndicators: false) { VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(care.jelly(who)?.name ?? "Bob")'s trophies").font(SK.font(26, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                    .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("trophies-close")
            }
            Text("Cups").font(SK.font(13, .semibold)).foregroundStyle(SK.muted).textCase(.uppercase)
            HStack(spacing: 10) {
                ForEach(ShowRank.allCases, id: \.rawValue) { r in
                    let place = t.cup(r)
                    VStack(spacing: 4) {
                        Image(systemName: "trophy.fill").font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(place == 1 ? ShowUI.goldDeep : place == 2 ? Color(hex: 0xC9CFD8) : place == 3 ? Color(hex: 0xC98B55) : SK.muted.opacity(0.25))
                        Text(r.title).font(SK.font(12, .semibold)).foregroundStyle(SK.ink)
                        Text(place.map { ShowUI.ordinal($0) } ?? "\u{2014}").font(SK.font(11, .semibold)).foregroundStyle(SK.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.8)))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("cup-\(r.rawValue)")
                }
            }
            Text("Rosettes").font(SK.font(13, .semibold)).foregroundStyle(SK.muted).textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(WearTag.jarOrder, id: \.rawValue) { tag in
                    let has = t.hasRosette(tag)
                    VStack(spacing: 3) {
                        Image(systemName: "seal.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(has ? ShowUI.tag(tag) : SK.muted.opacity(0.2))
                        Text(tag.title).font(SK.font(11, .semibold)).foregroundStyle(has ? SK.ink : SK.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(has ? 0.85 : 0.45)))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("rosette-\(tag.rawValue)")
                }
            }
            Text("Stickers").font(SK.font(13, .semibold)).foregroundStyle(SK.muted).textCase(.uppercase)
            FlowLayout(spacing: 6) {
                ForEach(ShowProgress.Sticker.allCases, id: \.rawValue) { s in
                    let has = t.stickers.contains(s.rawValue)
                    Text(s.title).font(SK.font(12, .semibold)).foregroundStyle(has ? ShowUI.brownGold : SK.muted).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(has ? ShowUI.light : .white.opacity(0.45)))
                }
            }
            Text(t.shows == 0 ? "No shows yet. The first one earns a sticker." : "\(t.shows) show\(t.shows == 1 ? "" : "s") so far.").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
            RaceTrophiesSection(care: care, who: who)          // (race ribbons and trophies: Trophies/)
            VolleyTrophiesSection(care: care, who: who)          // (beach volleyball ribbons and trophies: Volley/)
        } }
        .padding(16)
        .accessibilityIdentifier("trophies-sheet")
    }
}

// MARK: - the Show lobby

struct ShowLobby: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var card: () -> Void
    var start: (ShowRank) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }
    private var day: Int { GameCare.showDay }
    private var theme: ShowTheme { ShowSchedule.theme(dayKey: day) }
    private var tomorrow: ShowTheme { ShowSchedule.tomorrow(dayKey: day) }
    private var rank: ShowRank { care.show.progress.chosen }
    private var rivals: [ShowRival] { ShowRivalSource.rivals(dayKey: day, rank: rank, theme: theme, firstShow: care.show.progress.firstShowEver) }

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            ShowHeader(title: "Jelly Show", backID: "show-back", back: back) {
                Button { AudioHub.shared.uiTap(); card() } label: {
                    Text("\(care.jelly(who)?.name ?? "Bob")'s card").font(SK.font(15, .semibold)).foregroundStyle(SK.ink).padding(.horizontal, 16).frame(height: 44).background(Capsule().fill(DT.card))
                }.buttonStyle(.plain).accessibilityIdentifier("show-card")
            }
            if compact {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView { VStack(spacing: 10) { poster; ranks }.padding(.bottom, 8) }.scrollBounceBehavior(.basedOnSize)
                    ScrollView { VStack(spacing: 10) { today; ready; startButton }.padding(.bottom, 8) }.scrollBounceBehavior(.basedOnSize)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) { poster; ranks; today; ready }
                }
                .scrollBounceBehavior(.basedOnSize)
                startButton
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(ShowUI.hall.ignoresSafeArea())
        .accessibilityIdentifier("show-lobby")
    }

    /// Today's theme poster and tomorrow's teaser.
    private var poster: some View {
        HStack(spacing: 10) {
            ZStack {
                StageBackdrop().opacity(0.9)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S THEME").font(SK.font(12, .semibold)).foregroundStyle(ShowUI.gold).tracking(0.5)
                    Text(theme.title).font(SK.font(24, .semibold)).foregroundStyle(ShowUI.light).jLine(2, scale: 0.7)
                    HStack(spacing: 6) { TagChip(tag: theme.main); TagChip(tag: theme.friend, prefix: "+ friend: ") }
                    Text("\(theme.main.title) counts most").font(SK.font(12, .bold)).foregroundStyle(ShowUI.lilacPale)
                }
                .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .combine).accessibilityIdentifier("show-theme")
            VStack(alignment: .leading, spacing: 4) {
                Text("TOMORROW").font(SK.font(11, .semibold)).foregroundStyle(ShowUI.lilacPale).tracking(0.5)
                Text(tomorrow.title).font(SK.font(17, .semibold)).foregroundStyle(SK.cream).jLine(2, scale: 0.7)
                Text("\(tomorrow.main.title) + \(tomorrow.friend.title)").font(SK.font(12, .semibold)).foregroundStyle(Color(hex: 0xB58BDB))
                Text("Get ready: feed and dress").font(SK.font(11, .bold)).foregroundStyle(ShowUI.lilacPale)
            }
            .padding(12).frame(width: 118).frame(minHeight: 150, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(ShowUI.lilac, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            .accessibilityElement(children: .combine).accessibilityIdentifier("show-tomorrow")
        }
    }

    /// The rank picker: four tiles, the cleared ones with their cup, the picked one gold, the locked ones with a padlock.
    private var ranks: some View {
        let prog = care.show.progress
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pick a rank").font(SK.font(16, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Text(prog.requirement(rank.above ?? .ocean) ?? "Every rank is open").font(SK.font(11, .semibold)).foregroundStyle(SK.muted).jLine(1, scale: 0.7)
            }
            HStack(spacing: 6) {
                ForEach(ShowRank.allCases, id: \.rawValue) { r in
                    let open = prog.unlocked(r), picked = r == rank, cup = prog.trophies(character: care.jelly(who)?.character ?? who).cup(r)
                    Button { if open { AudioHub.shared.uiTap(); care.chooseShowRank(r) } else { AudioHub.shared.play(.notEnough) } } label: {
                        VStack(spacing: 1) {
                            Image(systemName: open ? (cup != nil ? "trophy.fill" : "drop.fill") : "lock.fill").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(open ? (cup == 1 ? ShowUI.goldDeep : cup == 2 ? Color(hex: 0x9AA3B2) : cup == 3 ? Color(hex: 0xC98B55) : SK.sky) : Color(hex: 0x7C6A93))
                            Text(r.title).font(SK.font(14, .semibold))
                            Text(picked ? "Selected" : open ? (cup.map { "\($0 == 1 ? "Gold" : $0 == 2 ? "Silver" : "Bronze") cup" } ?? "Open") : "Locked").font(SK.font(11, .semibold)).opacity(0.8)
                        }
                        .foregroundStyle(open ? (picked ? SK.ink : Color(hex: 0x2E6B26)) : Color(hex: 0x7C6A93))
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(picked ? ShowUI.gold : open ? Color(hex: 0xE3F4DD) : Color(hex: 0xE9E1F0)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(picked ? ShowUI.goldDeep : open ? SK.mint : Color(hex: 0xC9BBD9), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(r.title) rank, \(picked ? "selected" : open ? "open" : "locked")").accessibilityIdentifier("rank-\(r.rawValue)").accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DT.card))
        .accessibilityElement(children: .contain).accessibilityIdentifier("show-ranks")
    }

    /// Today's rivals at the picked rank and the prizes.
    private var today: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today at \(rank.title)").font(SK.font(16, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Text("3 rivals \u{00B7} 4 Jelbies").font(SK.font(12, .semibold)).foregroundStyle(SK.muted)
            }
            HStack(spacing: 8) {
                ForEach(Array(rivals.enumerated()), id: \.offset) { _, r in
                    VStack(spacing: 1) {
                        RivalBlob(tint: r.tint, size: 44)
                        Text(r.name).font(SK.font(r.headliner ? 11 : 14, .black)).foregroundStyle(SK.ink).jLine(1, scale: 0.6)
                        Text(r.persona.title).font(SK.font(11, .semibold)).foregroundStyle(SK.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6).padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: Double(r.tint.x), green: Double(r.tint.y), blue: Double(r.tint.z)).opacity(0.28)))
                    .accessibilityElement(children: .combine).accessibilityLabel("\(r.name), \(r.persona.title)")
                }
            }
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { p in
                    VStack(spacing: 1) {
                        Text(ShowUI.ordinal(p)).font(SK.font(11, .semibold)).foregroundStyle(SK.muted)
                        HStack(spacing: 3) { Image(systemName: "drop.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(SK.skyDeep); Text("\(rank.drops(place: p))").font(SK.font(15, .semibold)).foregroundStyle(SK.ink) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p == 1 ? Color(hex: 0xFFE7A8) : p == 2 ? Color(hex: 0xECE8EE) : p == 3 ? Color(hex: 0xF3E1D0) : Color(hex: 0xF2ECE6)))
                    .accessibilityElement(children: .combine).accessibilityLabel("\(ShowUI.ordinal(p)) pays \(rank.drops(place: p)) Drops")
                }
            }
            .accessibilityIdentifier("show-prizes")
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DT.card))
        .accessibilityElement(children: .contain).accessibilityIdentifier("show-today")
    }

    /// The Ready check: an estimate of each round.
    private var ready: some View {
        let est = care.showEstimate(jelly: who, rank: rank, theme: theme)
        let p = care.showPlayerInput(jelly: who)
        let outfit = care.showOutfitTags(jelly: who)
        let worn = rank.slotOrder.compactMap { outfit[$0] }
        let sum = worn.reduce(0) { $0 + theme.match($1) }
        let known = ShowTrickInfo.stageTricks.filter { p.tricks[$0] != nil }
        let best = known.max { (p.tricks[$0] ?? 0) < (p.tricks[$1] ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready check").font(SK.font(16, .semibold)).foregroundStyle(SK.ink)
                Spacer()
                Text("\(p.name) \u{00B7} out of 100 each").font(SK.font(12, .semibold)).foregroundStyle(SK.muted)
            }
            ShowBar(name: "Look", value: est.look / 100, color: SK.pink, note: "\(rank.slots) slots, \(String(format: "%g", (sum * 2).rounded() / 2)) theme match", score: est.lookPts, nameWidth: 50)
            ShowBar(name: "Dance", value: est.dance / 100, color: Color(hex: 0xB58BDB), note: p.dance.map { "\($0.title) skill \(ShowUI.pts(p.danceSkill))%" } ?? "No dance learned", score: est.dancePts, nameWidth: 50)
            ShowBar(name: "Trick", value: est.trick / 100, color: SK.honeyDeep, note: known.isEmpty ? "No tricks learned" : "\(known.count) known, \(best?.title.lowercased() ?? "") is \(ShowUI.pts(best.map { p.tricks[$0] ?? 0 } ?? 0))%", score: est.trickPts, nameWidth: 50)
            HStack {
                (Text("Estimate ").font(SK.font(14, .semibold)) + Text("about \(Int((est.total / 10).rounded()) * 10)").font(SK.font(17, .semibold)) + Text(" / 300").font(SK.font(14, .semibold))).foregroundStyle(SK.ink)
                Spacer()
                Text("\(rank.title) rivals about \(rank.rivalEstimate)").font(SK.font(12, .semibold)).foregroundStyle(SK.muted)
            }
            .padding(.top, 6).overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xD9C9AE)).frame(height: 2) }
            .accessibilityIdentifier("show-estimate")
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DT.card))
        .accessibilityElement(children: .contain).accessibilityIdentifier("show-ready")
    }

    private var startButton: some View {
        VStack(spacing: 6) {
            ShowCTA(title: "Start show", symbol: "star.fill", enabled: care.showBlocker(jelly: who) == nil, id: "show-start") { start(rank) }
            if let why = care.showBlocker(jelly: who) { Text(why).font(SK.font(12, .bold)).foregroundStyle(ShowUI.lilacPale).accessibilityIdentifier("show-why") }
        }
    }
}
