//
//  ShowScoreStrip.swift
//  The Trick round's scoreboard strip (2026-11-17, the owner: "the colored circles and names is stupid or at least too large make it smaller and lower on screen"):
//  one small chip per entrant (the player's Jelmiko first, then the three rivals) low on the screen, just above Skip / the trick menu. Each chip has a small HEAD PICTURE of
//  that entrant (the lobby's head renderer; a rival is drawn on the borrowed body she performs on, in her colour; with no body she is a tinted silhouette), her name in small
//  type and her Trick points so far. The one performing is gold. About 50 pt tall, never wider than the screen, nothing covers a face.
//

import SwiftUI
import UIKit
import simd

struct ScoreStrip: View {
    let care: GameCare
    /// 1 on iPhone, 1.35 on iPad.
    var scale: CGFloat = 1
    /// A phone on its side (the strip lives in the right column).
    var compact = false
    private var show: ShowFlow { care.show }

    /// The first word of a long name ("Duchess Marmalade" -> "Duchess") so a chip never truncates it.
    static func shortName(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }
    static let height: CGFloat = 56

    struct Entry: Identifiable, Equatable {
        var id: Int                  // 0 = the player, 1...3 = rival 0...2
        var name: String
        var points: Int
        var performing: Bool
        var tint: SIMD3<Float>?
        var key: HeadPortraitKey?
    }

    /// The entries, in order: him, then the rivals as they perform.
    var entries: [Entry] {
        guard let s = show.sim else { return [] }
        let up = show.trickStage == .rivals ? show.rivalTurn : nil
        var out = [Entry(id: 0, name: show.playerName, points: show.playerTrickPoints, performing: up == nil, tint: nil,
                         key: HeadPortraitKey(jelly: show.playerID, colour: nil, wear: nil))]
        for (i, r) in s.rivals.enumerated() {
            // (the head renderer draws roster bodies only: she is drawn on the contestant's body in her colour, as the Studio lobby draws her; her stage body is a park visitor's)
            let key: HeadPortraitKey? = HeadPortraitKey(jelly: show.playerID, colour: nil, wear: nil, rivalTint: r.tint, rivalName: r.name)
            out.append(Entry(id: i + 1, name: r.name, points: show.rivalTrickPoints(i), performing: up == i, tint: r.tint, key: key))
        }
        return out
    }

    var body: some View {
        let list = entries
        HStack(spacing: 6 * scale) {
            ForEach(list) { e in chip(e) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height * scale)
        .animation(.easeOut(duration: 0.15), value: list.map(\.performing))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trick-next")
    }

    private func chip(_ e: Entry) -> some View {
        let s = scale
        let face = (compact ? 28 : 31) * s
        return HStack(spacing: 2 * s) {
            StripFace(care: care, key: e.key, tint: e.tint ?? JellyRoster.tint(care.jelly(show.playerID)?.character ?? 0), size: face, ring: e.performing)
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.shortName(e.name)).font(JFont.scaled(10 * s, .heavy, cap: 1.1)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.8)
                Text("\(e.points)").font(JFont.scaled(17 * s, .black, cap: 1.3)).foregroundStyle(SK.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 3 * s)
        .frame(maxWidth: .infinity).frame(height: Self.height * s)
        .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(e.performing ? ShowUI.gold : SK.cream.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).strokeBorder(e.performing ? ShowUI.goldDeep : .clear, lineWidth: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.name), \(e.points) points\(e.performing ? ", performing" : "")")
    }
}

/// A small round head picture; a tinted silhouette until the picture is drawn (or when the entrant has no body).
private struct StripFace: View {
    let care: GameCare
    var key: HeadPortraitKey?
    var tint: SIMD3<Float>
    var size: CGFloat
    var ring: Bool
    @State private var image: UIImage?
    var body: some View {
        let c = Color(red: Double(tint.x), green: Double(tint.y), blue: Double(tint.z))
        ZStack {
            Circle().fill(SK.tile)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                Ellipse().fill(c.opacity(0.9)).frame(width: size * 0.7, height: size * 0.78).offset(y: size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(ring ? ShowUI.goldDeep : SK.ink.opacity(0.12), lineWidth: ring ? 2 : 1))
        .accessibilityHidden(true)
        .task(id: key) {
            guard let key else { image = nil; return }
            if let hit = HeadPortraitCache.shared.cached(key, care: care) { image = hit; return }
            image = await HeadPortraitCache.shared.image(key, care: care)
        }
    }
}
