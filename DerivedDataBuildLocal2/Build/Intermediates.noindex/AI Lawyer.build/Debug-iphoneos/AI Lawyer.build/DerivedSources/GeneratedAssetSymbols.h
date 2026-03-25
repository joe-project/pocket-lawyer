#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"Orga-Inc..AI-Lawyer";

/// The "AppAccentPrimary" asset catalog color resource.
static NSString * const ACColorNameAppAccentPrimary AC_SWIFT_PRIVATE = @"AppAccentPrimary";

/// The "AppAccentSecondary" asset catalog color resource.
static NSString * const ACColorNameAppAccentSecondary AC_SWIFT_PRIVATE = @"AppAccentSecondary";

/// The "AppBackground" asset catalog color resource.
static NSString * const ACColorNameAppBackground AC_SWIFT_PRIVATE = @"AppBackground";

/// The "AppCard" asset catalog color resource.
static NSString * const ACColorNameAppCard AC_SWIFT_PRIVATE = @"AppCard";

/// The "AppCardStroke" asset catalog color resource.
static NSString * const ACColorNameAppCardStroke AC_SWIFT_PRIVATE = @"AppCardStroke";

/// The "AppDepth" asset catalog color resource.
static NSString * const ACColorNameAppDepth AC_SWIFT_PRIVATE = @"AppDepth";

/// The "AppSecondaryButton" asset catalog color resource.
static NSString * const ACColorNameAppSecondaryButton AC_SWIFT_PRIVATE = @"AppSecondaryButton";

/// The "AppTextPrimary" asset catalog color resource.
static NSString * const ACColorNameAppTextPrimary AC_SWIFT_PRIVATE = @"AppTextPrimary";

/// The "AppTextSecondary" asset catalog color resource.
static NSString * const ACColorNameAppTextSecondary AC_SWIFT_PRIVATE = @"AppTextSecondary";

/// The "BackgroundNavy" asset catalog color resource.
static NSString * const ACColorNameBackgroundNavy AC_SWIFT_PRIVATE = @"BackgroundNavy";

/// The "GoldAccent" asset catalog color resource.
static NSString * const ACColorNameGoldAccent AC_SWIFT_PRIVATE = @"GoldAccent";

/// The "SidebarHeadingBlue" asset catalog color resource.
static NSString * const ACColorNameSidebarHeadingBlue AC_SWIFT_PRIVATE = @"SidebarHeadingBlue";

/// The "AppLogo" asset catalog image resource.
static NSString * const ACImageNameAppLogo AC_SWIFT_PRIVATE = @"AppLogo";

/// The "PocketLawLogo" asset catalog image resource.
static NSString * const ACImageNamePocketLawLogo AC_SWIFT_PRIVATE = @"PocketLawLogo";

#undef AC_SWIFT_PRIVATE
