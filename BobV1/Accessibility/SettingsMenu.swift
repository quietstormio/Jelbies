//
//  SettingsMenu.swift
//  The gear's popover: Accessibility (the in-app accessibility sheet) and Studio (the developer studio the gear used to open).
//

import SwiftUI

struct SettingsMenu: View {
    var openAccessibility: () -> Void
    var openStudio: () -> Void
    /// Back to the main menu (Continue there resumes); nil hides the button.
    var mainMenu: (() -> Void)? = nil
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(CloudTheme.font(20, .bold)).foregroundStyle(CloudTheme.ink)
                .accessibilityAddTraits(.isHeader).padding(.leading, 4)
            row("Accessibility", "accessibility", id: "settings-accessibility", action: openAccessibility)
            row("Studio", "slider.horizontal.3", id: "settings-studio", action: openStudio)
            if let mainMenu { row("Main menu", "house", id: "settings-main-menu", action: mainMenu) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: 260, alignment: .leading)
        .cloudCard(radius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-menu")
        .accessibilityAction(.escape) { close() }
    }

    private func row(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            AudioHub.shared.uiTap(); action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold)).accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(JellyButtonStyle(.secondary, size: 17, minHeight: 44))
        .padding(.horizontal, 2)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
    }
}
