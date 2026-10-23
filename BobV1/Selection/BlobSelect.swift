//
//  BlobSelect.swift
//  Multi-Blob selection.
//
//  - A tap (or double tap) on a Jelbie HIGHLIGHTS him: the outline draws from the top centre of his silhouette down both sides at once, meeting at
//    the bottom (a spark; a light tick at the start, a crisp tap when the halves meet), a soft glow, he hops, the others dim. Every draw
//    confirms itself after the glow; there is no "Play with" chip. The pick then persists (`highlighted`, a floor ring) until a tap on the floor
//    (`clearHighlight`), and the one main HUD control shows his individual menu.
//  - A sleeping Jelbie gets the pick instantly (`pick(_, instant: true)`): no draw, no hop, and he stays asleep.
//  - Another pick stops the first draw on the spot and restarts it on the new Jelbie.
//
//  The model is a pure state machine advanced by `tick(dt:)` (the stage's fixed steps), so it runs headless in tests.
//

import Foundation
import QuartzCore
import CoreGraphics
import Observation
import simd

struct SelectBlob: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Preview Blobs (DEBUG / SELECT_PREVIEW only) are drawn by the overlay at this floor spot; the real Blob (id 0) has none.
    var floor: SIMD2<Float>? = nil
    var scale: Float = 1
    /// Preview body colour (sRGB 0...1). Default = Bob's Baby blue (sRGB of PaletteKey.blue uiFlesh).
    var tint: SIMD3<Float> = SIMD3(0.70, 0.83, 0.945)
}

/// The two preview Blobs (plus the real one) for the highlight: `-BlobSelectPreview 2` or `3` (DEBUG or the SELECT_PREVIEW build flag).
enum SelectPreview {
    static func blobsFromLaunchArguments() -> [SelectBlob]? {
        #if DEBUG || SELECT_PREVIEW
        let n = UserDefaults.standard.integer(forKey: "BlobSelectPreview")
        guard n >= 2 else { return nil }
        var l = [SelectBlob(id: 0, name: "Bob")]
        l.append(SelectBlob(id: 1, name: "Pip", floor: SIMD2(-0.95, 1.55), scale: 0.92, tint: SIMD3(0.99, 0.90, 0.62)))
        if n >= 3 { l.append(SelectBlob(id: 2, name: "Moss", floor: SIMD2(1.05, 0.1), scale: 0.85, tint: SIMD3(0.70, 0.88, 0.80))) }
        if n >= 4 { l.append(SelectBlob(id: 3, name: "Lavender", floor: SIMD2(1.2, 1.6), scale: 0.95, tint: SIMD3(0.80, 0.72, 0.93))) }
        return l
        #else
        return nil
        #endif
    }
}

@MainActor
@Observable
final class BlobSelect {
    enum Phase: Equatable {
        case none
        /// The outline is drawing (`progress` 0...1 over `drawDuration`).
        case drawing(id: Int)
        /// Drawn: soft pulsing glow, the chip is up.
        case pending(id: Int)
    }

    static let drawDuration: Float = 0.6      // was 1.2: the highlight animates 2x faster

    /// The Blobs in the room (index 0 is the real one).
    private(set) var blobs: [SelectBlob] = [SelectBlob(id: 0, name: "Bob")]
    private(set) var phase: Phase = .none
    /// The Blob the action button currently acts on (set by the check).
    private(set) var confirmed: Int?

    /// Seconds since the current highlight started.
    @ObservationIgnored private(set) var clock: Float = 0
    @ObservationIgnored private var tickFired = false
    @ObservationIgnored private var metFired = false
    /// Set when the highlight has just reached "pending": the hop request for that Blob (GameCare takes it).
    @ObservationIgnored private(set) var hopRequest: Int?
    /// Screen silhouettes (points) of every Blob, published by the stage each frame while there are 2+ Blobs; used for hit tests and the outline.
    @ObservationIgnored var outlines: [Int: [CGPoint]] = [:]
    /// The projected floor ring of the settled pick (SelectionRing.swift).
    @ObservationIgnored var ring: SelectRing?
    /// The camera the outlines were made with (preview Blobs are placed with it).
    @ObservationIgnored var viewProj = matrix_identity_float4x4
    @ObservationIgnored var viewSize = CGSize.zero
    /// How many times the draw has been (re)started (tests, overlay restarts).
    @ObservationIgnored private(set) var drawStarts = 0
    /// Haptic hooks: a light tick at the draw start, a crisp tap when the halves meet.
    @ObservationIgnored var onDrawStart: () -> Void = {}
    @ObservationIgnored var onMeet: () -> Void = {}

