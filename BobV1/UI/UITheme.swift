import SwiftUI

// MARK: - Palette

extension Color {
    /// "#RRGGBB" hex.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt32(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255, opacity: 1)
    }
}

/// Cosy peach/cream palette matching RoomTheme's default tint (0.96, 0.78, 0.66).
enum UITheme {
    static let peach = Color(.sRGB, red: 0.96, green: 0.78, blue: 0.66)
    static let cream = Color(.sRGB, red: 1.0, green: 0.95, blue: 0.89)
    static let panel = Color(.sRGB, red: 1.0, green: 0.93, blue: 0.85)
    static let panelDeep = Color(.sRGB, red: 0.96, green: 0.84, blue: 0.72)
    static let ink = Color(.sRGB, red: 0.40, green: 0.24, blue: 0.20)
    static let inkSoft = Color(.sRGB, red: 0.40, green: 0.24, blue: 0.20).opacity(0.65)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.68)

    static func title(_ size: CGFloat = 28) -> Font { JFont.scaled(size, .bold, style: .title2) }
    static func body(_ size: CGFloat = 16) -> Font { JFont.scaled(size, .semibold) }
    static func caption(_ size: CGFloat = 13) -> Font { JFont.scaled(size, .medium, style: .footnote) }
}

extension BreedID {
    var core: Color { Color(hex: spec.colorHexCore) }
    var light: Color { Color(hex: spec.colorHexLight) }
    var deep: Color { Color(hex: spec.colorHexDeep) }
    var featureDescription: String {
        switch spec.feature {
        case .none: return "Smooth and squishy all over"
        case .dorsalSpikes: return "Soft spikes down its back"
        case .curlyAntenna: return "A bouncy curly antenna"
        }
    }
}

extension Marking {
    var displayName: String {
        switch self {
        case .none: return "Plain"
        case .spotOnHead: return "Head spot"
        case .starOnHead: return "Star"
        case .heartOnCheek: return "Heart cheek"
        case .freckles: return "Freckles"
        case .spotOnBack: return "Back spot"
        case .whiteBelly: return "Pale belly"
        }
    }
}
