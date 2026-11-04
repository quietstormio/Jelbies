//
//  VolleyLobby.swift
//  The Volleyball lobby (Go out > Beach), rebuilt to the lobby mockups: the four courts in a carousel, the Team card (you and a chosen teammate), the two options, and a pinned
//  Train / Play bar. Training (the stats and the drills) and How to play are sheets. Shared pieces are in Lobby/LobbyKit.swift.
//

import SwiftUI

struct VolleyLobby: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    /// "Go to the Park": leaves the lobby for the Park trip (the Town's own path).
    var park: () -> Void = {}
    var play: (VolleyTier) -> Void
    /// A drill, for the Jelbie picked on the Training sheet.
    var drill: (VolleyDrillKind, Int) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: Sheet?
    @State private var trainee = 0
    @State private var hint = LobbyHint()
    enum Sheet { case train, how, options }
    private var book: VolleyBook { care.volley.book }
    private var compact: Bool { vsc == .compact }
    private var blocker: String? { care.volleyBlocker(jelly: who, match: true) }
    /// Training and drills are solo: they never need a partner.
    private var drillBlocker: String? { care.volleyBlocker(jelly: who) }
    private var needsPartner: Bool { care.volleyPartnerBlocker(jelly: who) != nil }

    var body: some View {
        let char = care.jelly(who)?.character ?? who
        ZStack {
            LobbyScreen(header: AnyView(LobbyHeader(title: "Volleyball", wallet: care.bath.wallet, backID: "volley-back", helpID: "volley-help", back: back, help: { open(.how) },
                                                 optionsID: "volley-options", options: { open(.options) })),
                        why: needsPartner ? nil : blocker, whyID: "volley-why") {          // the partner rule is said under the picker instead
                courts
            } right: {
                VolleyTeamCard(care: care, who: $who, compact: compact, park: park)
                    .padding(.top, compact ? 0 : 12)
            } bar: {
                LobbyBottomBar(pepLeft: book.sessionsLeft(char), pepTotal: VolleyTraining.fullSessions, pepID: "volley-pep", trainID: "volley-train", playID: "volley-play",
                               playTitle: "Play", playIcon: needsPartner ? .lock : .ball, blocked: blocker != nil, trainBlocked: drillBlocker != nil,
                               train: { trainee = who; open(.train) }, play: { play(book.chosen) })
            }
            .accessibilityHidden(sheet != nil)
            if let sheet {
                Group {
                    switch sheet {
                    case .train: trainingSheet
                    case .options:
                        LobbySheet(title: "Options", close: { close() }) { optionsCard.padding(.top, 4) }.accessibilityIdentifier("volley-options-sheet")
                    case .how:
                        LobbyHowSheet(rows: [
                            (.three, "Three touches a side", "Bump, set, then spike it over the net."),
                            (.ring, "Tap on the ring", "Tap as the ring closes for a Perfect hit."),
                            (.tap, "Steer a Jelbie", "Double-tap a Jelbie to move them yourself."),
                            (.trophy, "First to \(VolleyTuning.pointsToWin), win by 2", "Win a match to open the next court."),
                        ], close: { close() })
                    }
                }
                .zIndex(1)
            }
        }
        .environment(\.lobbyTheme, .beach)
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-lobby")
        .onAppear {
            trainee = who
            switch UserDefaults.standard.string(forKey: "LobbyAuto") {          // capture aid: -LobbyAuto volleyTrain | volleyHow
            case "volleyTrain": sheet = .train
            case "volleyHow": sheet = .how
            default: break
            }
        }
    }

    private func open(_ s: Sheet) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { sheet = s } }
    private func close() { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { sheet = nil } }

    // MARK: courts

    private var courts: some View {
        let open = book.unlockedTiers.count
        return VStack(alignment: .leading, spacing: 0) {
            LobbyLabelRow(title: "Court", trailing: "\(open) of \(VolleyTier.allCases.count) open")
            LobbyCarousel(bleed: !compact, scrollTo: book.chosen.index >= 2 ? "tier-\(book.chosen.rawValue)" : nil) {
                ForEach(VolleyTier.allCases, id: \.rawValue) { t in courtCard(t).id("tier-\(t.rawValue)") }
            }
            .accessibilityIdentifier("volley-courts")
            LobbyPlaceInfo(text: hint.text ?? book.chosen.blurb, textID: "volley-blurb",
                           prizes: [LobbyPrize(label: "Win", amount: VolleyTuning.drops(win: true, tier: book.chosen), gold: true), LobbyPrize(label: "Loss", amount: VolleyTuning.drops(win: false, tier: book.chosen))], prizeID: "volley-prizes")
            .accessibilityElement(children: .contain)
        }
    }

    private func unlockRule(_ t: VolleyTier) -> String { "Win a match (or three close ones) at \(t.below?.title ?? "") to open" }

    private func courtCard(_ t: VolleyTier) -> some View {
        let isOpen = book.unlocked(t), on = book.chosen == t
        return Button {
            if isOpen { AudioHub.shared.uiTap(); book.chosen = t; book.save() } else { hint.show(unlockRule(t)) }
        } label: {
            LobbyCarouselCard(name: t.title, sub: isOpen ? t.className : "Win at \(t.below?.title ?? "")", selected: on && isOpen, locked: !isOpen) { CourtArt(tier: t) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOpen ? "\(t.title), \(t.className)" : "\(t.title), locked. Win at \(t.below?.title ?? "")")
        .accessibilityHint(isOpen ? t.blurb : unlockRule(t))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("volley-tier-\(t.rawValue)")
    }

    // MARK: options

    private var optionsCard: some View {
        let autoOn = Binding(get: { book.autoSwitch }, set: { book.autoSwitch = $0 })
        let slowOn = Binding(get: { book.slowBall }, set: { book.slowBall = $0 })
        let assist = A11ySettings.shared.raceAssist != .off
        return VStack(alignment: .leading, spacing: 0) {
            if compact {
                HStack(spacing: 12) {
                    LobbyOptionRow(icon: .autosw, title: "Auto-switch", isOn: autoOn, id: "volley-autoswitch", compact: true)
                    LobbyOptionRow(icon: .turtle, title: "Slower ball", isOn: slowOn, id: "volley-slow", compact: true)
                }
            } else {
                LobbyOptionRow(icon: .autosw, title: "Auto-switch Jelbies", isOn: autoOn, id: "volley-autoswitch")
                Rectangle().fill(SK.ink.opacity(0.08)).frame(height: 1)
                LobbyOptionRow(icon: .turtle, title: "Slower ball", isOn: slowOn, id: "volley-slow")
            }
            if assist {
                Text("Play assist is on (Settings > Accessibility): the Jelbie walks to the ball for you.").font(SK.font(11, .bold)).foregroundStyle(SK.muted)
                    .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, compact ? 12 : 14).padding(.vertical, compact ? 6 : 4).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.card))
    }

    // MARK: training

    private func statColor(_ k: VolleyStatKind) -> Color {
        switch k { case .speed: return SK.sky; case .power: return SK.pink; case .hops: return SK.mint; case .timing: return SK.honeyDeep }
    }
    private func drillIcon(_ k: VolleyDrillKind) -> LobbyIcon.Kind {
        switch k { case .bonk: return .dotted; case .spike: return .spike; case .block: return .block; case .sprint: return .run }
    }
    private func sectionHead(_ title: String, _ trailing: String? = nil) -> some View {
        HStack {
            Text(title.uppercased()).font(SK.font(12.5, .heavy)).tracking(0.6).foregroundStyle(SK.muted).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(SK.font(12.5, .heavy)).foregroundStyle(SK.muted) }
        }
        .padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 8)
    }

    private var trainingSheet: some View {
        let prof = care.jelly(trainee) ?? care.jelly(who)
        let c = prof?.character ?? trainee
        let st = book.stats(character: c)
        let left = book.sessionsLeft(c)
        let name = prof?.name ?? "Bob"
        return LobbySheet(title: "Training", full: true, close: { close() }) {
            VStack(alignment: .leading, spacing: 0) {
                LobbyChips(care: care, selected: trainee) { trainee = $0 }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text("Pep").font(SK.font(16, .black)).foregroundStyle(SK.ink)
                        HStack(spacing: 6) { ForEach(0..<VolleyTraining.fullSessions, id: \.self) { i in Capsule().fill(i < left ? SK.mint : SK.pepEmpty).frame(height: 12) } }
                        Text("\(left) left").font(SK.font(15, .black)).foregroundStyle(SK.ink).monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel("Pep: \(left) of \(VolleyTraining.fullSessions) full practices left today")
                    Text("Each practice uses one Pep. It refills overnight; after that, practice still helps, just less.").font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                }
                .lobbyCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)).padding(.top, 14)
                sectionHead("\(name) on the sand", "\(st.wins) win\(st.wins == 1 ? "" : "s") \u{00B7} \(st.matches) match\(st.matches == 1 ? "" : "es")")
                VStack(spacing: 11) {
                    LobbyBigStat(name: "Speed", value: st.speed, color: SK.sky, sub: "Quicker feet, longer steps")
                    LobbyBigStat(name: "Power", value: st.power, color: SK.pink, sub: "Harder hits and spikes")
                    LobbyBigStat(name: "Hops", value: st.hops, color: SK.mint, sub: "Higher jumps")
                    LobbyBigStat(name: "Timing", value: st.timing, color: SK.honeyDeep, sub: "A bigger hit window, a truer aim")
                }
                .lobbyCard().accessibilityElement(children: .contain).accessibilityIdentifier("volley-stats")
                sectionHead("Drills")
                VStack(spacing: 8) { ForEach(VolleyDrillKind.allCases, id: \.rawValue) { k in drillRow(k) } }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("volley-training")
        }
    }

    private func drillRow(_ k: VolleyDrillKind) -> some View {
        HStack(spacing: 12) {
            LobbyIcon(kind: drillIcon(k)).frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(SK.sky.opacity(0.55)))
            VStack(alignment: .leading, spacing: 4) {
                Text(k.title).font(SK.font(16, .black)).foregroundStyle(SK.ink).fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 5) {
                    ForEach(k.raises, id: \.rawValue) { s in
                        Text("+ \(s.title)").font(SK.font(11.5, .heavy)).foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(statColor(s).opacity(0x55 / 255.0)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm()
                let id = trainee
                close(); drill(k, id)
            } label: {
                Text("Go").font(SK.font(14.5, .black)).foregroundStyle(.white).padding(.horizontal, 16).frame(minHeight: 36)
                    .background(Capsule().fill(drillBlocker == nil ? SK.pinkStrong : SK.muted.opacity(0.45)))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(drillBlocker != nil)
            .accessibilityLabel("Go, \(k.title)").accessibilityHint(k.blurb).accessibilityIdentifier("volley-drill-\(k.rawValue)")
        }
        .padding(EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.9)))
    }
}

