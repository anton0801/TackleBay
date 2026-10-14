import SwiftUI

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var radius: CGFloat = Metrics.cardRadius
    var fill: Color = .white
    var padding: CGFloat? = 12

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .shadow(color: Color(hex: 0x0B4F6C).opacity(0.07), radius: 12, x: 0, y: 5)
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
    }
}

extension View {
    func tbCard(radius: CGFloat = Metrics.cardRadius, fill: Color = .white, padding: CGFloat? = 12) -> some View {
        modifier(CardBackground(radius: radius, fill: fill, padding: padding))
    }
}

/// Rounded icon badge (calendar, toolbox, wrench...).
struct IconTile: View {
    let systemName: String
    var tint: Color = .tbTeal
    var background: Color = .tbIceTile
    var size: CGFloat = 40
    var circle = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(
                Group {
                    if circle { Circle().fill(background) } else { RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(background) }
                }
            )
            .accessibilityHidden(true)
    }
}

struct TBProgressBar: View {
    let fraction: Double
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.tbTrack)
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x37D5DE), Color(hex: 0x14B2C4)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fraction > 0 ? height : 0, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Quantity stepper

/// − value + control. The value can also be typed for exact input.
struct QuantityStepper: View {
    @Binding var value: Int?
    var range: ClosedRange<Int>
    var size: CGFloat = 52
    var allowsTyping = true
    var placeholder = "0"
    var accessibilityName: String = "Quantity"
    var onStep: (() -> Void)?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: (value ?? 0) > range.lowerBound) {
                value = max(range.lowerBound, (value ?? range.lowerBound + 1) - 1)
            }
            Group {
                if allowsTyping {
                    TextField(placeholder, text: $text)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .multilineTextAlignment(.center)
                        .onChange(of: text) { new in
                            let digits = String(new.filter(\.isNumber).prefix(4))
                            if digits != new { text = digits; return }
                            value = digits.isEmpty ? nil : Int(digits)
                        }
                } else {
                    Text(value.map(String.init) ?? placeholder)
                }
            }
            .tbFont(size * 0.55, .bold, design: .rounded)
            .foregroundColor(.tbText)
            .frame(minWidth: size * 0.9)
            .frame(maxWidth: .infinity)
            stepButton("plus", enabled: (value ?? range.lowerBound - 1) < range.upperBound) {
                value = min(range.upperBound, (value ?? range.lowerBound - 1) + 1)
            }
        }
        .padding(.horizontal, 2)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().strokeBorder(Color.tbCardBorder, lineWidth: 1))
        .onAppear { text = value.map(String.init) ?? "" }
        .onChange(of: value) { new in
            let s = new.map(String.init) ?? ""
            if s != text { text = s }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(value.map(String.init) ?? "empty")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, (value ?? range.lowerBound - 1) + 1)
            case .decrement: value = max(range.lowerBound, (value ?? range.lowerBound + 1) - 1)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onStep?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(enabled ? (icon == "plus" ? Color(hex: 0x14A6B8) : .tbText) : .tbDisabledText)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.tbIceTile))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// Non-optional convenience wrapper.
struct IntStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var size: CGFloat = 44
    var allowsTyping = true
    var accessibilityName = "Quantity"
    var onStep: (() -> Void)?

    var body: some View {
        QuantityStepper(value: Binding(get: { value }, set: { value = min(max($0 ?? range.lowerBound, range.lowerBound), range.upperBound) }),
                        range: range, size: size, allowsTyping: allowsTyping, accessibilityName: accessibilityName, onStep: onStep)
    }
}

// MARK: - Text input

struct TBTextField: View {
    let label: String?
    @Binding var text: String
    var placeholder: String = ""
    var error: String?
    var limit: Int?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = label {
                Text(label.uppercased())
                    .tracking(0.6)
                    .tbFont(11, .semibold, style: .caption1)
                    .foregroundColor(.tbSecondary)
            }
            TextField(placeholder, text: $text)
                .tbFont(17, .semibold)
                .foregroundColor(.tbText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
                    .strokeBorder(error == nil ? Color.tbBorder : Color.tbError, lineWidth: error == nil ? 1.2 : 1.8))
                .onChange(of: text) { new in
                    if let limit = limit, new.count > limit { text = String(new.prefix(limit)) }
                }
                .accessibilityLabel(label ?? placeholder)
            if let error = error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .tbFont(14, .medium, style: .footnote)
                    .foregroundColor(.tbError)
            }
        }
    }
}

