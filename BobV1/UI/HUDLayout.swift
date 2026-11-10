//
//  HUDLayout.swift
//  Where the side rails sit: at the bottom of the screen (the user wants them there, 2026-10-22). Instead of lifting the buttons, the roam floor has corner
//  cut-outs under the two rails in portrait (`railRects`, used by GameCamera.refreshRoam), so a front-row Jelbie is never under a button.
//

import SwiftUI
import UIKit
import simd

enum HUDTuning {
    /// Portrait: lift of the side rails above the bottom edge, as a fraction of the screen height. 0 = at the bottom, as on release.
    static let frontBandPortrait: CGFloat = 0
    /// Landscape: 0 when the front-corner Jelbies do not reach under the rails; otherwise the band (the test decides).
    static let frontBandLandscape: CGFloat = 0
    static let railGap: CGFloat = 10            // space between buttons in a rail
    static let railWidth: CGFloat = 60, railRow: CGFloat = 54          // the left glass capsule: 60 wide, 54 pt rows
    static let goOutSize: CGFloat = 56, goOutSizeTight: CGFloat = 46
}

enum HUDLayout {
    /// True on iPad. Every iPad-only adaptation is gated on this (or on a measured size), so the iPhone path is untouched.
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Landscape layout wanted: a phone on its side (vsc .compact, as before) OR, on iPad only, a window wider than tall (iPad's vsc is .regular in every orientation).
    static func isLandscape(vsc: UserInterfaceSizeClass?, size: CGSize) -> Bool {
        vsc == .compact || (isPad && size.width > size.height)
    }

    /// The HUD's measured size (the game screen's geometry, window not display), kept by GameScreen for the roam floor's rail cut-outs. Zero until measured.
    nonisolated(unsafe) static var measuredSize: CGSize = .zero

    /// iPad HUD scale from the measured short side (744 pt mini -> 1.1, 1032 pt 13-inch -> 1.3). Always 1 on iPhone, so the phone HUD is untouched.
    static func padScale(short: CGFloat) -> CGFloat {
        guard isPad, short > 0 else { return 1 }
        return min(1.3, max(1.1, 1.1 + (short - 744) / 288 * 0.2))
    }
    static func padScale(size: CGSize) -> CGFloat { padScale(short: min(size.width, size.height)) }

    /// The size the iPad rails are laid out for: the measured HUD, else the screen.
    private static var padSize: CGSize { measuredSize.width > 0 && measuredSize.height > 0 ? measuredSize : UIScreen.main.bounds.size }

    /// Screen rectangles (fractions of width/height, top-left origin) of the bottom-corner rails in portrait: the left glass capsule (16 pt in, 60 wide: book, bag, Go out, mic) and the right
    /// heart alone (72), measured from a 393 pt wide phone (wider phones have slimmer fractions, so this is a touch conservative), up to
    /// `railHeightFraction` of the screen height from the bottom.
    static let railHeightFraction: CGFloat = 0.29          // the tall left capsule: 4 rows + divider + padding is ~245 pt of an 852 pt phone
    static let railRightHeightFraction: CGFloat = 0.13          // the heart alone: 72 pt + margin
    static let railRects: [CGRect] = [
        CGRect(x: 0, y: 1 - railHeightFraction, width: (16 + 60 + 4) / 393, height: railHeightFraction),
        CGRect(x: 1 - (16 + 4 + 72 + 4) / 393, y: 1 - railRightHeightFraction, width: (16 + 4 + 72 + 4) / 393, height: railRightHeightFraction),
    ]

    /// The park's bottom-centre "Go home" pill (Park/ParkChrome.swift: capsule minHeight 54, 26 pt side padding, font 19, 24 pt bottom padding above the safe area) as a screen
    /// rectangle (fractions, top-left origin), a little oversized and reaching the bottom edge. Reference phone: 393 x 852 portrait (34 pt bottom safe area), 852 x 393 landscape (21 pt).
    /// The park's round Play button: its diameter and the gap to the Go home pill.
    static let parkPlaySize: CGFloat = 54, parkPlayGap: CGFloat = 12
    static func parkHomeRect(aspect: Float) -> CGRect {
        let portrait = aspect < 1
        var w: CGFloat = portrait ? 393 : 852, h: CGFloat = portrait ? 852 : 393, safe: CGFloat = portrait ? 34 : 21
        if isPad { w = padSize.width; h = padSize.height; safe = 20 }          // iPad: the real window (the pill itself is not scaled)
        let pillW: CGFloat = 176, pillH: CGFloat = 54, margin: CGFloat = 10
        let top = (h - safe - 24 - pillH - margin) / h
        let halfW = (pillW / 2 + margin) / w
        let playW = (parkPlaySize + parkPlayGap) / w          // the round Play button stands to the left of the pill (ParkChrome.swift)
        return CGRect(x: 0.5 - halfW - playW, y: top, width: 2 * halfW + playW, height: 1 - top)
    }

    /// `railRects`, size-aware: on iPad the rails are scaled by `padScale` (and the window can be any size), so the cut-outs follow; on iPhone exactly `railRects`.
    static func railRects(aspect: Float) -> [CGRect] {
        guard isPad else { return railRects }
        let size = padSize, s = padScale(size: size)
        let w = size.width, h = size.height
        return [
            CGRect(x: 0, y: 1 - min(0.6, 250 * s / h), width: (16 + 60 * s + 4) / w, height: min(0.6, 250 * s / h)),
            CGRect(x: 1 - (16 + 4 + 72 * s + 4) / w, y: 1 - (72 * s + 24) / h, width: (16 + 4 + 72 * s + 4) / w, height: (72 * s + 24) / h),
        ]
    }

    /// True when a Jelbie centred at floor (x, z) has its body box (the same one the roam margins use) overlapping a rail rectangle on screen.
    static func bodyHitsRail(x: Float, z: Float, viewProj: simd_float4x4, size: CGSize, rails: [CGRect]) -> Bool {
        guard !rails.isEmpty else { return false }
        let e = GameCamera.roamLateralExtent, h = BobShape.H * 1.25, d: Float = 0.8
        var corners = [SIMD3<Float>]()
        for cx in [x - e, x + e] { for cy in [0, h] { for cz in [z - d, z + d] { corners.append(SIMD3(cx, cy, cz)) } } }
        let pts = Silhouette.project(corners, viewProj: viewProj, size: size)
        guard let lo = pts.map(\.x).min(), let hi = pts.map(\.x).max(), let top = pts.map(\.y).min(), let bot = pts.map(\.y).max() else { return false }
        let box = CGRect(x: lo / size.width, y: top / size.height, width: (hi - lo) / size.width, height: (bot - top) / size.height)
        return rails.contains { $0.intersects(box) }
    }

    /// Bottom padding for the bottom HUD cluster, measured from the bottom safe edge.
    static func lift(size: CGSize, safeBottom: CGFloat, compact: Bool) -> CGFloat {
        compact ? HUDTuning.frontBandLandscape * size.height : max(0, HUDTuning.frontBandPortrait * size.height - safeBottom)
    }

    /// For tests: the screen y (points, top-left origin) of the highest point of a front-row Jelbie whose body reaches into [xLo, xHi] screen points.
    @MainActor static func frontBandTop(aspect: Float, size: CGSize, xRange: ClosedRange<CGFloat>?) -> CGFloat {
        GameCamera.configureRoom(count: 3)
        guard let rf = GameCamera.refreshRoam(aspect: aspect) else { return size.height }
        let cam = GameCamera.camera(aspect: aspect)
        var top = size.height
        let z = rf.maxZ
        let hw = rf.halfWidth(at: z)
        var x = -hw
        while x <= hw + 0.001 {
            let e = GameCamera.roamLateralExtent, h = BobShape.H * 1.25, d: Float = 0.8
            var corners = [SIMD3<Float>]()
            for cx in [x - e, x + e] { for cy in [0, h] { for cz in [z - d, z + d] { corners.append(SIMD3(cx, cy, cz)) } } }
            let pts = Silhouette.project(corners, viewProj: cam.viewProj, size: size)
            if let lo = pts.map(\.x).min(), let hi = pts.map(\.x).max(), let y = pts.map(\.y).min() {
                if xRange == nil || (hi >= xRange!.lowerBound && lo <= xRange!.upperBound) { top = min(top, y) }
            }
            x += 0.1
        }
        return top
    }
}

/// The one glass look of the home HUD: neutral white frosted glass (the clear glass picked up the brown room and hid the brown icons).
enum HUDGlass {
    /// The opaque HUD fill (the default; -NoMaterials 0 brings the glass back): near-white cream, the look of the frosted glass over the room.
    static let opaque = Color(red: 0.985, green: 0.972, blue: 0.945)
    static let white = Color.white          // neutral, so it works over every room's colours
    static let frost: Glass = .regular.tint(white.opacity(0.55)).interactive()
    static let pink: Glass = .regular.tint(Color(red: 0.95, green: 0.38, blue: 0.56)).interactive()
}

extension View {
    /// White frosted Liquid Glass in `shape`, with a white fill under it so the room only shows through a little.
    func hudFrost<S: SwiftUI.Shape>(in shape: S) -> some View {
        hudGlassEffect(HUDGlass.frost, opaque: HUDGlass.opaque, in: shape, under: HUDGlass.white.opacity(0.4))
    }
    /// `.glassEffect`, or with -NoMaterials 1 an opaque `opaque` fill instead (no backdrop sampling over the live Metal view).
    @ViewBuilder
    func hudGlassEffect<S: SwiftUI.Shape>(_ glass: Glass, opaque: Color, in shape: S, under: Color? = nil) -> some View {
        if GfxFlags.noMaterials {
            background(shape.fill(opaque).shadow(color: Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.18), radius: 5, y: 2))
        } else if let under {
            background(shape.fill(under)).glassEffect(glass, in: shape)
        } else {
            glassEffect(glass, in: shape)
        }
    }
}

/// Sheet presentation for regular width: on iPad a sheet is a floating form/page card, so detents are ignored; ask for a full page card. A no-op on iPhone.
struct PadSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if HUDLayout.isPad { content.presentationSizing(.page) } else { content }
    }
}
extension View { func padSheetSizing() -> some View { modifier(PadSheetSizing()) } }
