//
//  GameCare+A11y.swift
//  The accessibility announcer a GameCare owns (kept as an associated object: no stored property in GameCare.swift).
//

import Foundation
import ObjectiveC

private nonisolated(unsafe) var a11yEventsKey: UInt8 = 0

extension GameCare {
    /// The VoiceOver announcer of this care (`Accessibility/A11yEvents.swift`), made on first use.
    var a11yEvents: A11yEvents {
        if let e = objc_getAssociatedObject(self, &a11yEventsKey) as? A11yEvents { return e }
        let e = A11yEvents(care: self)
        objc_setAssociatedObject(self, &a11yEventsKey, e, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return e
    }
}
