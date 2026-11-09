//
//  ShowUI.swift
//  The Jelly Show's places (the approved mockups Studio.dc.html, Condition.dc.html, Show.dc.html), reached from the Town:
//    StudioScreen      the stage card with the Jelbie and his slot chips, the Show-ready bars, Dress up / Enter Jelly Show.
//    ConditionScreen   the "Jelly Jars": five jars of stat-coloured jelly with numbers, a gold next-rank line, a +1 droplet on jars that just
//                      grew, the Glow pill with a Bath button, Food diary and Trophies as row buttons, "See today's Jelly Show".
//                      (it also picks the rank and shows the theme, the score estimate and its tip; Enter Jelly Show starts the show: there is no second lobby.)
//  Plus the shared pieces: the Jelbie portrait, the stat chip, the wardrobe sheet (owned wearables, tap to wear), the dance picker.
//  Everything lays out both ways: portrait stacks, a phone on its side puts the stage / poster beside the cards.
//

import SwiftUI

// MARK: - palette and small pieces

enum ShowUI {
    static let hall = Color(hex: 0x3B2E4F), stage = Color(hex: 0x4E3D68), platform = Color(hex: 0x6B5487), curtain = Color(hex: 0xC25A78)
    static let light = Color(hex: 0xFFF3C9), gold = Color(hex: 0xFFE07A), goldDeep = Color(hex: 0xF2B530), lilac = Color(hex: 0x9C8AB5), lilacPale = Color(hex: 0xCDBFE0), mist = Color(hex: 0xE2D6F0)
    static let sand = Color(hex: 0xEADFC8), bar = Color(hex: 0xE6D8C6), brownGold = Color(hex: 0x6B4A00), goldText = Color(hex: 0x8A6A12)
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
extension GameCare {
    /// The name to show for the Jelbie `who`: theirs, else the selected one's, else the first on the roster, else "Your Jelbie". (Never a made-up default.)
    func rosterName(_ who: Int) -> String {
        jelly(who)?.name ?? jelly(targetJelly)?.name ?? jellies.first?.name ?? "Your Jelbie"
    }
}

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
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .black)).foregroundStyle(SK.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(SK.cream))
            }.buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier(backID)
            VStack(alignment: .leading, spacing: 0) {
                if let k = kicker { Text(k).font(SK.font(12, .black)).foregroundStyle(ShowUI.gold).tracking(0.5) }
                Text(title).font(SK.font(24, .black)).foregroundStyle(light ? SK.cream : SK.ink).jLine(1, scale: 0.7)
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
    /// A thin ring OUTSIDE the portrait and a soft shadow (the lobby mockups' avatars); nil = the Show's 4 pt inner ring.
    var outerRing: CGFloat? = nil
    /// The lobby avatar: the body alone (no room) framed on the head, over a light backdrop; `friend` draws that Park visitor on this body instead.
    var head = false
    var friend: ParkVisitor? = nil
    /// A Show rival drawn as the stage draws her: this body in her pastel colour, no wear, no feature.
    var rival: ShowRival? = nil
    /// The lobby picker's picture: just the head (the render has a clear background), no circle, ring or shadow, so nothing crops it.
    var frameless = false
    @State private var image: UIImage?
    @State private var tried = false
    private var key: HeadPortraitKey { HeadPortraitKey(jelly: who, colour: friend?.colour, wear: friend?.wear, rivalTint: rival?.tint, rivalName: rival?.name) }
    var body: some View {
        if frameless { framelessBody } else { framedBody }
    }
    private var framelessBody: some View {
        let t = JellyRoster.tint(care.jelly(who)?.character ?? who)
        return ZStack {
            if let shown = image ?? HeadPortraitCache.shared.cached(key, care: care) { Image(uiImage: shown).resizable().scaledToFit() }
            else if tried { Circle().fill(Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))).padding(size * 0.2) }
            else { ProgressView().tint(SK.muted) }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(friend.map { "\($0.name), a Park friend" } ?? "\(care.jelly(who)?.name ?? "Jelbie")")
        .accessibilityIdentifier("jelbie-portrait")
        .task(id: "\(who)-\(care.store.revision)-\(friend?.id ?? -1)") { await loadHead() }
    }
    private func loadHead() async {
        let t0 = CACurrentMediaTime()
        let hit = HeadPortraitCache.shared.cached(key, care: care)
        image = hit; tried = false
        if hit != nil { NSLog("[portrait] tile %d from cache", who); return }
        if let img = await HeadPortraitCache.shared.image(key, care: care) {
            image = img
            NSLog("[portrait] tile %d drawn after %.0f ms", who, (CACurrentMediaTime() - t0) * 1000)
            return
        }
        if !Task.isCancelled { tried = true }
    }
    private var framedBody: some View {
        ZStack {
            Circle().fill(head ? SK.tile : ShowUI.platform)
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle()) }
            else if tried { Circle().fill(Color(red: Double(JellyRoster.tint(care.jelly(who)?.character ?? who).x), green: Double(JellyRoster.tint(care.jelly(who)?.character ?? who).y), blue: Double(JellyRoster.tint(care.jelly(who)?.character ?? who).z))).padding(size * 0.2) }
            else { ProgressView().tint(head ? SK.muted : .white) }
        }
        .frame(width: size, height: size)
        .overlay { if let r = outerRing { Circle().stroke(border, lineWidth: r).padding(-r / 2) } else { Circle().strokeBorder(border, lineWidth: 4) } }
        .shadow(color: outerRing == nil ? .black.opacity(0.25) : SK.ink.opacity(0.18), radius: outerRing == nil ? 6 : 3, y: outerRing == nil ? 3 : 2)
        .accessibilityLabel(rival.map { "\($0.name), \($0.persona.title)" } ?? friend.map { "\($0.name), a Park friend" } ?? "\(care.jelly(who)?.name ?? "Jelbie")")
        .accessibilityIdentifier("jelbie-portrait")
        .task(id: "\(who)-\(care.store.revision)-\(friend?.id ?? -1)-\(rival?.name ?? "")") {
            image = nil; tried = false
            try? await Task.sleep(nanoseconds: 350_000_000)
            for _ in 0..<40 {
                await Task.yield()
                if let img = head ? care.headProvider?(key) : care.portraitProvider?(who) { image = img; return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
            }
            tried = true
        }
    }
}

