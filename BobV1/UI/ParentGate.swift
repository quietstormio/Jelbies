//
//  ParentGate.swift
//  "Ask a grown-up": the hold-to-pass gate in front of everything that leaves the app (Settings, Shortcuts, the share sheet).
//

import SwiftUI
import UIKit

/// THE switch for the grown-up hold gate (owner 2026-11-19: "remove the parent gate if we don't need it"; the game is not in the App Store Kids category, so Apple does not
/// require it). false = every gated exit (Share, Write to us, Settings, Shortcuts) runs its action at once and the gate screen is never shown. To bring it back (for
/// example for the Kids category) set it to true: nothing else changes, every call site and the gate screen are still here, and the "grown-up" wording on the buttons,
/// the support hint and the privacy page reappears with it. A var only so a test can flip it (and must restore it).
enum ParentGate {
    nonisolated(unsafe) static var required = false

    /// When the gate is off and a gated exit asks to open it, the action runs here instead. True = it ran (the caller closes the request).
    @discardableResult
    static func intercept(isPresented: Bool, required: Bool = ParentGate.required, onPass: () -> Void) -> Bool {
        guard isPresented, !required else { return false }
        onPass()
        return true
    }
    /// Hint text for a gated button: the grown-up wording only while the gate is on.
    static func hint(_ gated: String, ungated: String) -> String { required ? gated : ungated }
}

/// The modal itself: opaque cream card, one brown button the adult holds for 2 seconds, and Cancel.
/// VoiceOver: the button's activate action asks one more deliberate question before it passes.
struct ParentGateView: View {
    var pass: () -> Void
    var cancel: () -> Void
    @State private var confirmVO = false

    var body: some View {
        ZStack {
            FocusStyle.cream.ignoresSafeArea()
            if HUDLayout.isPad {
                GeometryReader { geo in gateScroll(minHeight: geo.size.height) }          // iPad: centred on the screen, not pinned to the top
            } else {
                gateScroll(minHeight: nil)
            }
        }
        .confirmationDialog("Are you a grown-up?", isPresented: $confirmVO, titleVisibility: .visible) {
            Button("Yes, I am a grown-up") { pass() }
            Button("Cancel", role: .cancel) { }
        }
        .accessibilityIdentifier("parent-gate")
    }

    private func gateScroll(minHeight: CGFloat?) -> some View {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: HUDLayout.isPad ? 44 : 34, weight: .semibold)).foregroundStyle(FocusStyle.brown)
                        .accessibilityHidden(true)
                    Text("Ask a grown-up")
                        .font(SK.font(HUDLayout.isPad ? 32 : 24, .heavy)).foregroundStyle(FocusStyle.brown)
                        .accessibilityAddTraits(.isHeader)
                    Text("This goes outside Jelmiko. A grown-up can press and hold the button for 2 seconds.")
                        .font(SK.font(HUDLayout.isPad ? 20 : 16, .medium)).foregroundStyle(FocusStyle.brown)
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
                .padding(24).frame(maxWidth: HUDLayout.isPad ? 560 : 440).frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
            }
            .scrollBounceBehavior(.basedOnSize)
    }
}

private struct ParentGateModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onPass: () -> Void
    @State private var passed = false

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(get: { isPresented && ParentGate.required }, set: { isPresented = $0 }), onDismiss: {
            // Run the action only once the gate is fully gone, so Settings / the share sheet do not fight the cover.
            if passed { passed = false; onPass() }
        }) {
            ParentGateView(pass: { passed = true; isPresented = false }, cancel: { passed = false; isPresented = false })
        }
        .onChange(of: isPresented) { _, now in
            if ParentGate.intercept(isPresented: now, onPass: onPass) { isPresented = false }          // (gate off: the action runs at once, no gate screen)
        }
    }
}

extension View {
    /// Shows "Ask a grown-up" when isPresented turns true; onPass runs only after the adult holds the button. With `ParentGate.required` false it just runs onPass.
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

/// UIKit share sheet, shown only after the gate has passed when the gate is on (ShareLink cannot be gated).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    static func make(items: [Any]) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = [.saveToCameraRoll]          // (no saving to the phone's photo library from the share sheet either)
        return vc
    }
    func makeUIViewController(context: Context) -> UIActivityViewController { Self.make(items: items) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) { }
}

/// A Share button for a photo: the gate first (when `ParentGate.required`), then the system share sheet.
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

/// A text button that asks a grown-up (when `ParentGate.required`), then runs the action (Open Settings and friends).
struct GatedButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var gate = false

    var body: some View {
        Button { gate = true } label: { label() }
            .parentGate(isPresented: $gate, onPass: action)
    }
}
