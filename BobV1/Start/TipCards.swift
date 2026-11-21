//
//  TipCards.swift
//  The first-time tip card (model: TipBook.swift). The card is drawn in its own pass-through window above everything (the room, a Town screen, a sheet, the Jelly Spring), so one
//  view serves every screen and never needs a host inside them; only the card takes touches. A tap anywhere else dismisses it AND still reaches what it hit (a window-level recognizer
//  that never cancels touches). Look: the first-day tour's card family (cream, radius 24, the tour's shadow, the tour's pink "Got it").
//

import SwiftUI
import UIKit

/// Where a card stands. `top`: over the room / park / bath, under the top row (`below` = points under the safe top). `bottom`: on a full-screen UI, `lift` points above the screen's bottom edge
/// (the pinned bar's top - 12; nil = above the home indicator), `pointer` = a 22 x 12 pointer down at that x.
struct TipPlace: Equatable {
    enum Kind { case top, bottom }
    var kind: Kind
    var offset: CGFloat = 62
    var faces = false
    var pointerX: CGFloat? = nil

    static func of(_ id: String) -> TipPlace {
        switch id {
        case "park": return TipPlace(kind: .top, offset: 114)
        case "camp": return TipPlace(kind: .top, offset: 116)
        case "clean": return TipPlace(kind: .top, offset: 62)
        case "feed", "tricks", "dress", "play", "powerup": return TipPlace(kind: .top, offset: 62, faces: true)
        case "spring": return TipPlace(kind: .bottom, offset: 99)
        case "race", "volley": return TipPlace(kind: .bottom, offset: 110)
        case "show": return TipPlace(kind: .bottom, offset: 108)
        case "trophies": return TipPlace(kind: .bottom, offset: 238, pointerX: 70)
        default: return TipPlace(kind: .bottom, offset: -1)          // town, shop: above the home indicator
        }
    }
}

enum TipPlacement {
    static func width(_ size: CGSize) -> CGFloat {
        size.width > size.height * 1.2 ? min(size.width * 0.34, 340) : min(size.width - 32, 340)
    }

    /// The card's origin x and top y (card height `h` for the keep-off check; nil = every spot covers a face: wait). Pure, so tests can run it.
    static func origin(_ place: TipPlace, size: CGSize, safe: UIEdgeInsets, heads: [CGPoint], h: CGFloat, avoidMap: [CGRect] = []) -> CGPoint? {
        let landscape = size.width > size.height * 1.2
        let w = width(size)
        func covers(_ r: CGRect) -> Bool { heads.contains { r.insetBy(dx: -40, dy: -50).contains($0) } || avoidMap.contains { $0.intersects(r) } }
        switch (place.kind, landscape) {
        case (.top, false):
            let y = GameMessageLayout.top(safeTop: safe.top, portrait: true)          // the message bar's band: top left, under the top-left control (UI/GameMessageCenter.swift)
            var xs: [CGFloat] = [GameMessageLayout.margin, (size.width - w) / 2, size.width - w - 16]
            xs = xs.map { max($0, 8) }
            if !place.faces { return CGPoint(x: xs[0], y: y) }
            return xs.first { !covers(CGRect(x: $0, y: y, width: w, height: h)) }.map { CGPoint(x: $0, y: y) }
        case (.top, true):
            let y = GameMessageLayout.top(safeTop: safe.top, portrait: false)
            let left = GameMessageLayout.left(safeLeft: safe.left), right = size.width - max(safe.right, 40) - 20 - w
            let order: [CGFloat] = [left, right]          // the message bar's corner first; the far side only when a head is under it
            if !place.faces { return CGPoint(x: order[0], y: y) }
            return order.first { !covers(CGRect(x: $0, y: y, width: w, height: h)) }.map { CGPoint(x: $0, y: y) }
        case (.bottom, false):
            let bottom = size.height - (place.offset < 0 ? safe.bottom + 12 : place.offset)
            return CGPoint(x: (size.width - w) / 2, y: bottom - h)
        case (.bottom, true):
            let bottom = size.height - safe.bottom - 12
            let x = size.width - max(safe.right, 40) - 20 - w
            let c = CGPoint(x: x, y: bottom - h)
            if !avoidMap.isEmpty, covers(CGRect(origin: c, size: CGSize(width: w, height: h))) {
                let left = CGPoint(x: max(safe.left, 0) + 20, y: bottom - h)
                if !covers(CGRect(origin: left, size: CGSize(width: w, height: h))) { return left }
            }
            return c
        }
    }
}

/// The card itself.
struct TipCardView: View {
    let card: TipCard
    let width: CGFloat
    var pointerX: CGFloat? = nil
    var onGotIt: () -> Void
    @AccessibilityFocusState private var titleFocus: Bool

