//
//  PlayFont.swift
//  A rounded system font that grows with Dynamic Type (including the accessibility sizes), for the gameplay chrome (race, drill, show, bath, voice).
//  `size` is the design size at the default text size; `relativeTo` picks the curve it scales along.
//

import SwiftUI

struct PlayFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight; self.design = design
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: JFont.calm(weight), design: design)) }
}

extension View {
    /// `.font(.system(size:weight:design:))` that scales with Dynamic Type.
    func playFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .rounded, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(PlayFont(size: size, weight: weight, design: design, relativeTo: relativeTo))
    }
}
