//
//  SettingsMenu.swift
//  The gear's popover: Accessibility (the in-app accessibility sheet) and Studio (the developer studio the gear used to open).
//

import SwiftUI

struct SettingsMenu: View {
    var openAccessibility: () -> Void
    var openStudio: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings").jFont(17, .bold, relativeTo: .headline).foregroundStyle(FocusStyle.brown)
                .accessibilityAddTraits(.isHeader).padding(.leading, 6)
            row("Accessibility", "accessibility", id: "settings-accessibility", action: openAccessibility)
            row("Studio", "slider.horizontal.3", id: "settings-studio", action: openStudio)
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.28), radius: 12, y: 5))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-menu")
        .accessibilityAction(.escape) { close() }
    }

    private func row(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            AudioHub.shared.uiTap(); action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 28)
                Text(title).jFont(16, .semibold)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).opacity(0.5).accessibilityHidden(true)
            }
            .foregroundStyle(FocusStyle.brown)
            .padding(.horizontal, 12).frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.75)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
    }
}
