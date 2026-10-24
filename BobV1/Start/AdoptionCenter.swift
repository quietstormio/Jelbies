//
//  AdoptionCenter.swift
//  Pick a Jelbie (one on show at a time, in 3D), name it, bring it home. The first adoption of a new game is free; later ones (Town, Adoption
//  Center) cost Drops (AdoptionPrice), show "Already home" for the ones you have and stop at 3. Works in portrait and landscape.
//

import SwiftUI

struct AdoptionTrait {
    let signature: String, symbol: String, personality: String
    static func of(_ c: Int) -> AdoptionTrait {
        switch c {
        case 1: return AdoptionTrait(signature: "Gummy spines", symbol: "triangle.fill", personality: "Energetic: always off zooming, bouncing and playing chase.")
        case 2: return AdoptionTrait(signature: "Head daisy", symbol: "camera.macro", personality: "Calm: loves a sit, a stretch and a look out the window.")
        case 3: return AdoptionTrait(signature: "Little wings", symbol: "bird.fill", personality: "Playful and floaty: flaps, hops, dances and nuzzles.")
        default: return AdoptionTrait(signature: "Classic", symbol: "circle.fill", personality: "Balanced: a bit of everything, and happy with anything.")
        }
    }
}

struct AdoptionCenter: View {
    let mode: StartFlow.AdoptMode
    var done: (Int, String) -> Void
    var cancel: () -> Void

    @State private var pick = 0
    @State private var naming = false
    @State private var name = ""
    @State private var celebrating = false
    @State private var wallet = DropsWallet()
    @State private var home: [Int] = []
    @FocusState private var nameFocused: Bool
    @Environment(\.verticalSizeClass) private var vsc