/// The Studio's contestant: a big full-body action shot (the Jelbie alone, in his outfit; MelonStage.headSnapshot with `pose`) STANDING on a round podium in the stage's purple, a soft
/// contact shadow under his feet. No hop: he breathes slowly (a gentle swell from the floor up; only the front view, pose 0, is drawn). The picture is square
/// and the renderer pins the floor at `HeadPortraitKey.actionFloorFraction` of its height (either orientation), so the disc top sits exactly there.
struct JelbieActionShot: View {
    let care: GameCare
    var who: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [UIImage?] = [nil, nil, nil]
    @State private var breathe = false        // a slow render-server driven autoreversing swell
    private func key(_ pose: Int) -> HeadPortraitKey { HeadPortraitKey(jelly: who, colour: nil, wear: nil, pose: pose) }

    var body: some View {
        GeometryReader { g in
            let h = g.size.height, S = h * 0.86
            let floorY = h * 0.80                                  // the disc's top-centre, in the card
            let discW = S * 0.64, discH = discW * 0.30, rimH = discH * 0.42
            let x = g.size.width / 2
            ZStack {
                ActionPodium(width: discW, topH: discH, rim: rimH).position(x: x, y: floorY + rimH / 2)
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.42), .black.opacity(0)], center: .center, startRadius: 0, endRadius: discW * 0.26))
                    .frame(width: discW * 0.58, height: discH * 0.62).position(x: x, y: floorY)
                if let img = frames[0] {
                    Image(uiImage: img).resizable().scaledToFit().frame(width: S, height: S)
                        .scaleEffect(x: 1 + 0.008 * (breathe && !reduceMotion ? 1 : 0), y: 1 + 0.014 * (breathe && !reduceMotion ? 1 : 0), anchor: UnitPoint(x: 0.5, y: img.feetFraction ?? HeadPortraitKey.actionFloorFraction))
                        .position(x: x, y: floorY + discH * 0.08 - S * (img.feetFraction ?? HeadPortraitKey.actionFloorFraction) + S / 2)
                } else { ProgressView().tint(ShowUI.light).position(x: x, y: h * 0.5) }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)
        }
        .accessibilityLabel("\(care.jelly(who)?.name ?? "Jelbie") on the stage")
        .accessibilityIdentifier("studio-action-shot")
        .task(id: "\(who)-\(care.store.revision)") { await load() }
        .task(id: reduceMotion) {
            guard !reduceMotion else { breathe = false; return }
            breathe = true
        }
    }

    private func load() async {
        let t0 = CACurrentMediaTime()
        frames = [HeadPortraitCache.shared.cached(key(0), care: care), nil, nil]
        for pose in [0] {
            if frames[pose] != nil { continue }
            guard let img = await HeadPortraitCache.shared.image(key(pose), care: care) else { return }
            frames[pose] = img
            if pose == 0 { NSLog("[portrait] action shot %d drawn after %.0f ms", who, (CACurrentMediaTime() - t0) * 1000) }
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
        Text(prefix + tag.title).font(SK.font(size, .black)).foregroundStyle(SK.ink)
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
            Text(name).font(SK.font(15, .black)).foregroundStyle(SK.ink).frame(width: nameWidth, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(ShowUI.bar)
                    Capsule().fill(color).frame(width: max(6, g.size.width * CGFloat(min(max(value, 0), 1))))
                }
            }.frame(height: 12)
            if let score { Text("\(score)").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit().frame(width: 30, alignment: .trailing) }
            if !note.isEmpty { Text(note).font(SK.font(11, .heavy)).foregroundStyle(SK.muted).frame(width: 104, alignment: .leading).jLine(2, scale: 0.8) }
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
                if let s = symbol { Image(systemName: s).font(.system(size: 20, weight: .black)) }
                Text(title).font(SK.font(20, .black)).jLine(1, scale: 0.7)
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
                                if let item = StoreCatalog.item(wearing: look) { ItemArt(item: item, size: 34) } else { Image(systemName: look.slot.symbol).font(.system(size: 22, weight: .heavy)).foregroundStyle(SK.ink) }
                                Text(look.title).font(SK.font(11, .black)).foregroundStyle(SK.ink).jLine(1, scale: 0.7)
                                if let t = look.tags.first(where: { $0 == theme.main }) ?? look.tags.first(where: { $0 == theme.friend }) ?? look.tags.first { TagChip(tag: t, size: 10) }
                                Text(worn ? "Wearing" : other.map { "On \($0)" } ?? look.slot.title).font(SK.font(10, .heavy)).foregroundStyle(worn ? ShowUI.brownGold : SK.muted).jLine(1, scale: 0.7)
                            }
                            .padding(.horizontal, 4).frame(width: 78, height: 102)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(worn ? ShowUI.gold.opacity(0.35) : .white))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(m >= 1 ? ShowUI.gold : m >= 0.5 ? Color(hex: 0xF4D98C) : ShowUI.bar, lineWidth: 2))
                            .shadow(color: ShowUI.gold.opacity(m >= 1 ? 0.9 : m >= 0.5 ? 0.45 : 0), radius: m >= 1 ? 6 : 5)
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
                    if look == nil { Text("+").font(SK.font(22, .black)).foregroundStyle(ShowUI.lilacPale) }
                    else if let l = look, let item = StoreCatalog.item(wearing: l) { ItemArt(item: item, size: 32) }
                    else { Image(systemName: slot.symbol).font(.system(size: 18, weight: .heavy)).foregroundStyle(SK.ink) }
                }
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(look == nil ? ShowUI.lilac : m >= 1 ? ShowUI.gold : m >= 0.5 ? Color(hex: 0xF4D98C) : ShowUI.lilac, style: StrokeStyle(lineWidth: 2, dash: look == nil ? [5, 4] : [])))
                .shadow(color: ShowUI.gold.opacity(m >= 1 ? 0.85 : m >= 0.5 ? 0.45 : 0), radius: m >= 1 ? 6 : 5)
            }
            .buttonStyle(.plain).disabled(action == nil)
            if caption { Text(slot.title.replacingOccurrences(of: "Faces", with: "Face").replacingOccurrences(of: "Hats", with: "Head").replacingOccurrences(of: "Shoes", with: "Feet").replacingOccurrences(of: "Necks", with: "Neck").replacingOccurrences(of: "Bodies", with: "Body")).font(SK.font(11, .heavy)).foregroundStyle(m >= 1 ? ShowUI.gold : ShowUI.mist) }
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
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wardrobeOpen = false
    @State private var howOpen = false
    @State private var rankHint: String?
    /// The player has opened Dress up this visit: the button stops asking for attention.
    @State private var dressed = false
    @State private var pulse = false
    private var compact: Bool { vsc == .compact }
    private var day: Int { GameCare.showDay }
    private var theme: ShowTheme { ShowSchedule.theme(dayKey: day) }
    private var rank: ShowRank { care.show.progress.chosen }
    private var blocker: String? { care.showBlocker(jelly: who) }

    /// The shared lobby frame (Lobby/LobbyKit.swift) in the Studio's purple: the stage (the place), the Jelbie picker, the Show-ready card, Practise dance / Enter Jelly Show.
    private var lobbyHeader: AnyView { AnyView(LobbyHeader(title: "Jelly Show", wallet: care.bath.wallet, backID: "studio-back", helpID: "studio-help", back: back, help: { setHow(true) })) }
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            LobbyLabelRow(title: "Stage", trailing: "\(ShowUI.dayName(day))'s theme: \(theme.title)").accessibilityIdentifier("studio-theme")
            stageCard
            rankRow.padding(.top, 6)
            LobbyPlaceInfo(text: rank.lobbyBlurb, textID: "studio-blurb", prizes: LobbyPrize.places((1...3).map { rank.drops(place: $0) }), prizeID: "studio-prizes")
        }
    }
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            LobbyJelbiePicker(care: care, title: "Contestant", selected: [who], selectCount: 1, id: "studio-picker", tileID: { "studio-who-\($0.id)" }) { who = $0 }
                .padding(.bottom, 6)
            readyCard
        }
    }
    private var enterBar: some View {
        LobbyBottomBar(playID: "studio-show", playTitle: "Enter Jelly Show", playIcon: .star, blocked: blocker != nil, play: { show() })
    }

    /// iPad landscape only: the stage, ranks and prizes on the left, the contestant picker and the Show-ready card on the right, the Enter bar right under them
    /// (LobbyScreen's one capped column leaves wide empty sides and a gap above the button).
    private var padLandscape: some View {
        VStack(spacing: 0) {
            lobbyHeader.padding(.top, 8).padding(.horizontal, 24)
            // when both columns fit they take their natural height (so the Enter bar sits right under them); only if they do not fit do they scroll
            ViewThatFits(in: .vertical) {
                HStack(alignment: .top, spacing: 28) {
                    leftColumn.frame(maxWidth: .infinity, alignment: .leading)
                    rightColumn.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 28) {
                    ScrollView { leftColumn.frame(maxWidth: .infinity, alignment: .leading) }.scrollBounceBehavior(.basedOnSize)
                    ScrollView { rightColumn.frame(maxWidth: .infinity, alignment: .leading) }.scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.horizontal, 24).padding(.top, 6)
            VStack(spacing: 0) {
                Text(blocker ?? " ").font(SK.font(12, .bold)).foregroundStyle(LobbyTheme.studio.subheading).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("studio-why")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                enterBar
            }
            .frame(maxWidth: 520).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 1180).frame(maxWidth: .infinity)
        .background(LobbyTheme.studio.background.ignoresSafeArea())
    }

    private var lobbyFrame: some View {
        LobbyScreen(header: lobbyHeader, why: blocker, whyID: "studio-why") {
            leftColumn
        } right: {
            rightColumn.padding(.top, compact ? 0 : 12)
        } bar: {
            enterBar
        }
    }

    var body: some View {
        ZStack {
            Group {
                if PadLayout.isPad {
                    GeometryReader { g in
                        if g.size.width > g.size.height { padLandscape } else { lobbyFrame }
                    }
                } else { lobbyFrame }
            }
            .accessibilityHidden(howOpen)
            if howOpen {
                LobbyHowSheet(rows: [
                    (.hanger, "Dress for the theme", "Pick the rank, then tap Dress up. Things in today\u{2019}s style count most. Gold edge = a match."),
                    (.drop, "Feed and shine", "Theme foods fill the jars. A Clean before the Jelly Show adds Glow."),
                    (.trophy, "Enter the Jelly Show", "Look, Dance and Trick, each scored out of 100."),
                ], close: { setHow(false) })
                .zIndex(1)
            }
        }
        .environment(\.lobbyTheme, .studio)
        .accessibilityElement(children: .contain).accessibilityIdentifier("studio-screen")
        .onChange(of: wardrobeOpen) { _, open in if open { dressed = true } }
        .sheet(isPresented: $wardrobeOpen) {
            WardrobeSheet(care: care, who: who, theme: theme, rank: rank) { wardrobeOpen = false }
                .presentationDetents(compact ? [.large] : [.medium, .large]).presentationBackground(SK.cream)
        }
    }

    private func setHow(_ on: Bool) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { howOpen = on } }

    static func stageHeight(_ compact: Bool) -> CGFloat { compact ? 160 : 192 }

    /// The stage card: the Jelbie under a spotlight, the day's theme, his slot chips either side.
    private var stageCard: some View {
        let outfit = care.store.outfit(who)
        let slots = rank.slotOrder
        let left = Array(slots.prefix((slots.count + 1) / 2)), right = Array(slots.dropFirst((slots.count + 1) / 2))
        return ZStack {
            StageBackdrop()
            JelbieActionShot(care: care, who: who).padding(.top, 0)
            HStack(spacing: 0) {
                VStack(spacing: 10) { ForEach(left, id: \.rawValue) { s in SlotChip(slot: s, look: outfit[s], theme: theme, caption: false) { wardrobeOpen = true } } }.frame(width: 56)
                Spacer(minLength: 0)
                VStack(spacing: 10) { ForEach(right, id: \.rawValue) { s in SlotChip(slot: s, look: outfit[s], theme: theme, caption: false) { wardrobeOpen = true } } }.frame(width: 56)
            }
            .padding(.horizontal, 16)
            VStack {
                HStack(spacing: 5) { themeChip(theme.main, ""); themeChip(theme.friend, "+ ") }.padding(.top, 6)
                Spacer()
                HStack(alignment: .bottom) {
                    if dressed {
                        Text("Gold edge =\nmatches \(theme.main.title)").font(SK.font(12.5, .heavy)).foregroundStyle(ShowUI.gold).lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth: 104, alignment: .leading)
                    } else {
                        Text("Dress for \(theme.main.title) + \(theme.friend.title)").font(SK.font(12.5, .black)).foregroundStyle(ShowUI.gold).lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth: 124, alignment: .leading)
                            .accessibilityIdentifier("studio-dress-hint")
                    }
                    Spacer(minLength: 6)
                    Button { AudioHub.shared.uiTap(); wardrobeOpen = true } label: {
                        Text("Dress up").font(SK.font(14, .black)).foregroundStyle(SK.ink).padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(dressed ? ShowUI.light : ShowUI.gold))
                            .shadow(color: ShowUI.gold.opacity(dressed ? 0 : (pulse ? 0.95 : 0.35)), radius: dressed ? 0 : (pulse ? 10 : 3))
                            .scaleEffect(dressed || reduceMotion ? 1 : (pulse ? 1.07 : 1))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .padding(.vertical, -4)
                    .buttonStyle(.plain).accessibilityIdentifier("studio-dress")
                    .accessibilityHint(dressed ? "" : "Dress for \(theme.main.title) and \(theme.friend.title) before the Jelly Show")
                    .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } } else { pulse = true } }
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: Self.stageHeight(compact), maxHeight: Self.stageHeight(compact))          // tall: the contestant is a big action shot
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain).accessibilityIdentifier("studio-stage")
    }

    private func themeChip(_ t: WearTag, _ prefix: String) -> some View {
        Text("\(prefix)\(t.title)").font(SK.font(12, .black)).foregroundStyle(SK.ink).padding(.horizontal, 9).frame(minHeight: 22).background(Capsule().fill(ShowUI.tag(t)))
    }

    /// The rank to enter: one pill per rank (locked ones say what opens them).
    private var rankRow: some View {
        let prog = care.show.progress
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(ShowRank.allCases, id: \.rawValue) { r in
                    let open = prog.unlocked(r), picked = r == rank
                    Button {
                        AudioHub.shared.uiTap()
                        if open { _ = care.chooseShowRank(r); rankHint = nil }
                        else { rankHint = prog.requirement(r) ?? "Win at \(r.below?.title ?? "")" }
                    } label: {
                        HStack(spacing: 3) {
                            if !open { Image(systemName: "lock.fill").font(.system(size: 10, weight: .black)) }
                            Text(r.title).font(SK.font(13.5, .black)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(picked && open ? SK.ink : open ? ShowUI.light : ShowUI.lilac)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(picked && open ? ShowUI.gold : Color.white.opacity(open ? 0.14 : 0.06)))
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(open ? "\(r.title) rank" : "\(r.title) rank, locked. \(prog.requirement(r) ?? "Win at \(r.below?.title ?? "")")")
                    .accessibilityAddTraits(picked ? .isSelected : [])
                    .accessibilityIdentifier("rank-\(r.rawValue)")
                }
            }
            .padding(.vertical, -6)
            if let rankHint { Text(rankHint).font(SK.font(12, .bold)).foregroundStyle(ShowUI.lilacPale).lineLimit(2).accessibilityIdentifier("studio-rank-hint") }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .contain).accessibilityIdentifier("studio-ranks")
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
        let fc = care.showForecast(jelly: who, rank: rank, theme: theme)
        return LobbyStatsCard(title: "Show ready", groups: [LobbyStatGroup(id: "studio-stats", rows: [
            LobbyStatRow(label: "Look", value: min(1, sum / Float(rank.slots)), color: SK.pink, note: "\(match) of \(rank.slots) match theme"),
            LobbyStatRow(label: "Shine", value: glow, color: SK.sky, note: glow > 0.8 ? "Bathed recently" : glow > 0.3 ? "Glow \(ShowUI.glowOf5(glow)) of 5" : "A Clean would help"),
            LobbyStatRow(label: "Diet", value: 0.7 * main + 0.3 * friend, color: SK.mint, note: "\(theme.main.title) \(ShowUI.pts(main)) \u{00B7} \(theme.friend.title) \(ShowUI.pts(friend))"),
            LobbyStatRow(label: "Score", value: Float(fc.total) / 300, color: SK.pinkStrong, note: "about \(fc.total) of 300\nrivals about \(fc.rivals)"),
        ])], id: "studio-ready", trailing: {
            Button { AudioHub.shared.uiTap(); card() } label: { Text("\(care.rosterName(who))'s card \u{203A}").font(SK.font(14, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.8).frame(minHeight: 44) }
                .buttonStyle(.plain).padding(.vertical, -10).accessibilityIdentifier("studio-card")
        }, footer: {
            HStack(spacing: 7) {
                LobbyIcon(kind: .bulb, color: SK.ink).frame(width: 22, height: 22).background(Circle().fill(SK.honeyDeep.opacity(0.45)))
                Text(fc.tip).font(SK.font(13, .heavy)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("studio-tip")
        })
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
                    Text("Dress up").font(SK.font(26, .black)).foregroundStyle(SK.ink)
                    Spacer()
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                        .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("wardrobe-close")
                }
                HStack(spacing: 6) {
                    Text("\(theme.title):").font(SK.font(13, .heavy)).foregroundStyle(SK.muted)
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
        let name = care.rosterName(who)
        let meal = lastMeal(p)
        let glow = p?.grime.sparkle ?? 0
        let levels = WearTag.jarOrder.map { p?.stats.condition($0.condition) ?? 0 }
        let strongest = WearTag.jarOrder[levels.indices.max { levels[$0] < levels[$1] } ?? 0], weakest = WearTag.jarOrder[levels.indices.min { levels[$0] < levels[$1] } ?? 0]
        let target = ShowUI.target(after: care.show.progress.unlockedRanks)
        return VStack(spacing: 8) {
            HStack {
                Text("\(name)'s jelly jars").font(SK.font(18, .black)).foregroundStyle(SK.ink)
                Spacer()
            }
            HStack {
                if let meal { Text("Just fed: \(meal.food)").font(SK.font(13, .black)).foregroundStyle(ShowUI.brownGold).padding(.horizontal, 12).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xFFE7A8))).accessibilityIdentifier("condition-fed") }
                Spacer()
                Button { AudioHub.shared.uiTap(); bath?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill").font(.system(size: 14, weight: .black)).foregroundStyle(SK.skyDeep)
                        Text("Glow \(ShowUI.glowOf5(glow))/5").font(SK.font(14, .black)).foregroundStyle(Color(hex: 0x2F6F8C))
                        Text("Bath").font(SK.font(12, .black)).foregroundStyle(Color(hex: 0x2F6F8C)).padding(.horizontal, 10).frame(height: 28).background(Capsule().fill(.white))
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
                    Text(t.title).font(SK.font(13, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 28).background(Capsule().fill(ShowUI.tag(t)))
                }
            }
            VStack(spacing: 2) {
                Text("Strongest: \(strongest.title) \u{00B7} Weakest: \(weakest.title)").font(SK.font(15, .black)).foregroundStyle(SK.ink)
                if let target { Text("Gold dashed line: \(target.rank.title) target").font(SK.font(12, .bold)).foregroundStyle(ShowUI.goldText) }
                else { Text("Every rank is open. Keep your Jelbie fed and shiny!").font(SK.font(12, .bold)).foregroundStyle(ShowUI.goldText) }
            }
            .accessibilityIdentifier("condition-summary")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.12), radius: 6, y: 2))
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
                Text(title).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                Spacer()
                Text(note).font(SK.font(13, .heavy)).foregroundStyle(SK.muted)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .black)).foregroundStyle(SK.ink).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.1), radius: 6, y: 2))
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
                        Image(systemName: "drop.fill").font(.system(size: w * 0.3, weight: .black)).foregroundStyle(c).overlay(Image(systemName: "drop").font(.system(size: w * 0.3, weight: .black)).foregroundStyle(SK.ink))
                        Text("+\(max(1, Int(((level - previous) * 100).rounded())))").font(SK.font(11, .black)).foregroundStyle(ShowUI.gold)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(SK.ink))
                    }
                    .offset(y: max(top + h * 0.1, y - w * 0.95))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
                }
                // number plate
                Text("\(number)").font(SK.font(w * 0.34, .black)).foregroundStyle(SK.ink).monospacedDigit()
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
                Text("Food diary").font(SK.font(26, .black)).foregroundStyle(SK.ink)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                    .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("diary-close")
            }
            if meals.isEmpty { Text("Nothing eaten from the bag yet. Store foods fill the jars: sushi is Sparkly, donuts are Sweet.").font(SK.font(14, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(meals.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 10) {
                            Image(systemName: "fork.knife").font(.system(size: 16, weight: .heavy)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0xFFE7A8)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.food).font(SK.font(16, .black)).foregroundStyle(SK.ink)
                                HStack(spacing: 4) {
                                    ForEach(m.gains.sorted { $0.value > $1.value }, id: \.key) { k, v in
                                        if let key = ConditionKey(rawValue: k) { Text("+\(max(1, Int((v * 100).rounded()))) \(key.title)").font(SK.font(11, .black)).foregroundStyle(SK.ink).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(ShowUI.tag(key.tag))) }
                                    }
                                }
                            }
                            Spacer()
                            Text(m.date, style: .relative).font(SK.font(12, .heavy)).foregroundStyle(SK.muted) + Text(" ago").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
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
                Text("\(care.rosterName(who))'s trophies").font(SK.font(26, .black)).foregroundStyle(SK.ink)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                    .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("trophies-close")
            }
            Text("Cups").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
            HStack(spacing: 10) {
                ForEach(ShowRank.allCases, id: \.rawValue) { r in
                    let place = t.cup(r)
                    VStack(spacing: 4) {
                        Image(systemName: "trophy.fill").font(.system(size: 30, weight: .black))
                            .foregroundStyle(place == 1 ? ShowUI.goldDeep : place == 2 ? Color(hex: 0xC9CFD8) : place == 3 ? Color(hex: 0xC98B55) : SK.muted.opacity(0.25))
                        Text(r.title).font(SK.font(12, .black)).foregroundStyle(SK.ink)
                        Text(place.map { ShowUI.ordinal($0) } ?? "\u{2014}").font(SK.font(11, .heavy)).foregroundStyle(SK.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.8)))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("cup-\(r.rawValue)")
                }
            }
            Text("Rosettes").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(WearTag.jarOrder, id: \.rawValue) { tag in
                    let has = t.hasRosette(tag)
                    VStack(spacing: 3) {
                        Image(systemName: "seal.fill").font(.system(size: 26, weight: .black)).foregroundStyle(has ? ShowUI.tag(tag) : SK.muted.opacity(0.2))
                        Text(tag.title).font(SK.font(11, .black)).foregroundStyle(has ? SK.ink : SK.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(has ? 0.85 : 0.45)))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("rosette-\(tag.rawValue)")
                }
            }
            Text("Stickers").font(SK.font(13, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
            FlowLayout(spacing: 6) {
                ForEach(ShowProgress.Sticker.allCases, id: \.rawValue) { s in
                    let has = t.stickers.contains(s.rawValue)
                    Text(s.title).font(SK.font(12, .black)).foregroundStyle(has ? ShowUI.brownGold : SK.muted).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(has ? ShowUI.light : .white.opacity(0.45)))
                }
            }
            Text(t.shows == 0 ? "No Jelly Shows yet. The first one earns a sticker." : "\(t.shows) Jelly Show\(t.shows == 1 ? "" : "s") so far.").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
            RaceTrophiesSection(care: care, who: who)          // (race ribbons and trophies: Trophies/)
            VolleyTrophiesSection(care: care, who: who)          // (beach volleyball ribbons and trophies: Volley/)
        } }
        .padding(16)
        .accessibilityIdentifier("trophies-sheet")
    }
}

// (the Show lobby is in ShowLobby.swift)

/// The stage's podium: a round disc (top ellipse with a bright edge) on a rim in a deeper purple, the adoption picker's pedestal in the Show's palette.
struct ActionPodium: View {
    var width: CGFloat, topH: CGFloat, rim: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                Ellipse().frame(width: width, height: topH).offset(y: rim)
                Rectangle().frame(width: width, height: rim).offset(y: topH / 2)
            }
            .foregroundStyle(LinearGradient(colors: [Color(hex: 0x6E5AA6), Color(hex: 0x3B2D63)], startPoint: .top, endPoint: .bottom))
            Ellipse().fill(LinearGradient(colors: [ShowUI.lilacPale, ShowUI.lilac], startPoint: .top, endPoint: .bottom)).frame(width: width, height: topH)
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: width * 0.36)).frame(width: width, height: topH)
            Ellipse().strokeBorder(.white.opacity(0.75), lineWidth: 1.2).frame(width: width, height: topH)
        }
        .frame(width: width, height: topH + rim)
        .accessibilityHidden(true)
    }
}
