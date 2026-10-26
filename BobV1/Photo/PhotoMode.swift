//
//  PhotoMode.swift
//  Photo mode: the room's HUD steps aside, a bottom bar offers Pose / Frame / Filter / Shutter / Close, a finger orbits and pans the camera, a
//  pinch zooms (PhotoCam), a tap on a Jelbie makes him look at the camera. Shutter captures the stage view (the Metal frame, no HUD) with
//  drawHierarchy, adds the filter and frame (PhotoLook, via ImageRenderer), keeps it in the album and shows a preview card (Save / Share).
//  Hook for v2: a front-camera selfie bubble would sit in `PhotoModeView.topBar`'s trailing slot; nothing is built for it.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class PhotoMode {
    static let shared = PhotoMode()
    enum Panel { case pose, frame, filter }

    private(set) var active = false
    var panel: Panel?
    var who = 0
    var filter: PhotoFilter = .normal
    var frame: PhotoFrame = .none
    var flash = false
    var shot: (image: UIImage, url: URL)?
    var albumOpen = false
    @ObservationIgnored private weak var care: GameCare?
    nonisolated deinit {}

    func open(care: GameCare) {
        guard !active else { return }
        self.care = care
        who = min(care.targetJelly, max(care.jellies.count - 1, 0))
        PhotoCam.reset(); PhotoCam.active = true
        PhotoCam.onTapJelly = { [weak self] id in self?.lookAtCamera(id) }
        panel = nil; shot = nil
        withAnimation(.easeInOut(duration: 0.25)) { active = true }
    }

    func close() {
        PhotoCam.active = false; PhotoCam.onTapJelly = nil; PhotoCam.reset()          // the game camera is back exactly
        shot = nil; panel = nil
        withAnimation(.easeInOut(duration: 0.25)) { active = false }
    }

    // MARK: poses

    /// A move the Jelbies already have, run on `who` now.
    enum Pose: CaseIterable, Identifiable {
        case face, sit, hop, spin, jacks, flip, joy, giggle
        var id: Self { self }
        var title: String {
            switch self { case .face: return "Face me"; case .sit: return "Sit"; case .hop: return "Hop"; case .spin: return "Spin"
            case .jacks: return "Jumping jacks"; case .flip: return "Flip"; case .joy: return "Jump for joy"; case .giggle: return "Giggle" }
        }
        var symbol: String {
            switch self { case .face: return "eye"; case .sit: return "arrow.down.to.line"; case .hop: return "arrow.up"; case .spin: return "arrow.triangle.2.circlepath"
            case .jacks: return "figure.jumprope"; case .flip: return "arrow.uturn.up"; case .joy: return "party.popper"; case .giggle: return "face.smiling" }
        }
        var idle: IdleKind? {
            switch self { case .sit: return .sit; case .hop: return .bounce; case .spin: return .tail; case .jacks: return .jacks; case .joy: return .joy; case .giggle: return .giggle
            case .face, .flip: return nil }
        }
    }

    func run(_ pose: Pose) {
        guard let care, let brain = care.selectBrain(who) else { return }
        switch pose {
        case .face: lookAtCamera(who)
        case .flip: brain.flipCompact = false; brain.commandedFlipFail = false; brain.commandedFlip = true
        default: brain.commandedIdle = pose.idle
        }
    }

    func lookAtCamera(_ id: Int) {
        guard let care, let brain = care.selectBrain(id), care.raceBook.actors.indices.contains(id) else { return }
        who = id
        brain.startTurn(to: brain.faceCameraYaw(), sim: care.raceBook.actors[id].sim)
    }

    // MARK: shutter

    func shutter() {
        guard shot == nil, let view = MelonStageView.gameStage, view.bounds.width > 1, view.bounds.height > 1 else { return }
        AudioHub.shared.uiConfirm()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = view.window?.screen.scale ?? view.traitCollection.displayScale; fmt.opaque = true
        let size = view.bounds.size
        let raw = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) }
        let look = ZStack {
            Image(uiImage: raw).resizable().frame(width: size.width, height: size.height)
            PhotoLook(filter: filter, frame: frame).frame(width: size.width, height: size.height)
        }.frame(width: size.width, height: size.height)
        let r = ImageRenderer(content: look)
        r.scale = fmt.scale; r.isOpaque = true
        let out = r.uiImage ?? raw
        flash = true
        Task { @MainActor in try? await Task.sleep(nanoseconds: 60_000_000); withAnimation(.easeOut(duration: 0.4)) { flash = false } }
        guard let url = PhotoAlbum.shared.add(out) else { return }
        panel = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shot = (out, url) }
    }
}

