//
//  AccessibilitySettingsView.swift
//  The in-app Accessibility sheet (gear, Settings, Accessibility). Every row is a native Toggle / Picker bound to `A11ySettings`.
//

import SwiftUI

struct AccessibilitySettingsView: View {
    @Bindable var settings: A11ySettings = .shared
    var close: () -> Void = {}
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    toggle("Reduce motion in the game", $settings.reduceMotionInApp, "a11y-reduce-motion")
                    toggle("Longer hints", $settings.longerHints, "a11y-longer-hints")
                } header: { Text("Seeing") } footer: {
                    Text("Camera moves become fades. Jelly wobble stays. Hints stay until you use them.")
                }
                Section {
                    toggle("Sound captions", $settings.captions, "a11y-captions")
                    toggle("Announce events with VoiceOver", $settings.announcements, "a11y-announce")
                } header: { Text("Hearing") } footer: {
                    Text("Captions show sounds like \"Pip chirps\" under the top bar.")
                }
                if Self.partBLanded { Section {
                    Picker("Race controls", selection: $settings.raceAssist) {
                        ForEach(RaceAssist.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("a11y-race-assist")
                    toggle("Jump for me over hurdles", $settings.autoJump, "a11y-auto-jump")
                    toggle("Relaxed rhythm timing", $settings.relaxedTiming, "a11y-relaxed-timing")
                } header: { Text("Playing") } footer: {
                    Text(Self.raceFootnote(settings.raceAssist) + " Relaxed timing widens the windows in drills, the Show dance and the trick ring.")
                } }
                if Self.partBLanded { Section {
                    toggle("Tap to talk (instead of hold)", $settings.tapToTalk, "a11y-tap-to-talk")
                } header: { Text("Talking") } footer: {
                    Text("Tap the mic once to start and once to stop.")
                } }
                Section {
                    Button("System accessibility settings") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                    }
                    .accessibilityIdentifier("a11y-system-settings")
                } footer: {
                    Text("Jelbies also follows VoiceOver, Voice Control, Switch Control, Larger Text, Bold Text, Increase Contrast, Reduce Transparency and Reduce Motion.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SK.cream)
            .navigationTitle("Accessibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close).accessibilityIdentifier("a11y-done") } }
        }
        .accessibilityIdentifier("a11y-settings")
    }

    /// The Playing and Talking rows drive code that ships in Accessibility part B; flip when B merges so no row does nothing.
    static let partBLanded = true

    static func raceFootnote(_ a: RaceAssist) -> String {
        switch a {
        case .off: return "Off: two foot buttons."
        case .forgiving: return "Forgiving: the same foot twice is OK."
        case .oneButton: return "One button: a single Step button."
        case .auto: return "Auto run: he runs, you cheer."
        }
    }

    private func toggle(_ title: String, _ b: Binding<Bool>, _ id: String) -> some View {
        Toggle(title, isOn: b).accessibilityIdentifier(id)
    }
}
