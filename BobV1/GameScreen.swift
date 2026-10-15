//
//  GameScreen.swift
//  The game: Bob in the living room, full screen. The HUD is a ZStack overlay on top of the stage:
//  small gear (top-left) opens the studio; `hud` is the slot for the care menu (bottom-right).
//

import SwiftUI

struct GameScreen: View {
    @State private var model = GameScreen.makeGameModel()
    @State private var showStudio = false
    @State private var studioModel = ContentView.makeStudioModel()
    @State private var menuOpen = UserDefaults.standard.integer(forKey: "GameMenuOpen") != 0

    var body: some View {
        ZStack {
            MelonStage(model: model)
                .ignoresSafeArea()

            // dim scrim behind the care menu; a tap anywhere outside collapses it
            Color(red: 0.30, green: 0.20, blue: 0.14)
                .opacity(menuOpen ? 0.22 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(menuOpen)
                .onTapGesture { withAnimation(CareMenu.spring) { menuOpen = false } }
                .animation(.easeInOut(duration: 0.25), value: menuOpen)

            // HUD
            ZStack {
                VStack {
                    HStack {
                        GameCircleButton(systemName: "gearshape", label: "Studio") {
                            model.paused = true
                            showStudio = true
                        }
                        .accessibilityIdentifier("studio-button")
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        careSlot
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.black)
        .fullScreenCover(isPresented: $showStudio, onDismiss: { model.paused = false }) {
            ZStack(alignment: .topTrailing) {
                MelonScreen(model: studioModel) {
                    MelonStage(model: studioModel)
                }
                GameCircleButton(systemName: "xmark", label: "Close studio") { showStudio = false }
                    .accessibilityIdentifier("studio-close")
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
    }

    /// Bottom-right care menu: one round button that expands upward into Feed / Water / Call.
    private var careSlot: some View {
        CareMenu(open: $menuOpen, care: model.care)
            .padding(.trailing, 4)
            .padding(.bottom, 12)
            .task { await GameScreen.runDebugScript(model: model, open: $menuOpen) }
    }

    /// Harmless launch args for captures: -GameAction feed|water|call|wave (after 4 s), -GameScript 1 (timed demo of everything).
    @MainActor static func runDebugScript(model: MelonModel, open: Binding<Bool>) async {
        let d = UserDefaults.standard
        let care = model.care
        func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
        func idleWait() async {
            await sleep(1.5)
            for _ in 0..<80 where care.bowlOut || care.busy { await sleep(0.5) }
        }
        func choose(_ f: () -> Void) async {
            withAnimation(CareMenu.spring) { open.wrappedValue = true }
            await sleep(1.4)
            f()
            withAnimation(CareMenu.spring) { open.wrappedValue = false }
        }
        if let a = d.string(forKey: "GameAction") {
            await sleep(d.double(forKey: "GameActionDelay") > 0 ? d.double(forKey: "GameActionDelay") : 4)
            switch a {
            case "feed": care.feed()
            case "water": care.water()
            case "call": care.call()
            default: care.wave()
            }
        }
        if d.integer(forKey: "GameScript") != 0 {
            await sleep(16)
            await choose { care.feed() }
            await idleWait()
            await sleep(5)
            await choose { care.water() }
            await idleWait()
            await sleep(5)
            await choose { care.call() }
            await idleWait()
        }
    }

    static func makeGameModel() -> MelonModel {
        let m = MelonModel()
        m.gameMode = true
        m.palette = .blush
        return m
    }
}

/// Small matte cream circle with an SF Symbol.
struct GameCircleButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(red: 0.97, green: 0.94, blue: 0.88)).opacity(0.92))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Care menu

/// The expanding care button (bottom-right): paw -> cross, with Feed / Water / Call stacked above it.
struct CareMenu: View {
    @Binding var open: Bool
    let care: GameCare

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.88)
    static let brown = Color(red: 0.42, green: 0.34, blue: 0.30)

    private struct Item: Identifiable {
        let id: String, title: String, symbol: String
    }
    // top to bottom
    private let items = [Item(id: "care-feed", title: "Feed", symbol: "fork.knife"),
                         Item(id: "care-water", title: "Water", symbol: "drop.fill"),
                         Item(id: "care-call", title: "Call", symbol: "hand.wave.fill")]

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            if open {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                }
            }
            mainButton
        }
    }

    private func enabled(_ item: Item) -> Bool {
        switch item.id { case "care-feed": return !care.foodOut; case "care-water": return !care.waterOut; default: return true }
    }

    private func row(_ item: Item, index: Int) -> some View {
        let fromBottom = items.count - 1 - index          // 0 = nearest the main button
        let on = enabled(item)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            switch item.id {
            case "care-feed": care.feed()
            case "care-water": care.water()
            default: care.call()
            }
            withAnimation(Self.spring) { open = false }
        } label: {
            HStack(spacing: 10) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.brown)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(Capsule().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.18), radius: 6, y: 2))
                Image(systemName: item.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Self.brown)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.22), radius: 7, y: 3))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            }
            .opacity(on ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityIdentifier(item.id)
        .accessibilityLabel(item.title)
        .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
            .combined(with: .offset(y: 24 + CGFloat(fromBottom) * 10))
            .animation(Self.spring.delay(Double(fromBottom) * 0.05)))
    }

    private var mainButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(Self.spring) { open.toggle() }
        } label: {
            ZStack {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .opacity(open ? 0 : 1)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .scaleEffect(open ? 0.4 : 1)
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .bold))
                    .opacity(open ? 1 : 0)
                    .rotationEffect(.degrees(open ? 0 : -90))
                    .scaleEffect(open ? 1 : 0.4)
            }
            .foregroundStyle(Self.brown)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Self.cream).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.28), radius: 9, y: 4))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("care-menu")
        .accessibilityLabel(open ? "Close care menu" : "Care menu")
    }
}
