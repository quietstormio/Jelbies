#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"io.mgsllc.BobV1";

/// The "LaunchBackground" asset catalog color resource.
static NSString * const ACColorNameLaunchBackground AC_SWIFT_PRIVATE = @"LaunchBackground";

/// The "JelbiesLogo" asset catalog image resource.
static NSString * const ACImageNameJelbiesLogo AC_SWIFT_PRIVATE = @"JelbiesLogo";

/// The "room_thumb_cabin" asset catalog image resource.
static NSString * const ACImageNameRoomThumbCabin AC_SWIFT_PRIVATE = @"room_thumb_cabin";

/// The "room_thumb_home" asset catalog image resource.
static NSString * const ACImageNameRoomThumbHome AC_SWIFT_PRIVATE = @"room_thumb_home";

/// The "room_thumb_loft" asset catalog image resource.
static NSString * const ACImageNameRoomThumbLoft AC_SWIFT_PRIVATE = @"room_thumb_loft";

/// The "town_preview_adopt" asset catalog image resource.
static NSString * const ACImageNameTownPreviewAdopt AC_SWIFT_PRIVATE = @"town_preview_adopt";

/// The "town_preview_beach" asset catalog image resource.
static NSString * const ACImageNameTownPreviewBeach AC_SWIFT_PRIVATE = @"town_preview_beach";

/// The "town_preview_cafe" asset catalog image resource.
static NSString * const ACImageNameTownPreviewCafe AC_SWIFT_PRIVATE = @"town_preview_cafe";

/// The "town_preview_friends" asset catalog image resource.
static NSString * const ACImageNameTownPreviewFriends AC_SWIFT_PRIVATE = @"town_preview_friends";

/// The "town_preview_groom" asset catalog image resource.
static NSString * const ACImageNameTownPreviewGroom AC_SWIFT_PRIVATE = @"town_preview_groom";

/// The "town_preview_park" asset catalog image resource.
static NSString * const ACImageNameTownPreviewPark AC_SWIFT_PRIVATE = @"town_preview_park";

/// The "town_preview_shop" asset catalog image resource.
static NSString * const ACImageNameTownPreviewShop AC_SWIFT_PRIVATE = @"town_preview_shop";

/// The "town_preview_studio" asset catalog image resource.
static NSString * const ACImageNameTownPreviewStudio AC_SWIFT_PRIVATE = @"town_preview_studio";

/// The "town_preview_track" asset catalog image resource.
static NSString * const ACImageNameTownPreviewTrack AC_SWIFT_PRIVATE = @"town_preview_track";

#undef AC_SWIFT_PRIVATE
