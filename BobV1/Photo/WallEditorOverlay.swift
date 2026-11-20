//
//  WallEditorOverlay.swift
//  The wall picture editor's screen (GameCare+WallEdit.swift has the logic): a transparent layer over the live room takes the touches (a drag moves the picture, a pinch or the corner handle
//  sizes it, or, in Photo mode, a drag slides the photo inside the frame and a pinch zooms it), and a calm panel offers the shape, the frames (owned ones select, the others show their
//  price and lead to the Shop), Change photo, Take down, Cancel and Done. Same buttons and capsules as the album and the Bag.
//

import SwiftUI

struct WallEditorOverlay: View {
    let care: GameCare
    let session: WallEditSession
    @Environment(\.verticalSizeClass) private var vsc
    @State private var drag: DragKind?
    @State private var grab = SIMD2<Float>(0, 0)
    @State private var lastTranslation = CGSize.zero
    @State private var pinchBase: Float?
    @State private var confirmTakeDown = false
    private enum DragKind { case move, resize, pan }
    private var compact: Bool { vsc == .compact }

    /// The picture as it hangs now (the spot clamp applied).
    private var shown: WallPicture { WallZone.clamp(session.draft, in: care.roomID) ?? session.draft }

    // MARK: touches

    /// The framed picture's outline on the screen of `size`.
    private func outline(_ size: CGSize) -> CGRect? {
        let p = shown
        guard let a = GameCamera.screenPoint(wall: SIMD2(p.x - p.outerWidth / 2, p.y + p.outerHeight / 2), size: size),
              let b = GameCamera.screenPoint(wall: SIMD2(p.x + p.outerWidth / 2, p.y - p.outerHeight / 2), size: size) else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func touch(_ v: DragGesture.Value, size: CGSize) {
        if drag == nil {
            lastTranslation = .zero
            if session.photoMode { drag = .pan }
            else if let r = outline(size), hypot(v.startLocation.x - r.maxX, v.startLocation.y - r.maxY) < 40 { drag = .resize }
            else {
                drag = .move
                let p = shown
                grab = GameCamera.wallPoint(screen: v.startLocation, size: size).map { $0 - SIMD2(p.x, p.y) } ?? .zero
            }
        }
        switch drag {
        case .move:
            if let w = GameCamera.wallPoint(screen: v.location, size: size) { care.wallEditMove(to: w - grab) }
        case .resize:
            if let w = GameCamera.wallPoint(screen: v.location, size: size) {
                let p = shown
                care.wallEditSetWidth(abs(w.x - p.x) * 2 / (1 + 2 * p.frame.edge / p.shape.aspect))
            }
        case .pan:
            if let r = outline(size), r.width > 1, r.height > 1 {
                let dx = v.translation.width - lastTranslation.width, dy = v.translation.height - lastTranslation.height
                care.wallEditPan(shareX: Float(dx / r.width), shareY: Float(dy / r.height))
                lastTranslation = v.translation
            }
        case nil: break
        }
    }

    private func endTouch() {
        if drag == .move || drag == .resize, let c = WallZone.clamp(session.draft, in: care.roomID) { session.draft.x = c.x; session.draft.y = c.y; session.draft.width = c.width }
        drag = nil
    }

    private func pinch(_ m: CGFloat) {
        if session.photoMode {
            if pinchBase == nil { pinchBase = session.draft.crop.zoom }
            care.wallEditSetZoom((pinchBase ?? 1) * Float(m))
        } else {
            if pinchBase == nil { pinchBase = shown.width }
            care.wallEditSetWidth((pinchBase ?? 1) * Float(m))
        }
    }

    // MARK: body

    var body: some View {
        GeometryReader { outer in
        let inset = outer.safeAreaInsets
        GeometryReader { g in
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { touch($0, size: g.size) }.onEnded { _ in endTouch() })
                    .simultaneousGesture(MagnifyGesture().onChanged { pinch($0.magnification) }.onEnded { _ in
                        if !session.photoMode, let c = WallZone.clamp(session.draft, in: care.roomID) { session.draft.x = c.x; session.draft.y = c.y; session.draft.width = c.width }
                        pinchBase = nil
                    })
                    .accessibilityIdentifier("wall-edit-surface")
                    .accessibilityLabel("Room wall").accessibilityHint("Drag the picture to move it, pinch to make it bigger or smaller")
                outlineView(size: g.size)
                VStack(spacing: 8) {
                    if !compact { header }          // (a phone on its side: the hint is the panel's first line, so the band above the windows stays clear)
                    Spacer(minLength: 0)
                    panel(width: g.size.width - inset.leading - inset.trailing - 32)
                }
                .padding(.leading, inset.leading + 16).padding(.trailing, inset.trailing + 16)
                .padding(.top, max(inset.top, 0) + 8).padding(.bottom, max(inset.bottom, 0) + 10)
            }
        }
        .ignoresSafeArea()
        }
        .transition(.opacity)
        .alert("Take the picture down?", isPresented: $confirmTakeDown) {
            Button("Take down", role: .destructive) { care.takeDownWallPicture() }
            Button("Keep", role: .cancel) {}
        }
        .accessibilityIdentifier("wall-edit-overlay")
    }

    /// A dashed outline round the picture and, in picture mode, the corner handle (the resize grip).
    private func outlineView(size: CGSize) -> some View {
        // redrawn every frame while the editor is up: the camera rises (and later falls) under it, so the picture moves on the screen without its own state changing
        TimelineView(.animation) { _ in outlineCanvas(size: size) }
    }

    private func outlineCanvas(size: CGSize) -> some View {
        _ = session.draft; _ = session.photoMode          // (read here, in the body, so the outline follows the picture)
        return Canvas { ctx, _ in
            guard let r = outline(size) else { return }
            let box = Path(roundedRect: r.insetBy(dx: -4, dy: -4), cornerRadius: 8)
            ctx.stroke(box, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 5, dash: session.photoMode ? [] : [10, 7]))
            ctx.stroke(box, with: .color(SK.honey), style: StrokeStyle(lineWidth: 2.5, dash: session.photoMode ? [] : [10, 7]))
            if !session.photoMode {
                let h = CGRect(x: r.maxX - 15, y: r.maxY - 15, width: 30, height: 30)
                ctx.fill(Path(ellipseIn: h), with: .color(.white))
                ctx.stroke(Path(ellipseIn: h), with: .color(SK.honey), lineWidth: 4)
                var arrow = Path()
                arrow.move(to: CGPoint(x: h.minX + 9, y: h.minY + 9)); arrow.addLine(to: CGPoint(x: h.maxX - 9, y: h.maxY - 9))
                ctx.stroke(arrow, with: .color(SK.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Hang your picture").font(SK.font(18, .black)).foregroundStyle(SK.ink)
            Text(session.photoMode ? "Drag to slide the photo, pinch to zoom it" : "Drag to move it, pinch or drag the corner to size it").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.cream.opacity(0.94)).shadow(color: SK.shadow.opacity(0.2), radius: 6, y: 2))
        .frame(maxWidth: 520)
        .accessibilityElement(children: .combine)
    }

    // MARK: the panel

    private func panel(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            if compact {
                Text(session.photoMode ? "Drag to slide the photo, pinch to zoom it" : "Drag the picture to move it, pinch or drag the corner to size it").font(SK.font(12, .bold)).foregroundStyle(SK.muted)
                HStack(spacing: 8) { modeToggle; shapeButtons; Spacer(minLength: 0); frameStrip }
                HStack(spacing: 8) { photoActions; Spacer(minLength: 0); finishActions }
            } else {
                HStack(spacing: 8) { modeToggle; Spacer(minLength: 0); shapeButtons }
                frameStrip
                HStack(spacing: 8) { photoActions; Spacer(minLength: 0) }
                HStack(spacing: 8) { Spacer(minLength: 0); finishActions }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(SK.cream.opacity(0.96)).shadow(color: SK.shadow.opacity(0.22), radius: 8, y: 2))
        .frame(maxWidth: 640)
    }

    private var modeToggle: some View {
        HStack(spacing: 6) {
            chip("Move", symbol: "arrow.up.left.and.arrow.down.right", selected: !session.photoMode) { session.photoMode = false }
                .accessibilityIdentifier("wall-edit-mode-size")
            chip("Photo", symbol: "photo", selected: session.photoMode, enabled: session.canCrop) { session.photoMode = true }
                .accessibilityIdentifier("wall-edit-mode-photo")
        }
    }

    private var shapeButtons: some View {
        HStack(spacing: 6) {
            ForEach(WallShape.allCases, id: \.self) { s in
                let sym = s == .portrait ? "rectangle.portrait" : s == .square ? "square" : "rectangle"
                Button { AudioHub.shared.uiTap(); care.wallEditSetShape(s) } label: {
                    Image(systemName: sym).font(.system(size: 18, weight: .heavy)).foregroundStyle(SK.ink)
                        .frame(width: 48, height: 48).background(Circle().fill(session.draft.shape == s ? SK.honey : Color.white.opacity(0.92)))
                }
                .buttonStyle(.plain).disabled(!session.canReshape).opacity(session.canReshape ? 1 : 0.4).accessibilityLabel(s == .portrait ? "Upright" : s == .square ? "Square" : "Wide")
                .accessibilityAddTraits(session.draft.shape == s ? .isSelected : [])
                .accessibilityIdentifier("wall-edit-shape-\(s.rawValue)")
            }
        }
    }

    private var frameStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WallFrame.allCases, id: \.self) { f in
                    let item = StoreCatalog.item("frame-\(f.rawValue)")
                    let owned = care.store.ownsFrame(f)
                    Button {
                        AudioHub.shared.uiTap()
                        if owned { care.wallEditSetFrame(f) } else { care.wallShopRequest = true }          // an unowned frame leads to the Shop
                    } label: {
                        HStack(spacing: 6) {
                            if let item { ItemArt(item: item, size: 40) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.title).font(SK.font(13, .heavy)).foregroundStyle(SK.ink).lineLimit(1)
                                if owned { Text(session.draft.frame == f ? "Hanging" : "Owned").font(SK.font(11, .bold)).foregroundStyle(SK.muted) }
                                else if let item { HStack(spacing: 3) { JellyCoinIcon(size: 13); Text("\(item.price)").font(SK.font(11, .black)).foregroundStyle(SK.ink) } }
                            }
                        }
                        .padding(.horizontal, 8).frame(minHeight: 52)
                        .background(Capsule().fill(session.draft.frame == f ? SK.honey : Color.white.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(owned ? "\(f.title) frame" : "\(f.title) frame, \(item?.price ?? 0) JellyCoins, opens the Shop")
                    .accessibilityAddTraits(session.draft.frame == f ? .isSelected : [])
                    .accessibilityIdentifier("wall-edit-frame-\(f.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var photoActions: some View {
        HStack(spacing: 8) {
            PhotoActionButton(title: "Change photo", symbol: "photo.on.rectangle", prominent: false) { care.wallAlbumOpen = true }
                .accessibilityIdentifier("wall-edit-change-photo")
            if session.original != nil {
                PhotoActionButton(title: "Take down", symbol: "trash", prominent: false) { confirmTakeDown = true }
                    .accessibilityIdentifier("wall-edit-take-down")
            }
        }
    }

    private var finishActions: some View {
        HStack(spacing: 8) {
            PhotoActionButton(title: "Cancel", symbol: "xmark", prominent: false) { care.finishWallEdit(save: false) }
                .accessibilityIdentifier("wall-edit-cancel")
            PhotoActionButton(title: "Done", symbol: "checkmark", prominent: true) { care.finishWallEdit(save: true) }
                .accessibilityIdentifier("wall-edit-done")
        }
    }

    private func chip(_ title: String, symbol: String, selected: Bool, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13, weight: .heavy))
                Text(title).font(SK.font(14, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(SK.ink.opacity(enabled ? 1 : 0.4)).padding(.horizontal, 12).frame(minHeight: 44)
            .background(Capsule().fill(selected ? SK.honey : Color.white.opacity(0.92)))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Capture aids for the wall picture's flow (dev arguments only, never in an App Store archive): `-WallSeedPhotos <dir>` copies those pictures into the album, `-GrantFrames wood,gold|all`
/// owns frames without paying, `-WallFlow album` opens the album as the Bag does, `-AlbumViewFirst 1` opens the first photo's viewer, `-WallEdit 1 [-WallEditPhoto <path>] [-WallEditMode photo]`
/// opens the editor, `-StoreScroll frames` opens the Shop scrolled to the frames.
enum WallDemo {
    @MainActor static func prepare(store: StoreBook, defaults d: UserDefaults = .standard) {
        guard DevArgs.enabled else { return }
        if let g = d.string(forKey: "GrantFrames") {
            for f in WallFrame.allCases where g == "all" || g.split(separator: ",").contains(Substring(f.rawValue)) { store.grant("frame-\(f.rawValue)") }
        }
        if let dir = d.string(forKey: "WallSeedPhotos") {
            let fm = FileManager.default
            try? fm.createDirectory(at: PhotoAlbum.folder, withIntermediateDirectories: true)
            for u in ((try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where ["jpg", "jpeg"].contains(u.pathExtension.lowercased()) {
                let to = PhotoAlbum.folder.appending(path: u.lastPathComponent)
                if !fm.fileExists(atPath: to.path) { try? fm.copyItem(at: u, to: to) }
            }
            PhotoAlbum.shared.reload()
        }
        if d.string(forKey: "StoreScroll") == "frames" { ShopTab.scrollToFrames = true }
    }

    @MainActor static func run(model: MelonModel, defaults d: UserDefaults = .standard) async {
        guard DevArgs.enabled else { return }
        let care = model.care
        switch d.string(forKey: "WallFlow") {
        case "album": try? await Task.sleep(nanoseconds: 2_500_000_000); care.wallAlbumOpen = true          // as the Bag's "Hang a picture" does
        case "shoprequest": try? await Task.sleep(nanoseconds: 2_500_000_000); care.wallShopRequest = true          // as the album's "Get a frame" does
        case "hangfirst": try? await Task.sleep(nanoseconds: 2_500_000_000); if let u = PhotoAlbum.shared.items.first { care.hangFromAlbum(u) }          // as the album's "Hang on wall" does
        default: break
        }
        if d.integer(forKey: "WallEdit") != 0 {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            let photo = d.string(forKey: "WallEditPhoto").map { URL(fileURLWithPath: $0) }
            if let why = care.beginWallEdit(photo: photo) { NSLog("[wall] editor refused: %@", why) }
            if d.string(forKey: "WallEditMode") == "photo" { care.wallEdit?.photoMode = true }
            if let z = d.object(forKey: "WallEditZoom") as? Double { care.wallEditSetZoom(Float(z)) }
            if let c = d.string(forKey: "WallEditPan")?.split(separator: ",").compactMap({ Float($0) }), c.count == 2 { care.wallEditPan(shareX: c[0], shareY: c[1]) }
        }
    }
}
