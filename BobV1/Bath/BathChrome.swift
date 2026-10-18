//
//  BathChrome.swift
//  The clean-up's SwiftUI chrome: the tool bar (Jelly Soap, Rinse, Shine; the current one lit), a thin progress bar, the cancel
//  button, the "Done" card and the white fade overlay.
//

import SwiftUI

struct BathChrome: View {
    let care: GameCare

    private static let tools: [(BathPhase, String, String)] = [
        (.soap, "Jelly Soap", "bubbles.and.sparkles.fill"),
        (.rinse, "Rinse", "drop.fill"), (.shine, "Shine", "sparkles")]
    private var bath: BathFlow { care.bath }

    var body: some View {
        ZStack {
            if bath.showsChrome {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { care.cancelClean() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(CareMenu.brown)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(CareMenu.cream).opacity(0.92))
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bath-cancel")
                        .accessibilityLabel("Stop cleaning")
                    }
                    Spacer()
                    VStack(spacing: 10) {
                        if let p = bath.prompt {
                            Text(p)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(CareMenu.brown)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(CareMenu.cream).shadow(color: .black.opacity(0.15), radius: 5, y: 2))
                                .transition(.scale.combined(with: .opacity))
                        }
                        if bath.phase == .finish {
                            Button { care.finishClean() } label: {
                                Text("Done")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(CareMenu.brown)
                                    .padding(.horizontal, 28).padding(.vertical, 10)
                                    .background(Capsule().fill(CareMenu.cream).shadow(color: .black.opacity(0.18), radius: 6, y: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("bath-done")
                        } else {
                            toolBar
                            ProgressBar(value: bath.progress)
                                .frame(height: 6)
                                .padding(.horizontal, 24)
                                .accessibilityIdentifier("bath-progress")
                        }
                    }
                    .padding(.bottom, 14)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.2), value: bath.phase)
                .animation(.easeInOut(duration: 0.2), value: bath.prompt)
                .transition(.opacity)
            }
            Color.white.opacity(Double(bath.wipe))          // the fade to white; the world swaps only while this is fully opaque
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var toolBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.tools.enumerated()), id: \.offset) { _, t in
                let on = bath.phase == t.0
                VStack(spacing: 3) {
                    Image(systemName: UIImage(systemName: t.2) != nil ? t.2 : "circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(on ? Color.white : CareMenu.cream).shadow(color: .black.opacity(on ? 0.25 : 0.1), radius: on ? 7 : 3, y: 2))
                        .overlay(Circle().strokeBorder(on ? Color(red: 0.36, green: 0.62, blue: 0.95) : Color.white.opacity(0.5), lineWidth: on ? 2.5 : 1))
                        .scaleEffect(on ? 1.1 : 1)
                    Text(t.1)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(CareMenu.cream))
                }
                .foregroundStyle(CareMenu.brown)
                .opacity(on ? 1 : 0.7)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bath-toolbar")
    }
}

private struct ProgressBar: View {
    let value: Float
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.55))
                Capsule().fill(Color(red: 0.36, green: 0.62, blue: 0.95)).frame(width: max(6, g.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .animation(.easeOut(duration: 0.15), value: value)
    }
}