    private var price: Int? { mode == .first ? 0 : AdoptionPrice.next(home: home.count) }
    private var isHome: Bool { home.contains(pick) }
    private var canAdopt: Bool { !isHome && (price.map { $0 <= wallet.count } ?? false) }
    private var landscape: Bool { vsc == .compact }
    private func tint(_ c: Int) -> Color { let t = JellyRoster.tint(c); return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z)) }

    var body: some View {
        ZStack {
            ShowcaseStage(roster: [pick], focusFirst: true).id(pick)
            LinearGradient(colors: [SK.ink.opacity(0.35), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea().allowsHitTesting(false)
            Color.clear.contentShape(Rectangle()).gesture(swipe)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if landscape {
                    HStack { Spacer(); card.frame(width: 360) }
                } else {
                    card.frame(maxWidth: 520)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            if celebrating { Celebration(name: name).transition(.opacity) }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            home = mode == .first ? [] : JellyRoster.savedIDs()
            pick = (0..<JellyRoster.characterCount).first { !home.contains($0) } ?? 0
        }
        .accessibilityIdentifier("adoption-center")
    }

    // MARK: pieces

    private var topBar: some View {
        HStack {
            if mode == .more || naming {
                Button { AudioHub.shared.uiTap(); if naming { withAnimation(.easeOut(duration: 0.2)) { naming = false } } else { cancel() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: naming ? "chevron.left" : "house.fill").font(.system(size: 15, weight: .heavy))
                        Text(naming ? "Back" : "Home").font(SK.font(15, .heavy))
                    }
                    .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().fill(Color.white.opacity(0.88)))
                }
                .buttonStyle(.plain).accessibilityIdentifier("adopt-back")
            }
            Text("Adoption Center").font(SK.font(20, .black)).foregroundStyle(SK.cream).shadow(color: SK.ink.opacity(0.6), radius: 3, y: 1)
                .padding(.leading, 6).accessibilityAddTraits(.isHeader)
            Spacer()
            if mode == .more { DropsPill(wallet: wallet) }
        }
    }

    private var card: some View {
        VStack(spacing: 10) {
            if naming { nameCard } else { browseCard }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 12, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .padding(.bottom, 6)
    }

    private var browseCard: some View {
        let t = AdoptionTrait.of(pick)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                arrow("chevron.left", "Previous Jelbie") { step(-1) }
                VStack(spacing: 4) {
                    Text(JellyRoster.baseNames[pick]).font(SK.font(30, .black)).foregroundStyle(SK.ink)
                    HStack(spacing: 8) {
                        Circle().fill(tint(pick)).frame(width: 16, height: 16).overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                        Image(systemName: t.symbol).font(.system(size: 12, weight: .heavy)).foregroundStyle(SK.muted)
                        Text(t.signature).font(SK.font(14, .bold)).foregroundStyle(SK.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                arrow("chevron.right", "Next Jelbie") { step(1) }
            }
            Text(t.personality).font(SK.font(15, .semibold)).foregroundStyle(SK.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                ForEach(0..<JellyRoster.characterCount, id: \.self) { i in
                    Circle().fill(i == pick ? tint(i) : tint(i).opacity(0.4)).frame(width: i == pick ? 14 : 10, height: i == pick ? 14 : 10)
                        .overlay(Circle().strokeBorder(SK.ink.opacity(i == pick ? 0.5 : 0), lineWidth: 1.5))
                }
            }
            .accessibilityHidden(true)
            primary(adoptTitle, enabled: canAdopt, id: "adopt-pick") { withAnimation(.easeOut(duration: 0.2)) { name = JellyRoster.baseNames[pick]; naming = true }; nameFocused = true }
            if mode == .more, !isHome, price != nil, !canAdopt {
                Text("Earn Drops in races to bring \(JellyRoster.baseNames[pick]) home.").font(SK.font(13, .bold)).foregroundStyle(SK.muted)
            }
        }
    }

    private var adoptTitle: String {
        if isHome { return "Already home" }
        guard let p = price else { return "Your room is full: 3 Jelbies" }
        return p == 0 ? "Adopt \(JellyRoster.baseNames[pick]) (free)" : "Adopt \(JellyRoster.baseNames[pick]) for \(p) Drops"
    }

    private var nameCard: some View {
        VStack(spacing: 10) {
            Text("What will you call \(JellyRoster.baseNames[pick])?").font(SK.font(20, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
            TextField(JellyRoster.baseNames[pick], text: $name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
                .font(SK.font(24, .heavy)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(Capsule().fill(Color.white.opacity(0.9)))
                .overlay(Capsule().strokeBorder(tint(pick), lineWidth: 3))
                .onChange(of: name) { _, v in if v.count > 14 { name = String(v.prefix(14)) } }
                .onSubmit { bringHome() }
                .accessibilityIdentifier("adopt-name")
            primary("Bring \(finalName) home", enabled: true, id: "adopt-bring-home") { bringHome() }
        }
    }

    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? JellyRoster.baseNames[pick] : t
    }

    private func primary(_ title: String, enabled: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            Text(title).font(SK.font(18, .black)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54).padding(.horizontal, 10)
                .background(Capsule().fill(enabled ? SK.honey : Color.black.opacity(0.08)))
                .overlay(Capsule().strokeBorder(enabled ? SK.honeyDeep : .clear, lineWidth: 2))
                .opacity(enabled ? 1 : 0.65)
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier(id)
    }

    private func arrow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .black)).foregroundStyle(SK.ink)
                .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.85))).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard !naming, abs(v.translation.width) > abs(v.translation.height) else { return }
            step(v.translation.width < 0 ? 1 : -1)
        }
    }
    private func step(_ d: Int) {
        guard !naming else { return }
        let n = JellyRoster.characterCount
        pick = (pick + d + n) % n
    }

    // MARK: bring home

    private func bringHome() {
        guard !celebrating, canAdopt, let p = price else { return }
        name = finalName
        if p > 0, !wallet.spend(p) { return }
        nameFocused = false
        AudioHub.shared.play(.coin)
        withAnimation(.easeIn(duration: 0.2)) { celebrating = true }
        let c = pick, n = name
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            done(c, n)
        }
    }
}

/// The small "bring home" moment: sparkles and hearts float up over the Jelbie.
private struct Celebration: View {
    let name: String
    @State private var go = false
    var body: some View {
        ZStack {
            Color.white.opacity(go ? 0 : 0.5).ignoresSafeArea()
            ForEach(0..<16, id: \.self) { i in
                let a = Double(i) / 16 * 2 * .pi
                Image(systemName: i % 3 == 0 ? "sparkle" : "heart.fill")
                    .font(.system(size: CGFloat(18 + (i % 4) * 5), weight: .black))
                    .foregroundStyle(i % 3 == 0 ? SK.honeyDeep : SK.pink)
                    .offset(x: go ? CGFloat(cos(a)) * 150 : 0, y: go ? CGFloat(sin(a)) * 150 - 80 : 20)
                    .opacity(go ? 0 : 1).scaleEffect(go ? 1.2 : 0.4)
                    .animation(.easeOut(duration: 1.5).delay(Double(i % 4) * 0.06), value: go)
            }
            Text("\(name) is coming home!").font(SK.font(28, .black)).foregroundStyle(SK.cream)
                .shadow(color: SK.ink.opacity(0.7), radius: 4, y: 2).multilineTextAlignment(.center).padding(.horizontal, 24)
                .scaleEffect(go ? 1 : 0.6).animation(.spring(response: 0.5, dampingFraction: 0.6), value: go)
        }
        .allowsHitTesting(true)
        .onAppear { go = true }
        .accessibilityElement(children: .combine)
    }
}
