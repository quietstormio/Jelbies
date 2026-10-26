//
//  PhotoAlbum.swift
//  Every photo is kept in the app's Documents/Photos (JPEG). The in-game album: a grid, a viewer with Save to Photos / Share / Delete.
//  The main menu's Photos button shows it through StartFlow.albumView (registered at launch by PhotoAlbum.register()).
//

import SwiftUI
import Photos
import ImageIO
import Observation

@MainActor
@Observable
final class PhotoAlbum {
    static let shared = PhotoAlbum()
    private(set) var items: [URL] = []          // newest first

    static var folder: URL { URL.documentsDirectory.appending(path: "Photos", directoryHint: .isDirectory) }

    init() { reload() }
    nonisolated deinit {}

    /// Main menu: Photos opens the album.
    static func register() { StartFlow.albumView = { AnyView(PhotoAlbumView(close: nil)) } }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        items = urls.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @discardableResult
    func add(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss-SSS"; f.locale = Locale(identifier: "en_US_POSIX")
        let url = Self.folder.appending(path: "Jelbies-\(f.string(from: Date())).jpg")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        reload()
        return url
    }

    func delete(_ url: URL) { try? FileManager.default.removeItem(at: url); PhotoThumbs.cache.removeObject(forKey: url as NSURL); reload() }

    /// Add-only save to the system Photos library. True when it went in.
    static func saveToPhotos(_ url: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited, let data = try? Data(contentsOf: url) else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
            return true
        } catch { return false }
    }
}

enum PhotoThumbs {
    static let cache = NSCache<NSURL, UIImage>()
    static func image(_ url: URL, maxPixel: Int = 420) -> UIImage? {
        if let c = cache.object(forKey: url as NSURL) { return c }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}

struct PhotoAlbumView: View {
    /// Close button for when the album is opened from inside the game; the main menu draws its own, so it passes nil.
    var close: (() -> Void)?
    @State private var album = PhotoAlbum.shared
    @State private var viewing: URL?
    @Environment(\.verticalSizeClass) private var vsc

    var body: some View {
        ZStack {
            SK.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Photos").font(SK.font(30, .semibold)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let close { GameCircleButton(systemName: "xmark", label: "Close album") { close() } }
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.trailing, close == nil ? 56 : 0)
                if album.items.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "camera").font(.system(size: 40, weight: .semibold)).foregroundStyle(SK.muted).accessibilityHidden(true)
                        Text("No photos yet").font(SK.font(20, .semibold)).foregroundStyle(SK.ink)
                        Text("Use the camera button in the room to take one.").font(SK.font(15, .semibold)).foregroundStyle(SK.muted).multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .accessibilityElement(children: .combine)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: vsc == .compact ? 150 : 110), spacing: 8)], spacing: 8) {
                            ForEach(album.items, id: \.self) { url in
                                Button { viewing = url } label: {
                                    Color.clear.aspectRatio(0.75, contentMode: .fit)
                                        .overlay { if let t = PhotoThumbs.image(url) { Image(uiImage: t).resizable().scaledToFill() } else { SK.card } }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Photo")
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .onAppear { album.reload() }
        .fullScreenCover(item: $viewing) { url in PhotoViewer(url: url) { viewing = nil } }
        .accessibilityIdentifier("photo-album")
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// One photo, large: Save to Photos, Share, Delete (confirmed).
private struct PhotoViewer: View {
    let url: URL
    var done: () -> Void
    @State private var saved: Bool?
    @State private var confirmDelete = false

    var body: some View {
        let img = UIImage(contentsOfFile: url.path)
        ZStack {
            Color.black.ignoresSafeArea()
            if let img { Image(uiImage: img).resizable().scaledToFit().ignoresSafeArea(edges: .horizontal).accessibilityLabel("Photo") }
            VStack {
                HStack { Spacer(); GameCircleButton(systemName: "xmark", label: "Close photo") { done() } }
                Spacer()
                HStack(spacing: 10) {
                    PhotoActionButton(title: saved == true ? "Saved" : "Save to Photos", symbol: saved == true ? "checkmark" : "square.and.arrow.down", prominent: true) {
                        Task { saved = await PhotoAlbum.saveToPhotos(url) }
                    }
                    if let img { ShareLink(item: Image(uiImage: img), preview: SharePreview("Jelbies photo", image: Image(uiImage: img))) { PhotoActionLabel(title: "Share", symbol: "square.and.arrow.up", prominent: false) } }
                    PhotoActionButton(title: "Delete", symbol: "trash", prominent: false) { confirmDelete = true }
                }
                if saved == false { Text("Allow Photos access in Settings to save.").font(SK.font(14, .bold)).foregroundStyle(.white).padding(.top, 4) }
            }
            .padding(16)
        }
        .alert("Delete this photo?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { PhotoAlbum.shared.delete(url); done() }
            Button("Keep", role: .cancel) {}
        }
    }
}

struct PhotoActionLabel: View {
    let title: String, symbol: String, prominent: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            Text(title).font(SK.font(15, .semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(SK.ink).padding(.horizontal, 14).frame(minHeight: 48)
        .background(Capsule().fill(prominent ? SK.honey : DT.card).shadow(color: SK.shadow.opacity(0.25), radius: 4, y: 2))
    }
}

struct PhotoActionButton: View {
    let title: String, symbol: String, prominent: Bool
    let action: () -> Void
    var body: some View {
        Button { AudioHub.shared.uiTap(); action() } label: { PhotoActionLabel(title: title, symbol: symbol, prominent: prominent) }.buttonStyle(.plain)
    }
}
