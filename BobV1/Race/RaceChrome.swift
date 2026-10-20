//
//  RaceChrome.swift
//  Jelly Circuit's screen furniture: the 3-2-1-GO numerals, the two big foot buttons at the bottom, the placings card and the white fade.
//  The cream / brown look of the care menu and the focus UI.
//

import SwiftUI

struct RaceChrome: View {
    let care: GameCare
    private var race: RaceFlow { care.race }
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    @Environment(\.verticalSizeClass) private var vsc
    private var compact: Bool { vsc == .compact }          // a phone on its side: the foot buttons go to the two sides, the track stays in the middle

    var body: some View {
        ZStack {
            if race.trackVisible, race.isDrill {
                DrillChrome(care: care)
            } else if race.trackVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if race.showsCard { RacePlacingsCard(race: race) { race.goHome() }.padding(.horizontal, 24).transition(.scale(scale: 0.85).combined(with: .opacity)) }
                    Spacer()
                    if race.ui.phase != .results, !compact { footButtons }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) {
                    if compact, race.ui.phase != .results { sideButtons.padding(.horizontal, 14).padding(.bottom, 12) }
                }
                .animation(CareMenu.spring, value: race.showsCard)
                if race.showsCountdown { numeral(race.ui.countdown == 0 ? "" : "\(race.ui.countdown)") }
                if race.showsGo { numeral("GO!") }
            }
            Color.white.opacity(Double(race.wipe)).ignoresSafeArea().allowsHitTesting(false)
        }
        .allowsHitTesting(race.active)
        .accessibilityElement(children: .contain)
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            Text("Waddle Sprint")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(CareMenu.brown)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 2))
            if race.ui.stumbling, race.ui.tripped {
                hint("Whoops! He tripped. Practice helps")
            } else if race.ui.stumbling {
                hint("Oops! Left, right, left, right")
            } else if race.ui.stalled {
                hint("Keep tapping!")
            } else if race.ui.phase == .countdown {
                hint("Tap left, right, left, right")
            }
        }
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.15), value: race.ui.stumbling)
    }

    private func hint(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(CareMenu.brown)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(CareMenu.cream.opacity(0.92)))
            .transition(.opacity)
    }

    private func numeral(_ s: String) -> some View {
        Text(s)
            .font(.system(size: s == "GO!" ? 96 : 120, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 5)
            .shadow(color: FocusStyle.shadow.opacity(0.35), radius: 10, y: 6)
            .id(race.cueSerial)
            .transition(.scale(scale: 1.6).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityIdentifier("race-count")
            .offset(y: -60)
    }

    private var footButtons: some View {
        HStack(spacing: 14) {
            FootButton(title: "Left", id: "race-left", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive) { press(0) }
            FootButton(title: "Right", id: "race-right", symbol: "shoeprints.fill", flip: true, live: race.buttonsLive) { press(1) }
        }
        .frame(height: 170)
    }

    /// Landscape: Left at the left edge, Right at the right edge, each big enough for a thumb; the middle is left for the track.
    private var sideButtons: some View {
        HStack(alignment: .bottom, spacing: 0) {
            FootButton(title: "Left", id: "race-left", symbol: "shoeprints.fill", flip: false, live: race.buttonsLive) { press(0) }
                .frame(width: 190, height: 170)
            Spacer(minLength: 0)
            FootButton(title: "Right", id: "race-right", symbol: "shoeprints.fill", flip: true, live: race.buttonsLive) { press(1) }
                .frame(width: 190, height: 170)
        }
    }

    private func press(_ foot: Int) {
        let o = race.tap(foot: foot)
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
    let action: () -> Void
    @State private var down = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: UIImage(systemName: symbol) != nil ? symbol : "figure.walk")
                .font(.system(size: 54, weight: .bold))
                .scaleEffect(x: flip ? -1 : 1, y: 1)
                .rotationEffect(.degrees(flip ? 12 : -12))
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(CareMenu.brown)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(down ? FocusStyle.pink.opacity(0.55) : CareMenu.cream)
                .shadow(color: FocusStyle.shadow.opacity(down ? 0.12 : 0.28), radius: down ? 4 : 10, y: down ? 1 : 5)
        )
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
        .scaleEffect(down ? 0.96 : 1)
        .opacity(live ? 1 : 0.55)
        .animation(.easeOut(duration: 0.08), value: down)
        .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !down { down = true; action() } }
            .onEnded { _ in down = false })
        .accessibilityElement()
        .accessibilityLabel("\(title) foot")
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// 1st / 2nd / 3rd with names and times, the Drops earned and "Back home".
struct RacePlacingsCard: View {
    let race: RaceFlow
    let home: () -> Void

    @Environment(\.verticalSizeClass) private var vsc
    private var tight: Bool { vsc == .compact }
    private func ordinal(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : p == 3 ? "3rd" : "\(p)th" }
    private func medal(_ p: Int) -> Color {
        p == 1 ? Color(red: 0.98, green: 0.80, blue: 0.35) : p == 2 ? Color(red: 0.80, green: 0.84, blue: 0.90) : Color(red: 0.90, green: 0.68, blue: 0.52)
    }

    var body: some View {
        VStack(spacing: tight ? 6 : 14) {
            Text(race.ui.playerPlace == 1 ? "You won!" : "Finish!")
                .font(.system(size: tight ? 24 : 30, weight: .heavy, design: .rounded))
                .foregroundStyle(CareMenu.brown)
            VStack(spacing: tight ? 2 : 8) {
                ForEach(race.ui.placings, id: \.racer) { p in
                    HStack(spacing: 12) {
                        Text(ordinal(p.place))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(CareMenu.brown)
                            .frame(width: 52, height: 34)
                            .background(Capsule().fill(medal(p.place)))
                        Text(p.name)
                            .font(.system(size: 20, weight: p.isPlayer ? .heavy : .semibold, design: .rounded))
                            .foregroundStyle(CareMenu.brown)
                        Spacer()
                        Text(p.time.map { String(format: "%.1f s", $0) } ?? "-")
                            .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(CareMenu.brown.opacity(0.8))
                    }
                    .padding(.horizontal, 10).padding(.vertical, tight ? 2 : 5)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(p.isPlayer ? FocusStyle.pink.opacity(0.28) : Color.clear))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "drop.fill").foregroundStyle(FocusStyle.pink)
                Text("+\(race.ui.earned) Drops")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(CareMenu.brown)
            }
            if race.ui.waddleGain > 0.0005 {
                Text("Waddle got a little quicker")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CareMenu.brown.opacity(0.7))
            }
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                home()
            } label: {
                Text("Back home")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30).padding(.vertical, tight ? 8 : 12)
                    .background(Capsule().fill(FocusStyle.pink).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 6, y: 3))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("race-home")
        }
        .padding(.horizontal, 22).padding(.vertical, tight ? 10 : 20)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.3), radius: 16, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-card")
    }
}