    nonisolated deinit {}

    // MARK: queries

    var count: Int { blobs.count }
    var isSelecting: Bool { phase != .none }
    var selectedID: Int? {
        switch phase { case .none: return nil; case .drawing(let id), .pending(let id): return id }
    }
    var selectedName: String? { selectedID.flatMap { id in blobs.first { $0.id == id }?.name } }
    /// The action button (care menu) is visible: always with one Blob; with several only after a pick. (Unused by the new HUD; kept for source compatibility.)
    var actionVisible: Bool { count <= 1 || (confirmed != nil && phase == .none) }
    /// The Jelbie whose pick has settled (the persistent highlight); nil while a draw runs or when nothing is picked. While a draw runs use `selectedID`.
    var highlighted: Int? { phase == .none ? confirmed : nil }
    /// The outline is drawn and glowing.
    var glowing: Bool { if case .pending = phase { return true } else { return false } }
    /// 0...1 outline draw progress (eased) of the selected Blob; 1 once pending.
    var drawProgress: Float {
        switch phase {
        case .none: return 0
        case .pending: return 1
        case .drawing:
            let t = min(max(clock / Self.drawDuration, 0), 1)
            return t * t * (3 - 2 * t)
        }
    }
    /// Seconds since the halves met (the glow's phase), 0 while drawing.
    var glowTime: Float { glowing ? max(clock - Self.drawDuration, 0) : 0 }
    /// A Blob is dimmed while another one is selected.
    func isDimmed(_ id: Int) -> Bool { if let s = selectedID { return s != id }; return false }

    // MARK: setup

    func setBlobs(_ list: [SelectBlob]) {
        blobs = list.isEmpty ? [SelectBlob(id: 0, name: "Bob")] : Array(list.prefix(JellyRoster.maxCount))
        phase = .none; confirmed = nil
    }

    /// Drops the persistent highlight (a tap on empty floor) and stops any draw.
    func clearHighlight() { confirmed = nil; if phase != .none { cancel() } }

    /// The Blob under a screen point (the nearest one when silhouettes overlap), or nil for the floor.
    func hit(_ p: CGPoint) -> Int? {
        var best: (id: Int, y: CGFloat)?
        for (id, o) in outlines where Silhouette.contains(o, p) {
            let y = o.map(\.y).max() ?? 0
            if best == nil || y > best!.y { best = (id, y) }
        }
        return best?.id
    }

    /// Called by the stage each frame (2+ Blobs only): the camera, the real Blob's projected points and every outline.
    func publish(viewProj vp: simd_float4x4, size: CGSize, bob: () -> [CGPoint]) {
        viewProj = vp; viewSize = size
        guard count > 1 || isSelecting else { return }
        publishedAt = CACurrentMediaTime()
        outlines[0] = Silhouette.outline(of: bob())
        for b in blobs {
            guard let f = b.floor else { continue }
            outlines[b.id] = Silhouette.outline(of: Silhouette.project(Silhouette.profileWorldPoints(at: f, scale: b.scale), viewProj: vp, size: size))
        }
    }

    /// Called by the stage each frame with real Jellies: every Blob's outline from his own projected skin (`points(id)`), no stand-ins.
    func publish(viewProj vp: simd_float4x4, size: CGSize, points: (Int) -> [CGPoint]) {
        viewProj = vp; viewSize = size
        guard count > 1 || isSelecting else { return }
        publishedAt = CACurrentMediaTime()
        for b in blobs { outlines[b.id] = Silhouette.outline(of: points(b.id)) }
    }

    /// The real Blob's floor spot (GameCare sets it each step).
    @ObservationIgnored var bodyFloor = SIMD3<Float>(0, 0, 1)
    /// When the stage last published the projected outlines (CACurrentMediaTime).
    @ObservationIgnored private(set) var publishedAt: Double = 0
    var hasLiveOutline: Bool { CACurrentMediaTime() - publishedAt < 0.25 }

    // MARK: draw gate (the phone)

