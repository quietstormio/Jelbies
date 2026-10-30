//
//  HeadPortrait.swift
//  What a lobby avatar asks the stage for: Jelly `jelly` as he is (his colours, his outfit), or, with `colour`, that body in a Park visitor's colour wearing the visitor's one item
//  (the Park friend who plays beside a lone Jelbie). Drawn by MelonStage.headSnapshot with the room hidden, framed on the head.
//

import Foundation

struct HeadPortraitKey: Hashable, Sendable {
    var jelly: Int
    var colour: ParkColour?
    var wear: WearLook?
    /// A Show rival's body tint and name: drawn with `LocalRivalSource.palette`, exactly as the stage paints a borrowed body.
    var rivalTint: SIMD3<Float>? = nil
    var rivalName: String? = nil
    /// Another creature on this body (a Park friend or a rival): no feature, no wear of his.
    var borrowed: Bool { colour != nil || rivalTint != nil }
    /// How far above the body's centre the camera looks, and how tall the picture is (world units): the head, a hat and a little body.
    static var focusUp: Float { UserDefaults.standard.object(forKey: "HeadFocus") != nil ? UserDefaults.standard.float(forKey: "HeadFocus") : 0.30 }          // (-HeadFocus / -HeadSpan: capture aids)
    static var span: Float { UserDefaults.standard.object(forKey: "HeadSpan") != nil ? UserDefaults.standard.float(forKey: "HeadSpan") : 1.24 }
}
