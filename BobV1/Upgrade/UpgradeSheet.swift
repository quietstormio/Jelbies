//
//  UpgradeSheet.swift
//  The Upgrade menu, ONE generic sheet for every game (Race now, Volleyball next): a hero picture of the Jelbie picked in the lobby on a themed backdrop, the skills to buy
//  with the game's points, and the power-up food for the next game. The parent builds an `UpgradeConfig` from its model on every render and answers `buy` / `pick`;
//  the sheet only draws, and plays the Jelbie's emote (a squash-and-hop for a bought skill, a happy wiggle for a picked power-up) with a chip over the picture.
//

import SwiftUI

/// One skill row: its picture (an SF Symbol in a tinted rounded square), name, level of `maxLevel`, one line, and what the next level costs (nil = at the top).
struct UpgradeSkillInfo: Identifiable {
    var id: String
    var title: String
    var blurb: String
    /// SF Symbol names, the first that exists is drawn.
    var symbols: [String]
    var tint: Color
    var level: Int
    var maxLevel = 5
    var cost: Int?
}

/// One power-up tile: "None", or a race-boost food (the Shop's 3D thumbnail). `count` 0 = not owned: greyed with "Get in Shop".
struct UpgradePowerTile: Identifiable {
    var id: String
    var name: String
    var tag: String
    var item: StoreItem?
    var count: Int
    static let noneID = "none"
    var owned: Bool { id == Self.noneID || count > 0 }
}

/// One chip of the team switcher (Volleyball with two Jelbies on the team): the Jelbie's slot, name and own points.
struct UpgradeChip: Identifiable {
    var id: Int
    var name: String
    var points: Int
}

struct UpgradeConfig {
    /// The team's Jelbies to switch between (empty or one = no switcher, as the Track has).
    var chips: [UpgradeChip] = []
    /// "Race" / "Volleyball": titles and accessibility words.
    var gameWord: String
    var heroName: String
    var winLine: String
    var points: Int
    var backdrop: Color
    var podium: Color
    var skills: [UpgradeSkillInfo]
    var tiles: [UpgradePowerTile]
    var selectedTile: String
    var powerHeading = "Power-up for the next race"
    /// The beach picture: a sand band along the bottom and a net post (nil = a plain backdrop, as the Track has).
    var sand: Color? = nil
    /// The hero picture's height in portrait; a sheet with many skills compacts it (and its rows).
    var heroHeight: CGFloat = 232
    var dense: Bool { skills.count > 2 }
}

/// What the hero picture is doing.
private enum UpgradeEmote { case hop, wiggle }

private struct HeroPose { var sx: CGFloat = 1, sy: CGFloat = 1, lift: CGFloat = 0, turn: CGFloat = 0 }
private struct ChipPose { var opacity: Double = 0, rise: CGFloat = 0, scale: CGFloat = 0.6 }

struct UpgradeSheet: View {
    let care: GameCare
    /// The Jelbie's slot (the hero picture and his happy chirp).
    let who: Int
    let config: UpgradeConfig
    /// Buys the skill; true when it was bought.
    var buy: (String) -> Bool
    /// Picks a power-up tile (an owned one, or "none"); returns true when a food (not None) is now chosen.
    var pick: (String) -> Bool
    var shop: (() -> Void)?
    /// Switches the sheet to another Jelbie of the team (slot id); nil = no switcher.
    var switchTo: ((Int) -> Void)? = nil
    var done: () -> Void

    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.lobbyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emote: UpgradeEmote = .hop
    @State private var emoteSerial = 0
    @State private var chipText = ""
    @State private var chipSerial = 0

    private var compact: Bool { vsc == .compact }

