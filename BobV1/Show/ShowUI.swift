//
//  ShowUI.swift
//  The Jelly Show's places (the approved mockups Studio.dc.html, Condition.dc.html, Show.dc.html), reached from the Town:
//    StudioScreen      the stage card with the Jelbie and his slot chips, the Show-ready bars, Dress up / Enter Jelly Show.
//    ConditionScreen   the "Jelly Jars": five jars of stat-coloured jelly with numbers, a gold next-rank line, a +1 droplet on jars that just
//                      grew, the one Glow row with a Bath button, Trophies as a row button, a tap on a jar opens its card (ConditionGuide.swift), "See today's Jelly Show".
//                      (it also picks the rank and shows the theme, the score estimate and its tip; Enter Jelly Show starts the show: there is no second lobby.)
//  Plus the shared pieces: the Jelbie portrait, the stat chip, the wardrobe sheet (owned wearables, tap to wear), the dance picker.
//  Everything lays out both ways: portrait stacks, a phone on its side puts the stage / poster beside the cards.
//

import SwiftUI
import simd

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
        jelly(who)?.name ?? jelly(targetJelly)?.name ?? jellies.first?.name ?? "Your Jelmiko"
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
    /// The Bag / Shop picker at compact height: nudge the picture so its visible (non-transparent) box is centred in the square, whatever the head's ears, antennas or feet add above or below.
    var centreVisible = false
    @State private var image: UIImage?
    @State private var tried = false
    private var key: HeadPortraitKey { HeadPortraitKey(jelly: who, colour: friend?.colour, wear: friend?.wear, rivalTint: rival?.tint, rivalName: rival?.name, feature: friend?.signature) }
    var body: some View {
        if frameless { framelessBody } else { framedBody }
    }
    private var framelessBody: some View {
        let t = JellyRoster.tint(care.jelly(who)?.character ?? who)
        return ZStack {
            if let shown = image ?? HeadPortraitCache.shared.cached(key, care: care) { Image(uiImage: shown).resizable().scaledToFit().offset(y: centreVisible ? Self.centreOffset(shown, in: size) : 0) }
            else if tried { Circle().fill(Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))).padding(size * 0.2) }
            else { ProgressView().tint(SK.muted) }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(friend.map { "\($0.name), a Park friend" } ?? "\(care.jelly(who)?.name ?? "Jelmiko")")
        .accessibilityIdentifier("jelbie-portrait")
        .task(id: "\(who)-\(care.store.revision)-\(friend?.id ?? -1)") { await loadHead() }
    }
    private static let visibleCache = NSCache<UIImage, NSValue>()
    /// Vertical offset (pt) that centres the image's body box (head and feet; antennas and other thin top features do not count) in a `size` square it is scaled to fit. The alpha scan runs once per image (cached).
    static func centreOffset(_ img: UIImage, in size: CGFloat) -> CGFloat {
        guard let cg = img.cgImage, cg.width > 0, cg.height > 0 else { return 0 }
        let rows: (Int, Int)
        if let hit = visibleCache.object(forKey: img) { let r = hit.cgPointValue; rows = (Int(r.x), Int(r.y)) }
        else {
            let w = cg.width, h = cg.height
            var a = [UInt8](repeating: 0, count: w * h)
            let ok = a.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
            }
            var counts = [Int](repeating: 0, count: h)
            if ok { for y in 0..<h { counts[y] = a[(y * w)..<((y + 1) * w)].reduce(0) { $0 + ($1 > 12 ? 1 : 0) } } }
            // the BODY box: from the first row at least 30% as wide as the widest row (so thin antennas, ear tips and spikes are left out) down to the last opaque row (the feet)
            let widest = counts.max() ?? 0
            var top = h, bottom = -1
            if widest > 0 { for y in 0..<h where counts[y] > 0 { if top == h, counts[y] * 10 >= widest * 3 { top = y }; bottom = y } }
            if bottom < top { return 0 }
            visibleCache.setObject(NSValue(cgPoint: CGPoint(x: top, y: bottom)), forKey: img)
            rows = (top, bottom)
        }
        let scale = size / CGFloat(max(cg.width, cg.height))
        let mid = (CGFloat(rows.0) + CGFloat(rows.1 + 1)) / 2
        return (CGFloat(cg.height) / 2 - mid) * scale
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
        .accessibilityLabel(rival.map { "\($0.name), \($0.persona.title)" } ?? friend.map { "\($0.name), a Park friend" } ?? "\(care.jelly(who)?.name ?? "Jelmiko")")
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
    /// The picture's size as a fraction of the card's height, and where the disc top sits in the card (fraction of its height). The Studio's card draws a smaller Jelmiko with room round it; Dress up fills its taller picture area.
    var fill: CGFloat = 0.86
    var floorAt: CGFloat = 0.80
    /// The Studio's card shows a spinner while its first picture loads; Dress up never does (it opens on the lobby's cached picture and keeps the old one while a new one is drawn).
    var spinner = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The last picture drawn, and for WHOM: it may stand in while a new one of the SAME Jelmiko is drawn (a tapped item never flashes a spinner), never for another one.
    @State private var shown: (who: Int, image: UIImage)?
    @State private var breathe = false        // a slow render-server driven autoreversing swell
    private func key(_ pose: Int) -> HeadPortraitKey { HeadPortraitKey(jelly: who, colour: nil, wear: nil, pose: pose) }

    var body: some View {
        GeometryReader { g in
            let h = g.size.height, S = h * fill
            let floorY = h * floorAt                                  // the disc's top-centre, in the card
            let discW = S * 0.64, discH = discW * 0.30, rimH = discH * 0.42
            let x = g.size.width / 2
            ZStack {
                ActionPodium(width: discW, topH: discH, rim: rimH).position(x: x, y: floorY + rimH / 2)
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.42), .black.opacity(0)], center: .center, startRadius: 0, endRadius: discW * 0.26))
                    .frame(width: discW * 0.58, height: discH * 0.62).position(x: x, y: floorY)
                if let img = HeadPortraitCache.shared.cached(key(0), care: care) ?? (shown?.who == who ? shown?.image : nil) {
                    Image(uiImage: img).resizable().scaledToFit().frame(width: S, height: S)
                        .scaleEffect(x: 1 + 0.008 * (breathe && !reduceMotion ? 1 : 0), y: 1 + 0.014 * (breathe && !reduceMotion ? 1 : 0), anchor: UnitPoint(x: 0.5, y: img.feetFraction ?? HeadPortraitKey.actionFloorFraction))
                        .position(x: x, y: floorY + discH * 0.08 - S * (img.feetFraction ?? HeadPortraitKey.actionFloorFraction) + S / 2)
                } else if spinner { ProgressView().tint(ShowUI.light).position(x: x, y: h * 0.5) }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)
        }
        .accessibilityLabel("\(care.jelly(who)?.name ?? "Jelmiko") on the stage")
        .accessibilityIdentifier("studio-action-shot")
        .task(id: "\(who)-\(care.store.revision)") { await load() }
        .task(id: reduceMotion) {
            guard !reduceMotion else { breathe = false; return }
            breathe = true
        }
    }

    /// Draws the picture for `who` in what he wears now unless the cache already has it (the cache is per wardrobe state and per Jelmiko). `shown` is replaced by every new picture, so
    /// a worn item or another contestant always ends up on the stage (show-stage-r1: the old picture used to stay for good once there was one).
    private func load() async {
        let t0 = CACurrentMediaTime()
        let me = who
        if let hit = HeadPortraitCache.shared.cached(key(0), care: care) { shown = (me, hit); return }
        // a render that finds no stage / drawable yet (nil) is asked again, a few times, so the picture never stays on its spinner
        var got: UIImage?
        for attempt in 0..<4 where got == nil {
            if Task.isCancelled { return }
            if attempt > 0 { try? await Task.sleep(nanoseconds: 400_000_000) }
            got = await HeadPortraitCache.shared.image(key(0), care: care)
        }
        guard let img = got, !Task.isCancelled else { return }
        shown = (me, img)
        NSLog("[portrait] action shot %d drawn after %.0f ms", me, (CACurrentMediaTime() - t0) * 1000)
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

/// Owned wearables as tap-to-wear cards, the theme's matches edged in gold. One card per look; the worn one of a slot is marked. At the sheet's low height they are ONE row that
/// scrolls sideways (snapping to a card edge, part of the next card showing); pulled up to large they are a vertically scrolling grid (3 columns on a phone in portrait,
/// more when there is room).
struct WardrobeStrip: View {
    let care: GameCare
    var who: Int
    var theme: ShowTheme
    var slots: [WearSlot]? = nil          // nil = every slot
    var onChange: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scrolling = false
    /// Every owned look, best theme match first.
    static func ordered(care: GameCare, theme: ShowTheme, slots: [WearSlot]?) -> [WearLook] {
        StoreCatalog.items.filter { $0.isWearable && care.store.owns($0) }.compactMap(\.wear).filter { slots?.contains($0.slot) ?? true }
            .sorted { theme.match($0.tags) > theme.match($1.tags) }
    }
    static func rows<T>(_ list: [T], columns: Int) -> [[T]] { stride(from: 0, to: list.count, by: columns).map { Array(list[$0..<min($0 + columns, list.count)]) } }
    /// Columns and card width for the room there is: cards about 100 to 160 pt wide, never fewer than 3 columns (2 at accessibility text sizes).
    static func columns(for width: CGFloat, accessibility: Bool = false) -> (count: Int, card: CGFloat) {
        let gap = WardrobeCardFace.gap
        let n = max(accessibility ? 2 : 3, Int(((width + gap) / (WardrobeCardFace.minWidth + gap)).rounded(.down)))
        return (n, max(60, (width - gap * CGFloat(n - 1)) / CGFloat(n)))
    }
    var body: some View {
        let list = Self.ordered(care: care, theme: theme, slots: slots)
        Group {
            if list.isEmpty {
                Text("Nothing to wear yet. The Shop has hats, bows and shoes.").font(SK.font(13, .bold)).foregroundStyle(ShowUI.lilacPale).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                grid(list)
            }
        }
        .task(id: list.map(\.rawValue)) { await prewarm(list) }
    }

    private func grid(_ list: [WearLook]) -> some View {
        GeometryReader { g in
            let cols = Self.columns(for: g.size.width - 12, accessibility: typeSize.isAccessibilitySize)
            let rows = Self.rows(list, columns: cols.count)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: WardrobeCardFace.gap) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                            HStack(alignment: .top, spacing: WardrobeCardFace.gap) {
                                ForEach(row, id: \.rawValue) { look in card(look, width: cols.card) }
                                if row.count < cols.count { ForEach(0..<(cols.count - row.count), id: \.self) { _ in Color.clear.frame(width: cols.card) } }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .id(r)
                        }
                    }
                    .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 30)
                }
                .accessibilityIdentifier("wardrobe-grid")
                .onScrollPhaseChange { _, phase in scrolling = phase != .idle }
                .task {          // capture aids (dev arguments only): `-WardrobeScroll <seconds>` scrolls the grid to its third row after that long; `-WardrobeFlick <seconds>` flicks it top to bottom three times and logs the frame times
                    let d = UserDefaults.standard
                    guard DevArgs.enabled else { return }
                    let t = d.double(forKey: "WardrobeScroll")
                    if t > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
                        withAnimation { proxy.scrollTo(min(2, rows.count - 1), anchor: .top) }
                    }
                    if let f = d.string(forKey: "WardrobeFlick").flatMap(Double.init), rows.count > 2 {
                        try? await Task.sleep(nanoseconds: UInt64(f * 1_000_000_000))
                        let probe = FrameProbe(); probe.start()
                        for _ in 0..<3 {
                            withAnimation(.linear(duration: 0.35)) { proxy.scrollTo(rows.count - 1, anchor: .bottom) }
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            withAnimation(.linear(duration: 0.35)) { proxy.scrollTo(0, anchor: .top) }
                            try? await Task.sleep(nanoseconds: 450_000_000)
                        }
                        let line = "flick prewarm=\(Self.prewarmOn) \(probe.stop())\n"
                        if let path = d.string(forKey: "WardrobeFlickLog") { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
                    }
                }
            }
        }
    }

    /// Pictures for the whole wardrobe, in the order the cards appear: the first row and the next few at once, the rest one per frame and only while nothing is being scrolled,
    /// so a flick never lands on a run of empty placeholders for long. (The mini renderer draws on the main actor between frames, so this is one picture per turn.)
    static var prewarmOn: Bool { !(DevArgs.enabled && UserDefaults.standard.string(forKey: "WardrobePrewarm") == "0") }
    private func prewarm(_ list: [WearLook]) async {
        guard Self.prewarmOn else { return }
        for (i, look) in list.enumerated() {
            guard let item = StoreCatalog.item(wearing: look), StoreThumb.wardrobeCached(item) == nil else { continue }
            if i >= 12 { while scrolling && !Task.isCancelled { try? await Task.sleep(nanoseconds: 80_000_000) } }
            if Task.isCancelled { return }
            if StoreThumb.wardrobeImage(item) != nil { WardrobePictures.shared.version += 1 }
            try? await Task.sleep(nanoseconds: i < 12 ? 2_000_000 : 17_000_000)
        }
    }
    private func card(_ look: WearLook, width: CGFloat) -> some View {
        let worn = care.store.worn(who, look.slot) == look
        let other = worn || care.store.freeCopies(look) > 0 ? nil : care.store.wearer(look, among: care.jellies.count).flatMap { $0 != who ? care.jelly($0)?.name : nil }
        let m = theme.match(look.tags)
        return Button {
            AudioHub.shared.play(.shoeOn)
            if worn { care.store.takeOff(look.slot, from: who) } else if care.store.wear(look, on: who) { care.jelly(who)?.stats.nudge([.cool: 0.02]) }
            onChange()
        } label: {
            WardrobeCardFace(look: look, tag: Self.shownTag(look, theme), match: m, worn: worn, otherName: other, width: width)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(look.title), \(look.tags.map(\.title).joined(separator: " ")), \(worn ? "worn" : "not worn")\(other.map { ", worn by \($0)" } ?? "")")
        .accessibilityIdentifier("wardrobe-\(look.rawValue)")
    }
    static func shownTag(_ look: WearLook, _ theme: ShowTheme) -> WearTag? {
        look.tags.first(where: { $0 == theme.main }) ?? look.tags.first(where: { $0 == theme.friend }) ?? look.tags.first
    }
}

