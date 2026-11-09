//
//  ParentGate.swift
//  "Ask a grown-up": the hold-to-pass gate in front of everything that leaves the app (Settings, Shortcuts, the share sheet).
//

import SwiftUI
import UIKit

/// The modal itself: opaque cream card, one brown button the adult holds for 2 seconds, and Cancel.
/// VoiceOver: the button's activate action asks one more deliberate question before it passes.
struct ParentGateView: View {
    var pass: () -> Void
    var cancel: () -> Void
    @State private var confirmVO = false

    var body: some View {
        ZStack {
            FocusStyle.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 34, weight: .semibold)).foregroundStyle(FocusStyle.brown)
                        .accessibilityHidden(true)
                    Text("Ask a grown-up")
                        .font(SK.font(24, .heavy)).foregroundStyle(FocusStyle.brown)
                        .accessibilityAddTraits(.isHeader)
                    Text("This goes outside Jelbies. A grown-up can press and hold the button for 2 seconds.")
                        .font(SK.font(16, .medium)).foregroundStyle(FocusStyle.brown)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    HoldToConfirm(title: "Hold for a grown-up", id: "parent-gate-hold", tint: FocusStyle.brown,
                                  done: pass, accessibilityActivate: { confirmVO = true })
                        .padding(.top, 6)
                    Button { cancel() } label: {
                        Text("Cancel").font(SK.font(18, .bold)).foregroundStyle(FocusStyle.brown)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Capsule().strokeBorder(FocusStyle.brown, lineWidth: 2))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("parent-gate-cancel")
                }
                .padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .confirmationDialog("Are you a grown-up?", isPresented: $confirmVO, titleVisibility: .visible) {
            Button("Yes, I am a grown-up") { pass() }
            Button("Cancel", role: .cancel) { }
        }
        .accessibilityIdentifier("parent-gate")
    }
}

private struct ParentGateModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onPass: () -> Void
    @State private var passed = false

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented, onDismiss: {
            // Run the action only once the gate is fully gone, so Settings / the share sheet do not fight the cover.
            if passed { passed = false; onPass() }
        }) {
            ParentGateView(pass: { passed = true; isPresented = false }, cancel: { passed = false; isPresented = false })
        }
    }
}

extension View {
    /// Shows "Ask a grown-up" when isPresented turns true; onPass runs only after the adult holds the button.
    func parentGate(isPresented: Binding<Bool>, onPass: @escaping () -> Void) -> some View {
        modifier(ParentGateModifier(isPresented: isPresented, onPass: onPass))
    }
}

/// Every way out of the app, in one place.
enum ParentGateActions {
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
    static func openShortcuts() {
        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
    }
}

/// UIKit share sheet, shown only after the gate has passed (ShareLink cannot be gated).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) { }
}

/// A Share button for a photo: gate first, then the system share sheet.
struct GatedShareButton: View {
    let image: UIImage
    @State private var gate = false
    @State private var sharing = false

    var body: some View {
        Button { gate = true } label: { PhotoActionLabel(title: "Share", symbol: "square.and.arrow.up", prominent: false) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photo-share")
            .parentGate(isPresented: $gate) { sharing = true }
            .sheet(isPresented: $sharing) { ShareSheet(items: [image]).presentationDetents([.medium, .large]) }
    }
}

/// A text button that asks a grown-up, then runs the action (Open Settings and friends).
struct GatedButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var gate = false

    var body: some View {
        Button { gate = true } label: { label() }
            .parentGate(isPresented: $gate, onPass: action)
    }
}
