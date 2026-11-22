//
//  ProfileScreen.swift
//  The Profile of a Jelmiko (replaces the "Condition" screen the circled close-up button and the Studio's card link used to open): a head picture, the name and
//  kind, ONE plain sentence on how they are (the same words Siri and the Lock Screen say: Shared/JellyStatus.swift), a row of hearts, four status chips
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
    /// "7 AM", "8:20 PM": rounded to `round` minutes.
    static func clock(_ h: Double, round step: Int) -> String {
        let total = Int((DayMath.wrap(h) * 60 / Double(step)).rounded()) * step
        let m = total % 60, hh = (total / 60) % 24
        let h12 = hh % 12 == 0 ? 12 : hh % 12
        return m == 0 ? "\(h12) \(hh < 12 ? "AM" : "PM")" : "\(h12):\(String(format: "%02d", m)) \(hh < 12 ? "AM" : "PM")"
    }
}

/// One trophy chip on the Profile.
private struct ProfileTrophyChip: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let caption: String
    let date: String?
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
    @State private var trophiesOpen = false
    @State private var stylesOpen = false
    private var compact: Bool { vsc == .compact }

    private static let good = (bg: Color(hex: 0xDDF1E1), fg: Color(hex: 0x2F7A4A))
    private static let soon = (bg: Color(hex: 0xFFEBB0), fg: Color(hex: 0x8A5A00))
    private static let needs = (bg: Color(hex: 0xFAD3DC), fg: Color(hex: 0xB03A5B))

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            ShowHeader(title: "Profile", light: false, backID: "condition-back", back: back) { EmptyView() }
            if care.jellies.count > 1 { WhoRow(care: care, who: $who, heads: true) }
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
        .task { await Self.captureAids(care: care, who: $who) }
    }

    // MARK: facts (all read from the save)

    struct Facts {
        let p: JellyProfile?
        let state: JellyState?
        let asleep: Bool
        let sentence: String
        let hour: Double
        init(care: GameCare, who: Int) {
            p = care.jelly(who)
            let inp = care.widgetInputs().first { $0.id == who }
            let sleeping = care.asleepForAway(who)
            asleep = sleeping
            let st = inp.map { JellyState(record: WidgetBridge.record($0, look: ""), awaySeconds: 0) }
            state = st
            sentence = st.map { JellyStatus.sentence($0, sleeping: sleeping) } ?? ""
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

    private func whoCard(_ f: Facts) -> some View {
        let character = f.p?.character ?? who
        let t = JellyRoster.tint(character)
        let body = Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))
        let species = JellyRoster.species(character)
        let info = SpeciesInfo.all.first { $0.character == species }
        let kind = info?.name ?? JellyRoster.baseNames[min(max(species, 0), JellyRoster.baseNames.count - 1)]
        let loved = Int(((f.state?.levels[NeedKind.attention.rawValue] ?? 0) * 5).rounded())
        return card {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(body.opacity(0.35))
                        Circle().strokeBorder(body.opacity(0.7), lineWidth: 3)
                        JelbiePortrait(care: care, who: who, size: compact ? 96 : 118, head: true, frameless: true)
                    }
                    .frame(width: compact ? 104 : 128, height: compact ? 104 : 128)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(care.rosterName(who)).font(SK.font(30, .black)).foregroundStyle(SK.ink).jLine(2, scale: 0.6).accessibilityIdentifier("profile-name")
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 12, weight: .black)).foregroundStyle(ShowUI.goldDeep).accessibilityHidden(true)
                            Text(info.map { "\($0.name) \u{00B7} \($0.epithet)" } ?? kind).font(SK.font(14, .heavy)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        if let tr = f.p?.traits {
                            HStack(spacing: 6) {
                                Image(systemName: tr.personality.symbol).font(.system(size: 12, weight: .black)).foregroundStyle(SK.pink).accessibilityHidden(true)
                                Text("\(tr.personality.title): \(tr.personality.blurb)").font(SK.font(13, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(f.sentence).font(SK.font(18, .black)).foregroundStyle(SK.ink).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile-sentence")
                HStack(spacing: 6) {
                    Text("Feels loved").font(SK.font(14, .heavy)).foregroundStyle(SK.muted)
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < loved ? "heart.fill" : "heart").font(.system(size: 20, weight: .black))
                            .foregroundStyle(i < loved ? SK.pink : SK.pink.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Feels loved: \(loved) of 5 hearts")
                .accessibilityIdentifier("profile-hearts")
            }
        }
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
                    ForEach(chips, id: \.title) { c in
                        let tone = c.tone == .good ? Self.good : c.tone == .soon ? Self.soon : Self.needs
                        HStack(spacing: 8) {
                            Image(systemName: c.icon).font(.system(size: 17, weight: .black)).foregroundStyle(tone.fg).frame(width: 26).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.title).font(SK.font(11, .heavy)).foregroundStyle(tone.fg.opacity(0.8)).textCase(.uppercase)
                                Text(c.value).font(SK.font(15, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tone.bg))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(c.title): \(c.value)")
                        .accessibilityIdentifier("profile-chip-\(c.title.lowercased())")
                    }
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
                HStack(spacing: 10) {
                    if let item { ItemArt(item: item, size: 48).accessibilityHidden(true) }
                    else { Image(systemName: "fork.knife").font(.system(size: 20, weight: .black)).foregroundStyle(SK.muted).frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.7))).accessibilityHidden(true) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Favourite food").font(SK.font(11, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
                        Text(item?.name ?? f.p?.traits?.snackName ?? "Still finding out").font(SK.font(16, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Favourite food: \(item?.name ?? f.p?.traits?.snackName ?? "still finding out")")
                .accessibilityIdentifier("profile-fav-food")
                favRow(icon: "person.2.fill", color: SK.mint, title: "Best friend at the Park",
                       value: friend.map { "\($0.0.name) \u{00B7} \(ParkFriendLevel.of($0.1).title)" } ?? "Still finding out", id: "profile-fav-friend")
                if !powerUps.isEmpty {
                    favRow(icon: "bolt.fill", color: SK.honeyDeep, title: "Power-up now",
                           value: powerUps.map { k in "\(k.title) \u{00B7} \(SK.timeLeft(f.p?.perks.remaining(k) ?? 0)) left" }.joined(separator: ", "), id: "profile-fav-perk")
                }
            }
        }
    }

    private func favRow(icon: String, color: Color, title: String, value: String, id: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20, weight: .black)).foregroundStyle(.white).frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(SK.font(11, .heavy)).foregroundStyle(SK.muted).textCase(.uppercase)
                Text(value).font(SK.font(16, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }

    // MARK: 4. trophies

    private func trophyChips() -> (chips: [ProfileTrophyChip], total: Int, ribbons: Int) {
        let c = care.jelly(who)?.character ?? who
        let shelf = care.race.trophies.shelf(character: c)
        let show = care.show.progress.trophies(character: c)
        let since = care.race.trophies.engravingSince
        func date(_ key: String) -> String { TrophyShelfItem.dateText(shelf.won?[key], before: since) }
        let medal: [Color] = [Color(hex: 0xF2B530), Color(hex: 0xA9B3C2), Color(hex: 0xC98B55)]
        var out: [ProfileTrophyChip] = []
        for t in Trophy.all + Trophy.allVolley where shelf.has(t) {
            out.append(ProfileTrophyChip(id: "t-\(t.id)", icon: "trophy.fill", color: Color(hex: 0xF2B530), caption: t.title, date: date("trophy.\(t.id)")))
        }
        for r in ShowRank.allCases { if let p = show.cup(r) {
            let key = "show.\(r.rawValue).\(p)"
            out.append(ProfileTrophyChip(id: "cup-\(r.rawValue)", icon: "trophy.fill", color: medal[min(max(p, 1), 3) - 1], caption: "\(r.title) Show cup \u{00B7} \(ShowUI.ordinal(p))", date: date(key)))
        } }
        for tag in WearTag.jarOrder where show.hasRosette(tag) {
            out.append(ProfileTrophyChip(id: "ros-\(tag.rawValue)", icon: "seal.fill", color: ShowUI.tag(tag), caption: "\(tag.title) rosette", date: nil))
        }
        for t in VolleyTier.allCases where shelf.volleyWon(t) > 0 {
            out.append(ProfileTrophyChip(id: "vol-\(t.rawValue)", icon: "figure.volleyball", color: SK.sky, caption: "Volleyball \(t.title) \u{00D7}\(shelf.volleyWon(t))", date: date("volley.\(t.rawValue)")))
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
                        cardTitle(empty ? "Trophies" : "\(t.total) trophy\(t.total == 1 ? "" : "s")" + (t.ribbons > 0 ? " \u{00B7} \(t.ribbons) ribbon\(t.ribbons == 1 ? "" : "s")" : ""), icon: "trophy.fill", color: ShowUI.goldDeep)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .black)).foregroundStyle(SK.ink).accessibilityHidden(true)
                    }
                    if empty {
                        Text("No trophies yet. Win a race, a show or a volleyball match.").font(SK.font(14, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(shown) { c in
                                HStack(spacing: 6) {
                                    Image(systemName: c.icon).font(.system(size: 13, weight: .black)).foregroundStyle(c.color).accessibilityHidden(true)
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
