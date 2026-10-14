import SwiftUI

struct HomeView<Stage: View>: View {
    var store: GameStore
    var events: CareEvents
    var persist: () -> Void
    @ViewBuilder var stage: () -> Stage
    var onAdopted: (String) -> Void = { _ in }

    @State private var showKennel = false
    @State private var tick = 0

    private var selected: BlobState? {
        store.blobs.first { $0.id == events.selectedID } ?? store.blobs.first
    }

    var body: some View {
        ZStack {
            stage().ignoresSafeArea()
            VStack(spacing: 0) {
                chips.padding(.top, 8)
                Spacer()
                toolbar.padding(.bottom, 10)
            }
            .padding(.horizontal, 14)
            if let id = events.statusID, let blob = store.blob(id) {
                Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { events.hideStatus() }
                BlobStatusCard(blob: blob) { events.hideStatus() }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(UITheme.spring, value: events.statusID)
        .fullScreenCover(isPresented: $showKennel) {
            KennelView(store: store, persist: persist, onAdopted: onAdopted) { showKennel = false }
        }
        .onAppear {
            if events.selectedID == nil || store.blob(events.selectedID!) == nil { events.selectedID = store.blobs.first?.id }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(store.blobs) { b in
                let isSel = b.id == selected?.id
                Button {
                    events.selectedID = b.id; tick += 1
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(b.breed.core).frame(width: 12, height: 12)
                        Text(b.name).font(UITheme.body(15))
                    }
                    .foregroundStyle(UITheme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(isSel ? UITheme.cream : UITheme.cream.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(isSel ? b.breed.core : .clear, lineWidth: 2.5))
                    .shadow(color: UITheme.ink.opacity(isSel ? 0.2 : 0.08), radius: 6, y: 3)
                    .scaleEffect(isSel ? 1.05 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
            Spacer()
        }
        .animation(UITheme.spring, value: selected?.id)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            CareButton(icon: "fork.knife", label: "Feed", tint: Color(hex: "#E58A4A")) { act { store.feed($0); events.send(.feed($0)) } }
            CareButton(icon: "drop.fill", label: "Water", tint: Color(hex: "#5BA9D6")) { act { store.water($0); events.send(.water($0)) } }
            CareButton(icon: "bubbles.and.sparkles.fill", label: "Bathe", tint: Color(hex: "#8F7BD6")) { act { store.bathe($0, amount: 0.6); events.send(.bathe($0)) } }
            CareButton(icon: "soccerball", label: "Play", tint: Color(hex: "#6CBF7A")) { act { events.send(.play($0)) } }
            if store.canAdopt {
                CareButton(icon: "plus", label: "Adopt", tint: UITheme.ink) { showKennel = true; tick += 1 }
            }
        }
        .padding(10)
        .softPanel(radius: 32)
    }

    private func act(_ f: (UUID) -> Void) {
        guard let id = selected?.id else { return }
        f(id)
        persist()
        tick += 1
    }
}

private struct CareButton: View {
    var icon: String
    var label: String
    var tint: Color
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 26, weight: .bold, design: .rounded))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(tint.opacity(0.18)))
                    .foregroundStyle(tint)
                Text(label).font(UITheme.caption(12)).foregroundStyle(UITheme.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BouncyStyle())
        .accessibilityLabel(label)
    }
}

private struct BouncyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

#Preview("Home") {
    let s = PreviewSupport.store(blobs: 2)
    return HomeView(store: s, events: CareEvents(), persist: {}) { HUDPlaceholderStage(store: s) }
}
