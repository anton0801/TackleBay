import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    // Palette from the specification / design_tokens.json
    static let tbBackground = Color(hex: 0xEAF8FB)
    static let tbSurface = Color.white
    static let tbText = Color(hex: 0x12344B)
    static let tbSecondary = Color(hex: 0x526E80)
    static let tbNavy = Color(hex: 0x073D68)
    static let tbBlue = Color(hex: 0x008DCE)
    static let tbTurquoise = Color(hex: 0x25C9D5)
    static let tbGold = Color(hex: 0xFFC94A)
    static let tbGoldShadow = Color(hex: 0xC9881A)
    static let tbWood = Color(hex: 0x945227)
    static let tbCoral = Color(hex: 0xFF7449)
    static let tbReady = Color(hex: 0x187455)
    static let tbCare = Color(hex: 0x8B570D)
    static let tbCareBackground = Color(hex: 0xFFF0CA)
    static let tbError = Color(hex: 0xB93436)
    static let tbBorder = Color(hex: 0xC7DEE7)
    static let tbBonusText = Color(hex: 0xF4FCFF)
    static let tbBonusSecondary = Color(hex: 0xBDD8E8)

    // Derived UI tones used across the mockups
    static let tbTeal = Color(hex: 0x16AFC0)          // selected segment / check fill
    static let tbTealDeep = Color(hex: 0x0E93A3)
    static let tbIceTile = Color(hex: 0xDDF3F8)       // icon tiles, soft buttons
    static let tbIceField = Color(hex: 0xF4FBFD)      // fields
    static let tbPanel = Color(hex: 0xF7FCFE)         // content sheet
    static let tbCardBorder = Color(hex: 0xE2F0F5)
    static let tbTrack = Color(hex: 0xE1EFF4)
    static let tbTabActive = Color(hex: 0x1C6FD1)
    static let tbTabIdle = Color(hex: 0x5B7486)
    static let tbCoralSoft = Color(hex: 0xFFE8E0)
    static let tbGreenSoft = Color(hex: 0xDDF4EA)
    static let tbErrorSoft = Color(hex: 0xFDECEC)
    static let tbDisabled = Color(hex: 0xD3DCE1)
    static let tbDisabledText = Color(hex: 0x8C9EAA)
    static let tbGoldTop = Color(hex: 0xFFDB57)
    static let tbGoldBottom = Color(hex: 0xFFC131)
    static let tbGoldEdge = Color(hex: 0xE6AC26)
}

/// Fonts scale with Dynamic Type. Headings use the rounded system design.
struct TBFontModifier: ViewModifier {
    @Environment(\.sizeCategory) private var sizeCategory
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let textStyle: UIFont.TextStyle
    let maxSize: CGFloat?

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory.uiCategory)
        var scaled = UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size, compatibleWith: traits)
        if let maxSize = maxSize { scaled = min(scaled, maxSize) }
        return content.font(.system(size: scaled, weight: weight, design: design))
    }
}

extension View {
    func tbFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .rounded,
                style: UIFont.TextStyle = .body, max: CGFloat? = nil) -> some View {
        modifier(TBFontModifier(size: size, weight: weight, design: design, textStyle: style, maxSize: max))
    }

    /// Big rounded display heading (screen titles over the bay).
    func tbDisplay(_ size: CGFloat = 34) -> some View {
        tbFont(size, .heavy, style: .largeTitle, max: size * 1.6)
    }
}

extension ContentSizeCategory {
    var uiCategory: UIContentSizeCategory {
        switch self {
        case .extraSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .extraLarge
        case .extraExtraLarge: return .extraExtraLarge
        case .extraExtraExtraLarge: return .extraExtraExtraLarge
        case .accessibilityMedium: return .accessibilityMedium
        case .accessibilityLarge: return .accessibilityLarge
        case .accessibilityExtraLarge: return .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: return .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

enum Metrics {
    static let side: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let fieldRadius: CGFloat = 14
    static let buttonHeight: CGFloat = 56
    static let minHit: CGFloat = 44
    static let sheetOverlap: CGFloat = 28
}

/// Environment value with the top safe-area inset, used by heroes that draw under the status bar.
private struct SafeTopKey: EnvironmentKey { static let defaultValue: CGFloat = 47 }
private struct SafeBottomKey: EnvironmentKey { static let defaultValue: CGFloat = 34 }

extension EnvironmentValues {
    var safeTop: CGFloat {
        get { self[SafeTopKey.self] }
        set { self[SafeTopKey.self] = newValue }
    }

    var safeBottom: CGFloat {
        get { self[SafeBottomKey.self] }
        set { self[SafeBottomKey.self] = newValue }
    }
}

extension Image {
    /// SF Symbol with a fallback for names that don't exist on older systems.
    static func symbol(_ name: String, fallback: String) -> Image {
        UIImage(systemName: name) != nil ? Image(systemName: name) : Image(systemName: fallback)
    }
}