// MARK: - The Team (picker + stats card)

/// The shared Jelbie picker (pick two) and the stats card with both team members' Speed / Power / Hops / Timing. With three Jelbies a tap on an unselected tile replaces the one
/// picked earliest (`who` is always the earlier pick, `VolleyBook.partner` the later); with two both play; with one the Park friend is the teammate.
struct VolleyTeamCard: View {
    let care: GameCare
    @Binding var who: Int
    var compact = false
    var park: () -> Void = {}
    private var book: VolleyBook { care.volley.book }

    var body: some View {
        let mine = care.jelly(who)
        let partner = care.volleyPartner(for: who)
        let friend = partner == nil ? care.volleyParkFriend() : nil
        let locked = partner == nil && friend == nil
        VStack(alignment: .leading, spacing: 0) {
            LobbyJelbiePicker(care: care, title: "Team", selected: [who, partner?.id].compactMap { $0 }, selectCount: 2, id: "volley-picker", tileID: { "volley-who-\($0.id)" }, friends: friend.map { [$0] } ?? [],
                              blocker: locked ? GameCare.volleyNeedsPartner : nil,
                              footnote: friend.map { "Your Park friend \($0.name) fills in." } ?? "Short a teammate? A Park friend fills in.", footnoteButton: locked ? (title: "Go to the Park", id: "volley-go-park", action: park) : nil, lockedCount: locked ? 1 : 0, lockedText: "Needs a partner") { id in
                guard care.jellies.count >= 3, id != who, id != partner?.id, let c = care.jelly(id) else { return }
                let keep = partner?.id ?? who
                book.partner = c.character; book.save()
                who = keep
            }
            .padding(.bottom, 6)
            LobbyStatsCard(title: "Team stats", groups: [group(mine, id: "volley-team-1"), partner.map { group($0, id: "volley-team-2") } ?? friendGroup(friend)].compactMap { $0 }, id: "volley-team")
        }
    }