/// What a Dress up card looks like (no game state: the picture loads itself from the shared mini-render cache). The picture is a square as wide as the card
/// less the padding, under it the full name (two lines reserved), the theme tag and the slot (or "Wearing" / "On <name>"), so every card has the same height.
struct WardrobeCardFace: View {
    static let gap: CGFloat = 10
    static let minWidth: CGFloat = 100
    static let pad: CGFloat = 5
    /// The name may shrink to this much of its size to stay in two lines (the test measures with it).
    static let nameScale: CGFloat = 0.85
    var look: WearLook
    var tag: WearTag?
    var match: Float
    var worn: Bool
    var otherName: String?
    var width: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize
    private var pictures = WardrobePictures.shared
    var picture: CGFloat { width - 2 * Self.pad }
    var body: some View {
        let _ = pictures.version          // redraw when a picture lands in the cache
        let image = StoreCatalog.item(wearing: look).flatMap { StoreThumb.wardrobeCached($0) }
        return VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: picture * 0.16, style: .continuous).fill(SK.pink.opacity(0.25))
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else if StoreCatalog.item(wearing: look) == nil { Image(systemName: look.slot.symbol).font(.system(size: 30, weight: .heavy)).foregroundStyle(SK.ink) }
                if worn {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 24, height: 24).background(Circle().fill(ShowUI.gold)).padding(5)
                }
            }
            .frame(width: picture, height: picture)
            Text(look.title).font(SK.font(12, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : WardrobeCardFace.nameScale)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 2, reservesSpace: true).frame(maxWidth: .infinity)
            if let tag { TagChip(tag: tag, size: 11) } else { Color.clear.frame(height: 22) }
            Text(worn ? "Wearing" : otherName.map { "On \($0)" } ?? look.slot.title).font(SK.font(11, .heavy)).foregroundStyle(worn ? ShowUI.brownGold : SK.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Self.pad)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(worn ? ShowUI.gold.opacity(0.35) : .white))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(match >= 1 ? ShowUI.gold : match >= 0.5 ? Color(hex: 0xF4D98C) : ShowUI.bar, lineWidth: match >= 1 || worn ? 3 : 2))
        .shadow(color: ShowUI.gold.opacity(match >= 1 ? 0.9 : match >= 0.5 ? 0.45 : 0), radius: match >= 1 ? 6 : 5)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: look) {
            guard let item = StoreCatalog.item(wearing: look), StoreThumb.wardrobeCached(item) == nil else { return }
            await Task.yield()          // a card that scrolled in before the sweep reached it draws its own picture, one per turn
            if StoreThumb.wardrobeImage(item) != nil { pictures.version += 1 }
        }
    }
}

