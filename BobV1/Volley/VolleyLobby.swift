//
//  VolleyLobby.swift
//  The Volleyball lobby (Go out > Beach), rebuilt to the lobby mockups: the four courts in a carousel, the Team card (you and a chosen teammate), the two options, and a pinned
//  Play bar. How to play and the options are sheets. Shared pieces are in Lobby/LobbyKit.swift.
//

import SwiftUI

struct VolleyLobby: View {
    let care: GameCare
    @Binding var who: Int
    var back: () -> Void
    /// "Go to the Park": leaves the lobby for the Park trip (the Town's own path).
    var park: () -> Void = {}
    /// To the Shop (the Upgrade sheet's "Shop ›").
    var shop: (() -> Void)? = nil
    var play: (VolleyTier) -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: Sheet?
    @State private var hint = LobbyHint()
    /// The Jelbie the Upgrade sheet shows (a team member; reset to the first pick on open).
    @State private var upgradeWho: Int?
    enum Sheet { case how, options, upgrade }
    private var book: VolleyBook { care.volley.book }
    private var compact: Bool { vsc == .compact }
    private var blocker: String? { care.volleyBlocker(jelly: who, match: true) }
    private var needsPartner: Bool { care.volleyPartnerBlocker(jelly: who) != nil }

    var body: some View {
        ZStack {
            LobbyScreen(header: AnyView(LobbyHeader(title: "Jelly Volleyball", wallet: care.bath.wallet, backID: "volley-back", helpID: "volley-help", back: back, help: { open(.how) },
                                                 optionsID: "volley-options", options: { open(.options) })),
                        why: needsPartner ? nil : blocker, whyID: "volley-why") {          // the partner rule is said under the picker instead
                courts
            } right: {
                VolleyTeamCard(care: care, who: $who, compact: compact, park: park)
                    .padding(.top, compact ? 0 : 12)
            } bar: {
                LobbyBottomBar(playID: "volley-play", playTitle: "Play", playIcon: needsPartner ? .lock : .ball, blocked: blocker != nil, upgradeID: "volley-upgrade",
                               upgradePoints: teamPoints, upgrade: { upgradeWho = who; open(.upgrade) }, play: { play(book.chosen) })
            }
            .accessibilityHidden(sheet != nil)
            if let sheet {
                Group {
                    switch sheet {
                    case .upgrade:
                        if let first = care.jelly(who), let p = care.jelly(upgradeWho ?? who) {
                            UpgradeSheet(care: care, who: p.id, config: care.volleyUpgradeConfig(p, team: first), buy: { care.volleyBuySkill($0, p) }, pick: { care.volleyPickPower($0, p) },
                                         shop: shop.map { go in { close(); go() } }, switchTo: { upgradeWho = $0 }, done: { close() })
                        }
                    case .options:
                        LobbySheet(title: "Options", close: { close() }) { optionsCard.padding(.top, 4) }.accessibilityIdentifier("volley-options-sheet")
                    case .how:
                        LobbyHowSheet(rows: [
                            (.three, "Three touches a side", "Bump, set, then spike it over the net."),
                            (.ring, "Tap on the ring", "Tap as the ring closes for a Perfect hit."),
                            (.tap, "Steer a Jelbie", "Double-tap a Jelbie to move them yourself."),
                            (.trophy, "First to \(VolleyTuning.pointsToWin) points", "Win a match to open the next court."),
                        ], close: { close() })
                    }
                }
                .zIndex(1)
            }
        }
        .environment(\.lobbyTheme, .beach)
        .accessibilityElement(children: .contain).accessibilityIdentifier("volley-lobby")
        .onAppear {
            switch UserDefaults.standard.string(forKey: "LobbyAuto") {          // capture aid: -LobbyAuto volleyHow
            case "volleyHow": sheet = .how
            default: break
            }
        }
    }

    /// The Upgrade badge: the TOTAL points across the team members.
    private var teamPoints: Int {
        guard let me = care.jelly(who) else { return 0 }
        let team = [me] + [care.volleyPartner(for: who)].compactMap { $0 }
        return team.reduce(0) { $0 + care.upgrades.points(.volley, character: $1.character) }
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
