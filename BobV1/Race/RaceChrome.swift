//
//  RaceChrome.swift
//  Jelly Circuit's screen furniture: the 3-2-1-GO numerals, the two big foot buttons at the bottom, the placings card and the white fade.
//  The cream / brown look of the care menu and the focus UI.
//

import SwiftUI

struct RaceChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc

    var body: some View {
        if PadLayout.isPad {
            GeometryReader { g in
                let land = HUDLayout.isLandscape(vsc: vsc, size: g.size)          // iPad landscape, measured synchronously (no first-frame flash from the bottom to the sides)
                RaceChromeLayout(care: care, compact: land, padLandscape: land).statusBarHidden(care.race.trackVisible)
            }
        } else {
            RaceChromeLayout(care: care, compact: vsc == .compact, padLandscape: false)
        }
    }
}

private struct RaceChromeLayout: View {
    let care: GameCare
    /// A phone on its side (or an iPad in landscape): the foot buttons go to the two sides, the track stays in the middle.
    let compact: Bool
    /// iPad landscape: smaller corner buttons so the track's hedges stay visible.
    let padLandscape: Bool
    private var race: RaceFlow { care.race }
    @State private var padH: CGFloat = 0
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        ZStack {
            if race.trackVisible {
                if pullSurfaceOn { RacePullSurface(race: race) }          // (pull control: the whole screen is the control, under everything else)
                if race.holdsCard { Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { race.skipWinHold() } }          // (first place: the card waits for the celebration; a tap anywhere brings it at once)
                VStack(spacing: 0) {
                    topBar.allowsHitTesting(!race.ui.pull)          // (a pull may start on the title pill)
                    Spacer()
                    if race.showsCard { RacePlacingsCard(race: race, maxHeight: ResultCardMetrics.maxHeight(screenH: padH)) { race.goHome() }.resultCardSlot().transition(A11ySettings.shared.reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)) }
                    Spacer()
                    if race.ui.phase != .results, !compact, hasAssistButtons { footButtons }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) {
                    if compact, race.ui.phase != .results, hasAssistButtons { sideButtons.padding(.horizontal, padLandscape ? 26 : 14).padding(.bottom, padLandscape ? 28 : 12) }
                }
                .animation(CareMenu.spring, value: race.showsCard)
                if race.showsCountdown { numeral(race.ui.countdown == 0 ? "" : "\(race.ui.countdown)") }
                if race.showsGo { numeral("GO!") }
                if race.canForfeit {          // the Home pill sits outside the top bar and above the pull surface (the pull surface owns every touch under it)
                    ForfeitHomePill(care: care).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 14).padding(.top, 8)          // (the same corner as the hidden copy in the top bar)
                }
                ForfeitHomeCard(care: care)
            }
            Color.white.opacity(Double(race.wipe)).ignoresSafeArea().allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { padH = $0 }
        .allowsHitTesting(race.active)
        .accessibilityElement(children: .contain)
        .defersSystemGestures(on: race.ui.pull ? .all : .bottom)
        .onChange(of: race.ui.bonkSerial) { _, _ in rigid.impactOccurred(intensity: 0.9) }          // (the player's trip, pull control)
    }

    /// Pull control with no assist button: the whole screen is the control (the pull surface), no buttons at all.
    private var pullSurfaceOn: Bool {
        race.ui.pull && race.ui.phase != .results && (race.assist == .off || race.assist == .forgiving)
    }
    /// The foot buttons (taps) or the Hop / Cheer button of an assist (pull); none when the pull surface is the control.
    private var hasAssistButtons: Bool { !race.ui.pull || race.assist == .oneButton || race.assist == .auto }

    private var topBar: some View {
        VStack(spacing: 10) {
            // the header row, like the Show's round header: the Home pill (drawn above the pull surface, in the overlay; a hidden copy keeps its place here) then the title, centred on the pill
            HStack(spacing: 12) {
                ForfeitHomePill(care: care).hidden()
                Text(race.ui.course == .puddle ? "Jelly Race" : "Jelly Race · \(race.ui.course.title)")
                    .playFont(17, .bold)
                    .foregroundStyle(CareMenu.brown)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
                Spacer(minLength: 0)
            }
            // the hint has its own row, centred under the header
            Group {
            if race.ui.pull {
                RacePullTopRow(race: race)
            } else if race.ui.stumbling, race.ui.tripped {
                hint(race.ui.playerName.isEmpty ? "Whoops! A trip!" : "Whoops! \(race.ui.playerName) tripped")
            } else if race.ui.stumbling {
                hint("Oops! Left, right, left, right")
            } else if race.ui.stalled {
                hint("Keep tapping!")
            } else if race.ui.hurdleAhead, race.assist != .auto, !A11ySettings.shared.autoJump {
                hint("Jump!")
            } else if race.ui.inTurn {
                hint("Bend! Ease off a little")
            } else if race.ui.phase == .countdown {
                hint("Tap left, right, left, right")
            }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.15), value: race.ui.stumbling)
    }

    private func hint(_ s: String) -> some View {
        Text(s)
            .playFont(15, .semibold)
            .foregroundStyle(CareMenu.brown)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(CareMenu.cream.opacity(0.92)))
            .transition(.opacity)
    }

    private func numeral(_ s: String) -> some View {
        Text(s)
            .font(.system(size: s == "GO!" ? 96 : 120, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 3)
            .shadow(color: FocusStyle.shadow.opacity(0.35), radius: 6, y: 3)
            .id(race.cueSerial)
            .transition(A11ySettings.shared.reduceMotion ? .opacity : .scale(scale: 1.6).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityIdentifier("race-count")
            .offset(y: compact ? 16 : -60)          // (landscape: the big numeral sits below the header and the hint, never on them)
    }

    private var footButtons: some View {
        assistOrFeet(width: nil).frame(height: 170).frame(maxWidth: PadLayout.isPad ? 640 : .infinity)
    }

    /// The input for the chosen assist (Settings > Accessibility): two feet, one Step button, or a Cheer button while he runs by himself.
    @ViewBuilder
    private func assistOrFeet(width: CGFloat?) -> some View {
        switch race.assist {
        case .oneButton where race.ui.pull:
            FootButton(title: "Hop", id: "race-hop", symbol: "arrow.up.circle.fill", flip: false, live: race.buttonsLive, tilt: false, key: .space, liveValue: "\(race.ui.hopSerial) hops") { hop() }
        case .oneButton:
            HStack(spacing: 14) {
                FootButton(title: "Step", id: "race-step", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive, key: .space) { press(-1) }
                if race.ui.hasHurdles { jumpButton.frame(width: 120) }
            }
        case .auto:
            FootButton(title: "Cheer", id: "race-cheer", symbol: "hands.clap.fill", flip: false, live: true, key: .space) { cheer() }
        default:
            HStack(spacing: 14) {
                FootButton(title: "Left", id: "race-left", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive, key: .leftArrow) { press(0) }
                if race.ui.hasHurdles { jumpButton.frame(width: 104) }          // (hurdle courses: Jump between the two feet, reachable by either thumb)
                FootButton(title: "Right", id: "race-right", symbol: "shoeprints.fill", flip: true, live: race.buttonsLive, key: .rightArrow) { press(1) }
            }
        }
    }

    /// The Jump button of a hurdle course (the Jelbie does his hop; timed just before a bar he clears it).
    private var jumpButton: some View {
        FootButton(title: "Jump", id: "race-jump", symbol: "arrow.up.circle.fill", flip: false, live: race.buttonsLive, tilt: false, key: .upArrow) { jump() }
    }

    /// The one-button assist's Hop in a pull race.
    private func hop() {
        if race.hopAssist() != .ignored { light.impactOccurred(intensity: 0.6) }
    }

    private func jump() {
        if race.jump() { light.impactOccurred(intensity: 0.6) }
    }

    private func cheer() {
        AudioHub.shared.chirp(jelly: race.playerID, .happy)
        light.impactOccurred(intensity: 0.4)
    }

    /// Landscape: Left at the left edge, Right at the right edge, each big enough for a thumb; the middle is left for the track.
    private var sideButtons: some View {
        Group {
            if race.assist == .oneButton || race.assist == .auto {
                assistOrFeet(width: nil).frame(height: padLandscape ? 110 : 150).padding(.horizontal, 40).frame(maxWidth: PadLayout.isPad ? 520 : .infinity)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    FootButton(title: "Left", id: "race-left", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive, key: .leftArrow) { press(0) }
                        .frame(width: padLandscape ? 120 : 190, height: padLandscape ? 120 : 170)
                    Spacer(minLength: 0)
                    if race.ui.hasHurdles { jumpButton.frame(width: padLandscape ? 100 : 130, height: padLandscape ? 120 : 170).padding(.trailing, 10) }          // (landscape: Jump just inside the Right foot)
                    FootButton(title: "Right", id: "race-right", symbol: "shoeprints.fill", flip: true, live: race.buttonsLive, key: .rightArrow) { press(1) }
                        .frame(width: padLandscape ? 120 : 190, height: padLandscape ? 120 : 170)
                }
            }
        }
    }

    /// `foot` -1 = the one-button Step (the feet alternate by themselves).
    private func press(_ foot: Int) {
        let o = foot < 0 ? race.stepOne() : race.tap(foot: foot)
        switch o {
        case .stumble: rigid.impactOccurred(intensity: 0.9)
        case .queued: light.impactOccurred(intensity: 0.5)
        case .ignored: break
        }
    }
}

