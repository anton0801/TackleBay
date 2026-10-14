import SwiftUI

/// Gold enamel CTA with dark text (primary action).
struct GoldButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tbFont(compact ? 15 : 18, .bold)
            .foregroundColor(isEnabled ? .tbText : .tbDisabledText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, compact ? 12 : 20)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                ZStack {
                    if isEnabled {
                        Capsule().fill(LinearGradient(colors: [.tbGoldTop, .tbGoldBottom], startPoint: .top, endPoint: .bottom))
                        Capsule()
                            .fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)], startPoint: .top, endPoint: .center))
                            .padding(.horizontal, 10)
                            .padding(.top, 2)
                            .padding(.bottom, height * 0.45)
                        Capsule().strokeBorder(Color.tbGoldEdge, lineWidth: 1.5)
                    } else {
                        Capsule().fill(Color.tbDisabled)
                    }
                }
            )
            .shadow(color: isEnabled ? Color.tbGoldShadow.opacity(configuration.isPressed ? 0.15 : 0.32) : .clear,
                    radius: configuration.isPressed ? 3 : 8, x: 0, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// White button with a turquoise outline (secondary action).
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var tint: Color = .tbTeal
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tbFont(compact ? 15 : 17, .bold)
            .foregroundColor(isEnabled ? .tbText : .tbDisabledText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, compact ? 10 : 18)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().strokeBorder(isEnabled ? tint.opacity(0.75) : Color.tbDisabled, lineWidth: 1.6))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Pale ice-blue button (Keep packing, Cancel, Back).
struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    var foreground: Color = .tbText
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tbFont(17, .bold)
            .foregroundColor(isEnabled ? foreground : .tbDisabledText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(Color.tbIceTile.opacity(configuration.isPressed ? 1 : 0.85)))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Deep navy capsule (Back to bonus, bonus links).
struct NavyButtonStyle: ButtonStyle {
    var height: CGFloat = Metrics.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tbFont(18, .bold)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: height)
            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x0B4C82), .tbNavy], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Color.tbNavy.opacity(0.35), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Label used inside the big buttons: optional leading icon, title, optional trailing chevron.
struct ButtonLabel: View {
    let title: String
    var icon: String?
    var iconStyle: IconStyle = .plain
    var chevron = false

    enum IconStyle { case plain, navyCircle }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                switch iconStyle {
                case .plain:
                    Image(systemName: icon).font(.system(size: 17, weight: .bold))
                case .navyCircle:
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.tbGoldTop)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.tbText))
                }
            }
            Text(title)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy))
            }
        }
    }
}

/// Round 44 pt icon button used in heroes.
struct CircleIconButton: View {
    enum Style { case light, navy, glass }
    let systemName: String
    var style: Style = .light
    var size: CGFloat = 40
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(style == .light ? .tbText : .white)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(background)
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(style == .light ? 0.9 : 0.15), lineWidth: 1))
                .shadow(color: Color.tbNavy.opacity(0.18), radius: 6, y: 3)
        }
        .buttonStyle(PressableStyle())
        .frame(minWidth: Metrics.minHit, minHeight: Metrics.minHit)
        .accessibilityLabel(label)
    }

    private var background: Color {
        switch style {
        case .light: return Color.white.opacity(0.92)
        case .navy: return .tbNavy
        case .glass: return Color.tbNavy.opacity(0.55)
        }
    }
}

/// Small gold "Save" pill used in editor heroes.
struct GoldPillButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .tbFont(16, .bold)
                .foregroundColor(isEnabled ? .tbText : .tbDisabledText)
                .padding(.horizontal, 18)
                .frame(minHeight: 38)
                .background(
                    Capsule().fill(isEnabled
                                   ? AnyShapeStyleBox.gold
                                   : AnyShapeStyleBox.disabled)
                )
                .overlay(Capsule().strokeBorder(isEnabled ? Color.tbGoldEdge : .clear, lineWidth: 1.2))
                .shadow(color: Color.tbGoldShadow.opacity(isEnabled ? 0.3 : 0), radius: 6, y: 3)
        }
        .buttonStyle(PressableStyle())
        .frame(minHeight: 44)
    }
}

enum AnyShapeStyleBox {
    static let gold = LinearGradient(colors: [.tbGoldTop, .tbGoldBottom], startPoint: .top, endPoint: .bottom)
    static let disabled = LinearGradient(colors: [.tbDisabled, .tbDisabled], startPoint: .top, endPoint: .bottom)
}

/// "‹ Cancel" / "‹ Back" text-pill in heroes.
struct HeroTextButton: View {
    let title: String
    var showChevron = true
    var pill = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showChevron { Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)) }
                Text(title).tbFont(16, .semibold)
            }
            .foregroundColor(.tbText)
            .padding(.horizontal, pill ? 14 : 4)
            .frame(minHeight: 36)
            .background(Capsule().fill(pill ? Color.white.opacity(0.88) : .clear))
        }
        .buttonStyle(PressableStyle())
        .frame(minHeight: 44)
    }
}
