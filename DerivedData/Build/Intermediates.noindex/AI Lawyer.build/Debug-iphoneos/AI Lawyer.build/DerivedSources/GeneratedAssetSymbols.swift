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

    /// The "AppAccentPrimary" asset catalog color resource.
    static let appAccentPrimary = DeveloperToolsSupport.ColorResource(name: "AppAccentPrimary", bundle: resourceBundle)

    /// The "AppAccentSecondary" asset catalog color resource.
    static let appAccentSecondary = DeveloperToolsSupport.ColorResource(name: "AppAccentSecondary", bundle: resourceBundle)

    /// The "AppBackground" asset catalog color resource.
    static let appBackground = DeveloperToolsSupport.ColorResource(name: "AppBackground", bundle: resourceBundle)

    /// The "AppCard" asset catalog color resource.
    static let appCard = DeveloperToolsSupport.ColorResource(name: "AppCard", bundle: resourceBundle)

    /// The "AppCardStroke" asset catalog color resource.
    static let appCardStroke = DeveloperToolsSupport.ColorResource(name: "AppCardStroke", bundle: resourceBundle)

    /// The "AppDepth" asset catalog color resource.
    static let appDepth = DeveloperToolsSupport.ColorResource(name: "AppDepth", bundle: resourceBundle)

    /// The "AppSecondaryButton" asset catalog color resource.
    static let appSecondaryButton = DeveloperToolsSupport.ColorResource(name: "AppSecondaryButton", bundle: resourceBundle)

    /// The "AppTextPrimary" asset catalog color resource.
    static let appTextPrimary = DeveloperToolsSupport.ColorResource(name: "AppTextPrimary", bundle: resourceBundle)

    /// The "AppTextSecondary" asset catalog color resource.
    static let appTextSecondary = DeveloperToolsSupport.ColorResource(name: "AppTextSecondary", bundle: resourceBundle)

    /// The "BackgroundNavy" asset catalog color resource.
    static let backgroundNavy = DeveloperToolsSupport.ColorResource(name: "BackgroundNavy", bundle: resourceBundle)

    /// The "GoldAccent" asset catalog color resource.
    static let goldAccent = DeveloperToolsSupport.ColorResource(name: "GoldAccent", bundle: resourceBundle)

    /// The "SidebarHeadingBlue" asset catalog color resource.
    static let sidebarHeadingBlue = DeveloperToolsSupport.ColorResource(name: "SidebarHeadingBlue", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "PocketLawLogo" asset catalog image resource.
    static let pocketLawLogo = DeveloperToolsSupport.ImageResource(name: "PocketLawLogo", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "AppAccentPrimary" asset catalog color.
    static var appAccentPrimary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appAccentPrimary)
#else
        .init()
#endif
    }

    /// The "AppAccentSecondary" asset catalog color.
    static var appAccentSecondary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appAccentSecondary)
#else
        .init()
#endif
    }

    /// The "AppBackground" asset catalog color.
    static var appBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appBackground)
#else
        .init()
#endif
    }

    /// The "AppCard" asset catalog color.
    static var appCard: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appCard)
#else
        .init()
#endif
    }

    /// The "AppCardStroke" asset catalog color.
    static var appCardStroke: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appCardStroke)
#else
        .init()
#endif
    }

    /// The "AppDepth" asset catalog color.
    static var appDepth: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appDepth)
#else
        .init()
#endif
    }

    /// The "AppSecondaryButton" asset catalog color.
    static var appSecondaryButton: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appSecondaryButton)
#else
        .init()
#endif
    }

    /// The "AppTextPrimary" asset catalog color.
    static var appTextPrimary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appTextPrimary)
#else
        .init()
#endif
    }

    /// The "AppTextSecondary" asset catalog color.
    static var appTextSecondary: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appTextSecondary)
#else
        .init()
#endif
    }

    /// The "BackgroundNavy" asset catalog color.
    static var backgroundNavy: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .backgroundNavy)
#else
        .init()
#endif
    }

    /// The "GoldAccent" asset catalog color.
    static var goldAccent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .goldAccent)
#else
        .init()
#endif
    }

    /// The "SidebarHeadingBlue" asset catalog color.
    static var sidebarHeadingBlue: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .sidebarHeadingBlue)
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

    /// The "AppAccentPrimary" asset catalog color.
    static var appAccentPrimary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appAccentPrimary)
#else
        .init()
#endif
    }

    /// The "AppAccentSecondary" asset catalog color.
    static var appAccentSecondary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appAccentSecondary)
#else
        .init()
#endif
    }

    /// The "AppBackground" asset catalog color.
    static var appBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appBackground)
#else
        .init()
#endif
    }

    /// The "AppCard" asset catalog color.
    static var appCard: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appCard)