/// Multi-line note input (iOS 15 compatible).
struct TBTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 96
    var limit: Int
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .tbFont(16, .regular, design: .rounded)
                    .foregroundColor(.tbText)
                    .frame(minHeight: minHeight)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .onAppear { UITextView.appearance().backgroundColor = .clear }
                    .onChange(of: text) { new in if new.count > limit { text = String(new.prefix(limit)) } }
                if text.isEmpty {
                    Text(placeholder)
                        .tbFont(16, .regular, design: .rounded)
                        .foregroundColor(.tbSecondary.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
                .strokeBorder(error == nil ? Color.tbBorder : Color.tbError, lineWidth: error == nil ? 1.2 : 1.8))
            HStack {
                if let error = error {
                    Text(error).tbFont(14, .medium, style: .footnote).foregroundColor(.tbError)
                }
                Spacer()
                Text("\(text.count)/\(limit)").tbFont(13, style: .caption2).foregroundColor(.tbSecondary)
            }
        }
    }
}

// MARK: - Selection

struct TBSegmented<T: Hashable>: View {
    let options: [(T, String, String?)]
    @Binding var selection: T
    var height: CGFloat = 42

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option in
                let selected = option.0 == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option.0 }
                } label: {
                    HStack(spacing: 7) {
                        if let icon = option.2 { Image.symbol(icon, fallback: "drop.fill").font(.system(size: 16, weight: .semibold)) }
                        Text(option.1).tbFont(15, .bold).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .foregroundColor(selected ? .white : .tbText)
                    .frame(maxWidth: .infinity, minHeight: height - 6)
                    .background(Capsule().fill(selected ? Color.tbTeal : Color.clear))
                    .shadow(color: selected ? Color.tbTeal.opacity(0.35) : .clear, radius: 5, y: 2)
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.85)))
        .overlay(Capsule().strokeBorder(Color.tbCardBorder, lineWidth: 1))
    }
}

struct ChipButton: View {
    let title: String
    var icon: AnyView?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon = icon { icon.frame(width: 20, height: 20) }
                Text(title).tbFont(14, .semibold).lineLimit(1)
            }
            .foregroundColor(selected ? .white : .tbText)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(selected ? Color.tbTeal : Color.white))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.tbCardBorder, lineWidth: 1))
            .frame(minHeight: 44)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Notices

struct InfoBanner: View {
    enum Kind { case info, warning, error, success }
    let text: String
    var detail: String?
    var kind: Kind = .info

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: detail == nil ? 20 : 26, weight: .semibold))
                .foregroundColor(iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(text).tbFont(detail == nil ? 14 : 16, detail == nil ? .medium : .bold).foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail {
                    Text(detail).tbFont(13, .regular).foregroundColor(textColor.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .info: return Color(hex: 0x1580C4)
        case .warning: return Color(hex: 0xF08A18)
        case .error: return .tbError
        case .success: return .tbReady
        }
    }

    private var textColor: Color {
        switch kind {
        case .info: return Color(hex: 0x16507A)
        case .warning: return .tbCare
        case .error: return .tbError
        case .success: return .tbReady
        }
    }

    private var background: Color {
        switch kind {
        case .info: return Color(hex: 0xDDF2F9)
        case .warning: return .tbCareBackground
        case .error: return .tbErrorSoft
        case .success: return .tbGreenSoft
        }
    }

    private var border: Color {
        switch kind {
        case .info: return Color(hex: 0xC9E8F3)
        case .warning: return Color(hex: 0xF7DE9B)
        case .error: return Color(hex: 0xF5C9C9)
        case .success: return Color(hex: 0xBFE6D4)
        }
    }
}

struct SectionTitle: View {
    let text: String
    var size: CGFloat = 20

    var body: some View {
        Text(text)
            .tbFont(size, .heavy, style: .title2)
            .foregroundColor(.tbText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text).tbFont(15, .bold).foregroundColor(.tbText).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wavy turquoise underline used under display titles.
struct Swoosh: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.15))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.05),
                       control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.15),
                       control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.55))
        return p
    }
}