    /// On the phone the draw clock only starts once a real, fresh outline of the Blob has been published by the stage and the roster sheet is gone;
    /// nothing is ever drawn over an empty or placeholder path. Off in headless tests (no stage to publish).
    @ObservationIgnored var gateDraw = false
    /// The roster sheet / scrim is up (GameScreen sets it); its dismissal gets `sheetSettle` seconds to fade before the draw starts.
    @ObservationIgnored var sheetOpen = false { didSet { if oldValue && !sheetOpen { sheetClosedAt = CACurrentMediaTime() } } }
    @ObservationIgnored private var sheetClosedAt: Double = -1000
    static let sheetSettle: Double = 0.35
    @ObservationIgnored private var armedAt: Double = 0
    /// A highlight is armed but its draw has not started (waiting for the real outline / the sheet to go).
    @ObservationIgnored private(set) var waiting = false

    /// The Jelly is not ready to be drawn yet (asleep on his back, rolling up): the draw waits for him to stand, then goes on as usual.
    /// GameCare wires it and wakes the sleeper; nil / false = go.
    @ObservationIgnored var holdFor: ((Int) -> Bool)?

    private func gateOpen(_ id: Int) -> Bool {
        if holdFor?(id) == true { return false }
        if !gateDraw { return true }
        guard !sheetOpen, CACurrentMediaTime() - sheetClosedAt >= Self.sheetSettle else { return false }
        return publishedAt > armedAt && (outlines[id]?.count ?? 0) >= 8
    }
    private func arm() {
        armedAt = CACurrentMediaTime()
        waiting = gateDraw || (selectedID.map { holdFor?($0) == true } ?? false)
        if !waiting { fireStartIfNeeded() }
    }
    /// 1 normally; for a roster pick the outline fades out over the last 0.45 s of its hold.
    var outlineAlpha: Float {
        guard rosterPick, case .pending = phase else { return 1 }
        return min(max((Self.drawDuration + Self.autoHold - clock) / 0.45, 0), 1)
    }

    // MARK: events

    /// A double tap on a Blob: the same as a tap pick.
    func doubleTap(_ id: Int) { guard count > 1 else { return }; pick(id) }          // (one Blob: no select step)

    /// Highlights a Jelbie, also with a single Blob. Every draw confirms itself after the glow (`autoHold`).
    /// `quietHop`: no hop when the glow completes (a voice name already has its own hop, and a trick may be running).
    /// `instant`: a sleeper. No draw, no hop, no `selectedID`: the pick settles at once and he stays asleep.
    func pick(_ id: Int, quietHop: Bool = false, instant: Bool = false) {
        guard blobs.contains(where: { $0.id == id }) else { return }
        if instant {
            phase = .none; confirmed = id; rosterPick = false; waiting = false; hopRequest = nil
            return
        }
        if selectedID == id, rosterPick { return }
        quiet = quietHop
        phase = .drawing(id: id)
        confirmed = nil; rosterPick = true
        clock = 0; tickFired = false; metFired = false; hopRequest = nil
        drawStarts += 1
        arm()
    }
    func highlight(_ id: Int, quietHop: Bool = false) { pick(id, quietHop: quietHop) }
    /// Seconds the glow holds after the halves meet before a roster pick confirms itself.
    static let autoHold: Float = 1.2
    /// The current draw is self-confirming (every draw is, now).
    @ObservationIgnored private(set) var rosterPick = false
    @ObservationIgnored private var quiet = false

    /// Settles the pick (called by `tick` after the glow).
    func confirm() {
        guard case .pending(let id) = phase else { return }
        rosterPick = false; waiting = false
        confirmed = id
        phase = .none
    }

    /// Stops a draw in progress.
    func cancel() {
        guard phase != .none else { return }
        rosterPick = false; waiting = false
        phase = .none; clock = 0; hopRequest = nil
    }

    /// GameCare takes the hop request once.
    func takeHopRequest() -> Int? { defer { hopRequest = nil }; return hopRequest }

    /// Advances the highlight by `dt`.
    func tick(dt: Float) {
        guard let id = selectedID else { return }
        if waiting {
            guard gateOpen(id) else { return }
            waiting = false
        }
        clock += dt
        fireStartIfNeeded()
        if !metFired, clock >= Self.drawDuration {
            metFired = true
            onMeet()
            phase = .pending(id: id)
            hopRequest = quiet ? nil : id
        }
        if rosterPick, case .pending = phase, clock >= Self.drawDuration + Self.autoHold {
            rosterPick = false
            confirm()
        }
    }

    private func fireStartIfNeeded() {
        if !tickFired { tickFired = true; onDrawStart() }
    }
}
