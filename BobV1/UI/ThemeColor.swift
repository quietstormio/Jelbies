//
//  ThemeColor.swift
//  The player's theme colour: one saved choice (UserDefaults "ThemeColor.v1") that gives a full palette for the title screen and the
//  loading screen (background, pattern, button lip, New Game fill, Continue text, logo shadow, the peeking Jelbie's rim and eyes).
//  Sky Blue is the default (the title design's exact colours). Every other palette is derived from its background colour with the same
//  relationships, then darkened until the button text is 4.5:1 or better.
//

import SwiftUI
import UIKit

struct ThemePalette: Equatable {
    var id: String
    var bg, lip, newGame, continueText, shadow, rim, eye, shade: Color
    var patternOpacity = 0.13
    var newGameLabel: Color { .white }
}

enum ThemePreset: String, CaseIterable, Identifiable {
    case sky, pink, mint, lavender, yellow, peach, navy, teal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sky: "Sky Blue"; case .pink: "Bubblegum Pink"; case .mint: "Mint"; case .lavender: "Lavender"
        case .yellow: "Sunny Yellow"; case .peach: "Peach"; case .navy: "Midnight Navy"; case .teal: "Jelly Teal"
        }
    }
    var hex: UInt32 {
        switch self {
        case .sky: 0x5A97D6; case .pink: 0xEE8DB6; case .mint: 0x5FC4A0; case .lavender: 0x9D8CDF
        case .yellow: 0xF2C14E; case .peach: 0xF4A27A; case .navy: 0x26335F; case .teal: 0x2FA3A6
        }
    }
}

enum ThemeMath {
    static func lum(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func f(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }
    static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let l1 = lum(a), l2 = lum(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
    static func ui(_ hex: UInt32) -> UIColor { UIColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
    static func hsb(_ c: UIColor) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }
    /// Darkens until `against` contrast is at least 4.5.
    static func readable(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat, on against: UIColor) -> UIColor {
        var b = b
        var c = UIColor(hue: h, saturation: min(max(s, 0), 1), brightness: b, alpha: 1)
        var n = 0
        while contrast(c, against) < 4.5, n < 60 { b *= 0.95; c = UIColor(hue: h, saturation: min(max(s, 0), 1), brightness: b, alpha: 1); n += 1 }
        return c
    }

    static func palette(id: String, bg: UIColor) -> ThemePalette {
        let (h, s0, b0) = hsb(bg)
        let s = s0, b = b0
        let dark = b < 0.45
        let white = UIColor.white
        let newGame = dark ? readable(h, s * 0.9, min(1, b * 1.7), on: white) : readable(h, min(1, s + 0.12), b * 0.83, on: white)
        let text = readable(h, min(1, s + 0.13), b * 0.76, on: white)
        let lipB = dark ? b * 0.6 : b * 0.70
        return ThemePalette(
            id: id, bg: Color(bg),
            lip: Color(UIColor(hue: h, saturation: min(1, s + 0.11), brightness: lipB, alpha: 1)),
            newGame: Color(newGame), continueText: Color(text),
            shadow: Color(UIColor(hue: h, saturation: min(1, s + 0.09), brightness: dark ? b * 0.7 : b * 0.83, alpha: 1)),
            rim: Color(UIColor(hue: h, saturation: s * 0.64, brightness: min(1, dark ? b + 0.3 : b + 0.04), alpha: 1)),
            eye: Color(UIColor(hue: h, saturation: s * 0.53, brightness: min(b * 0.87, 0.72), alpha: 1)),
            shade: Color(UIColor(hue: h, saturation: 0.09, brightness: 0.97, alpha: 1)))
    }

    static func palette(_ p: ThemePreset) -> ThemePalette {
        if p == .sky {          // the title design's exact colours
            return ThemePalette(id: p.rawValue, bg: Color(hex: 0x5A97D6), lip: Color(hex: 0x2F5F97), newGame: Color(hex: 0x3672B3),
                                continueText: Color(hex: 0x2F66A4), shadow: Color(hex: 0x3B74B2), rim: Color(hex: 0x8DB8E0),
                                eye: Color(hex: 0x7F9FB9), shade: Color(hex: 0xE2EDF8))
        }
        return palette(id: p.rawValue, bg: ui(p.hex))
    }
}

/// The saved choice: a preset's raw value. (Older builds could save "custom:RRGGBB"; that migrates to the nearest preset.)
@Observable @MainActor final class ThemeStore {
    static let shared = ThemeStore()
    static let key = "ThemeColor.v1"
    var selection: String { didSet { if selection != oldValue { UserDefaults.standard.set(selection, forKey: Self.key) } } }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? ThemePreset.sky.rawValue
        if ThemePreset(rawValue: saved) != nil { selection = saved }
        else if saved.hasPrefix("custom:"), let v = UInt32(saved.dropFirst(7), radix: 16) {
            selection = ThemePreset.nearest(toHex: v).rawValue
            UserDefaults.standard.set(selection, forKey: Self.key)
        } else { selection = ThemePreset.sky.rawValue }
    }

    var preset: ThemePreset? { ThemePreset(rawValue: selection) }
    var currentPreset: ThemePreset { preset ?? .sky }
    var palette: ThemePalette { ThemeMath.palette(currentPreset) }
    /// The logo's outline tone for this theme: the accent itself, deepened only where needed to reach 3:1 on white.
    var logoOutline: Color { currentPreset.logoRim.map { Color(hex: $0) } ?? palette.rim }
    func choose(_ p: ThemePreset) {
        selection = p.rawValue
        AppIconSwitcher.syncIfEnabled(p)
    }
}

extension ThemePreset {
    /// Deeper logo outline (the accent itself, deepened only where a preset is under 3:1 on white).
    var logoRim: UInt32? {
        switch self {
        case .pink: 0xD9668F; case .mint: 0x2E9C78; case .lavender: 0x7A66CC; case .yellow: 0xC08A1E
        case .peach: 0xD9774A; case .teal: 0x1F8A8D; case .sky: 0x5A97D6; case .navy: 0x26335F
        }
    }
    static func nearest(toHex v: UInt32) -> ThemePreset {
        func c(_ h: UInt32) -> (Double, Double, Double) { (Double(h >> 16 & 255), Double(h >> 8 & 255), Double(h & 255)) }
        let a = c(v)
        return allCases.min { l, r in dist(a, c(l.hex)) < dist(a, c(r.hex)) } ?? .sky
    }
    private static func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        (a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)
    }
    /// Alternate app icon set name; Sky Blue is the primary icon (nil).
    var alternateIconName: String? { self == .sky ? nil : "AppIcon-" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// Suffix of the pre-rendered intro clip ("jelbies_intro_<id>"); Sky Blue uses the original.
    var introResource: String { "jelbies_intro_" + rawValue }
}

/// Switches the home-screen icon to match the theme ("Match app icon to theme", on by default).
enum AppIconSwitcher {
    static let key = "ThemeIcon.match.v1"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    @MainActor static func syncIfEnabled(_ p: ThemePreset) { if enabled { apply(p) } }
    @MainActor static func apply(_ p: ThemePreset) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != p.alternateIconName else { return }
        app.setAlternateIconName(p.alternateIconName) { _ in }
    }
}