    private func group(_ j: JellyProfile?, id: String) -> LobbyStatGroup? {
        guard let j else { return nil }
        let st = book.stats(character: j.character)
        return LobbyStatGroup(id: id, name: j.name, rows: [
            LobbyStatRow(label: "Speed", value: st.speed, color: SK.sky), LobbyStatRow(label: "Power", value: st.power, color: SK.pink),
            LobbyStatRow(label: "Hops", value: st.hops, color: SK.mint), LobbyStatRow(label: "Timing", value: st.timing, color: SK.honeyDeep),
        ])
    }

    private func friendGroup(_ friend: ParkVisitor?) -> LobbyStatGroup {
        guard let friend else {
            return LobbyStatGroup(id: "volley-team-friend", custom: AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { Image(systemName: "lock.fill").font(.system(size: 18, weight: .heavy)).foregroundStyle(SK.muted); Text("No partner yet").font(SK.font(15.5, .black)).foregroundStyle(SK.ink) }
                    Text("Make a friend at the Park, or adopt a second Jelbie.").font(SK.font(12.5, .bold)).foregroundStyle(SK.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 0, idealWidth: 170, maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore).accessibilityLabel("No partner yet. Make a friend at the Park, or adopt a second Jelbie.")))
        }
        return LobbyStatGroup(id: "volley-team-friend", custom: AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // the friend as he will play: the lone Jelbie's body in the friend's colour and item, rendered by the stage (a friend with a signature feature is never picked)
                    JelbiePortrait(care: care, who: care.jellies.first?.id ?? 0, size: 46, border: .white, outerRing: 3, head: true, friend: friend)
                    Text(friend.name).font(SK.font(15.5, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                }
                Text("Plays with you until you adopt a second Jelbie. Steady, and sets you up.").font(SK.font(12.5, .bold)).foregroundStyle(SK.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, idealWidth: 170, maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Park friend. Plays with you until you adopt a second Jelbie. Steady, and sets you up.")
        ))
    }
}