/// Hides a piece of the room's HUD while Photo mode is up.
struct PhotoHidden: ViewModifier {
    func body(content: Content) -> some View {
        let on = PhotoMode.shared.active
        content.opacity(on ? 0 : 1).allowsHitTesting(!on).accessibilityHidden(on)
    }
}
extension View { func photoHidden() -> some View { modifier(PhotoHidden()) } }

struct PhotoModeView: View {
    let care: GameCare
    @State private var mode = PhotoMode.shared
    @State private var album = PhotoAlbum.shared
    @State private var hint = true
    @Environment(\.verticalSizeClass) private var vsc
    private var landscape: Bool { vsc == .compact }

    var body: some View {
        ZStack {
            PhotoLook(filter: mode.filter, frame: mode.frame).ignoresSafeArea()
            if mode.shot == nil {
                VStack(spacing: 8) {
                    topBar
                    Spacer()
                    panelRow
                    bar
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .transition(.opacity)
            }
            if let s = mode.shot { PhotoPreview(image: s.image, url: s.url, landscape: landscape) { withAnimation(.easeInOut(duration: 0.25)) { mode.shot = nil } } }
            Color.white.ignoresSafeArea().opacity(mode.flash ? 0.9 : 0).allowsHitTesting(false)
        }
        .onAppear { Task { try? await Task.sleep(nanoseconds: 4_500_000_000); withAnimation { hint = false } } }
        .fullScreenCover(isPresented: $mode.albumOpen) { PhotoAlbumView(close: { mode.albumOpen = false }) }
        .accessibilityElement(children: .contain)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            if hint {
                Text("Drag to look around, pinch to zoom, tap a Jelbie")
                    .font(SK.font(14, .bold)).foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Capsule().fill(SK.cream.opacity(0.92))).transition(.opacity)
            }
            Spacer()
            Button { AudioHub.shared.uiTap(); album.reload(); mode.albumOpen = true } label: {   // (v2: the selfie bubble goes beside this)
                Group {
                    if let u = album.items.first, let t = PhotoThumbs.image(u, maxPixel: 160) { Image(uiImage: t).resizable().scaledToFill() }
                    else { Image(systemName: "photo.on.rectangle").font(.system(size: 15, weight: .semibold)).foregroundStyle(SK.ink) }
                }
                .frame(width: 44, height: 44).background(SK.cream).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white, lineWidth: 2))
                .shadow(color: SK.shadow.opacity(0.3), radius: 3, y: 1).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("Photo album").accessibilityIdentifier("photo-album-button")
        }
    }

    @ViewBuilder private var panelRow: some View {
        switch mode.panel {
        case .pose:
            VStack(spacing: 8) {
                if care.jellies.count > 1 {
                    chips(care.jellies.map { ($0.id, $0.name, nil as String?) }, selected: mode.who) { mode.who = $0 }
                }
                chips(PhotoMode.Pose.allCases.enumerated().map { ($0.offset, $0.element.title, $0.element.symbol as String?) }, selected: -1) { mode.run(PhotoMode.Pose.allCases[$0]) }
            }
        case .frame:
            chips(PhotoFrame.allCases.enumerated().map { ($0.offset, $0.element.title, $0.element.symbol as String?) }, selected: PhotoFrame.allCases.firstIndex(of: mode.frame) ?? 0) { mode.frame = PhotoFrame.allCases[$0] }
        case .filter:
            chips(PhotoFilter.allCases.enumerated().map { ($0.offset, $0.element.title, nil as String?) }, selected: PhotoFilter.allCases.firstIndex(of: mode.filter) ?? 0) { mode.filter = PhotoFilter.allCases[$0] }
        case nil: EmptyView()
        }
    }

    private func chips(_ items: [(Int, String, String?)], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { it in
                    Button { AudioHub.shared.uiTap(); pick(it.0) } label: {
                        HStack(spacing: 5) {
                            if let s = it.2 { Image(systemName: s).font(.system(size: 13, weight: .semibold)) }
                            Text(it.1).font(SK.font(15, .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Capsule().fill(it.0 == selected ? SK.honey : SK.cream.opacity(0.94)).shadow(color: SK.shadow.opacity(0.2), radius: 3, y: 1))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(it.0 == selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 4)
        }
        .frame(maxWidth: 560)
    }

    private var bar: some View {
        HStack(alignment: .center, spacing: landscape ? 28 : 16) {
            barButton("xmark", "Close", id: "photo-close") { mode.close() }
            barButton("figure.wave", "Pose", on: mode.panel == .pose, id: "photo-pose") { toggle(.pose) }
            Button { mode.shutter() } label: {
                Circle().fill(Color.white).frame(width: 66, height: 66)
                    .overlay(Circle().strokeBorder(SK.ink.opacity(0.25), lineWidth: 2))
                    .padding(5).overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                    .shadow(color: SK.shadow.opacity(0.35), radius: 5, y: 2)
            }
            .buttonStyle(.plain).accessibilityLabel("Shutter").accessibilityIdentifier("photo-shutter")
            barButton("rectangle.inset.filled", "Frame", on: mode.panel == .frame, id: "photo-frame") { toggle(.frame) }
            barButton("camera.filters", "Filter", on: mode.panel == .filter, id: "photo-filter") { toggle(.filter) }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, landscape ? 2 : 6)
    }

    private func toggle(_ p: PhotoMode.Panel) { withAnimation(.easeInOut(duration: 0.2)) { mode.panel = mode.panel == p ? nil : p } }

    private func barButton(_ symbol: String, _ label: String, on: Bool = false, id: String, _ a: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); a() } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(SK.ink)
                    .frame(width: 46, height: 46).background(Circle().fill(on ? SK.honey : SK.cream.opacity(0.94)))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                Text(label).font(SK.font(11, .semibold)).foregroundStyle(.white).shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            }
            .frame(minWidth: 52, minHeight: 56)
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

/// After the shutter: the picture, Save to Photos, Share, Done. It is already in the album.
private struct PhotoPreview: View {
    let image: UIImage
    let url: URL
    let landscape: Bool
    var done: () -> Void
    @State private var saved: Bool?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { done() }
            Group {
                if landscape { HStack(spacing: 18) { picture; actions.frame(width: 210) } }
                else { VStack(spacing: 14) { picture; actions } }
            }
            .padding(16)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .accessibilityIdentifier("photo-preview")
    }

    private var picture: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(8).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .rotationEffect(.degrees(landscape ? 0 : -1.5))
            .accessibilityLabel("Your photo")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Text("Kept in your album").font(SK.font(14, .bold)).foregroundStyle(.white)
            HStack(spacing: 10) {
                PhotoActionButton(title: saved == true ? "Saved" : "Save to Photos", symbol: saved == true ? "checkmark" : "square.and.arrow.down", prominent: true) {
                    Task { saved = await PhotoAlbum.saveToPhotos(url) }
                }
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Jelbies photo", image: Image(uiImage: image))) { PhotoActionLabel(title: "Share", symbol: "square.and.arrow.up", prominent: false) }
            }
            .fixedSize(horizontal: false, vertical: true)
            if saved == false { Text("Allow Photos access in Settings to save.").font(SK.font(13, .bold)).foregroundStyle(.white).multilineTextAlignment(.center) }
            PhotoActionButton(title: "Done", symbol: "checkmark.circle", prominent: false) { done() }
        }
    }
}
