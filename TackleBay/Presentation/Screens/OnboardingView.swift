import SwiftUI

/// Three illustrated pages. No permissions, no demo records, no automatic ticket.
struct OnboardingView: View {
    let isReplay: Bool
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var ui: AppUI
    @State private var page = 0
    @State private var forward = true
    @Environment(\.safeTop) private var safeTop
    @Environment(\.safeBottom) private var safeBottom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.tbNavy.ignoresSafeArea()
            Group {
                switch page {
                case 0: pageOne
                case 1: pageTwo
                default: pageThree
                }
            }
            .id(page)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                                              removal: .move(edge: forward ? .leading : .trailing)))
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -60 && page < 2 { next() }
                    if value.translation.width > 60 && page > 0 { back() }
                }
        )
    }

    private func finish() {
        services.tapFeedback()
        if isReplay {
            withAnimation(.easeOut(duration: 0.2)) { ui.replayingOnboarding = false }
        } else {
            ui.run { try store.perform { db, _ in db.settings.onboardingCompleted = true } }
        }
    }

    private func next() {
        services.tapFeedback()
        forward = true
        withAnimation(.easeInOut(duration: 0.22)) { page = min(page + 1, 2) }
    }

    private func back() {
        forward = false
        withAnimation(.easeInOut(duration: 0.22)) { page = max(page - 1, 0) }
    }

    // MARK: Page 1 — Your Tackle

    private var pageOne: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Image("tb_onboarding_tackle")
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [Color(hex: 0x063A6B, opacity: 0), Color(hex: 0x0A4C86, opacity: 0.55), Color(hex: 0x062F5C, opacity: 0.92)],
                               startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Skip", action: finish)
                            .tbFont(16, .bold)
                            .foregroundColor(.tbText)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 38)
                            .background(Capsule().fill(Color.white.opacity(0.88)))
                            .buttonStyle(PressableStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, safeTop + 8)
                    Spacer()
                    VStack(spacing: 14) {
                        Text("A home for your tackle")
                            .tbFont(36, .heavy, style: .largeTitle, max: 50)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Swoosh().fill(Color(hex: 0x3BE3F0)).frame(width: 150, height: 14)
                        Text("Keep track of your gear, its condition and where it belongs.")
                            .tbFont(17, .medium)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        PageDots(page: 0, light: true).padding(.top, 10)
                        Button(action: next) { ButtonLabel(title: "Next", chevron: true) }
                            .buttonStyle(GoldButtonStyle(height: 52))
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, safeBottom + 24)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Page 2 — Out and Back

    private var pageTwo: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Image("tb_onboarding_return")
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height * 0.68, alignment: .top)
                    .clipped()
                    .accessibilityHidden(true)
                HStack {
                    Spacer()
                    TackleBayLogo(height: 46)
                }
                .padding(.horizontal, 16)
                .padding(.top, safeTop + 4)
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 14) {
                        Text("Pack it. Bring it back.")
                            .tbFont(28, .heavy, style: .largeTitle, max: 42)
                            .foregroundColor(.tbText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Build your kits, check what you take and record what returns.")
                            .tbFont(16, .medium)
                            .foregroundColor(.tbText.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        PageDots(page: 1, light: false).padding(.vertical, 8)
                        Button(action: next) { ButtonLabel(title: "Next", chevron: true) }
                            .buttonStyle(GoldButtonStyle(height: 52))
                        HStack {
                            Button(action: back) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                                    Text("Back").tbFont(19, .semibold)
                                }
                                .frame(minHeight: 44)
                            }
                            Spacer()
                            Button("Skip", action: finish).tbFont(19, .semibold).frame(minHeight: 44)
                        }
                        .foregroundColor(Color(hex: 0x1366C9))
                        .buttonStyle(PressableStyle())
                        .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 46)
                    .padding(.bottom, safeBottom + 14)
                    .frame(maxWidth: .infinity)
                    .background(WavePanel().fill(Color(hex: 0xF2FAFD)).shadow(color: Color.black.opacity(0.08), radius: 10, y: -4))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Page 3 — A Little Bay Bonus

    private var pageThree: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Image("tb_onboarding_showcase")
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height * 0.68, alignment: .top)
                    .clipped()
                    .accessibilityHidden(true)
                HStack {
                    Spacer()
                    TackleBayLogo(height: 46)
                }
                .padding(.horizontal, 16)
                .padding(.top, safeTop + 4)
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("Build your little corner of the bay")
                            .tbFont(30, .heavy, style: .largeTitle, max: 44)
                            .foregroundColor(.tbText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Swoosh().fill(Color(hex: 0x2BD0E4)).frame(width: 150, height: 14)
                        Text("Claim free tickets and collect decorative miniatures.")
                            .tbFont(16, .medium)
                            .foregroundColor(.tbText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Virtual rewards only. No purchases or cash prizes.")
                            .tbFont(13, .regular)
                            .foregroundColor(.tbSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 6) {
                            PageDots(page: 2, light: false)
                            Text("3 of 3").tbFont(16, .medium).foregroundColor(.tbSecondary)
                        }
                        .padding(.vertical, 6)
                        HStack(spacing: 12) {
                            Button(action: back) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold))
                                    Text("Back").tbFont(18, .semibold)
                                }
                                .foregroundColor(.tbText)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .background(Capsule().fill(Color.tbIceTile))
                            }
                            .buttonStyle(PressableStyle())
                            Button(action: finish) { ButtonLabel(title: "Get started", chevron: true) }
                                .buttonStyle(GoldButtonStyle(height: 52))
                            Button("Skip", action: finish)
                                .tbFont(18, .semibold)
                                .foregroundColor(Color(hex: 0x1366C9))
                                .frame(minWidth: 44, minHeight: 44)
                                .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 44)
                    .padding(.bottom, safeBottom + 14)
                    .frame(maxWidth: .infinity)
                    .background(WavePanel().fill(Color(hex: 0xF2FAFD)).shadow(color: Color.black.opacity(0.08), radius: 10, y: -4))
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct PageDots: View {
    let page: Int
    let light: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == page ? Color(hex: light ? 0x37E2F0 : 0x15B4C6) : (light ? Color.white.opacity(0.45) : Color(hex: 0xBFE4EE)))
                    .frame(width: 11, height: 11)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(page + 1) of 3")
    }
}

/// Light panel with a soft wave on its top edge (onboarding pages 2–3).
struct WavePanel: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = rect.minY + 34
        p.move(to: CGPoint(x: rect.minX, y: top))
        p.addCurve(to: CGPoint(x: rect.maxX, y: top - 6),
                   control1: CGPoint(x: rect.width * 0.32, y: top - 46),
                   control2: CGPoint(x: rect.width * 0.62, y: top + 34))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 200))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + 200))
        p.closeSubpath()
        return p
    }
}
