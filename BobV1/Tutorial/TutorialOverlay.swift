//
//  TutorialOverlay.swift
//  The tutorial's own top window (level .normal + 6: above the tip cards at + 5, the message bar at + 4, every sheet) and what is drawn in it: the dim with the ring, and the one CoachCard.
//  Touches: the window answers only where the step wants them blocked (`TutorialPolicy`). On a spotlight step everything outside the ring's hole is blocked and the hole passes through to the real control;
//  on a card-only step only the card takes touches; an idle tutorial (no step) answers nothing at all. The window is never the key window and is hidden whenever no step is up.
//

import SwiftUI
import UIKit

// MARK: touches (pure, tested)

enum TutorialPolicy {
    /// True when the tutorial window must take a touch at `p` (the card and the chips inside it then get it); false = it falls through to the game.
    static func swallows(_ step: TutorialStep?, spot: CoachSpot?, cardFrame: CGRect, at p: CGPoint) -> Bool {
        guard let step else { return false }
        switch step.kind {
        case .arrival, .intro: return true
        case .spot:
            guard let spot else { return cardFrame.insetBy(dx: -4, dy: -4).contains(p) }          // the control is not there: only the card
            if step.wait == .button { return true }
            return !spot.contains(p)
        case .card:
            if step.wait == .button { return true }
            return cardFrame.insetBy(dx: -4, dy: -4).contains(p)
        }
    }
}

// MARK: placement (pure, tested)

enum TutorialPlacement {
    struct Result: Equatable {
        var frame: CGRect
        var maxHeight: CGFloat
        var pointer: (up: Bool, x: CGFloat)?
        static func == (a: Result, b: Result) -> Bool { a.frame == b.frame && a.maxHeight == b.maxHeight && a.pointer?.up == b.pointer?.up && a.pointer?.x == b.pointer?.x }
    }

    /// Where the card stands. `natural` is the card's MEASURED height at `width`; it is never taller than the room (the card scrolls inside then).
    static func place(size: CGSize, safe: UIEdgeInsets, spot: CoachSpot?, place: TutorialStep.Place, natural: CGFloat, wide: Bool, avoid: CGPoint?, pinned: Bool = false, beside: Bool = false) -> Result {
        let landscape = size.width > size.height * 1.2
        let left = safe.left + Coach.inset, right = size.width - safe.right - Coach.inset
        let topLim = safe.top + 58, botLim = size.height - max(safe.bottom, 8) - 12
        let fullRoom = max(botLim - topLim, 120)
        var w = wide ? min(Coach.wideWidth, right - left) : min(Coach.width(size), right - left)
        func clampX(_ x: CGFloat, _ w: CGFloat) -> CGFloat { min(max(x, left), max(right - w, left)) }
        func hits(_ r: CGRect) -> Bool { avoid.map { r.insetBy(dx: -40, dy: -50).contains($0) } ?? false }

        if let spot, !pinned {
            let hole = spot.hole
            let roomAbove = hole.minY - Coach.cardGap - topLim, roomBelow = botLim - hole.maxY - Coach.cardGap
            let preferAbove = hole.midY > size.height / 2
            if beside {          // a control in the rail with empty floor beside it: the card stands beside it
                let leftSide0 = hole.midX < size.width / 2
                let room0 = leftSide0 ? right - hole.maxX - Coach.inset : hole.minX - Coach.inset - left
                if room0 >= 240 {
                    let bw = min(w, room0), h = min(natural, fullRoom)
                    let low = size.height - max(safe.bottom, 8) - 100          // (the heart and the name chip live below this line)
                    let y = min(max(hole.midY - h / 2, topLim), max(low - h, topLim))
                    let x = leftSide0 ? hole.maxX + Coach.inset : hole.minX - Coach.inset - bw
                    return Result(frame: CGRect(x: x, y: y, width: bw, height: h), maxHeight: h, pointer: nil)
                }
            }
            // a band above or below the control that is tall enough and has a spot along it that is clear of the Jelmiko (he wanders: never under the card)
            var firstFit: Result?
            for sd in (preferAbove ? [0, 1] : [1, 0]) where natural <= (sd == 0 ? roomAbove : roomBelow) {
                let h = natural
                let y = sd == 0 ? hole.minY - Coach.cardGap - h : hole.maxY + Coach.cardGap
                for x in [clampX(hole.midX - w / 2, w), clampX(left, w), clampX(right - w, w)] {
                    let r = Result(frame: CGRect(x: x, y: y, width: w, height: h), maxHeight: h, pointer: (up: sd == 1, x: hole.midX - x))
                    if firstFit == nil { firstFit = r }
                    if !hits(r.frame) { return r }
                }
            }
            let sideRoom0 = hole.midX < size.width / 2 ? right - hole.maxX - Coach.inset : hole.minX - Coach.inset - left
            if let ff = firstFit, !(sideRoom0 >= 220) || avoid == nil { return ff }
            // no clear band (or the Jelmiko is in it): beside the control when there is room (a short landscape screen, a control at an edge), else the roomier band, scrolling
            let leftSide = hole.midX < size.width / 2
            let sideRoom = leftSide ? right - hole.maxX - Coach.inset : hole.minX - Coach.inset - left
            if sideRoom >= 220 {
                w = min(w, sideRoom)
                let h = min(natural, fullRoom)
                let y = min(max(hole.midY - h / 2, topLim), botLim - h)
                let x = leftSide ? hole.maxX + Coach.inset : hole.minX - Coach.inset - w
                return Result(frame: CGRect(x: x, y: y, width: w, height: h), maxHeight: h, pointer: nil)
            }
            let above = roomAbove >= roomBelow
            let room = max(above ? roomAbove : roomBelow, 120)
            let h = min(natural, room)
            let y = above ? hole.minY - Coach.cardGap - h : hole.maxY + Coach.cardGap
            let x = clampX(hole.midX - w / 2, w)
            return Result(frame: CGRect(x: x, y: y, width: w, height: h), maxHeight: room, pointer: (up: !above, x: hole.midX - x))
        }
        // no ring: the card stands by itself
        let h = min(natural, fullRoom)
        switch place {
        case .top:
            if landscape {
                let onRight = (avoid?.x ?? 0) < size.width / 2
                let x = onRight ? right - w - 80 : left + 90
                return Result(frame: CGRect(x: clampX(x, w), y: topLim + 4, width: w, height: h), maxHeight: fullRoom, pointer: nil)
            }
            return Result(frame: CGRect(x: clampX((size.width - w) / 2, w), y: topLim + 4, width: w, height: h), maxHeight: fullRoom, pointer: nil)
        case .low:
            if landscape { return Result(frame: CGRect(x: right - w - 8, y: topLim + (fullRoom - h) / 2, width: w, height: h), maxHeight: fullRoom, pointer: nil) }
            return Result(frame: CGRect(x: clampX((size.width - w) / 2, w), y: botLim - h - 12, width: w, height: h), maxHeight: fullRoom, pointer: nil)
        }
    }
}

