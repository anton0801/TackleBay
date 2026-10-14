import SwiftUI
import UIKit

/// Header artwork that fills the hero and stretches when the list is pulled down.
struct StretchyHeaderImage: View {
    let name: String
    let height: CGFloat
    var alignment: Alignment = .bottom
    var overlay: LinearGradient?

    var body: some View {
        GeometryReader { geo in
            let pull = max(0, geo.frame(in: .global).minY)
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: height + pull, alignment: alignment)
                .clipped()
                .overlay(overlay)
                .offset(y: -pull)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Fills the proposed width × fixed height with a cropped image without ever widening its parent.
struct FillImage: View {
    let name: String
    let height: CGFloat
    var alignment: Alignment = .center

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(Image(name).resizable().scaledToFill(), alignment: alignment)
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Light rounded content sheet that overlaps the hero and runs to the bottom of the page.
struct PanelBackground: View {
    var color: Color = .tbPanel
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(color)
            .shadow(color: Color(hex: 0x0B4F6C).opacity(0.10), radius: 14, y: -2)
            .padding(.bottom, -2000)
            .onTapGesture { UIApplication.shared.endEditing() }
    }
}

extension UIApplication {
    /// Ends text editing anywhere in the app (tap on empty panel space).
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Common page: bay hero on top (drawn under the status bar), light panel with content below.
struct HeroScreen<Hero: View, Content: View>: View {
    var heroHeight: CGFloat
    var heroImage = "tb_bay_header"
    var heroAlignment: Alignment = .bottom
    var heroOverlay: LinearGradient?
    var overlap: CGFloat = Metrics.sheetOverlap
    var panelColor: Color = .tbPanel
    var contentTopPadding: CGFloat = 22
    let hero: Hero
    let content: Content
    @Environment(\.safeTop) private var safeTop
    @Environment(\.sizeCategory) private var sizeCategory

    /// Heroes carry titles, so they grow with Dynamic Type; the artwork stays pinned to the bottom edge.
    private var scaledHeroHeight: CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory.uiCategory)
        let factor = UIFontMetrics(forTextStyle: .body).scaledValue(for: 100, compatibleWith: traits) / 100
        guard factor > 1 else { return heroHeight }
        return heroHeight * min(1 + (factor - 1) * 0.7, 1.6)
    }

    init(heroHeight: CGFloat,
         heroImage: String = "tb_bay_header",
         heroAlignment: Alignment = .bottom,
         heroOverlay: LinearGradient? = nil,
         overlap: CGFloat = Metrics.sheetOverlap,
         panelColor: Color = .tbPanel,
         contentTopPadding: CGFloat = 22,
         @ViewBuilder hero: () -> Hero,
         @ViewBuilder content: () -> Content) {
        self.heroHeight = heroHeight
        self.heroImage = heroImage
        self.heroAlignment = heroAlignment
        self.heroOverlay = heroOverlay
        self.overlap = overlap
        self.panelColor = panelColor
        self.contentTopPadding = contentTopPadding
        self.hero = hero()
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    StretchyHeaderImage(name: heroImage, height: scaledHeroHeight + safeTop, alignment: heroAlignment, overlay: heroOverlay)
                    hero
                        .padding(.top, safeTop)
                        .frame(height: scaledHeroHeight + safeTop, alignment: .top)
                }
                .frame(height: scaledHeroHeight + safeTop)
                VStack(spacing: 0) { content }
                    .padding(.horizontal, Metrics.side)
                    .padding(.top, contentTopPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .background(PanelBackground(color: panelColor))
                    .padding(.top, -overlap)
            }
        }
        .background(Color.tbBackground.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Pinned bottom action area with a soft fade so scrolled content passes underneath.
struct BottomActionBar<Content: View>: View {
    var color: Color = .tbPanel
    let content: Content

    init(color: Color = .tbPanel, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) { content }
            .padding(.horizontal, Metrics.side)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(
                LinearGradient(colors: [color.opacity(0), color.opacity(0.94), color], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
                    .ignoresSafeArea(edges: .bottom)
            )
    }
}

/// Hero top row: leading control, optional centre, trailing control.
struct HeroTopBar<Leading: View, Center: View, Trailing: View>: View {
    let leading: Leading
    let center: Center
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder center: () -> Center, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            center
            HStack {
                leading
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .frame(minHeight: 56)
    }
}

struct PelicanKeeper: View {
    var height: CGFloat
    var body: some View {
        Image("tb_pelican_keeper").resizable().scaledToFit().frame(height: height).accessibilityHidden(true)
    }
}

struct PelicanPeek: View {
    var width: CGFloat
    var mirrored = false
    var body: some View {
        Image("tb_pelican_peek").resizable().scaledToFit().frame(width: width)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }
}

/// Generic empty / error state block with an illustration slot.
struct EmptyStateBlock<Art: View, Actions: View>: View {
    let title: String
    let message: String
    let art: Art
    let actions: Actions

    init(title: String, message: String, @ViewBuilder art: () -> Art, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.art = art()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 14) {
            art
            Text(title)
                .tbFont(30, .heavy, style: .title1, max: 44)
                .foregroundColor(.tbText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .tbFont(18, .regular)
                .foregroundColor(.tbText.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions.padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}