    private var disc: some View {
        Image(systemName: card.symbol).font(.system(size: 20, weight: .heavy)).foregroundStyle(SK.ink)
            .frame(width: 40, height: 40).background(Circle().fill(SK.honey)).accessibilityHidden(true)
    }
    private var title: some View {
        Text(card.title).font(SK.font(17, .black)).foregroundStyle(SK.ink)
            .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocus)
    }
    private var gotIt: some View {
        TourCapsuleButton(title: "Got it", hint: "Hides this tip", id: "tip-got-it") { AudioHub.shared.uiTap(); onGotIt() }
            .background(GeometryReader { g in Color.clear.preference(key: TipGotItKey.self, value: g.frame(in: .global)) })
    }

    var body: some View { realBody }

    // A simple two-layout card: the button beside the title when the title fits, else under the body.
    private var realBody: some View {
        let inner = width - 32
        return TipCardLayout(inner: inner, disc: AnyView(disc), title: AnyView(title), body: card.body, gotIt: AnyView(gotIt))
            .padding(16)
            .frame(width: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0xFFFDF8))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(hex: 0x4D331F).opacity(0.10), lineWidth: 1))
                    .shadow(color: Color(hex: 0x5A3A2A).opacity(0.3), radius: 10, y: 4)
            )
            .overlay(alignment: .bottomLeading) {
                if let px = pointerX { Triangle(up: false).fill(Color(hex: 0xFFFDF8)).frame(width: 22, height: 12).offset(x: min(max(px - 11, 22), width - 44), y: 11) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tip-\(card.id)")
            .onAppear { if UIAccessibility.isVoiceOverRunning { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { titleFocus = true } } }
    }
}

private struct TipCardLayout: View {
    let inner: CGFloat
    let disc: AnyView, title: AnyView
    let body_: String
    let gotIt: AnyView
    init(inner: CGFloat, disc: AnyView, title: AnyView, body: String, gotIt: AnyView) {
        self.inner = inner; self.disc = disc; self.title = title; self.body_ = body; self.gotIt = gotIt
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            column(beside: true)
            column(beside: false)
        }
    }
    private func column(beside: Bool) -> some View {
        VStack(alignment: .leading, spacing: beside ? 4 : 12) {
            if beside {
                HStack(spacing: 12) { disc; title.lineLimit(1).fixedSize(horizontal: true, vertical: false); Spacer(minLength: 8); gotIt }.frame(minHeight: 44)
            } else {
                HStack(spacing: 12) { disc; title.lineLimit(2) }.frame(minHeight: 44)
            }
            Text(body_).font(JFont.scaled(14.5, .semibold, design: .default)).foregroundStyle(SK.muted).lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 52)
            if !beside { HStack { Spacer(minLength: 0); gotIt } }
        }
        .frame(width: inner, alignment: .leading)
    }
}

// MARK: the window

/// A clear window that only the card answers to.
final class TipWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let b = TipBook.shared
        guard b.current != nil, (b.passThrough ? b.gotItFrame : b.cardFrame).insetBy(dx: -4, dy: -4).contains(point) else { return nil }          // only the card answers; everything else falls through to the game
        return super.hitTest(point, with: event)
    }
}

/// The overlay's content: the current card, placed for the screen's size.
struct TipOverlay: View {
    private let book = TipBook.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    private var motion: Bool { !(reduceMotionEnv || A11ySettings.shared.reduceMotion) }

