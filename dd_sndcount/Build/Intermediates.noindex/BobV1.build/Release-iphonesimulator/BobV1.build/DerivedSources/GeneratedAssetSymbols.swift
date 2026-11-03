import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "LaunchBackground" asset catalog color resource.
    static let launchBackground = DeveloperToolsSupport.ColorResource(name: "LaunchBackground", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "JelbiesLogo" asset catalog image resource.
    static let jelbiesLogo = DeveloperToolsSupport.ImageResource(name: "JelbiesLogo", bundle: resourceBundle)

    /// The "room_thumb_cabin" asset catalog image resource.
    static let roomThumbCabin = DeveloperToolsSupport.ImageResource(name: "room_thumb_cabin", bundle: resourceBundle)

    /// The "room_thumb_home" asset catalog image resource.
    static let roomThumbHome = DeveloperToolsSupport.ImageResource(name: "room_thumb_home", bundle: resourceBundle)

    /// The "room_thumb_loft" asset catalog image resource.
    static let roomThumbLoft = DeveloperToolsSupport.ImageResource(name: "room_thumb_loft", bundle: resourceBundle)

    /// The "town_preview_adopt" asset catalog image resource.
    static let townPreviewAdopt = DeveloperToolsSupport.ImageResource(name: "town_preview_adopt", bundle: resourceBundle)

    /// The "town_preview_beach" asset catalog image resource.
    static let townPreviewBeach = DeveloperToolsSupport.ImageResource(name: "town_preview_beach", bundle: resourceBundle)

    /// The "town_preview_cafe" asset catalog image resource.
    static let townPreviewCafe = DeveloperToolsSupport.ImageResource(name: "town_preview_cafe", bundle: resourceBundle)

    /// The "town_preview_friends" asset catalog image resource.
    static let townPreviewFriends = DeveloperToolsSupport.ImageResource(name: "town_preview_friends", bundle: resourceBundle)

    /// The "town_preview_groom" asset catalog image resource.
    static let townPreviewGroom = DeveloperToolsSupport.ImageResource(name: "town_preview_groom", bundle: resourceBundle)

    /// The "town_preview_park" asset catalog image resource.
    static let townPreviewPark = DeveloperToolsSupport.ImageResource(name: "town_preview_park", bundle: resourceBundle)

    /// The "town_preview_shop" asset catalog image resource.
    static let townPreviewShop = DeveloperToolsSupport.ImageResource(name: "town_preview_shop", bundle: resourceBundle)

    /// The "town_preview_studio" asset catalog image resource.
    static let townPreviewStudio = DeveloperToolsSupport.ImageResource(name: "town_preview_studio", bundle: resourceBundle)

    /// The "town_preview_track" asset catalog image resource.
    static let townPreviewTrack = DeveloperToolsSupport.ImageResource(name: "town_preview_track", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "JelbiesLogo" asset catalog image.
    static var jelbiesLogo: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jelbiesLogo)
#else
        .init()
#endif
    }

    /// The "room_thumb_cabin" asset catalog image.
    static var roomThumbCabin: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .roomThumbCabin)
#else
        .init()
#endif
    }

    /// The "room_thumb_home" asset catalog image.
    static var roomThumbHome: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .roomThumbHome)
#else
        .init()
#endif
    }

    /// The "room_thumb_loft" asset catalog image.
    static var roomThumbLoft: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .roomThumbLoft)
#else
        .init()
#endif
    }

    /// The "town_preview_adopt" asset catalog image.
    static var townPreviewAdopt: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewAdopt)
#else
        .init()
#endif
    }

    /// The "town_preview_beach" asset catalog image.
    static var townPreviewBeach: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewBeach)
#else
        .init()
#endif
    }

    /// The "town_preview_cafe" asset catalog image.
    static var townPreviewCafe: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewCafe)
#else
        .init()
#endif
    }

    /// The "town_preview_friends" asset catalog image.
    static var townPreviewFriends: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewFriends)
#else
        .init()
#endif
    }

    /// The "town_preview_groom" asset catalog image.
    static var townPreviewGroom: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewGroom)
#else
        .init()
#endif
    }

    /// The "town_preview_park" asset catalog image.
    static var townPreviewPark: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewPark)
#else
        .init()
#endif
    }

    /// The "town_preview_shop" asset catalog image.
    static var townPreviewShop: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewShop)
#else
        .init()
#endif
    }

    /// The "town_preview_studio" asset catalog image.
    static var townPreviewStudio: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewStudio)
#else
        .init()
#endif
    }

    /// The "town_preview_track" asset catalog image.
    static var townPreviewTrack: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .townPreviewTrack)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "JelbiesLogo" asset catalog image.
    static var jelbiesLogo: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .jelbiesLogo)
#else
        .init()
#endif
    }

    /// The "room_thumb_cabin" asset catalog image.
    static var roomThumbCabin: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .roomThumbCabin)
#else
        .init()
#endif
    }

    /// The "room_thumb_home" asset catalog image.
    static var roomThumbHome: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .roomThumbHome)
#else
        .init()
#endif
    }

    /// The "room_thumb_loft" asset catalog image.
    static var roomThumbLoft: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .roomThumbLoft)
#else
        .init()
#endif
    }

    /// The "town_preview_adopt" asset catalog image.
    static var townPreviewAdopt: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewAdopt)
#else
        .init()
#endif
    }

    /// The "town_preview_beach" asset catalog image.
    static var townPreviewBeach: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewBeach)
#else
        .init()
#endif
    }

    /// The "town_preview_cafe" asset catalog image.
    static var townPreviewCafe: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewCafe)
#else
        .init()
#endif
    }

    /// The "town_preview_friends" asset catalog image.
    static var townPreviewFriends: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewFriends)
#else
        .init()
#endif
    }

    /// The "town_preview_groom" asset catalog image.
    static var townPreviewGroom: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewGroom)
#else
        .init()
#endif
    }

    /// The "town_preview_park" asset catalog image.
    static var townPreviewPark: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewPark)
#else
        .init()
#endif
    }

    /// The "town_preview_shop" asset catalog image.
    static var townPreviewShop: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewShop)
#else
        .init()
#endif
    }

    /// The "town_preview_studio" asset catalog image.
    static var townPreviewStudio: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewStudio)
#else
        .init()
#endif
    }

    /// The "town_preview_track" asset catalog image.
    static var townPreviewTrack: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .townPreviewTrack)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

