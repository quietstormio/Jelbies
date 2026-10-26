//
//  JelbiesSnippetView.swift
//  The Siri snippet card for "Check on the Jelbies": one row per Jelbie (his face, name, how he is, the items that want care), in the game's
//  cream #F7F0E0 / ink #4D331F and rounded type. Pure SwiftUI over projected `JellyState`s, so the capture tests render it.
//

import SwiftUI

struct JelbiesSnippetView: View {
    let states: [JellyState]
    var sleeping = false

    var body: some View {
        let sorted = states.sorted { $0.id < $1.id }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: sleeping ? "moon.zzz.fill" : "heart.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(JellyPalette.bodyDeep(sleeping ? "purple" : "blue"))
                Text(title(sorted)).font(JellyPalette.font(17, .semibold)).foregroundStyle(JellyPalette.ink)
                Spacer(minLength: 0)
            }
            if sorted.isEmpty {
                Text("Open the game to meet your Jelbies.").font(JellyPalette.font(14, .semibold)).foregroundStyle(JellyPalette.inkSoft)
            } else {
                ForEach(sorted) { s in row(s) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(JellyPalette.cream))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(JellyPalette.ink.opacity(0.08), lineWidth: 1))
    }

    private func title(_ s: [JellyState]) -> String {
        if s.isEmpty { return "Jelbies" }
        let needy = JellyStatus.needyCount(s)
        if needy == 0 { return sleeping ? "Everyone is napping" : (s.count == 1 ? "\(s[0].name) is doing well" : "Everyone is doing well") }
        return needy == 1 ? "Someone needs you" : "\(needy) Jelbies need you"
    }

    private func row(_ s: JellyState) -> some View {
        let mood = JellyFaceMood.of(s, sleeping: sleeping)
        return HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(JellyPalette.body(s.color).opacity(0.28)).frame(width: 46, height: 46)
                    JellyFaceGlyph(color: s.color, mood: mood).frame(width: 36, height: 36)
                }
                if mood == .sleeping { SleepZs(size: 9, color: JellyPalette.bodyDeep(s.color)).offset(x: 8, y: -6) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(JellyPalette.font(16)).foregroundStyle(JellyPalette.ink)
                Text(JellyStatus.sentence(s, sleeping: sleeping).replacingOccurrences(of: "\(s.name) is ", with: "").capitalizingFirst)
                    .font(JellyPalette.font(13, .semibold)).foregroundStyle(JellyPalette.inkSoft).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(JellyCare.allCases, id: \.self) { c in
                    let t = s.tier(c)
                    if t.rawValue >= NeedTier.hungry.rawValue {
                        Image(systemName: c.systemImage).font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WidgetTheme.tint(t))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(WidgetTheme.tint(t).opacity(0.16)))
                    }
                }
                if !s.needsAttention {
                    Image(systemName: sleeping ? "zzz" : "checkmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(JellyPalette.bodyDeep("green"))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(JellyPalette.body("green").opacity(0.3)))
                }
            }
        }
    }
}

private extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