    var body: some View {
        GeometryReader { geo in
            let safe = TipWindowHost.safeInsets
            ZStack(alignment: .topLeading) {
                Color.clear
                if let id = book.current, let card = TipBook.card(id) {
                    placed(card, size: geo.size, safe: safe)
                        .transition(motion ? .opacity.combined(with: .offset(y: 8)) : .opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeOut(duration: 0.25), value: book.current)
        }
        .ignoresSafeArea()
    }

    private func placed(_ card: TipCard, size: CGSize, safe: UIEdgeInsets) -> some View {
        let place = TipPlace.of(card.id)
        let w = TipPlacement.width(size)
        let landscape = size.width > size.height * 1.2
        let h: CGFloat = 143
        return TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let heads = TipWindowHost.heads(size: size, wanted: place.faces)
            let origin = TipPlacement.origin(place, size: size, safe: safe, heads: heads, h: h, avoidMap: TipWindowHost.mapButtons(card.id, size: size))
                ?? TipPlacement.origin(TipPlace(kind: place.kind, offset: place.offset), size: size, safe: safe, heads: [], h: h) ?? .zero
            let view = TipCardView(card: card, width: w, pointerX: landscape ? nil : place.pointerX) { TipBook.shared.dismiss() }
                .background(GeometryReader { g in Color.clear.preference(key: TipFrameKey.self, value: g.frame(in: .global)) })
                .onPreferenceChange(TipFrameKey.self) { TipBook.shared.cardFrame = $0 }
                .onPreferenceChange(TipGotItKey.self) { TipBook.shared.gotItFrame = $0 }
                .onAppear { TipBook.shared.passThrough = landscape && card.id == "town" }
            Group {
                if place.kind == .bottom {          // stands on its bar: the bottom edge is fixed, the card grows upward
                    view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, origin.x).padding(.bottom, size.height - (origin.y + h))
                } else {
                    view.padding(.leading, origin.x).padding(.top, origin.y)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .animation(.easeOut(duration: 0.2), value: origin.x)
        }
    }
}

private struct TipGotItKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct TipFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Owns the window and the tap-outside recognizer.
@MainActor
enum TipWindowHost {
    private static var window: TipWindow?
    private static var recognizer: TipTapRecognizerTarget?
    /// The game (set by GameScreen): where the Jelmiko's heads are, for the keep-off check.
    static weak var care: GameCare?
    /// Town-screen buttons a landscape card must not cover (set by the Town screens; empty elsewhere).
    static var landscapeMapButtons: [String: [CGRect]] = [:]

    static var safeInsets: UIEdgeInsets { (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow && !($0 is TipWindow) })?.safeAreaInsets ?? .zero }

    static func mapButtons(_ id: String, size: CGSize) -> [CGRect] { landscapeMapButtons[id] ?? [] }

    /// Every head on the stage in window points (room only: the Park / Camp / bath use other cameras and keep the card at the top, clear of their row).
    static func heads(size: CGSize, wanted: Bool) -> [CGPoint] {
        guard wanted, let care, !care.tripActive, !care.bath.active else { return [] }
        return ([care.headWorld] + care.bubbleHub.heads.filter { $0.key > 0 }.map(\.value)).compactMap { ThoughtBubbleView.project($0, size: size, focus: care.focus.blend) }
    }

    /// Makes the window (once) and installs the tap-outside recognizer on the game's key window.
    static func install() {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = TipWindow(windowScene: scene)
        w.windowLevel = .normal + 5
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: TipOverlay())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
        if let key = scene.windows.first(where: { !($0 is TipWindow) && $0.isKeyWindow }) ?? scene.windows.first(where: { !($0 is TipWindow) }) {
            let t = TipTapRecognizerTarget()
            let r = UITapGestureRecognizer(target: t, action: #selector(TipTapRecognizerTarget.tapped(_:)))
            r.cancelsTouchesInView = false; r.delaysTouchesBegan = false; r.delaysTouchesEnded = false; r.delegate = t
            key.addGestureRecognizer(r)
            recognizer = t
        }
    }
}

final class TipTapRecognizerTarget: NSObject, UIGestureRecognizerDelegate {
    @MainActor @objc func tapped(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, TipBook.shared.current != nil else { return }
        let p = g.location(in: nil)
        let b = TipBook.shared
        if (b.passThrough ? b.gotItFrame : b.cardFrame).insetBy(dx: -2, dy: -2).contains(p) { return }
        TipBook.shared.dismiss()
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

// MARK: screens register here

extension View {
    /// This view is the screen of tip `id`: it is "open" while it is up, and asks for the card `delay` seconds after it appears (when `ready`).
    func tipScreen(_ id: String, ready: Bool = true, delay: Double = 0) -> some View {
        modifier(TipScreenModifier(id: id, ready: ready, delay: delay))
    }
}

/// A zero-size view that stands for "the screen of tip `id` is up": drop it into a screen under the condition that makes it that screen (`if bath.phase == .soap { TipAnchor("clean", delay: 1) }`).
struct TipAnchor: View {
    let id: String
    var ready = true
    var delay: Double = 0
    init(_ id: String, ready: Bool = true, delay: Double = 0) { self.id = id; self.ready = ready; self.delay = delay }
    var body: some View { Color.clear.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true).tipScreen(id, ready: ready, delay: delay) }
}

private struct TipScreenModifier: ViewModifier {
    let id: String
    let ready: Bool
    let delay: Double
    func body(content: Content) -> some View {
        content
            .onAppear { TipBook.shared.screenOpened(id); TipWindowHost.install() }
            .onDisappear { TipBook.shared.screenClosed(id) }
            .task(id: ready) {
                guard ready else { return }
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                if !Task.isCancelled { TipBook.shared.request(id) }
            }
    }
}
