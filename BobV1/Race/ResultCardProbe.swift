//
//  ResultCardProbe.swift
//  A test-only measuring aid for the results cards (Jelly Volleyball, Jelly Race, Jelly Show). `.resultProbe("id")` on a Text records its frame (in the "resultScreen"
//  coordinate space) and whether it is cut short (its height is less than the height the same text needs at that width). Off unless the environment key is set,
//  so the shipped screens are unchanged: the modifier then returns the content as it is.
//

import SwiftUI

struct ResultTextInfo: Equatable {
    var id: String
    var frame: CGRect
    var actualHeight: CGFloat
    var idealHeight: CGFloat
    var truncated: Bool { actualHeight + 0.75 < idealHeight }
}

struct ResultTextKey: PreferenceKey {
    static var defaultValue: [ResultTextInfo] = []
    static func reduce(value: inout [ResultTextInfo], nextValue: () -> [ResultTextInfo]) { value += nextValue() }
}

private struct ResultProbeOnKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var resultProbeOn: Bool {
        get { self[ResultProbeOnKey.self] }
        set { self[ResultProbeOnKey.self] = newValue }
    }
}

struct ResultProbe: ViewModifier {
    let id: String
    @Environment(\.resultProbeOn) private var on
    func body(content: Content) -> some View {
        if on {
            content.background(
                GeometryReader { p in
                    let frame = p.frame(in: .named("resultScreen"))
                    content.fixedSize(horizontal: false, vertical: true)
                        .frame(width: p.size.width, alignment: .topLeading)
                        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                        .background(GeometryReader { q in
                            Color.clear.preference(key: ResultTextKey.self, value: [ResultTextInfo(id: id, frame: frame, actualHeight: p.size.height, idealHeight: q.size.height)])
                        })
                }
            )
        } else {
            content
        }
    }
}

extension View {
    /// Mark a text (or a button label) of a results card for the layout tests. No effect in the shipped app.
    func resultProbe(_ id: String) -> some View { modifier(ResultProbe(id: id)) }
}