    var body: some View {
        LobbySheet(title: "Upgrade", full: true, close: done) {
            Group {
                if compact {
                    HStack(alignment: .top, spacing: 14) {
                        hero.frame(width: 200, height: 200)
                        VStack(alignment: .leading, spacing: 8) { skillsHeader; skillRows }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 8) { powerHeader; tiles; doneButton.padding(.top, 4) }.frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        hero.frame(height: config.heroHeight)
                        VStack(alignment: .leading, spacing: 8) { skillsHeader; skillRows }
                        VStack(alignment: .leading, spacing: 8) { powerHeader; tiles }
                        doneButton.padding(.top, 2)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .accessibilityIdentifier("upgrade-sheet")
    }

    // MARK: hero + emote

    private var hero: some View {
        UpgradeHero(care: care, who: who, config: config, emote: emote, emoteSerial: emoteSerial, chipText: chipText, chipSerial: chipSerial, reduceMotion: reduceMotion)
            .overlay(alignment: .bottomLeading) { switcher.padding(8) }
    }

    /// The team toggle over the picture: a face chip per Jelbie with his points; shown only when the team has more than one.
    @ViewBuilder
    private var switcher: some View {
        if let switchTo, config.chips.count > 1 {
            HStack(spacing: 8) {
                ForEach(config.chips) { c in
                    let on = c.id == who
                    Button { if !on { AudioHub.shared.uiTap(); switchTo(c.id) } } label: {
                        ZStack(alignment: .topTrailing) {
                            JelbiePortrait(care: care, who: c.id, size: 40, border: .white, outerRing: on ? 3 : 1, head: true)
                                .overlay(Circle().strokeBorder(theme.primary, lineWidth: on ? 3 : 0).padding(-3))
                                .padding(.top, 6).padding(.trailing, 6)
                            Text("\(c.points)").font(SK.font(11, .black)).foregroundStyle(SK.ink).monospacedDigit()
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18).background(Capsule().fill(.white))
                                .overlay(Capsule().strokeBorder(SK.honeyDeep, lineWidth: 1.2))
                        }
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(c.name), \(c.points) points")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("upgrade-switch-\(c.id)")
                }
            }
        }
    }

    /// The happy moment: the picture's emote (skipped under Reduce Motion), the chip, a soft haptic and the Jelbie's happy chirp.
    private func celebrate(_ kind: UpgradeEmote, chip: String) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        AudioHub.shared.chirp(jelly: who, .happy, src: "upgrade")
        emote = kind
        chipText = chip
        chipSerial += 1
        if !reduceMotion { emoteSerial += 1 }
        UIAccessibility.post(notification: .announcement, argument: chip)
    }

    // MARK: skills

    private var skillsHeader: some View {
        Text("SKILLS").font(SK.font(12.5, .black)).foregroundStyle(theme.subheading).tracking(0.8).accessibilityAddTraits(.isHeader)
    }

    private var skillRows: some View {
        VStack(spacing: config.dense ? 6 : 8) {
            ForEach(config.skills) { s in skillRow(s) }
        }
    }

    private func symbol(_ names: [String]) -> String { names.first { UIImage(systemName: $0) != nil } ?? "star.fill" }

    private func skillRow(_ s: UpgradeSkillInfo) -> some View {
        let canBuy = s.cost.map { config.points >= $0 } ?? false
        return HStack(spacing: 12) {
            Image(systemName: symbol(s.symbols)).font(.system(size: 24, weight: .heavy)).foregroundStyle(SK.ink.opacity(0.85))
                .frame(width: config.dense ? 46 : 54, height: config.dense ? 46 : 54).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(s.tint)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(s.title).font(SK.font(16.5, .black)).foregroundStyle(SK.ink)
                    Text("Level \(s.level)").font(SK.font(12.5, .heavy)).foregroundStyle(SK.muted)
                }
                Text(s.blurb).font(SK.font(12.5, .bold)).foregroundStyle(SK.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    ForEach(0..<s.maxLevel, id: \.self) { i in
                        Circle().fill(i < s.level ? theme.primary : SK.ink.opacity(0.12)).frame(width: 9, height: 9)
                    }
                }
                .padding(.top, 2).accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            buyButton(s, canBuy: canBuy)
        }
        .padding(config.dense ? 7 : 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(theme.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upgrade-skill-\(s.id)")
    }

    @ViewBuilder
    private func buyButton(_ s: UpgradeSkillInfo, canBuy: Bool) -> some View {
        if let cost = s.cost {
            Button {
                AudioHub.shared.uiTap()
                if buy(s.id) { celebrate(.hop, chip: "\u{2605} \(s.title) up!") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 12, weight: .black))
                    Text("\(cost)").font(SK.font(16, .black)).monospacedDigit()
                }
                .foregroundStyle(canBuy ? theme.primaryText : SK.muted)
                .padding(.horizontal, 14).frame(minWidth: 64, minHeight: 44)
                .background(Capsule().fill(canBuy ? theme.primary : SK.ink.opacity(0.08)))
            }
            .buttonStyle(.plain).disabled(!canBuy)
            .accessibilityLabel("Upgrade \(s.title) for \(cost) points").accessibilityValue(canBuy ? "" : "not enough points")
            .accessibilityIdentifier("upgrade-buy-\(s.id)")
        } else {
            Text("Max").font(SK.font(14, .black)).foregroundStyle(SK.muted)
                .padding(.horizontal, 14).frame(minWidth: 64, minHeight: 44).background(Capsule().fill(SK.ink.opacity(0.08)))
                .accessibilityLabel("\(s.title) is at the top level").accessibilityIdentifier("upgrade-max-\(s.id)")
        }
    }

    // MARK: power-ups

    private var powerHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(config.powerHeading.uppercased()).font(SK.font(12.5, .black)).foregroundStyle(theme.subheading).tracking(0.8).lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let shop {
                Button { AudioHub.shared.uiTap(); shop() } label: {
                    Text("Shop \u{203A}").font(SK.font(13.5, .black)).foregroundStyle(theme.subheading).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).padding(.vertical, -12).accessibilityIdentifier("upgrade-shop")
            }
        }
    }

    private var tiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(config.tiles) { t in tile(t) }
            }
            .padding(.horizontal, 4).padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(.horizontal, -4)
        .accessibilityIdentifier("upgrade-powerups")
    }

    private func tile(_ t: UpgradePowerTile) -> some View {
        let selected = t.owned && config.selectedTile == t.id
        return Button {
            if t.owned {
                AudioHub.shared.uiTap()
                if pick(t.id), let n = t.item?.name { celebrate(.wiggle, chip: "\(n) ready!") }
            } else if let shop { AudioHub.shared.uiTap(); shop() }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if let item = t.item {
                        ItemArt(item: item, size: 64).opacity(t.owned ? 1 : 0.4).saturation(t.owned ? 1 : 0)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.6)).frame(width: 64, height: 64)
                        Circle().strokeBorder(SK.muted.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, dash: [3, 5])).frame(width: 34, height: 34)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 14.5, style: .continuous).strokeBorder(theme.primary, lineWidth: selected ? 3 : 0).padding(-3))
                Text(t.name).font(SK.font(13, .black)).foregroundStyle(t.owned ? SK.ink : SK.muted).lineLimit(1).minimumScaleFactor(0.7)
                Text(t.tag).font(SK.font(11, .bold)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 88).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!t.owned && shop == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.name), \(t.tag)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("upgrade-power-\(t.id)")
    }

    private var doneButton: some View {
        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiConfirm(); done() } label: {
            Text("Done").font(SK.font(19, .black)).foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, minHeight: 58).background(Capsule().fill(theme.primary))
        }
        .buttonStyle(.plain).accessibilityIdentifier("upgrade-done")
    }
}

