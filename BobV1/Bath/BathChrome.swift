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
    @Environment(\.verticalSizeClass) private var vsc
    @State private var pulse = false

    /// "Next": the stage's goal is met; the player moves on when ready (nothing advances by itself).
    private var nextButton: some View {
        Button { care.nextCleanStep() } label: {
            Text("Next")
                .playFont(18, .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 30).frame(minHeight: 44)
                .background(Capsule().fill(FocusStyle.pink).shadow(color: .black.opacity(0.18), radius: 6, y: 2))
        }
        .buttonStyle(.plain)
        .scaleEffect(pulse && !A11ySettings.shared.reduceMotion ? 1.06 : 1)          // (static under Reduce Motion)
        .onAppear { guard !A11ySettings.shared.reduceMotion else { return }; withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } }
        .transition(.scale.combined(with: .opacity))
        .accessibilityIdentifier("bath-next")
    }

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
                                .frame(width: 44, height: 44)
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
                                .playFont(16, .semibold)
                                .foregroundStyle(CareMenu.brown)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .accessibilityIdentifier("bath-prompt")
                                .background(Capsule().fill(CareMenu.cream).shadow(color: .black.opacity(0.15), radius: 5, y: 2))
                                .transition(.scale.combined(with: .opacity))
                        }
                        if bath.phase == .finish {
                            Button { care.finishClean() } label: {
                                Text("Done")
                                    .playFont(18, .bold)
                                    .foregroundStyle(CareMenu.brown)
                                    .padding(.horizontal, 28).padding(.vertical, 10).frame(minHeight: 44)
                                    .background(Capsule().fill(CareMenu.cream).shadow(color: .black.opacity(0.18), radius: 6, y: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("bath-done")
                        } else if vsc == .compact {
                            toolBar
                            helpButton
                            HStack(spacing: 12) {
                                ProgressBar(value: bath.progress).frame(height: 6).accessibilityIdentifier("bath-progress")
                                if bath.stageComplete { nextButton }
                            }
                            .padding(.horizontal, 24)
                        } else {
                            toolBar
                            helpButton
                            ProgressBar(value: bath.progress)
                                .frame(height: 6)
                                .padding(.horizontal, 24)
                                .accessibilityIdentifier("bath-progress")
                            if bath.stageComplete { nextButton }
                        }
                    }
                    .padding(.bottom, 14)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.2), value: bath.phase)
                .animation(.easeInOut(duration: 0.2), value: bath.prompt)
                .animation(.easeInOut(duration: 0.2), value: bath.stageComplete)
                .transition(.opacity)
            }
            Color.white.opacity(Double(bath.wipe))          // the fade to white; the world swaps only while this is fully opaque
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// "Help me scrub": the scripted scrub for this stage, for a player who cannot rub the screen (VoiceOver, Switch Control, a motor difficulty).
    /// It never presses Next for them.
    @ViewBuilder
    private var helpButton: some View {
        if !bath.stageComplete {
            Button { bath.assistScrub.toggle(); AudioHub.shared.uiTap() } label: {
                HStack(spacing: 8) {
                    Image(systemName: bath.assistScrub ? "hand.raised.slash.fill" : "hand.point.up.left.fill")
                    Text(bath.assistScrub ? "Stop helping" : "Help me scrub")
                }
                .playFont(16, .bold)
                .foregroundStyle(CareMenu.brown)
                .padding(.horizontal, 22).frame(minHeight: 48)
                .background(Capsule().fill(bath.assistScrub ? Color.white : CareMenu.cream).shadow(color: .black.opacity(0.15), radius: 5, y: 2))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bath-help")
            .accessibilityLabel(bath.assistScrub ? "Stop helping" : "Help me scrub")
            .accessibilityValue(bath.assistScrub ? "On" : "Off")
            .accessibilityHint("Scrubs for you on this step. You still tap Next.")
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
                        .overlay(alignment: .topTrailing) {
                            if on && bath.stageComplete {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(.white, Color(red: 0.36, green: 0.78, blue: 0.5))
                                    .offset(x: 4, y: -4).transition(.scale)
                            }
                        }
                    Text(t.1)
                        .playFont(11, .semibold, relativeTo: .caption)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(CareMenu.cream))
                }
                .foregroundStyle(CareMenu.brown)
                .opacity(on ? 1 : 0.7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t.1)
                .accessibilityValue(on ? (bath.stageComplete ? "Current step, done" : "Current step") : "")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bath-toolbar")
    }
}

private struct ProgressBar: View {
    let value: Float
    var body: some View { bar.accessibilityElement().accessibilityLabel("Progress").accessibilityValue("\(Int(min(1, max(0, value)) * 100)) percent") }
    private var bar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.55))
                Capsule().fill(Color(red: 0.36, green: 0.62, blue: 0.95)).frame(width: max(6, g.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .animation(.easeOut(duration: 0.15), value: value)
    }
}