/// One big foot button. It fires on touch DOWN (no tap delay), like a game pad.
struct FootButton: View {
    let title: String
    let id: String
    let symbol: String
    let flip: Bool
    let live: Bool
    var tilt = true
    var key: KeyEquivalent?
    /// What the element reports while it is live (the pull race's Hop button reports the hops, like the pull pad); nil = nothing.
    var liveValue: String?
    let action: () -> Void
    @State private var down = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: UIImage(systemName: symbol) != nil ? symbol : "figure.walk")
                .font(.system(size: 54, weight: .bold))
                .scaleEffect(x: flip ? -1 : 1, y: 1)
                .rotationEffect(.degrees(tilt ? (flip ? 12 : -12) : 0))
            Text(title)
                .playFont(22, .heavy)
        }
        .foregroundStyle(CareMenu.brown)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(down ? FocusStyle.pink.opacity(0.55) : CareMenu.cream)
                .shadow(color: FocusStyle.shadow.opacity(down ? 0.12 : 0.28), radius: down ? 4 : 6, y: down ? 1 : 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
        .scaleEffect(down ? 0.96 : 1)
        .opacity(live ? 1 : 0.55)
        .animation(.easeOut(duration: 0.08), value: down)
        .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !down { down = true; action() } }
            .onEnded { _ in down = false })
        .background {
            if let key { Button("") { action() }.keyboardShortcut(key, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) }          // hardware keyboard / Full Keyboard Access
        }
        .accessibilityElement()
        .accessibilityLabel(title == "Left" || title == "Right" ? "\(title) foot" : title)
        .accessibilityValue(live ? (liveValue ?? "") : "waiting")
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// 1st / 2nd / 3rd with names and times, the JellyCoins earned and "Back home".
struct RacePlacingsCard: View {
    let race: RaceFlow
    /// The tallest the card may be (the chrome measures the screen); taller content scrolls inside it with "Back home" kept in view.
    var maxHeight: CGFloat = .infinity
    let home: () -> Void

    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.dynamicTypeSize) private var dts
    private var tight: Bool { vsc == .compact }
    private func ordinal(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : p == 3 ? "3rd" : "\(p)th" }
    private func medal(_ p: Int) -> Color {
        p == 1 ? Color(red: 0.98, green: 0.80, blue: 0.35) : p == 2 ? Color(red: 0.80, green: 0.84, blue: 0.90) : Color(red: 0.90, green: 0.68, blue: 0.52)
    }

    private var hasSecondary: Bool { true }

    var body: some View {
        ResultCardFrame(buttonColor: SK.pinkStrong, homeID: "race-home", maxHeight: maxHeight, hasSecondary: hasSecondary, home: home) {
            Text(race.ui.playerPlace == 1 ? "You won!" : "Finish!")
                .playFont(tight ? 26 : 30, .heavy)
                .foregroundStyle(CareMenu.brown)
                .resultText("title").accessibilityAddTraits(.isHeader)
            VStack(spacing: tight ? 3 : 4) {
                ForEach(race.ui.placings, id: \.racer) { p in
                    let place = Text(ordinal(p.place))
                        .playFont(17, .heavy)
                        .foregroundStyle(CareMenu.brown)
                        .fixedSize().resultProbe("place\(p.place)")
                        .frame(minWidth: 52, minHeight: 34)
                        .background(Capsule().fill(medal(p.place)))
                    let name = Text(p.name)
                        .playFont(20, p.isPlayer ? .heavy : .semibold)
                        .foregroundStyle(CareMenu.brown)
                        .multilineTextAlignment(.leading).lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true).resultProbe("name\(p.place)")
                    let time = Text(p.time.map { String(format: "%.1f s", $0) } ?? "-")
                        .playFont(18, .semibold).monospacedDigit()
                        .foregroundStyle(CareMenu.brown.opacity(0.85))
                        .fixedSize().resultProbe("time\(p.place)")
                    Group {
                        if dts.isAccessibilitySize {
                            // the largest text sizes: the place and the time on one line, the name under them (nothing side by side to squeeze)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { place; Spacer(minLength: 6); time }
                                name
                            }
                        } else {
                            HStack(spacing: 12) { place; name.layoutPriority(1); Spacer(minLength: 6); time }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, tight ? 2 : 3)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(p.isPlayer ? FocusStyle.pink.opacity(0.28) : Color.clear))
                    .accessibilityElement(children: .combine)
                }
            }
        } secondary: {
            VStack(spacing: 8) {
                ResultCoinsLine(coinText: race.ui.earned.coinText)
                if race.assist == .auto {
                    Text("Auto run pays half the JellyCoins")
                        .playFont(14, .medium)
                        .foregroundStyle(CareMenu.brown.opacity(0.85))
                        .resultText("assist")
                        .accessibilityIdentifier("race-auto-note")
                }
            }
            VStack(spacing: 8) {
                if race.ui.pointsEarned > 0 { ResultPointsRow(title: "Jelly Race points  +\(race.ui.pointsEarned)", detail: "\(race.ui.playerName) now has \(race.ui.pointsAfter) to spend", id: "race-points") }
                if race.awards.newRibbon { ResultRewardRow(symbol: "rosette", text: "New ribbon!", id: "race-new-ribbon", probe: "ribbon") }
                if let t = race.awards.trophies.first {
                    ResultRewardRow(symbol: "trophy.fill", text: race.awards.trophies.count > 1 ? "Trophy! \(t.title) +\(race.awards.trophies.count - 1)" : "Trophy! \(t.title)", id: "race-trophy", probe: "trophy")
                }
            }
            if let t = race.unlockedNow {
                Text("\(t.title) course unlocked!")
                    .playFont(15, .heavy)
                    .foregroundStyle(SK.pinkStrong)
                    .resultText("unlocked")
                    .accessibilityIdentifier("race-unlocked")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-card")
    }
}
