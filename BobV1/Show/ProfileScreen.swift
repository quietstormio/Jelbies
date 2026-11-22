//
//  ProfileScreen.swift
//  The Profile of a Jelmiko (replaces the "Condition" screen the circled close-up button and the Studio's card link used to open): a head picture, the name and
//  kind, ONE plain sentence on how they are (the same words Siri and the Lock Screen say: Shared/JellyStatus.swift), the RELATIONSHIP (five hearts that fill partly + a level name; Jelly/JellyBond.swift), four status chips
//  (food, water, clean, sleep), the favourites the save really holds, the trophies, and "See today's Jelly Show". No meters with numbers: the old jelly jars
//  are one small row at the bottom ("Jelly Show styles") that opens the old jars card (ConditionScreen in `sheetMode`).
//

import SwiftUI

/// The words of the status chips: pure functions of the projected state and the clock hour (tested by eye in the real app; no gameplay values here).
enum ProfileWords {
    enum Tone { case good, soon, needs }

    struct Chip: Equatable {
        var title: String, value: String, icon: String, tone: Tone
    }

    /// Food or water: Full / Not hungry / Peckish / Hungry / Very hungry (water: Quenched / Not thirsty / A little thirsty / Thirsty / Very thirsty).
    /// Tiers are the game's own (`NeedTier`); a Normal need under the "happy" line reads as coming up, so the chip is never green while the sentence names it.
    static func need(_ s: JellyState, _ c: JellyCare) -> Chip {
        let drink = c == .water
        let level = s.level(c), tier = s.tier(c)
        let icon = drink ? "drop.fill" : "fork.knife", title = drink ? "Water" : "Food"
        switch tier {
        case .full: return Chip(title: title, value: drink ? "Quenched" : "Full", icon: icon, tone: .good)
        case .normal:
            if level >= NeedsTuning.happy { return Chip(title: title, value: drink ? "Not thirsty" : "Not hungry", icon: icon, tone: .good) }
            return Chip(title: title, value: drink ? "A little thirsty" : "Peckish", icon: icon, tone: .soon)
        case .hungry: return Chip(title: title, value: drink ? "Thirsty" : "Hungry", icon: icon, tone: .needs)
        case .famished: return Chip(title: title, value: drink ? "Very thirsty" : "Very hungry", icon: icon, tone: .needs)
        }
    }

    static func clean(_ s: JellyState) -> Chip {
        switch s.coat {
        case .beautiful: return Chip(title: "Clean", value: "Sparkling clean", icon: "bubbles.and.sparkles.fill", tone: .good)
        case .clean, .normal: return Chip(title: "Clean", value: "Clean", icon: "bubbles.and.sparkles.fill", tone: .good)
        case .dirty: return Chip(title: "Clean", value: "A bit grubby", icon: "bubbles.and.sparkles.fill", tone: .soon)
        case .filthy: return Chip(title: "Clean", value: "Needs a bath", icon: "bubbles.and.sparkles.fill", tone: .needs)
        }
    }

    /// Sleep from the shared sleeping hours (`SleepHours`, the lock screen card's rule) on the game clock hour.
    static func sleep(asleep: Bool, hour: Double) -> Chip {
        let night = SleepHours.isNight(hour: hour)
        if asleep {
            if night { return Chip(title: "Sleep", value: "Asleep \u{00B7} up around \(clock(wakeHour(after: hour), round: 30))", icon: "moon.zzz.fill", tone: .good) }
            return Chip(title: "Sleep", value: "Napping", icon: "moon.zzz.fill", tone: .good)
        }
        if night { return Chip(title: "Sleep", value: "Sleepy", icon: "moon.fill", tone: .soon) }
        if DayMath.wrap(hour) >= 17 { return Chip(title: "Sleep", value: "Bedtime around \(clock(bedHour(after: hour), round: 10))", icon: "moon.stars.fill", tone: .good) }
        return Chip(title: "Sleep", value: "Awake", icon: "sun.max.fill", tone: .good)
    }

