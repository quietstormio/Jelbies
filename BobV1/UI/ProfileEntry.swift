//
//  ProfileEntry.swift
//  profile-entry-r1: two more ways to the Jelmiko Profile (besides the close-up's Profile button and the Jelly Show lobby): the roster panel's cards and the selected
//  Jelmiko's name header. One person icon everywhere (the close-up's own `person.crop.circle`), so the player learns one symbol.
//  Opening is the Town flow's `.condition` screen with no origin of its own: the flow's root is `.condition`, so its back button leaves the flow (TownUI.swift).
//

import SwiftUI

/// The small Profile button: the close-up's person icon (same symbol, weight and brown) on the same frosted circle, 36 pt drawn inside a 44 pt tap target.
struct ProfileEntryButton: View {
    let name: String
    var identifier = "profile-entry"
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            action()
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
                .frame(width: 36, height: 36)
                .hudFrost(in: .circle)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()          // keeps its size at the largest text sizes: the name beside it gives way
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Open \(name)'s profile")
        .accessibilityShowsLargeContentViewer { Label("Open \(name)'s profile", systemImage: "person.crop.circle") }
    }
}

extension GameCare {
    /// Only at home, in the room: not in a close-up, a bath, room arranging, a race / show / volleyball / café / park / camp / spa trip.
    var profileEntryAvailable: Bool {
        !focus.isActive && !tripActive && !park.active && !cafe.active && !bath.active && !arranging && !raceBusy
    }
    /// The Jelmiko a Profile button opens (nil = not at home / no such Jelmiko). Pure: it selects nobody, calls nobody and touches no outfit.
    func profileEntryTarget(_ id: Int) -> Int? { profileEntryAvailable && jelly(id) != nil ? id : nil }
}