// MARK: the window

final class TutorialWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let t = Tutorial.shared
        guard !isHidden, let step = t.step else { return nil }
        let spot = TutorialTargets.shared.spot(for: step, size: bounds.size)
        guard TutorialPolicy.swallows(step, spot: spot, cardFrame: t.cardFrame, at: point) else { return nil }
        return super.hitTest(point, with: event) ?? self
    }
}

@MainActor
enum TutorialWindowHost {
    private(set) static var window: TutorialWindow?
    static func setVisible(_ on: Bool) {
        if on { install() }
        window?.isHidden = !on
    }
    static func install() {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = TutorialWindow(windowScene: scene)
        w.windowLevel = .normal + 6
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: TutorialOverlay())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = true
        window = w
    }
}

// MARK: the overlay

struct TutorialOverlay: View {
    private let tutorial = Tutorial.shared
    private let targets = TutorialTargets.shared
    @State private var natural: CGFloat = 170
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    private var motion: Bool { !(reduceMotionEnv || A11ySettings.shared.reduceMotion) }

    var body: some View {
        GeometryReader { geo in
            if let step = tutorial.step {
                // the Jelmiko roams: his ring and the card beside it are re-read ten times a second
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in content(step, geo.size) }
            }
        }
        .ignoresSafeArea()
    }

    private func nameOf() -> String { tutorial.name }

    private func card(_ step: TutorialStep, width: CGFloat, maxHeight: CGFloat?, pointer: (up: Bool, x: CGFloat)?, columns: Int, measuring: Bool = false) -> CoachCard {
        let n = nameOf()
        let intro = step.kind == .intro
        return CoachCard(title: step.head(n), subtitle: intro ? step.line(n) : nil, text: intro ? nil : step.line(n), rows: intro ? Tutorial.introRows : [], columns: columns,
                         button: step.button, buttonID: measuring ? "" : "tutorial-button", onButton: { AudioHub.shared.uiTap(); tutorial.buttonTapped() },
                         dots: tutorial.isHint ? nil : (step.chapter, tutorial.chapterCount), onSkip: { tutorial.skip() },
                         pointer: pointer, width: width, maxHeight: maxHeight, identifier: "tutorial-card", centered: false, measuring: measuring)
    }

    @ViewBuilder private func content(_ step: TutorialStep, _ size: CGSize) -> some View {
        let safe = TipWindowHost.safeInsets
        let landscape = size.width > size.height * 1.2
        let spot = targets.spot(for: step, size: size)
        let wide = step.kind == .intro && landscape
        let baseW = wide ? min(Coach.wideWidth, size.width - safe.left - safe.right - 2 * Coach.inset) : Coach.width(size)
        let avoid = targets.jelmiko?(size).map { CGPoint(x: $0.midX, y: $0.midY) }
        let r = TutorialPlacement.place(size: size, safe: safe, spot: wide ? nil : spot, place: step.place, natural: natural, wide: wide, avoid: step.target == "jelmiko" ? nil : avoid, pinned: step.pinned, beside: step.beside)
        ZStack(alignment: .topLeading) {
            if step.kind == .arrival {
                Color.clear.overlay(alignment: .bottom) { CoachSkipChip { tutorial.skip() }.padding(.bottom, max(safe.bottom, 10) + 14) }
            } else {
                if (step.kind == .spot || step.kind == .intro), let spot { CoachSpotlight(spot: spot, pulse: motion) }
                card(step, width: r.frame.width, maxHeight: r.maxHeight, pointer: r.pointer, columns: wide ? 3 : 1)
                    .id(tutorial.serial)
                    .transition(.opacity)
                    .padding(.leading, r.frame.minX).padding(.top, r.frame.minY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // the card at its natural height, unseen: its height is what the placement above uses
                card(step, width: baseW, maxHeight: nil, pointer: nil, columns: wide ? 3 : 1, measuring: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in if abs(h - natural) > 0.5 { natural = h } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25), value: tutorial.serial)
        .onAppear { tutorial.cardFrame = step.kind == .arrival ? .zero : r.frame }
        .onChange(of: r.frame) { _, f in tutorial.cardFrame = step.kind == .arrival ? .zero : f }
        .onChange(of: tutorial.serial) { _, _ in
            if UIAccessibility.isVoiceOverRunning, let t = step.line(nameOf()) { A11yAnnounce.say(t, priority: .normal, now: Date()) }
        }
    }
}
