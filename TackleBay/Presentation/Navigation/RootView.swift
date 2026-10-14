import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.tbBackground.ignoresSafeArea()
                switch store.loadState {
                case .loading:
                    LaunchView()
                case .failed(let message):
                    LoadErrorView(message: message)
                case .ready:
                    if store.db.settings.onboardingCompleted {
                        MainTabsView()
                    } else {
                        OnboardingView(isReplay: false)
                            .transition(.opacity)
                    }
                }
                if ui.replayingOnboarding {
                    OnboardingView(isReplay: true)
                        .transition(.opacity)
                        .zIndex(5)
                }
                SheetHost().zIndex(10)
                ToastView().zIndex(11)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.safeTop, geo.safeAreaInsets.top)
            .environment(\.safeBottom, geo.safeAreaInsets.bottom)
        }
        .alert(ui.alert?.title ?? "", isPresented: Binding(get: { ui.alert != nil }, set: { if !$0 { ui.alert = nil } }),
               presenting: ui.alert) { item in
            ForEach(item.actions) { action in
                Button(action.title, role: action.role) { action.action() }
            }
        } message: { item in
            if let message = item.message { Text(message) }
        }
        .onAppear { router.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { router.reduceMotion = $0 }
        .onChange(of: router.topRoute) { route in
            if route == .bonus { services.audio.bonusSceneAppeared() } else { services.audio.bonusSceneDisappeared() }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: services.audio.appBecameActive()
            default: services.audio.appWillResignActive()
            }
        }
        .onChange(of: store.db.settings.onboardingCompleted) { done in
            if !done { router.resetAll() }
        }
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            Image("tb_bay_header").resizable().scaledToFill().ignoresSafeArea().accessibilityHidden(true)
            TackleBayLogo(height: 80)
        }
    }
}

/// A read failure is not an empty database: offer Retry or a restore instead of silently starting over.
struct LoadErrorView: View {
    let message: String
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var backup: BackupService
    @EnvironmentObject private var ui: AppUI
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TackleBayLogo(height: 64).padding(.top, 40)
                Image.symbol("externaldrive.badge.exclamationmark", fallback: "exclamationmark.triangle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundColor(.tbError)
                    .padding(.top, 10)
                Text("Your data couldn't be opened")
                    .tbFont(28, .heavy).foregroundColor(.tbText).multilineTextAlignment(.center)
                Text("Nothing was deleted. \(message)")
                    .tbFont(17).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
                Button { store.load() } label: { ButtonLabel(title: "Retry", icon: "arrow.clockwise") }
                    .buttonStyle(GoldButtonStyle())
                if backup.previousCopyDate != nil && store.canReplaceDatabase {
                    Button { restorePrevious() } label: { ButtonLabel(title: "Restore previous data", icon: "clock.arrow.circlepath") }
                        .buttonStyle(OutlineButtonStyle())
                }
                if store.canReplaceDatabase {
                    Button { importing = true } label: { ButtonLabel(title: "Restore from backup", icon: "square.and.arrow.down") }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(24)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task {
                do {
                    let candidate = try await backup.readCandidate(from: url)
                    try await backup.apply(candidate)
                } catch { ui.show(error, title: "Couldn't restore") }
            }
        }
    }

    private func restorePrevious() {
        Task {
            do {
                let candidate = try await backup.readPreviousCandidate()
                try await backup.apply(candidate)
            } catch { ui.show(error, title: "Couldn't restore") }
        }
    }
}

struct MainTabsView: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                NavStack(tab: tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(router.tab == tab ? 1 : 0)
                    .allowsHitTesting(router.tab == tab)
                    .accessibilityHidden(router.tab != tab)
            }
        }
    }
}

/// Custom per-tab stack (iOS 15 compatible). Covered screens stay alive so forms keep their state.
struct NavStack: View {
    let tab: AppTab
    @EnvironmentObject private var router: Router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let entries = router.entries(tab)
        ZStack {
            rootView
                .safeAreaInset(edge: .bottom, spacing: 0) { TBTabBar() }
                .zIndex(0)
                .allowsHitTesting(entries.isEmpty)
                .accessibilityHidden(!entries.isEmpty)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let isTop = index == entries.count - 1
                RouteView(route: entry.route)
                    .background(Color.tbBackground.ignoresSafeArea())
                    .modifier(SwipeBackModifier(enabled: isTop && entry.route.allowsSwipeBack) { router.pop(animated: false) })
                    .zIndex(Double(index + 1))
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .allowsHitTesting(isTop)
                    .accessibilityHidden(!isTop)
            }
        }
    }

    @ViewBuilder private var rootView: some View {
        switch tab {
        case .home: HomeView()
        case .gear: GearLibraryView()
        case .trips: TripsView()
        case .kits: KitsView()
        }
    }
}

struct SwipeBackModifier: ViewModifier {
    let enabled: Bool
    let onBack: () -> Void
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .overlay(alignment: .leading) {
                if enabled {
                    Color.clear
                        .frame(width: 22)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                                .onChanged { offset = max(0, $0.translation.width) }
                                .onEnded { value in
                                    let width = UIScreen.main.bounds.width
                                    if value.translation.width > width * 0.3 || value.predictedEndTranslation.width > width * 0.6 {
                                        withAnimation(.easeOut(duration: 0.18)) { offset = width }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                            onBack()
                                            offset = 0
                                        }
                                    } else {
                                        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                                    }
                                }
                        )
                }
            }
    }
}

struct TBTabBar: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var services: AppServices

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = router.tab == tab
                Button {
                    if router.tab != tab { services.haptics.selection() }
                    router.select(tab)
                } label: {
                    VStack(spacing: 3) {
                        tabIcon(tab)
                            .frame(height: 24)
                        Text(tab.title)
                            .tbFont(13, selected ? .bold : .medium, max: 18)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Capsule()
                            .fill(selected ? Color.tbTabActive : Color.clear)
                            .frame(width: 40, height: 3)
                    }
                    .foregroundColor(selected ? .tbTabActive : .tbTabIdle)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color(hex: 0x0B4F6C).opacity(0.1), radius: 12, y: -3)
                .padding(.bottom, -60)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder private func tabIcon(_ tab: AppTab) -> some View {
        switch tab {
        case .kits:
            Image.symbol("case.fill", fallback: "briefcase.fill")
                .font(.system(size: 20, weight: .semibold))
        case .trips:
            Image(systemName: "calendar")
                .font(.system(size: 21, weight: .semibold))
        default:
            Image(systemName: tab.icon).font(.system(size: 20, weight: .semibold))
        }
    }
}
