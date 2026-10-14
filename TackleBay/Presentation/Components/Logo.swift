import SwiftUI

/// Outlined display text: navy outline drawn by offset copies, fill on top.
struct OutlinedText: View {
    let text: String
    let size: CGFloat
    var fill: AnyView
    var outline: Color = Color(hex: 0x0A3A63)
    var outlineWidth: CGFloat

    init<Fill: View>(_ text: String, size: CGFloat, outline: Color = Color(hex: 0x0A3A63), outlineWidth: CGFloat? = nil, @ViewBuilder fill: () -> Fill) {
        self.text = text
        self.size = size
        self.outline = outline
        self.outlineWidth = outlineWidth ?? max(1, size * 0.045)
        self.fill = AnyView(fill())
    }

    private var base: some View {
        Text(text).font(.system(size: size, weight: .black, design: .rounded)).kerning(-size * 0.02)
    }

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                base.foregroundColor(outline)
                    .offset(x: CGFloat(cos(angle)) * outlineWidth, y: CGFloat(sin(angle)) * outlineWidth)
            }
            base.foregroundColor(outline).offset(y: outlineWidth * 1.6)
            fill.mask(base)
        }
        .fixedSize()
    }
}

/// "Tackle Bay" wordmark drawn in code: white "Tackle", turquoise "Bay", sun, swoosh and gulls.
struct TackleBayLogo: View {
    var height: CGFloat = 64

    var body: some View {
        let size = height * 0.62
        ZStack(alignment: .topLeading) {
            // Sun rising behind the first letters, with a little wave across it.
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFD75E), Color(hex: 0xFFA22E)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.62, height: size * 0.62)
                WaveStroke()
                    .stroke(Color(hex: 0x3FD9E6), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .frame(width: size * 1.25, height: size * 0.16)
                    .offset(y: size * 0.12)
            }
            .frame(width: size * 1.3, height: size * 0.4, alignment: .top)
            .clipped()
            .offset(x: size * 0.95, y: 0)

            HStack(alignment: .firstTextBaseline, spacing: size * 0.04) {
                OutlinedText("Tackle", size: size) {
                    LinearGradient(colors: [.white, Color(hex: 0xEAF7FF)], startPoint: .top, endPoint: .bottom)
                }
                OutlinedText("Bay", size: size) {
                    LinearGradient(colors: [Color(hex: 0x8CF4FF), Color(hex: 0x21C3E2)], startPoint: .top, endPoint: .bottom)
                }
            }
            .offset(y: size * 0.22)

            Swoosh()
                .fill(LinearGradient(colors: [Color(hex: 0x2BD0E4), Color(hex: 0x56E6F0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 2.9, height: size * 0.32)
                .offset(x: size * 1.2, y: size * 1.33)
                .shadow(color: Color(hex: 0x0A3A63).opacity(0.35), radius: 0, x: 0, y: 1.5)

            Gulls()
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.2, size * 0.04), lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.9, height: size * 0.35)
                .offset(x: size * 4.75, y: size * 0.02)
        }
        .frame(width: size * 5.7, height: height * 1.12, alignment: .topLeading)
        .shadow(color: Color(hex: 0x063055).opacity(0.25), radius: 4, x: 0, y: 3)
        .accessibilityElement()
        .accessibilityLabel("Tackle Bay")
        .accessibilityAddTraits(.isHeader)
    }
}

struct WaveStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY),
                   control2: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.maxY))
        return p
    }
}

/// Two small seagull strokes.
struct Gulls: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func gull(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
            p.move(to: CGPoint(x: x, y: y + w * 0.1))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + w * 0.25), control: CGPoint(x: x + w * 0.25, y: y - w * 0.15))
            p.addQuadCurve(to: CGPoint(x: x + w, y: y + w * 0.05), control: CGPoint(x: x + w * 0.75, y: y - w * 0.15))
        }
        gull(rect.minX, rect.minY + rect.height * 0.15, rect.width * 0.48)
        gull(rect.minX + rect.width * 0.55, rect.minY + rect.height * 0.55, rect.width * 0.38)
        return p
    }
}

/// "Bay Bonus" title for the wooden sign.
struct BayBonusTitle: View {
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: -size * 0.12) {
            HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
                OutlinedText("Bay", size: size, outline: Color(hex: 0x3A1F0C)) {
                    LinearGradient(colors: [.white, Color(hex: 0xEFEFEF)], startPoint: .top, endPoint: .bottom)
                }
                OutlinedText("Bonus", size: size, outline: Color(hex: 0x063055)) {
                    LinearGradient(colors: [Color(hex: 0x8CF4FF), Color(hex: 0x1EC0E0)], startPoint: .top, endPoint: .bottom)
                }
            }
            Swoosh()
                .fill(Color(hex: 0x2BD0E4))
                .frame(width: size * 3.2, height: size * 0.3)
                .offset(x: size * 0.9)
        }
        .accessibilityElement()
        .accessibilityLabel("Bay Bonus")
        .accessibilityAddTraits(.isHeader)
    }
}
