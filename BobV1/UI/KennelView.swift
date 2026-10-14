import SwiftUI

/// The adoption shop. Works as onboarding (no `onClose`) or as a sheet from HomeView.
struct KennelView: View {
    var store: GameStore
    var persist: () -> Void = {}
    var onAdopted: (String) -> Void = { _ in }
    var onClose: (() -> Void)? = nil
    /// Show the X button (false during first-run onboarding).
    var dismissible = true
    /// ImageRenderer can't draw ScrollView; snapshots set this to lay content out plainly.
    var flat = false

    @State private var breed: BreedID = .berry
    @State private var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    @State private var chosen: AdoptionCandidate?
    @State private var rerolls = 0

    private var candidates: [AdoptionCandidate] { KennelGenerator.candidates(for: breed, seed: seed) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [UITheme.cream, UITheme.peach.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if flat { content } else {
                ScrollView { content }.scrollIndicators(.hidden)
            }
        }
        .sheet(item: $chosen) { c in
            NamingSheet(store: store, candidate: c, persist: persist) { name in
                chosen = nil
                onAdopted(name)
                onClose?()
            }
            .presentationDetents([.large])
            .presentationCornerRadius(34)
        }
        .sensoryFeedback(.selection, trigger: breed)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: rerolls)
    }

    private var content: some View {
        VStack(spacing: 20) {
            header
            breedPicker
            candidateSection
        }
        .padding(.horizontal, 18).padding(.bottom, 30).padding(.top, 8)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Blob Kennel").font(UITheme.title(32))
                Text(store.canAdopt ? "Pick a breed, then meet the litter." : "Your home is full")
                    .font(UITheme.caption(15)).foregroundStyle(UITheme.inkSoft)
            }
            Spacer()
            if dismissible, let onClose {
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(width: 40, height: 40).background(Circle().fill(UITheme.panelDeep.opacity(0.7)))
                }
                .accessibilityLabel("Close")
            }
        }
        .foregroundStyle(UITheme.ink)
        .padding(.top, 12)
    }

    private var breedPicker: some View {
        HStack(spacing: 10) {
            ForEach(BreedID.allCases) { b in
                BreedCard(breed: b, selected: b == breed)
                    .onTapGesture { withAnimation(UITheme.spring) { breed = b; seed = .random(in: 1...UInt64.max) } }
                    .accessibilityAddTraits(b == breed ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var candidateSection: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Meet the \(breed.spec.displayName) litter").font(UITheme.title(20))
                Spacer()
                Button {
                    withAnimation(UITheme.spring) { seed = .random(in: 1...UInt64.max); rerolls += 1 }
                } label: { Label("Show me others", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(PillButtonStyle(tint: breed.deep, filled: false, compact: true))
            }
            .foregroundStyle(UITheme.ink)
            HStack(alignment: .top, spacing: 10) {
                ForEach(candidates) { c in
                    CandidateCard(candidate: c, enabled: store.canAdopt) { chosen = c }
                }
            }
            .id(seed)
            .transition(.opacity)
            if !store.canAdopt {
                Text("Your home is full").font(UITheme.body(15)).foregroundStyle(UITheme.inkSoft)
                    .padding(.top, 4)
            }
        }
    }
}

private struct BreedCard: View {
    var breed: BreedID
    var selected: Bool
    var body: some View {
        VStack(spacing: 6) {
            BlobPlaceholder(breed: breed).frame(height: 84)
            Text(breed.spec.displayName).font(UITheme.body(18))
            Text(breed.spec.blurb).font(UITheme.caption(11)).multilineTextAlignment(.center)
                .foregroundStyle(UITheme.inkSoft).lineLimit(4, reservesSpace: true)
            Text(breed.featureDescription).font(UITheme.caption(11)).bold()
                .multilineTextAlignment(.center).foregroundStyle(breed.deep).lineLimit(3, reservesSpace: true)
        }
        .foregroundStyle(UITheme.ink)
        .padding(10)
        .frame(maxWidth: .infinity)
        .softPanel(radius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(breed.core, lineWidth: selected ? 3.5 : 0))
        .scaleEffect(selected ? 1.03 : 0.97)
        .animation(UITheme.spring, value: selected)
        .contentShape(Rectangle())
    }
}

private struct CandidateCard: View {
    var candidate: AdoptionCandidate
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        let b = candidate.breed
        VStack(spacing: 6) {
            BlobPlaceholder(breed: b, look: candidate.look).frame(height: 96)
            Text(candidate.personality.displayName).font(UITheme.body(16))
            Text(candidate.personality.blurb).font(UITheme.caption(11)).multilineTextAlignment(.center)
                .foregroundStyle(UITheme.inkSoft).lineLimit(4, reservesSpace: true)
            VStack(spacing: 2) {
                tag(candidate.look.marking.displayName)
                tag(sizeWord)
                if b != .berry { tag(featureWord) }
            }
            Button(action: action) { Text("Choose") }
                .buttonStyle(PillButtonStyle(tint: b.deep, compact: true))
                .disabled(!enabled).opacity(enabled ? 1 : 0.4)
        }
        .foregroundStyle(UITheme.ink)
        .padding(8)
        .frame(maxWidth: .infinity)
        .softPanel(radius: 22)
        .sensoryFeedback(.impact(weight: .medium), trigger: candidate.id)
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(UITheme.caption(11)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(candidate.breed.light.opacity(0.35)))
    }
    private var sizeWord: String {
        let s = candidate.look.sizeScale
        return s < 0.98 ? "Petite" : s > 1.02 ? "Big" : "Medium"
    }
    private var featureWord: String {
        let f = candidate.look.featureScale
        let noun = candidate.breed == .mint ? "spikes" : (candidate.look.featureCount >= 2 ? "antennae" : "antenna")
        return (f < 0.95 ? "Small " : f > 1.1 ? "Big " : "Neat ") + noun
    }
}

private struct NamingSheet: View {
    var store: GameStore
    var candidate: AdoptionCandidate
    var persist: () -> Void
    var done: (String) -> Void

    @State private var name = ""
    @State private var error: String?
    @State private var welcome: String?
    @State private var dice = 0
    @FocusState private var focused: Bool

    var body: some View {
        let b = candidate.breed
        ZStack {
            UITheme.cream.ignoresSafeArea()
            VStack(spacing: 18) {
                BlobPlaceholder(breed: b, look: candidate.look).frame(height: 150)
                if let welcome {
                    Text(welcome).font(UITheme.title(26)).foregroundStyle(UITheme.ink)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("Name your \(candidate.personality.displayName) \(b.spec.displayName)")
                        .font(UITheme.title(22)).foregroundStyle(UITheme.ink)
                    HStack {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focused)
                            .onSubmit { confirm() }
                            .onChange(of: name) { _, v in
                                if v.count > 12 { name = String(v.prefix(12)) }
                                error = nil
                            }
                            .font(UITheme.body(20))
                        Button {
                            name = NameSuggester.random(excluding: store.blobs.map(\.name)); dice += 1
                        } label: { Image(systemName: "dice.fill").font(.system(size: 22)) }
                            .accessibilityLabel("Suggest a name")
                    }
                    .foregroundStyle(UITheme.ink)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.7)))
                    if let error {
                        Text(error).font(UITheme.caption(14)).foregroundStyle(.red.opacity(0.8))
                    } else {
                        Text("\(name.trimmingCharacters(in: .whitespaces).count)/12").font(UITheme.caption())
                            .foregroundStyle(UITheme.inkSoft)
                    }
                    Button("Take \(name.isEmpty ? "me" : name) home") { confirm() }
                        .buttonStyle(PillButtonStyle(tint: b.deep))
                }
                Spacer()
            }
            .padding(24)
        }
        .animation(UITheme.spring, value: welcome)
        .sensoryFeedback(.selection, trigger: dice)
        .sensoryFeedback(.success, trigger: welcome)
        .sensoryFeedback(.error, trigger: error)
        .onAppear { name = candidate.suggestedName }
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.adopt(candidate: candidate, name: trimmed)
            persist()
            focused = false
            welcome = "Welcome home, \(trimmed)!"
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                done(trimmed)
            }
        } catch AdoptError.invalidName {
            error = "Names need 1 to 12 characters."
        } catch AdoptError.duplicateName {
            error = "You already have a Blob called that."
        } catch AdoptError.tooManyBlobs {
            error = "Your home is full."
        } catch {
            self.error = "Something went wrong."
        }
    }
}

#Preview("Kennel") {
    KennelView(store: PreviewSupport.store(blobs: 0))
}