#else
        .init()
#endif
    }

    /// The "AppCardStroke" asset catalog color.
    static var appCardStroke: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appCardStroke)
#else
        .init()
#endif
    }

    /// The "AppDepth" asset catalog color.
    static var appDepth: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appDepth)
#else
        .init()
#endif
    }

    /// The "AppSecondaryButton" asset catalog color.
    static var appSecondaryButton: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appSecondaryButton)
#else
        .init()
#endif
    }

    /// The "AppTextPrimary" asset catalog color.
    static var appTextPrimary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appTextPrimary)
#else
        .init()
#endif
    }

    /// The "AppTextSecondary" asset catalog color.
    static var appTextSecondary: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .appTextSecondary)
#else
        .init()
#endif
    }

    /// The "BackgroundNavy" asset catalog color.
    static var backgroundNavy: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .backgroundNavy)
#else
        .init()
#endif
    }

    /// The "GoldAccent" asset catalog color.
    static var goldAccent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .goldAccent)
#else
        .init()
#endif
    }

    /// The "SidebarHeadingBlue" asset catalog color.
    static var sidebarHeadingBlue: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .sidebarHeadingBlue)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "AppAccentPrimary" asset catalog color.
    static var appAccentPrimary: SwiftUI.Color { .init(.appAccentPrimary) }

    /// The "AppAccentSecondary" asset catalog color.
    static var appAccentSecondary: SwiftUI.Color { .init(.appAccentSecondary) }

    /// The "AppBackground" asset catalog color.
    static var appBackground: SwiftUI.Color { .init(.appBackground) }

    /// The "AppCard" asset catalog color.
    static var appCard: SwiftUI.Color { .init(.appCard) }

    /// The "AppCardStroke" asset catalog color.
    static var appCardStroke: SwiftUI.Color { .init(.appCardStroke) }

    /// The "AppDepth" asset catalog color.
    static var appDepth: SwiftUI.Color { .init(.appDepth) }

    /// The "AppSecondaryButton" asset catalog color.
    static var appSecondaryButton: SwiftUI.Color { .init(.appSecondaryButton) }

    /// The "AppTextPrimary" asset catalog color.
    static var appTextPrimary: SwiftUI.Color { .init(.appTextPrimary) }

    /// The "AppTextSecondary" asset catalog color.
    static var appTextSecondary: SwiftUI.Color { .init(.appTextSecondary) }

    /// The "BackgroundNavy" asset catalog color.
    static var backgroundNavy: SwiftUI.Color { .init(.backgroundNavy) }

    /// The "GoldAccent" asset catalog color.
    static var goldAccent: SwiftUI.Color { .init(.goldAccent) }

    /// The "SidebarHeadingBlue" asset catalog color.
    static var sidebarHeadingBlue: SwiftUI.Color { .init(.sidebarHeadingBlue) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "AppAccentPrimary" asset catalog color.
    static var appAccentPrimary: SwiftUI.Color { .init(.appAccentPrimary) }

    /// The "AppAccentSecondary" asset catalog color.
    static var appAccentSecondary: SwiftUI.Color { .init(.appAccentSecondary) }

    /// The "AppBackground" asset catalog color.
    static var appBackground: SwiftUI.Color { .init(.appBackground) }

    /// The "AppCard" asset catalog color.
    static var appCard: SwiftUI.Color { .init(.appCard) }

    /// The "AppCardStroke" asset catalog color.
    static var appCardStroke: SwiftUI.Color { .init(.appCardStroke) }

    /// The "AppDepth" asset catalog color.
    static var appDepth: SwiftUI.Color { .init(.appDepth) }

    /// The "AppSecondaryButton" asset catalog color.
    static var appSecondaryButton: SwiftUI.Color { .init(.appSecondaryButton) }

    /// The "AppTextPrimary" asset catalog color.
    static var appTextPrimary: SwiftUI.Color { .init(.appTextPrimary) }

    /// The "AppTextSecondary" asset catalog color.
    static var appTextSecondary: SwiftUI.Color { .init(.appTextSecondary) }

    /// The "BackgroundNavy" asset catalog color.
    static var backgroundNavy: SwiftUI.Color { .init(.backgroundNavy) }

    /// The "GoldAccent" asset catalog color.
    static var goldAccent: SwiftUI.Color { .init(.goldAccent) }

    /// The "SidebarHeadingBlue" asset catalog color.
    static var sidebarHeadingBlue: SwiftUI.Color { .init(.sidebarHeadingBlue) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "PocketLawLogo" asset catalog image.
    static var pocketLawLogo: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pocketLawLogo)
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

    /// The "PocketLawLogo" asset catalog image.
    static var pocketLawLogo: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pocketLawLogo)
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