/// Bumped when a Dress up picture lands in the cache, so the cards showing a placeholder redraw.
@MainActor @Observable final class WardrobePictures {
    static let shared = WardrobePictures()
    var version = 0
}

/// Frame timing for the capture aids (dev arguments only): the worst gap between two frames while it runs.
@MainActor final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var last = 0.0, worst = 0.0, frames = 0, over33 = 0
    func start() { link = CADisplayLink(target: self, selector: #selector(tick(_:))); link?.add(to: .main, forMode: .common) }
    @objc private func tick(_ l: CADisplayLink) {
        if last > 0 { let d = l.timestamp - last; worst = max(worst, d); frames += 1; if d > 0.0334 { over33 += 1 } }
        last = l.timestamp
    }
    func stop() -> String { link?.invalidate(); return "frames=\(frames) worst_ms=\(Int(worst * 1000)) over33ms=\(over33)" }
}

@MainActor
extension StoreThumb {
    /// The Dress up card's picture: the same Jelmiko-wearing-it mesh as the shop's thumbnail, drawn once per item at 360 px (about 120 pt at 3x) and framed on the item.
    static func wardrobeImage(_ item: StoreItem) -> UIImage? {
        guard let w = item.wear, let m = mesh(for: item) else { return nil }
        let a = angles(for: item)
        if w.isShoe { return image("ward-\(item.id)", mesh: m, size: 360, yaw: a.yaw, pitch: a.pitch, tight: true) }
        // hand items: a cream body, so a sky-blue band does not vanish into the blue catalogue Jelmiko
        let drawn = w.slot == .hands ? creamBody(m) : m
        return image("ward-\(item.id)", mesh: drawn, size: 360, yaw: a.yaw, pitch: a.pitch, focus: cardFocus(w, mesh: m))
    }
    static func wardrobeCached(_ item: StoreItem) -> UIImage? { cachedImage("ward-\(item.id)") }
    /// The same picture of the bare catalogue Jelmiko (no piece), framed exactly as `wardrobeImage` frames the item: for telling a piece that renders nothing from one that does.
    static func wardrobeBareImage(_ item: StoreItem) -> UIImage? {
        guard let w = item.wear, !w.isShoe, let m = mesh(for: item) else { return nil }
        let a = angles(for: item)
        let bare = w.slot == .hands ? creamBody(jelbieBody()) : jelbieBody()
        return image("wardbare-\(item.id)", mesh: bare, size: 360, yaw: a.yaw, pitch: a.pitch, focus: cardFocus(w, mesh: m))
    }
    /// The catalogue Jelmiko's body vertices recoloured cream (the eyes and the piece keep their colours).
    static func creamBody(_ m: RoomMesh) -> RoomMesh {
        let flesh = JellyRoster.palette(0)?.flesh ?? OKLab.srgbToLinear(SIMD3(0.50, 0.68, 0.95))
        let cream = OKLab.srgbToLinear(SIMD3<Float>(0.98, 0.94, 0.84))
        var out = m
        for i in 0..<min(JellyPortraitRenderer.renderMesh.vertexCount, out.vertices.count) {
            let c = out.vertices[i].color
            if simd_length(SIMD3(c.x, c.y, c.z) - flesh) < 0.002 { out.vertices[i].color = SIMD4(cream, 1) }
        }
        return out
    }
    /// (centre, radius) for the card: closer than the shop's thumbnail, then moved and widened so the whole piece is inside (a clip at the side of the head, a tall cone,
    /// a wristband on the arm). Hand items are framed on the arm nearest the camera.
    static func cardFocus(_ look: WearLook, mesh m: RoomMesh) -> (SIMD3<Float>, Float) {
        var base: (SIMD3<Float>, Float)
        switch look.slot {
        case .head: base = (SIMD3(0, 1.0, 0.05), 0.63)
        case .face: base = (SIMD3(0, 0.86, 0.30), 0.50)
        case .neck: base = look == .diamondJ ? (SIMD3(0, 0.36, 0.25), 0.40) : (SIMD3(0, 0.50, 0.2), 0.46)
        case .hands: base = (SIMD3(0, 0.45, 0.10), 0.80)
        default: let f = wornFocus(look); base = (f.0, f.1 * 0.85)
        }
        let n = jelbieBody().vertices.count
        guard m.vertices.count > n else { return base }
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in m.vertices[n...] {
            let p = SIMD3(v.pos.x, v.pos.y, v.pos.z)
                        lo = simd_min(lo, p); hi = simd_max(hi, p)
        }
        guard lo.x.isFinite else { return base }
        let mid = (lo + hi) / 2, half = (hi - lo) / 2
        if look.slot == .hands { return (mid, min(max(0.55, simd_length(half) * 1.3), 0.9)) }          // both arms
        let c = SIMD3(base.0.x + (mid.x - base.0.x) * 0.8, base.0.y + (mid.y - base.0.y) * 0.4, base.0.z + (mid.z - base.0.z) * 0.4)          // sideways almost onto the piece (a clip at the side of the head), up and back only part way
        var need: Float = 0
        for sx: Float in [-1, 1] { for sy: Float in [-1, 1] { for sz: Float in [-1, 1] {
            need = max(need, simd_length(SIMD3(mid.x + sx * half.x, mid.y + sy * half.y, mid.z + sz * half.z) - c))
        } } }
        if look.slot == .neck || look.slot == .body {          // a thin piece (a medal, a whistle, a chain) fills the picture: frame by its own width and height, not the torso's
            let off = simd_length(SIMD2(c.x - mid.x, c.y - mid.y))
            return (c, min(max(0.38, max(half.x, half.y) * 1.3 + off), 1.0))
        }
        return (c, min(max(0.58, need * 0.95), 1.3))
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
    /// Dress up opens low enough that the stage (the player's own Jelmiko wearing what they tap) stays in view above it; drag it up to browse.
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
        LobbyBottomBar(playID: "studio-show", playTitle: "Enter Jelly Show", playIcon: .star, blocked: blocker != nil, why: blocker, play: { show() })
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
        .task {          // capture aid (dev arguments only): `-WardrobeAfter <seconds>` opens Dress up that long after the Studio appears
            guard DevArgs.enabled, UserDefaults.standard.double(forKey: "WardrobeAfter") > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(UserDefaults.standard.double(forKey: "WardrobeAfter") * 1_000_000_000))
            wardrobeOpen = true
        }
        .overlay {          // Dress up is its own full screen over the lobby (not a sheet); back returns to the lobby exactly as it was
            if wardrobeOpen {
                DressUpScreen(care: care, who: who, theme: theme, rank: rank) { AudioHub.shared.uiTap(); wardrobeOpen = false }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: wardrobeOpen)
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
                HStack(spacing: 0) { themeChip(theme.main, ""); Spacer(minLength: 0); themeChip(theme.friend, "+ ") }.padding(.horizontal, 10).padding(.top, 4)          // (a chip in each top corner: nothing over his head, antennae, ears or a tall hat)
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
            LobbyStatRow(label: "Score", value: Float(fc.total) / 300, color: SK.pinkStrong, note: "about \(fc.total) of 300\nentrants about \(fc.rivals)"),
        ])], id: "studio-ready", trailing: {
            Button { AudioHub.shared.uiTap(); card() } label: { Text("\(care.rosterName(who))'s profile \u{203A}").font(SK.font(14, .heavy)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.8).frame(minHeight: 44) }
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

/// The Dress up picture: the player's own Jelmiko, whole, on the stage disc under the spotlight in what he wears now (the lobby's action shot, drawn to fill this taller area), the worn slots
/// either side of him, the theme's tags in the top corners. Its size is a fixed `height` per device and orientation, and the Jelmiko's feet always stand at `floorAt` of it, so a tall hat
/// or a tapped item never moves or rescales him.
struct DressUpFigure: View {
    let care: GameCare
    var who: Int
    var theme: ShowTheme
    var rank: ShowRank
    var height: CGFloat
    /// Where his feet (the disc top) stand in the area, as a fraction of its height; the picture is as tall as the area, so the room above is the 0.42-of-his-height the renderer leaves for hats.
    static let floorAt: CGFloat = 0.87
    /// The picture is this much of the area's height (a margin of about 3% above the tallest hat in the catalogue, the party cone, and the disc's front rim kept inside the area).
    static let fill: CGFloat = 0.94
    private func chip(_ t: WearTag, _ prefix: String) -> some View {
        Text("\(prefix)\(t.title)").font(SK.font(12, .black)).foregroundStyle(SK.ink).padding(.horizontal, 9).frame(minHeight: 22).background(Capsule().fill(ShowUI.tag(t)))
    }
    private func column(_ slots: [WearSlot], _ outfit: [WearSlot: WearLook]) -> some View {
        VStack(spacing: 10) {
            ForEach(slots, id: \.rawValue) { s in SlotChip(slot: s, look: outfit[s], theme: theme, caption: false) { if let l = outfit[s] { care.store.takeOff(l.slot, from: who) } } }
        }
        .frame(width: 56)
    }
    var body: some View {
        let outfit = care.store.outfit(who)
        let slots = rank.slotOrder
        let left = Array(slots.prefix((slots.count + 1) / 2)), right = Array(slots.dropFirst((slots.count + 1) / 2))
        let wearing = rank.slotOrder.compactMap { outfit[$0]?.title } + outfit.filter { !rank.slotOrder.contains($0.key) }.map { $0.value.title }
        ZStack {
            StageBackdrop()
            JelbieActionShot(care: care, who: who, fill: Self.fill, floorAt: Self.floorAt, spinner: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(care.rosterName(who))\(wearing.isEmpty ? ", wearing nothing" : ", wearing \(wearing.joined(separator: " and "))")")
            HStack(spacing: 0) {
                column(left, outfit); Spacer(minLength: 0); column(right, outfit)
            }
            .padding(.horizontal, 14)
            VStack {
                HStack(spacing: 0) { chip(theme.main, ""); Spacer(minLength: 0); chip(theme.friend, "+ ") }.padding(.horizontal, 10).padding(.top, 8)
                Spacer()
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain).accessibilityIdentifier("dressup-figure")
    }
}

/// Dress up, its own full screen (not a sheet): over the lobby, with the lobby's back arrow. The Jelmiko in what he wears fills a pinned picture at the top (feet always in view, see
/// `DressUpFigure`), the one-line rule and the hint under it, and below that the filter chips and a grid of cards that scrolls on its own. Landscape and iPad: the picture on the leading
/// side at full height, the chips and the grid on the trailing side. What a tap does is the same as ever: it puts the item on / takes it off (the Studio's show-outfit rule sits in the Town).
struct DressUpScreen: View {
    let care: GameCare
    var who: Int
    var theme: ShowTheme
    var rank: ShowRank
    var close: () -> Void
    @State private var slot: WearSlot?
    @Environment(\.horizontalSizeClass) private var hsc
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The picture area's height in a stacked (portrait phone) layout: a fixed share of the room, more of it on a tall phone, less on a short one so a full row of cards still shows under it.
    static func figureHeight(containerHeight h: CGFloat) -> CGFloat { (h * (h < 700 ? 0.38 : 0.44)).rounded() }
    static func isSplit(width: CGFloat, height: CGFloat, hSize: UserInterfaceSizeClass?, vSize: UserInterfaceSizeClass?) -> Bool { vSize == .compact || hSize == .regular || width > height * 1.2 }

    private var rule: some View {
        VStack(spacing: 2) {
            Text("\(rank.title) rank scores \(rank.slots) slots: \(rank.slotOrder.map { $0.title }.joined(separator: ", ")). Gold = matches \(theme.main.title).")
                .font(SK.font(12, .bold)).foregroundStyle(ShowUI.lilacPale).multilineTextAlignment(.center).lineLimit(typeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.8)
            Text("Tap a worn slot to take it off.").font(SK.font(11, .bold)).foregroundStyle(ShowUI.lilac)
        }
        .frame(maxWidth: .infinity)
    }
    private var chips: some View {
        WardrobeFilterChips(slot: $slot, slots: WearSlot.allCases.filter { s in StoreCatalog.items.contains { $0.wear?.slot == s && care.store.owns($0) } })
    }
    private var grid: some View {
        WardrobeStrip(care: care, who: who, theme: theme, slots: slot.map { [$0] }).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var header: some View { ShowHeader(title: "Dress up", light: true, backID: "dressup-back", back: close) { EmptyView() } }

    var body: some View {
        GeometryReader { g in
            Group {
                if Self.isSplit(width: g.size.width, height: g.size.height, hSize: hsc, vSize: vsc) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 6) {
                            header
                            DressUpFigure(care: care, who: who, theme: theme, rank: rank, height: max(160, g.size.height - 52 - 56 - 16))
                            rule
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 8) { chips; grid }.frame(width: min(430, g.size.width * 0.46))
                    }
                } else {
                    VStack(spacing: 6) {
                        header
                        DressUpFigure(care: care, who: who, theme: theme, rank: rank, height: Self.figureHeight(containerHeight: g.size.height))
                        rule
                        chips
                        grid
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4)
        }
        .background(ShowUI.hall.ignoresSafeArea())
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("dressup-screen")
        .task {          // capture aids (dev arguments only): `-WardrobeSlot <head|feet|...>` starts on that filter; `-WardrobeWear <look,look>` puts those on (a tap each)
            guard DevArgs.enabled else { return }
            if let raw = UserDefaults.standard.string(forKey: "WardrobeSlot"), let s = WearSlot(rawValue: raw) { slot = s }
            if let raw = UserDefaults.standard.string(forKey: "WardrobeWear") {
                for name in raw.split(separator: ",") { if let l = WearLook(rawValue: String(name)) { care.store.grant(StoreCatalog.item(wearing: l)?.id ?? ""); _ = care.store.wear(l, on: who) } }
            }
        }
    }
}

/// The filter chips (All + one per slot with goods): the same look as the Shop's, but the row starts at the sheet's side margin and only scrolls when it must.
struct WardrobeFilterChips: View {
    @Binding var slot: WearSlot?
    var slots: [WearSlot]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", symbol: "square.grid.2x2.fill", on: slot == nil, id: "all") { slot = nil }
                ForEach(slots, id: \.rawValue) { s in chip(s.title, symbol: s.symbol, on: slot == s, id: s.rawValue) { slot = s } }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .frame(height: 44)
        .accessibilityIdentifier("wardrobe-slot-chips")
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
        .buttonStyle(.plain).accessibilityIdentifier("wardrobe-slot-\(id)").accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Condition (the Jelly Jars)

struct ConditionScreen: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var show: () -> Void
    var bath: (() -> Void)? = nil
    /// Starts the normal Feed flow (closes this screen and opens the Feed picker); nil = no Feed button action.
    var feed: (() -> Void)? = nil
    /// Same for the Drink picker (the jar card shows the button only when an owned drink fills the jar).
    var drink: (() -> Void)? = nil
    /// The old jars card on its own, as the sheet the Profile's "Jelly Show styles" row opens (no header, pills, Trophies row or Show button; a close button instead).
    var sheetMode = false
    @Environment(\.verticalSizeClass) private var vsc
    @State private var jarOpen: WearTag?
    @State private var trophiesOpen = false
    /// The jars fill from 0 to their level over 0.6 s when the card appears (and from the previous level after a meal).
    @State private var grown = false
    private var compact: Bool { vsc == .compact }

    var body: some View {
        let p = care.jelly(who)
        if sheetMode {
            VStack(spacing: 10) {
                HStack {
                    Text("Jelly Show styles").font(SK.font(22, .black)).foregroundStyle(SK.ink).jLine(1, scale: 0.7)
                    Spacer()
                    Button { AudioHub.shared.uiTap(); back() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                        .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("styles-close")
                }
                if care.jellies.count > 1 { WhoRow(care: care, who: $who) }
                ScrollView(showsIndicators: false) { jars(p) }.scrollBounceBehavior(.basedOnSize)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 14)
            .accessibilityIdentifier("condition-styles-sheet")
            .onAppear { grown = false; withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.15)) { grown = true } }
            .sheet(item: $jarOpen) { t in ConditionJarCard(care: care, who: who, tag: t, feed: feed, drink: drink, close: { jarOpen = nil }).presentationDetents([.medium, .large]).presentationBackground(SK.cream) }
        } else {
        VStack(spacing: compact ? 8 : 12) {
            ShowHeader(title: "Condition", light: false, backID: "condition-back", back: back) { EmptyView() }
            if care.jellies.count > 1 { WhoRow(care: care, who: $who) }
            if compact {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView(showsIndicators: false) { jars(p) }.scrollBounceBehavior(.basedOnSize).frame(maxWidth: .infinity)
                    VStack(spacing: 10) {
                        ScrollView(showsIndicators: false) { glowBlock(p).padding(12).background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.cream)) }.scrollBounceBehavior(.basedOnSize)
                        rows(p)
                        ShowCTA(title: "See today's Jelly Show", id: "condition-show", height: 54) { show() }
                    }
                    .frame(width: 300)
                }
            } else {
                ScrollView(showsIndicators: false) { jars(p) }.scrollBounceBehavior(.basedOnSize)
                rows(p)
                ShowCTA(title: "See today's Jelly Show", id: "condition-show", height: 56) { show() }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(ShowUI.sand.ignoresSafeArea())
        .accessibilityIdentifier("condition-screen")
        .onAppear { grown = false; withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.15)) { grown = true } }
        .onChange(of: who) { _, _ in grown = false; withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.1)) { grown = true } }
        .sheet(item: $jarOpen) { t in ConditionJarCard(care: care, who: who, tag: t, feed: feed, drink: drink, close: { jarOpen = nil }).presentationDetents([.medium, .large]).presentationBackground(SK.cream) }
        .sheet(isPresented: $trophiesOpen) { TrophiesSheet(care: care, who: who) { trophiesOpen = false }.presentationDetents([.medium, .large]).presentationBackground(SK.cream) }
        .task {          // capture aid (dev arguments only): `-CondJar cute|sweet|sparkly|cool|sporty` opens that jar's card
            guard DevArgs.enabled, let raw = UserDefaults.standard.string(forKey: "CondJar"), let t = WearTag(rawValue: raw) else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            jarOpen = t
        }
        }
    }

    /// The last meal within half an hour: what it raised ("+1" droplets) and its name ("Just fed").
    private func lastMeal(_ p: JellyProfile?) -> MealEntry? {
        guard let m = p?.stats.meals.first, Date().timeIntervalSince(m.date) < 1800 else { return nil }
        return m
    }

    private func jars(_ p: JellyProfile?) -> some View {
        let name = care.rosterName(who)
        let meal = lastMeal(p)
        let levels = WearTag.jarOrder.map { p?.stats.condition($0.condition) ?? 0 }
        let target = ShowUI.target(after: care.show.progress.unlockedRanks)
        let theme: ShowTheme? = ShowSchedule.theme(dayKey: GameCare.showDay)
        let last = WearTag.jarOrder.count - 1
        return VStack(spacing: 8) {
            HStack(alignment: .top) { VStack(alignment: .leading, spacing: 2) {
                Text("\(name)'s jelly jars").font(SK.font(18, .black)).foregroundStyle(SK.ink)
                Text(ConditionGuide.subtitle).font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if compact, let meal { fedChip(meal) } }
            if !compact, let meal { HStack { fedChip(meal); Spacer() } }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(WearTag.jarOrder.enumerated()), id: \.offset) { i, t in
                    let v = levels[i]
                    let gain = meal?.gains[t.condition.rawValue] ?? 0
                    let today = ConditionGuide.todayTag(t, theme: theme)
                    let quiet = theme != nil && today == nil
                    Button { AudioHub.shared.uiTap(); jarOpen = t } label: {
                        JellyJar(tag: t, level: grown ? v : max(0, v - gain), previous: max(0, v - gain), grew: gain > 0.004 && grown, target: target?.level, targetTag: i == last ? target?.rank.title : nil, dim: quiet ? 0.6 : 1, number: ShowUI.pts(v))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ConditionGuide.jarLabel(t, number: ShowUI.pts(v), today: today, grew: gain > 0.004 && grown))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("jar-\(t.rawValue)")
                }
            }
            .frame(height: compact ? 125 : 320)
            HStack(alignment: .top, spacing: 8) {
                ForEach(WearTag.jarOrder, id: \.rawValue) { t in
                    let today = ConditionGuide.todayTag(t, theme: theme)
                    VStack(spacing: 3) {
                        Text(t.title).font(SK.font(13, .black)).foregroundStyle(SK.ink).jLine(1, scale: 0.7).frame(maxWidth: .infinity, minHeight: 28).background(Capsule().fill(ShowUI.tag(t)))
                        Text(today ?? " ").font(SK.font(11, .black)).foregroundStyle(ShowUI.brownGold).jLine(1, scale: 0.6)
                            .padding(.horizontal, today == nil ? 0 : 6).padding(.vertical, 1).background(Capsule().fill(today == nil ? Color.clear : ShowUI.gold))
                            .accessibilityHidden(true)
                    }
                    .opacity(theme != nil && today == nil ? 0.6 : 1)
                }
            }
            if !compact || sheetMode { glowBlock(p) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.12), radius: 6, y: 2))
        .accessibilityElement(children: .contain).accessibilityIdentifier("condition-jars")
    }

    private func fedChip(_ meal: MealEntry) -> some View {
        Text("Just fed: \(meal.food)").font(SK.font(13, .black)).foregroundStyle(ShowUI.brownGold).padding(.horizontal, 12).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xFFE7A8))).accessibilityIdentifier("condition-fed")
    }
    /// The Glow row (plain words and the Bath button), its caption and the drain line. Under the jars in portrait; in the right column in landscape.
    private func glowBlock(_ p: JellyProfile?) -> some View {
        let glow = p?.grime.sparkle ?? 0
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill").font(.system(size: 14, weight: .black)).foregroundStyle(SK.skyDeep).accessibilityHidden(true)
                Text("Fresh bath sparkle: \(ConditionGuide.glowWord(glow))").font(SK.font(14, .black)).foregroundStyle(Color(hex: 0x2F6F8C)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("condition-glow-word")
                Spacer(minLength: 4)
                Button { AudioHub.shared.uiTap(); bath?() } label: {
                    Text("Bath").font(SK.font(13, .black)).foregroundStyle(Color(hex: 0x2F6F8C)).padding(.horizontal, 14).frame(minHeight: 36).background(Capsule().fill(.white))
                }
                .buttonStyle(.plain).disabled(bath == nil || !care.canClean(jelly: who))
                .accessibilityLabel("Bath. Fresh bath sparkle is \(ConditionGuide.glowWord(glow))").accessibilityIdentifier("condition-glow")
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 4).frame(minHeight: 44).background(Capsule().fill(Color(hex: 0xDDEFF6)))
            Text(ConditionGuide.glowCaption).font(SK.font(11, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(ConditionGuide.drainLine).font(SK.font(11, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("condition-drain")
        }
    }

    private func rows(_ p: JellyProfile?) -> some View {
        let t = care.show.progress.trophies(character: p?.character ?? who)
        let ribbons = care.race.trophies.shelf(character: p?.character ?? who).raceRibbonCount          // (race ribbons: Trophies/)
        return VStack(spacing: 8) {
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
    /// The rank's name on a small gold tag at the end of the dashed line (drawn on one jar only).
    var targetTag: String? = nil
    /// A quieter jar (not one of today's two styles).
    var dim: Double = 1
    var number: Int
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let top = h * 0.095, bottom = h * 0.97, inner = bottom - top
            let y = bottom - inner * CGFloat(min(max(level, 0), 1))
            let yp = bottom - inner * CGFloat(min(max(previous, 0), 1))
            let c = ShowUI.tag(tag)
            ZStack(alignment: .top) {
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
                Text("\(number)").font(SK.font(w * 0.34, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                    .frame(width: w * 0.72, height: h * 0.12)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0xFBF6EA)).overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SK.ink.opacity(0.3), lineWidth: 1.5)))
                    .offset(y: bottom - h * 0.17)
            }.opacity(dim)
            if let target, let targetTag {
                Text(targetTag).font(.system(size: 10, weight: .black)).foregroundStyle(ShowUI.brownGold).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(ShowUI.gold)).position(x: w * 0.9 - min(w * 0.4, 24), y: bottom - inner * CGFloat(target) - 9)
            }
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

/// The trophy cabinet (trophy-look-r1): a section per event (Jelly Show, Jelly Race, Jelly Volleyball), each a few rows of big coloured icons (Trophies/TrophyCabinet.swift), earned ones in full
/// colour and the rest faint, with only a one-word label under each. Show: a cup per rank, a rosette per theme stat, the four stickers as round badges.
struct TrophiesSheet: View {
    let care: GameCare
    var who: Int
    var close: () -> Void
    var body: some View {
        let t = care.show.progress.trophies(character: care.jelly(who)?.character ?? who)
        let shelf = care.race.trophies.shelf(character: care.jelly(who)?.character ?? who)
        let any = t.cupCount > 0 || !t.rosettes.isEmpty || !t.stickers.isEmpty || shelf.raceRibbonCount > 0 || !shelf.earned.isEmpty || shelf.volleyTotal > 0
        ScrollView(showsIndicators: false) { VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(care.rosterName(who))'s trophies").font(SK.font(26, .black)).foregroundStyle(SK.ink)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundStyle(SK.ink).frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.85))) }
                    .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("trophies-close")
            }
            TrophyCaseToggle(care: care)
            CabinetSection(title: "Jelly Show", symbol: "star.fill", tint: Color(hex: 0xA77BEA), identifier: "show-trophies") {
                CabinetRow {
                    ForEach(ShowRank.allCases, id: \.rawValue) { r in
                        let place = t.cup(r)
                        let tone: CabinetTone = [CabinetTone.bronze, .silver, .gold, .rainbow][min(r.index, 3)]
                        CabinetTile(label: r.title, earned: place != nil, place: place ?? 0, glow: tone.base, a11y: place.map { "\(r.title) cup, \(ShowUI.ordinal($0)) place" } ?? "\(r.title) cup, not yet", id: "cup-\(r.rawValue)") { CabinetCup(tone: tone) }
                    }
                }
                CabinetRow {
                    ForEach(WearTag.jarOrder, id: \.rawValue) { tag in
                        let has = t.hasRosette(tag)
                        CabinetTile(label: tag.title, earned: has, glow: ShowUI.tag(tag), a11y: has ? "\(tag.title) rosette, earned" : "\(tag.title) rosette, not yet", id: "rosette-\(tag.rawValue)") {
                            CabinetRosette(base: ShowUI.tag(tag), symbol: "star.fill")
                        }
                    }
                }
                CabinetRow {
                    ForEach(ShowProgress.Sticker.allCases, id: \.rawValue) { s in
                        let has = t.stickers.contains(s.rawValue)
                        let look = Self.look(s)
                        CabinetTile(label: look.word, earned: has, locked: true, glow: look.color, a11y: has ? "\(s.title) sticker, earned" : "\(s.title) sticker, not yet", id: "sticker-\(s.rawValue)") {
                            CabinetBadge(color: look.color, symbol: look.symbol)
                        }
                    }
                }
            }
            RaceTrophiesSection(care: care, who: who)          // (race rosettes and milestone badges: Trophies/)
            VolleyTrophiesSection(care: care, who: who)          // (beach volleyball rosettes and badges: Volley/)
            if !any { Text("Win a Show, a race or a match to fill the cabinet.").font(SK.font(13, .bold)).foregroundStyle(SK.muted).frame(maxWidth: .infinity) }
        }
        .frame(maxWidth: 520).frame(maxWidth: .infinity) }
        .padding(16)
        .accessibilityIdentifier("trophies-sheet")
    }
    /// A sticker's round badge: its colour, its symbol and its one-word label (its full title is in the VoiceOver label).
    private static func look(_ s: ShowProgress.Sticker) -> (color: Color, symbol: String, word: String) {
        switch s {
        case .firstShow: return (Color(hex: 0xF5B82E), "star.fill", "First")
        case .perfectDance: return (Color(hex: 0xEE5FA0), "music.note", "Dance")
        case .glowBurst: return (Color(hex: 0x2FB6C8), "sparkles", "Glow")
        case .hatTrick: return (Color(hex: 0x8B5CD6), "medal.fill", "Hat-trick")
        }
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
