import SwiftUI

// MARK: - Category glyphs (vector, drawn in code)

struct RodGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.1, y: r.minY + h * 0.92))
        p.addLine(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.1))
        // grip
        p.move(to: CGPoint(x: r.minX + w * 0.06, y: r.minY + h * 0.86))
        p.addLine(to: CGPoint(x: r.minX + w * 0.22, y: r.minY + h * 0.7))
        // reel
        p.addEllipse(in: CGRect(x: r.minX + w * 0.24, y: r.minY + h * 0.62, width: w * 0.16, height: h * 0.16))
        // line
        p.move(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.1))
        p.addLine(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.5))
        return p
    }
}

struct ReelGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: r.minX + w * 0.12, y: r.minY + h * 0.2, width: w * 0.56, height: h * 0.56))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.29, y: r.minY + h * 0.37, width: w * 0.22, height: h * 0.22))
        p.move(to: CGPoint(x: r.minX + w * 0.4, y: r.minY + h * 0.48))
        p.addLine(to: CGPoint(x: r.minX + w * 0.82, y: r.minY + h * 0.62))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.78, y: r.minY + h * 0.58, width: w * 0.14, height: h * 0.14))
        p.move(to: CGPoint(x: r.minX + w * 0.4, y: r.minY + h * 0.76))
        p.addLine(to: CGPoint(x: r.minX + w * 0.4, y: r.minY + h * 0.9))
        p.move(to: CGPoint(x: r.minX + w * 0.22, y: r.minY + h * 0.9))
        p.addLine(to: CGPoint(x: r.minX + w * 0.58, y: r.minY + h * 0.9))
        return p
    }
}

struct HookGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: r.minX + w * 0.5, y: r.minY + h * 0.04, width: w * 0.16, height: h * 0.14))
        p.move(to: CGPoint(x: r.minX + w * 0.58, y: r.minY + h * 0.18))
        p.addLine(to: CGPoint(x: r.minX + w * 0.58, y: r.minY + h * 0.66))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.2, y: r.minY + h * 0.6),
                   control1: CGPoint(x: r.minX + w * 0.58, y: r.minY + h * 0.98),
                   control2: CGPoint(x: r.minX + w * 0.2, y: r.minY + h * 0.92))
        p.addLine(to: CGPoint(x: r.minX + w * 0.32, y: r.minY + h * 0.68))
        return p
    }
}

struct LureGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: r.minX + w * 0.08, y: r.minY + h * 0.3, width: w * 0.62, height: h * 0.32))
        p.move(to: CGPoint(x: r.minX + w * 0.68, y: r.minY + h * 0.46))
        p.addLine(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.3))
        p.addLine(to: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.62))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: r.minX + w * 0.18, y: r.minY + h * 0.4, width: w * 0.07, height: h * 0.07))
        p.move(to: CGPoint(x: r.minX + w * 0.38, y: r.minY + h * 0.62))
        p.addLine(to: CGPoint(x: r.minX + w * 0.38, y: r.minY + h * 0.8))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.26, y: r.minY + h * 0.76), control: CGPoint(x: r.minX + w * 0.3, y: r.minY + h * 0.9))
        return p
    }
}

struct CategoryIcon: View {
    let category: GearCategory
    var size: CGFloat = 24
    var color: Color = .tbText

    var body: some View {
        Group {
            switch category {
            case .rods: RodGlyph().stroke(color, style: stroke)
            case .reels: ReelGlyph().stroke(color, style: stroke)
            case .terminalTackle: HookGlyph().stroke(color, style: stroke)
            case .lures: LureGlyph().stroke(color, style: stroke)
            case .tools: Image(systemName: "wrench.and.screwdriver.fill").resizable().scaledToFit().foregroundColor(color)
            case .clothing: Image(systemName: "tshirt.fill").resizable().scaledToFit().foregroundColor(color)
            case .containers: Image(systemName: "briefcase.fill").resizable().scaledToFit().foregroundColor(color)
            case .supplies: Image(systemName: "bag.fill").resizable().scaledToFit().foregroundColor(color)
            case .other: Image(systemName: "square.grid.2x2.fill").resizable().scaledToFit().foregroundColor(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: max(1.6, size * 0.085), lineCap: .round, lineJoin: .round)
    }
}

// MARK: - Gear photo / artwork tile

/// Real photo first, sample artwork for Sample Collection, otherwise the category symbol.
struct GearImage: View {
    let gear: Gear?
    var category: GearCategory = .other
    var width: CGFloat
    var height: CGFloat? = nil
    var corner: CGFloat = 14
    var thumbnail = true
    var fill = false
    /// Sample artwork shown on a dock scene (list rows), like the illustrative examples in the mockups.
    var scenic = false
    @EnvironmentObject private var services: AppServices

    var body: some View {
        let h = height ?? width
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xEEF9FC), Color(hex: 0xD9F0F7)], startPoint: .top, endPoint: .bottom))
            content(h: h)
        }
        .frame(width: width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(h: CGFloat) -> some View {
        if let gear = gear, let pid = gear.photoID, let ref = services.store.db.photos[pid],
           let image = services.store.photos.image(ref, thumbnail: thumbnail) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: width, height: h).clipped()
        } else if let gear = gear, let art = gear.sampleArt {
            if scenic {
                ZStack {
                    Image("tb_bay_header").resizable().scaledToFill()
                        .frame(width: width, height: h, alignment: .bottom).clipped()
                    Image(art).resizable().scaledToFit().padding(min(width, h) * 0.06)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                }
            } else {
                Image(art).resizable().scaledToFit().padding(min(width, h) * 0.08)
            }
        } else {
            CategoryIcon(category: gear?.category ?? category, size: min(width, h) * 0.46, color: Color(hex: 0x1A6E92))
        }
    }
}

/// Small check badge in the corner of packed thumbnails.
struct CheckBadge: View {
    var size: CGFloat = 24
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.tbTeal))
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
    }
}