    /// The hour the night they are in (or the next one) ends, in whole minutes after `hour` (may pass 24).
    static func wakeHour(after hour: Double) -> Double {
        var t = hour, n = 0
        while !SleepHours.isNight(hour: DayMath.wrap(t)), n < 36 * 60 { t += 1.0 / 60; n += 1 }
        n = 0
        while SleepHours.isNight(hour: DayMath.wrap(t)), n < 36 * 60 { t += 1.0 / 60; n += 1 }
        return t
    }
    /// The hour the next night begins.
    static func bedHour(after hour: Double) -> Double {
        var t = hour, n = 0
        while !SleepHours.isNight(hour: DayMath.wrap(t)), n < 36 * 60 { t += 1.0 / 60; n += 1 }
        return t
    }
    /// The Profile's short status line (Siri and the widget keep `JellyStatus.sentence`): no needs / one need = the full sentence; two or more = "Berry needs you: hungry and thirsty."
    /// (at most two reasons, the most urgent first; the Right now chips show the rest).
    static func shortStatus(_ s: JellyState, sleeping: Bool, night: Bool) -> String {
        let needy = JellyCare.allCases.filter { s.tier($0).rawValue >= NeedTier.hungry.rawValue }
        guard needy.count >= 2 else { return JellyStatus.sentence(s, sleeping: sleeping, night: night).replacingOccurrences(of: " Still dozing, though.", with: "") }          // never three lines
        let worst = needy.sorted { a, b in
            let ta = s.tier(a).rawValue, tb = s.tier(b).rawValue
            return ta != tb ? ta > tb : s.level(a) < s.level(b)
        }.prefix(2).map { c -> String in
            switch c {
            case .food: return "hungry"
            case .water: return "thirsty"
            case .heart: return "lonely"
            case .soap: return "dirty"
            }
        }
        return "\(s.name) needs you: \(worst.joined(separator: " and "))."
    }
    /// "7 AM", "8:20 PM": rounded to `round` minutes.
    static func clock(_ h: Double, round step: Int) -> String {
        let total = Int((DayMath.wrap(h) * 60 / Double(step)).rounded()) * step
        let m = total % 60, hh = (total / 60) % 24
        let h12 = hh % 12 == 0 ? 12 : hh % 12
        return m == 0 ? "\(h12) \(hh < 12 ? "AM" : "PM")" : "\(h12):\(String(format: "%02d", m)) \(hh < 12 ? "AM" : "PM")"
    }
}

/// One trophy chip on the Profile. `entry` = the same real mini render the Trophy Shelf card draws (TrophyEntry.picture); the symbol is only the fallback.
private struct ProfileTrophyChip: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let caption: String
    let date: String?
    var entry: TrophyEntry? = nil
}

/// The tones of the status chips (shared by the Right now card and the tests).
enum ProfileTone {
    static let good = (bg: Color(hex: 0xDDF1E1), fg: Color(hex: 0x2F7A4A))
    static let soon = (bg: Color(hex: 0xFFEBB0), fg: Color(hex: 0x8A5A00))
    static let needs = (bg: Color(hex: 0xFAD3DC), fg: Color(hex: 0xB03A5B))
    static func of(_ t: ProfileWords.Tone) -> (bg: Color, fg: Color) { t == .good ? good : t == .soon ? soon : needs }
}

/// THE PAGE HAS A FIXED SKELETON: every text slot below reserves its worst-case height, so the cards never move between Jelmiko or states.
/// A text slot that must fit the longest of several texts: invisible copies of all of them set the height (and the ideal width), the real text sits on top.
struct ProfileRulerText: View {
    let text: String
    let ruler: [String]
    var font: Font
    var color: Color = SK.ink
    var lineSpacing: CGFloat = 0
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(ruler.enumerated()), id: \.offset) { _, t in
                Text(t).font(font).lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true).hidden().accessibilityHidden(true)
            }
            Text(text).font(font).foregroundStyle(color).lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Every description paragraph of every skin and colour variant (the worst case the paragraph slot reserves).
enum ProfileRuler {
    static let paragraphs: [String] = {
        var out: [String] = []
        for (look, v) in SkinAbout.looks.sorted(by: { $0.key < $1.key }) {
            out.append(v.colour + " " + v.character)
            for c in (SkinAbout.variants[look] ?? [:]).values { out.append(c + " " + v.character) }
        }
        for look in 0...3 { for c in SkinAbout.legacy.values { out.append(c + " " + (SkinAbout.looks[look]?.character ?? "")) } }          // the old exclusive colours: only the four starters can wear them
        return out
    }()
}

/// The description paragraph slot: always as tall as the longest paragraph of any skin.
struct ProfileParagraph: View {
    let text: String
    var body: some View {
        ProfileRulerText(text: text, ruler: ProfileRuler.paragraphs, font: SK.font(15, .bold), lineSpacing: 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, -3)          // line-box trim: the card rhythm is measured to the letters
    }
}

