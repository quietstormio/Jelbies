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

/// The saved choice. `selection` is a preset's raw value or "custom:RRGGBB".
@Observable @MainActor final class ThemeStore {
    static let shared = ThemeStore()
    static let key = "ThemeColor.v1"
    var selection: String { didSet { if selection != oldValue { UserDefaults.standard.set(selection, forKey: Self.key) } } }

    init() { selection = UserDefaults.standard.string(forKey: Self.key) ?? ThemePreset.sky.rawValue }

    var preset: ThemePreset? { ThemePreset(rawValue: selection) }
    var palette: ThemePalette {
        if let p = preset { return ThemeMath.palette(p) }
        if selection.hasPrefix("custom:"), let v = UInt32(selection.dropFirst(7), radix: 16) {
            // one colour in: keep the hue, clamp lightness so the derived palette stays readable
            let (h, s, b) = ThemeMath.hsb(ThemeMath.ui(v))
            let bg = UIColor(hue: h, saturation: min(max(s, 0.25), 0.85), brightness: min(max(b, 0.3), 0.92), alpha: 1)
            return ThemeMath.palette(id: selection, bg: bg)
        }
        return ThemeMath.palette(.sky)
    }
    func choose(_ p: ThemePreset) { selection = p.rawValue }
    func chooseCustom(_ c: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        selection = String(format: "custom:%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
    var customColor: Color {
        if selection.hasPrefix("custom:"), let v = UInt32(selection.dropFirst(7), radix: 16) { return Color(hex: v) }
        return Color(hex: 0x8B5CF6)
    }
}