/// Recolours the logo's blue-to-white ramp onto outline-to-white (see LogoTint.metal). 
extension View {
    @MainActor func themedLogo() -> some View {
        colorEffect(ShaderLibrary.logoTint(.color(ThemeStore.shared.logoOutline)))
    }
}

/// The "Peek" app icon's colours for a theme (mirrors tools/themeicon/make_theme_assets.py).
struct IconPalette {
    var bg, body, line, ink, hi, shine: Color
    init(_ p: ThemePreset) {
        let (h, s, b) = ThemeMath.hsb(ThemeMath.ui(p.hex))
        let dark = b < 0.45
        func hsb(_ s: CGFloat, _ b: CGFloat) -> Color { Color(UIColor(hue: h, saturation: min(max(s, 0), 1), brightness: min(max(b, 0), 1), alpha: 1)) }
        bg = Color(hex: p.hex); body = .white; hi = .white
        line = dark ? hsb(s, b + 0.3) : hsb(s + 0.1, b * 0.72)
        ink = hsb(s * 0.9 + 0.1, min(b * 0.4, 0.28))
        shine = hsb(s * 0.3, 1)
    }
}

struct ThemeIconView: View {
    let preset: ThemePreset
    var body: some View {
        Canvas { ctx, size in
            let pal = IconPalette(preset)
            let k = size.width / 1024
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pal.bg))
            func E(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ c: Color) {
                ctx.fill(Path(ellipseIn: CGRect(x: (cx - rx) * k, y: (cy - ry) * k, width: 2 * rx * k, height: 2 * ry * k)), with: .color(c))
            }
            // the round head dome (mirrors tools/themeicon/make_theme_assets.py)
            let cx: CGFloat = 512, cy: CGFloat = 891, rx: CGFloat = 643, ry: CGFloat = 459, ow: CGFloat = 44
            E(cx, cy, rx + ow / 2, ry + ow / 2, pal.line)
            E(cx, cy, rx - ow / 2, ry - ow / 2, pal.body)
            let a = rx - ow / 2 - 55, b = ry - ow / 2 - 55
            func onArc(_ deg: Double) -> CGPoint { CGPoint(x: (cx + a * cos(deg * .pi / 180)) * k, y: (cy + b * sin(deg * .pi / 180)) * k) }
            var arc = Path()
            for i in 0...40 { let q = onArc(228 + Double(i) * 0.85); if i == 0 { arc.move(to: q) } else { arc.addLine(to: q) } }
            ctx.stroke(arc, with: .color(pal.shine), style: StrokeStyle(lineWidth: 40 * k, lineCap: .round))
            let dot = onArc(220)
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 18 * k, y: dot.y - 18 * k, width: 36 * k, height: 36 * k)), with: .color(pal.shine))
            for sx: CGFloat in [-1, 1] {
                var brow = Path()
                brow.move(to: CGPoint(x: (cx + sx * 105) * k, y: 690 * k)); brow.addLine(to: CGPoint(x: (cx + sx * 225) * k, y: 690 * k))
                ctx.stroke(brow, with: .color(pal.ink), style: StrokeStyle(lineWidth: 30 * k, lineCap: .round))
                E(cx + sx * 165, 788, 40, 52, pal.ink)
                E(cx + sx * 165 - sx * 11, 768, 11, 13, pal.hi)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }
}
