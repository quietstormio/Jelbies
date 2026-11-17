//
//  ForfeitHome.swift
//  "Go home" in the middle of a competition (the Jelly Race, the Jelly Show, Jelly Volleyball): a small Home pill in the top-left corner, then a card
//  ("Go home? This counts as a forfeit.") that holds the competition still behind it. "Go home" takes the usual fade home with NOTHING settled: no Drops,
//  trophy, ribbon, points or stats, no result screen, no win. A Bag food used as the start power-up (and a race perk eaten before) stays spent; there is no Drops entry fee.
//

import SwiftUI

extension GameCare {
    /// A competition is live and can be left: the race, the show (before its results) or the match (before it is over).
    var canForfeit: Bool { race.canForfeit || show.canForfeit || volley.canForfeit }

    /// The Home pill was tapped: the card comes up and the competition waits (the show's dance keeps its song's clock).
    func askForfeit() { guard canForfeit else { return }; forfeitAsk = true }

    /// "Keep playing" / a tap outside the card: everything goes on exactly where it was.
    func keepPlaying() { forfeitAsk = false }

    /// "Go home": the competition ends with nothing settled and the Jelmiko go home through the usual fade (the swap puts every body, idle block and wall back).
    func confirmForfeit() {
        forfeitAsk = false
        if race.canForfeit { race.forfeit() }
        else if show.canForfeit { show.forfeit() }
        else if volley.canForfeit { volley.forfeit() }
    }

    /// Per fixed step: the card never outlives its competition (it ended behind it, or the trip went away).
    func forfeitTick() { if forfeitAsk, !canForfeit { forfeitAsk = false } }
}

/// The small "Home" pill (the Town screen's, cream).
struct ForfeitHomePill: View {
    let care: GameCare
    var body: some View {
        Button { AudioHub.shared.uiTap(); care.askForfeit() } label: {
            HStack(spacing: 5) {
                Image(systemName: "house.fill").font(.system(size: 15, weight: .heavy))
                Text("Home").font(SK.font(15, .heavy))
            }
            .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.85)).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 5, y: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go home").accessibilityHint("Asks to leave this competition. It counts as a forfeit.")
        .accessibilityIdentifier("forfeit-home")
    }
}

/// The confirm card over a dimmed screen; a tap outside it is "Keep playing".
struct ForfeitHomeCard: View {
    let care: GameCare
    var body: some View {
        if care.forfeitAsk, care.canForfeit {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { AudioHub.shared.uiTap(); care.keepPlaying() }
                    .accessibilityHidden(true)
                VStack(spacing: 14) {
                    Text("Go home?").font(SK.font(22, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                    Text("This counts as a forfeit.").font(SK.font(16, .semibold)).foregroundStyle(SK.ink.opacity(0.8)).multilineTextAlignment(.center)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { keep; go }
                        VStack(spacing: 10) { go; keep }
                    }
                }
                .padding(20).frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0xFFFDF8))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(hex: 0x4D331F).opacity(0.10), lineWidth: 1))
                        .shadow(color: Color(hex: 0x5A3A2A).opacity(0.3), radius: 10, y: 4)
                )
                .padding(24)
                .accessibilityElement(children: .contain).accessibilityIdentifier("forfeit-card")
            }
            .transition(.opacity)
        }
    }
    private var keep: some View {
        Button { AudioHub.shared.uiTap(); care.keepPlaying() } label: {
            Text("Keep playing").font(SK.font(17, .heavy)).foregroundStyle(SK.ink).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 22).frame(minHeight: 44)
                .background(Capsule().fill(SK.honey)).contentShape(Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier("forfeit-keep")
    }
    private var go: some View { TourCapsuleButton(title: "Go home", hint: "Leaves with no rewards", id: "forfeit-go") { AudioHub.shared.uiTap(); care.confirmForfeit() } }
}