/// The status sentence slot: always two lines of space (a one-line sentence sits on the first line).
struct ProfileStatus: View {
    let text: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("A\nA").font(SK.font(18, .black)).lineSpacing(2).hidden().accessibilityHidden(true)          // two lines of space, line spacing included
            Text(text).font(SK.font(18, .black)).foregroundStyle(SK.ink).lineSpacing(2).lineLimit(2)
        }
        .padding(.top, -4).padding(.bottom, -3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One "Right now" chip: the same size always (the value reserves two lines).
struct ProfileChipView: View {
    let chip: ProfileWords.Chip
    var body: some View {
        let tone = ProfileTone.of(chip.tone)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: chip.icon).font(.system(size: 17, weight: .black)).foregroundStyle(tone.fg).frame(width: 26, height: 34).accessibilityHidden(true)          // beside the first line, not the middle of the reserved space
            VStack(alignment: .leading, spacing: 0) {
                Text(chip.title).font(SK.font(11, .heavy)).foregroundStyle(tone.fg.opacity(0.8)).textCase(.uppercase).lineLimit(1)
                Text(chip.value).font(SK.font(15, .black)).foregroundStyle(SK.ink).lineLimit(2, reservesSpace: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tone.bg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chip.title): \(chip.value)")
        .accessibilityIdentifier("profile-chip-\(chip.title.lowercased())")
    }
}

/// A value text for a Favourites row: always `lines` lines of space.
struct ProfileFavText: View {
    let text: String
    var lines = 1
    var body: some View { Text(text).font(SK.font(16, .black)).foregroundStyle(SK.ink).lineLimit(lines, reservesSpace: true) }
}

/// One "Favourites" row: the same height always (the value is one fixed-height line, or reserves two lines: `ProfileFavText`).
struct ProfileFavRow<Icon: View, Value: View>: View {
    let title: String
    @ViewBuilder var value: () -> Value
    @ViewBuilder var icon: () -> Icon
    var body: some View {
        HStack(spacing: 10) {
            icon().frame(width: 48, height: 48).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(SK.font(11, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase).lineLimit(1)
                value()
            }
            Spacer(minLength: 0)
        }
    }
}

/// The two tags under the name ("Blush", "Sleepy type"): ONE row, always, for every kind name x every type name. The row picks the roomiest of four looks that holds the WIDEST
/// kind next to the WIDEST type (invisible rulers), so the choice, and so the height, is the same for every Jelmiko: full words, then without the word "type", then smaller, then without icons.
struct ProfileTagRow: View {
    let kind: String?
    let type: String?
    var typeIcon = "sparkles"
    static let kinds: [String] = SpeciesInfo.all.map(\.name)
    static let types: [String] = JellyPersonality.allCases.map(\.title)

    private func chip(_ icon: String, _ color: Color, _ text: String, size: CGFloat, icons: Bool) -> some View {
        HStack(spacing: 4) {
            if icons { Image(systemName: icon).font(.system(size: size - 2, weight: .black)).foregroundStyle(color).accessibilityHidden(true) }
            Text(text).font(SK.font(size, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
        }
        .padding(.horizontal, icons ? 10 : 9).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    private func row(_ k: String?, _ t: String?, size: CGFloat, icons: Bool, word: Bool) -> some View {
        HStack(spacing: 6) {
            if let k { chip("sparkles", ShowUI.goldDeep, k, size: size, icons: icons).accessibilityElement(children: .combine).accessibilityIdentifier("profile-kind") }
            if let t { chip(typeIcon, SK.pink, word ? "\(t) type" : t, size: size, icons: icons).fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                .accessibilityElement(children: .combine).accessibilityLabel("\(t) type").accessibilityIdentifier("profile-type") }
        }
    }

    private func tier(size: CGFloat, icons: Bool, word: Bool) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 6) {          // the ruler: the widest kind, the widest type
                ZStack(alignment: .leading) { ForEach(Self.kinds, id: \.self) { chip("sparkles", .clear, $0, size: size, icons: icons) } }
                ZStack(alignment: .leading) { ForEach(Self.types, id: \.self) { chip(typeIcon, .clear, word ? "\($0) type" : $0, size: size, icons: icons) } }
            }
            .hidden().accessibilityHidden(true)
            row(kind, type, size: size, icons: icons, word: word)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tier(size: 15, icons: true, word: true)
            tier(size: 15, icons: true, word: false)
            tier(size: 13, icons: true, word: false)
            tier(size: 13, icons: false, word: false)
        }
    }
}

/// The power-ups line: names only, soonest to end first, on ONE line ("Full belly, Tidy, Cozy +1 more"; "None right now").
struct ProfilePerkNames: View {
    let names: [String]
    var body: some View {
        if names.isEmpty { Text("None right now").font(SK.font(16, .black)).foregroundStyle(SK.muted).lineLimit(1) }
        else {
            ViewThatFits(in: .horizontal) {
                ForEach(Array((1...names.count).reversed()), id: \.self) { n in
                    Text(names.prefix(n).joined(separator: ", ") + (n < names.count ? " +\(names.count - n) more" : ""))
                        .font(SK.font(16, .black)).foregroundStyle(SK.ink).lineLimit(1)
                }
            }
        }
    }
}

/// The Relationship row: label, five hearts (the current one fills partly, bottom up), the level name under them. When a heart fills while this is on screen it pops
/// (no pop under Reduce Motion, and none on first appearance or when another Jelmiko is picked: the view is re-made per Jelmiko with `.id`).
struct BondHeartsRow: View {
    let level: BondLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped: Int? = nil
    private static let box = CGSize(width: 19, height: 17)

    var body: some View {
        let label = Text("Relationship").font(SK.font(13, .heavy)).foregroundStyle(SK.muted)
        let hearts = HStack(spacing: 1) { ForEach(0..<BondTuning.hearts, id: \.self) { i in heart(i) } }
        let name = ProfileRulerText(text: level.name, ruler: BondTuning.levelNames, font: SK.font(14, .black)).accessibilityIdentifier("profile-relationship-level")          // as wide / tall as the longest stage name: the line breaks the same for every Jelmiko
        return ViewThatFits(in: .horizontal) {          // one line when it fits; the stage name wraps under only at large text sizes
            HStack(spacing: 6) { label; hearts; name; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 2) { HStack(spacing: 8) { label; hearts; Spacer(minLength: 0) }; name }
            VStack(alignment: .leading, spacing: 2) { label; hearts; name }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.spoken)
        .accessibilityIdentifier("profile-hearts")
        .onChange(of: level.hearts) { old, new in
            guard new > old, !reduceMotion else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { popped = new - 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { withAnimation(.easeOut(duration: 0.2)) { popped = nil } }
        }
    }

    private func heart(_ i: Int) -> some View {
        let f = level.fill(i)
        return ZStack {
            Image(systemName: "heart.fill").resizable().scaledToFit().foregroundStyle(SK.pink.opacity(0.22))
            Image(systemName: "heart.fill").resizable().scaledToFit().foregroundStyle(SK.pink)
                .mask(alignment: .bottom) { Rectangle().frame(height: Self.box.height * f) }          // a true partial fill, bottom up (the heart glyph is not swapped for a half-heart)
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .scaleEffect(popped == i ? 1.4 : 1)
        .accessibilityHidden(true)
    }
}

struct ProfileScreen: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    var show: () -> Void
    var bath: (() -> Void)? = nil
    var feed: (() -> Void)? = nil
    var drink: (() -> Void)? = nil
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var dts
    @State private var trophiesOpen = false
    @State private var stylesOpen = false
    private var compact: Bool { vsc == .compact }

    /// Capture aid (dev arguments only): `-ProfileTypeSample Gentle` shows that personality word on every Jelmiko (roster arguments make Jelmiko without a personality).
    private static var typeSample: String? {
        guard DevArgs.enabled, let t = UserDefaults.standard.string(forKey: "ProfileTypeSample"), !t.isEmpty else { return nil }
        return t
    }
    /// The living line about the pet's life (one short sentence, at most two lines; another worker feeds it). Nil = the slot is hidden. `-ProfileLatelySample 1` (dev arguments only) fills it with a sample.
    private static func lately(_ f: Facts) -> String? {
        if DevArgs.enabled, UserDefaults.standard.integer(forKey: "ProfileLatelySample") != 0 { return "Berry plays most with Latte, and an ice pop is her favourite treat." }
        return nil
    }


    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            ShowHeader(title: "Profile", light: false, backID: "condition-back", back: back) { EmptyView() }
            if care.jellies.count > 1 { WhoRow(care: care, who: $who, heads: true) }
            ScrollViewReader { proxy in
            TimelineView(.periodic(from: .now, by: 3)) { _ in
                let facts = Facts(care: care, who: who)
                if compact {
                    ScrollView(showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 12) { whoCard(facts); rightNowCard(facts) }.frame(maxWidth: .infinity)
                            VStack(spacing: 12) { favouritesCard(facts); trophiesCard(); stylesRow }.frame(maxWidth: .infinity)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) { whoCard(facts); rightNowCard(facts); favouritesCard(facts); trophiesCard(); stylesRow }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .task {          // capture aid (dev arguments only): `-ProfileScroll 1` scrolls the trophies card into view
                guard DevArgs.enabled, UserDefaults.standard.integer(forKey: "ProfileScroll") != 0 else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation { proxy.scrollTo(UserDefaults.standard.integer(forKey: "ProfileScroll") == 2 ? "profile-who" : "profile-trophies", anchor: .bottom) }          // `-ProfileScroll 2` scrolls the top card's bottom into view (landscape captures)
            }
            }
            ShowCTA(title: "See today's Jelly Show", id: "condition-show", height: compact ? 54 : 56) { show() }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(ShowUI.sand.ignoresSafeArea())
        .accessibilityIdentifier("condition-screen")
        .sheet(isPresented: $trophiesOpen) { TrophiesSheet(care: care, who: who) { trophiesOpen = false }.presentationDetents([.medium, .large]).presentationBackground(SK.cream) }
        .sheet(isPresented: $stylesOpen) {
            ConditionScreen(care: care, who: $who, back: { stylesOpen = false }, show: { stylesOpen = false; show() }, bath: { stylesOpen = false; bath?() }, feed: feed, drink: drink, sheetMode: true)
                .presentationDetents([.large]).presentationBackground(ShowUI.sand)
        }
        .task {
            await Self.captureAids(care: care, who: $who)
            if DevArgs.enabled, UserDefaults.standard.integer(forKey: "ProfileStyles") != 0 { try? await Task.sleep(nanoseconds: 2_500_000_000); stylesOpen = true }          // capture aid: `-ProfileStyles 1` opens the Jelly Show styles sheet
        }
    }

    // MARK: facts (all read from the save)

    struct Facts {
        let p: JellyProfile?
        let state: JellyState?
        let asleep: Bool
        let sentence: String
        /// The short status line of the new top card.
        let short: String
        let hour: Double
        /// The relationship now (points from the save; display only).
        let bond: BondLevel
        init(care: GameCare, who: Int) {
            p = care.jelly(who)
            bond = BondLevel(points: JellyBond.points(care.jelly(who)?.character ?? who))
            let inp = care.widgetInputs().first { $0.id == who }
            let sleeping = care.asleepForAway(who)
            asleep = sleeping
            let st = inp.map { JellyState(record: WidgetBridge.record($0, look: ""), awaySeconds: 0) }
            state = st
            sentence = st.map { JellyStatus.sentence($0, sleeping: sleeping, night: SleepHours.isNight(hour: DayClock.shared.hour)) } ?? ""
            short = st.map { ProfileWords.shortStatus($0, sleeping: sleeping, night: SleepHours.isNight(hour: DayClock.shared.hour)) } ?? ""
            hour = DayClock.shared.hour
        }
    }

    private func card<C: View>(tint: Color = .white, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.12), radius: 6, y: 2))
    }

    private func cardTitle(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .black)).foregroundStyle(.white).frame(width: 28, height: 28).background(Circle().fill(color)).accessibilityHidden(true)
            Text(text).font(SK.font(16, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: 1. who

    private struct WhoBits { let body: Color; let species: Int; let info: SpeciesInfo?; let variant: JellyVariant? }
    private func whoBits(_ f: Facts) -> WhoBits {
        let character = f.p?.character ?? who
        let t = JellyRoster.tint(character)
        let species = JellyRoster.species(character)
        return WhoBits(body: Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z)), species: species,
                       info: SpeciesInfo.all.first { $0.character == species }, variant: JellyVariants.adopted(character))
    }

    private func whoPicture(_ b: WhoBits, _ size: CGFloat) -> some View {
        ZStack {
            Circle().fill(b.body.opacity(0.35))
            Circle().strokeBorder(b.body.opacity(0.7), lineWidth: 3)
            JelbiePortrait(care: care, who: who, size: size * 0.92, head: true, frameless: true)
        }
        .frame(width: size, height: size)
    }

    private func whoName(_ center: Bool) -> some View {
        Text(care.rosterName(who)).font(SK.font(30, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.75)
            .multilineTextAlignment(center ? .center : .leading)
            .padding(.top, -6).padding(.bottom, -5)          // trim the line box so the letters (cap height / baseline), not the box, set the gaps
            .accessibilityIdentifier("profile-name")
    }

    /// The kind chip ("Blush") and the type chip ("Sleepy type"): ALWAYS exactly one row, the same for every Jelmiko (ProfileTagRow).
    private func whyChips(_ f: Facts, _ b: WhoBits, center: Bool) -> some View {
        ProfileTagRow(kind: b.info?.name, type: Self.typeSample ?? f.p?.traits?.personality.title, typeIcon: f.p?.traits?.personality.symbol ?? "sparkles")
            .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
    }

    private func whoStatus(_ f: Facts, center: Bool) -> some View {
        ProfileStatus(text: f.short).accessibilityIdentifier("profile-sentence")
    }

    /// The description as ONE paragraph, exactly as the game words it (SkinAbout: the colour sentence + the character sentence; the same words as the Spring page).
    @ViewBuilder private func aboutParagraph(_ b: WhoBits) -> some View {
        if b.info != nil {
            ProfileParagraph(text: SkinAbout.text(look: b.species, variant: b.variant)).accessibilityIdentifier("profile-about")
        }
    }

    /// The living-line slot: a soft bubble in the pet's body tint with a small sparkle; nothing at all when there is no text.
    @ViewBuilder private func latelyBubble(_ f: Facts, _ b: WhoBits) -> some View {
        if let text = Self.lately(f), !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkle").font(.system(size: 13, weight: .black)).foregroundStyle(ShowUI.goldDeep).padding(.top, 3).accessibilityHidden(true)
                Text(text).font(SK.font(15, .semibold)).foregroundStyle(SK.ink).lineSpacing(3).lineLimit(dts.isAccessibilitySize ? 5 : 2, reservesSpace: true)          // always two lines of space
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(b.body.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(b.body.opacity(0.5), lineWidth: 1.5))
            .accessibilityElement(children: .ignore).accessibilityLabel("Lately: \(text)").accessibilityIdentifier("profile-lately")
        }
    }

    /// The top card: header row (picture, name, chips, short status), the description paragraph, the living line (when there is one), the Relationship line.
    private func whoCard(_ f: Facts) -> some View {
        let b = whoBits(f)
        let text = VStack(alignment: .leading, spacing: 8) {          // one rhythm: name, chip row(s), status, 8 pt apart
            whoName(false); whyChips(f, b, center: false); whoStatus(f, center: false)
        }
        let pic: CGFloat = compact ? 104 : 128
        return card {
            VStack(alignment: .leading, spacing: 14) {          // one card rhythm: header, paragraph, living line, Relationship, 14 pt apart
                if dts.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { whoPicture(b, 104); text }
                } else {
                    // The text block is centred against the picture when shorter; when taller, both start at the top of the row.
                    HStack(alignment: .top, spacing: 14) {
                        whoPicture(b, pic)
                        text.frame(maxWidth: .infinity, minHeight: pic, alignment: .leading)
                    }
                }
                aboutParagraph(b)
                latelyBubble(f, b)
                BondHeartsRow(level: f.bond).frame(maxWidth: .infinity, alignment: .leading).id(who)
            }
        }
        .id("profile-who")
    }

    // MARK: 2. right now

    private func rightNowCard(_ f: Facts) -> some View {
        var chips: [ProfileWords.Chip] = []
        if let s = f.state { chips = [ProfileWords.need(s, .food), ProfileWords.need(s, .water), ProfileWords.clean(s)] }
        chips.append(ProfileWords.sleep(asleep: f.asleep, hour: f.hour))
        return card {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("Right now", icon: "clock.fill", color: SK.sky)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(chips, id: \.title) { c in ProfileChipView(chip: c) }
                }
            }
        }
    }

    // MARK: 3. favourites

    private func favouritesCard(_ f: Facts) -> some View {
        let snack = f.p?.traits?.snack
        let item = snack.flatMap { s in StoreCatalog.items.first { $0.food == s } ?? StoreCatalog.items.first { $0.id == s } }
        let powerUps = f.p?.perks.active ?? []
        let character = f.p?.character ?? who
        let friend = care.parkBook.visitors.filter { $0.mergedInto == nil }
            .compactMap { v -> (ParkVisitor, Float)? in let pts = v.friendship["\(character)"] ?? 0; return ParkFriendLevel.of(pts) >= .friend ? (v, pts) : nil }
            .max { $0.1 < $1.1 }
        return card {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("Favourites", icon: "heart.fill", color: SK.pink)
                ProfileFavRow(title: "Favourite food", value: { ProfileFavText(text: item?.name ?? f.p?.traits?.snackName ?? "Still finding out") }) {
                    if let item { ItemArt(item: item, size: 48) }
                    else { Image(systemName: "fork.knife").font(.system(size: 20, weight: .black)).foregroundStyle(SK.muted).frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.7))) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Favourite food: \(item?.name ?? f.p?.traits?.snackName ?? "still finding out")")
                .accessibilityIdentifier("profile-fav-food")
                ProfileFavRow(title: "Best friend at the Park", value: { ProfileFavText(text: friend.map { "\($0.0.name) \u{00B7} \(ParkFriendLevel.of($0.1).title)" } ?? "Still finding out", lines: 2) }) {
                    Image(systemName: "person.2.fill").font(.system(size: 20, weight: .black)).foregroundStyle(.white).frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(SK.mint))
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("profile-fav-friend")
                // Always there (a calm empty state), so the card below never moves when a power-up starts or ends.
                ProfileFavRow(title: "Power-ups", value: { ProfilePerkNames(names: powerUps.sorted { (f.p?.perks.remaining($0) ?? 0) < (f.p?.perks.remaining($1) ?? 0) }.map(\.title)) }) {
                    Image(systemName: "bolt.fill").font(.system(size: 20, weight: .black)).foregroundStyle(.white).frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(SK.honeyDeep))
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("profile-fav-perk")
            }
        }
    }

    // MARK: 4. trophies

    /// The pictures are the Trophy Shelf card's own (`TrophyEntry.make(...).picture`: the trophy's mesh through StoreThumb, in its real metal, cached); the coloured symbol stays as the fallback.
    private func trophyChips() -> (chips: [ProfileTrophyChip], total: Int, ribbons: Int) {
        let c = care.jelly(who)?.character ?? who
        let shelf = care.race.trophies.shelf(character: c)
        let show = care.show.progress.trophies(character: c)
        let since = care.race.trophies.engravingSince
        func date(_ key: String) -> String { TrophyShelfItem.dateText(shelf.won?[key], before: since) }
        func entry(_ id: String, caption: String, spec: TrophyShelfSpec) -> TrophyEntry { TrophyEntry.make(TrophyShelfItem(id: id, event: caption, character: c, date: nil), spec: spec) }
        let medal: [Color] = [Color(hex: 0xF2B530), Color(hex: 0xA9B3C2), Color(hex: 0xC98B55)]
        var out: [ProfileTrophyChip] = []
        for t in Trophy.all + Trophy.allVolley where shelf.has(t) {
            var spec = TrophyShelfSpec(), id = t.id
            if t.id.hasPrefix("first."), let tier = CourseTier(rawValue: String(t.id.dropFirst(6))), let k = CourseTier.allCases.firstIndex(of: tier) {
                id = "cup.\(tier.rawValue)"; spec.cups[k] = UInt8(shelf.bestRace(tier) ?? 1)          // the cup of his best place there (as on the wall)
            }
            if t.id.hasPrefix("vfirst.") { id = "volley.\(t.id.dropFirst(7))" }          // the first volleyball win: the volleyball cup
            let pic: TrophyEntry? = TrophyShelfGeometry.singleMesh(id: id) == nil ? nil : entry(id, caption: t.title, spec: spec)          // (a trophy the wall has no model for keeps its symbol)
            out.append(ProfileTrophyChip(id: "t-\(t.id)", icon: "trophy.fill", color: Color(hex: 0xF2B530), caption: t.title, date: date("trophy.\(t.id)"), entry: pic))
        }
        for r in ShowRank.allCases { if let p = show.cup(r) {
            let key = "show.\(r.rawValue).\(p)"
            var spec = TrophyShelfSpec(); spec.contest = UInt8(min(max(p, 1), 3))
            out.append(ProfileTrophyChip(id: "cup-\(r.rawValue)", icon: "trophy.fill", color: medal[min(max(p, 1), 3) - 1], caption: "\(r.title) Show cup \u{00B7} \(ShowUI.ordinal(p))", date: date(key), entry: entry("contest", caption: r.title, spec: spec)))
        } }
        for tag in WearTag.jarOrder where show.hasRosette(tag) {
            out.append(ProfileTrophyChip(id: "ros-\(tag.rawValue)", icon: "seal.fill", color: ShowUI.tag(tag), caption: "\(tag.title) rosette", date: nil))
        }
        for t in VolleyTier.allCases where shelf.volleyWon(t) > 0 {
            out.append(ProfileTrophyChip(id: "vol-\(t.rawValue)", icon: "figure.volleyball", color: SK.sky, caption: "Volleyball \(t.title) \u{00D7}\(shelf.volleyWon(t))", date: date("volley.\(t.rawValue)"), entry: entry("volley.\(t.rawValue)", caption: t.title, spec: TrophyShelfSpec())))
        }
        return (out, out.count, shelf.raceRibbonCount)
    }

    private func trophiesCard() -> some View {
        let t = trophyChips()
        let empty = t.total == 0 && t.ribbons == 0
        let shown = Array(t.chips.prefix(8))
        return Button { AudioHub.shared.uiTap(); trophiesOpen = true } label: {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        cardTitle(empty ? "Trophies" : "\(t.total) \(t.total == 1 ? "trophy" : "trophies")" + (t.ribbons > 0 ? " \u{00B7} \(t.ribbons) ribbon\(t.ribbons == 1 ? "" : "s")" : ""), icon: "trophy.fill", color: ShowUI.goldDeep)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .black)).foregroundStyle(SK.ink).accessibilityHidden(true)
                    }
                    if empty {
                        Text("No trophies yet. Win a race, a show or a volleyball match.").font(SK.font(14, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(shown) { c in
                                HStack(spacing: 6) {
                                    if let img = c.entry?.picture { Image(uiImage: img).resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true) }
                                    else { Image(systemName: c.icon).font(.system(size: 13, weight: .black)).foregroundStyle(c.color).accessibilityHidden(true) }
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(c.caption).font(SK.font(12, .black)).foregroundStyle(SK.ink)
                                        if let d = c.date { Text(d).font(SK.font(10, .bold)).foregroundStyle(SK.muted) }
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(0.85)))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(c.date.map { "\(c.caption), \($0)" } ?? c.caption)
                            }
                            if t.chips.count > shown.count {
                                Text("+\(t.chips.count - shown.count) more").font(SK.font(12, .black)).foregroundStyle(SK.muted).padding(.horizontal, 10).padding(.vertical, 8)
                            }
                        }
                        if t.ribbons > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: UIImage(systemName: "rosette") != nil ? "rosette" : "seal.fill").font(.system(size: 13, weight: .black)).foregroundStyle(Color(hex: 0xA9B3C2)).accessibilityHidden(true)
                                Text("\(t.ribbons) race ribbon\(t.ribbons == 1 ? "" : "s")").font(SK.font(13, .heavy)).foregroundStyle(SK.muted)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens the trophy shelf")
        .accessibilityIdentifier("condition-trophies")
        .id("profile-trophies")
    }

    // MARK: the old jars, out of the way

    private var stylesRow: some View {
        Button { AudioHub.shared.uiTap(); stylesOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "flask.fill").font(.system(size: 13, weight: .black)).foregroundStyle(SK.muted).accessibilityHidden(true)
                Text("Jelly Show styles").font(SK.font(14, .heavy)).foregroundStyle(SK.muted)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .black)).foregroundStyle(SK.muted).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain).accessibilityIdentifier("profile-styles")
    }

    // MARK: capture aids (dev arguments only)

    /// `-OpenProfile <index>` picks that Jelmiko; `-ProfileSeed 1` gives the picked Jelmiko a few race, volleyball and show trophies (for the screenshots).
    @MainActor private static func captureAids(care: GameCare, who: Binding<Int>) async {
        guard DevArgs.enabled else { return }
        let d = UserDefaults.standard
        if d.object(forKey: "OpenProfile") != nil, care.jellies.indices.contains(d.integer(forKey: "OpenProfile")) { who.wrappedValue = d.integer(forKey: "OpenProfile") }
        if d.integer(forKey: "ProfileFed") != 0 { for j in care.jellies { for k in NeedKind.allCases { j.needs.set(k, 1) }; j.grime.dirt = 0 } }          // `-ProfileFed 1`: nobody wants anything (to see the plain "asleep" sentence)
        if d.object(forKey: "BondSet") != nil {          // `-BondSet <points>` sets the picked Jelmiko's relationship points outright (a capture aid: the only place that can LOWER them)
            let c = care.jelly(who.wrappedValue)?.character ?? who.wrappedValue
            JellyBond.seedIfNeeded(c)
            var m = UserDefaults.standard.dictionary(forKey: JellyBond.key(c)) ?? [:]
            m["p"] = max(d.integer(forKey: "BondSet"), 0)
            UserDefaults.standard.set(m, forKey: JellyBond.key(c))
        }
        if d.integer(forKey: "ProfileSeed") != 0, d.integer(forKey: "ProfileSeeded") == 0 {
            d.set(1, forKey: "ProfileSeeded")
            let c = care.jelly(who.wrappedValue)?.character ?? who.wrappedValue
            let tiers = CourseTier.allCases
            care.race.trophies.recordRace(character: c, tier: tiers[0], place: 1)
            care.race.trophies.recordRace(character: c, tier: tiers[1], place: 1)
            care.race.trophies.recordRace(character: c, tier: tiers[1], place: 2)
            var s = care.race.trophies.shelf(character: c)
            s.volleyWins = [VolleyTier.allCases[0].rawValue: 2]
            s.stamp("volley.\(VolleyTier.allCases[0].rawValue)", Date())
            care.race.trophies.setShelf(s, character: c)
            if let theme = Optional(ShowSchedule.theme(dayKey: GameCare.showDay)) {
                _ = care.show.progress.record(rank: .puddle, place: 1, theme: theme, character: c, burst: false, perfectDance: false, hatTrick: false)
                care.race.trophies.recordShowCup(character: c, rank: .puddle, place: 1)
            }
        }
    }
}