// MARK: - Hero

/// The big picture of the Jelbie on the game's backdrop: the Studio's full-body action shot (pose 0) standing on a podium, the name and win line top-left, the points top-right.
/// The emote moves the Jelbie only (anchored at his feet), never the podium.
private struct UpgradeHero: View {
    let care: GameCare
    let who: Int
    let config: UpgradeConfig
    let emote: UpgradeEmote
    let emoteSerial: Int
    let chipText: String
    let chipSerial: Int
    let reduceMotion: Bool
    @State private var image: UIImage?

    private func key() -> HeadPortraitKey { HeadPortraitKey(jelly: who, colour: nil, wear: nil, pose: 0) }

    var body: some View {
        GeometryReader { g in
            let h = g.size.height, S = h * 0.86
            let floorY = h * 0.80
            let discW = S * 0.64, discH = discW * 0.30
            let x = g.size.width / 2
            let feet = image?.feetFraction ?? HeadPortraitKey.actionFloorFraction
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(config.backdrop)
                if let sand = config.sand {
                    Rectangle().fill(sand).frame(height: h * 0.34).frame(maxHeight: .infinity, alignment: .bottom)
                    // a simple net post at the left, its net running off to the edge
                    Capsule().fill(SK.ink.opacity(0.55)).frame(width: 5, height: h * 0.55).position(x: g.size.width * 0.12, y: h * 0.58)
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.75)).frame(width: g.size.width * 0.12 - 2.5, height: h * 0.16).position(x: (g.size.width * 0.12 - 2.5) / 2 , y: h * 0.40)
                }
                Ellipse().fill(config.podium).frame(width: discW, height: discH).position(x: x, y: floorY)
                Ellipse().strokeBorder(.white.opacity(0.7), lineWidth: 1.2).frame(width: discW, height: discH).position(x: x, y: floorY)
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.3), .black.opacity(0)], center: .center, startRadius: 0, endRadius: discW * 0.26))
                    .frame(width: discW * 0.58, height: discH * 0.62).position(x: x, y: floorY)
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFit().frame(width: S, height: S)
                        .keyframeAnimator(initialValue: HeroPose(), trigger: emoteSerial) { content, p in
                            content
                                .scaleEffect(x: p.sx, y: p.sy, anchor: UnitPoint(x: 0.5, y: feet))
                                .rotationEffect(.degrees(Double(p.turn)), anchor: UnitPoint(x: 0.5, y: feet))
                                .offset(y: p.lift)
                        } keyframes: { _ in
                            let hop = emote == .hop          // (a builder has no if/else: both emotes share the 0.75 / 0.8 s track layout, the other one's values are the rest pose)
                            KeyframeTrack(\.sx) { CubicKeyframe(hop ? 1.08 : 1, duration: 0.12); CubicKeyframe(hop ? 0.94 : 1, duration: 0.15); CubicKeyframe(hop ? 0.94 : 1, duration: 0.20); CubicKeyframe(hop ? 1.08 : 1, duration: 0.10); SpringKeyframe(1, duration: 0.18) }
                            KeyframeTrack(\.sy) { CubicKeyframe(hop ? 0.9 : 1, duration: 0.12); CubicKeyframe(hop ? 1.08 : 1, duration: 0.15); CubicKeyframe(hop ? 1.08 : 1, duration: 0.20); CubicKeyframe(hop ? 0.9 : 1, duration: 0.10); SpringKeyframe(1, duration: 0.18) }
                            KeyframeTrack(\.lift) { CubicKeyframe(0, duration: 0.12); CubicKeyframe(hop ? -30 : 0, duration: 0.15); CubicKeyframe(0, duration: 0.20); CubicKeyframe(0, duration: 0.10); CubicKeyframe(0, duration: 0.18) }
                            KeyframeTrack(\.turn) { CubicKeyframe(hop ? 0 : -9, duration: 0.10); CubicKeyframe(hop ? 0 : 9, duration: 0.20); CubicKeyframe(hop ? 0 : -9, duration: 0.20); CubicKeyframe(hop ? 0 : 9, duration: 0.20); CubicKeyframe(0, duration: 0.10) }
                        }
                        .position(x: x, y: floorY + discH * 0.08 - S * feet + S / 2)
                } else { ProgressView().position(x: x, y: h * 0.5) }
                chip.position(x: x, y: h * 0.30)
            }
            .overlay(alignment: .topLeading) { namePill.padding(10) }
            .overlay(alignment: .topTrailing) { pointsPill.padding(10) }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upgrade-hero")
        .task(id: "\(who)-\(care.store.revision)") { await load() }
    }

    private var namePill: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(config.heroName).font(SK.font(15, .black)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(config.winLine).font(SK.font(11, .bold)).foregroundStyle(SK.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(.white.opacity(0.88)))
    }

    private var pointsPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").font(.system(size: 13, weight: .black)).foregroundStyle(SK.honeyDeep)
            Text("\(config.points) point\(config.points == 1 ? "" : "s")").font(SK.font(14, .black)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 12).frame(minHeight: 34).background(Capsule().fill(.white.opacity(0.88)))
        .accessibilityElement(children: .ignore).accessibilityLabel("\(config.points) points").accessibilityIdentifier("upgrade-points")
    }

    /// The white chip that pops up over the picture and floats away.
    private var chip: some View {
        Text(chipText).font(SK.font(15, .black)).foregroundStyle(SK.ink).lineLimit(1).fixedSize()
            .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(.white).shadow(color: .black.opacity(0.15), radius: 4, y: 2))
            .keyframeAnimator(initialValue: ChipPose(), trigger: chipSerial) { content, p in
                content.opacity(p.opacity).scaleEffect(p.scale).offset(y: p.rise)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) { LinearKeyframe(1, duration: 0.12); LinearKeyframe(1, duration: 0.88); LinearKeyframe(0, duration: 0.6) }
                KeyframeTrack(\.scale) { SpringKeyframe(1, duration: 0.25, spring: .bouncy); LinearKeyframe(1, duration: 1.35) }
                KeyframeTrack(\.rise) { LinearKeyframe(0, duration: 0.2); LinearKeyframe(reduceMotion ? 0 : -42, duration: 1.4) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func load() async {
        image = HeadPortraitCache.shared.cached(key(), care: care)
        if image == nil { image = await HeadPortraitCache.shared.image(key(), care: care) }
    }
}
