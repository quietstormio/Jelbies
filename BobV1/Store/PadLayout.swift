//
//  PadLayout.swift
//  iPad layout helpers for the Town screens, Settings and the small sheets. Every helper is a no-op on iPhone (idiom check, not size class: a Plus/Max
//  iPhone on its side is also a regular-width screen) so the iPhone layouts are exactly what they were.
//

import SwiftUI
import UIKit

extension View {
    /// On iPad: a centred readable column no wider than `maxWidth` (a background applied after this stays full-bleed). On iPhone: unchanged.
    @ViewBuilder func padReadable(_ maxWidth: CGFloat = 760) -> some View {
        if PadLayout.isPad { self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity) } else { self }
    }
}
