//
//  ThoughtLineView.swift
//  The tiny thought line over a Jelly's head ("zoomies time!"): a small cream cloud with two trailing circles, like the need bubble, but with a
//  short text in ink. Drawn from `ThoughtLines.current` (AI/ThoughtLines.swift decides when; this view only draws), anchored with the same
//  world -> screen projection as the hearts and the bubble. A slow poll when nothing is up, 30 fps while a line is on screen. Never takes touches.
//

import SwiftUI
import simd

struct ThoughtLineView: View {
    let care: GameCare

    var body: some View {
        let lines = care.voice.ai.thoughts
        TimelineView(.periodic(from: .now, by: lines.current == nil ? 0.3 : 1.0 / 30)) { _ in
            GeometryReader { geo in
                if let l = lines.current, let head = headPoint(l.jelly, geo.size) {
                    let age = CACurrentMediaTime() - l.wall
                    cloud(l.text, age: age)
                        .position(x: min(max(head.x + 10, 90), geo.size.width - 90), y: max(head.y - 78, 100))
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("thought-line")
                        .accessibilityLabel("\(care.jelly(l.jelly)?.name ?? "Jelly") thinks: \(l.text)")
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func headPoint(_ id: Int, _ size: CGSize) -> CGPoint? {
        ThoughtBubbleView.project(care.bubbleHead(id) + SIMD3(0, 0.1, 0), size: size, focus: care.focus.blend)
    }

    private func cloud(_ text: String, age: Double) -> some View {
        let pop = CGFloat(max(0, 1 - exp(-7 * age) * cos(14 * age)))
        let leave = max(0, min(1, (ThoughtLines.life - age) / 0.35))
        return Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(DiaryStyle.ink)
            .lineLimit(2).multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: 180)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(FocusStyle.cream.opacity(0.97))
                        .shadow(color: FocusStyle.shadow.opacity(0.22), radius: 6, y: 3)
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // the two trailing circles toward his head
                Circle().fill(FocusStyle.cream.opacity(0.97)).frame(width: 12, height: 12).offset(x: 8, y: 12)
                Circle().fill(FocusStyle.cream.opacity(0.97)).frame(width: 7, height: 7).offset(x: 0, y: 24)
            }
            .scaleEffect(0.75 + 0.25 * pop, anchor: .bottomLeading)
            .opacity(Double(leave))
    }
}
